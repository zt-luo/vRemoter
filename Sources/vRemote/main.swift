// vRemote for macOS.
//
// 1. Remote voice key → matching Option trigger semantics
// 2. Remote ATVV + Mac microphone → aligned mix → vRemoteDr 2ch → WeType
// 3. A physical Mac Option key controls the same remote microphone session
//
// macOS-only. Requires:
//   * Chromecast Remote paired in System Settings → Bluetooth
//   * Accessibility permission (System Settings → Privacy & Security →
//     Accessibility) for Option observation
//   * vRemoteDriver.driver installed and visible as vRemoteDr 2ch in
//     System Settings → Sound → Input/Output
//   * WeType configured for Option-as-voice-mode trigger
//
// Run:   swift run
// Quit:  menu bar icon → 退出, or Ctrl+C

import AppKit
import CoreGraphics
import Darwin
import Foundation

// MARK: - Menu bar UI

final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var headerLabel: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var loggingToggleItem: NSMenuItem!
    private var logSizeItem: NSMenuItem!
    private var recordingToggleItem: NSMenuItem!
    private var recordingSizeItem: NSMenuItem!
    private var languageItems: [AppLanguage: NSMenuItem] = [:]

    private var chromecastHIDConnected = false
    private var chromecastBLEConnected = false
    private var chromecastRemoteStreaming = false
    private var remoteStreaming = false


    private let chromecastHID = ChromecastRemoteHIDBridge()
    private let inputTriggerMonitor = InputTriggerMonitor()
    private let voiceInputState = VoiceInputStateMonitor()
    private lazy var voiceSession = VoiceSessionCoordinator(
        voiceState: voiceInputState
    )
    private let debugWindow = DebugWindowController()
    private let updateWindow = UpdateWindowController()
    private let chromecastBLE = BLEBridge(
        nameHint: "Chromecast Remote",
        savedUUIDFilename: "chromecast-remote-uuid.txt",
        recordingPrefix: "chromecast-remote-voice",
        logTag: "CAST-BLE",
        resetSessionOnConnect: true
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppStorage.prepare()
        NSApp.setActivationPolicy(.accessory)
        voiceInputState.setHost(VoiceInputHost.weType)
        voiceSession.voiceHost = VoiceInputHost.weType
        voiceSession.triggerMode = AppStorage.weTypeTriggerMode
        AppAnalytics.configure()
        // Keep one continuous diagnostic history.
        // Log.swift rotates at 5 MB; only the explicit menu action clears it.
        Log.setEnabled(true)
        let appVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "development"
        print("[APP] ===== vRemoter \(appVersion) started =====")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let statusImage = LogoAsset.image.copy() as? NSImage
        statusImage?.size = NSSize(width: 18, height: 18)
        statusItem.button?.image = statusImage
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.title = ""
        NSApp.applicationIconImage = LogoAsset.image

        let menu = NSMenu()
        menu.delegate = self
        let header = NSMenuItem(
            title: L10n.text("状态 · 启动中", "Status · Starting"),
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)
        headerLabel = header

        let launch = NSMenuItem(
            title: L10n.text("登录时自动启动", "Launch at login"),
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launch.target = self
        menu.addItem(launch)
        launchAtLoginItem = launch

        menu.addItem(.separator())
        menu.addItem(makeControlMenu())
        menu.addItem(makeLogMenu())
        menu.addItem(makeRecordingMenu())
        menu.addItem(makeLanguageMenu())

        menu.addItem(.separator())
        let updates = NSMenuItem(
            title: L10n.text("版本与更新…", "Version & Updates…"),
            action: #selector(openVersionUpdates),
            keyEquivalent: ""
        )
        updates.target = self
        menu.addItem(updates)

        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: L10n.text("退出", "Quit"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        refreshMenuState()
        wireDebugWindow()

        chromecastHID.onConnectionChanged = { [weak self] connected in
            self?.chromecastHIDConnected = connected
            AppAnalytics.signal(
                connected
                    ? "Remote.Chromecast.HID.connected"
                    : "Remote.Chromecast.HID.disconnected"
            )
            self?.updateStatus()
        }
        chromecastBLE.onConnectionChanged = { [weak self] connected in
            self?.chromecastBLEConnected = connected
            AppAnalytics.signal(
                connected
                    ? "Remote.Chromecast.BLE.connected"
                    : "Remote.Chromecast.BLE.disconnected"
            )
            if !connected {
                self?.chromecastRemoteStreaming = false
                self?.voiceSession.remoteDisconnected(.chromecast)
            }
            self?.refreshCombinedStreaming()
            self?.updateStatus()
        }
        chromecastBLE.onStreamingChanged = { [weak self] streaming, _ in
            self?.chromecastRemoteStreaming = streaming
            AppAnalytics.signal(
                streaming
                    ? "Voice.Chromecast.started"
                    : "Voice.Chromecast.stopped"
            )
            self?.refreshCombinedStreaming()
            self?.updateStatus()
        }
        chromecastBLE.onAudioStarted = { [weak self] reason, _ in
            self?.voiceSession.remoteAudioStarted(
                remote: .chromecast,
                reason: reason,
                supportsPhysicalHoldGesture: true
            )
        }
        chromecastBLE.onAudioStopped = { [weak self] reason in
            self?.voiceSession.remoteAudioStopped(
                remote: .chromecast,
                reason: reason
            )
        }
        chromecastBLE.onMicrophoneOpenFailed = { [weak self] code in
            self?.voiceSession.remoteMicrophoneOpenFailed(
                remote: .chromecast,
                code: code
            )
        }
        chromecastBLE.onLevel = { [weak self] db, _ in
            guard AudioPipe.shared.isRemoteInputEnabled else { return }
            self?.debugWindow.updateRemoteLevel(db)
        }
        voiceSession.preferredRemoteProvider = { [weak self] in
            self?.preferredVoiceRemote()
        }
        voiceSession.onMicrophoneCloseRequested = { [weak self] in
            self?.closeAllRemoteMicrophones()
        }
        voiceSession.onMicrophoneOpenRequested = {
            [weak self] remote, bypassDebounce in
            guard AudioPipe.shared.isRemoteInputEnabled else {
                print("[AUDIO] 遥控器未勾选，跳过主动开麦")
                return .unavailable
            }
            return self?.openRemoteMicrophone(
                remote,
                bypassDebounce: bypassDebounce
            ) ?? .unavailable
        }
        voiceSession.onStateChanged = { [weak self] status in
            self?.headerLabel.title = "状态 · \(status)"
            self?.updateStatus()
        }
        voiceSession.onSnapshotObserved = { [weak self] _ in
            self?.updateStatus()
        }
        voiceSession.start()
        inputTriggerMonitor.start()
        chromecastHID.start()
        chromecastBLE.start()

        // Start the loopback engine eagerly so device binding is verified
        // before the first BLE audio packet arrives.
        _ = AudioPipe.shared
        AudioPipe.shared.onMacLevel = { [weak self] db in
            self?.debugWindow.updateMacLevel(db)
        }
        AudioPipe.shared.onRouteChanged = { [weak self] _ in
            self?.updateStatus()
        }
        AudioPipe.shared.onSecondInputCaptureChanged = { [weak self] _ in
            self?.updateStatus()
        }

        DispatchQueue.main.async { [weak self] in
            self?.debugWindow.show()
        }
        if CommandLine.arguments.contains("--update-available-demo") {
            print("[UPDATE] update-available demo requested")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.updateWindow.showDemoUpdate()
            }
        } else if CommandLine.arguments.contains("--update-current-demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.updateWindow.showUpToDateDemo()
            }
        } else if CommandLine.arguments.contains("--updates-window-demo") {
            print("[UPDATE] updates-window demo requested")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.updateWindow.show()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                self?.updateWindow.checkAutomatically()
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuState()
    }

    private func makeLogMenu() -> NSMenuItem {
        let root = NSMenuItem(title: L10n.text("日志", "Logs"), action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: L10n.text("日志", "Logs"))

        let toggle = NSMenuItem(
            title: L10n.text("记录日志", "Record logs"),
            action: #selector(toggleLogging),
            keyEquivalent: ""
        )
        toggle.target = self
        submenu.addItem(toggle)
        loggingToggleItem = toggle

        let size = NSMenuItem(title: L10n.text("占用 · 0 字节", "Size · 0 bytes"), action: nil, keyEquivalent: "")
        size.isEnabled = false
        submenu.addItem(size)
        logSizeItem = size

        let refresh = NSMenuItem(
            title: L10n.text("刷新占用大小", "Refresh size"),
            action: #selector(refreshStorageSizes),
            keyEquivalent: ""
        )
        refresh.target = self
        submenu.addItem(refresh)

        let open = NSMenuItem(
            title: L10n.text("打开日志文件夹", "Open logs folder"),
            action: #selector(openLogFolder),
            keyEquivalent: ""
        )
        open.target = self
        submenu.addItem(open)

        let clear = NSMenuItem(
            title: L10n.text("清空日志", "Clear logs"),
            action: #selector(clearLog),
            keyEquivalent: ""
        )
        clear.target = self
        submenu.addItem(clear)

        root.submenu = submenu
        return root
    }

    private func makeControlMenu() -> NSMenuItem {
        let root = NSMenuItem(title: L10n.text("控制台", "Console"), action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: L10n.text("控制台", "Console"))

        let open = NSMenuItem(
            title: L10n.text("打开前台控制台", "Open console"),
            action: #selector(openDebugWindow),
            keyEquivalent: ""
        )
        open.target = self
        submenu.addItem(open)

        let stop = NSMenuItem(
            title: L10n.text("关闭麦克风", "Stop microphone"),
            action: #selector(stopMicrophone),
            keyEquivalent: ""
        )
        stop.target = self
        submenu.addItem(stop)

        let restart = NSMenuItem(
            title: L10n.text("重启 App", "Restart app"),
            action: #selector(restartApp),
            keyEquivalent: ""
        )
        restart.target = self
        submenu.addItem(restart)

        root.submenu = submenu
        return root
    }

    private func makeRecordingMenu() -> NSMenuItem {
        let root = NSMenuItem(title: L10n.text("调试录音", "Debug recordings"), action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: L10n.text("调试录音", "Debug recordings"))

        let toggle = NSMenuItem(
            title: L10n.text("保存 WAV 与原始数据", "Save WAV and raw data"),
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        toggle.target = self
        submenu.addItem(toggle)
        recordingToggleItem = toggle

        let size = NSMenuItem(title: L10n.text("占用 · 0 字节", "Size · 0 bytes"), action: nil, keyEquivalent: "")
        size.isEnabled = false
        submenu.addItem(size)
        recordingSizeItem = size

        let refresh = NSMenuItem(
            title: L10n.text("刷新占用大小", "Refresh size"),
            action: #selector(refreshStorageSizes),
            keyEquivalent: ""
        )
        refresh.target = self
        submenu.addItem(refresh)

        let open = NSMenuItem(
            title: L10n.text("打开录音文件夹", "Open recordings folder"),
            action: #selector(openRecordingFolder),
            keyEquivalent: ""
        )
        open.target = self
        submenu.addItem(open)

        let clear = NSMenuItem(
            title: L10n.text("清空录音文件", "Clear recordings"),
            action: #selector(clearRecordings),
            keyEquivalent: ""
        )
        clear.target = self
        submenu.addItem(clear)

        root.submenu = submenu
        return root
    }

    private func makeLanguageMenu() -> NSMenuItem {
        let root = NSMenuItem(
            title: L10n.text("语言", "Language"),
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu(title: L10n.text("语言", "Language"))
        let options: [(AppLanguage, String, Selector)] = [
            (.system, L10n.text("跟随系统", "System Default"), #selector(selectSystemLanguage)),
            (.simplifiedChinese, "简体中文", #selector(selectSimplifiedChinese)),
            (.english, "English", #selector(selectEnglish))
        ]
        for (language, title, selector) in options {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            item.state = AppLanguage.selected == language ? .on : .off
            submenu.addItem(item)
            languageItems[language] = item
        }
        root.submenu = submenu
        return root
    }

    private func updateStatus() {
        let anyHID = chromecastHIDConnected
        let anyBLE = chromecastBLEConnected
        let host = VoiceInputHost.weType
        let voiceSnapshot = voiceInputState.snapshotNow()
        let voiceUsesVRemote = voiceSnapshot.inputDeviceNames.contains("vRemoteDr 2ch")
        let statusText: String
        if host.canObserveRecording,
           voiceSnapshot.isRecording,
           !voiceUsesVRemote {
            statusText = L10n.text(
                "\(host.shortTitle)输入设备错误",
                "Incorrect \(host.shortTitle) input"
            )
        } else if remoteStreaming {
            statusText = L10n.text("遥控器录音中", "Remote recording")
        } else if anyHID && anyBLE {
            statusText = L10n.text("已就绪", "Ready")
        } else if anyHID || anyBLE {
            statusText = L10n.text("正在连接语音服务", "Connecting voice service")
        } else {
            statusText = L10n.text("等待遥控器", "Waiting for remote")
        }
        statusItem.button?.toolTip = "vRemoter · \(statusText)"
        headerLabel.title = L10n.text("状态 · \(statusText)", "Status · \(statusText)")
        debugWindow.update(
            status: statusText,
            hidConnected: anyHID,
            bleConnected: anyBLE,
            remoteStreaming: remoteStreaming,
            macInputEnabled: AudioPipe.shared.isMacInputEnabled,
            remoteInputEnabled: AudioPipe.shared.isRemoteInputEnabled,
            secondInputDevices: AudioPipe.availableSecondInputDevices(),
            secondInputDeviceUID: AudioPipe.shared.secondInputDeviceUID,
            secondInputDeviceName: AudioPipe.shared.secondInputDeviceName,
            secondInputCapturing: AudioPipe.shared.isSecondInputCapturing,
            voiceHost: host,
            voiceIsRecording: voiceSnapshot.isRecording,
            voiceInput: voiceSnapshot.deviceSummary,
            voiceInputWarning: voiceInputWarning(
                host: host,
                snapshot: voiceSnapshot
            ),
            driverAvailable: AudioPipe.shared.isOutputDeviceAvailable,
            chromecastConnected: chromecastHIDConnected || chromecastBLEConnected,
            macLevelDB: nil,
            remoteLevelDB: nil
        )
    }

    private func voiceInputWarning(
        host: VoiceInputHost,
        snapshot: VoiceInputStateMonitor.Snapshot
    ) -> String? {
        guard host == .weType else { return nil }
        if snapshot.state == .unavailable {
            return L10n.text("微信输入法未运行", "WeType is not running")
        }
        // WeType only exposes its input device while its voice engine is
        // actually recording. Idle snapshots have no device list, which is not
        // a misconfiguration.
        guard snapshot.state == .active,
              !snapshot.inputDeviceIDs.isEmpty,
              !snapshot.inputDeviceNames.contains("vRemoteDr 2ch") else {
            return nil
        }
        return L10n.text(
            "麦克风不是 vRemoteDr 2ch",
            "Microphone is not vRemoteDr 2ch"
        )
    }

    private func wireDebugWindow() {
        debugWindow.onStopMicrophone = { [weak self] in
            self?.stopMicrophoneNow()
        }
        debugWindow.onRestartApp = { [weak self] in
            self?.restartAppNow()
        }
        debugWindow.onMacInputEnabledChanged = { [weak self] enabled in
            let audio = AudioPipe.shared
            audio.setInputEnabled(
                mac: enabled,
                remote: audio.isRemoteInputEnabled
            )
            self?.updateStatus()
        }
        debugWindow.onSecondInputDeviceChanged = { [weak self] uid in
            AudioPipe.shared.setSecondInputDevice(uid: uid)
            self?.updateStatus()
        }
        debugWindow.onRemoteInputEnabledChanged = { [weak self] enabled in
            let audio = AudioPipe.shared
            audio.setInputEnabled(
                mac: audio.isMacInputEnabled,
                remote: enabled
            )
            if !enabled {
                self?.chromecastBLE.closeMicrophone(force: true)
                self?.debugWindow.updateRemoteLevel(-120)
            } else if VoiceInputHost.weType.canObserveRecording,
                      self?.voiceInputState.snapshotNow().isRecording == true {
                self?.openPreferredRemoteMicrophone()
            }
            self?.updateStatus()
        }
        debugWindow.onInputTriggerChanged = { [weak self] in
            self?.inputTriggerMonitor.triggerConfigurationDidChange()
        }
        debugWindow.onWeTypeTriggerModeChanged = { [weak self] mode in
            guard let self else { return }
            self.voiceSession.forceClose()
            self.voiceSession.triggerMode = mode
            self.inputTriggerMonitor.triggerConfigurationDidChange()
            self.updateStatus()
        }
        debugWindow.onRemoteMappingEnabledChanged = { [weak self] _, enabled in
            self?.chromecastHID.setRemappingEnabled(enabled)
        }
    }

    @objc private func openDebugWindow() {
        debugWindow.show()
    }

    @objc private func openVersionUpdates() {
        updateWindow.show()
    }

    @objc private func selectSystemLanguage() {
        setLanguageAndRestart(.system)
    }

    @objc private func selectSimplifiedChinese() {
        setLanguageAndRestart(.simplifiedChinese)
    }

    @objc private func selectEnglish() {
        setLanguageAndRestart(.english)
    }

    private func setLanguageAndRestart(_ language: AppLanguage) {
        guard AppLanguage.selected != language else { return }
        AppLanguage.selected = language
        restartAppNow()
    }

    @objc private func stopMicrophone() {
        stopMicrophoneNow()
    }

    private func stopMicrophoneNow() {
        voiceSession.forceClose()
        chromecastBLE.closeMicrophone(force: true)
        AudioPipe.shared.setRemoteActive(false)
        updateStatus()
    }

    @objc private func restartApp() {
        restartAppNow()
    }

    private func restartAppNow() {
        stopMicrophoneNow()
        let bundleURL = Bundle.main.bundleURL
        // `NSWorkspace.openApplication` may reuse the current instance for an
        // accessory app. Use `/usr/bin/open -n` so macOS creates a genuinely
        // new process before this one exits.
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        launcher.arguments = ["-n", bundleURL.path]
        do {
            try launcher.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                NSApp.terminate(nil)
            }
        } catch {
            print("[APP] 重启失败: \(error.localizedDescription)")
        }
    }

    private func refreshCombinedStreaming() {
        remoteStreaming = chromecastRemoteStreaming
    }

    private func preferredVoiceRemote() -> VoiceRemoteID? {
        chromecastBLEConnected ? .chromecast : nil
    }

    private func openRemoteMicrophone(
        _ remote: VoiceRemoteID,
        bypassDebounce: Bool
    ) -> RemoteMicrophoneOpenResult {
        guard remote == .chromecast, chromecastBLEConnected else {
            return .unavailable
        }
        return chromecastBLE.openMicrophone(
            bypassDebounce: bypassDebounce
        )
    }

    private func openPreferredRemoteMicrophone() {
        guard let remote = preferredVoiceRemote() else { return }
        _ = openRemoteMicrophone(remote, bypassDebounce: false)
    }

    private func closeAllRemoteMicrophones() {
        chromecastBLE.closeMicrophone(force: true)
    }

    private func refreshMenuState() {
        launchAtLoginItem?.state = LaunchAtLogin.isEnabled ? .on : .off
        loggingToggleItem?.state = Log.isEnabled ? .on : .off
        recordingToggleItem?.state = AppStorage.recordingEnabled ? .on : .off
        refreshSizeLabels()
    }

    private func refreshSizeLabels() {
        logSizeItem?.title = L10n.text("占用", "Size")
            + " · \(AppStorage.formattedSize(Log.byteSize))"
        let recordingBytes = AppStorage.byteSize(
            of: AppStorage.recordingsDirectory
        )
        recordingSizeItem?.title = L10n.text("占用", "Size")
            + " · \(AppStorage.formattedSize(recordingBytes))"
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
        } catch {
            headerLabel.title = L10n.text(
                "状态 · 登录启动设置失败",
                "Status · Launch-at-login failed"
            )
        }
        refreshMenuState()
    }

    @objc private func toggleLogging() {
        Log.setEnabled(!Log.isEnabled)
        if Log.isEnabled {
            print("[APP] 日志已由用户开启")
        }
        refreshMenuState()
    }

    @objc private func toggleRecording() {
        let enabled = !AppStorage.recordingEnabled
        AppStorage.recordingEnabled = enabled
        chromecastBLE.setRecordingEnabled(enabled)
        refreshMenuState()
    }

    @objc private func refreshStorageSizes() {
        refreshSizeLabels()
    }

    @objc private func openLogFolder() {
        AppStorage.ensureDirectory(AppStorage.logsDirectory)
        NSWorkspace.shared.open(AppStorage.logsDirectory)
    }

    @objc private func openRecordingFolder() {
        AppStorage.ensureDirectory(AppStorage.recordingsDirectory)
        NSWorkspace.shared.open(AppStorage.recordingsDirectory)
    }

    @objc private func clearLog() {
        Log.clear()
        refreshSizeLabels()
    }

    @objc private func clearRecordings() {
        refreshSizeLabels()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        chromecastHID.stop()
        inputTriggerMonitor.stop()
        voiceSession.stop()
        chromecastBLE.stop()
        AudioPipe.shared.stop()
        // 切换器会话若还挂着 ⌘ 虚按住状态，退出时收尾。
        AppSwitcherSession.shared.cancel()
        ScrollRepeatSession.shared.end()
        KeyRepeatSession.shared.end()
    }
}

// MARK: - Entry

#if DEBUG
if CommandLine.arguments.contains("--voice-session-self-test") {
    exit(VoiceSessionSelfTest.run() ? EXIT_SUCCESS : EXIT_FAILURE)
}
#endif

let app = NSApplication.shared
let delegate = AppController()
app.delegate = delegate

// Convert SIGTERM (including `kill`/`pkill`) into a normal AppKit
// termination so Option and the CoreAudio IOProc are always released.
signal(SIGTERM, SIG_IGN)
let terminationSignal = DispatchSource.makeSignalSource(
    signal: SIGTERM,
    queue: .main
)
terminationSignal.setEventHandler {
    NSApp.terminate(nil)
}
terminationSignal.resume()

app.run()
