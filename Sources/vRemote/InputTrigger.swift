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

    /// WeType stores its shortcut per side, and the two modes may use
    /// opposite sides of the same modifier. Accept only the selected side.
    func matchesPhysicalKeyCode(_ keyCode: Int64) -> Bool {
        Int64(primaryKeyCode) == keyCode
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

    var shortcut: TriggerShortcut {
        TriggerShortcut(self)
    }
}

/// One modifier key with its explicit side. A shortcut can contain several.
struct TriggerModifier: Codable, Hashable {
    let keyCode: CGKeyCode
    let flag: CGEventFlags
    let deviceFlag: CGEventFlags

    enum CodingKeys: String, CodingKey {
        case keyCode
        case flagRaw
        case deviceRaw
    }

    init(keyCode: CGKeyCode, flag: CGEventFlags, deviceFlag: CGEventFlags) {
        self.keyCode = keyCode
        self.flag = flag
        self.deviceFlag = deviceFlag
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = CGKeyCode(try values.decode(UInt16.self, forKey: .keyCode))
        flag = CGEventFlags(
            rawValue: try values.decode(UInt64.self, forKey: .flagRaw)
        )
        deviceFlag = CGEventFlags(
            rawValue: try values.decode(UInt64.self, forKey: .deviceRaw)
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(UInt16(keyCode), forKey: .keyCode)
        try values.encode(flag.rawValue, forKey: .flagRaw)
        try values.encode(deviceFlag.rawValue, forKey: .deviceRaw)
    }

    static func == (lhs: TriggerModifier, rhs: TriggerModifier) -> Bool {
        lhs.keyCode == rhs.keyCode
            && lhs.flag.rawValue == rhs.flag.rawValue
            && lhs.deviceFlag.rawValue == rhs.deviceFlag.rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(flag.rawValue)
        hasher.combine(deviceFlag.rawValue)
    }

    var symbol: String {
        if flag.contains(.maskCommand) { return "⌘" }
        if flag.contains(.maskAlternate) { return "⌥" }
        if flag.contains(.maskControl) { return "⌃" }
        if flag.contains(.maskShift) { return "⇧" }
        if flag.contains(.maskSecondaryFn) { return "Fn" }
        return "?"
    }

    var title: String {
        switch keyCode {
        case 0x3A: L10n.text("左 Option (⌥)", "Left Option (⌥)")
        case 0x3D: L10n.text("右 Option (⌥)", "Right Option (⌥)")
        case 0x37: L10n.text("左 Command (⌘)", "Left Command (⌘)")
        case 0x36: L10n.text("右 Command (⌘)", "Right Command (⌘)")
        case 0x3B: L10n.text("左 Control (⌃)", "Left Control (⌃)")
        case 0x3E: L10n.text("右 Control (⌃)", "Right Control (⌃)")
        case 0x38: L10n.text("左 Shift (⇧)", "Left Shift (⇧)")
        case 0x3C: L10n.text("右 Shift (⇧)", "Right Shift (⇧)")
        case 0x3F: "Fn / Globe"
        default: "Modifier 0x\(String(keyCode, radix: 16))"
        }
    }

    static let optionLeft = TriggerModifier(
        keyCode: 0x3A, flag: .maskAlternate, deviceFlag: CGEventFlags(rawValue: 0x20)
    )
    static let optionRight = TriggerModifier(
        keyCode: 0x3D, flag: .maskAlternate, deviceFlag: CGEventFlags(rawValue: 0x40)
    )
    static let commandLeft = TriggerModifier(
        keyCode: 0x37, flag: .maskCommand, deviceFlag: CGEventFlags(rawValue: 0x08)
    )
    static let commandRight = TriggerModifier(
        keyCode: 0x36, flag: .maskCommand, deviceFlag: CGEventFlags(rawValue: 0x10)
    )
    static let controlLeft = TriggerModifier(
        keyCode: 0x3B, flag: .maskControl, deviceFlag: CGEventFlags(rawValue: 0x01)
    )
    static let controlRight = TriggerModifier(
        keyCode: 0x3E, flag: .maskControl, deviceFlag: CGEventFlags(rawValue: 0x2000)
    )
    static let shiftLeft = TriggerModifier(
        keyCode: 0x38, flag: .maskShift, deviceFlag: CGEventFlags(rawValue: 0x02)
    )
    static let shiftRight = TriggerModifier(
        keyCode: 0x3C, flag: .maskShift, deviceFlag: CGEventFlags(rawValue: 0x04)
    )
    static let function = TriggerModifier(
        keyCode: 0x3F, flag: .maskSecondaryFn, deviceFlag: []
    )
}

/// A voice trigger is either one modifier key, a single key, or a shortcut.
struct TriggerShortcut: Codable, Hashable {
    /// `nil` means the shortcut is a single modifier key.
    let keyCode: CGKeyCode?
    /// Sorted by key code for stable equality.
    let modifiers: [TriggerModifier]

    init(keyCode: CGKeyCode?, modifiers: [TriggerModifier]) {
        self.keyCode = keyCode
        self.modifiers = modifiers.sorted { $0.keyCode < $1.keyCode }
    }

