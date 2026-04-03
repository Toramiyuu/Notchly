import SwiftUI

struct NewsView: View {

    @ObservedObject private var manager = NewsManager.shared
    @ObservedObject private var settings = NewsSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            // Source label + refresh button
            HStack {
                Text(settings.selectedSource.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)
                Spacer()
                Button {
                    manager.fetch()
                } label: {
                    Image(systemName: manager.isLoading ? "arrow.circlepath" : "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                        .rotationEffect(manager.isLoading ? .degrees(360) : .zero)
                        .animation(manager.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                                   value: manager.isLoading)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 6)

            if let error = manager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if manager.items.isEmpty && !manager.isLoading {
                Text("No articles loaded")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(manager.items) { item in
                            NewsRow(item: item)
                            if item.id != manager.items.last?.id {
                                Divider()
                                    .background(.white.opacity(0.08))
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct NewsRow: View {
    let item: NewsItem
    @State private var isHovered = false

    var body: some View {
        Button {
            if let url = item.link {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(isHovered ? 1.0 : 0.85))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let date = item.pubDate {
                        Text(date, style: .relative)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(isHovered ? 0.5 : 0.2))
                    .padding(.top, 2)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 6)
            .background(isHovered ? Color.white.opacity(0.06) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
