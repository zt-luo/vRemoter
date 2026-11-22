import Foundation

enum AppStorage {
    static let loggingEnabledKey = "loggingEnabled"
    static let recordingEnabledKey = "recordingEnabled"
    static let macInputEnabledKey = "macInputEnabled"
    static let remoteInputEnabledKey = "remoteInputEnabled"
    static let remoteConnectionEnabledKey = "remoteConnectionEnabled"
    static let secondInputDeviceUIDKey = "secondInputDeviceUID"
    static let voiceInputSelectedAppKey = "voiceInput.selectedApp"
    static let voiceInputDetectedModeKey = "voiceInput.detectedMode"

    static let logsDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/vRemote", isDirectory: true)
    }()

    static let logFile = logsDirectory.appendingPathComponent("vRemote.log")

    static let applicationSupportDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/vRemote", isDirectory: true)
    }()

    static let recordingsDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/vRemote/Recordings",
                isDirectory: true
            )
    }()

    static func prepare() {
        UserDefaults.standard.register(defaults: [
            loggingEnabledKey: false,
            recordingEnabledKey: false,
            macInputEnabledKey: true,
            remoteInputEnabledKey: true,
            remoteConnectionEnabledKey: true,
            voiceInputSelectedAppKey: VoiceInputAppCatalog.weType.id,
            voiceInputDetectedModeKey: "",
            secondInputDeviceUIDKey: "",
        ])
        ensureDirectory(logsDirectory)
        ensureDirectory(applicationSupportDirectory)
        ensureDirectory(recordingsDirectory)

        // vRemote has its own storage namespace and never touches V1 data.
    }

    static var loggingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: loggingEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: loggingEnabledKey) }
    }

    static var recordingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: recordingEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: recordingEnabledKey) }
    }

    static var macInputEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: macInputEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: macInputEnabledKey) }
    }

    static var remoteInputEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: remoteInputEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: remoteInputEnabledKey) }
    }

    /// Whether vRemoter keeps its own BLE/HID connection to the remote alive.
    /// Disabling it saves the remote's battery; the setting is persistent.
    static var remoteConnectionEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: remoteConnectionEnabledKey) }
        set {
            UserDefaults.standard.set(
                newValue,
                forKey: remoteConnectionEnabledKey
            )
        }
    }

    static var selectedVoiceInputAppID: String {
        get {
            UserDefaults.standard.string(forKey: voiceInputSelectedAppKey)
                ?? VoiceInputAppCatalog.weType.id
        }
        set {
            UserDefaults.standard.set(newValue, forKey: voiceInputSelectedAppKey)
        }
    }

    static var selectedVoiceInputApp: VoiceInputApp {
        VoiceInputAppCatalog.app(id: selectedVoiceInputAppID)
    }

    static func shortcutKey(
        appID: String,
        mode: VoiceGestureMode
    ) -> String {
        "voiceInput.\(appID).\(mode.rawValue).shortcut"
    }

    static func shortcut(
        for appID: String,
        mode: VoiceGestureMode
    ) -> TriggerShortcut {
        let key = shortcutKey(appID: appID, mode: mode)
        if let data = UserDefaults.standard.data(forKey: key),
           let shortcut = try? JSONDecoder().decode(
               TriggerShortcut.self,
               from: data
           ) {
            return shortcut
        }
        // Migration from the single-modifier trigger settings.
        let legacyKey = mode == .pushToTalk
            ? "weTypePTTTriggerKey"
            : "weTypeToggleTriggerKey"
        if let raw = UserDefaults.standard.string(forKey: legacyKey),
           let trigger = InputTriggerKey(rawValue: raw) {
            return trigger.shortcut
        }
        if mode == .pushToTalk,
           let raw = UserDefaults.standard.string(forKey: "inputTriggerKey"),
           let trigger = InputTriggerKey(rawValue: raw) {
            return trigger.shortcut
        }
        let app = VoiceInputAppCatalog.app(id: appID)
        return mode == .pushToTalk
            ? app.defaultPTTShortcut
            : app.defaultToggleShortcut
    }

    static func setShortcut(
        _ shortcut: TriggerShortcut,
        for appID: String,
        mode: VoiceGestureMode
    ) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        UserDefaults.standard.set(
            data,
            forKey: shortcutKey(appID: appID, mode: mode)
        )
    }

    static var pttShortcut: TriggerShortcut {
        shortcut(for: selectedVoiceInputAppID, mode: .pushToTalk)
    }

    static var toggleShortcut: TriggerShortcut {
        shortcut(for: selectedVoiceInputAppID, mode: .toggle)
    }

    static var detectedTriggerMode: VoiceGestureMode? {
        get {
            let key = voiceInputDetectedModeKey + "." + selectedVoiceInputAppID
            guard let raw = UserDefaults.standard.string(forKey: key) else {
                return nil
            }
            return VoiceGestureMode(rawValue: raw)
        }
        set {
            let key = voiceInputDetectedModeKey + "." + selectedVoiceInputAppID
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    static var secondInputDeviceUID: String {
        get { UserDefaults.standard.string(forKey: secondInputDeviceUIDKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: secondInputDeviceUIDKey) }
    }

    static func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    static func byteSize(of url: URL) -> UInt64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            ), values.isRegularFile == true else { continue }
            total += UInt64(values.fileSize ?? 0)
        }
        return total
    }

    static func clearFiles(in directory: URL) {
        let fm = FileManager.default
        ensureDirectory(directory)
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for file in files {
            try? fm.removeItem(at: file)
        }
    }

    static func formattedSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(bytes),
            countStyle: .file
        )
    }
}
