import Foundation
import AppKit

struct BookmarkItem: Identifiable, Codable {
    let id: UUID
    var name: String
    var urlString: String

    init(name: String, urlString: String) {
        self.id = UUID()
        self.name = name
        self.urlString = urlString
    }

    var url: URL? { URL(string: urlString) }

    var favicon: NSImage? {
        guard let url, let host = url.host else { return nil }
        let faviconURL = URL(string: "https://www.google.com/s2/favicons?sz=64&domain=\(host)")!
        if let data = try? Data(contentsOf: faviconURL) {
            return NSImage(data: data)
        }
        return nil
    }
}

class BookmarksManager: ObservableObject {

    static let shared = BookmarksManager()

    @Published var items: [BookmarkItem] = []

    private let savePath: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Notchly", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        savePath = dir.appendingPathComponent("bookmarks.json")
        load()
    }

    func open(_ item: BookmarkItem) {
        guard let url = item.url else { return }
        NSWorkspace.shared.open(url)
    }

    func add(name: String, urlString: String) {
        var normalized = urlString.trimmingCharacters(in: .whitespaces)
        if !normalized.hasPrefix("http://") && !normalized.hasPrefix("https://") {
            normalized = "https://" + normalized
        }
        items.append(BookmarkItem(name: name, urlString: normalized))
        save()
    }

    func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func update(_ item: BookmarkItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i] = item
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: savePath, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: savePath),
              let saved = try? JSONDecoder().decode([BookmarkItem].self, from: data) else { return }
        items = saved
    }
}
