import AppKit
import SwiftUI
import Combine

/// Manages the transparent NSWindow that sits in/around the notch area.
class NotchWindowController: NSWindowController {

    private let targetScreen: NSScreen

    private(set) var collapsedFrame: NSRect = .zero
    private(set) var expandedFrame: NSRect = .zero
    private(set) var liveFrame: NSRect = .zero

    private(set) var isExpanded = false
    private var isPinned = false
    private var isAnimating = false
    private var hoverTimer: Timer?
    private var isHoveringCollapsed = false
    private var cancellables = Set<AnyCancellable>()
    private var currentWidgetHeight: CGFloat = 200
    private var isLive = false
    private let livePillExtraHeight: CGFloat = 10

    init(screen: NSScreen) {
        self.targetScreen = screen
        let window = NotchWindow()
        super.init(window: window)

        computeFrames()
        configureWindow()
        embedContentView()
        setupNotifications()
        startHoverMonitor()
        subscribeToSettings()
        subscribeToMediaState()
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    // MARK: - Setup

    private func computeFrames(widgetHeight: CGFloat = 160) {
        let screen = targetScreen
        let screenFrame = screen.frame
        let notchRect = NotchScreenDetector.notchRect(on: screen)
        let settings = GeneralSettings.shared

        collapsedFrame = notchRect

        let liveWidth: CGFloat = 320
        let liveX = (notchRect.midX - liveWidth / 2)
            .clamped(to: screenFrame.minX...(screenFrame.maxX - liveWidth))
        liveFrame = NSRect(
            x: liveX,
            y: notchRect.minY - livePillExtraHeight,
            width: liveWidth,
            height: notchRect.height + livePillExtraHeight
        )

        let panelWidth: CGFloat = max(notchRect.width + 200, 520) + settings.notchWidthOffset
        let panelHeight: CGFloat = widgetHeight + settings.notchHeightOffset
        let panelX = (notchRect.midX - panelWidth / 2)
            .clamped(to: screenFrame.minX...(screenFrame.maxX - panelWidth))

        expandedFrame = NSRect(
            x: panelX,
            y: notchRect.minY - panelHeight,
            width: panelWidth,
            height: panelHeight + notchRect.height
        )
    }

    private func configureWindow() {
        guard let window else { return }
        window.setFrame(collapsedFrame, display: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 5)
        window.ignoresMouseEvents = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.styleMask = [.borderless, .fullSizeContentView]
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }

    private func embedContentView() {
        guard let window else { return }
        let hosting = ClickThroughHostingView(rootView: NookPanelView())
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
    }

    private func subscribeToSettings() {
        // Recompute frames whenever notch offset settings change
        let settings = GeneralSettings.shared
        Publishers.CombineLatest(settings.$notchWidthOffset, settings.$notchHeightOffset)
            .dropFirst()  // skip initial value
            .sink { [weak self] _, _ in
                guard let self else { return }
                self.computeFrames(widgetHeight: self.currentWidgetHeight)
                let frame = self.isExpanded ? self.expandedFrame : (self.isLive ? self.liveFrame : self.collapsedFrame)
                self.window?.setFrame(frame, display: true, animate: true)
            }
            .store(in: &cancellables)
    }

    private func subscribeToMediaState() {
        MediaManager.shared.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                self?.setLive(track != nil)
            }
            .store(in: &cancellables)
    }

