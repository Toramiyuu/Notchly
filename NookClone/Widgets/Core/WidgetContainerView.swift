import SwiftUI

/// Renders enabled widgets as horizontal tabs inside the notch panel.
struct WidgetContainerView: View {

    @ObservedObject private var registry = WidgetRegistry.shared
    // Empty string = "no explicit selection, use first enabled widget"
    // @AppStorage does not support Optional<String> so we use "" as the sentinel
    @AppStorage("notchly.lastWidgetTab") private var selectedWidgetID: String = ""
    @Namespace private var tabNamespace
    @State private var slideForward = true

    var body: some View {
        let enabled = registry.enabledWidgets

        if enabled.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                if enabled.count > 1 {
                    tabBar(enabled)
                }
                widgetContent(enabled)
                    .frame(maxWidth: .infinity)
                    .clipped()
            }
        }
    }

    private func tabBar(_ widgets: [WidgetRegistry.WidgetEntry]) -> some View {
        HStack(spacing: 0) {
            ForEach(widgets) { widget in
                let selected = isSelected(widget, in: widgets)
                Button {
                    let currentIdx = widgets.firstIndex(where: { $0.id == selectedWidgetID }) ?? 0
                    let newIdx = widgets.firstIndex(where: { $0.id == widget.id }) ?? 0
                    slideForward = newIdx >= currentIdx
                    NotificationCenter.default.post(name: .notchPanelHeightChanged, object: widget.preferredHeight)
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        selectedWidgetID = widget.id
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: widget.icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(selected ? .white : .white.opacity(0.35))
                        Text(widget.title)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(selected ? .white.opacity(0.9) : .white.opacity(0.3))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.white.opacity(0.18))
                                .matchedGeometryEffect(id: "tabIndicator", in: tabNamespace)
                                .padding(.horizontal, 4)
                        }
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selected)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func widgetContent(_ widgets: [WidgetRegistry.WidgetEntry]) -> some View {
        // Resolve the active ID: stored value if it exists in enabled widgets, else first
        let activeID = (!selectedWidgetID.isEmpty && widgets.contains(where: { $0.id == selectedWidgetID }))
            ? selectedWidgetID
            : widgets.first?.id
        if let id = activeID, let widget = widgets.first(where: { $0.id == id }) {
            widget.makeBody()
                .id(id)
                .transition(.asymmetric(
                    insertion: .move(edge: slideForward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: slideForward ? .leading : .trailing).combined(with: .opacity)
                ))
                .onAppear {
                    NotificationCenter.default.post(
                        name: .notchPanelHeightChanged,
                        object: widget.preferredHeight
                    )
                }
        }
    }

    private func isSelected(_ widget: WidgetRegistry.WidgetEntry, in widgets: [WidgetRegistry.WidgetEntry]) -> Bool {
        if selectedWidgetID.isEmpty || !widgets.contains(where: { $0.id == selectedWidgetID }) {
            return widgets.first?.id == widget.id
        }
        return selectedWidgetID == widget.id
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.dashed")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.3))
            Text("No widgets enabled")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}
