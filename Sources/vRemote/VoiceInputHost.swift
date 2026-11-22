import Foundation

/// A selectable voice-input application. Only `isSupported` apps can be
/// selected; the rest are placeholders for future providers.
struct VoiceInputApp: Identifiable, Hashable {
    let id: String
    let title: String
    let shortTitle: String
    let bundleID: String
    let logTag: String
    let isSupported: Bool
    let canObserveRecording: Bool
    let requiresStartConfirmation: Bool
    let requiresCloseConfirmation: Bool
    let defaultPTTShortcut: TriggerShortcut
    let defaultToggleShortcut: TriggerShortcut
}

enum VoiceInputAppCatalog {
    static let weType = VoiceInputApp(
        id: "wetype",
        title: L10n.text("微信输入法", "WeType"),
        shortTitle: L10n.text("微信输入法", "WeType"),
        bundleID: "com.tencent.inputmethod.wetype",
        logTag: "WETYPE-STATE",
        isSupported: true,
        canObserveRecording: true,
        requiresStartConfirmation: false,
        requiresCloseConfirmation: false,
        defaultPTTShortcut: .pttDefault,
        defaultToggleShortcut: .toggleDefault
    )

    /// A disabled menu row. It reserves the selector for future apps without
    /// claiming support for a provider we have not verified.
    static let more = VoiceInputApp(
        id: "more",
        title: L10n.text(
            "更多语音输入软件（即将支持）",
            "More voice input apps (coming soon)"
        ),
        shortTitle: L10n.text(
            "更多语音输入软件",
            "More voice input apps"
        ),
        bundleID: "",
        logTag: "VOICE-APP",
        isSupported: false,
        canObserveRecording: false,
        requiresStartConfirmation: true,
        requiresCloseConfirmation: true,
        defaultPTTShortcut: .pttDefault,
        defaultToggleShortcut: .toggleDefault
    )

    static let all: [VoiceInputApp] = [weType, more]

    static func app(id: String) -> VoiceInputApp {
        all.first(where: { $0.id == id }) ?? weType
    }
}

enum VoiceGestureMode: String, CaseIterable, Identifiable {
    /// The synthetic trigger stays held for the whole session.
    case pushToTalk
    /// A short synthetic tap toggles the host's voice session.
    case toggle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pushToTalk: L10n.text("按住说话", "Push to Talk")
        case .toggle: L10n.text("点按切换", "Tap to Toggle")
        }
    }
}
