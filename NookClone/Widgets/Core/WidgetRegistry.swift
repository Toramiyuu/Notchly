import SwiftUI
import Combine

/// Manages the ordered list of available widgets and their enabled state.
class WidgetRegistry: ObservableObject {

    static let shared = WidgetRegistry()

    @Published var widgets: [WidgetEntry] = []

    private let orderKey = "notchly.widgetOrder"
    private let enabledKey = "notchly.widgetEnabled"

    struct WidgetEntry: Identifiable {
        let id: String
        let title: String
        let icon: String
        var isEnabled: Bool
        /// Total panel content height (tab bar + widget body + padding) in points.
        let preferredHeight: CGFloat
        // View builders stored as closures to avoid constructing views outside SwiftUI
        let makeBody: () -> AnyView
        let makeSettingsView: () -> AnyView
    }

    private init() {
        buildDefaultWidgets()
        loadPersistedState()
    }

    private func buildDefaultWidgets() {
        widgets = [
            WidgetEntry(
                id: "media",
                title: "Media",
                icon: "music.note",
                isEnabled: true,
                preferredHeight: 200,
                makeBody: { AnyView(MediaWidgetView()) },
                makeSettingsView: { AnyView(MediaWidgetSettingsView()) }
            ),
            WidgetEntry(
                id: "calendar",
                title: "Calendar",
                icon: "calendar",
                isEnabled: true,
                preferredHeight: 230,
                makeBody: { AnyView(CalendarDayView()) },
                makeSettingsView: { AnyView(CalendarWidgetSettingsView()) }
            ),
            WidgetEntry(
                id: "droparea",
                title: "Drop Area",
                icon: "tray.and.arrow.down",
                isEnabled: false,
                preferredHeight: 200,
                makeBody: { AnyView(DropAreaView()) },
                makeSettingsView: { AnyView(DropAreaSettingsView()) }
            ),
            WidgetEntry(
                id: "notes",
                title: "Notes",
                icon: "note.text",
                isEnabled: false,
                preferredHeight: 260,
                makeBody: { AnyView(NotesView()) },
                makeSettingsView: { AnyView(NotesWidgetSettingsView()) }
            ),
            WidgetEntry(
                id: "hud",
                title: "HUD",
                icon: "speaker.wave.2",
                isEnabled: false,
                preferredHeight: 140,
                makeBody: { AnyView(HUDWidgetView()) },
                makeSettingsView: { AnyView(HUDSettingsView()) }
            ),
            WidgetEntry(
                id: "quickapps",
                title: "Quick Apps",
                icon: "square.grid.2x2",
                isEnabled: false,
                preferredHeight: 140,
                makeBody: { AnyView(QuickAppsView()) },
                makeSettingsView: { AnyView(QuickAppsSettingsView()) }
            ),
            WidgetEntry(
                id: "clipboard",
                title: "Clipboard",
                icon: "clipboard",
                isEnabled: true,
                preferredHeight: 230,
                makeBody: { AnyView(ClipboardHistoryView()) },
                makeSettingsView: { AnyView(ClipboardSettingsView()) }
            ),
            WidgetEntry(
                id: "sysmonitor",
                title: "System",
                icon: "gauge.with.dots.needle.bottom.50percent",
                isEnabled: false,
                preferredHeight: 150,
                makeBody: { AnyView(SystemMonitorView()) },
                makeSettingsView: { AnyView(SystemMonitorSettingsView()) }
            ),
            WidgetEntry(
                id: "weather",
                title: "Weather",
                icon: "cloud.sun.fill",
                isEnabled: true,
                preferredHeight: 200,
                makeBody: { AnyView(WeatherView()) },
                makeSettingsView: { AnyView(WeatherSettingsView()) }
            ),
            WidgetEntry(
                id: "todo",
                title: "Todo",
                icon: "checklist",
                isEnabled: false,
                preferredHeight: 200,
                makeBody: { AnyView(TodoView()) },
                makeSettingsView: { AnyView(TodoSettingsView()) }
            ),
            WidgetEntry(
                id: "shortcuts",
                title: "Shortcuts",
                icon: "arrow.trianglehead.2.clockwise",
                isEnabled: false,
                preferredHeight: 140,
                makeBody: { AnyView(ShortcutsView()) },
                makeSettingsView: { AnyView(ShortcutsSettingsView()) }
            ),
            WidgetEntry(
                id: "mirror",
                title: "Mirror",
                icon: "camera.metering.center.weighted",
                isEnabled: false,
                preferredHeight: 190,
                makeBody: { AnyView(MirrorView()) },
                makeSettingsView: { AnyView(MirrorSettingsView()) }
            ),
            WidgetEntry(
                id: "bluetooth",
                title: "Bluetooth",
                icon: "bluetooth",
                isEnabled: false,
                preferredHeight: 190,
                makeBody: { AnyView(BluetoothView()) },
                makeSettingsView: { AnyView(BluetoothSettingsView()) }
            ),
            WidgetEntry(
                id: "bookmarks",
                title: "Bookmarks",
                icon: "bookmark.fill",
                isEnabled: false,
                preferredHeight: 200,
                makeBody: { AnyView(BookmarksView()) },
                makeSettingsView: { AnyView(BookmarksSettingsView()) }
            ),
            WidgetEntry(
                id: "news",
                title: "News",
                icon: "newspaper.fill",
                isEnabled: false,
                preferredHeight: 260,
                makeBody: { AnyView(NewsView()) },
                makeSettingsView: { AnyView(NewsSettingsView()) }
            ),
        ]
    }

    // MARK: - Persistence

    private func loadPersistedState() {
        let defaults = UserDefaults.standard

        if let enabledDict = defaults.dictionary(forKey: enabledKey) as? [String: Bool] {
            for i in widgets.indices {
                if let enabled = enabledDict[widgets[i].id] {
                    widgets[i].isEnabled = enabled
                }
            }
        }

        if let order = defaults.array(forKey: orderKey) as? [String] {
            let ordered = order.compactMap { id in widgets.first(where: { $0.id == id }) }
            let missing = widgets.filter { w in !order.contains(w.id) }
            widgets = ordered + missing
        }
    }

    func saveState() {
        let defaults = UserDefaults.standard
        defaults.set(widgets.map(\.id), forKey: orderKey)
        defaults.set(
            Dictionary(uniqueKeysWithValues: widgets.map { ($0.id, $0.isEnabled) }),
            forKey: enabledKey
        )
    }

    var enabledWidgets: [WidgetEntry] {
        widgets.filter(\.isEnabled)
    }

    func setEnabled(_ id: String, enabled: Bool) {
        guard let idx = widgets.firstIndex(where: { $0.id == id }) else { return }
        widgets[idx].isEnabled = enabled
        saveState()
    }

    func move(from source: IndexSet, to destination: Int) {
        widgets.move(fromOffsets: source, toOffset: destination)
        saveState()
    }
}
