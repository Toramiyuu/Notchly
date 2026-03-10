import SwiftUI

/// Root SwiftUI view rendered inside the notch window.
struct NookPanelView: View {

    @State private var isExpanded = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                if isExpanded {
                    // Frosted glass panel
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        )
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
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.black)
            .frame(width: 162, height: 32)
            .frame(maxWidth: .infinity)
    }
}

extension Notification.Name {
    static let notchPanelExpandedChanged = Notification.Name("notchPanelExpandedChanged")
    static let notchPanelTapped          = Notification.Name("notchPanelTapped")
    static let notchPanelHeightChanged   = Notification.Name("notchPanelHeightChanged")
}
