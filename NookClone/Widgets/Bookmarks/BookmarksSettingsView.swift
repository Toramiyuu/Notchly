import SwiftUI

struct BookmarksSettingsView: View {

    @ObservedObject private var manager = BookmarksManager.shared
    @State private var newName = ""
    @State private var newURL = ""
    @State private var editingItem: BookmarkItem? = nil

    var body: some View {
        Form {
            Section("Add Bookmark") {
                TextField("Name", text: $newName)
                TextField("URL (e.g. github.com)", text: $newURL)
                Button("Add") {
                    guard !newName.trimmingCharacters(in: .whitespaces).isEmpty,
                          !newURL.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    manager.add(name: newName.trimmingCharacters(in: .whitespaces),
                                urlString: newURL.trimmingCharacters(in: .whitespaces))
                    newName = ""
                    newURL = ""
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty ||
                          newURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !manager.items.isEmpty {
                Section("Bookmarks") {
                    List {
                        ForEach(manager.items) { item in
                            HStack {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(.secondary)
                                Image(systemName: "globe")
                                    .frame(width: 16)
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.body)
                                    Text(item.urlString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .onDelete { manager.remove(at: $0) }
                        .onMove { manager.move(from: $0, to: $1) }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                    .frame(minHeight: 120)
                }
            }
        }
        .formStyle(.grouped)
    }
}
