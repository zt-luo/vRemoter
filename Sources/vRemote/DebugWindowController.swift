import AppKit
import ApplicationServices
import AVFoundation
import CoreBluetooth
import CoreGraphics
import SwiftUI

enum PermissionKind: String, Identifiable, CaseIterable {
    case microphone
    case accessibility
    case inputMonitoring
    case bluetooth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: L10n.text("麦克风权限", "Microphone Permission")
        case .accessibility: L10n.text("辅助功能权限", "Accessibility Permission")
        case .inputMonitoring: L10n.text("输入监控权限", "Input Monitoring Permission")
        case .bluetooth: L10n.text("蓝牙权限", "Bluetooth Permission")
        }
    }

    var settingsURL: URL? {
        let anchor: String
        switch self {
        case .microphone: anchor = "Privacy_Microphone"
        case .accessibility: anchor = "Privacy_Accessibility"
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        case .bluetooth: anchor = "Privacy_Bluetooth"
        }
        return URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        )
    }

    var screenshotNames: [String] {
        switch self {
        case .microphone: ["permission-microphone", "permission-microphone"]
        case .accessibility: ["permission-accessibility", "permission-accessibility"]
        case .inputMonitoring: ["permission-input-monitoring", "permission-input-monitoring"]
        case .bluetooth: ["permission-bluetooth", "permission-bluetooth"]
        }
    }

    var guidance: [String] {
        switch self {
        case .microphone:
            return [
                L10n.text(
                    "系统设置会打开到“隐私与安全性 → 麦克风”。",
                    "System Settings will open Privacy & Security > Microphone."
                ),
                L10n.text(
                    "找到 vRemote（或 vRemoter），打开右侧开关；若已经打开，关闭后重新打开一次。",
                    "Find vRemote or vRemoter and enable it. If already enabled, turn it off and on once."
                )
            ]
        case .accessibility:
            return [
                L10n.text(
                    "系统设置会打开到“隐私与安全性 → 辅助功能”。",
                    "System Settings will open Privacy & Security > Accessibility."
                ),
                L10n.text(
                    "找到 vRemote（或 vRemoter）并打开开关。列表中没有时，点加号选择应用。",
                    "Enable vRemote or vRemoter. If it is missing, use the plus button to add the app."
                )
            ]
        case .inputMonitoring:
            return [
                L10n.text(
                    "系统设置会打开到“隐私与安全性 → 输入监控”。",
                    "System Settings will open Privacy & Security > Input Monitoring."
                ),
                L10n.text(
                    "找到 vRemote（或 vRemoter）并打开开关。macOS 提示重新启动时允许它重新打开。",
                    "Enable vRemote or vRemoter, then allow macOS to relaunch it when prompted."
                )
            ]
        case .bluetooth:
            return [
                L10n.text(
                    "系统设置会打开到“隐私与安全性 → 蓝牙”。",
                    "System Settings will open Privacy & Security > Bluetooth."
                ),
                L10n.text(
                    "找到 vRemote（或 vRemoter）并打开开关，然后返回应用等待遥控器重新连接。",
                    "Enable vRemote or vRemoter, then return to the app and wait for the remote to reconnect."
                )
            ]
        }
    }

    var pageCount: Int { screenshotNames.count }

    func screenshotName(for page: Int) -> String {
        screenshotNames[min(max(page, 0), pageCount - 1)]
    }
}

private enum ConsoleTheme {
    static let panel = Color(red: 0.055, green: 0.059, blue: 0.067)
    static let surface = Color(red: 0.083, green: 0.091, blue: 0.103)
    static let surface2 = Color(red: 0.102, green: 0.112, blue: 0.124)
    static let line = Color(red: 0.22, green: 0.23, blue: 0.25)
    static let lineSoft = Color(red: 0.15, green: 0.16, blue: 0.18)
    static let text = Color(red: 0.93, green: 0.94, blue: 0.95)
    static let secondary = Color(red: 0.55, green: 0.57, blue: 0.61)
    static let tertiary = Color(red: 0.39, green: 0.41, blue: 0.45)
    static let green = Color(red: 0.31, green: 0.82, blue: 0.53)
    static let amber = Color(red: 0.96, green: 0.61, blue: 0.19)
    static let amberDeep = Color(red: 0.16, green: 0.13, blue: 0.09)
    static let red = Color(red: 0.94, green: 0.33, blue: 0.34)
    static let redDeep = Color(red: 0.25, green: 0.08, blue: 0.09)
    static let black = Color(red: 0.025, green: 0.028, blue: 0.032)
}

enum LogoAsset {
    static let image: NSImage = {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "vRemoterLogo", withExtension: "png"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Design/vRemoter-Logo-v1/vRemoter-app-icon-v9.png")
        ]
        for candidate in candidates.compactMap({ $0 }) {
            if let image = NSImage(contentsOf: candidate) { return image }
        }
        return NSImage(size: NSSize(width: 64, height: 64))
    }()
}

private enum GuideAsset {
    static func image(named name: String) -> NSImage? {
        let candidates: [URL?] = [
            Bundle.main.resourceURL?
                .appendingPathComponent("PermissionGuides", isDirectory: true)
                .appendingPathComponent("\(name).png"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/PermissionGuides/\(name).png")
        ]
        for candidate in candidates.compactMap({ $0 }) {
            if let image = NSImage(contentsOf: candidate) { return image }
        }
        return nil
    }
}

private enum RemoteImageAsset {
    static func image(for remote: SupportedRemoteID) -> NSImage? {
        let name = "chromecast-voice-remote"
        let candidates: [URL?] = [
            Bundle.main.resourceURL?
                .appendingPathComponent("RemoteImages", isDirectory: true)
                .appendingPathComponent("\(name).png"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/RemoteImages/\(name).png")
        ]
        for candidate in candidates.compactMap({ $0 }) {
            if let image = NSImage(contentsOf: candidate) { return image }
        }
        return nil
    }
}

private enum ConsoleModal: Identifiable {
    case permission(PermissionKind)

    var id: String {
        switch self {
        case .permission(let kind): "permission-\(kind.id)"
        }
    }
}

private enum ConsolePage: String, CaseIterable, Identifiable {
    case mixer
    case mapping

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mixer: L10n.text("音频", "Audio")
        case .mapping: L10n.text("按键映射", "Key Mapping")
        }
    }

    var symbol: String {
        switch self {
        case .mixer: "slider.horizontal.3"
        case .mapping: "keyboard"
        }
    }
}

