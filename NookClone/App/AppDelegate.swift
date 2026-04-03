import AppKit
import SwiftUI

@main
struct NotchlyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // MenuBarExtra provides the status bar item and menu (macOS 13+)
        MenuBarExtra("Notchly", systemImage: "rectangle.topthird.inset.filled") {
            Button("Settings...") {
                appDelegate.openSettings()
            }
            .keyboardShortcut(",")

            Button("About Notchly") {
                appDelegate.showAbout()
            }

            Divider()

            Button("Quit Notchly") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var notchWindowController: NotchWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var aboutWindow: NSWindow?
    private var fullscreenMonitor: FullscreenMonitor?
    private var globalHotkeyMonitor: Any?
    private var localHotkeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory mode: no dock icon, no menu bar (besides MenuBarExtra)
        NSApp.setActivationPolicy(.accessory)

        // Set up the notch panel window
        setupNotchWindow()

        // Monitor fullscreen applications
        fullscreenMonitor = FullscreenMonitor { [weak self] isFullscreen in
            self?.notchWindowController?.setHidden(isFullscreen)
        }

        // Start HUD key interception (also requests Accessibility permission)
        HUDInterceptor.shared.start()

        // Install global hotkey (Option+N) — requires Accessibility permission
        setupHotkey()

        // Eagerly initialize background singletons so they start polling at launch
        _ = ClipboardManager.shared
        _ = SystemMonitorManager.shared
        _ = WeatherManager.shared
        // BluetoothManager initializes lazily on first widget view (requires TCC authorization)
        _ = ShortcutsManager.shared
        _ = TodoManager.shared
    }

    private func setupNotchWindow() {
        guard let screen = NotchScreenDetector.notchScreen() else { return }
        if !NotchScreenDetector.hasNotch(screen),
           !UserDefaults.standard.bool(forKey: "general.noNotchAlertDismissed") {
            showNoNotchAlert()
        }
        notchWindowController = NotchWindowController(screen: screen)
        notchWindowController?.showWindow(nil)
    }

    private func showNoNotchAlert() {
        let alert = NSAlert()
        alert.messageText = "No Notch Detected"
        alert.informativeText = "Notchly is designed for MacBooks with a notch. The panel will appear at the top of your screen but may not look as intended."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Quit")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't show again"
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: "general.noNotchAlertDismissed")
        }
        if response == .alertSecondButtonReturn {
            NSApplication.shared.terminate(nil)
        }
    }

    func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showAbout() {
        if aboutWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "About Notchly"
            window.center()
            window.contentView = NSHostingView(rootView: AboutView())
            window.isReleasedWhenClosed = false
            aboutWindow = window
        }
        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Global hotkey (Option+N)

    private func handleHotkeyEvent(_ event: NSEvent) -> Bool {
        guard GeneralSettings.shared.hotkeyEnabled else { return false }
        guard event.keyCode == 45,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option else {
            return false
        }
        guard let controller = notchWindowController else { return true }
        if controller.isExpanded {
            controller.collapse()
        } else {
            controller.expand()
        }
        return true
    }

    private func setupHotkey() {
        localHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            (self?.handleHotkeyEvent(event) ?? false) ? nil : event
        }

        installGlobalHotkeyIfNeeded()

        NotificationCenter.default.addObserver(
            forName: .accessibilityPermissionGranted, object: nil, queue: .main
        ) { [weak self] _ in
            self?.installGlobalHotkeyIfNeeded()
        }
    }

    private func installGlobalHotkeyIfNeeded() {
        guard globalHotkeyMonitor == nil, AXIsProcessTrusted() else { return }
        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handleHotkeyEvent(event)
        }
    }
}

// MARK: - Active app tracking (for clipboard paste-back)

class ActiveAppTracker {
    static let shared = ActiveAppTracker()
    private(set) var previousApp: NSRunningApplication?
    private init() {}

    /// Call just before the notch panel expands so we know where to paste back.
    func captureActiveApp() {
        previousApp = NSWorkspace.shared.runningApplications.first {
            $0.isActive && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        }
    }

    /// Activate the previously captured app and send ⌘V into it.
    func pasteIntoPreviousApp() {
        guard let app = previousApp else { return }
        app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let src  = CGEventSource(stateID: .combinedSessionState)
            let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
            let up   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
            down?.flags = .maskCommand
            up?.flags   = .maskCommand
            down?.post(tap: .cgAnnotatedSessionEventTap)
            up?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
