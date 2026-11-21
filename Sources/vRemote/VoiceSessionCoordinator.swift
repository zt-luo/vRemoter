import Foundation

enum VoiceRemoteID: String, CaseIterable {
    case chromecast
}

enum RemoteMicrophoneOpenResult: Equatable {
    case sent
    case alreadyStreaming
    case retryAfter(TimeInterval)
    case unavailable
    case failed(String)
}

protocol VoiceInputStateProviding: AnyObject {
    var onSnapshotChanged: ((VoiceInputStateMonitor.Snapshot) -> Void)? {
        get set
    }

    func start()
    func stop()
    func snapshotNow() -> VoiceInputStateMonitor.Snapshot
}

extension VoiceInputStateMonitor: VoiceInputStateProviding {}

/// Coordinates the input-method toggle, supported remote gestures, and each
/// remote's independent ATVV transport.
///
/// A transport START/STOP is never itself a keyboard toggle. A physical
/// keyboard trigger already reaches WeType. A remote gesture synthesizes
/// exactly one trigger only when it changes the intended recognition state.
final class VoiceSessionCoordinator {
    private enum Phase: String {
        case closed
        case opening
        case open
        case closing
    }

    private enum Owner: String {
        case none
        case remote
        case keyboard
    }

    private struct PhysicalVoiceGesture {
        let beganAt: Date
        let recognitionWasOpen: Bool
        let generation: UInt64
    }

    struct DebugSnapshot: Equatable {
        let phase: String
        let generation: UInt64
        let sessionRemote: VoiceRemoteID?
        let streamingRemotes: Set<VoiceRemoteID>
        let openRequestedRemote: VoiceRemoteID?
    }

    private static let remoteHoldThreshold: TimeInterval = 0.55
    private static let openConfirmationTimeout: TimeInterval = 1.0
    private static let closeVerificationTimeout: TimeInterval = 1.2
    private static let maximumOpenAttempts = 3

    private let voiceState: any VoiceInputStateProviding
    private let setRemoteRouteActive: (Bool, Bool) -> Void
    private let triggerTap: (InputTriggerKey) -> Void
    private let triggerDown: (InputTriggerKey) -> Void
    private let triggerUp: (InputTriggerKey) -> Void
    private let now: () -> Date

    /// WeType owns this session and is driven by the remote / keyboard gesture.
    var voiceHost: VoiceInputHost = .weType
    /// How the input method's shortcut is synthesized. WeType currently uses
    /// push-to-talk; the toggle path remains available for tap-to-continue.
    var triggerMode: VoiceGestureMode = .pushToTalk

    private var phase: Phase = .closed
    private var owner: Owner = .none
    private var generation: UInt64 = 0
    private var routeActive = false
    private var sessionRemote: VoiceRemoteID?
    private var streamingRemotes = Set<VoiceRemoteID>()
    private var openRequestedRemote: VoiceRemoteID?
    private var physicalVoiceGestures = [VoiceRemoteID: PhysicalVoiceGesture]()
    private var syntheticTriggerIsDown = false
    private var syntheticToggleIsOpen = false
    private var sessionTriggerKey: InputTriggerKey = AppStorage.activeTriggerKey
    private var sessionTriggerMode: VoiceGestureMode = .pushToTalk
    private var continuousRemoteSession = false
    private var continuousRecoveryAttempted = false
    private var continuousStopInProgress = false
    private var suppressedRemoteButtons = Set<String>()
    private var continuousIdleWorkItem: DispatchWorkItem?

    private var routeCloseWorkItem: DispatchWorkItem?
    private var startVerificationWorkItem: DispatchWorkItem?
    private var closeVerificationWorkItem: DispatchWorkItem?
    private var openRetryWorkItem: DispatchWorkItem?
    private var openConfirmationWorkItem: DispatchWorkItem?

    var preferredRemoteProvider: (() -> VoiceRemoteID?)?
    /// Called before the snapshot is applied to session logic. The UI uses it
    /// to refresh the host device summary without changing session state.
    var onSnapshotObserved: ((VoiceInputStateMonitor.Snapshot) -> Void)?
    var onMicrophoneOpenRequested:
        ((VoiceRemoteID, Bool) -> RemoteMicrophoneOpenResult)?
    var onMicrophoneCloseRequested: (() -> Void)?
    var onStateChanged: ((String) -> Void)?

