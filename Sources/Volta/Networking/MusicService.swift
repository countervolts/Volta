import Foundation

// MARK: - Backend kind

// Server protocol saved with each connection.
enum MusicBackendKind: String, Codable, Sendable, CaseIterable {
    case subsonic
    case jellyfin
    case emby
    case plex

    var displayName: String {
        switch self {
        case .subsonic: return "Subsonic / Navidrome"
        case .jellyfin: return "Jellyfin"
        case .emby:     return "Emby"
        case .plex:     return "Plex"
        }
    }
}

// MARK: - Capabilities

// Backend feature flags.
struct MusicServiceCapabilities: OptionSet, Sendable {
    let rawValue: Int

    static let folderBrowsing    = MusicServiceCapabilities(rawValue: 1 << 0)
    static let publicSharing     = MusicServiceCapabilities(rawValue: 1 << 1)
    static let favorites         = MusicServiceCapabilities(rawValue: 1 << 2)
    static let syncedLyrics      = MusicServiceCapabilities(rawValue: 1 << 3)
    static let topSongsByArtist  = MusicServiceCapabilities(rawValue: 1 << 4)
    static let playlistComments  = MusicServiceCapabilities(rawValue: 1 << 5)
    static let artistBiography   = MusicServiceCapabilities(rawValue: 1 << 6)
    static let songsByGenre      = MusicServiceCapabilities(rawValue: 1 << 7)
    static let recentlyPlayed    = MusicServiceCapabilities(rawValue: 1 << 8)
    static let playCounts        = MusicServiceCapabilities(rawValue: 1 << 9)
    static let replayGain        = MusicServiceCapabilities(rawValue: 1 << 10)
    static let bpmTag            = MusicServiceCapabilities(rawValue: 1 << 11)
    static let serverScrobbling  = MusicServiceCapabilities(rawValue: 1 << 12)
    static let playlistReordering = MusicServiceCapabilities(rawValue: 1 << 13)

    // OpenSubsonic reference surface.
    static let subsonicFull: MusicServiceCapabilities = [
        .folderBrowsing, .publicSharing, .favorites, .syncedLyrics, .topSongsByArtist,
        .playlistComments, .artistBiography, .songsByGenre, .recentlyPlayed,
        .playCounts, .replayGain, .bpmTag, .serverScrobbling, .playlistReordering,
    ]
}

// MARK: - MusicService protocol

// Shared API the app uses for every backend.
protocol MusicService: Sendable {
    // connection identity for record matching and media URLs
    var config: SubsonicConfig { get }
    var backendKind: MusicBackendKind { get }
    var capabilities: MusicServiceCapabilities { get }

    // health
    func ping() async throws
    func serverHealth() async throws -> ServerHealthSnapshot

    // folder / directory browsing
    func musicFolders() async throws -> [MusicFolder]
    func indexes(musicFolderId: String?) async throws -> [BrowseEntry]
    func musicDirectory(id: String) async throws -> [BrowseEntry]

    // albums
    func randomAlbums(size: Int) async throws -> [Album]
    func newestAlbums(size: Int) async throws -> [Album]
    func recentlyPlayedAlbums(size: Int) async throws -> [Album]
    func frequentAlbums(size: Int) async throws -> [Album]
    func allAlbums(size: Int, offset: Int) async throws -> [Album]
    func album(id: String) async throws -> Album?
    func albums(ids: [String]) async throws -> [Album]

    // artists
    func artists() async throws -> [Artist]
    func artist(id: String) async throws -> Artist?
    func artistInfo(id: String) async throws -> ArtistInfo?
    func songsForArtist(id: String) async throws -> [Song]
    func topSongs(artistName: String, count: Int) async throws -> [Song]

    // songs
    func song(id: String) async throws -> Song?
    func randomSongs(size: Int) async throws -> [Song]
    func songsByGenre(_ genre: String, count: Int, offset: Int) async throws -> [Song]

    // search
    func search(query: String, artistCount: Int, albumCount: Int, songCount: Int) async throws -> (artists: [Artist], albums: [Album], songs: [Song])

    // playlists
    func playlists() async throws -> [Playlist]
    func playlist(id: String) async throws -> Playlist?
    func createPlaylist(name: String) async throws -> Playlist?
    func createPlaylist(name: String, songIDs: [String]) async throws -> Playlist?
    func addToPlaylist(playlistID: String, songID: String) async throws
    func removeFromPlaylist(playlistID: String, index: Int) async throws
    func deletePlaylist(id: String) async throws
    func renamePlaylist(playlistID: String, name: String) async throws
    func updatePlaylistComment(playlistID: String, comment: String) async throws
    func replacePlaylistSongs(playlistID: String, songIDs: [String]) async throws