@MainActor
private final class ConsoleViewModel: ObservableObject {
    @Published var selectedPage: ConsolePage = CommandLine.arguments.contains(
        "--mapping-window-demo"
    ) ? .mapping : .mixer
    @Published var status = "启动中"
    @Published var hidConnected = false
    @Published var bleConnected = false
    @Published var remoteStreaming = false
    @Published var macInputEnabled = true
    @Published var remoteInputEnabled = true
    @Published var secondInputDevices: [AudioInputDevice] = []
    @Published var secondInputDeviceUID = ""
    @Published var secondInputDeviceName = ""
    @Published var secondInputCapturing = false
    @Published var voiceApps = VoiceInputAppCatalog.all
    @Published var selectedVoiceAppID = AppStorage.selectedVoiceInputAppID
    @Published var pttShortcut = AppStorage.pttShortcut
    @Published var toggleShortcut = AppStorage.toggleShortcut
    @Published var shortcutError: String?
    @Published var voiceIsRecording = false
    @Published var voiceInput = "--"
    @Published var voiceInputWarning: String?
    @Published var driverAvailable = false
    @Published var macLevelDB = -120.0
    @Published var remoteLevelDB = -120.0
    @Published var microphoneGranted = false
    @Published var accessibilityGranted = false
    @Published var inputMonitoringGranted = false
    @Published var bluetoothGranted = false
    @Published var chromecastConnected = false
    @Published var activeModal: ConsoleModal?
    var onStopMicrophone: (() -> Void)?
    var onRestartApp: (() -> Void)?
    var onMacInputEnabledChanged: ((Bool) -> Void)?
    var onRemoteInputEnabledChanged: ((Bool) -> Void)?
    var onSecondInputDeviceChanged: ((String) -> Void)?
    var onShortcutsChanged: (() -> Void)?
    var onVoiceInputAppChanged: ((VoiceInputApp) -> Void)?
    var onRemoteMappingEnabledChanged: ((SupportedRemoteID, Bool) -> Void)?

    var voiceApp: VoiceInputApp {
        VoiceInputAppCatalog.app(id: selectedVoiceAppID)
    }
    var voiceUsesVRemote: Bool { voiceInput.contains("vRemoteDr 2ch") }

    func setVoiceInputApp(_ id: String) {
        let app = VoiceInputAppCatalog.app(id: id)
        guard app.isSupported, app.id != selectedVoiceAppID else { return }
        selectedVoiceAppID = app.id
        AppStorage.selectedVoiceInputAppID = app.id
        pttShortcut = AppStorage.shortcut(for: app.id, mode: .pushToTalk)
        toggleShortcut = AppStorage.shortcut(for: app.id, mode: .toggle)
        shortcutError = nil
        onVoiceInputAppChanged?(app)
        onShortcutsChanged?()
    }

    func setPTTShortcut(_ shortcut: TriggerShortcut) {
        guard shortcut != toggleShortcut else {
            shortcutError = L10n.text(
                "按住说话和点按切换不能使用同一个快捷键。",
                "Push-to-talk and toggle cannot use the same shortcut."
            )
            return
        }
        pttShortcut = shortcut
        shortcutError = nil
        AppStorage.setShortcut(
            shortcut,
            for: selectedVoiceAppID,
            mode: .pushToTalk
        )
        onShortcutsChanged?()
    }

    func setToggleShortcut(_ shortcut: TriggerShortcut) {
        guard shortcut != pttShortcut else {
            shortcutError = L10n.text(
                "按住说话和点按切换不能使用同一个快捷键。",
                "Push-to-talk and toggle cannot use the same shortcut."
            )
            return
        }
        toggleShortcut = shortcut
        shortcutError = nil
        AppStorage.setShortcut(
            shortcut,
            for: selectedVoiceAppID,
            mode: .toggle
        )
        onShortcutsChanged?()
    }

    func setRemoteMappingEnabled(_ enabled: Bool, remote: SupportedRemoteID) {
        RemoteMappingStore.shared.setEnabled(enabled, for: remote)
        onRemoteMappingEnabledChanged?(remote, enabled)
    }

    func setMacInputEnabled(_ enabled: Bool) {
        macInputEnabled = enabled
        onMacInputEnabledChanged?(enabled)
    }

    func setRemoteInputEnabled(_ enabled: Bool) {
        remoteInputEnabled = enabled
        onRemoteInputEnabledChanged?(enabled)
    }

    func setSecondInputDevice(_ uid: String) {
        guard secondInputDeviceUID != uid else { return }
        secondInputDeviceUID = uid
        onSecondInputDeviceChanged?(uid)
    }

    func refreshPermissions() {
        let demoMode = ProcessInfo.processInfo.environment["VREMOTER_PERMISSION_DEMO"] == "1"
            || CommandLine.arguments.contains("--permission-demo")
        if demoMode {
            microphoneGranted = false
            accessibilityGranted = false
            inputMonitoringGranted = false
            bluetoothGranted = false
            return
        }
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = CGPreflightListenEventAccess()
        if #available(macOS 11.0, *) {
            bluetoothGranted = CBManager.authorization == .allowedAlways
        } else {
            bluetoothGranted = true
        }
    }

    func openSettings(for kind: PermissionKind) {
        guard let url = kind.settingsURL else { return }
        NSWorkspace.shared.open(url)
        activeModal = nil
    }

    func openSoundInputSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Sound-Settings.extension?input",
            "x-apple.systempreferences:com.apple.preference.sound?input"
        ]
        for value in candidates {
            if let url = URL(string: value), NSWorkspace.shared.open(url) { break }
        }
    }

    func observeRemoteLevel(_ db: Double) {
        remoteLevelDB = db
    }

}

final class DebugWindowController: NSWindowController, NSWindowDelegate {
    private static let windowSize = NSSize(width: 775, height: 658)

    var onStopMicrophone: (() -> Void)?
    var onRestartApp: (() -> Void)?
    var onMacInputEnabledChanged: ((Bool) -> Void)?
    var onRemoteInputEnabledChanged: ((Bool) -> Void)?
    var onSecondInputDeviceChanged: ((String) -> Void)?
    var onShortcutsChanged: (() -> Void)?
    var onVoiceInputAppChanged: ((VoiceInputApp) -> Void)?
    var onRemoteMappingEnabledChanged: ((SupportedRemoteID, Bool) -> Void)?

    private let model = ConsoleViewModel()
    private var permissionTimer: Timer?

