import SwiftUI

struct BookmarksView: View {

    @ObservedObject private var manager = BookmarksManager.shared

    var body: some View {
        if manager.items.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 10)], spacing: 10) {
                    ForEach(manager.items) { item in
                        BookmarkButton(item: item)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bookmark.slash")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.3))
            Text("No bookmarks yet")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.3))
            Text("Add some in Settings → Bookmarks")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.2))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

private struct BookmarkButton: View {
    let item: BookmarkItem
    @State private var favicon: NSImage? = nil
    @State private var isHovered = false

    var body: some View {
        Button {
            BookmarksManager.shared.open(item)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(isHovered ? 0.15 : 0.08))
                    if let favicon {
                        Image(nsImage: favicon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(width: 52, height: 52)

                Text(item.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 80)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .onAppear {
            DispatchQueue.global(qos: .utility).async {
                let img = item.favicon
                DispatchQueue.main.async { favicon = img }
            }
        }
    }
}