    private func setLive(_ live: Bool) {
        guard live != isLive else { return }
        isLive = live
        guard !isExpanded else { return }
        let targetFrame = live ? liveFrame : collapsedFrame
        window?.ignoresMouseEvents = !live
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.5
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window?.animator().setFrame(targetFrame, display: true)
        }
    }

    private func startHoverMonitor() {
        // Poll mouse position — NSTrackingArea doesn't fire when ignoresMouseEvents = true
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkHover()
        }
        hoverTimer?.tolerance = 0.01
    }

    private func checkHover() {
        let mouse = NSEvent.mouseLocation
        let hoverFrame = isExpanded ? expandedFrame : (isLive ? liveFrame : collapsedFrame)
        let hovering = hoverFrame.contains(mouse)
        if hovering != isHoveringCollapsed {
            isHoveringCollapsed = hovering
            NotificationCenter.default.post(name: .notchPillHoverChanged, object: hovering)
        }
        if hovering && !isExpanded && GeneralSettings.shared.openOnHover {
            expand()
        } else if !hovering && !isAnimating {
            collapseIfNeeded()
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTap),
            name: .notchPanelTapped,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHeightChanged(_:)),
            name: .notchPanelHeightChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCollapseRequested),
            name: .notchPanelCollapseRequested,
            object: nil
        )
    }

    @objc private func handleCollapseRequested() {
        collapse()
    }

    // MARK: - Expand / Collapse

    func expand() {
        guard !isExpanded else { return }
        ActiveAppTracker.shared.captureActiveApp()
        isExpanded = true
        window?.hasShadow = true
        window?.ignoresMouseEvents = false
        window?.makeKey()
        computeFrames(widgetHeight: currentWidgetHeight)
        NotificationCenter.default.post(name: .notchPanelExpandedChanged, object: true)
        isAnimating = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window?.animator().setFrame(expandedFrame, display: true)
        } completionHandler: { [weak self] in
            self?.isAnimating = false
        }
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        isPinned = false
        window?.hasShadow = false
        window?.ignoresMouseEvents = !isLive
        NotificationCenter.default.post(name: .notchPanelExpandedChanged, object: false)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window?.animator().setFrame(isLive ? liveFrame : collapsedFrame, display: true)
        }
    }

    func collapseIfNeeded() {
        guard !isPinned else { return }
        // Don't start the collapse countdown while the user is clicking
        guard NSEvent.pressedMouseButtons == 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, !self.isPinned, !self.isAnimating else { return }
            guard NSEvent.pressedMouseButtons == 0 else { return }
            let mouse = NSEvent.mouseLocation
            if let frame = self.window?.frame, !frame.contains(mouse) {
                self.collapse()
            }
        }
    }

    @objc private func handleTap() {
        guard GeneralSettings.shared.openOnClick else { return }
        isPinned.toggle()
        if isPinned { expand() } else { collapseIfNeeded() }
    }

    func setHidden(_ hidden: Bool) {
        hidden ? window?.orderOut(nil) : window?.orderFront(nil)
    }

    @objc private func handleHeightChanged(_ notification: Notification) {
        guard let height = notification.object as? CGFloat else { return }
        // AppKit frame animations must run on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.currentWidgetHeight = height
            self.computeFrames(widgetHeight: height)
            if self.isExpanded {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.25
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    self.window?.animator().setFrame(self.expandedFrame, display: true)
                }
            }
        }
    }

    @objc private func screensChanged() {
        computeFrames(widgetHeight: currentWidgetHeight)
        window?.setFrame(isExpanded ? expandedFrame : (isLive ? liveFrame : collapsedFrame), display: true)
    }
}

// MARK: - Comparable clamped helper

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - ClickThroughHostingView

/// NSHostingView subclass that accepts the first mouse click as an action
/// (rather than consuming it for key-window acquisition).
/// Without this, every button in the panel requires two clicks: one to focus
/// the window, one to trigger the action.
private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - NotchWindow

/// NSPanel subclass used for the notch overlay.
///
/// Using NSPanel with .nonactivatingPanel is the correct pattern for floating
/// utility panels on macOS (the same approach used by Alfred, Raycast, etc.).
/// It lets the panel become the key window — so SwiftUI buttons receive events
/// normally — without stealing the active-app status from the user's current app.
class NotchWindow: NSPanel {
    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask,
                  backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 32),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// If a click arrives while the panel is not key, make it key first so the
    /// event is delivered to SwiftUI as an action (not consumed for focus).
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown && !isKeyWindow {
            makeKey()
        }
        super.sendEvent(event)
    }
}