    // favorites
    func star(id: String) async throws
    func unstar(id: String) async throws

    // stats
    func getMusicFolderStats() async throws -> (artists: Int, albums: Int, songs: Int)
    func scrobble(id: String, at date: Date?, submission: Bool) async throws

    // lyrics
    func lyricsBySongId(id: String) async throws -> LyricsList?
    func lyrics(artist: String, title: String) async throws -> String?

    // sharing
    func sharingAvailable() async -> Bool
    func createShare(id: String) async throws -> URL?

    // media URLs (auth embedded so AVPlayer / image loaders can use them directly)
    func coverArtURL(id: String?, size: Int?) -> URL?
    func liveArtworkURLs(id: String?) -> [URL]
    func streamURL(id: String) -> URL?
    func streamURL(for song: Song) -> URL?
    func downloadURL(id: String) -> URL?
    func downloadURL(for song: Song) -> URL?
    func originalStreamURL(id: String) -> URL?

    // Extra stream/download headers, mainly Plex identity headers.
    func mediaRequestHeaders() -> [String: String]

    // Progressive transcodes have no size/range support.
    func downloadIsProgressive(id: String) -> Bool
    func downloadIsProgressive(for song: Song) -> Bool

    // Warm backend metadata needed by synchronous stream URL builders.
    func prepareForPlayback(id: String) async
    func prepareForPlayback(song: Song) async

    // True when streamURL(id:) can already build the correct (original or
    // transcoded, per settings) URL without any further async warm-up.
    func streamMetadataReady(id: String) -> Bool
    func streamMetadataReady(for song: Song) -> Bool
}

// Short call-shape helpers; backends implement only the full forms.
extension MusicService {
    func mediaRequestHeaders() -> [String: String] { [:] }
    func downloadIsProgressive(id: String) -> Bool { false }
    func downloadIsProgressive(for song: Song) -> Bool { downloadIsProgressive(id: song.id) }
    func prepareForPlayback(id: String) async {}
    func prepareForPlayback(song: Song) async { await prepareForPlayback(id: song.id) }
    func streamMetadataReady(id: String) -> Bool { true }
    func streamMetadataReady(for song: Song) -> Bool { streamMetadataReady(id: song.id) }
    func streamURL(for song: Song) -> URL? { streamURL(id: song.id) }
    func downloadURL(for song: Song) -> URL? { downloadURL(id: song.id) }
    func coverArtURL(id: String?) -> URL? { coverArtURL(id: id, size: nil) }
    func liveArtworkURLs(id: String?) -> [URL] { coverArtURL(id: id).map { [$0] } ?? [] }
    func allAlbums(size: Int) async throws -> [Album] { try await allAlbums(size: size, offset: 0) }
    func songsByGenre(_ genre: String, count: Int) async throws -> [Song] {
        try await songsByGenre(genre, count: count, offset: 0)
    }
    func scrobble(id: String, at date: Date?, submission: Bool) async throws {}
    func replacePlaylistSongs(playlistID: String, songIDs: [String]) async throws {
        throw SubsonicError.server(code: 0, message: "Playlist reordering is not supported by this server.")
    }
}

// MARK: - Shared streaming preferences

