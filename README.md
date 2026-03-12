# Notchly

A Dynamic Island-style notch panel for macOS. Hover to expand widgets; when music plays, the notch widens into a live pill showing album art and an animated spectrograph.

## Features

### Live Notch Pill
When music is playing, the collapsed notch expands into a Dynamic Island-style live pill — album art on the left, animated spectrograph on the right. Flat top merges seamlessly with the physical notch; rounded bottom corners emerge below it. When nothing is playing, the pill hides entirely behind the notch.

### Widgets

| Widget | Description |
|--------|-------------|
| **Media** | Now-playing from Apple Music or Spotify, album art, animated spectrograph, playback controls |
| **Calendar** | Today's events via EventKit, color-coded by calendar |
| **Clipboard** | Clipboard history manager with one-click paste and image preview |
| **Bluetooth** | Connected device list with battery levels and connect/disconnect |
| **Drop Area** | Drag-and-drop shelf for files, URLs, and text with AirDrop/Share actions |
| **Notes** | Persistent rich-text notepad with bold/italic/underline formatting |
| **HUD Replacement** | Custom volume and brightness overlay replacing the system HUD |

## Requirements

- macOS 14.0 (Sonoma) or later
- MacBook with notch recommended (works on all Macs)
- Xcode 15+ to build

## Building

```bash
# Install xcodegen if not already installed
brew install xcodegen

# Generate Xcode project
cd ~/Desktop/Notchly
xcodegen generate

# Open in Xcode
open Notchly.xcodeproj
```

Then press **⌘R** to build and run.

## Permissions Required

| Permission | Used For |
|-----------|----------|
| Accessibility | HUD interception via CGEventTap |
| Apple Music | Now-playing track info |
| Calendar | Today's event display |
| Microphone | _(not required — spectrograph is animated)_ |

## Architecture

```
Notchly/
├── App/           - AppDelegate, app entry point
├── Window/        - NotchWindowController, hover detection, fullscreen monitoring
├── Widgets/
│   ├── Core/      - NookWidget protocol, WidgetRegistry, WidgetContainerView
│   ├── Media/     - MediaManager (ScriptingBridge), AudioSpectrograph (AVAudio + vDSP)
│   ├── Calendar/  - CalendarManager (EventKit)
│   ├── DropArea/  - Drag-and-drop shelf, NSSharingService
│   └── Notes/     - NSTextView rich editor, auto-save
├── HUD/           - CGEventTap interception, CoreAudio volume, IOKit brightness
└── Settings/      - GeneralSettings, SettingsWindowController, per-widget panes
```

## Privacy

Notchly does not collect or transmit any data. All data (notes, settings) is stored locally in `~/Library/Application Support/Notchly/`.

## License

This is a clean-room implementation for educational purposes. Not affiliated with lo.cafe or the original NotchNook application.
