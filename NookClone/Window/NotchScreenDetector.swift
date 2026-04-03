import AppKit

/// Utilities for detecting screens that have a notch.
enum NotchScreenDetector {

    /// Returns the first screen with a notch (safeAreaInsets.top > 0),
    /// falling back to the main screen if none found.
    static func notchScreen() -> NSScreen? {
        let notched = NSScreen.screens.first { screen in
            if #available(macOS 12.0, *) {
                return screen.safeAreaInsets.top > 0
            }
            return false
        }
        return notched ?? NSScreen.main
    }

    /// The notch rectangle in screen coordinates (flipped from AppKit's bottom-left origin).
    static func notchRect(on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame

        if #available(macOS 12.0, *) {
            let insets = screen.safeAreaInsets
            if insets.top > 0 {
                let notchHeight = insets.top
                // MacBook Air models (native width ≤ 2880px) have wider notch (~234pt)
                // MacBook Pro models (native width ≥ 3024px) have narrower notch (~162pt)
                let nativeWidth = screenFrame.width * screen.backingScaleFactor
                let notchWidth: CGFloat = nativeWidth <= 2880 ? 234 : 162
                let centerX = screenFrame.midX
                return NSRect(
                    x: centerX - notchWidth / 2,
                    y: screenFrame.maxY - notchHeight,
                    width: notchWidth,
                    height: notchHeight
                )
            }
        }

        // No notch: return a thin strip at the very top (fallback for testing)
        return NSRect(
            x: screenFrame.midX - 80,
            y: screenFrame.maxY - 32,
            width: 160,
            height: 32
        )
    }

    /// Whether the given screen has a notch.
    static func hasNotch(_ screen: NSScreen) -> Bool {
        if #available(macOS 12.0, *) {
            return screen.safeAreaInsets.top > 0
        }
        return false
    }
}
