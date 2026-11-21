import CoreGraphics
import Foundation

enum InputTriggerKey: String, CaseIterable, Identifiable {
    // Legacy raw values stay in place so existing settings keep working.
    // `option`, `command`, `control`, and `shift` are the left-side keys.
    case option
    case optionRight
    case command
    case commandRight
    case control
    case controlRight
    case shift
    case shiftRight
    case function

    var id: String { rawValue }

    var title: String {
        switch self {
        case .option: L10n.text("左 Option (⌥)", "Left Option (⌥)")
        case .optionRight: L10n.text("右 Option (⌥)", "Right Option (⌥)")
        case .command: L10n.text("左 Command (⌘)", "Left Command (⌘)")
        case .commandRight: L10n.text("右 Command (⌘)", "Right Command (⌘)")
        case .control: L10n.text("左 Control (⌃)", "Left Control (⌃)")
        case .controlRight: L10n.text("右 Control (⌃)", "Right Control (⌃)")
        case .shift: L10n.text("左 Shift (⇧)", "Left Shift (⇧)")
        case .shiftRight: L10n.text("右 Shift (⇧)", "Right Shift (⇧)")
        case .function: "Fn / Globe"
        }
    }

    /// Physical keys accepted for the keyboard trigger. Both sides are
    /// accepted even when the remote synthesizes only the selected side, so a
    /// mismatch between the user's habit and the host shortcut cannot leave
    /// the audio route closed.
    var keyCodes: Set<Int64> {
        switch self {
        case .option, .optionRight: [0x3A, 0x3D]
        case .command, .commandRight: [0x37, 0x36]
        case .control, .controlRight: [0x3B, 0x3E]
        case .shift, .shiftRight: [0x38, 0x3C]
        case .function: [0x3F]
        }
    }

    /// The side synthesized for the remote voice key.
    var primaryKeyCode: CGKeyCode {
        switch self {
        case .option: 0x3A
        case .optionRight: 0x3D
        case .command: 0x37
        case .commandRight: 0x36
        case .control: 0x3B
        case .controlRight: 0x3E
        case .shift: 0x38
        case .shiftRight: 0x3C
        case .function: 0x3F
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .option, .optionRight: .maskAlternate
        case .command, .commandRight: .maskCommand
        case .control, .controlRight: .maskControl
        case .shift, .shiftRight: .maskShift
        case .function: .maskSecondaryFn
        }
    }

    /// NX device-dependent modifier bit. Some input methods (notably WeType)
    /// determine press/release of a modifier from this bit rather than the
    /// device-independent flag alone.
    var deviceFlag: CGEventFlags {
        switch self {
        case .option: CGEventFlags(rawValue: 0x20)        // left Option
        case .optionRight: CGEventFlags(rawValue: 0x40)   // right Option
        case .command: CGEventFlags(rawValue: 0x08)       // left Command
        case .commandRight: CGEventFlags(rawValue: 0x10)  // right Command
        case .control: CGEventFlags(rawValue: 0x01)       // left Control
        case .controlRight: CGEventFlags(rawValue: 0x2000) // right Control
        case .shift: CGEventFlags(rawValue: 0x02)         // left Shift
        case .shiftRight: CGEventFlags(rawValue: 0x04)    // right Shift
        case .function: []
        }
    }
}

enum Key {
    /// Lets the event tap distinguish vRemoter-generated events from physical
    /// keyboards, Bluetooth buttons, and external remappers.
    static let syntheticMarker: Int64 = 0x4D_49_52_42 // "MIRB"

    static func triggerDown(_ trigger: InputTriggerKey = AppStorage.inputTriggerKey) {
        post(trigger: trigger, keyDown: true)
    }

    static func triggerUp(_ trigger: InputTriggerKey = AppStorage.inputTriggerKey) {
        post(trigger: trigger, keyDown: false)
    }

    /// A deliberate short modifier click for toggle-mode input methods.
    static func triggerTap(
        _ trigger: InputTriggerKey = AppStorage.inputTriggerKey,
        completion: (() -> Void)? = nil
    ) {
        triggerDown(trigger)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            triggerUp(trigger)
            completion?()
        }
    }

    private static func post(trigger: InputTriggerKey, keyDown: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: trigger.primaryKeyCode,
            keyDown: keyDown
        ) else { return }
        event.flags = keyDown
            ? trigger.flag.union(trigger.deviceFlag)
            : []
        event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        event.post(tap: .cghidEventTap)
        print(
            "[KEY] synthetic \(trigger.title) " +
            (keyDown ? "DOWN" : "UP") +
            " keyCode=0x" + String(trigger.primaryKeyCode, radix: 16) +
            " flags=0x" + String(event.flags.rawValue, radix: 16)
        )
    }
}
