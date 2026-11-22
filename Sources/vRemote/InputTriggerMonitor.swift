import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Global keyboard monitor for the two voice shortcuts.
///
/// WeType's push-to-talk mode is a modifier-only shortcut, while the toggle
/// mode can be a modifier-only shortcut, a single key, or a combination. The
/// monitor reports the mode whose shortcut matched; the session coordinator
/// owns the actual state transition.
final class InputTriggerMonitor {
    private var tapPort: CFMachPort?
    private var triggerKeysDown = Set<Int64>()
    private var activeKeyModes = Set<VoiceGestureMode>()
    private var pttShortcut: TriggerShortcut = .pttDefault
    private var toggleShortcut: TriggerShortcut = .toggleDefault
    private(set) var isAvailable = false

    var onTriggerDown: ((VoiceGestureMode) -> Void)?
    var onTriggerUp: ((VoiceGestureMode) -> Void)?

    func configure(ptt: TriggerShortcut, toggle: TriggerShortcut) {
        pttShortcut = ptt
        toggleShortcut = toggle
        resetState()
        print(
            "[INPUT-TRIGGER] push-to-talk=\(ptt.label) " +
            "toggle=\(toggle.label)"
        )
    }

    func start() {
        guard AXIsProcessTrusted() else {
            isAvailable = false
            print("[INPUT-TRIGGER] accessibility permission unavailable")
            return
        }
        isAvailable = true

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = {
            _, type, event, context -> Unmanaged<CGEvent>?
            in
            guard let context else {
                return Unmanaged.passRetained(event)
            }
            let monitor = Unmanaged<InputTriggerMonitor>
                .fromOpaque(context)
                .takeUnretainedValue()

            if type == .tapDisabledByTimeout
                || type == .tapDisabledByUserInput
            {
                if let tapPort = monitor.tapPort {
                    CGEvent.tapEnable(tap: tapPort, enable: true)
                }
                return Unmanaged.passRetained(event)
            }

            let isSynthetic = event.getIntegerValueField(
                .eventSourceUserData
            ) == Key.syntheticMarker
            if isSynthetic {
                return Unmanaged.passRetained(event)
            }

            monitor.observeTriggerEvent(type: type, event: event)
            return Unmanaged.passRetained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[INPUT-TRIGGER] unable to create event tap")
            return
        }
        tapPort = tap
        guard let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            print("[INPUT-TRIGGER] unable to create run-loop source")
            tapPort = nil
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[INPUT-TRIGGER] trigger monitor ready")
    }

    func triggerConfigurationDidChange() {
        resetState()
        print(
            "[INPUT-TRIGGER] push-to-talk=\(pttShortcut.label) " +
            "toggle=\(toggleShortcut.label)"
        )
    }

    func stop() {
        resetState()
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: false)
        }
        tapPort = nil
    }

    private func resetState() {
        triggerKeysDown.removeAll()
        activeKeyModes.removeAll()
    }

    private func observeTriggerEvent(type: CGEventType, event: CGEvent) {
        let keyCode = CGKeyCode(
            event.getIntegerValueField(.keyboardEventKeycode)
        )

        switch type {
        case .flagsChanged:
            checkModifierOnly(
                keyCode: keyCode,
                flags: event.flags,
                mode: .pushToTalk,
                shortcut: pttShortcut
            )
            checkModifierOnly(
                keyCode: keyCode,
                flags: event.flags,
                mode: .toggle,
                shortcut: toggleShortcut
            )
        case .keyDown, .keyUp:
            let isDown = type == .keyDown
            for (mode, shortcut) in [
                (VoiceGestureMode.pushToTalk, pttShortcut),
                (.toggle, toggleShortcut)
            ] where !shortcut.isModifierOnly {
                guard shortcut.matchesKeyEvent(
                    keyCode: keyCode,
                    flags: event.flags
                ) else { continue }
                if isDown {
                    guard activeKeyModes.insert(mode).inserted else { continue }
                    print("[INPUT-TRIGGER] \(mode.rawValue) DOWN key=0x\(String(keyCode, radix: 16))")
                    onTriggerDown?(mode)
                } else {
                    guard activeKeyModes.remove(mode) != nil else { continue }
                    print("[INPUT-TRIGGER] \(mode.rawValue) UP key=0x\(String(keyCode, radix: 16))")
                    onTriggerUp?(mode)
                }
                return
            }
        default:
            break
        }
    }

    private func checkModifierOnly(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        mode: VoiceGestureMode,
        shortcut: TriggerShortcut
    ) {
        guard shortcut.isModifierOnly,
              shortcut.matchesModifierKeyCode(Int64(keyCode)) else {
            return
        }
        let isDown = triggerKeysDown.contains(Int64(keyCode))
        if isDown {
            triggerKeysDown.remove(Int64(keyCode))
            print("[INPUT-TRIGGER] \(mode.rawValue) UP modifier=0x\(String(keyCode, radix: 16))")
            onTriggerUp?(mode)
        } else {
            triggerKeysDown.insert(Int64(keyCode))
            print("[INPUT-TRIGGER] \(mode.rawValue) DOWN modifier=0x\(String(keyCode, radix: 16))")
            onTriggerDown?(mode)
        }
    }
}
