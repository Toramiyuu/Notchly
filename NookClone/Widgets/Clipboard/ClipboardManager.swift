import AppKit
import Combine

struct ClipboardItem: Identifiable, Codable {
    let id: UUID
    let date: Date
    let kind: Kind

    enum Kind: Codable {
        case text(String)
        case image(String)   // filename in images directory
    }

    init(text: String)    { id = UUID(); date = Date(); kind = .text(text) }
    init(imageFilename: String) { id = UUID(); date = Date(); kind = .image(imageFilename) }

    var displayText: String? { guard case .text(let s) = kind else { return nil }; return s }

    /// Loads the image data from the images directory on disk.
    var imageData: Data? {
        guard case .image(let filename) = kind else { return nil }
        return try? Data(contentsOf: ClipboardManager.imagesDir.appendingPathComponent(filename))
    }
}

class ClipboardManager: ObservableObject {

    static let shared = ClipboardManager()

    /// Directory where clipboard image files are stored (separate from the JSON index).
    static let imagesDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Notchly/clipboard-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    @Published var items: [ClipboardItem] = []

    private var pollTimer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var isExpanded = false
    private let savePath: URL

    var maxItems: Int {
        get { UserDefaults.standard.integer(forKey: "clipboard.maxItems").nonZeroOr(20) }
        set { UserDefaults.standard.set(newValue, forKey: "clipboard.maxItems") }
    }

    var autoClearOnQuit: Bool {
        get { UserDefaults.standard.bool(forKey: "clipboard.autoClearOnQuit") }
        set { UserDefaults.standard.set(newValue, forKey: "clipboard.autoClearOnQuit") }
    }

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Notchly", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        savePath = dir.appendingPathComponent("clipboard.json")
        loadFromDisk()
        startPolling(interval: 2.0)
        observePanel()
        observeTermination()
    }

    deinit { pollTimer?.invalidate() }

    // MARK: - App termination

    private func observeTermination() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.autoClearOnQuit else { return }
            self.clear()
        }
    }

    // MARK: - Panel observation

    private func observePanel() {
        NotificationCenter.default.addObserver(forName: .notchPanelExpandedChanged, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            let expanded = (note.object as? Bool) ?? false
            self.isExpanded = expanded
            self.restartTimer()
        }
    }

    private func restartTimer() {
        pollTimer?.invalidate()
        startPolling(interval: isExpanded ? 0.5 : 2.0)
    }

    // MARK: - Polling

    private func startPolling(interval: TimeInterval) {
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        pollTimer?.tolerance = interval * 0.2
    }

    private func checkClipboard() {
        let count = NSPasteboard.general.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
            DispatchQueue.main.async { self.addItem(ClipboardItem(text: text)) }
        } else if let images = NSPasteboard.general.readObjects(forClasses: [NSImage.self]) as? [NSImage],
                  let first = images.first,
                  let tiff = first.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) {
            let filename = UUID().uuidString + ".png"
            let fileURL = Self.imagesDir.appendingPathComponent(filename)
            try? png.write(to: fileURL, options: .atomic)
            DispatchQueue.main.async { self.addItem(ClipboardItem(imageFilename: filename)) }
        }
    }

    // MARK: - Management

    func addItem(_ item: ClipboardItem) {
        // Don't duplicate consecutive identical text items
        if case .text(let new) = item.kind,
           case .text(let existing) = items.first?.kind,
           new == existing { return }
        items.insert(item, at: 0)
        // Remove evicted items and delete their image files
        while items.count > maxItems {
            let evicted = items.removeLast()
            if case .image(let filename) = evicted.kind {
                try? FileManager.default.removeItem(at: Self.imagesDir.appendingPathComponent(filename))
            }
        }
        saveToDisk()
    }

    func copyItem(_ item: ClipboardItem) {
        NSPasteboard.general.clearContents()
        switch item.kind {
        case .text(let s):
            NSPasteboard.general.setString(s, forType: .string)
        case .image(let filename):
            let fileURL = Self.imagesDir.appendingPathComponent(filename)
            if let data = try? Data(contentsOf: fileURL), let image = NSImage(data: data) {
                NSPasteboard.general.writeObjects([image])
            }
        }
        lastChangeCount = NSPasteboard.general.changeCount
    }

    /// Copy item to pasteboard, collapse the panel, then paste into the previously active app.
    func pasteItem(_ item: ClipboardItem) {
        copyItem(item)
        NotificationCenter.default.post(name: .notchPanelCollapseRequested, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            ActiveAppTracker.shared.pasteIntoPreviousApp()
        }
    }

    func remove(_ item: ClipboardItem) {
        if case .image(let filename) = item.kind {
            try? FileManager.default.removeItem(at: Self.imagesDir.appendingPathComponent(filename))
        }
        items.removeAll { $0.id == item.id }
        saveToDisk()
    }

    func clear() {
        for item in items {
            if case .image(let filename) = item.kind {
                try? FileManager.default.removeItem(at: Self.imagesDir.appendingPathComponent(filename))
            }
        }
        items.removeAll()
        try? FileManager.default.removeItem(at: savePath)
    }

    // MARK: - Persistence

    private func saveToDisk() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: savePath, options: .atomic)
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: savePath) else { return }
        if let saved = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            items = saved
        } else {
            // Migrate from old schemas (text-only or inline image data)
            // Drop image items from old format — they stored raw Data which
            // is incompatible with the new filename-based format. Text items
            // are preserved.
            struct LegacyItem: Decodable {
                let id: UUID; let date: Date; let kind: LegacyKind
                enum LegacyKind: Decodable { case text(String); case image(Data) }
            }
            if let old = try? JSONDecoder().decode([LegacyItem].self, from: data) {
                items = old.compactMap { item in
                    guard case .text(let s) = item.kind else { return nil }
                    return ClipboardItem(text: s)
                }
                saveToDisk()
            }
        }
    }
}

private extension Int {
    func nonZeroOr(_ fallback: Int) -> Int { self > 0 ? self : fallback }
}