    init(
        voiceState: any VoiceInputStateProviding,
        setRemoteRouteActive: @escaping (Bool, Bool) -> Void = {
            AudioPipe.shared.setRemoteActive($0, captureSecondInput: $1)
        },
        triggerTap: @escaping (InputTriggerKey) -> Void = { Key.triggerTap($0) },
        triggerDown: @escaping (InputTriggerKey) -> Void = { Key.triggerDown($0) },
        triggerUp: @escaping (InputTriggerKey) -> Void = { Key.triggerUp($0) },
        now: @escaping () -> Date = Date.init
    ) {
        self.voiceState = voiceState
        self.setRemoteRouteActive = setRemoteRouteActive
        self.triggerTap = triggerTap
        self.triggerDown = triggerDown
        self.triggerUp = triggerUp
        self.now = now
    }

    var debugSnapshot: DebugSnapshot {
        DebugSnapshot(
            phase: phase.rawValue,
            generation: generation,
            sessionRemote: sessionRemote,
            streamingRemotes: streamingRemotes,
            openRequestedRemote: openRequestedRemote
        )
    }

    func start() {
        voiceState.onSnapshotChanged = { [weak self] snapshot in
            self?.onSnapshotObserved?(snapshot)
            self?.handleVoiceSnapshot(snapshot)
        }
        voiceState.start()
    }

    // MARK: - ATVV transport

    func remoteAudioStarted(
        remote: VoiceRemoteID,
        reason: UInt8,
        supportsPhysicalHoldGesture: Bool = false
    ) {
        let snapshot = voiceState.snapshotNow()
        let inserted = streamingRemotes.insert(remote).inserted
        if inserted {
            continuousRecoveryAttempted = false
        }
        if openRequestedRemote == remote {
            openRequestedRemote = nil
            openConfirmationWorkItem?.cancel()
            openConfirmationWorkItem = nil
        }

        if phase == .closing {
            print(
                "[VOICE-SESSION] late AUDIO_START while closing " +
                "remote=\(remote.rawValue) reason=" +
                String(format: "0x%02x", reason)
            )
            closeAllRemoteTransports()
            return
        }

        if supportsPhysicalHoldGesture, reason == 0x03 {
            let recognitionWasOpen = phase == .open
                || (voiceHost.canObserveRecording && snapshot.isRecording)
            if physicalVoiceGestures[remote] == nil {
                physicalVoiceGestures[remote] = PhysicalVoiceGesture(
                    beganAt: now(),
                    recognitionWasOpen: recognitionWasOpen,
                    generation: generation
                )
            }
            print(
                "[VOICE-SESSION] physical ATVV DOWN " +
                "remote=\(remote.rawValue) " +
                "recognitionWasOpen=\(recognitionWasOpen)"
            )

            if recognitionWasOpen {
                sessionRemote = remote
                activateRemoteRoute()
                publish("遥控器按住录音中")
                return
            }
        }

        if !inserted {
            print(
                "[VOICE-SESSION] duplicate AUDIO_START ignored " +
                "remote=\(remote.rawValue) reason=" +
                String(format: "0x%02x", reason)
            )
            return
        }

        activateRemoteRoute()
        print(
            "[VOICE-SESSION] AUDIO_START remote=\(remote.rawValue) reason=" +
            String(format: "0x%02x", reason) +
            " phase=\(phase.rawValue) owner=\(owner.rawValue) " +
            "voiceBefore=\(snapshot.state.rawValue) " +
            "device=\(snapshot.deviceSummary)"
        )

        switch phase {
        case .opening, .open:
            publish(recordingStatus("遥控器已接入", "remote connected"))

        case .closed:
            // A reason-0 stream while closed can only be a stale response to
            // an earlier host request; the physical gesture uses reason 0x03.
            guard reason != 0x00 else {
                print(
                    "[VOICE-SESSION] stale host AUDIO_START ignored " +
                    "remote=\(remote.rawValue)"
                )
                closeAllRemoteTransports()
                return
            }
            beginOpening(
                owner: .remote,
                remote: remote,
                sendTrigger: true,
                requestTransportImmediately: false
            )
            // beginOpening advances the session generation. Keep the
            // in-flight physical gesture attached to that new session so its
            // matching AUDIO_STOP can complete the tap/hold decision.
            if supportsPhysicalHoldGesture,
               reason == 0x03,
               let gesture = physicalVoiceGestures[remote]
            {
                physicalVoiceGestures[remote] = PhysicalVoiceGesture(
                    beganAt: gesture.beganAt,
                    recognitionWasOpen: gesture.recognitionWasOpen,
                    generation: generation
                )
            }

        case .closing:
            break
        }
    }

