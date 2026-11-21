import Foundation

/// The input method that owns the remote voice session.
enum VoiceInputHost: String, CaseIterable, Identifiable, Codable {
    case weType

    var id: String { rawValue }

    var title: String { L10n.text("微信输入法", "WeType") }
    var shortTitle: String { L10n.text("微信输入法", "WeType") }
    var bundleID: String { "com.tencent.inputmethod.wetype" }
    var logTag: String { "WETYPE-STATE" }

    /// WeType exposes its CoreAudio recording state. Its shortcut is still the
    /// authoritative start/stop signal, but the state lets vRemoter open the
    /// mix when WeType consumes the shortcut before the event tap sees it.
    var canObserveRecording: Bool { true }

    /// WeType's shortcut key itself is the confirmation; waiting one second
    /// would trip its prewarm latency.
    var requiresStartConfirmation: Bool { false }

    /// WeType's push-to-talk ends on the synthetic key-up; close immediately
    /// instead of waiting for the full CoreAudio close verification.
    var requiresCloseConfirmation: Bool { false }

    var gestureMode: VoiceGestureMode { .pushToTalk }

    /// WeType stores its push-to-talk shortcut as right Option by default,
    /// and its shortcut monitor distinguishes the physical side.
    var defaultTrigger: InputTriggerKey { .optionRight }

    /// Label used by the voice row on the key-mapping page.
    var voiceActionTitle: String {
        RemoteMappingTarget.weTypeVoice.title
    }
}

enum VoiceGestureMode {
    /// A short synthetic tap toggles the host's voice session.
    case toggle
    /// The synthetic trigger stays held for the whole physical gesture.
    case pushToTalk
}
