import SwiftUI

/// In-panel settings overlay — widget enable/disable list accessible via the gear button.
struct PanelSettingsView: View {

    @ObservedObject private var registry = WidgetRegistry.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Widgets")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.bottom, 8)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(registry.widgets) { widget in
                        widgetRow(widget)
                    }
                }
            }
        }
    }

    private func widgetRow(_ widget: WidgetRegistry.WidgetEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: widget.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
                .frame(width: 16, alignment: .center)

            Text(widget.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))

            Spacer()

            Toggle("", isOn: Binding(
                get: { widget.isEnabled },
                set: { registry.setEnabled(widget.id, enabled: $0) }
            ))
            .toggleStyle(.switch)
            .scaleEffect(0.7, anchor: .trailing)
            .tint(Color(red: 0.35, green: 0.78, blue: 1.0))
            .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.06))
        )
    }
}