    func remoteAudioStopped(remote: VoiceRemoteID, reason: UInt8) {
        streamingRemotes.remove(remote)
        if openRequestedRemote == remote {
            openRequestedRemote = nil
            openConfirmationWorkItem?.cancel()
            openConfirmationWorkItem = nil
        }

        if reason == 0x02,
           let gesture = physicalVoiceGestures.removeValue(forKey: remote)
        {
            let duration = now().timeIntervalSince(gesture.beganAt)
            let wasHold = duration >= Self.remoteHoldThreshold
            print(
                String(
                    format:
                        "[VOICE-SESSION] physical ATVV UP remote=%@ " +
                        "duration=%.3fs kind=%@ recognitionWasOpen=%@",
                    remote.rawValue,
                    duration,
                    wasHold ? "HOLD" : "TAP",
                    gesture.recognitionWasOpen ? "true" : "false"
                )
            )

            guard gesture.generation == generation else {
                print(
                    "[VOICE-SESSION] stale physical release ignored " +
                    "remote=\(remote.rawValue)"
                )
                return
            }

            if wasHold || gesture.recognitionWasOpen {
                closeRecognitionFromRemote(
                    reason: wasHold
                        ? "ATVV HOLD release"
                        : "ATVV TAP toggle"
                )
                return
            }

            // First Chromecast short tap: the physical stream ends at button
            // release. Immediately request a persistent stream from that same
            // remote. BLEBridge has already marked its local stream idle
            // before invoking this callback, so no fixed delay is necessary.
            // First short tap: keep the host session open and request a
            // persistent remote stream. A push-to-talk host keeps its
            // synthetic key held; a toggle host already got its start tap on
            // press.
            guard phase == .opening || phase == .open else { return }
            sessionRemote = remote
            continuousRemoteSession = true
            continuousRecoveryAttempted = false
            requestRemoteTransportOpen(
                remote,
                bypassDebounce: true,
                attempt: 1
            )
            publish(recordingStatus(
                "遥控器持续收音 · 短按任意键停止",
                "streaming · press any key to stop"
            ))
            return
        }

        print(
            "[VOICE-SESSION] AUDIO_STOP remote=\(remote.rawValue) reason=" +
            String(format: "0x%02x", reason) +
            " phase=\(phase.rawValue)"
        )

        // A continuous session expects the remote stream to stay alive.
        // Try one recovery before ending the host session.
        if continuousRemoteSession, streamingRemotes.isEmpty {
            if continuousRecoveryAttempted {
                continuousRecoveryAttempted = false
                beginClosing(
                    sendTrigger: true,
                    reason: "continuous stream lost"
                )
            } else {
                continuousRecoveryAttempted = true
                requestRemoteTransportOpen(
                    remote,
                    bypassDebounce: true,
                    attempt: 1
                )
            }
            return
        }

        // Do not automatically reopen a generic transport STOP. Only the
        // proven physical-tap path above performs an immediate recovery.
        if phase == .open || phase == .opening {
            publish(L10n.text(
                "\(voiceHost.shortTitle)仍开启 · 遥控器音频已停止",
                "\(voiceHost.shortTitle) still open · remote audio stopped"
            ))
        } else if streamingRemotes.isEmpty {
            scheduleRouteClose(after: 0.08)
        }
    }

    func remoteDisconnected(_ remote: VoiceRemoteID) {
        streamingRemotes.remove(remote)
        physicalVoiceGestures.removeValue(forKey: remote)
        continuousRemoteSession = false
        if openRequestedRemote == remote {
            openRequestedRemote = nil
            openRetryWorkItem?.cancel()
            openRetryWorkItem = nil
            openConfirmationWorkItem?.cancel()
            openConfirmationWorkItem = nil
        }

        guard sessionRemote == remote else { return }

        if sessionTriggerMode == .pushToTalk {
            // A disconnected remote can never deliver its release edge, so the
            // synthetic trigger must be released here instead of sticking down.
            if phase == .opening || phase == .open {
                beginClosing(
                    sendTrigger: syntheticTriggerIsDown,
                    reason: "remote disconnected"
                )
            } else {
                releaseSyntheticTrigger()
            }
            return
        }

        if syntheticToggleIsOpen {
            beginClosing(sendTrigger: true, reason: "remote disconnected")
            return
        }
        if phase == .opening || phase == .open,
           let replacement = preferredRemoteProvider?() {
            sessionRemote = replacement
            requestRemoteTransportOpen(
                replacement,
                bypassDebounce: false,
                attempt: 1
            )
        }
    }

