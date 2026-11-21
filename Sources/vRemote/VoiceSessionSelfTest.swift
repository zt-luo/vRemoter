#if DEBUG
import CoreAudio
import Foundation

enum VoiceSessionSelfTest {
    private final class FakeVoiceInputState: VoiceInputStateProviding {
        var onSnapshotChanged: ((VoiceInputStateMonitor.Snapshot) -> Void)?
        private(set) var snapshot: VoiceInputStateMonitor.Snapshot

        init(state: VoiceInputStateMonitor.State = .inactive) {
            snapshot = Self.makeSnapshot(state)
        }

        func start() {}
        func stop() {}

        func snapshotNow() -> VoiceInputStateMonitor.Snapshot {
            snapshot
        }

        func emit(_ state: VoiceInputStateMonitor.State) {
            snapshot = Self.makeSnapshot(state)
            onSnapshotChanged?(snapshot)
        }

        private static func makeSnapshot(
            _ state: VoiceInputStateMonitor.State
        ) -> VoiceInputStateMonitor.Snapshot {
            VoiceInputStateMonitor.Snapshot(
                state: state,
                pid: 123,
                processObjectID: 456,
                inputDeviceIDs: state == .active ? [789] : [],
                inputDeviceNames: state == .active ? ["vRemoteDr 2ch"] : []
            )
        }
    }

    private final class Harness {
        let voiceState: FakeVoiceInputState
        let coordinator: VoiceSessionCoordinator
        var clock = Date(timeIntervalSince1970: 1_000)
        var triggerTapCount = 0
        var triggerDownCount = 0
        var triggerUpCount = 0
        var routeChanges = [Bool]()
        var routeCaptureFlags = [Bool]()
        var openRequests = [(VoiceRemoteID, Bool)]()
        var closeRequestCount = 0
        var openResults = [RemoteMicrophoneOpenResult]()
        var preferredRemote: VoiceRemoteID? = .chromecast

        init(initialState: VoiceInputStateMonitor.State = .inactive) {
            voiceState = FakeVoiceInputState(state: initialState)
            var routeSink: ((Bool, Bool) -> Void)?
            var triggerSink: (() -> Void)?
            var triggerDownSink: (() -> Void)?
            var triggerUpSink: (() -> Void)?
            var nowSink: (() -> Date)?
            coordinator = VoiceSessionCoordinator(
                voiceState: voiceState,
                setRemoteRouteActive: { routeSink?($0, $1) },
                triggerTap: { triggerSink?() },
                triggerDown: { triggerDownSink?() },
                triggerUp: { triggerUpSink?() },
                now: { nowSink?() ?? Date(timeIntervalSince1970: 0) }
            )
            coordinator.triggerMode = .toggle
            routeSink = { [weak self] active, captureSecond in
                self?.routeChanges.append(active)
                self?.routeCaptureFlags.append(captureSecond)
            }
            triggerSink = { [weak self] in
                self?.triggerTapCount += 1
            }
            triggerDownSink = { [weak self] in
                self?.triggerDownCount += 1
            }
            triggerUpSink = { [weak self] in
                self?.triggerUpCount += 1
            }
            nowSink = { [weak self] in
                self?.clock ?? Date(timeIntervalSince1970: 0)
            }
            coordinator.preferredRemoteProvider = { [weak self] in
                self?.preferredRemote
            }
            coordinator.onMicrophoneOpenRequested = {
                [weak self] remote, bypass in
                guard let self else { return .unavailable }
                self.openRequests.append((remote, bypass))
                return self.openResults.isEmpty
                    ? .sent
                    : self.openResults.removeFirst()
            }
            coordinator.onMicrophoneCloseRequested = { [weak self] in
                self?.closeRequestCount += 1
            }
            coordinator.start()
        }

        func advance(_ seconds: TimeInterval) {
            clock = clock.addingTimeInterval(seconds)
        }

        func beginChromecastPress() {
            coordinator.remoteAudioStarted(
                remote: .chromecast,
                reason: 0x03,
                supportsPhysicalHoldGesture: true
            )
        }

        func endChromecastPress() {
            coordinator.remoteAudioStopped(remote: .chromecast, reason: 0x02)
        }
    }

    private final class CheckContext {
        private(set) var failures = 0

        func expect(
            _ condition: @autoclosure () -> Bool,
            _ message: String
        ) {
            if condition() {
                VoiceSessionSelfTest.emit("[SELF-TEST] PASS \(message)")
            } else {
                failures += 1
                VoiceSessionSelfTest.emit("[SELF-TEST] FAIL \(message)")
            }
        }
    }

