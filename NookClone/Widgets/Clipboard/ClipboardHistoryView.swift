import SwiftUI

struct ClipboardHistoryView: View {

    @ObservedObject private var manager = ClipboardManager.shared
    @State private var pastedID: UUID? = nil

    var body: some View {
        if manager.items.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(manager.items) { item in
                        ClipboardItemRow(item: item, pastedID: $pastedID) {
                            manager.pasteItem(item)
                            withAnimation { pastedID = item.id }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                if pastedID == item.id { pastedID = nil }
                            }
                        } onDelete: {
                            withAnimation { manager.remove(item) }
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "clipboard")
                .foregroundStyle(.white.opacity(0.3))
            Text("Nothing copied yet")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

private struct ClipboardItemRow: View {
    let item: ClipboardItem
    @Binding var pastedID: UUID?
    let onPaste: () -> Void
    let onDelete: () -> Void

    private var isPasted: Bool { pastedID == item.id }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPaste) {
                HStack(spacing: 6) {
                    Image(systemName: isPasted ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(isPasted ? .green : .white.opacity(0.4))
                        .frame(width: 14)

                    rowContent

                    Text(item.date, style: .time)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.white.opacity(isPasted ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        switch item.kind {
        case .text(let s):
            Text(s)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .image:
            if let data = item.imageData, let nsImage = NSImage(data: data) {
                HStack(spacing: 6) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 32, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    Text("Image")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