    func remoteMicrophoneOpenFailed(remote: VoiceRemoteID, code: UInt16) {
        guard openRequestedRemote == remote,
              phase == .opening || phase == .open
        else { return }
        openRequestedRemote = nil
        openConfirmationWorkItem?.cancel()
        openConfirmationWorkItem = nil
        print(
            "[VOICE-SESSION] MIC_OPEN failed remote=\(remote.rawValue) " +
            String(format: "code=0x%04x", code)
        )
        scheduleOpenRetry(remote: remote, after: 0.20, attempt: 2)
    }

    // MARK: - Physical keyboard trigger

    /// Called before the real physical trigger reaches WeType. It updates the
    /// remote transport only; it never synthesizes a second keyboard event.
    func triggerDownObserved(isSynthetic: Bool) {
        guard !isSynthetic else { return }
        let snapshot = voiceState.snapshotNow()
        let shouldOpen: Bool
        switch phase {
        case .closed:
            // WeType always reports an active input stream, so its snapshot
            // cannot tell us whether the host is already recording.
            shouldOpen = voiceHost.canObserveRecording
                ? !snapshot.isRecording
                : true
        case .closing:
            // A second deliberate physical trigger reverses the user's last
            // intent even if CoreAudio has not published inactive yet.
            shouldOpen = true
        case .opening, .open:
            shouldOpen = false
        }

        print(
            "[TRIGGER] DOWN source=keyboard action=" +
            (shouldOpen ? "open" : "close") +
            " phase=\(phase.rawValue) " +
            "voiceBefore=\(snapshot.state.rawValue) " +
            "device=\(snapshot.deviceSummary)"
        )

        if shouldOpen {
            guard let remote = preferredRemoteProvider?() else {
                beginOpeningWithoutRemote()
                return
            }
            beginOpening(
                owner: .keyboard,
                remote: remote,
                sendTrigger: false,
                requestTransportImmediately: false
            )
        } else {
            beginClosing(sendTrigger: false, reason: "keyboard trigger")
        }
    }

    func triggerUpObserved(isSynthetic: Bool) {
        guard !isSynthetic else { return }
        print(
            "[TRIGGER] UP source=keyboard phase=\(phase.rawValue) " +
            "owner=\(owner.rawValue)"
        )
        if sessionTriggerMode == .toggle {
            // The physical key itself toggled WeType; key-up must not close.
            reconcileSoon(after: 0.03)
            reconcileSoon(after: 0.15)
            return
        }
        if voiceHost == .weType {
            // The physical key-up already reached WeType. If its recording
            // state is already idle, close now; otherwise let the snapshot
            // callback close when WeType stops.
            if phase == .opening || phase == .open {
                if voiceState.snapshotNow().isRecording {
                    reconcileSoon(after: 0.03)
                    reconcileSoon(after: 0.15)
                } else {
                    beginClosing(
                        sendTrigger: false,
                        reason: "keyboard trigger up"
                    )
                }
            }
            return
        }
        reconcileSoon(after: 0.03)
        reconcileSoon(after: 0.15)
    }

    // MARK: - Lifecycle / manual control

    func forceClose() {
        generation &+= 1
        cancelScheduledWork()
        stopSyntheticToggleIfNeeded()
        releaseSyntheticTrigger()
        phase = .closed
        owner = .none
        sessionRemote = nil
        physicalVoiceGestures.removeAll()
        continuousRemoteSession = false
        continuousStopInProgress = false
        closeRouteAndTransports()
        publish("已手动关闭")
    }

    func stop() {
        forceClose()
        voiceState.stop()
    }

    // MARK: - Voice input observation