    private static func emit(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    static func run() -> Bool {
        let checks = CheckContext()
        testActiveBeforeRelease(checks)
        testStopBeforeActive(checks)
        testSecondTapCloses(checks)
        testLongPressCloses(checks)
        testKeyboardOpenRemoteClose(checks)
        testRemoteOpenKeyboardClose(checks)
        testChromecastReasonZeroWhileClosedIsIgnored(checks)
        testDebouncedRetry(checks)
        testWeTypeHoldSurvivesStartVerification(checks)
        testWeTypeKeyboardHoldCloses(checks)
        testWeTypeAdoptsExternalRecording(checks)
        testWeTypeShortTapDoesNotReopen(checks)
        testRemoteSessionDoesNotCaptureSecondInput(checks)
        testKeyboardSessionCapturesSecondInput(checks)
        testForceCloseReleasesWeTypeTrigger(checks)
        testTriggerDeviceFlags(checks)
        testRepeatableTargets(checks)
        emit("[SELF-TEST] completed failures=\(checks.failures)")
        return checks.failures == 0
    }

    private static func testActiveBeforeRelease(_ c: CheckContext) {
        let h = Harness()
        h.beginChromecastPress()
        h.voiceState.emit(.active)
        c.expect(h.openRequests.isEmpty, "active-before-release waits for physical STOP")
        h.advance(0.18)
        h.endChromecastPress()
        c.expect(h.triggerTapCount == 1, "first short tap sends one trigger")
        c.expect(h.openRequests.count == 1, "physical STOP immediately requests persistent stream")
        c.expect(h.openRequests.first?.0 == .chromecast, "recovery targets Chromecast")
        c.expect(h.openRequests.first?.1 == true, "recovery bypasses transport debounce")
        c.expect(h.coordinator.debugSnapshot.phase == "open", "active-before-release remains open")
    }

    private static func testStopBeforeActive(_ c: CheckContext) {
        let h = Harness()
        h.beginChromecastPress()
        h.advance(0.12)
        h.endChromecastPress()
        c.expect(h.openRequests.count == 1, "stop-before-active also opens without fixed delay")
        h.voiceState.emit(.active)
        c.expect(h.openRequests.count == 1, "active confirmation does not duplicate MIC_OPEN")
        c.expect(h.coordinator.debugSnapshot.phase == "open", "late active completes opening")
    }

    private static func testSecondTapCloses(_ c: CheckContext) {
        let h = Harness()
        h.beginChromecastPress()
        h.advance(0.15)
        h.endChromecastPress()
        h.voiceState.emit(.active)
        h.coordinator.remoteAudioStarted(remote: .chromecast, reason: 0x00)
        h.beginChromecastPress()
        h.advance(0.16)
        h.endChromecastPress()
        c.expect(h.triggerTapCount == 2, "second short tap sends exactly one close trigger")
        c.expect(h.openRequests.count == 1, "second tap never reopens microphone")
        c.expect(h.coordinator.debugSnapshot.phase == "closed", "second tap closes")
    }

    private static func testLongPressCloses(_ c: CheckContext) {
        let h = Harness()
        h.beginChromecastPress()
        h.voiceState.emit(.active)
        h.advance(0.70)
        h.endChromecastPress()
        c.expect(h.triggerTapCount == 2, "long release sends one close trigger")
        c.expect(h.openRequests.isEmpty, "long release never requests persistent reopen")
        c.expect(h.coordinator.debugSnapshot.phase == "closed", "long release closes")
    }

    private static func testKeyboardOpenRemoteClose(_ c: CheckContext) {
        let h = Harness()
        h.coordinator.triggerDownObserved(isSynthetic: false)
        h.voiceState.emit(.active)
        h.coordinator.triggerUpObserved(isSynthetic: false)
        c.expect(h.triggerTapCount == 0, "physical keyboard open is not replayed")
        h.coordinator.remoteAudioStarted(remote: .chromecast, reason: 0x00)
        h.beginChromecastPress()
        h.advance(0.14)
        h.endChromecastPress()
        c.expect(h.triggerTapCount == 1, "remote can close keyboard-opened session")
        c.expect(h.coordinator.debugSnapshot.phase == "closed", "cross-close closes")
    }

    private static func testRemoteOpenKeyboardClose(_ c: CheckContext) {
        let h = Harness()
        h.beginChromecastPress()
        h.advance(0.16)
        h.endChromecastPress()
        h.voiceState.emit(.active)
        h.coordinator.remoteAudioStarted(remote: .chromecast, reason: 0x00)
        h.coordinator.triggerDownObserved(isSynthetic: false)
        h.coordinator.triggerUpObserved(isSynthetic: false)
        c.expect(h.triggerTapCount == 1, "keyboard close does not synthesize another trigger")
        c.expect(h.openRequests.count == 1, "stale active cannot reopen transport")
        c.expect(h.coordinator.debugSnapshot.phase == "closed", "keyboard close closes the session")
    }

    private static func testChromecastReasonZeroWhileClosedIsIgnored(
        _ c: CheckContext
    ) {
        let h = Harness()
        h.coordinator.remoteAudioStarted(remote: .chromecast, reason: 0x00)
        c.expect(h.triggerTapCount == 0, "stale Chromecast reason-0 sends no trigger")
        c.expect(h.coordinator.debugSnapshot.phase == "closed", "stale Chromecast reason-0 stays closed")
        c.expect(
            h.coordinator.debugSnapshot.streamingRemotes.isEmpty,
            "stale Chromecast reason-0 is closed locally"
        )
    }

    private static func testDebouncedRetry(_ c: CheckContext) {
        let h = Harness()
        h.openResults = [.retryAfter(0.02), .sent]
        h.beginChromecastPress()
        h.advance(0.13)
        h.endChromecastPress()
        c.expect(h.coordinator.debugSnapshot.openRequestedRemote == nil, "debounced request is not marked sent")
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        c.expect(h.openRequests.count == 2, "debounced open receives a bounded retry")
        c.expect(
            h.coordinator.debugSnapshot.openRequestedRemote == .chromecast,
            "only the sent retry becomes pending"
        )
    }

    private static func testWeTypeHoldSurvivesStartVerification(
        _ c: CheckContext
    ) {
        let h = Harness()
        h.coordinator.voiceHost = .weType
        h.coordinator.triggerMode = .pushToTalk
        h.beginChromecastPress()
        c.expect(h.triggerDownCount == 1, "weType press sends one keyDown")
        c.expect(h.triggerTapCount == 0, "weType never sends a synthetic tap")
        c.expect(
            h.coordinator.debugSnapshot.phase == "open",
            "weType opens without waiting for CoreAudio"
        )
        RunLoop.current.run(until: Date().addingTimeInterval(1.1))
        c.expect(
            h.coordinator.debugSnapshot.phase == "open",
            "weType does not hit the one-second opening timeout"
        )
        c.expect(h.closeRequestCount == 0, "weType keeps the remote stream open")
        h.endChromecastPress()
        c.expect(h.triggerUpCount == 1, "weType release sends one keyUp")
        c.expect(
            h.coordinator.debugSnapshot.phase == "closed",
            "weType release closes the session"
        )
        c.expect(
            h.openRequests.isEmpty,
            "weType push-to-talk never requests a persistent stream"
        )
    }

    private static func testWeTypeKeyboardHoldCloses(_ c: CheckContext) {
        let h = Harness()
        h.coordinator.voiceHost = .weType
        h.coordinator.triggerMode = .pushToTalk
        h.coordinator.triggerDownObserved(isSynthetic: false)
        c.expect(h.triggerDownCount == 0, "keyboard PTT is not replayed")
        c.expect(
            h.openRequests.isEmpty,
            "keyboard PTT does not open the remote mic for WeType"
        )
        c.expect(
            h.coordinator.debugSnapshot.phase == "open",
            "keyboard PTT opens the session immediately"
        )
        h.coordinator.triggerUpObserved(isSynthetic: false)
        c.expect(
            h.coordinator.debugSnapshot.phase == "closed",
            "keyboard PTT release closes the session"
        )
        c.expect(h.triggerTapCount == 0, "keyboard PTT never synthesizes a trigger")
    }

    private static func testWeTypeAdoptsExternalRecording(
        _ c: CheckContext
    ) {
        let h = Harness()
        h.coordinator.voiceHost = .weType
        h.coordinator.triggerMode = .pushToTalk
        h.voiceState.emit(.active)
        c.expect(
            h.coordinator.debugSnapshot.phase == "open",
            "weType adopts external recording"
        )
        c.expect(
            h.routeChanges.last == true,
            "weType adoption opens the mix"
        )
        c.expect(
            h.routeCaptureFlags.last == true,
            "weType external recording captures the computer mic"
        )
        h.voiceState.emit(.inactive)
        c.expect(
            h.coordinator.debugSnapshot.phase == "closed",
            "weType inactive closes the mix"
        )
        c.expect(
            h.routeChanges.last == false,
            "weType inactive closes the route"
        )
    }

    private static func testRemoteSessionDoesNotCaptureSecondInput(
        _ c: CheckContext
    ) {
        let h = Harness()
        h.coordinator.voiceHost = .weType
        h.coordinator.triggerMode = .pushToTalk
        h.beginChromecastPress()
        c.expect(
            h.routeCaptureFlags.last == false,
            "weType remote session does not capture the computer mic"
        )
        h.endChromecastPress()
    }

    private static func testKeyboardSessionCapturesSecondInput(
        _ c: CheckContext
    ) {
        let h = Harness()
        h.coordinator.voiceHost = .weType
        h.coordinator.triggerMode = .pushToTalk
        h.coordinator.triggerDownObserved(isSynthetic: false)
        c.expect(
            h.routeCaptureFlags.last == true,
            "weType keyboard session captures the computer mic"
        )
        h.coordinator.triggerUpObserved(isSynthetic: false)
        c.expect(
            h.routeCaptureFlags.last == false,
            "closing the keyboard session releases the computer mic"
        )
    }

    private static func testWeTypeShortTapDoesNotReopen(_ c: CheckContext) {
        let h = Harness()
        h.coordinator.voiceHost = .weType
        h.coordinator.triggerMode = .pushToTalk
        h.beginChromecastPress()
        h.advance(0.12)
        h.endChromecastPress()
        c.expect(h.triggerDownCount == 1, "short PTT press sends keyDown")
        c.expect(h.triggerUpCount == 1, "short PTT release sends keyUp")
        c.expect(
            h.openRequests.isEmpty,
            "short PTT press never opens a persistent stream"
        )
        c.expect(
            h.coordinator.debugSnapshot.phase == "closed",
            "short PTT press closes on release"
        )
    }

    private static func testForceCloseReleasesWeTypeTrigger(
        _ c: CheckContext
    ) {
        let h = Harness()
        h.coordinator.voiceHost = .weType
        h.coordinator.triggerMode = .pushToTalk
        h.beginChromecastPress()
                h.coordinator.forceClose()
        c.expect(
            h.triggerUpCount == 1,
            "forceClose releases a held push-to-talk trigger"
        )
        c.expect(
            h.coordinator.debugSnapshot.phase == "closed",
            "forceClose leaves the session closed"
        )
    }

    private static func testRepeatableTargets(_ c: CheckContext) {
        for target in [
            RemoteMappingTarget.deleteBackward,
            .arrowUp, .arrowDown, .arrowLeft, .arrowRight,
            .pageUp, .pageDown,
        ] {
            c.expect(target.isRepeatable, "\(target.rawValue) repeats while held")
        }
        for target in [
            RemoteMappingTarget.returnKey,
            .escape,
            .home,
            .end,
            .volumeUp,
            .volumeDown,
            .mute,
            .playPause,
            .showDesktop,
            .appSwitcher,
        ] {
            c.expect(!target.isRepeatable, "\(target.rawValue) is one-shot")
        }
    }

    private static func testTriggerDeviceFlags(_ c: CheckContext) {
        c.expect(
            InputTriggerKey.option.primaryKeyCode == 0x3A,
            "left option posts keyCode 0x3A"
        )
        c.expect(
            InputTriggerKey.option.deviceFlag.rawValue == 0x20,
            "left option carries the NX left-option device bit"
        )
        c.expect(
            InputTriggerKey.optionRight.primaryKeyCode == 0x3D,
            "right option posts keyCode 0x3D"
        )
        c.expect(
            InputTriggerKey.optionRight.deviceFlag.rawValue == 0x40,
            "right option carries the NX right-option device bit"
        )
        c.expect(
            InputTriggerKey.option.keyCodes == [0x3A, 0x3D],
            "option observes both physical sides"
        )
        c.expect(
            InputTriggerKey.optionRight.keyCodes == [0x3A, 0x3D],
            "right option also observes both physical sides"
        )
        c.expect(
            InputTriggerKey.command.primaryKeyCode == 0x37
                && InputTriggerKey.command.deviceFlag.rawValue == 0x08,
            "left command maps to keyCode 0x37 and device bit 0x08"
        )
        c.expect(
            InputTriggerKey.commandRight.primaryKeyCode == 0x36
                && InputTriggerKey.commandRight.deviceFlag.rawValue == 0x10,
            "right command maps to keyCode 0x36 and device bit 0x10"
        )
        c.expect(
            InputTriggerKey.control.primaryKeyCode == 0x3B
                && InputTriggerKey.control.deviceFlag.rawValue == 0x01,
            "left control maps to keyCode 0x3B and device bit 0x01"
        )
        c.expect(
            InputTriggerKey.controlRight.primaryKeyCode == 0x3E
                && InputTriggerKey.controlRight.deviceFlag.rawValue == 0x2000,
            "right control maps to keyCode 0x3E and device bit 0x2000"
        )
        c.expect(
            InputTriggerKey.shift.primaryKeyCode == 0x38
                && InputTriggerKey.shift.deviceFlag.rawValue == 0x02,
            "left shift maps to keyCode 0x38 and device bit 0x02"
        )
        c.expect(
            InputTriggerKey.shiftRight.primaryKeyCode == 0x3C
                && InputTriggerKey.shiftRight.deviceFlag.rawValue == 0x04,
            "right shift maps to keyCode 0x3C and device bit 0x04"
        )
    }
}
#endif