    init() {
        let windowSize = Self.windowSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("vRemoter 控制台", "vRemoter Console")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(
            red: 0.055,
            green: 0.059,
            blue: 0.067,
            alpha: 1
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = windowSize
        window.maxSize = windowSize
        super.init(window: window)
        window.delegate = self

        model.onStopMicrophone = { [weak self] in self?.onStopMicrophone?() }
        model.onRestartApp = { [weak self] in self?.onRestartApp?() }
        model.onMacInputEnabledChanged = { [weak self] enabled in
            self?.onMacInputEnabledChanged?(enabled)
        }
        model.onRemoteInputEnabledChanged = { [weak self] enabled in
            self?.onRemoteInputEnabledChanged?(enabled)
        }
        model.onSecondInputDeviceChanged = { [weak self] uid in
            self?.onSecondInputDeviceChanged?(uid)
        }
        model.onShortcutsChanged = { [weak self] in
            self?.onShortcutsChanged?()
        }
        model.onVoiceInputAppChanged = { [weak self] app in
            self?.onVoiceInputAppChanged?(app)
        }
        model.onRemoteMappingEnabledChanged = { [weak self] remote, enabled in
            self?.onRemoteMappingEnabledChanged?(remote, enabled)
        }
        window.contentView = NSHostingView(
            rootView: StudioMixerView(model: model)
                .preferredColorScheme(.dark)
                .frame(
                    width: windowSize.width,
                    height: windowSize.height
                )
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        model.refreshPermissions()
        startPermissionTimer()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func update(
        status: String,
        hidConnected: Bool,
        bleConnected: Bool,
        remoteStreaming: Bool,
        macInputEnabled: Bool,
        remoteInputEnabled: Bool,
        secondInputDevices: [AudioInputDevice],
        secondInputDeviceUID: String,
        secondInputDeviceName: String,
        secondInputCapturing: Bool,
        voiceIsRecording: Bool,
        voiceInput: String,
        voiceInputWarning: String?,
        driverAvailable: Bool,
        chromecastConnected: Bool,
        macLevelDB: Double? = nil,
        remoteLevelDB: Double? = nil
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.model.status = status
            self.model.hidConnected = hidConnected
            self.model.bleConnected = bleConnected
            self.model.remoteStreaming = remoteStreaming
            self.model.macInputEnabled = macInputEnabled
            self.model.remoteInputEnabled = remoteInputEnabled
            self.model.secondInputDevices = secondInputDevices
            self.model.secondInputDeviceUID = secondInputDeviceUID
            self.model.secondInputDeviceName = secondInputDeviceName
            self.model.secondInputCapturing = secondInputCapturing
            self.model.voiceIsRecording = voiceIsRecording
            self.model.voiceInput = voiceInput
            self.model.voiceInputWarning = voiceInputWarning
            self.model.driverAvailable = driverAvailable
            self.model.chromecastConnected = chromecastConnected
            if let macLevelDB { self.model.macLevelDB = macLevelDB }
            if let remoteLevelDB { self.model.remoteLevelDB = remoteLevelDB }
            self.model.refreshPermissions()
        }
    }

    func updateMacLevel(_ db: Double) {
        DispatchQueue.main.async { [weak self] in self?.model.macLevelDB = db }
    }

    func updateRemoteLevel(_ db: Double) {
        DispatchQueue.main.async { [weak self] in self?.model.observeRemoteLevel(db) }
    }

    func windowWillClose(_ notification: Notification) {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    private func startPermissionTimer() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                self?.model.refreshPermissions()
            }
        }
    }
}

private struct StudioMixerView: View {
    @ObservedObject var model: ConsoleViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 68)
            if model.selectedPage == .mixer {
                Spacer().frame(height: 15)
                mixer
                    .frame(height: 288)
                Spacer().frame(height: 17)
                statusPanel
                    .frame(height: 230)
            } else {
                Spacer().frame(height: 15)
                KeyMappingView(model: model)
                    .frame(height: 535)
            }
        }
        .padding(20)
        .frame(width: 775, height: 658)
        .background(ConsoleTheme.panel)
        .sheet(item: $model.activeModal) { modal in
            switch modal {
            case .permission(let kind):
                PermissionGuideView(
                    kind: kind,
                    onCancel: { model.activeModal = nil },
                    onOpenSettings: { model.openSettings(for: kind) }
                )
            }
        }
    }

    /// 主界面副标题：当前版本号 + 渠道后缀（如「1.2.3 Beta」）。
    /// Beta 后缀来自 Info.plist 的 VRemoterBetaSuffix；发布正式版时置空即可。
    private var versionLabel: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "dev"
        let suffix = Bundle.main.object(
            forInfoDictionaryKey: "VRemoterBetaSuffix"
        ) as? String ?? ""
        return version + suffix
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: LogoAsset.image)
                .resizable()
                .interpolation(.high)
                .frame(width: 45, height: 45)
            VStack(alignment: .leading, spacing: 1) {
                Text("vRemoter")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(ConsoleTheme.text)
                Text(versionLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ConsoleTheme.secondary)
            }
            ConsolePageSelector(selection: $model.selectedPage)
                .frame(width: 202)
            Spacer()
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                Text(model.remoteStreaming
                    ? L10n.text("录音中", "Recording")
                    : statusText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
            if model.remoteStreaming {
                Button(L10n.text("结束录音", "Stop")) { model.onStopMicrophone?() }
                    .buttonStyle(ConsoleButtonStyle(
                        tone: ConsoleButtonTone.error,
                        compact: true,
                        consoleSized: true
                    ))
            }
        }
        .padding(.horizontal, 20)
        .background(panelBackground(ConsoleTheme.surface, radius: 19))
    }

    private var statusText: String {
        if !model.microphoneGranted || !model.accessibilityGranted || !model.inputMonitoringGranted {
            return L10n.text("需要处理", "Action needed")
        }
        if model.hidConnected && model.bleConnected {
            return L10n.text("正在运行", "Running")
        }
        return L10n.text("正在连接", "Connecting")
    }

    private var statusColor: Color {
        if model.remoteStreaming { return ConsoleTheme.amber }
        if !model.microphoneGranted || !model.accessibilityGranted || !model.inputMonitoringGranted {
            return ConsoleTheme.red
        }
        return model.hidConnected && model.bleConnected
            ? ConsoleTheme.green
            : ConsoleTheme.amber
    }

    private var mixer: some View {
        HStack(spacing: 0) {
            InputChannelView(
                title: L10n.text("电脑麦克风", "Computer Mic"),
                subtitle: model.secondInputDeviceName,
                db: model.macLevelDB,
                enabled: model.macInputEnabled,
                capturing: model.secondInputCapturing,
                participationNote: model.voiceApp.id == VoiceInputAppCatalog.weType.id
                    ? L10n.text(
                        "键盘触发时参与混合",
                        "In mix on keyboard trigger"
                    )
                    : nil,
                devices: model.secondInputDevices,
                selectedDeviceUID: model.secondInputDeviceUID,
                onSelectDevice: model.setSecondInputDevice,
                onToggle: model.setMacInputEnabled
            )
            .frame(width: 225)
            Divider().overlay(ConsoleTheme.lineSoft)
            InputChannelView(
                title: L10n.text("遥控器麦克风", "Remote Mic"),
                subtitle: L10n.text("蓝牙语音遥控器", "Bluetooth Voice Remote"),
                db: model.remoteLevelDB,
                enabled: model.remoteInputEnabled,
                onToggle: model.setRemoteInputEnabled
            )
            .frame(width: 224)
            Divider().overlay(ConsoleTheme.lineSoft)
            OutputChannelView(model: model)
                .frame(width: 284)
        }
        .background(panelBackground(ConsoleTheme.surface2, radius: 19))
        .clipped()
    }

    private var statusPanel: some View {
        VStack(spacing: 0) {
            StatusRow(
                title: model.voiceApp.title,
                value: voiceStatusValue,
                tone: voiceStatusTone,
                action: nil,
                onAction: {}
            )
            StatusRow(
                title: L10n.text("音频驱动", "Audio driver"),
                value: model.driverAvailable
                    ? L10n.text("vRemoteDr 2ch 可用", "vRemoteDr 2ch available")
                    : L10n.text("未安装或需要修复", "Missing or needs repair"),
                tone: model.driverAvailable ? .good : .error,
                action: model.driverAvailable ? nil : L10n.text("打开声音", "Open Sound"),
                onAction: model.openSoundInputSettings
            )
            StatusRow(
                title: L10n.text("遥控器连接", "Remote connection"),
                value: remoteConnectionValue,
                tone: model.hidConnected && model.bleConnected ? .good : .warning,
                action: model.hidConnected && model.bleConnected
                    ? nil
                    : L10n.text("蓝牙设置", "Bluetooth settings"),
                onAction: { model.activeModal = .permission(.bluetooth) }
            )
            StatusRow(
                title: L10n.text("麦克风权限", "Microphone"),
                value: model.microphoneGranted
                    ? L10n.text("已授权", "Granted")
                    : L10n.text("未授权", "Not granted"),
                tone: model.microphoneGranted ? .good : .error,
                action: model.microphoneGranted ? nil : L10n.text("去授权", "Grant"),
                onAction: { model.activeModal = .permission(.microphone) }
            )
            StatusRow(
                title: L10n.text("辅助功能权限", "Accessibility"),
                value: model.accessibilityGranted
                    ? L10n.text("已授权", "Granted")
                    : L10n.text("语音键无法正确映射", "Voice key mapping unavailable"),
                tone: model.accessibilityGranted ? .good : .error,
                action: model.accessibilityGranted ? nil : L10n.text("去授权", "Grant"),
                onAction: { model.activeModal = .permission(.accessibility) }
            )
            StatusRow(
                title: L10n.text("输入监控权限", "Input Monitoring"),
                value: model.inputMonitoringGranted
                    ? L10n.text("已授权", "Granted")
                    : L10n.text("无法监听遥控器语音键", "Cannot monitor remote voice key"),
                tone: model.inputMonitoringGranted ? .good : .warning,
                action: model.inputMonitoringGranted ? nil : L10n.text("去授权", "Grant"),
                onAction: { model.activeModal = .permission(.inputMonitoring) }
            )
        }
        .padding(.horizontal, 15)
        .background(panelBackground(ConsoleTheme.surface, radius: 19))
    }

    private var remoteConnectionValue: String {
        if model.hidConnected && model.bleConnected {
            return model.remoteStreaming
                ? L10n.text("HID · BLE · 语音流传输中", "HID · BLE · Streaming")
                : L10n.text("HID · BLE 已就绪", "HID · BLE ready")
        }
        if model.hidConnected || model.bleConnected {
            return L10n.text("正在连接语音服务", "Connecting voice service")
        }
        return L10n.text("HID 与 BLE 未连接", "HID and BLE disconnected")
    }

    private var voiceStatusValue: String {
        if let warning = model.voiceInputWarning {
            return warning
        }
        if model.voiceApp.canObserveRecording {
            if model.voiceIsRecording {
                return model.voiceUsesVRemote
                    ? L10n.text(
                        "vRemoteDr 2ch · 录音中",
                        "vRemoteDr 2ch · Recording"
                    )
                    : model.voiceInput
            }
            return L10n.text("当前未录音", "Not recording")
        }
        if model.voiceIsRecording {
            return model.voiceUsesVRemote
                ? L10n.text(
                    "麦克风 · vRemoteDr 2ch",
                    "Microphone · vRemoteDr 2ch"
                )
                : L10n.text(
                    "麦克风 · \(model.voiceInput)",
                    "Microphone · \(model.voiceInput)"
                )
        }
        return L10n.text("已就绪", "Ready")
    }

    private var voiceStatusTone: StatusTone {
        if model.voiceInputWarning != nil { return .warning }
        if model.voiceApp.canObserveRecording,
           model.voiceIsRecording,
           !model.voiceUsesVRemote {
            return .error
        }
        return .good
    }

}

