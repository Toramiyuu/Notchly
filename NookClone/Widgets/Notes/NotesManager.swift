import AppKit
import Combine

/// Loads and saves rich text note content to Application Support.
class NotesManager: ObservableObject {

    static let shared = NotesManager()

    @Published var noteContent: NSAttributedString

    private let notePath: URL
    private var saveTask: DispatchWorkItem?

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("Notchly", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        notePath = dir.appendingPathComponent("note.rtf")

        if let data = try? Data(contentsOf: notePath),
           let attr = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            noteContent = attr
        } else {
            noteContent = NSAttributedString()
        }
    }

    func save(_ content: NSAttributedString) {
        noteContent = content
        saveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.writeToDisk(content)
        }
        saveTask = task
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    private func writeToDisk(_ content: NSAttributedString) {
        guard content.length > 0 else {
            try? FileManager.default.removeItem(at: notePath)
            return
        }
        let range = NSRange(location: 0, length: content.length)
        guard let data = try? content.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) else { return }
        try? data.write(to: notePath, options: .atomic)
    }
}
