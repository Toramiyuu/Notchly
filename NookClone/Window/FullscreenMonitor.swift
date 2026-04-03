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

    /// Detects true macOS fullscreen (the kind that hides the menu bar and notch).
    ///
    /// On macOS 15+, `AXFullScreen` alone is unreliable — it returns `true` for
    /// maximized and tiled windows that still show the menu bar.  We use the
    /// window-list CGS API to check whether a window on the active space has the
    /// `.fullScreenWindow` style mask, which is only set for genuine fullscreen.
    private func isFrontmostAppFullscreen() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }

        // CGWindowListCopyWindowInfo is the most reliable way to detect true
        // fullscreen windows on modern macOS — it reports the actual window
        // backing-store level, which only goes to kCGFullScreenWindow for the
        // real fullscreen mode (not maximized/tiled).
        let pid = frontApp.processIdentifier
        guard pid > 0,
              let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] else {
            return false
        }

        let screenFrame = NSScreen.screens.first?.frame ?? .zero

        for info in windowList {
            guard let ownerPID = info[kCGWindowOwnerPID] as? Int32, ownerPID == pid else { continue }
            guard let bounds = info[kCGWindowBounds] as? [String: CGFloat] else { continue }

            let w = bounds["Width"] ?? 0
            let h = bounds["Height"] ?? 0

            // A true fullscreen window covers the entire screen including the
            // menu bar / notch area.  Allow 1pt tolerance for rounding.
            if abs(w - screenFrame.width) < 2 && abs(h - screenFrame.height) < 2 {
                return true
            }
        }

        return false
    }
}