private struct ConsolePageSelector: View {
    @Binding var selection: ConsolePage

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ConsolePage.allCases) { page in
                Button {
                    selection = page
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: page.symbol)
                        Text(page.title)
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(
                        selection == page
                            ? ConsoleTheme.text
                            : ConsoleTheme.secondary
                    )
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(
                        selection == page
                            ? ConsoleTheme.surface2
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(page.title)
            }
        }
        .padding(3)
        .background(ConsoleTheme.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }
}

private struct KeyMappingView: View {
    @ObservedObject var model: ConsoleViewModel
    @ObservedObject private var mappings = RemoteMappingStore.shared
    @State private var selectedDevice: SupportedRemoteID = .chromecast
    @State private var recordingShortcut: VoiceGestureMode?

    var body: some View {
        VStack(spacing: 14) {
            triggerPanel
                .frame(height: 178)
            HStack(spacing: 14) {
                devicePanel
                    .frame(width: 238)
                mappingPanel
            }
        }
    }

    private var triggerPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.badge.mic")
                    .foregroundStyle(ConsoleTheme.green)
                Text(L10n.text("语音输入与触发键", "Voice input & trigger"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ConsoleTheme.text)
                Spacer(minLength: 8)
                if model.remoteStreaming {
                    Text(L10n.text("录音结束后可修改", "Stop recording to change"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(ConsoleTheme.tertiary)
                }
                Menu {
                    ForEach(model.voiceApps) { app in
                        Button {
                            model.setVoiceInputApp(app.id)
                        } label: {
                            if app.id == model.selectedVoiceAppID {
                                Label(app.title, systemImage: "checkmark")
                            } else {
                                Text(app.title)
                            }
                        }
                        .disabled(!app.isSupported)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(model.voiceApp.title)
                            .font(.system(size: 11.5, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundStyle(ConsoleTheme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(ConsoleTheme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(ConsoleTheme.line, lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(model.remoteStreaming)
            }
            HStack(spacing: 12) {
                shortcutCard(for: .pushToTalk)
                shortcutCard(for: .toggle)
            }
            if let error = model.shortcutError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(ConsoleTheme.amber)
            } else {
                Text(L10n.text(
                    "两个键必须不同；支持修饰键、单键和组合键。当前模式由微信输入法自动识别。",
                    "The two shortcuts must differ. Modifiers, single keys and combinations are supported. The active mode is detected from WeType."
                ))
                    .font(.system(size: 10.5))
                    .foregroundStyle(ConsoleTheme.secondary)
            }
            if let warning = model.voiceInputWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(ConsoleTheme.amber)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(panelBackground(ConsoleTheme.surface, radius: 17))
        .sheet(item: $recordingShortcut) { mode in
            TriggerShortcutRecorderView(
                title: mode.title,
                current: shortcut(for: mode),
                onCancel: { recordingShortcut = nil },
                onSave: { shortcut in
                    switch mode {
                    case .pushToTalk: model.setPTTShortcut(shortcut)
                    case .toggle: model.setToggleShortcut(shortcut)
                    }
                    recordingShortcut = nil
                }
            )
        }
    }

    private func shortcut(for mode: VoiceGestureMode) -> TriggerShortcut {
        switch mode {
        case .pushToTalk: model.pttShortcut
        case .toggle: model.toggleShortcut
        }
    }

    private func shortcutCard(for mode: VoiceGestureMode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle()
                    .fill(ConsoleTheme.green)
                    .frame(width: 6, height: 6)
                Text(mode.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ConsoleTheme.text)
                Spacer()
                Text(L10n.text("已配置", "Configured"))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(ConsoleTheme.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(ConsoleTheme.green.opacity(0.12))
                    .clipShape(Capsule())
            }
            Text(mode == .pushToTalk
                ? L10n.text("长按遥控器语音键", "Hold the remote voice key")
                : L10n.text("短按遥控器语音键", "Tap the remote voice key"))
                .font(.system(size: 10.5))
                .foregroundStyle(ConsoleTheme.secondary)
            HStack(spacing: 8) {
                Text(L10n.text("触发键", "Shortcut"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(ConsoleTheme.tertiary)
                Spacer(minLength: 6)
                Button {
                    recordingShortcut = mode
                } label: {
                    HStack(spacing: 6) {
                        Text(shortcut(for: mode).label)
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                        Image(systemName: "record.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(ConsoleTheme.green)
                    }
                    .foregroundStyle(ConsoleTheme.text)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(ConsoleTheme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(ConsoleTheme.line, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(model.remoteStreaming)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ConsoleTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(ConsoleTheme.line, lineWidth: 1)
        )
    }

    private var devicePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("支持的设备", "Supported devices"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ConsoleTheme.secondary)

            DeviceSelectionRow(
                title: SupportedRemoteID.chromecast.title,
                signature: SupportedRemoteID.chromecast.signature,
                connected: model.chromecastConnected,
                selected: selectedDevice == .chromecast
            ) { selectedDevice = .chromecast }

            Spacer()
            Label(
                L10n.text(
                    "设置跟随型号，不绑定某一只遥控器",
                    "Settings follow the model, not one unit"
                ),
                systemImage: "checkmark.shield.fill"
            )
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(ConsoleTheme.green)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .background(panelBackground(ConsoleTheme.surface, radius: 17))
    }

    private var mappingPanel: some View {
        HStack(spacing: 14) {
            VStack(spacing: 10) {
                RemoteProductImage(kind: selectedDevice)
                    .frame(width: 128)
                Text(L10n.text("14 个可映射键", "14 mappable buttons"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(ConsoleTheme.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding(.top, 14)
            .frame(width: 130)
            Divider().overlay(ConsoleTheme.lineSoft)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedDevice.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(ConsoleTheme.text)
                        Text(L10n.text("点击右侧菜单修改按键", "Use each menu to assign a key"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(ConsoleTheme.tertiary)
                    }
                    Spacer()
                    Toggle(
                        L10n.text("启用映射", "Enable"),
                        isOn: Binding(
                            get: { mappings.isEnabled(selectedDevice) },
                            set: { model.setRemoteMappingEnabled($0, remote: selectedDevice) }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                Divider().overlay(ConsoleTheme.lineSoft)
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(RemoteProfiles.buttons(for: selectedDevice)) { button in
                            MappingRow(
                                remote: selectedDevice,
                                button: button,
                                enabled: mappings.isEnabled(selectedDevice)
                            )
                        }
                    }
                }
                HStack {
                    if !mappings.isEnabled(selectedDevice) {
                        Label(
                            L10n.text("未启用时保持系统原行为", "System behavior is unchanged"),
                            systemImage: "info.circle"
                        )
                        .font(.system(size: 10.5))
                        .foregroundStyle(ConsoleTheme.secondary)
                    }
                    Spacer()
                    Button(L10n.text("恢复默认", "Reset")) {
                        mappings.reset(selectedDevice)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(ConsoleTheme.green)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(15)
        .background(panelBackground(ConsoleTheme.surface, radius: 17))
    }
}

private struct DeviceSelectionRow: View {
    let title: String
    let signature: String
    let connected: Bool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(connected ? ConsoleTheme.green : ConsoleTheme.tertiary)
                        .frame(width: 8, height: 8)
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(ConsoleTheme.text)
                        .lineLimit(1)
                }
                HStack {
                    Text(signature)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(ConsoleTheme.tertiary)
                    Spacer()
                    Text(connected
                        ? L10n.text("已连接", "Connected")
                        : L10n.text("未连接", "Offline"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(connected ? ConsoleTheme.green : ConsoleTheme.tertiary)
                }
            }
            .padding(11)
            .background(selected ? ConsoleTheme.surface2 : ConsoleTheme.black.opacity(0.35))
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(selected ? ConsoleTheme.green.opacity(0.8) : ConsoleTheme.lineSoft, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(connected ? "connected" : "offline")")
    }
}

private struct MappingRow: View {
    @ObservedObject private var mappings = RemoteMappingStore.shared
    @State private var showRecorder = false
    let remote: SupportedRemoteID
    let button: RemoteButtonDefinition
    let enabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: button.symbol)
                .frame(width: 18)
                .foregroundStyle(button.voiceControlled ? ConsoleTheme.green : ConsoleTheme.secondary)
            Text(button.title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(ConsoleTheme.text)
                .frame(width: 76, alignment: .leading)
            Spacer(minLength: 4)
            if !button.remappable {
                Text(L10n.text("设备内部功能", "Device-only function"))
                    .font(.system(size: 11))
                    .foregroundStyle(ConsoleTheme.tertiary)
            } else if button.voiceControlled {
                Text(RemoteMappingTarget.voiceInput.title)
                    .font(.system(size: 11))
                    .foregroundStyle(ConsoleTheme.green)
            } else {
                HStack(spacing: 4) {
                    Picker(
                        button.title,
                        selection: Binding(
                            get: { mappings.target(for: button, remote: remote) },
                            set: { target in
                                if target == .custom {
                                    showRecorder = true
                                } else {
                                    mappings.setTarget(target, for: button, remote: remote)
                                }
                            }
                        )
                    ) {
                        ForEach(RemoteMappingTarget.allCases.filter { $0 != .voiceInput }) { target in
                            Text(target == .custom
                                ? customMenuTitle
                                : target.title
                            ).tag(target)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 142)
                    if mappings.target(for: button, remote: remote) == .custom {
                        Button { showRecorder = true } label: {
                            Image(systemName: "record.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ConsoleTheme.green)
                        .help(L10n.text("重新录制按键", "Record again"))
                    }
                }
            }
        }
        .frame(height: 28)
        .padding(.horizontal, 9)
        .background(ConsoleTheme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .sheet(isPresented: $showRecorder) {
            KeyboardShortcutCaptureView(
                buttonTitle: button.title,
                onCancel: { showRecorder = false },
                onSave: { shortcut in
                    mappings.setCustomShortcut(
                        shortcut,
                        for: button,
                        remote: remote
                    )
                    showRecorder = false
                }
            )
        }
    }

    /// 「自定义」菜单项标题：已录制显示「自定义（当前：⇧⌘K）」，未录制显示「自定义…」。
    /// 不改动 RemoteMappingStore.targetTitle()——它被 HID 桥用于状态上报。
    private var customMenuTitle: String {
        let current = mappings.targetTitle(for: button, remote: remote)
        if mappings.customShortcut(for: button, remote: remote) != nil {
            return L10n.text(
                "自定义（当前：\(current)）",
                "Custom (Current: \(current))"
            )
        }
        return L10n.text("自定义…", "Custom…")
    }
}

private struct TriggerShortcutRecorderView: View {
    let title: String
    let current: TriggerShortcut
    let onCancel: () -> Void
    let onSave: (TriggerShortcut) -> Void
    @State private var captured: TriggerShortcut?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.text(
                    "录制\(title)快捷键",
                    "Record \(title) shortcut"
                ))
                    .font(.system(size: 20, weight: .semibold))
                Text(L10n.text(
                    "按下一个修饰键、单键或组合键。",
                    "Press a modifier, a single key, or a combination."
                ))
                    .font(.system(size: 13))
                    .foregroundStyle(ConsoleTheme.secondary)
            }

            TriggerShortcutCaptureView { shortcut in
                captured = shortcut
            }
            .frame(height: 82)
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .stroke(
                        captured == nil ? ConsoleTheme.line : ConsoleTheme.green,
                        lineWidth: 1.5
                    )
            )
            .overlay {
                VStack(spacing: 5) {
                    Text(captured?.label ?? current.label)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(captured == nil ? ConsoleTheme.secondary : ConsoleTheme.text)
                    Text(L10n.text(
                        "支持左右修饰键、单键和组合键",
                        "Left/right modifiers, single keys and combinations"
                    ))
                        .font(.system(size: 10.5))
                        .foregroundStyle(ConsoleTheme.tertiary)
                }
                .allowsHitTesting(false)
            }

            HStack {
                Button(L10n.text("取消", "Cancel"), action: onCancel)
                Spacer()
                Button(L10n.text("保存快捷键", "Save Shortcut")) {
                    if let captured { onSave(captured) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(captured == nil)
            }
        }
        .padding(24)
        .frame(width: 430, height: 245)
        .background(ConsoleTheme.panel)
        .foregroundStyle(ConsoleTheme.text)
    }
}

private struct TriggerShortcutCaptureView: NSViewRepresentable {
    let onCapture: (TriggerShortcut) -> Void

    func makeNSView(context: Context) -> TriggerShortcutCaptureNSView {
        let view = TriggerShortcutCaptureNSView()
        view.onCapture = onCapture
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(
        _ nsView: TriggerShortcutCaptureNSView,
        context: Context
    ) {
        nsView.onCapture = onCapture
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

private final class TriggerShortcutCaptureNSView: NSView {
    var onCapture: ((TriggerShortcut) -> Void)?
    private var activeModifiers: [CGKeyCode: TriggerModifier] = [:]
    private var sawNonModifierKey = false
    private var captured = false

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat, !captured else { return }
        let keyCode = CGKeyCode(event.keyCode)
        if TriggerShortcut.modifier(for: keyCode) != nil {
            return
        }
        sawNonModifierKey = true
        captured = true
        let shortcut = TriggerShortcut(
            keyCode: keyCode,
            modifiers: Array(activeModifiers.values)
        )
        onCapture?(shortcut)
    }

    override func keyUp(with event: NSEvent) {
        // A key release is irrelevant once keyDown captured the shortcut.
    }

    override func flagsChanged(with event: NSEvent) {
        guard !captured else { return }
        let keyCode = CGKeyCode(event.keyCode)
        guard let modifier = TriggerShortcut.modifier(for: keyCode) else {
            return
        }
        let cgFlags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        let isDown = cgFlags.contains(modifier.flag)
        if isDown {
            activeModifiers[keyCode] = modifier
            return
        }
        let wasActive = activeModifiers.removeValue(forKey: keyCode) != nil
        guard wasActive, !sawNonModifierKey, activeModifiers.isEmpty else {
            return
        }
        captured = true
        onCapture?(TriggerShortcut(keyCode: nil, modifiers: [modifier]))
    }
}

private struct KeyboardShortcutCaptureView: View {
    let buttonTitle: String
    let onCancel: () -> Void
    let onSave: (RemoteCustomShortcut) -> Void
    @State private var captured: RemoteCustomShortcut?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.text("录制键盘按键", "Record Keyboard Key"))
                    .font(.system(size: 20, weight: .semibold))
                Text(L10n.text(
                    "为“\(buttonTitle)”按下一个按键或组合键。",
                    "Press a key or shortcut for “\(buttonTitle)”."
                ))
                    .font(.system(size: 13))
                    .foregroundStyle(ConsoleTheme.secondary)
            }

            KeyboardEventCaptureView { shortcut in
                captured = shortcut
            }
            .frame(height: 82)
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .stroke(
                        captured == nil ? ConsoleTheme.line : ConsoleTheme.green,
                        lineWidth: 1.5
                    )
            )
            .overlay {
                VStack(spacing: 5) {
                    Text(captured?.label ?? L10n.text("现在按下键盘按键", "Press a key now"))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(captured == nil ? ConsoleTheme.secondary : ConsoleTheme.text)
                    Text(L10n.text("支持 Command / Option / Control / Shift 组合", "Command / Option / Control / Shift are supported"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(ConsoleTheme.tertiary)
                }
                .allowsHitTesting(false)
            }

            HStack {
                Button(L10n.text("取消", "Cancel"), action: onCancel)
                Spacer()
                Button(L10n.text("保存映射", "Save Mapping")) {
                    if let captured { onSave(captured) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(captured == nil)
            }
        }
        .padding(24)
        .frame(width: 430, height: 245)
        .background(ConsoleTheme.panel)
        .foregroundStyle(ConsoleTheme.text)
    }
}

private struct KeyboardEventCaptureView: NSViewRepresentable {
    let onCapture: (RemoteCustomShortcut) -> Void

    func makeNSView(context: Context) -> KeyboardCaptureNSView {
        let view = KeyboardCaptureNSView()
        view.onCapture = onCapture
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyboardCaptureNSView, context: Context) {
        nsView.onCapture = onCapture
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

private final class KeyboardCaptureNSView: NSView {
    var onCapture: ((RemoteCustomShortcut) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat else { return }
        onCapture?(Self.shortcut(from: event))
    }

    private static func shortcut(from event: NSEvent) -> RemoteCustomShortcut {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var flags: CGEventFlags = []
        var prefix = ""
        if modifiers.contains(.control) {
            flags.insert(.maskControl)
            prefix += "⌃"
        }
        if modifiers.contains(.option) {
            flags.insert(.maskAlternate)
            prefix += "⌥"
        }
        if modifiers.contains(.shift) {
            flags.insert(.maskShift)
            prefix += "⇧"
        }
        if modifiers.contains(.command) {
            flags.insert(.maskCommand)
            prefix += "⌘"
        }

        let special: [UInt16: String] = [
            0x24: "Return", 0x30: "Tab", 0x31: "Space", 0x33: "Delete",
            0x35: "Esc", 0x73: "Home", 0x77: "End", 0x74: "Page Up",
            0x79: "Page Down", 0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
            0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
            0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
            0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
        ]
        let key = special[event.keyCode]
            ?? event.charactersIgnoringModifiers?.uppercased()
            ?? String(format: "Key 0x%02X", event.keyCode)
        return RemoteCustomShortcut(
            keyCode: event.keyCode,
            flags: flags.rawValue,
            label: prefix + key
        )
    }
}

private struct RemoteProductImage: View {
    let kind: SupportedRemoteID

    var body: some View {
        Group {
            if let image = RemoteImageAsset.image(for: kind) {
                if kind == .chromecast {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 112, height: 304)
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 92, height: 260)
                }
            } else {
                Label(
                    L10n.text("遥控器图片缺失", "Remote image unavailable"),
                    systemImage: "photo.badge.exclamationmark"
                )
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(ConsoleTheme.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: kind == .chromecast ? 304 : 260)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.title)
    }
}

private struct InputChannelView: View {
    let title: String
    let subtitle: String
    let db: Double
    let enabled: Bool
    var capturing: Bool?
    var participationNote: String?
    var showTestHint = false
    var devices: [AudioInputDevice] = []
    var selectedDeviceUID = ""
    var onSelectDevice: ((String) -> Void)?
    let onToggle: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(enabled ? ConsoleTheme.text : ConsoleTheme.tertiary)
                .lineLimit(1)
            if let onSelectDevice {
                if devices.isEmpty {
                    Text(L10n.text("未找到输入设备", "No input device"))
                        .font(.system(size: 13))
                        .foregroundStyle(ConsoleTheme.tertiary)
                        .padding(.top, 4)
                } else {
                    Picker(
                        L10n.text("输入设备", "Input device"),
                        selection: Binding(
                            get: { selectedDeviceUID },
                            set: { onSelectDevice($0) }
                        )
                    ) {
                        ForEach(devices) { device in
                            Text(device.name).tag(device.uid)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(maxWidth: 172, alignment: .leading)
                    .padding(.top, 2)
                }
            } else {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(enabled ? ConsoleTheme.secondary : ConsoleTheme.tertiary)
                    .padding(.top, 4)
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(enabled ? ConsoleTheme.green : ConsoleTheme.tertiary)
                    .frame(width: 10, height: 10)
                Text(activityText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(enabled ? ConsoleTheme.secondary : ConsoleTheme.tertiary)
                Spacer()
                Text(dbText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(ConsoleTheme.secondary)
            }
            .padding(.top, 15)
            MeterView(db: enabled ? db : -120, color: ConsoleTheme.green, count: 10)
                .padding(.top, showTestHint ? 35 : 15)
                .overlay(alignment: .topLeading) {
                    if showTestHint {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                            Text(L10n.text(
                                "按一下遥控器麦克风键测试",
                                "Press the remote mic button"
                            ))
                                .lineLimit(1)
                        }
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(ConsoleTheme.text)
                        .padding(.horizontal, 9)
                        .frame(height: 25)
                        .background(ConsoleTheme.black.opacity(0.96))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(ConsoleTheme.green.opacity(0.8), lineWidth: 1)
                        )
                        .offset(y: -1)
                    }
                }
            HStack {
                Text(L10n.text("低", "Low"))
                Spacer()
                Text(L10n.text("高", "High"))
            }
            .font(.system(size: 11))
            .foregroundStyle(ConsoleTheme.tertiary)
            // 不再固定 141pt：电平条 10 段实际宽 176pt，写死宽度导致“高”不贴电平条右缘。
            .padding(.top, 6)
            HStack(spacing: 9) {
                Toggle(String(), isOn: Binding(
                    get: { enabled },
                    set: { onToggle($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                Text(enabled
                    ? L10n.text("打开", "On")
                    : L10n.text("关闭", "Off"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(enabled ? ConsoleTheme.text : ConsoleTheme.tertiary)
                Spacer()
            }
            .padding(.top, 31)
            HStack(spacing: 4) {
                Text(enabled
                    ? (participationNote ?? L10n.text("参与混合", "In mix"))
                    : L10n.text("不参与混合", "Not in mix"))
                Spacer()
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(enabled ? ConsoleTheme.secondary : ConsoleTheme.tertiary)
            .padding(.top, 22)
        }
        .padding(.horizontal, 23)
        .padding(.top, 23)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(enabled ? 1 : 0.58)
    }

    private var activityText: String {
        guard enabled else { return L10n.text("不参与混合", "Muted") }
        if let capturing, !capturing {
            return L10n.text("就绪", "Ready")
        }
        return L10n.text("有声音", "Active")
    }

    private var dbText: String {
        guard enabled, db > -100 else { return "−∞" }
        return String(format: "%.0f dB", db)
    }
}

private struct OutputChannelView: View {
    @ObservedObject var model: ConsoleViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.text("混合输出", "Mixed Output"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(ConsoleTheme.text)
            Text(L10n.text("发送给微信输入法", "Sent to WeType"))
                .font(.system(size: 13))
                .foregroundStyle(ConsoleTheme.secondary)
                .padding(.top, 4)
            HStack(spacing: 6) {
                Circle().fill(outputError ? ConsoleTheme.red : ConsoleTheme.amber)
                    .frame(width: 10, height: 10)
                Text(outputError
                    ? L10n.text("未输出", "No output")
                    : model.remoteStreaming
                        ? L10n.text("正在输出", "Sending")
                        : L10n.text("等待录音", "Waiting"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(outputError ? ConsoleTheme.red : ConsoleTheme.amber)
                Spacer()
                Text(outputError ? "−∞" : "−9 dB")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(ConsoleTheme.secondary)
            }
            .padding(.top, 15)
            MeterView(
                db: outputError ? -120 : max(model.macLevelDB, model.remoteLevelDB),
                color: ConsoleTheme.amber,
                count: 14
            )
            .padding(.top, 15)
            HStack {
                Text(L10n.text("低", "Low"))
                Spacer()
                Text(L10n.text("高", "High"))
            }
            .font(.system(size: 11))
            .foregroundStyle(ConsoleTheme.tertiary)
            .frame(width: 188)
            .padding(.top, 6)
            HStack(spacing: 8) {
                Circle().fill(ConsoleTheme.amber).frame(width: 10, height: 10)
                Text(L10n.text("两路已合并", "Inputs mixed"))
                    .font(.system(
                        size: AppLanguage.selected.usesEnglish ? 11 : 14,
                        weight: .semibold
                    ))
                    .foregroundStyle(ConsoleTheme.amber)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer()
                Text("vRemoteDr 2ch")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ConsoleTheme.text)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 15)
            .frame(height: 60)
            .background(panelBackground(ConsoleTheme.surface, radius: 14))
            .padding(.top, 25)
            Text(outputError
                ? L10n.text("等待音频链路恢复", "Waiting for audio route")
                : L10n.text("微信输入法正在接收", "WeType is receiving"))
                .font(.system(size: 11))
                .foregroundStyle(outputError ? ConsoleTheme.red : ConsoleTheme.secondary)
                .padding(.top, 15)
        }
        .padding(.horizontal, 23)
        .padding(.top, 23)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ConsoleTheme.amberDeep)
        .overlay(alignment: .top) {
            Rectangle().fill(ConsoleTheme.amber).frame(height: 3)
        }
    }

    private var outputError: Bool {
        !model.driverAvailable
            || (model.voiceApp.canObserveRecording
                && model.voiceIsRecording
                && !model.voiceUsesVRemote)
    }
}

private struct MeterView: View {
    let db: Double
    let color: Color
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < activeCount ? color : ConsoleTheme.black)
                    .frame(width: count > 10 ? 13 : 14, height: 21)
            }
        }
    }

    private var activeCount: Int {
        guard db > -100 else { return 0 }
        return min(count, max(0, Int(((db + 60) / 60) * Double(count))))
    }
}

private enum StatusTone { case good, warning, error }

private struct StatusPill: View {
    let title: String
    let tone: StatusTone

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 13)
        .frame(height: 28)
        .background(background)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.9), lineWidth: 1))
    }

    private var color: Color {
        switch tone {
        case .good: ConsoleTheme.green
        case .warning: ConsoleTheme.amber
        case .error: ConsoleTheme.red
        }
    }

    private var background: Color {
        switch tone {
        case .good: ConsoleTheme.black
        case .warning: ConsoleTheme.amberDeep
        case .error: ConsoleTheme.redDeep
        }
    }
}

private struct StatusRow: View {
    let title: String
    let value: String
    let tone: StatusTone
    let action: String?
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ConsoleTheme.secondary)
                .frame(width: 145, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tone == .good ? ConsoleTheme.text : color)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let action {
                Button(action, action: onAction)
                    .buttonStyle(ConsoleButtonStyle(
                        tone: tone,
                        compact: true,
                        consoleSized: true
                    ))
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 35)
        .background(tone == .good ? Color.clear : color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var color: Color {
        switch tone {
        case .good: ConsoleTheme.green
        case .warning: ConsoleTheme.amber
        case .error: ConsoleTheme.red
        }
    }
}

private struct PermissionGuideView: View {
    let kind: PermissionKind
    let onCancel: () -> Void
    let onOpenSettings: () -> Void
    @State private var page = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(nsImage: LogoAsset.image)
                    .resizable()
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.system(size: 19, weight: .semibold))
                    Text(L10n.text(
                        "设置向导 · 第 \(page + 1) / \(kind.pageCount) 步",
                        "Setup guide · Step \(page + 1) of \(kind.pageCount)"
                    ))
                        .font(.system(size: 11))
                        .foregroundStyle(ConsoleTheme.secondary)
                }
                Spacer()
            }

            GuideScreenshot(kind: kind, page: $page)
                .frame(height: 350)

            Text(kind.guidance[page])
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ConsoleTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<kind.pageCount, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? ConsoleTheme.green : ConsoleTheme.line)
                            .frame(width: index == page ? 18 : 7, height: 7)
                    }
                }
                Spacer()
                Button(L10n.text("取消", "Cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(ConsoleButtonStyle(tone: .neutral))
                Button(L10n.text("立即设置", "Open Settings"), action: onOpenSettings)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(ConsoleButtonStyle(tone: ConsoleButtonTone.good))
            }
        }
        .padding(22)
        .frame(width: 620, height: 580)
        .background(ConsoleTheme.panel)
        .foregroundStyle(ConsoleTheme.text)
    }
}

private struct GuideScreenshot: View {
    let kind: PermissionKind
    @Binding var page: Int

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = GuideAsset.image(named: kind.screenshotName(for: page)) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    screenshotPlaceholder
                }

                RoundedRectangle(cornerRadius: 10)
                    .stroke(ConsoleTheme.red, lineWidth: 3)
                    .frame(
                        width: proxy.size.width * highlightWidth,
                        height: proxy.size.height * highlightHeight
                    )
                    .position(
                        x: proxy.size.width * highlightX,
                        y: proxy.size.height * highlightY
                    )

                HStack {
                    guideArrow(systemName: "chevron.left", enabled: page > 0) {
                        if page > 0 { page -= 1 }
                    }
                    Spacer()
                    guideArrow(systemName: "chevron.right", enabled: page < kind.pageCount - 1) {
                        if page < kind.pageCount - 1 { page += 1 }
                    }
                }
                .padding(.horizontal, 10)
            }
            .background(ConsoleTheme.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ConsoleTheme.line))
        }
    }

    private var screenshotPlaceholder: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("系统设置", "System Settings"))
                    .font(.system(size: 16, weight: .semibold))
                Text(L10n.text("隐私与安全性", "Privacy & Security"))
                    .foregroundStyle(ConsoleTheme.text)
                Text(kind.title.replacingOccurrences(of: "权限", with: ""))
                    .foregroundStyle(ConsoleTheme.green)
                Spacer()
            }
            .padding(20)
            .frame(width: 190, alignment: .leading)
            .background(ConsoleTheme.surface)
            VStack(alignment: .leading, spacing: 18) {
                Text(kind.title)
                    .font(.system(size: 18, weight: .semibold))
                Text(L10n.text(
                    "允许下方的应用访问此功能。",
                    "Allow the apps below to access this feature."
                ))
                    .foregroundStyle(ConsoleTheme.secondary)
                HStack {
                    Image(nsImage: LogoAsset.image).resizable().frame(width: 30, height: 30)
                    Text("vRemoter")
                    Spacer()
                    Toggle("", isOn: .constant(false)).labelsHidden()
                }
                .padding(12)
                .background(ConsoleTheme.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                Spacer()
            }
            .padding(20)
        }
        .foregroundStyle(ConsoleTheme.text)
    }

    private var secondPageY: CGFloat {
        switch kind {
        case .microphone: 0.92
        case .accessibility: 0.89
        case .inputMonitoring: 0.46
        case .bluetooth: 0.74
        }
    }

    private var highlightWidth: CGFloat {
        (page == 0 ? 0.38 : 0.45)
    }

    private var highlightHeight: CGFloat {
        0.10
    }

    private var highlightX: CGFloat {
        (page == 0 ? 0.255 : 0.62)
    }

    private var highlightY: CGFloat {
        (page == 0 ? 0.25 : secondPageY)
    }

    private func guideArrow(
        systemName: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 30, height: 30)
                .background(ConsoleTheme.black.opacity(0.82))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? ConsoleTheme.text : ConsoleTheme.tertiary)
        .disabled(!enabled)
    }

}

private enum ConsoleButtonTone { case neutral, good, warning, error }

private struct ConsoleButtonStyle: ButtonStyle {
    let tone: ConsoleButtonTone
    var compact = false
    var consoleSized = false