    private func handleVoiceSnapshot(
        _ snapshot: VoiceInputStateMonitor.Snapshot
    ) {
        switch snapshot.state {
        case .active:
            switch phase {
            case .opening:
                startVerificationWorkItem?.cancel()
                startVerificationWorkItem = nil
                phase = .open
                activateRemoteRoute()
                if let remote = sessionRemote,
                   !streamingRemotes.contains(remote),
                   openRequestedRemote != remote
                {
                    requestRemoteTransportOpen(
                        remote,
                        bypassDebounce: false,
                        attempt: 1
                    )
                }
                publish(recordingStatus(
                    snapshot.deviceSummary,
                    snapshot.deviceSummary
                ))

            case .open:
                activateRemoteRoute()
                publish(recordingStatus(
                    snapshot.deviceSummary,
                    snapshot.deviceSummary
                ))

            case .closing:
                // CoreAudio can remain active briefly after the trigger has
                // toggled the host off. Never reinterpret this stale edge as a
                // fresh external opening.
                print(
                    "[VOICE-SESSION] active snapshot ignored while closing"
                )

            case .closed:
                adoptExternalActivation(snapshot)
            }

        case .inactive:
            switch phase {
            case .opening:
                // The opening verification owns this transient idle window.
                break
            case .open, .closing:
                if voiceHost == .weType,
                   syntheticTriggerIsDown,
                   phase == .open {
                    // WeType can briefly report idle while capture warms up.
                    // Keep the mix open while the push-to-talk key is held.
                    if continuousRemoteSession {
                        scheduleContinuousIdleCheck()
                    }
                    return
                }
                finalizeClosed(reason: "\(voiceHost.shortTitle) inactive")
            case .closed:
                if routeActive || !streamingRemotes.isEmpty {
                    closeRouteAndTransports()
                }
            }
            publish(L10n.text(
                "\(voiceHost.shortTitle)已就绪",
                "\(voiceHost.shortTitle) ready"
            ))

        case .unavailable:
            if phase != .opening {
                finalizeClosed(reason: "\(voiceHost.shortTitle) unavailable")
            }
            publish(L10n.text(
                "等待\(voiceHost.shortTitle)",
                "Waiting for \(voiceHost.shortTitle)"
            ))
        }
    }

    private func adoptExternalActivation(
        _ snapshot: VoiceInputStateMonitor.Snapshot
    ) {
        generation &+= 1
        cancelScheduledWork()
        phase = .open
        owner = .keyboard
        sessionRemote = preferredRemoteProvider?()
        activateRemoteRoute()
        print(
            "[VOICE-SESSION] \(voiceHost.shortTitle) external activation " +
            "adopted device=\(snapshot.deviceSummary)"
        )
        publish(recordingStatus(
            snapshot.deviceSummary,
            snapshot.deviceSummary
        ))
    }

    // MARK: - State transitions

    private func beginOpeningWithoutRemote() {
        generation &+= 1
        cancelScheduledWork()
        phase = .opening
        owner = .keyboard
        sessionRemote = nil
        activateRemoteRoute()
        publish(L10n.text(
            "\(voiceHost.shortTitle)正在启动 · 等待遥控器",
            "\(voiceHost.shortTitle) starting · waiting for remote"
        ))
        scheduleStartVerification(for: generation)
    }

    private func beginOpening(
        owner: Owner,
        remote: VoiceRemoteID,
        sendTrigger: Bool,
        requestTransportImmediately: Bool
    ) {
        generation &+= 1
        cancelScheduledWork()
        phase = .opening
        self.owner = owner
        sessionRemote = remote
        sessionTriggerKey = AppStorage.activeTriggerKey
        sessionTriggerMode = triggerMode
        activateRemoteRoute()
        if sendTrigger {
            switch sessionTriggerMode {
            case .pushToTalk:
                if !syntheticTriggerIsDown {
                    syntheticTriggerIsDown = true
                    triggerDown(sessionTriggerKey)
                }
            case .toggle:
                triggerTap(sessionTriggerKey)
                syntheticToggleIsOpen = true
            }
        }
        if requestTransportImmediately {
            requestRemoteTransportOpen(
                remote,
                bypassDebounce: false,
                attempt: 1
            )
        }
        publish(
            owner == .keyboard
                ? L10n.text(
                    "\(voiceHost.shortTitle)正在启动 · 遥控器已预热",
                    "\(voiceHost.shortTitle) starting · remote ready"
                )
                : L10n.text(
                    "遥控器已启动 · 正在打开\(voiceHost.shortTitle)",
                    "Remote started · opening \(voiceHost.shortTitle)"
                )
        )
        scheduleStartVerification(for: generation)
    }

