import SwiftUI

/// Scrolling marquee for track title + artist/album subtitle.
struct TrackInfoView: View {

    let title: String
    let artist: String
    let album: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            MarqueeText(text: title, font: .system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            Text(subtitleText)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var subtitleText: String {
        if artist.isEmpty { return album }
        if album.isEmpty { return artist }
        return "\(artist) — \(album)"
    }
}

/// A text view that scrolls horizontally when the text is too long.
struct MarqueeText: View {

    let text: String
    let font: Font
    @State private var containerWidth: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var needsScrolling: Bool { textWidth > containerWidth }
    private let speed: Double = 30 // points per second

    var body: some View {
        GeometryReader { geo in
            let cw = geo.size.width
            ZStack(alignment: .leading) {
                // Invisible text to measure width; .id(text) forces remount on track change
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize()
                    .id(text)
                    .background(
                        GeometryReader { inner in
                            Color.clear.onAppear {
                                containerWidth = cw
                                textWidth = inner.size.width
                                startAnimationIfNeeded()
                            }
                        }
                    )
                    .opacity(0)

                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize()
                    .offset(x: offset)
            }
            .clipped()
        }
        .frame(height: 18)  // Approximate line height for 13pt system font
    }

    private func startAnimationIfNeeded() {
        guard needsScrolling else { return }
        let scrollDistance = textWidth - containerWidth + 20
        let duration = scrollDistance / speed

        withAnimation(.linear(duration: 1.0)) { offset = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.linear(duration: duration)) {
                offset = -scrollDistance
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + duration + 0.5) {
            offset = 0
            startAnimationIfNeeded()
        }
    }
}
