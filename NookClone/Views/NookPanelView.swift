import SwiftUI

/// Root SwiftUI view rendered inside the notch window.
struct NookPanelView: View {

    @State private var isExpanded = false
    @ObservedObject private var media = MediaManager.shared

    private var showLiveNotch: Bool { media.currentTrack != nil && !isExpanded }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                if isExpanded {
                    // Flat top so panel flows directly out of the notch; rounded bottom corners only
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0, bottomLeadingRadius: 20,
                        bottomTrailingRadius: 20, topTrailingRadius: 0,
                        style: .continuous
                    )
                    .fill(.black)
                    .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                }

                VStack(spacing: 0) {
                    // Notch pill — tapping toggles pin
                    notchPill
                        .onTapGesture {
                            NotificationCenter.default.post(name: .notchPanelTapped, object: nil)
                        }

                    if isExpanded {
                        WidgetContainerView()
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                            .padding(.bottom, 14)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: isExpanded)
        .onReceive(NotificationCenter.default.publisher(for: .notchPanelExpandedChanged)) { note in
            if let expanded = note.object as? Bool {
                isExpanded = expanded
            }
        }
    }

    private var notchPill: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.black)
            if let track = media.currentTrack, !isExpanded {
                liveNotchContent(track: track)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showLiveNotch)
        .frame(width: 162, height: 32)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func liveNotchContent(track: TrackInfo) -> some View {
        HStack(spacing: 0) {
            AlbumCoverView(artwork: track.artwork, size: 20)
                .padding(.leading, 10)
            Spacer(minLength: 6)
            Text(track.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 80)
            Spacer(minLength: 6)
            NotchMiniSpectrograph(isPlaying: track.isPlaying)
                .padding(.trailing, 10)
        }
    }
}

private struct NotchMiniSpectrograph: View {
    let isPlaying: Bool
    private let barCount    = 5
    private let barWidth:   CGFloat = 2.5
    private let barSpacing: CGFloat = 2.0
    private let maxHeight:  CGFloat = 14.0
    private let minHeight:  CGFloat = 2.0

    var body: some View {
        if isPlaying {
            TimelineView(.animation) { context in
                barsView(phase: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            idleBarsView
        }
    }

    private func barsView(phase: Double) -> some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(barColor(for: i, playing: true))
                    .frame(width: barWidth, height: barHeight(for: i, phase: phase))
            }
        }
    }

    private var idleBarsView: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(barColor(for: i, playing: false))
                    .frame(width: barWidth, height: minHeight + 1)
            }
        }
    }

    private func barHeight(for index: Int, phase: Double) -> CGFloat {
        let offset     = Double(index) * 0.7
        let speed      = 2.2 + Double(index) * 0.35
        let normalized = (sin(phase * speed + offset) + 1.0) / 2.0
        return minHeight + normalized * (maxHeight - minHeight)
    }

    private func barColor(for index: Int, playing: Bool) -> Color {
        guard playing else { return .white.opacity(0.25) }
        let opacities: [Double] = [0.55, 0.75, 0.90, 0.75, 0.55]
        return .white.opacity(opacities[index])
    }
}

extension Notification.Name {
    static let notchPanelExpandedChanged = Notification.Name("notchPanelExpandedChanged")
    static let notchPanelTapped          = Notification.Name("notchPanelTapped")
    static let notchPanelHeightChanged   = Notification.Name("notchPanelHeightChanged")
}