    private func closeRecognitionFromRemote(reason: String) {
        guard phase == .opening || phase == .open else {
            print(
                "[VOICE-SESSION] \(reason) ignored phase=\(phase.rawValue)"
            )
            return
        }
        beginClosing(sendTrigger: true, reason: reason)
    }

    private func beginClosing(sendTrigger: Bool, reason: String) {
        guard phase != .closed, phase != .closing else {
            print(
                "[VOICE-SESSION] close ignored phase=\(phase.rawValue) " +
                "reason=\(reason)"
            )
            return
        }

        generation &+= 1
        cancelScheduledWork()
        phase = .closing
        owner = .none
        openRequestedRemote = nil
        continuousRemoteSession = false
        continuousIdleWorkItem?.cancel()
        continuousIdleWorkItem = nil
        if sendTrigger {
            switch sessionTriggerMode {
            case .pushToTalk:
                releaseSyntheticTrigger()
            case .toggle:
                triggerTap(sessionTriggerKey)
                syntheticToggleIsOpen = false
            }
        } else {
            // A physical shortcut already toggled the host; never send a
            // second synthetic tap on close.
            syntheticToggleIsOpen = false
        }
        scheduleRouteClose(after: 0.10)
        scheduleCloseVerification(for: generation)
        publish(L10n.text(
            "遥控器已结束 · 正在关闭\(voiceHost.shortTitle)",
            "Remote ended · closing \(voiceHost.shortTitle)"
        ))
        print(
            "[VOICE-SESSION] begin closing reason=\(reason) " +
            "trigger=\(sendTrigger ? "synthetic" : "physical")"
        )
    }

    private func finalizeClosed(reason: String) {
        generation &+= 1
        cancelScheduledWork()
        stopSyntheticToggleIfNeeded()
        releaseSyntheticTrigger()
        phase = .closed
        owner = .none
        sessionRemote = nil
        physicalVoiceGestures.removeAll()
        continuousRemoteSession = false
        continuousStopInProgress = false
        closeRouteAndTransports()
        print("[VOICE-SESSION] closed reason=\(reason)")
    }

    private func stopSyntheticToggleIfNeeded() {
        guard syntheticToggleIsOpen else { return }
        syntheticToggleIsOpen = false
        triggerTap(sessionTriggerKey)
    }

    private func releaseSyntheticTrigger() {
        guard syntheticTriggerIsDown else { return }
        syntheticTriggerIsDown = false
        triggerUp(sessionTriggerKey)
    }

    // MARK: - Remote transport requests

    private func requestRemoteTransportOpen(
        _ remote: VoiceRemoteID,
        bypassDebounce: Bool,
        attempt: Int
    ) {
        guard phase == .opening || phase == .open,
              !streamingRemotes.contains(remote),
              openRequestedRemote != remote
        else { return }

        guard let request = onMicrophoneOpenRequested else {
            print(
                "[VOICE-SESSION] MIC_OPEN unavailable " +
                "remote=\(remote.rawValue)"
            )
            return
        }

        let result = request(remote, bypassDebounce)
        switch result {
        case .sent:
            openRequestedRemote = remote
            scheduleOpenConfirmation(
                remote: remote,
                attempt: attempt,
                generation: generation
            )
            print(
                "[VOICE-SESSION] MIC_OPEN sent remote=\(remote.rawValue) " +
                "attempt=\(attempt)"
            )

        case .alreadyStreaming:
            streamingRemotes.insert(remote)
            openRequestedRemote = nil
            print(
                "[VOICE-SESSION] MIC_OPEN already streaming " +
                "remote=\(remote.rawValue)"
            )

        case .retryAfter(let delay):
            scheduleOpenRetry(
                remote: remote,
                after: delay,
                attempt: attempt + 1
            )

        case .unavailable:
            print(
                "[VOICE-SESSION] MIC_OPEN target unavailable " +
                "remote=\(remote.rawValue)"
            )

        case .failed(let message):
            print(
                "[VOICE-SESSION] MIC_OPEN failed remote=\(remote.rawValue) " +
                "message=\(message)"
            )
            scheduleOpenRetry(
                remote: remote,
                after: 0.20,
                attempt: attempt + 1
            )
        }
    }

