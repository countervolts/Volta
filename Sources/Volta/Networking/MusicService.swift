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

    // OpenSubsonic reference surface.
    static let subsonicFull: MusicServiceCapabilities = [
        .folderBrowsing, .publicSharing, .favorites, .syncedLyrics, .topSongsByArtist,
        .playlistComments, .artistBiography, .songsByGenre, .recentlyPlayed,
        .playCounts, .replayGain, .bpmTag,
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

    // favorites
    func star(id: String) async throws
    func unstar(id: String) async throws

    // stats
    func getMusicFolderStats() async throws -> (artists: Int, albums: Int, songs: Int)

    // lyrics
    func lyricsBySongId(id: String) async throws -> LyricsList?
    func lyrics(artist: String, title: String) async throws -> String?

    // sharing
    func sharingAvailable() async -> Bool
    func createShare(id: String) async throws -> URL?

    // media URLs (auth embedded so AVPlayer / image loaders can use them directly)
    func coverArtURL(id: String?, size: Int?) -> URL?
    func streamURL(id: String) -> URL?
    func downloadURL(id: String) -> URL?
    func originalStreamURL(id: String) -> URL?

    // Extra stream/download headers, mainly Plex identity headers.
    func mediaRequestHeaders() -> [String: String]

    // Progressive transcodes have no size/range support.
    func downloadIsProgressive(id: String) -> Bool

    // Some backends (Plex) need to fetch per-track metadata before a synchronous
    // streamURL can point at the original file instead of falling back to a
    // transcode. Warm that state here ahead of building the URL.
    func prepareForPlayback(id: String) async

    // True when streamURL(id:) can already build the correct (original or
    // transcoded, per settings) URL without any further async warm-up.
    func streamMetadataReady(id: String) -> Bool
}

// Short call-shape helpers; backends implement only the full forms.
extension MusicService {
    func mediaRequestHeaders() -> [String: String] { [:] }
    func downloadIsProgressive(id: String) -> Bool { false }
    func prepareForPlayback(id: String) async {}
    func streamMetadataReady(id: String) -> Bool { true }
    func coverArtURL(id: String?) -> URL? { coverArtURL(id: id, size: nil) }
    func allAlbums(size: Int) async throws -> [Album] { try await allAlbums(size: size, offset: 0) }
    func songsByGenre(_ genre: String, count: Int) async throws -> [Song] {
        try await songsByGenre(genre, count: count, offset: 0)
    }
}

// MARK: - Shared streaming preferences

// The bitrate/format selection logic is identical across backends (it reads the same
// user settings + Performance Mode cap); only the URL shape differs. Centralised here
// so Subsonic, Jellyfin and Plex stay in lock-step.
enum StreamingPreferences {
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

    // target transcode container (e.g. "mp3", "opus"), or nil when "raw"/original.
    static var transcodingFormat: String? {
        let format = UserDefaults.standard.string(forKey: "transcodingFormat") ?? "raw"
        return format == "raw" ? nil : format
    }

    static var plexUniversalTranscodeExtension: String {
        transcodingFormat == "opus" ? "opus" : "mp3"
    }

    // The user wants a transcode only when they cap the bitrate or pick a target
    // format; otherwise every backend should serve the original file untouched.
    static func wantsTranscode(bitrateKbps: Int) -> Bool {
        bitrateKbps > 0 || transcodingFormat != nil
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
