---
name: notchly-macos-floating-panel
description: |
  Fix for macOS floating panel buttons requiring two clicks, or not receiving
  mouse events at all. Use when: (1) SwiftUI buttons in a borderless NSWindow
  need two clicks, (2) first click consumed by focus acquisition, (3) building
  a floating utility panel (like Spotlight, Alfred, Raycast).
author: Claude Code
version: 1.0.0
---

# macOS Floating Panel — Click-Through Fix

## When to Use

- SwiftUI buttons inside a borderless `NSWindow` require two clicks
- First click is consumed by AppKit's key-window acquisition
- Building a floating overlay/utility panel that shouldn't steal app focus
- `acceptsFirstMouse(for:)` alone doesn't fix the issue

## Solution

Use `NSPanel` with `.nonactivatingPanel` instead of `NSWindow`. This is the standard macOS pattern for floating utility panels.

### 1. Subclass NSPanel (not NSWindow)

```swift
class FloatingPanel: NSPanel {
    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask,
                  backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Deliver the first click as an action, not just focus acquisition
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown && !isKeyWindow {
            makeKey()
        }
        super.sendEvent(event)
    }
}
```

### 2. Belt-and-suspenders: ClickThrough NSHostingView

```swift
final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
```

### 3. On expand: enable mouse events and make key

```swift
window?.ignoresMouseEvents = false
window?.makeKey()
```

## Why acceptsFirstMouse Alone Fails

AppKit hit-tests to private SwiftUI subviews, not the NSHostingView root. Those private views don't override `acceptsFirstMouse`, so the override on the hosting view is bypassed. The `sendEvent` override at the window level catches ALL events regardless of which subview is hit-tested.

## Why NSPanel, Not NSWindow

`NSPanel` with `.nonactivatingPanel` lets the panel become key (so SwiftUI buttons work) without stealing active-app status. This is critical for `.accessory` activation policy apps (LSUIElement) where `NSApp.activate()` fights with the user's current app.

## Additional Gotcha: AVAudioEngine Input Tap

On macOS, `AVAudioEngine.inputNode.installTap()` creates an audio loopback that routes microphone input to speaker output, causing audible playback changes (bass-boost, feedback). Use animated simulation instead of real audio processing for visualizations.

## When NOT to Use

- Standard app windows that should become the active app on click
- Windows that should hide when the app deactivates
- Modal dialogs or sheets

## Verification

1. Build and run the app
2. Click a SwiftUI button in the panel on the FIRST click — action fires immediately
3. The previously active app stays active (no dock icon bounce, no menu bar switch)
