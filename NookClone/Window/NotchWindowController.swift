import AppKit
import SwiftUI
import Combine

/// Manages the transparent NSWindow that sits in/around the notch area.
class NotchWindowController: NSWindowController {

    private let targetScreen: NSScreen

    private(set) var collapsedFrame: NSRect = .zero
    private(set) var expandedFrame: NSRect = .zero

    private(set) var isExpanded = false
    private var isPinned = false
    private var hoverTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var currentWidgetHeight: CGFloat = 160

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
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    // MARK: - Setup

    private func computeFrames(widgetHeight: CGFloat = 160) {
        let screen = targetScreen
        let screenFrame = screen.frame
        let notchRect = NotchScreenDetector.notchRect(on: screen)
        let settings = GeneralSettings.shared

        collapsedFrame = notchRect

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
        let hosting = NSHostingView(rootView: NookPanelView())
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
                let frame = self.isExpanded ? self.expandedFrame : self.collapsedFrame
                self.window?.setFrame(frame, display: true, animate: true)
            }
            .store(in: &cancellables)
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
        if !isExpanded {
            guard GeneralSettings.shared.openOnHover else { return }
            if collapsedFrame.contains(mouse) { expand() }
        } else if !isPinned {
            if let frame = window?.frame, !frame.contains(mouse) { collapseIfNeeded() }
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
    }

    // MARK: - Expand / Collapse

    func expand() {
        guard !isExpanded else { return }
        isExpanded = true
        window?.ignoresMouseEvents = false
        window?.hasShadow = true
        computeFrames(widgetHeight: currentWidgetHeight)
        NotificationCenter.default.post(name: .notchPanelExpandedChanged, object: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window?.animator().setFrame(expandedFrame, display: true)
        }
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        isPinned = false
        window?.hasShadow = false
        NotificationCenter.default.post(name: .notchPanelExpandedChanged, object: false)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window?.animator().setFrame(collapsedFrame, display: true)
        } completionHandler: { [weak self] in
            self?.window?.ignoresMouseEvents = true
        }
    }

    func collapseIfNeeded() {
        guard !isPinned else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, !self.isPinned else { return }
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
        window?.setFrame(isExpanded ? expandedFrame : collapsedFrame, display: true)
    }
}

// MARK: - Comparable clamped helper

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - NotchWindow

class NotchWindow: NSWindow {
    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask,
                  backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 32),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered, defer: false
        )
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
