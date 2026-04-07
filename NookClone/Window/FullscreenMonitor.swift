import AppKit

/// Monitors for fullscreen applications and calls back when state changes.
class FullscreenMonitor {

    private let onChange: (Bool) -> Void
    private var wsObservers: [Any] = []
    private var pollTimer: Timer?

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        setupObservers()
    }

    deinit {
        pollTimer?.invalidate()
        wsObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    private func setupObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter

        // App activation change
        wsObservers.append(wsCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.checkFullscreen() })

        // Space change (catches fullscreen apps on different spaces)
        wsObservers.append(wsCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.checkFullscreen() })

        // Periodic poll as safety net
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkFullscreen()
        }
    }

    private var lastFullscreenState = false

    private func checkFullscreen() {
        let isFullscreen = isFrontmostAppFullscreen()
        guard isFullscreen != lastFullscreenState else { return }
        lastFullscreenState = isFullscreen
        onChange(isFullscreen)
    }

    /// Detects true macOS fullscreen — the kind that hides the menu bar.
    ///
    /// The previous CGWindowList size-check caused false positives: Chrome, Teams,
    /// Word and other apps create backing/render windows whose reported bounds equal
    /// the screen dimensions, even though the menu bar is still visible.  Those apps
    /// were incorrectly triggering `orderOut`, making Notchly invisible whenever the
    /// user switched away from the desktop.
    ///
    /// The reliable signal is simpler: true fullscreen hides the menu bar, which
    /// macOS reflects immediately in `NSScreen.visibleFrame`.  In normal mode the
    /// menu bar occupies ~24–37 pt at the top of the screen, so
    /// `screen.frame.maxY - screen.visibleFrame.maxY` is ≥ 20.  When the menu bar
    /// is hidden that gap collapses to < 5.
    private func isFrontmostAppFullscreen() -> Bool {
        guard let screen = NSScreen.main else { return false }
        return screen.frame.maxY - screen.visibleFrame.maxY < 5
    }
}