    init(_ key: InputTriggerKey) {
        let modifier: TriggerModifier
        switch key {
        case .option: modifier = .optionLeft
        case .optionRight: modifier = .optionRight
        case .command: modifier = .commandLeft
        case .commandRight: modifier = .commandRight
        case .control: modifier = .controlLeft
        case .controlRight: modifier = .controlRight
        case .shift: modifier = .shiftLeft
        case .shiftRight: modifier = .shiftRight
        case .function: modifier = .function
        }
        self.init(keyCode: nil, modifiers: [modifier])
    }

    var isModifierOnly: Bool { keyCode == nil }

    var flags: CGEventFlags {
        modifiers.reduce(into: CGEventFlags()) { $0.formUnion($1.flag) }
    }

    var deviceFlags: CGEventFlags {
        modifiers.reduce(into: CGEventFlags()) { $0.formUnion($1.deviceFlag) }
    }

    var label: String {
        if isModifierOnly, let modifier = modifiers.first {
            return modifier.title
        }
        let prefix = modifiers.map(\.symbol).joined()
        let key = Self.keyTitle(keyCode ?? 0)
        return prefix.isEmpty ? key : "\(prefix) \(key)"
    }

    /// Exact modifier set (device-independent) for a physical key event.
    func matchesKeyEvent(keyCode eventKeyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard let keyCode, keyCode == eventKeyCode else { return false }
        let required = flagsOf(modifiers)
        let relevantMask: CGEventFlags = [
            .maskCommand, .maskAlternate, .maskControl, .maskShift,
            .maskSecondaryFn
        ]
        let relevant = flags.intersection(relevantMask)
        return relevant == required
    }

    /// Modifier-only shortcut matches a `flagsChanged` key code.
    func matchesModifierKeyCode(_ eventKeyCode: Int64) -> Bool {
        guard isModifierOnly, let modifier = modifiers.first else { return false }
        return Int64(modifier.keyCode) == eventKeyCode
    }

    private func flagsOf(_ list: [TriggerModifier]) -> CGEventFlags {
        list.reduce(into: CGEventFlags()) { $0.formUnion($1.flag) }
    }

    static func keyTitle(_ keyCode: CGKeyCode) -> String {
        switch keyCode {
        case 0x31: "Space"
        case 0x24: "Return"
        case 0x30: "Tab"
        case 0x35: "Escape"
        case 0x33: "Delete"
        case 0x7E: "↑"
        case 0x7D: "↓"
        case 0x7B: "←"
        case 0x7C: "→"
        case 0x73: "Home"
        case 0x77: "End"
        case 0x74: "Page Up"
        case 0x79: "Page Down"
        default: "Key 0x\(String(keyCode, radix: 16))"
        }
    }

    static func modifier(for keyCode: CGKeyCode) -> TriggerModifier? {
        switch keyCode {
        case 0x3A: .optionLeft
        case 0x3D: .optionRight
        case 0x37: .commandLeft
        case 0x36: .commandRight
        case 0x3B: .controlLeft
        case 0x3E: .controlRight
        case 0x38: .shiftLeft
        case 0x3C: .shiftRight
        case 0x3F: .function
        default: nil
        }
    }

    static let pttDefault = TriggerShortcut(.optionRight)
    static let toggleDefault = TriggerShortcut(.option)
}

enum Key {
    /// Lets the event tap distinguish vRemoter-generated events from physical
    /// keyboards, Bluetooth buttons, and external remappers.
    static let syntheticMarker: Int64 = 0x4D_49_52_42 // "MIRB"

    static func triggerDown(_ shortcut: TriggerShortcut) {
        post(shortcut: shortcut, keyDown: true)
    }

    static func triggerUp(_ shortcut: TriggerShortcut) {
        post(shortcut: shortcut, keyDown: false)
    }

    /// A deliberate short click for toggle-mode input methods.
    static func triggerTap(
        _ shortcut: TriggerShortcut,
        completion: (() -> Void)? = nil
    ) {
        triggerDown(shortcut)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            triggerUp(shortcut)
            completion?()
        }
    }

    private static func post(shortcut: TriggerShortcut, keyDown: Bool) {
        if let keyCode = shortcut.keyCode {
            if keyDown {
                for modifier in shortcut.modifiers {
                    postKey(
                        modifier.keyCode,
                        flags: modifier.flag.union(modifier.deviceFlag),
                        keyDown: true
                    )
                }
                postKey(
                    keyCode,
                    flags: shortcut.flags.union(shortcut.deviceFlags),
                    keyDown: true
                )
            } else {
                postKey(
                    keyCode,
                    flags: shortcut.flags.union(shortcut.deviceFlags),
                    keyDown: false
                )
                for modifier in shortcut.modifiers.reversed() {
                    postKey(modifier.keyCode, flags: [], keyDown: false)
                }
            }
            return
        }
        guard let modifier = shortcut.modifiers.first else { return }
        postKey(
            modifier.keyCode,
            flags: keyDown ? modifier.flag.union(modifier.deviceFlag) : [],
            keyDown: keyDown
        )
    }

    private static func postKey(
        _ keyCode: CGKeyCode,
        flags: CGEventFlags,
        keyDown: Bool
    ) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: keyDown
        ) else { return }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        event.post(tap: .cghidEventTap)
        print(
            "[KEY] synthetic keyCode=0x" + String(keyCode, radix: 16) +
            " " + (keyDown ? "DOWN" : "UP") +
            " flags=0x" + String(event.flags.rawValue, radix: 16)
        )
    }
}
