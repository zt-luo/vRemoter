import Foundation

/// Which input method owns the remote voice session.
///
/// Doubao exposes a reliable CoreAudio recording state, so its sessions are
/// confirmed against the process. WeType keeps its audio engine running
/// permanently, so its process state can never confirm a recording; its
/// session is driven by the remote / keyboard gesture instead.
enum VoiceInputHost: String, CaseIterable, Identifiable, Codable {
    case doubao
    case weType

    var id: String { rawValue }

    var title: String {
        switch self {
        case .doubao: L10n.text("豆包输入法", "Doubao Input")
        case .weType: L10n.text("微信输入法", "WeType")
        }
    }

    var shortTitle: String {
        switch self {
        case .doubao: L10n.text("豆包", "Doubao")
        case .weType: L10n.text("微信输入法", "WeType")
        }
    }

    var bundleID: String {
        switch self {
        case .doubao: "com.bytedance.inputmethod.doubaoime"
        case .weType: "com.tencent.inputmethod.wetype"
        }
    }

    var logTag: String {
        switch self {
        case .doubao: "DOUBAO-STATE"
        case .weType: "WETYPE-STATE"
        }
    }

    /// Both hosts expose a usable CoreAudio recording state on current
    /// macOS. WeType is still gesture-started, but its recording state lets
    /// vRemoter open the mix even when WeType consumes the shortcut key before
    /// vRemoter's event tap sees it.
    var canObserveRecording: Bool { true }

    /// Doubao needs the one-second CoreAudio confirmation before the session
    /// is considered open. WeType's shortcut key itself is the confirmation;
    /// waiting would trip its prewarm latency.
    var requiresStartConfirmation: Bool {
        switch self {
        case .doubao: true
        case .weType: false
        }
    }

    /// WeType's push-to-talk ends on the synthetic key-up; close immediately
    /// instead of waiting for the full CoreAudio close verification.
    var requiresCloseConfirmation: Bool {
        switch self {
        case .doubao: true
        case .weType: false
        }
    }

    var gestureMode: VoiceGestureMode {
        switch self {
        case .doubao: .toggle
        case .weType: .pushToTalk
        }
    }

    /// Doubao accepts a single left Option press. WeType stores its
    /// push-to-talk shortcut as right Option by default, and its shortcut
    /// monitor distinguishes the physical side.
    var defaultTrigger: InputTriggerKey {
        switch self {
        case .doubao: .option
        case .weType: .optionRight
        }
    }

    /// Label used by the voice row on the key-mapping page.
    var voiceActionTitle: String {
        switch self {
        case .doubao: RemoteMappingTarget.doubaoVoice.title
        case .weType: L10n.text("微信输入法语音", "WeType Voice")
        }
    }
}

enum VoiceGestureMode {
    /// A short synthetic tap toggles the host's voice session.
    case toggle
    /// The synthetic trigger stays held for the whole physical gesture.
    case pushToTalk
}
