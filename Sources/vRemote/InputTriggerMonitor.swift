import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Global keyboard trigger monitor for the voice shortcut.
///
/// The same key can arrive as `flagsChanged` on a real keyboard and as a plain
/// `keyDown`/`keyUp` on some input-method paths. The monitor tracks the
/// physical key codes so a release is always paired with the matching press.
final class InputTriggerMonitor {
    private var tapPort: CFMachPort?
    private var triggerKeysDown = Set<Int64>()
    private(set) var isAvailable = false
    var onTriggerDownObserved: ((Bool) -> Void)?
    var onTriggerUpObserved: ((Bool) -> Void)?

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
                print(
                    "[INPUT-TRIGGER] delivered synthetic trigger " +
                    "type=\(type.rawValue) " +
                    "flags=0x\(String(event.flags.rawValue, radix: 16))"
                )
                return Unmanaged.passRetained(event)
            }

            monitor.observeTriggerEvent(
                type: type,
                event: event,
                isSynthetic: false
            )
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
        triggerKeysDown.removeAll()
        print("[INPUT-TRIGGER] listening for \(AppStorage.activeTriggerKey.title)")
    }

    func stop() {
        triggerKeysDown.removeAll()
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: false)
        }
        tapPort = nil
    }

    private func observeTriggerEvent(
        type: CGEventType,
        event: CGEvent,
        isSynthetic: Bool
    ) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard !isSynthetic else { return }
        let trigger = AppStorage.activeTriggerKey
        guard trigger.matchesPhysicalKeyCode(keyCode) else { return }

        let isDown: Bool
        switch type {
        case .keyDown:
            isDown = true
        case .keyUp:
            isDown = false
        case .flagsChanged:
            // When another Option key remains held, maskAlternate stays set
            // even while this key is released. The per-key set is therefore
            // a more reliable release signal than the aggregate flag alone.
            if triggerKeysDown.contains(keyCode) {
                isDown = false
            } else {
                guard event.flags.contains(trigger.flag) else {
                    print(
                        "[INPUT-TRIGGER] orphan UP ignored keyCode=0x" +
                        String(keyCode, radix: 16)
                    )
                    return
                }
                isDown = true
            }
        default:
            return
        }

        print(
            "[INPUT-TRIGGER] type=\(type.rawValue) " +
            "keyCode=0x\(String(keyCode, radix: 16)) " +
            "edge=\(isDown ? "DOWN" : "UP")"
        )
        if isDown {
            guard triggerKeysDown.insert(keyCode).inserted else { return }
            onTriggerDownObserved?(isSynthetic)
        } else {
            guard triggerKeysDown.remove(keyCode) != nil else { return }
            onTriggerUpObserved?(isSynthetic)
        }
    }
}
