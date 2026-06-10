import Foundation

enum SettingsBackupError: LocalizedError {
    case invalidFile

    var errorDescription: String? {
        switch self {
        case .invalidFile: "Invalid settings backup file."
        }
    }
}

enum UserDefaultsBackupValue: Codable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case data(Data)

    enum CodingKeys: CodingKey { case type, string, bool, int, double, data }
    enum ValueType: String, Codable { case string, bool, int, double, data }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(ValueType.self, forKey: .type)
        switch type {
        case .string: self = .string(try c.decode(String.self, forKey: .string))
        case .bool: self = .bool(try c.decode(Bool.self, forKey: .bool))
        case .int: self = .int(try c.decode(Int.self, forKey: .int))
        case .double: self = .double(try c.decode(Double.self, forKey: .double))
        case .data: self = .data(try c.decode(Data.self, forKey: .data))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let value):
            try c.encode(ValueType.string, forKey: .type)
            try c.encode(value, forKey: .string)
        case .bool(let value):
            try c.encode(ValueType.bool, forKey: .type)
            try c.encode(value, forKey: .bool)
        case .int(let value):
            try c.encode(ValueType.int, forKey: .type)
            try c.encode(value, forKey: .int)
        case .double(let value):
            try c.encode(ValueType.double, forKey: .type)
            try c.encode(value, forKey: .double)
        case .data(let value):
            try c.encode(ValueType.data, forKey: .type)
            try c.encode(value, forKey: .data)
        }
    }

    init?(object: Any) {
        switch object {
        case let value as String: self = .string(value)
        case let value as Bool: self = .bool(value)
        case let value as Int: self = .int(value)
        case let value as Double: self = .double(value)
        case let value as Float: self = .double(Double(value))
        case let value as Data: self = .data(value)
        default: return nil
        }
    }

    var object: Any {
        switch self {
        case .string(let value): value
        case .bool(let value): value
        case .int(let value): value
        case .double(let value): value
        case .data(let value): value
        }
    }
}

struct SettingsBackupPayload: Codable {
    let app: String
    let version: Int
    let createdAt: Date
    let values: [String: UserDefaultsBackupValue]
}

enum SettingsBackupManager {
    private static let keys: Set<String> = [
        "gaplessPlayback", "replayGainMode", "crossfadeDurationSeconds",
        "automixStyle", "automixMaxBlendSeconds", "automixSilenceTrim",
        "automixTempoMatch", "autoplayEnabled", "playbackTransitionMode",
        "crossfadeEnabled", "streamingBitrate", "streamingBitrateCell",
        "downloadBitrate", "transcodingFormat", "downloadThreadingMode",
        "downloadSpeedLimitKBps", "downloadCapMB", "autoEvictDownloads",
        "artworkAnimation", "liveArtwork", "showLosslessBadge",
        "dynamicBackground", "showTrackArtwork", "accentColorName",
        "customAccentRed", "customAccentGreen", "customAccentBlue",
        "imageLoadMode", "cacheMode", "prefetchArtistImages",
        "localArtworkLibraryDownloaded", "albumSortOrder",
        "developerLogging", "developerPerformanceOverlay",
        "showWarningNotifications", "showOfflineErrorNotifications",
        "autoPlaylistBackupEnabled", "saveLyricsLocally", "forceLiquidGlass",
        "themeMode", "monoAudio", "spatialWidener", "spatialWidenerAmount",
        "equalizerEnabled",
        "performanceModeEnabled", "pmHalfFrameRate", "pmReduceImageQuality",
        "pmDisableLiveArtwork", "pmDisableDynamicBackground", "pmReduceAnimations",
        "pmDisablePrefetch", "pmSimpleTransitions",
        "pmLowerStreamQuality", "pmBypassAudioEffects",
        "smartPlaylists", "playlistFolders"
    ]

    static func exportURL() throws -> URL {
        let defaults = UserDefaults.standard.dictionaryRepresentation()
        var values: [String: UserDefaultsBackupValue] = [:]
        for key in keys {
            guard let object = defaults[key],
                  let value = UserDefaultsBackupValue(object: object) else { continue }
            values[key] = value
        }

        let payload = SettingsBackupPayload(
            app: "Volta",
            version: 1,
            createdAt: Date(),
            values: values
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Volta-Settings-\(stamp()).json")
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func restore(from url: URL) throws -> Int {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(SettingsBackupPayload.self, from: data)
        guard payload.app == "Volta" else { throw SettingsBackupError.invalidFile }

        var count = 0
        for (key, value) in payload.values where keys.contains(key) {
            UserDefaults.standard.set(value.object, forKey: key)
            count += 1
        }
        UserDefaults.standard.synchronize()
        return count
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