    private func scheduleOpenRetry(
        remote: VoiceRemoteID,
        after delay: TimeInterval,
        attempt: Int
    ) {
        guard attempt <= Self.maximumOpenAttempts else {
            print(
                "[VOICE-SESSION] MIC_OPEN retries exhausted " +
                "remote=\(remote.rawValue)"
            )
            return
        }
        openRetryWorkItem?.cancel()
        let expectedGeneration = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.generation == expectedGeneration,
                  self.phase == .opening || self.phase == .open
            else { return }
            self.openRetryWorkItem = nil
            self.requestRemoteTransportOpen(
                remote,
                bypassDebounce: true,
                attempt: attempt
            )
        }
        openRetryWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0.01, delay),
            execute: work
        )
    }

    private func scheduleOpenConfirmation(
        remote: VoiceRemoteID,
        attempt: Int,
        generation expectedGeneration: UInt64
    ) {
        openConfirmationWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.generation == expectedGeneration,
                  self.openRequestedRemote == remote,
                  !self.streamingRemotes.contains(remote),
                  self.phase == .opening || self.phase == .open
            else { return }
            self.openRequestedRemote = nil
            self.openConfirmationWorkItem = nil
            print(
                "[VOICE-SESSION] MIC_OPEN confirmation timeout " +
                "remote=\(remote.rawValue) attempt=\(attempt)"
            )
            self.scheduleOpenRetry(
                remote: remote,
                after: 0.05,
                attempt: attempt + 1
            )
        }
        openConfirmationWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.openConfirmationTimeout,
            execute: work
        )
    }

    // MARK: - Verification and route lifecycle

    private func scheduleStartVerification(for expectedGeneration: UInt64) {
        startVerificationWorkItem?.cancel()
        startVerificationWorkItem = nil
        guard voiceHost.requiresStartConfirmation else {
            // WeType's shortcut key is the confirmation. Do not run the
            // one-second CoreAudio timeout while its capture prewarms.
            guard generation == expectedGeneration, phase == .opening else {
                return
            }
            phase = .open
            publish(L10n.text(
                "\(voiceHost.shortTitle)录音中 · 遥控器已接入",
                "\(voiceHost.shortTitle) recording · remote connected"
            ))
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.generation == expectedGeneration,
                  self.phase == .opening
            else { return }
            self.startVerificationWorkItem = nil
            let snapshot = self.voiceState.snapshotNow()
            if snapshot.isRecording {
                self.handleVoiceSnapshot(snapshot)
                return
            }
            self.finalizeClosed(reason: "opening timeout")
            self.publish(L10n.text(
                "\(self.voiceHost.shortTitle)未启动 · 遥控器自动关闭",
                "\(self.voiceHost.shortTitle) did not start · remote closed"
            ))
        }
        startVerificationWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func scheduleCloseVerification(for expectedGeneration: UInt64) {
        closeVerificationWorkItem?.cancel()
        closeVerificationWorkItem = nil
        guard voiceHost.requiresCloseConfirmation else {
            // The synthetic key-up has been posted; close now instead of
            // waiting for the host's CoreAudio state to settle.
            guard generation == expectedGeneration, phase == .closing else {
                return
            }
            finalizeClosed(reason: "host close")
            publish(L10n.text("已就绪", "Ready"))
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.generation == expectedGeneration,
                  self.phase == .closing
            else { return }
            self.closeVerificationWorkItem = nil
            let snapshot = self.voiceState.snapshotNow()
            if snapshot.isRecording {
                // The requested close did not become observable. Follow the
                // real CoreAudio state without synthesizing another trigger.
                self.phase = .open
                self.owner = .keyboard
                self.sessionRemote = self.preferredRemoteProvider?()
                self.activateRemoteRoute()
                if let remote = self.sessionRemote {
                    self.requestRemoteTransportOpen(
                        remote,
                        bypassDebounce: false,
                        attempt: 1
                    )
                }
                self.publish(L10n.text(
                    "\(self.voiceHost.shortTitle)仍在录音 · 请再次关闭",
                    "\(self.voiceHost.shortTitle) still recording · close again"
                ))
                print(
                    "[VOICE-SESSION] close not observed; restored open state"
                )
            } else {
                self.finalizeClosed(reason: "close verification")
                self.publish(L10n.text("已就绪", "Ready"))
            }
        }
        closeVerificationWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.closeVerificationTimeout,
            execute: work
        )
    }

    private func reconcileSoon(after delay: TimeInterval) {
        let expectedGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.generation == expectedGeneration else { return }
            self.handleVoiceSnapshot(self.voiceState.snapshotNow())
        }
    }

    private func activateRemoteRoute() {
        routeCloseWorkItem?.cancel()
        routeCloseWorkItem = nil
        let captureSecond = owner == .keyboard
        if routeActive {
            // The owner can change while the route is already open (for
            // example a keyboard session followed by a remote press). Refresh
            // the second-input decision without resetting the route.
            setRemoteRouteActive(true, captureSecond)
            return
        }
        routeActive = true
        setRemoteRouteActive(true, captureSecond)
        print(
            "[VOICE-SESSION] audio route ON phase=\(phase.rawValue) " +
            "owner=\(owner.rawValue) captureSecond=\(captureSecond)"
        )
    }

    private func scheduleRouteClose(after delay: TimeInterval) {
        routeCloseWorkItem?.cancel()
        let expectedGeneration = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == expectedGeneration else { return }
            self.routeCloseWorkItem = nil
            self.closeRouteAndTransports()
        }
        routeCloseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func closeAllRemoteTransports() {
        onMicrophoneCloseRequested?()
        streamingRemotes.removeAll()
        openRequestedRemote = nil
        openRetryWorkItem?.cancel()
        openRetryWorkItem = nil
        openConfirmationWorkItem?.cancel()
        openConfirmationWorkItem = nil
        continuousIdleWorkItem?.cancel()
        continuousIdleWorkItem = nil
    }

    private func closeRouteAndTransports() {
        let hadTransport =
            !streamingRemotes.isEmpty || openRequestedRemote != nil
        routeActive = false
        setRemoteRouteActive(false, false)
        if hadTransport {
            closeAllRemoteTransports()
        }
        print("[VOICE-SESSION] audio route OFF")
    }

    private func cancelScheduledWork() {
        routeCloseWorkItem?.cancel()
        routeCloseWorkItem = nil
        startVerificationWorkItem?.cancel()
        startVerificationWorkItem = nil
        closeVerificationWorkItem?.cancel()
        closeVerificationWorkItem = nil
        openRetryWorkItem?.cancel()
        openRetryWorkItem = nil
        openConfirmationWorkItem?.cancel()
        openConfirmationWorkItem = nil
        continuousIdleWorkItem?.cancel()
        continuousIdleWorkItem = nil
    }

    /// A short press of any remote button ends a continuous session. The key
    /// is swallowed so its mapping never fires.
    func handleRemoteButtonDuringContinuous(
        button: RemoteButtonDefinition,
        remote: SupportedRemoteID,
        isDown: Bool
    ) -> Bool {
        guard remote.rawValue == VoiceRemoteID.chromecast.rawValue else {
            return false
        }
        if suppressedRemoteButtons.contains(button.id) {
            if !isDown { suppressedRemoteButtons.remove(button.id) }
            return true
        }
        if continuousStopInProgress {
            if isDown {
                suppressedRemoteButtons.insert(button.id)
            } else {
                suppressedRemoteButtons.remove(button.id)
            }
            return true
        }
        guard continuousRemoteSession,
              phase == .opening || phase == .open
        else { return false }
        guard isDown else { return false }
        suppressedRemoteButtons.insert(button.id)
        continuousRemoteSession = false
        continuousStopInProgress = true
        print("[VOICE-SESSION] continuous stop by button=\(button.id)")
        closeRecognitionFromRemote(reason: "remote button \(button.id)")
        return true
    }

    private func scheduleContinuousIdleCheck() {
        continuousIdleWorkItem?.cancel()
        let expectedGeneration = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.generation == expectedGeneration,
                  self.continuousRemoteSession,
                  self.phase == .open,
                  !self.voiceState.snapshotNow().isRecording
            else { return }
            self.continuousIdleWorkItem = nil
            print("[VOICE-SESSION] WeType idle during continuous session")
            self.beginClosing(
                sendTrigger: true,
                reason: "WeType idle during continuous"
            )
        }
        continuousIdleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func recordingStatus(_ suffixZH: String, _ suffixEN: String) -> String {
        L10n.text(
            "\(voiceHost.shortTitle)录音中 · \(suffixZH)",
            "\(voiceHost.shortTitle) recording · \(suffixEN)"
        )
    }

    private func publish(_ status: String) {
        onStateChanged?(status)
    }
}
