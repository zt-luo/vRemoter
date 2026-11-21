import Foundation

enum AppStorage {
    static let loggingEnabledKey = "loggingEnabled"
    static let recordingEnabledKey = "recordingEnabled"
    static let macInputEnabledKey = "macInputEnabled"
    static let remoteInputEnabledKey = "remoteInputEnabled"
    static let secondInputDeviceUIDKey = "secondInputDeviceUID"
    static let weTypeTriggerModeKey = "weTypeTriggerMode"
    static let weTypePTTTriggerKeyKey = "weTypePTTTriggerKey"
    static let weTypeToggleTriggerKeyKey = "weTypeToggleTriggerKey"

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
            weTypeTriggerModeKey: VoiceGestureMode.pushToTalk.rawValue,
            weTypePTTTriggerKeyKey: InputTriggerKey.optionRight.rawValue,
            weTypeToggleTriggerKeyKey: InputTriggerKey.option.rawValue,
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

    static var weTypeTriggerMode: VoiceGestureMode {
        get {
            let raw = UserDefaults.standard.string(forKey: weTypeTriggerModeKey)
            return VoiceGestureMode(rawValue: raw ?? "") ?? .pushToTalk
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: weTypeTriggerModeKey)
        }
    }

    static var weTypePTTTriggerKey: InputTriggerKey {
        get {
            let raw = UserDefaults.standard.string(forKey: weTypePTTTriggerKeyKey)
            return InputTriggerKey(rawValue: raw ?? "") ?? .optionRight
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: weTypePTTTriggerKeyKey)
        }
    }

    static var weTypeToggleTriggerKey: InputTriggerKey {
        get {
            let raw = UserDefaults.standard.string(forKey: weTypeToggleTriggerKeyKey)
            return InputTriggerKey(rawValue: raw ?? "") ?? .option
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: weTypeToggleTriggerKeyKey)
        }
    }

    static var activeTriggerKey: InputTriggerKey {
        triggerKey(for: weTypeTriggerMode)
    }

    static func triggerKey(for mode: VoiceGestureMode) -> InputTriggerKey {
        switch mode {
        case .pushToTalk: weTypePTTTriggerKey
        case .toggle: weTypeToggleTriggerKey
        }
    }

    static func setTriggerKey(_ key: InputTriggerKey, for mode: VoiceGestureMode) {
        switch mode {
        case .pushToTalk: weTypePTTTriggerKey = key
        case .toggle: weTypeToggleTriggerKey = key
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
