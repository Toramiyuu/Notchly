import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DroppedItem: Identifiable, Codable {
    let id: UUID
    let urlString: String?
    let text: String?

    var url: URL? { urlString.flatMap { URL(string: $0) } }
    var icon: NSImage? { url.flatMap { NSWorkspace.shared.icon(forFile: $0.path) } }
    var displayName: String {
        url?.lastPathComponent ?? String((text ?? "Text").prefix(20))
    }

    init(url: URL?, text: String?) {
        self.id = UUID()
        self.urlString = url?.absoluteString
        self.text = text
    }
}

class DropAreaStore: ObservableObject {
    static let shared = DropAreaStore()
    @Published var items: [DroppedItem] = []

    private let savePath: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Notchly", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        savePath = dir.appendingPathComponent("droparea.json")
        load()
    }

    func add(_ item: DroppedItem) {
        if items.count >= DropAreaSettings.shared.maxItems { items.removeFirst() }
        items.append(item)
        save()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: savePath, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: savePath),
              let saved = try? JSONDecoder().decode([DroppedItem].self, from: data) else { return }
        items = saved
    }
}

struct DropAreaView: View {

    @ObservedObject private var store = DropAreaStore.shared
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 8) {
            if !store.items.isEmpty {
                ShelfTrayView(items: store.items)
            }
            dropTarget
        }
        .frame(maxWidth: .infinity)
    }

    private var dropTarget: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(
                isTargeted ? Color.white.opacity(0.6) : Color.white.opacity(0.2),
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 3])
            )
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isTargeted ? Color.white.opacity(0.1) : Color.clear)
            )
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.4))
                    Text(store.items.isEmpty ? "Drop files here" : "Drop more")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(minHeight: store.items.isEmpty ? 70 : 44)
            .onDrop(of: [UTType.fileURL, UTType.url, UTType.plainText], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
                return true
            }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    let url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else {
                        url = item as? URL
                    }
                    if let url {
                        DispatchQueue.main.async {
                            DropAreaStore.shared.add(DroppedItem(url: url, text: nil))
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                    let url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else {
                        url = item as? URL
                    }
                    if let url {
                        DispatchQueue.main.async {
                            DropAreaStore.shared.add(DroppedItem(url: url, text: nil))
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                    if let text = item as? String {
                        DispatchQueue.main.async {
                            DropAreaStore.shared.add(DroppedItem(url: nil, text: text))
                        }
                    }
                }
            }
        }
    }
}