enum TranscodeSourceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case flac
    case alac
    case wavAiff
    case mp3
    case aac
    case opus
    case oggVorbis
    case otherLossless
    case otherLossy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flac: return "FLAC"
        case .alac: return "ALAC / Lossless M4A"
        case .wavAiff: return "WAV / AIFF"
        case .mp3: return "MP3"
        case .aac: return "AAC / M4A"
        case .opus: return "Opus"
        case .oggVorbis: return "Ogg / Vorbis"
        case .otherLossless: return "Other Lossless"
        case .otherLossy: return "Other Lossy"
        }
    }

    var detail: String {
        switch self {
        case .flac: return "Files tagged as FLAC."
        case .alac: return "Apple Lossless in M4A/MP4 containers."
        case .wavAiff: return "PCM, WAV, AIFF, and related uncompressed files."
        case .mp3: return "MPEG layer 3 files."
        case .aac: return "AAC streams and lossy M4A/MP4 files."
        case .opus: return "Opus files and WebM/Opus streams."
        case .oggVorbis: return "Vorbis audio in Ogg/OGA containers."
        case .otherLossless: return "Lossless formats not listed above."
        case .otherLossy: return "Lossy or unknown formats not listed above."
        }
    }

    var systemImage: String {
        switch self {
        case .flac, .alac, .wavAiff, .otherLossless:
            return "waveform"
        case .mp3, .aac, .opus, .oggVorbis, .otherLossy:
            return "music.note"
        }
    }

    static func resolve(for song: Song) -> TranscodeSourceKind {
        allCases.first { $0.matches(song) } ?? .otherLossy
    }

    func matches(_ song: Song) -> Bool {
        let suffixes = Self.sourceExtensions(for: song)
        let codec = Self.normalized(song.codec)
        let contentType = Self.normalizedContentType(song.contentType)

        switch self {
        case .flac:
            return suffixes.contains("flac")
                || codec == "flac"
                || contentType?.contains("flac") == true
        case .alac:
            return codec == "alac"
                || codec == "apple_lossless"
                || contentType?.contains("alac") == true
                || (suffixes.contains("m4a") || suffixes.contains("mp4")) && song.isLossless
        case .wavAiff:
            return !suffixes.isDisjoint(with: ["wav", "wave", "aif", "aiff"])
                || codec?.hasPrefix("pcm") == true
                || codec == "lpcm"
                || contentType?.contains("wav") == true
                || contentType?.contains("wave") == true
                || contentType?.contains("aiff") == true
        case .mp3:
            return suffixes.contains("mp3")
                || codec == "mp3"
                || contentType?.contains("mpeg") == true
                || contentType?.contains("mp3") == true
        case .aac:
            return codec == "aac"
                || codec == "aac_latm"
                || codec == "mp4a"
                || codec?.hasPrefix("mp4a.") == true
                || contentType?.contains("aac") == true
                || ((suffixes.contains("m4a") || suffixes.contains("mp4")) && !song.isLossless)
        case .opus:
            return suffixes.contains("opus")
                || suffixes.contains("webm")
                || codec == "opus"
                || contentType?.contains("opus") == true
                || contentType?.contains("webm") == true
        case .oggVorbis:
            return !suffixes.isDisjoint(with: ["ogg", "oga", "vorbis"])
                || codec == "vorbis"
                || contentType?.contains("ogg") == true
                || contentType?.contains("vorbis") == true
        case .otherLossless:
            return song.isLossless
        case .otherLossy:
            return !song.isLossless
        }
    }

    private static func sourceExtensions(for song: Song) -> Set<String> {
        var values: Set<String> = []
        if let suffix = normalized(song.suffix) {
            values.insert(suffix)
        }
        if let path = normalized(song.path),
           let ext = path.split(separator: ".").last,
           !ext.isEmpty {
            values.insert(String(ext))
        }
        return values
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func normalizedContentType(_ value: String?) -> String? {
        normalized(value)?
            .split(separator: ";", maxSplits: 1)
            .first
            .map(String.init)
    }
}

enum TranscodeRuleTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case original
    case mp3
    case aac
    case opus

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .original: return "Original"
        case .mp3: return "MP3"
        case .aac: return "AAC"
        case .opus: return "Opus"
        }
    }

    var explicitFormat: String? {
        switch self {
        case .automatic, .original:
            return nil
        case .mp3, .aac, .opus:
            return rawValue
        }
    }
}

enum TranscodingSettingsMode: String, CaseIterable, Identifiable, Sendable {
    case simple
    case advanced

    var id: String { rawValue }

    var label: String {
        switch self {
        case .simple: return "Simple"
        case .advanced: return "Advanced"
        }
    }
}

struct StreamingTranscodeDecision: Equatable, Sendable {
    let requestedBitrateKbps: Int
    let bitrateKbps: Int
    let format: String?
    let sourceKind: TranscodeSourceKind?
    let ruleTarget: TranscodeRuleTarget?

    var wantsTranscode: Bool { bitrateKbps > 0 }
    var usesRuleOverride: Bool { ruleTarget != nil && ruleTarget != .automatic }

    static func original(requestedBitrateKbps: Int = 0,
                         sourceKind: TranscodeSourceKind? = nil,
                         ruleTarget: TranscodeRuleTarget? = nil) -> StreamingTranscodeDecision {
        StreamingTranscodeDecision(
            requestedBitrateKbps: requestedBitrateKbps,
            bitrateKbps: 0,
            format: nil,
            sourceKind: sourceKind,
            ruleTarget: ruleTarget
        )
    }
}

