import Foundation

struct TodoItem: Identifiable, Codable {
    let id: UUID
    var text: String
    var isDone: Bool
    let createdAt: Date

    init(text: String) {
        id = UUID()
        self.text = text
        isDone = false
        createdAt = Date()
    }
}

class TodoManager: ObservableObject {

    static let shared = TodoManager()

    @Published var items: [TodoItem] = []

    private let savePath: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Notchly", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        savePath = dir.appendingPathComponent("todos.json")
        load()
    }

    func add(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        items.insert(TodoItem(text: t), at: 0)
        save()
    }

    func toggle(_ item: TodoItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].isDone.toggle()
        save()
    }

    func delete(_ item: TodoItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clearDone() {
        items.removeAll { $0.isDone }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: savePath, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: savePath),
              let saved = try? JSONDecoder().decode([TodoItem].self, from: data) else { return }
        items = saved
    }
}
