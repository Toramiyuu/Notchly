import AppKit
import SwiftUI

/// Multi-pane settings window controller.
class SettingsWindowController: NSWindowController {

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Notchly Settings"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsRootView())
        self.init(window: window)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Settings Root View

struct SettingsRootView: View {

    enum Pane: String, CaseIterable, Identifiable {
        case general    = "General"
        case widgets    = "Widgets"
        case media      = "Media"
        case calendar   = "Calendar"
        case dropArea   = "Drop Area"
        case notes      = "Notes"
        case hud        = "HUD"
        case quickApps  = "Quick Apps"
        case clipboard  = "Clipboard"
        case sysMonitor = "System"
        case weather    = "Weather"
        case todo       = "Todo"
        case shortcuts  = "Shortcuts"
        case mirror     = "Mirror"
        case bluetooth  = "Bluetooth"
        case about      = "About"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general:    return "gear"
            case .widgets:    return "square.grid.2x2"
            case .media:      return "music.note"
            case .calendar:   return "calendar"
            case .dropArea:   return "tray.and.arrow.down"
            case .notes:      return "note.text"
            case .hud:        return "speaker.wave.2"
            case .quickApps:  return "square.grid.2x2"
            case .clipboard:  return "clipboard"
            case .sysMonitor: return "gauge.with.dots.needle.bottom.50percent"
            case .weather:    return "cloud.sun.fill"
            case .todo:       return "checklist"
            case .shortcuts:  return "arrow.trianglehead.2.clockwise"
            case .mirror:     return "camera.metering.center.weighted"
            case .bluetooth:  return "bluetooth"
            case .about:      return "info.circle"
            }
        }
    }

    @State private var selection: Pane = .general

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $selection) { pane in
                Label(pane.rawValue, systemImage: pane.icon)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            Group {
                switch selection {
                case .general:    GeneralSettingsPane()
                case .widgets:    ReorderWidgetsView()
                case .media:      MediaWidgetSettingsView()
                case .calendar:   CalendarWidgetSettingsView()
                case .dropArea:   DropAreaSettingsView()
                case .notes:      NotesWidgetSettingsView()
                case .hud:        HUDSettingsView()
                case .quickApps:  QuickAppsSettingsView()
                case .clipboard:  ClipboardSettingsView()
                case .sysMonitor: SystemMonitorSettingsView()
                case .weather:    WeatherSettingsView()
                case .todo:       TodoSettingsView()
                case .shortcuts:  ShortcutsSettingsView()
                case .mirror:     MirrorSettingsView()
                case .bluetooth:  BluetoothSettingsView()
                case .about:      AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}

// MARK: - General Pane

struct GeneralSettingsPane: View {
    @ObservedObject private var settings = GeneralSettings.shared

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Expand on hover", isOn: $settings.openOnHover)
                Toggle("Toggle on click", isOn: $settings.openOnClick)
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Global hotkey (⌥N)", isOn: $settings.hotkeyEnabled)
            }
            Section("Notch Fine-Tune") {
                NotchFineTuneView()
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Widget Reorder

struct ReorderWidgetsView: View {
    @ObservedObject private var registry = WidgetRegistry.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Drag to reorder. Toggle to enable or disable.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            List {
                ForEach($registry.widgets) { $widget in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                        Image(systemName: widget.icon)
                            .frame(width: 20)
                        Text(widget.title)
                        Spacer()
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { widget.isEnabled },
                                set: { registry.setEnabled(widget.id, enabled: $0) }
                            )
                        )
                        .labelsHidden()
                    }
                }
                .onMove { from, to in registry.move(from: from, to: to) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }
}

// MARK: - View alias (SettingsView used in AppDelegate)
typealias SettingsView = SettingsRootView