// The bitrate/format selection logic is identical across backends (it reads the same
// user settings + Performance Mode cap); only the URL shape differs. Centralised here
// so Subsonic, Jellyfin and Plex stay in lock-step.
enum StreamingPreferences {
    static let transcodingEnabledKey = "transcodingEnabled"
    static let transcodingModeKey = "transcodingSettingsMode"
    static let transcodingCellularOnlyKey = "transcodingCellularOnly"
    static let transcodingMigrationVersionKey = "transcodingSettingsMigrationVersion"
    static let transcodingRulesEnabledKey = "transcodingRulesEnabled"
    static let transcodeFileTypeRulesKey = "transcodeFileTypeRules"
    static let transcodeRuleDefaultBitrateKey = "transcodeRuleDefaultBitrate"

    // effective streaming bitrate in kbps, or 0 for "original / no cap".
    static var streamBitrateKbps: Int {
        let onCellular = UserDefaults.standard.bool(forKey: "networkIsCellular")
        let cellBitrate = UserDefaults.standard.integer(forKey: "streamingBitrateCell")
        let wifiBitrate = UserDefaults.standard.integer(forKey: "streamingBitrate")
        var bitrate = (onCellular && cellBitrate > 0) ? cellBitrate : wifiBitrate
        let cap = PerformanceMode.streamBitrateCap
        if cap > 0 { bitrate = bitrate > 0 ? min(bitrate, cap) : cap }
        return max(0, bitrate)
    }

    // effective download bitrate in kbps, or 0 for "original".
    static var downloadBitrateKbps: Int {
        max(0, UserDefaults.standard.integer(forKey: "downloadBitrate"))
    }

    // Preferred transcode target (e.g. "mp3", "aac", "opus"), or nil when the
    // user has not selected a target format. This does not enable transcoding by
    // itself; quality/bitrate settings decide that.
    static var transcodingFormat: String? {
        let format = UserDefaults.standard.string(forKey: "transcodingFormat") ?? "raw"
        return format == "raw" ? nil : format
    }

    static var activeTranscodingFormat: String {
        transcodingFormat ?? "mp3"
    }

    static var plexUniversalTranscodeExtension: String {
        plexUniversalTranscodeExtension(for: activeTranscodingFormat)
    }

    static func plexUniversalTranscodeExtension(for format: String?) -> String {
        format == "opus" ? "opus" : "mp3"
    }

    // The user wants a transcode only when they cap the bitrate. The selected
    // format only chooses the target when a stream/download is already capped.
    static func wantsTranscode(bitrateKbps: Int) -> Bool {
        bitrateKbps > 0
    }

    static var transcodingEnabled: Bool {
        migrateTranscodingSettingsIfNeeded()
        return UserDefaults.standard.object(forKey: transcodingEnabledKey) as? Bool ?? true
    }

    static var transcodingMode: TranscodingSettingsMode {
        migrateTranscodingSettingsIfNeeded()
        let raw = UserDefaults.standard.string(forKey: transcodingModeKey)
            ?? TranscodingSettingsMode.simple.rawValue
        return TranscodingSettingsMode(rawValue: raw) ?? .simple
    }

    static var transcodingCellularOnly: Bool {
        migrateTranscodingSettingsIfNeeded()
        return UserDefaults.standard.bool(forKey: transcodingCellularOnlyKey)
    }

    static var currentConnectionAllowsTranscoding: Bool {
        !transcodingCellularOnly || UserDefaults.standard.bool(forKey: "networkIsCellular")
    }

    static var transcodeRulesEnabled: Bool {
        transcodingEnabled && transcodingMode == .advanced
    }

    static var transcodeRuleDefaultBitrateKbps: Int {
        let value = UserDefaults.standard.integer(forKey: transcodeRuleDefaultBitrateKey)
        return value > 0 ? value : 320
    }

    static var transcodeRuleTargets: [TranscodeSourceKind: TranscodeRuleTarget] {
        decodeRuleTargets(UserDefaults.standard.string(forKey: transcodeFileTypeRulesKey))
    }

    static func ruleTarget(for kind: TranscodeSourceKind,
                           targets: [TranscodeSourceKind: TranscodeRuleTarget]? = nil) -> TranscodeRuleTarget {
        (targets ?? transcodeRuleTargets)[kind] ?? .automatic
    }

    static func streamDecision(for song: Song?) -> StreamingTranscodeDecision {
        transcodeDecision(for: song, requestedBitrateKbps: streamBitrateKbps)
    }