    init(tone: ConsoleButtonTone, compact: Bool = false, consoleSized: Bool = false) {
        self.tone = tone
        self.compact = compact
        self.consoleSized = consoleSized
    }

    init(tone: StatusTone, compact: Bool = false, consoleSized: Bool = false) {
        switch tone {
        case .good: self.tone = .good
        case .warning: self.tone = .warning
        case .error: self.tone = .error
        }
        self.compact = compact
        self.consoleSized = consoleSized
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .frame(height: buttonHeight)
            .background(configuration.isPressed ? background.opacity(0.65) : background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(foreground.opacity(0.85), lineWidth: 1)
            )
    }

    private var fontSize: CGFloat {
        if consoleSized { return compact ? 11 : 14 }
        return compact ? 9 : 11
    }

    private var horizontalPadding: CGFloat {
        if consoleSized { return compact ? 15 : 23 }
        return compact ? 12 : 18
    }

    private var buttonHeight: CGFloat {
        if consoleSized { return compact ? 30 : 43 }
        return compact ? 24 : 34
    }

    private var cornerRadius: CGFloat {
        if consoleSized { return compact ? 12 : 11 }
        return compact ? 10 : 9
    }

    private var foreground: Color {
        switch tone {
        case .neutral: ConsoleTheme.text
        case .good: ConsoleTheme.green
        case .warning: ConsoleTheme.amber
        case .error: ConsoleTheme.red
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: ConsoleTheme.black
        case .good: Color(red: 0.06, green: 0.25, blue: 0.16)
        case .warning: ConsoleTheme.amberDeep
        case .error: ConsoleTheme.redDeep
        }
    }
}

private func panelBackground(_ color: Color, radius: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: radius)
        .fill(color)
        .overlay(RoundedRectangle(cornerRadius: radius).stroke(ConsoleTheme.line, lineWidth: 1))
}
