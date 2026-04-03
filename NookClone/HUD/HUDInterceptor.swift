import AppKit
import CoreAudio
import IOKit
import IOKit.graphics

/// Intercepts volume/brightness media key events and shows the custom HUD overlay.
/// Volume/brightness keys on MacBooks emit NSEventTypeSystemDefined (subtype 8), not keyDown.
/// Requires Accessibility permission (AXIsProcessTrusted) for the CGEventTap.
class HUDInterceptor {

    static let shared = HUDInterceptor()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var accessibilityTimer: Timer?
    private var watchdogTimer: Timer?

    private init() {}

    func start() {
        guard HUDSettings.shared.isEnabled else { return }
        if AXIsProcessTrusted() {
            installEventTap()
        } else {
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
            waitForAccessibility()
        }
    }

    func stop() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    private func waitForAccessibility() {
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            if AXIsProcessTrusted() {
                timer.invalidate()
                self?.accessibilityTimer = nil
                self?.installEventTap()
                NotificationCenter.default.post(name: .accessibilityPermissionGranted, object: nil)
            }
        }
    }

    // MARK: - CGEventTap

    private func installEventTap() {
        guard eventTap == nil else { return }

        // Tap systemDefined events — this is what MacBook media/volume keys generate
        // CGEventType.systemDefined raw value is 14 (kCGEventSystemDefined)
        // Also listen for tapDisabledByTimeout (raw value = 0xFFFFFFFE) so we can re-enable
        let eventMask = CGEventMask(1 << 14)
        // Use passUnretained — HUDInterceptor is a singleton that lives for the app's lifetime,
        // so the unretained reference is always valid and no balancing release is needed.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passRetained(event) }
                let me = Unmanaged<HUDInterceptor>.fromOpaque(userInfo).takeUnretainedValue()

                // macOS disables the tap if the callback takes too long or the
                // system decides to revoke it.  Re-enable immediately.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = me.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passRetained(event)
                }

                return me.handle(event: event)
            },
            userInfo: selfPtr
        ) else {
            return
        }

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.eventTap = tap
        self.runLoopSource = src
        startWatchdog()
    }

    /// Periodically checks that the event tap is still alive and re-enables or
    /// re-creates it if the system disabled it outside of the callback path.
    private func startWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self, HUDSettings.shared.isEnabled else { return }
            if let tap = self.eventTap {
                if !CGEvent.tapIsEnabled(tap: tap) {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            } else {
                // Tap was destroyed — try to recreate it
                self.installEventTap()
            }
        }
        watchdogTimer?.tolerance = 1.0
    }

    private func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
        // Media keys arrive as systemDefined events with subtype 8
        guard event.getIntegerValueField(.eventSourceStateID) >= 0 else {
            return Unmanaged.passRetained(event)
        }

        // Convert to NSEvent to read the subtype and data
        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type.rawValue == 14,  // NSEventType.systemDefined = 14
              nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passRetained(event)
        }

        // data1 encodes key code (bits 16-23) and key state (bits 8-11, 0=down 1=up)
        let data1 = nsEvent.data1
        let keyCode = Int((data1 & 0xFFFF0000) >> 16)
        let keyFlags = Int(data1 & 0x0000FFFF)
        let keyDown = (keyFlags >> 8) == 0xA   // 0xA = key press, 0xB = key release

        guard keyDown else { return Unmanaged.passRetained(event) }

        // NX key type constants (from <IOKit/hidsystem/ev_keymap.h>)
        switch keyCode {
        case 0:   // NX_KEYTYPE_SOUND_UP
            DispatchQueue.main.async { self.adjustVolume(+1) }
            return nil  // Suppress system HUD
        case 1:   // NX_KEYTYPE_SOUND_DOWN
            DispatchQueue.main.async { self.adjustVolume(-1) }
            return nil
        case 7:   // NX_KEYTYPE_MUTE
            DispatchQueue.main.async { self.toggleMute() }
            return nil
        case 144: // NX_KEYTYPE_BRIGHTNESS_UP
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.showBrightness() }
            return Unmanaged.passRetained(event)  // Let system change brightness
        case 145: // NX_KEYTYPE_BRIGHTNESS_DOWN
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.showBrightness() }
            return Unmanaged.passRetained(event)
        default:
            return Unmanaged.passRetained(event)
        }
    }

    // MARK: - Volume control via CoreAudio

    private func defaultOutputDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceID
    }

    private func getSystemVolume() -> Float {
        let device = defaultOutputDevice()
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 0
        )
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr {
            return volume
        }
        address.mElement = 1
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume)
        return volume
    }

    private func setSystemVolume(_ volume: Float) {
        let device = defaultOutputDevice()
        var vol = min(max(volume, 0), 1)
        let size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 0
        )
        if AudioObjectSetPropertyData(device, &address, 0, nil, size, &vol) == noErr { return }
        for ch: UInt32 in [1, 2] {
            address.mElement = ch
            AudioObjectSetPropertyData(device, &address, 0, nil, size, &vol)
        }
    }

    private func isSystemMuted() -> Bool {
        let device = defaultOutputDevice()
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)
        return muted != 0
    }

    private func setSystemMuted(_ muted: Bool) {
        let device = defaultOutputDevice()
        var muteValue: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &muteValue)
    }

    private func adjustVolume(_ delta: Int) {
        let current = getSystemVolume()
        let step: Float = 1.0 / 16.0  // standard macOS volume step
        setSystemVolume(current + Float(delta) * step)
        showVolume()
    }

    private func toggleMute() {
        setSystemMuted(!isSystemMuted())
        showVolume()
    }

    private func showVolume() {
        let muted = isSystemMuted()
        let volume = getSystemVolume()
        HUDOverlayWindow.shared.show(type: .volume(muted: muted), value: muted ? 0 : volume)
    }

    // MARK: - Brightness via IOKit

    private func showBrightness() {
        HUDOverlayWindow.shared.show(type: .brightness, value: getDisplayBrightness())
    }

    private func getDisplayBrightness() -> Float {
        // Modern path: DisplayServices private framework (reliable on Apple Silicon + macOS 12+)
        typealias GetBrightnessFunc = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
        if let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) {
            defer { dlclose(handle) }
            if let sym = dlsym(handle, "DisplayServicesGetBrightness") {
                let getBrightness = unsafeBitCast(sym, to: GetBrightnessFunc.self)
                var brightness: Float = 0
                if getBrightness(CGMainDisplayID(), &brightness) == 0 {
                    return brightness
                }
            }
        }
        // Fallback: IOKit IODisplayConnect (Intel Macs, older macOS)
        var brightness: Float = 0.5
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IODisplayConnect"),
                                           &iterator) == KERN_SUCCESS else { return brightness }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &brightness)
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)
        return brightness
    }
}