    static func downloadDecision(for song: Song?) -> StreamingTranscodeDecision {
        transcodeDecision(for: song, requestedBitrateKbps: downloadBitrateKbps)
    }

    static func transcodeDecision(for song: Song?, requestedBitrateKbps: Int) -> StreamingTranscodeDecision {
        let bitrate = max(0, requestedBitrateKbps)
        let sourceKind = song.map(TranscodeSourceKind.resolve)

        guard transcodingEnabled else {
            return .original(requestedBitrateKbps: bitrate, sourceKind: sourceKind)
        }

        guard currentConnectionAllowsTranscoding else {
            return .original(requestedBitrateKbps: bitrate, sourceKind: sourceKind)
        }

        let activeRuleTarget = transcodeRulesEnabled ? sourceKind.map { ruleTarget(for: $0) } : nil

        if transcodeRulesEnabled,
           let sourceKind,
           let target = activeRuleTarget {
            switch target {
            case .automatic:
                break
            case .original:
                return .original(
                    requestedBitrateKbps: bitrate,
                    sourceKind: sourceKind,
                    ruleTarget: target
                )
            case .mp3, .aac, .opus:
                return StreamingTranscodeDecision(
                    requestedBitrateKbps: bitrate,
                    bitrateKbps: bitrate > 0 ? bitrate : transcodeRuleDefaultBitrateKbps,
                    format: target.explicitFormat,
                    sourceKind: sourceKind,
                    ruleTarget: target
                )
            }
        }

        guard wantsTranscode(bitrateKbps: bitrate) else {
            return .original(
                requestedBitrateKbps: bitrate,
                sourceKind: sourceKind,
                ruleTarget: activeRuleTarget
            )
        }

        return StreamingTranscodeDecision(
            requestedBitrateKbps: bitrate,
            bitrateKbps: bitrate,
            format: transcodingFormat,
            sourceKind: sourceKind,
            ruleTarget: activeRuleTarget
        )
    }

    static func decodeRuleTargets(_ raw: String?) -> [TranscodeSourceKind: TranscodeRuleTarget] {
        guard let raw,
              let data = raw.data(using: .utf8),
              let stored = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        var targets: [TranscodeSourceKind: TranscodeRuleTarget] = [:]
        for (key, value) in stored {
            guard let kind = TranscodeSourceKind(rawValue: key),
                  let target = TranscodeRuleTarget(rawValue: value) else { continue }
            targets[kind] = target
        }
        return targets
    }

    static func encodeRuleTargets(_ targets: [TranscodeSourceKind: TranscodeRuleTarget]) -> String {
        let stored = targets.reduce(into: [String: String]()) { result, element in
            guard element.value != .automatic else { return }
            result[element.key.rawValue] = element.value.rawValue
        }
        guard !stored.isEmpty,
              let data = try? JSONEncoder().encode(stored),
              let raw = String(data: data, encoding: .utf8) else {
            return ""
        }
        return raw
    }

    static func migrateTranscodingSettingsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: transcodingMigrationVersionKey) < 1 else { return }

        if defaults.object(forKey: transcodingEnabledKey) == nil {
            defaults.set(true, forKey: transcodingEnabledKey)
        }

        if defaults.object(forKey: transcodingCellularOnlyKey) == nil {
            defaults.set(false, forKey: transcodingCellularOnlyKey)
        }

        if defaults.object(forKey: transcodingModeKey) == nil {
            let hadUnreleasedAdvancedState =
                defaults.bool(forKey: transcodingRulesEnabledKey)
                || !(defaults.string(forKey: transcodeFileTypeRulesKey) ?? "").isEmpty
            defaults.set(
                hadUnreleasedAdvancedState
                    ? TranscodingSettingsMode.advanced.rawValue
                    : TranscodingSettingsMode.simple.rawValue,
                forKey: transcodingModeKey
            )
        }

        defaults.set(1, forKey: transcodingMigrationVersionKey)
    }
}

// MARK: - Factory

// Build the right client and run that backend's login handshake.
enum MusicServiceFactory {
    static func make(config: SubsonicConfig,
                     kind: MusicBackendKind,
                     session: URLSession = .shared) async throws -> any MusicService {
        switch kind {
        case .subsonic:
            return SubsonicClient(config: config, session: session)
        case .jellyfin:
            return try await JellyfinClient.connect(config: config, flavor: .jellyfin, session: session)
        case .emby:
            return try await JellyfinClient.connect(config: config, flavor: .emby, session: session)
        case .plex:
            return try await PlexClient.connect(config: config, session: session)
        }
    }
}
