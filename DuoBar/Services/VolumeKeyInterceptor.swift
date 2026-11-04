import AppKit
import ApplicationServices

enum VolumeKey: Equatable {
    case up
    case down
    case mute
}

/// While the popover is open, takes over the hardware volume keys so the
/// system volume overlay stays hidden and only DuoBar's own slider moves.
/// Needs Accessibility permission for the event tap; without it the keys keep
/// their normal system behavior.
@MainActor
final class VolumeKeyInterceptor {
    /// Return true when the key was handled; the event is then consumed.
    var onKey: ((_ key: VolumeKey, _ isFineStep: Bool) -> Bool)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hasPromptedForAccess = false
    private var lastKeyDownWasHandled = false

    func start() {
        guard tap == nil else { return }
        let shouldPrompt = !hasPromptedForAccess
        hasPromptedForAccess = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: shouldPrompt] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return }

        // NSEvent.EventType.systemDefined carries the media and volume keys.
        let mask = CGEventMask(1) << CGEventMask(NSEvent.EventType.systemDefined.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: volumeKeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }

        let data = nsEvent.data1
        let keyCode = (data & 0xFFFF_0000) >> 16
        let isKeyDown = ((data & 0xFF00) >> 8) == 0x0A
        let key: VolumeKey
        switch keyCode {
        case 0: key = .up        // NX_KEYTYPE_SOUND_UP
        case 1: key = .down      // NX_KEYTYPE_SOUND_DOWN
        case 7: key = .mute      // NX_KEYTYPE_MUTE
        default: return Unmanaged.passUnretained(event)
        }

        // A key-up follows its key-down, so the system never sees half a press.
        guard isKeyDown else {
            return lastKeyDownWasHandled ? nil : Unmanaged.passUnretained(event)
        }
        let isFineStep = nsEvent.modifierFlags.contains([.option, .shift])
        lastKeyDownWasHandled = onKey?(key, isFineStep) == true
        return lastKeyDownWasHandled ? nil : Unmanaged.passUnretained(event)
    }
}

private func volumeKeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let interceptor = Unmanaged<VolumeKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
    // The tap's run loop source is on the main run loop.
    return MainActor.assumeIsolated {
        interceptor.handle(type: type, event: event)
    }
}
