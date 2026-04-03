import Foundation

class ShortcutsManager: ObservableObject {

    static let shared = ShortcutsManager()

    @Published var available: [String] = []
    @Published var pinned: [String] {
        didSet { UserDefaults.standard.set(pinned, forKey: "shortcuts.pinned") }
    }
    @Published var runningName: String?

    private init() {
        pinned = UserDefaults.standard.stringArray(forKey: "shortcuts.pinned") ?? []
        fetchAvailable()
    }

    // MARK: - Fetch

    func fetchAvailable() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let output = Self.shell("/usr/bin/shortcuts", ["list"])
            let names = output
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            DispatchQueue.main.async { self?.available = names }
        }
    }

    // MARK: - Run

    func run(_ name: String) {
        guard runningName == nil else { return }
        runningName = name
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            proc.arguments = ["run", name]
            proc.standardOutput = Pipe()
            proc.standardError = Pipe()
            try? proc.run()

            // Time out after 30 seconds so a hung shortcut doesn't lock the UI forever
            let deadline = DispatchTime.now() + 30
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: deadline) {
                if proc.isRunning { proc.terminate() }
            }
            proc.waitUntilExit()
            DispatchQueue.main.async { self?.runningName = nil }
        }
    }

    // MARK: - Pin management

    func pin(_ name: String) {
        guard !pinned.contains(name) else { return }
        pinned.append(name)
    }

    func unpin(_ name: String) {
        pinned.removeAll { $0 == name }
    }

    func movePinned(from source: IndexSet, to destination: Int) {
        pinned.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Shell helper

    @discardableResult
    private static func shell(_ path: String, _ args: [String], timeout: TimeInterval = 10) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        // Terminate after timeout so a slow `shortcuts list` doesn't block the background thread
        let item = DispatchWorkItem { if proc.isRunning { proc.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: item)
        proc.waitUntilExit()
        item.cancel()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
