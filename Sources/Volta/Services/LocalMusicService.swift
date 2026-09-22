import AVFoundation
import Foundation
import UIKit
import UniformTypeIdentifiers

enum LocalLibraryError: LocalizedError {
    case folderSelectionCancelled
    case noSupportedAudio
    case bookmarkUnavailable

    var errorDescription: String? {
        switch self {
        case .folderSelectionCancelled:
            return "No music folder was selected."
        case .noSupportedAudio:
            return "That folder does not contain supported audio files."
        case .bookmarkUnavailable:
            return "Volta could not keep access to that folder."
        }
    }
}

/// A local folder is persisted as a security-scoped bookmark so files stay
/// playable after relaunch without copying the user's music into Volta.
@MainActor
final class LocalLibraryStore: NSObject, ObservableObject, UIDocumentPickerDelegate {
    static let shared = LocalLibraryStore()

    private static let bookmarkKey = "localMusicFolderBookmark"
    private static let restoreKey = "localMusicAutoRestore"
    private static let libraryIDKey = "localMusicLibraryID"
    private static let rootFingerprintKey = "localMusicRootFingerprint"

    private var picker: UIDocumentPickerViewController?
    private var pickerContinuation: CheckedContinuation<URL?, Never>?
    private var accessedRoot: URL?

    var shouldRestore: Bool {
        UserDefaults.standard.bool(forKey: Self.restoreKey)
            && UserDefaults.standard.data(forKey: Self.bookmarkKey) != nil
    }

    func chooseService() async throws -> LocalMusicService {
        guard let folder = await chooseFolder() else {
            throw LocalLibraryError.folderSelectionCancelled
        }
        guard folder.startAccessingSecurityScopedResource() else {
            throw LocalLibraryError.bookmarkUnavailable
        }
        let defaults = UserDefaults.standard
        let previousLibraryID = defaults.object(forKey: Self.libraryIDKey)
        let previousFingerprint = defaults.object(forKey: Self.rootFingerprintKey)
        let libraryID = libraryID(for: folder)
        let service: LocalMusicService
        do {
            service = try await LocalMusicService.make(rootURL: folder, libraryID: libraryID)
        } catch {
            folder.stopAccessingSecurityScopedResource()
            restore(previousLibraryID, forKey: Self.libraryIDKey, defaults: defaults)
            restore(previousFingerprint, forKey: Self.rootFingerprintKey, defaults: defaults)
            throw error
        }
        stopAccessingCurrentRoot()
        accessedRoot = folder
        try saveBookmark(for: folder)
        UserDefaults.standard.set(true, forKey: Self.restoreKey)
        return service
    }

    func restoreService() async throws -> LocalMusicService? {
        guard shouldRestore,
              let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else {
            return nil
        }

        var stale = false
        let folder = try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        guard folder.startAccessingSecurityScopedResource() else {
            throw LocalLibraryError.bookmarkUnavailable
        }
        stopAccessingCurrentRoot()
        accessedRoot = folder
        if stale { try saveBookmark(for: folder) }
        return try await LocalMusicService.make(rootURL: folder, libraryID: restoredLibraryID(for: folder))
    }

    func disableAutoRestore() {
        UserDefaults.standard.set(false, forKey: Self.restoreKey)
    }

    deinit {
        accessedRoot?.stopAccessingSecurityScopedResource()
    }

    private func saveBookmark(for folder: URL) throws {
        let data = try folder.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
    }

    /// Security-scoped bookmark bytes and absolute paths may change when a
    /// folder is moved or the bookmark is refreshed. Persist an opaque ID once
    /// for the selected root instead, retaining it when Files identifies the
    /// same directory again.
    private func libraryID(for folder: URL) -> String {
        let fingerprint = rootFingerprint(for: folder)
        let defaults = UserDefaults.standard
        if defaults.string(forKey: Self.rootFingerprintKey) == fingerprint,
           let id = defaults.string(forKey: Self.libraryIDKey)?.nonBlank {
            return id
        }
        let id = UUID().uuidString.lowercased()
        defaults.set(id, forKey: Self.libraryIDKey)
        defaults.set(fingerprint, forKey: Self.rootFingerprintKey)
        return id
    }

    private func restoredLibraryID(for folder: URL) -> String {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: Self.libraryIDKey)?.nonBlank {
            return id
        }
        // Existing installations have a bookmark but no opaque ID yet. Assign
        // one exactly once during the first upgrade restore.
        return libraryID(for: folder)
    }

    private func rootFingerprint(for folder: URL) -> String {
        if let identifier = try? folder.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier {
            return "resource:\(String(describing: identifier))"
        }
        // This fallback is only used when Files cannot provide a stable file
        // identity. The generated library ID remains stable across relaunches.
        return "path:\(folder.standardizedFileURL.path)"
    }

    private func restore(_ value: Any?, forKey key: String, defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func stopAccessingCurrentRoot() {
        accessedRoot?.stopAccessingSecurityScopedResource()
        accessedRoot = nil
    }

    private func chooseFolder() async -> URL? {
        await withCheckedContinuation { continuation in
            pickerContinuation = continuation
            let documentPicker = UIDocumentPickerViewController(
                forOpeningContentTypes: [.folder],
                asCopy: false
            )
            documentPicker.delegate = self
            documentPicker.allowsMultipleSelection = false
            picker = documentPicker

            guard let scene = UIApplication.shared.connectedScenes
                    .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
                    ?? UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let root = (scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first)?.rootViewController
            else {
                picker = nil
                pickerContinuation = nil
                continuation.resume(returning: nil)
                return
            }

            var presenter = root
            while let presented = presenter.presentedViewController { presenter = presented }
            presenter.present(documentPicker, animated: true)
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finishPicking(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finishPicking(nil)
    }

    private func finishPicking(_ url: URL?) {
        picker?.dismiss(animated: true)
        picker = nil
        pickerContinuation?.resume(returning: url)
        pickerContinuation = nil
    }
}

private struct LocalMetadata: Codable, Sendable {
    var title: String?
    var artist: String?
    var albumArtist: String?
    var album: String?
    var track: Int?
    var discNumber: Int?
    var year: Int?
    var genre: String?
    var codec: String?
    var bitRate: Int?
    var samplingRate: Int?
    var bitDepth: Int?
    var channelCount: Int?
    var duration: Int?
    var artwork: Data?
    var lyrics: String?
}

private struct LocalScannedTrack: Sendable {
    let url: URL
    let relativePath: String
    let modifiedAt: Date
    let size: Int
    let suffix: String
    let contentType: String?
    let metadata: LocalMetadata
    let artworkURL: URL?
}

/// A small, per-library cache avoids opening and parsing every media container
/// on each launch. Source size and modification date make a changed file a
/// cache miss; deleted files naturally disappear because only the current
/// enumeration is written back.
private struct LocalMetadataCache: Codable, Sendable {
    var schemaVersion: Int
    var entries: [String: LocalCachedTrack]
}

private struct LocalCachedTrack: Codable, Sendable {
    let size: Int
    let modifiedAt: Date
    let metadata: LocalMetadata
    let embeddedArtworkPath: String?
    let lyricsFromSidecar: Bool
}

struct LocalLibrarySnapshot: Sendable {
    let folderName: String
    let directories: [String]
    let songs: [Song]
    let albums: [Album]
    let artists: [Artist]
    let songURLs: [String: URL]
    let artworkURLs: [String: URL]
    let lyricsBySongID: [String: String]
}

private struct LocalPlaylistRecord: Codable, Sendable {
    let id: String
    var name: String
    var comment: String?
    var songIDs: [String]
    let created: Date
    var changed: Date
}

/// Local files intentionally implement the same catalog contract as a server.
/// Existing library, album, search, artwork, and playback screens can therefore
/// use metadata as their source of truth without a second UI-specific catalog.
final class LocalMusicService: MusicService, @unchecked Sendable {
    /// Legacy value retained only for compatibility with pre-1.4.1 callers.
    /// Per-library persistence must use `persistenceID` below.
    static let serverID = "local-library"

    let config: SubsonicConfig
    let backendKind: MusicBackendKind = .subsonic
    let capabilities: MusicServiceCapabilities = [
        .folderBrowsing,
        .favorites,
        .songsByGenre,
        .topSongsByArtist,
        .playCounts,
        .playlistReordering,
    ]
    let rootURL: URL
    let libraryID: String
    var persistenceID: String { "local-library:\(libraryID)" }
    let folderName: String
    var songCount: Int { songs.count }
    var albumCount: Int { albums.count }
    var artistCount: Int { artists.count }
    var totalBytes: Int { songs.reduce(0) { $0 + ($1.size ?? 0) } }

    private let songs: [Song]
    private let directories: Set<String>
    private let albums: [Album]
    private let artists: [Artist]
    private let albumsByID: [String: Album]
    private let artistsByID: [String: Artist]
    private let songsByID: [String: Song]
    private let songURLs: [String: URL]
    private let artworkURLs: [String: URL]
    private let lyricsBySongID: [String: String]
    private let persistenceLock = NSLock()
    private var localPlaylists: [LocalPlaylistRecord]
    private var starredIDs: Set<String>

    private static var legacyLocalDataDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Volta/LocalLibrary", isDirectory: true)
    }

    private static func localDataDirectory(for libraryID: String) -> URL {
        legacyLocalDataDirectory.appendingPathComponent(libraryID, isDirectory: true)
    }

    private static func playlistsURL(for libraryID: String) -> URL {
        localDataDirectory(for: libraryID).appendingPathComponent("playlists.json")
    }

    private static func metadataCacheURL(for libraryID: String) -> URL {
        localDataDirectory(for: libraryID).appendingPathComponent("metadata-cache.json")
    }

    private var localDataDirectory: URL { Self.localDataDirectory(for: libraryID) }
    private var playlistsURL: URL { Self.playlistsURL(for: libraryID) }
    private var starredDefaultsKey: String { "localMusicStarredIDs.\(libraryID)" }

    private init(rootURL: URL, libraryID: String, snapshot: LocalLibrarySnapshot) {
        self.rootURL = rootURL
        self.libraryID = libraryID
        self.folderName = snapshot.folderName
        self.directories = Set(snapshot.directories)
        self.songs = snapshot.songs
        self.albums = snapshot.albums
        self.artists = snapshot.artists
        self.albumsByID = Dictionary(uniqueKeysWithValues: snapshot.albums.map { ($0.id, $0) })
        self.artistsByID = Dictionary(uniqueKeysWithValues: snapshot.artists.map { ($0.id, $0) })
        self.songsByID = Dictionary(uniqueKeysWithValues: snapshot.songs.map { ($0.id, $0) })
        self.songURLs = snapshot.songURLs
        self.artworkURLs = snapshot.artworkURLs
        self.lyricsBySongID = snapshot.lyricsBySongID
        self.localPlaylists = Self.loadPlaylists(for: libraryID, songs: snapshot.songs)
        self.starredIDs = Self.loadStarredIDs(for: libraryID, songs: snapshot.songs)
        self.config = SubsonicConfig(
            baseURL: URL(string: "https://local.volta.invalid")!,
            username: "Local Library",
            password: ""
        )
    }

    static func make(rootURL: URL, libraryID: String? = nil) async throws -> LocalMusicService {
        // The store always supplies an opaque, bookmark-backed ID. The path
        // fallback keeps direct/test construction deterministic without making
        // the persisted application path part of an identity.
        let libraryID = libraryID?.nonBlank ?? "temporary-\(Crypto.md5Hex(rootURL.standardizedFileURL.path))"
        let snapshot = try await scan(rootURL: rootURL, libraryID: libraryID)
        return LocalMusicService(rootURL: rootURL, libraryID: libraryID, snapshot: snapshot)
    }

    func ping() async throws {}

    func serverHealth() async throws -> ServerHealthSnapshot {
        ServerHealthSnapshot(
            status: "local",
            apiVersion: nil,
            serverType: "Local Files",
            latencyMS: 0,
            checkedAt: Date()
        )
    }

    func musicFolders() async throws -> [MusicFolder] {
        [MusicFolder(id: "local-root", name: folderName)]
    }

    func indexes(musicFolderId: String?) async throws -> [BrowseEntry] {
        // `getIndexes` represents the selected music folder itself. Unlike the
        // old implementation, a filename at the root is not promoted into a
        // fake directory; the root can contain both tracks and folders.
        browseEntries(in: "")
    }

    func musicDirectory(id: String) async throws -> [BrowseEntry] {
        guard id.hasPrefix("local-folder:") else { return [] }
        return browseEntries(in: String(id.dropFirst("local-folder:".count)))
    }

    private func browseEntries(in directory: String) -> [BrowseEntry] {
        let prefix = directory.isEmpty ? "" : directory + "/"
        var childFolders = Set<String>()
        var entries: [BrowseEntry] = []
        for path in directories where path.hasPrefix(prefix) {
            let remainder = String(path.dropFirst(prefix.count))
            guard !remainder.isEmpty else { continue }
            if let slash = remainder.firstIndex(of: "/") {
                childFolders.insert(String(remainder[..<slash]))
            } else {
                childFolders.insert(remainder)
            }
        }
        for song in songs where song.path?.hasPrefix(prefix) == true {
            guard let path = song.path else { continue }
            let remainder = String(path.dropFirst(prefix.count))
            if let slash = remainder.firstIndex(of: "/") {
                let child = String(remainder[..<slash])
                childFolders.insert(child)
            } else {
                entries.append(BrowseEntry(id: song.id, name: song.title, isDirectory: false, coverArt: song.coverArt, song: song))
            }
        }
        let folders = childFolders.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map {
            BrowseEntry(id: "local-folder:\(prefix)\($0)", name: $0, isDirectory: true, coverArt: nil, song: nil)
        }
        return folders + entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func randomAlbums(size: Int) async throws -> [Album] {
        Array(albums.shuffled().prefix(max(0, size)))
    }

    func newestAlbums(size: Int) async throws -> [Album] {
        // Filesystem modification time is not a release/addition date. Do not
        // present alphabetically ordered local albums as "Newest".
        []
    }

    func recentlyPlayedAlbums(size: Int) async throws -> [Album] {
        // Local Files does not currently persist play history as a catalog
        // statistic, so an empty result hides this remote-only shelf.
        []
    }

    func frequentAlbums(size: Int) async throws -> [Album] {
        []
    }

    func allAlbums(size: Int, offset: Int) async throws -> [Album] {
        let start = min(max(0, offset), albums.count)
        let end = min(albums.count, start + max(0, size))
        return Array(albums[start..<end])
    }

    func album(id: String) async throws -> Album? { albumsByID[id] }
    func albums(ids: [String]) async throws -> [Album] { ids.compactMap { albumsByID[$0] } }
    func artists() async throws -> [Artist] { artists }
    func artist(id: String) async throws -> Artist? { artistsByID[id] }
    func artistInfo(id: String) async throws -> ArtistInfo? { nil }

    func songsForArtist(id: String) async throws -> [Song] {
        songs.filter { $0.artistId == id || $0.albumArtistId == id }
    }

    func topSongs(artistName: String, count: Int) async throws -> [Song] {
        // There is no local play-count data yet. Returning file-order tracks
        // here would make an arbitrary list look like a popularity ranking.
        []
    }

    func song(id: String) async throws -> Song? { songsByID[id] }
    func randomSongs(size: Int) async throws -> [Song] { Array(songs.shuffled().prefix(max(0, size))) }

    func songsByGenre(_ genre: String, count: Int, offset: Int) async throws -> [Song] {
        let matching = songs.filter { $0.genre?.localizedCaseInsensitiveCompare(genre) == .orderedSame }
        let start = min(max(0, offset), matching.count)
        let end = min(matching.count, start + max(0, count))
        return Array(matching[start..<end])
    }

    func search(query: String, artistCount: Int, albumCount: Int, songCount: Int) async throws -> (artists: [Artist], albums: [Album], songs: [Song]) {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return ([], [], []) }
        return (
            Array(artists.filter { $0.name.localizedCaseInsensitiveContains(needle) }.prefix(max(0, artistCount))),
            Array(albums.filter { $0.name.localizedCaseInsensitiveContains(needle) || ($0.artist?.localizedCaseInsensitiveContains(needle) == true) }.prefix(max(0, albumCount))),
            Array(songs.filter { $0.title.localizedCaseInsensitiveContains(needle) || ($0.artist?.localizedCaseInsensitiveContains(needle) == true) || ($0.album?.localizedCaseInsensitiveContains(needle) == true) }.prefix(max(0, songCount)))
        )
    }

    func playlists() async throws -> [Playlist] {
        persistenceLock.withLock {
            localPlaylists.map(makePlaylist)
        }
    }

    func playlist(id: String) async throws -> Playlist? {
        persistenceLock.withLock {
            localPlaylists.first(where: { $0.id == id }).map(makePlaylist)
        }
    }

    private func unsupportedPlaylistOperation() -> SubsonicError {
        .server(code: 0, message: "Playlists are not available for local files yet.")
    }

    func createPlaylist(name: String) async throws -> Playlist? {
        try await createPlaylist(name: name, songIDs: [])
    }

    func createPlaylist(name: String, songIDs: [String]) async throws -> Playlist? {
        let now = Date()
        let record = LocalPlaylistRecord(
            id: "local-playlist:\(UUID().uuidString)",
            name: name,
            comment: nil,
            songIDs: songIDs.filter { songsByID[$0] != nil },
            created: now,
            changed: now
        )
        let result = persistenceLock.withLock { () -> Playlist in
            localPlaylists.append(record)
            persistLocalData()
            return makePlaylist(record)
        }
        return result
    }

    func addToPlaylist(playlistID: String, songID: String) async throws {
        try mutatePlaylist(id: playlistID) { record in
            guard songsByID[songID] != nil, !record.songIDs.contains(songID) else { return }
            record.songIDs.append(songID)
            record.changed = Date()
        }
    }

    func removeFromPlaylist(playlistID: String, index: Int) async throws {
        try mutatePlaylist(id: playlistID) { record in
            guard record.songIDs.indices.contains(index) else { return }
            record.songIDs.remove(at: index)
            record.changed = Date()
        }
    }

    func deletePlaylist(id: String) async throws {
        persistenceLock.withLock {
            localPlaylists.removeAll { $0.id == id }
            persistLocalData()
        }
    }

    func renamePlaylist(playlistID: String, name: String) async throws {
        try mutatePlaylist(id: playlistID) { record in
            record.name = name
            record.changed = Date()
        }
    }

    func updatePlaylistComment(playlistID: String, comment: String) async throws {
        try mutatePlaylist(id: playlistID) { record in
            record.comment = comment
            record.changed = Date()
        }
    }

    func replacePlaylistSongs(playlistID: String, songIDs: [String]) async throws {
        try mutatePlaylist(id: playlistID) { record in
            record.songIDs = songIDs.filter { songsByID[$0] != nil }
            record.changed = Date()
        }
    }

    func star(id: String) async throws {
        persistenceLock.withLock {
            starredIDs.insert(id)
            persistLocalData()
        }
    }

    func unstar(id: String) async throws {
        persistenceLock.withLock {
            starredIDs.remove(id)
            persistLocalData()
        }
    }

    func localStarredSongIDs() -> Set<String> {
        persistenceLock.withLock { starredIDs }
    }
    func getMusicFolderStats() async throws -> (artists: Int, albums: Int, songs: Int) {
        (artists.count, albums.count, songs.count)
    }
    func scrobble(id: String, at date: Date?, submission: Bool) async throws {}
    func lyricsBySongId(id: String) async throws -> LyricsList? {
        guard let text = lyricsBySongID[id],
              let parsed = LyricsParser.parse(text: text),
              !parsed.lines.isEmpty else { return nil }
        return parsed.lyricsList
    }
    func lyrics(artist: String, title: String) async throws -> String? {
        songs.first {
            $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame
                && ($0.artist ?? "").localizedCaseInsensitiveCompare(artist) == .orderedSame
        }.flatMap { lyricsBySongID[$0.id] }
    }
    func sharingAvailable() async -> Bool { false }
    func createShare(id: String) async throws -> URL? { nil }

    func coverArtURL(id: String?, size: Int?) -> URL? {
        guard let id else { return nil }
        return artworkURLs[id]
    }

    func liveArtworkURLs(id: String?) -> [URL] { [] }

    func streamURL(id: String) -> URL? { songURLs[id] }
    func streamURL(for song: Song) -> URL? { songURLs[song.id] }
    func downloadURL(id: String) -> URL? { songURLs[id] }
    func downloadURL(for song: Song) -> URL? { songURLs[song.id] }
    func originalStreamURL(id: String) -> URL? { songURLs[id] }
    func mediaRequestHeaders() -> [String: String] { [:] }
    func prepareForPlayback(id: String) async {}
    func prepareForPlayback(song: Song) async {}
    func streamMetadataReady(id: String) -> Bool { songURLs[id] != nil }
    func streamMetadataReady(for song: Song) -> Bool { songURLs[song.id] != nil }

    private func makePlaylist(_ record: LocalPlaylistRecord) -> Playlist {
        let entries = record.songIDs.compactMap { songsByID[$0] }
        return Playlist(
            id: record.id,
            name: record.name,
            comment: record.comment,
            owner: "On This Device",
            songCount: entries.count,
            duration: entries.reduce(0) { $0 + ($1.duration ?? 0) },
            created: ISO8601DateFormatter().string(from: record.created),
            changed: ISO8601DateFormatter().string(from: record.changed),
            played: nil,
            coverArt: entries.compactMap(\.coverArt).first,
            entry: entries
        )
    }

    private func mutatePlaylist(id: String, _ mutation: (inout LocalPlaylistRecord) -> Void) throws {
        try persistenceLock.withLock {
            guard let index = localPlaylists.firstIndex(where: { $0.id == id }) else {
                throw SubsonicError.server(code: 0, message: "Playlist not found.")
            }
            mutation(&localPlaylists[index])
            persistLocalData()
        }
    }

    private func persistLocalData() {
        try? FileManager.default.createDirectory(at: localDataDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(localPlaylists) {
            try? data.write(to: playlistsURL, options: .atomic)
        }
        UserDefaults.standard.set(Array(starredIDs), forKey: starredDefaultsKey)
    }

    private static let legacyFavoritesKey = "localMusicStarredIDs"
    private static let legacyFavoritesMigrationKey = "localMusicStarredIDsMigratedToScopedLibraries"
    private static let legacyPlaylistsMigrationKey = "localMusicPlaylistsMigratedToScopedLibraries"

    private static func loadStarredIDs(for libraryID: String, songs: [Song]) -> Set<String> {
        let defaults = UserDefaults.standard
        let key = "localMusicStarredIDs.\(libraryID)"
        if let saved = defaults.stringArray(forKey: key) {
            return Set(saved).intersection(Set(songs.map(\.id)))
        }

        // Legacy IDs contained only the relative path. They are ambiguous once
        // another root is selected, so migrate them once to the currently
        // restored library rather than leaking them into every later library.
        guard !defaults.bool(forKey: legacyFavoritesMigrationKey) else { return [] }
        let remapped = remapLegacySongIDs(defaults.stringArray(forKey: legacyFavoritesKey) ?? [], songs: songs)
        defaults.set(Array(remapped), forKey: key)
        defaults.set(true, forKey: legacyFavoritesMigrationKey)
        return remapped
    }

    private static func loadPlaylists(for libraryID: String, songs: [Song]) -> [LocalPlaylistRecord] {
        let scopedURL = playlistsURL(for: libraryID)
        if let data = try? Data(contentsOf: scopedURL),
           let saved = try? JSONDecoder().decode([LocalPlaylistRecord].self, from: data) {
            return sanitizePlaylists(saved, songs: songs)
        }

        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: legacyPlaylistsMigrationKey),
              let data = try? Data(contentsOf: legacyLocalDataDirectory.appendingPathComponent("playlists.json")),
              let legacy = try? JSONDecoder().decode([LocalPlaylistRecord].self, from: data) else {
            return []
        }
        let migrated = sanitizePlaylists(legacy, songs: songs)
        defaults.set(true, forKey: legacyPlaylistsMigrationKey)
        try? FileManager.default.createDirectory(at: localDataDirectory(for: libraryID), withIntermediateDirectories: true)
        if let encoded = try? JSONEncoder().encode(migrated) {
            try? encoded.write(to: scopedURL, options: .atomic)
        }
        return migrated
    }

    private static func sanitizePlaylists(_ records: [LocalPlaylistRecord], songs: [Song]) -> [LocalPlaylistRecord] {
        let validIDs = Set(songs.map(\.id))
        let legacyMap = Dictionary(uniqueKeysWithValues: songs.map { song in
            (legacySongID(relativePath: song.path ?? ""), song.id)
        })
        return records.map { record in
            var copy = record
            var seen = Set<String>()
            copy.songIDs = record.songIDs.compactMap { id in
                let resolved = validIDs.contains(id) ? id : legacyMap[id]
                guard let resolved, seen.insert(resolved).inserted else { return nil }
                return resolved
            }
            return copy
        }
    }

    private static func remapLegacySongIDs(_ ids: [String], songs: [Song]) -> Set<String> {
        let map = Dictionary(uniqueKeysWithValues: songs.map { song in
            (legacySongID(relativePath: song.path ?? ""), song.id)
        })
        return Set(ids.compactMap { map[$0] })
    }

    private static func legacySongID(relativePath: String) -> String {
        "local-song:\(Crypto.md5Hex(relativePath))"
    }

    private static func loadMetadataCache(for libraryID: String) -> [String: LocalCachedTrack] {
        let url = metadataCacheURL(for: libraryID)
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(LocalMetadataCache.self, from: data),
              cache.schemaVersion == 1 else { return [:] }
        return cache.entries
    }

    private static func saveMetadataCache(_ entries: [String: LocalCachedTrack], for libraryID: String) {
        let directory = localDataDirectory(for: libraryID)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cache = LocalMetadataCache(schemaVersion: 1, entries: entries)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: metadataCacheURL(for: libraryID), options: .atomic)
    }

    private static func scan(rootURL: URL, libraryID: String) async throws -> LocalLibrarySnapshot {
        try await Task.detached(priority: .userInitiated) {
            let files = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )?.compactMap { $0 as? URL } ?? []
            let directories = files.compactMap { url -> String? in
                guard url.standardizedFileURL != rootURL.standardizedFileURL,
                      (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
                return relativePath(url, root: rootURL)
            }
            let audioFiles = files.filter { isSupportedAudio($0) }.sorted { relativePath($0, root: rootURL).localizedStandardCompare(relativePath($1, root: rootURL)) == .orderedAscending }
            guard !audioFiles.isEmpty else { throw LocalLibraryError.noSupportedAudio }

            let imageFiles = files.filter { isSupportedImage($0) }
            // Multiple formats commonly share a stem (`cover.jpg` +
            // `cover.png`). Group first so a duplicate key cannot trap, then
            // choose one with the same deterministic priority used for album
            // artwork elsewhere.
            let imageByKey = Dictionary(uniqueKeysWithValues: Dictionary(grouping: imageFiles) {
                artworkKey($0, root: rootURL)
            }.compactMap { key, urls in
                preferredImage(urls).map { (key, $0) }
            })
            let imageByDirectory = Dictionary(grouping: imageFiles) { $0.deletingLastPathComponent().path }
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Volta/LocalLibrary/Artwork", isDirectory: true)
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

            let cachedTracks = loadMetadataCache(for: libraryID)
            var refreshedCache: [String: LocalCachedTrack] = [:]
            var scanned: [LocalScannedTrack] = []
            var songURLs: [String: URL] = [:]
            var artworkURLs: [String: URL] = [:]
            for url in audioFiles {
                let relative = relativePath(url, root: rootURL)
                let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let modifiedAt = resourceValues?.contentModificationDate ?? .distantPast
                let fileSize = resourceValues?.fileSize ?? 0
                let cached = cachedTracks[relative]
                let cachedArtworkURL = cached?.embeddedArtworkPath.map(URL.init(fileURLWithPath:))
                let canReuseCache = cached?.size == fileSize
                    && cached?.modifiedAt == modifiedAt
                    && (cachedArtworkURL == nil || FileManager.default.fileExists(atPath: cachedArtworkURL!.path))
                var metadata = canReuseCache ? (cached?.metadata ?? LocalMetadata()) : await readMetadata(url)
                var embeddedArtworkURL = canReuseCache ? cachedArtworkURL : nil
                var lyricsFromSidecar = canReuseCache ? (cached?.lyricsFromSidecar ?? false) : false
                let songID = songID(for: relative, libraryID: libraryID)
                let stem = url.deletingPathExtension().lastPathComponent
                let directoryImages = imageByDirectory[url.deletingLastPathComponent().path] ?? []
                if metadata.lyrics == nil || lyricsFromSidecar {
                    var sidecarLyrics: String?
                    let sidecarExtensions = ["lrc", "ttml", "txt"]
                    for ext in sidecarExtensions {
                        let sidecar = url.deletingPathExtension().appendingPathExtension(ext)
                        if let data = try? Data(contentsOf: sidecar),
                           let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).nonBlank {
                            sidecarLyrics = text
                            break
                        }
                    }
                    if let sidecarLyrics {
                        metadata.lyrics = sidecarLyrics
                        lyricsFromSidecar = true
                    } else if lyricsFromSidecar {
                        // The sidecar was removed; do not keep stale lyrics.
                        metadata.lyrics = nil
                        lyricsFromSidecar = false
                    }
                }
                let sibling = imageByKey["\(url.deletingLastPathComponent().path)\u{1f}\(stem.lowercased())"]
                    ?? preferredImage(directoryImages)
                var artworkURL = sibling
                if let artwork = metadata.artwork {
                    let fingerprint = Crypto.md5Hex(
                        "\(songID)|\(fileSize)|\(modifiedAt.timeIntervalSinceReferenceDate)|\(Crypto.md5Hex(artwork))"
                    )
                    let extracted = appSupport.appendingPathComponent("\(fingerprint).\(imageFileExtension(for: artwork))")
                    if !FileManager.default.fileExists(atPath: extracted.path) {
                        try? artwork.write(to: extracted, options: .atomic)
                    }
                    if FileManager.default.fileExists(atPath: extracted.path) {
                        embeddedArtworkURL = extracted
                        artworkURL = extracted
                    }
                } else if let embeddedArtworkURL {
                    artworkURL = embeddedArtworkURL
                }
                let artworkLookupID = artworkURL.map { Self.artworkID(for: $0, root: rootURL, libraryID: libraryID) }
                if let artworkLookupID, let artworkURL { artworkURLs[artworkLookupID] = artworkURL }
                let values = LocalMetadata(
                    title: metadata.title ?? stem.nonBlank,
                    artist: metadata.artist,
                    albumArtist: metadata.albumArtist,
                    album: metadata.album,
                    track: metadata.track,
                    discNumber: metadata.discNumber,
                    year: metadata.year,
                    genre: metadata.genre,
                    codec: metadata.codec,
                    bitRate: metadata.bitRate,
                    samplingRate: metadata.samplingRate,
                    bitDepth: metadata.bitDepth,
                    channelCount: metadata.channelCount,
                    duration: metadata.duration,
                    artwork: nil,
                    lyrics: metadata.lyrics
                )
                let song = LocalSongBuilder.song(
                    id: songID,
                    relativePath: relative,
                    url: url,
                    metadata: values,
                    artworkID: artworkLookupID
                )
                scanned.append(LocalScannedTrack(
                    url: url,
                    relativePath: relative,
                    modifiedAt: modifiedAt,
                    size: fileSize,
                    suffix: url.pathExtension.lowercased(),
                    contentType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType,
                    metadata: values,
                    artworkURL: artworkURL
                ))
                songURLs[song.id] = url
                var cacheMetadata = metadata
                cacheMetadata.artwork = nil // large image bytes live in Artwork/ instead of JSON
                refreshedCache[relative] = LocalCachedTrack(
                    size: fileSize,
                    modifiedAt: modifiedAt,
                    metadata: cacheMetadata,
                    embeddedArtworkPath: embeddedArtworkURL?.path,
                    lyricsFromSidecar: lyricsFromSidecar
                )
            }

            saveMetadataCache(refreshedCache, for: libraryID)

            return buildSnapshot(
                folderName: rootURL.lastPathComponent,
                libraryID: libraryID,
                rootURL: rootURL,
                directories: directories,
                tracks: scanned,
                songURLs: songURLs,
                artworkURLs: artworkURLs,
                lyricsBySongID: Dictionary(uniqueKeysWithValues: scanned.compactMap { track in
                    let id = songID(for: track.relativePath, libraryID: libraryID)
                    return track.metadata.lyrics.map { (id, $0) }
                })
            )
        }.value
    }

    private static func buildSnapshot(
        folderName: String,
        libraryID: String,
        rootURL: URL,
        directories: [String],
        tracks: [LocalScannedTrack],
        songURLs: [String: URL],
        artworkURLs: [String: URL],
        lyricsBySongID: [String: String]
    ) -> LocalLibrarySnapshot {
        var songs: [Song] = []
        var songsByAlbum: [String: [Song]] = [:]
        var albumValues: [String: (name: String, artist: String, artistID: String, cover: String?, modified: Date)] = [:]
        var artistAlbums: [String: [String]] = [:]
        var artistNames: [String: String] = [:]
        for track in tracks {
            let artist = track.metadata.artist ?? "Unknown Artist"
            let albumArtist = track.metadata.albumArtist ?? artist
            let album = track.metadata.album ?? "Unknown Album"
            let artistID = "local-artist:\(libraryID):\(Crypto.md5Hex(normalized(artist)))"
            let albumArtistID = "local-artist:\(libraryID):\(Crypto.md5Hex(normalized(albumArtist)))"
            let albumID = "local-album:\(libraryID):\(Crypto.md5Hex(normalized(albumArtist) + "\u{1f}" + normalized(album)))"
            let artworkLookupID = track.artworkURL.map { Self.artworkID(for: $0, root: rootURL, libraryID: libraryID) }
            let songID = songID(for: track.relativePath, libraryID: libraryID)
            let song = LocalSongBuilder.song(
                id: songID,
                relativePath: track.relativePath,
                url: track.url,
                metadata: track.metadata,
                artworkID: artworkLookupID,
                artist: artist,
                albumArtist: albumArtist,
                album: album,
                artistID: artistID,
                albumArtistID: albumArtistID,
                albumID: albumID,
                size: track.size,
                contentType: track.contentType,
                modifiedAt: track.modifiedAt
            )
            songs.append(song)
            songsByAlbum[albumID, default: []].append(song)
            albumValues[albumID] = (
                album,
                albumArtist,
                albumArtistID,
                artworkLookupID,
                max(albumValues[albumID]?.modified ?? .distantPast, track.modifiedAt)
            )
            artistNames[albumArtistID] = albumArtist
            if !artistAlbums[albumArtistID, default: []].contains(albumID) {
                artistAlbums[albumArtistID, default: []].append(albumID)
            }
        }

        let sortedSongs = songs.sorted(by: LocalSongBuilder.sort)
        let albums: [Album] = albumValues.map { id, value in
            let albumSongs = (songsByAlbum[id] ?? []).sorted(by: LocalSongBuilder.sort)
            return Album(
                id: id,
                name: value.name,
                artist: value.artist,
                artistId: value.artistID,
                coverArt: value.cover,
                songCount: albumSongs.count,
                duration: albumSongs.reduce(0) { $0 + ($1.duration ?? 0) },
                playCount: nil,
                created: ISO8601DateFormatter().string(from: value.modified),
                year: albumSongs.compactMap(\.year).first,
                genre: albumSongs.compactMap(\.genre).first,
                starred: nil,
                comment: nil,
                recordLabel: nil,
                song: albumSongs
            )
        }.sorted { (left: Album, right: Album) in
            left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }

        let albumMap = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })
        let artists: [Artist] = artistNames.map { id, name in
            let artistAlbums = (artistAlbums[id] ?? []).compactMap { albumMap[$0] }
            return Artist(id: id, name: name, coverArt: artistAlbums.compactMap(\.coverArt).first, albumCount: artistAlbums.count, artistImageUrl: nil, starred: nil, album: artistAlbums)
        }.sorted { (left: Artist, right: Artist) in
            left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }

        return LocalLibrarySnapshot(
            folderName: folderName,
            directories: directories,
            songs: sortedSongs,
            albums: albums,
            artists: artists,
            songURLs: songURLs,
            artworkURLs: artworkURLs,
            lyricsBySongID: lyricsBySongID
        )
    }

    private static func readMetadata(_ url: URL) async -> LocalMetadata {
        // AVFoundation is a useful fallback, but it does not expose every tag
        // family consistently (notably ID3/FLAC/iTunes artwork on Files URLs).
        // The web player reads these containers directly, so do the same here
        // and only use AVFoundation to fill fields the byte reader missed.
        let embedded = readByteMetadata(url)
        let assetMetadata = await readAVFoundationMetadata(url)
        var result = mergeMetadata(embedded, assetMetadata)

        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration))?.seconds ?? 0
        result.duration = duration.isFinite && duration > 0 ? Int(duration.rounded()) : nil
        return result
    }

    private static func readAVFoundationMetadata(_ url: URL) async -> LocalMetadata {
        let asset = AVURLAsset(url: url)
        var result = LocalMetadata()
        let commonMetadata = (try? await asset.load(.commonMetadata)) ?? []
        for item in commonMetadata {
            let common = item.commonKey?.rawValue.lowercased() ?? ""
            let rawKey = String(describing: item.key).lowercased()
            let key = common.isEmpty ? rawKey : common
            let text = (try? await item.load(.stringValue))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nonBlank
            let number = try? await item.load(.numberValue)
            let dataValue = try? await item.load(.dataValue)
            switch key {
            case "title", "©nam", "tit2": result.title = result.title ?? text
            case "artist", "©art", "tpe1": result.artist = result.artist ?? text
            case "albumartist", "album artist", "aart", "tpe2": result.albumArtist = result.albumArtist ?? text
            case "albumname", "album", "©alb", "talb": result.album = result.album ?? text
            case "genre", "©gen", "tcon": result.genre = result.genre ?? text
            case "creationdate", "©day", "tdrc": result.year = result.year ?? parseNumber(text)
            case "tracknumber", "trkn", "trck": result.track = result.track ?? parseNumber(text) ?? number?.intValue
            case "discnumber", "disk": result.discNumber = result.discNumber ?? parseNumber(text) ?? number?.intValue
            case "type", "codec": result.codec = result.codec ?? text
            case "lyrics", "unsyncedlyrics", "uslt": result.lyrics = result.lyrics ?? text
            case "artwork", "covr", "apic": result.artwork = result.artwork ?? dataValue
            default: break
            }
        }

        // Container tags do not consistently include technical stream details.
        // AVFoundation exposes those for the formats the current platform can
        // decode, without guessing when a track does not report them.
        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        if let track = audioTracks.first {
            let estimatedRate = (try? await track.load(.estimatedDataRate)) ?? 0
            if estimatedRate.isFinite, estimatedRate > 0 {
                result.bitRate = Int((estimatedRate / 1_000).rounded())
            }
            let descriptions = (try? await track.load(.formatDescriptions)) ?? []
            for description in descriptions {
                guard let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description) else { continue }
                let format = streamDescription.pointee
                if format.mSampleRate.isFinite, format.mSampleRate > 0 {
                    result.samplingRate = result.samplingRate ?? Int(format.mSampleRate.rounded())
                }
                if format.mBitsPerChannel > 0 {
                    result.bitDepth = result.bitDepth ?? Int(format.mBitsPerChannel)
                }
                if format.mChannelsPerFrame > 0 {
                    result.channelCount = result.channelCount ?? Int(format.mChannelsPerFrame)
                }
            }
        }
        return result
    }

    private static func mergeMetadata(_ primary: LocalMetadata, _ fallback: LocalMetadata) -> LocalMetadata {
        LocalMetadata(
            title: primary.title ?? fallback.title,
            artist: primary.artist ?? fallback.artist,
            albumArtist: primary.albumArtist ?? fallback.albumArtist,
            album: primary.album ?? fallback.album,
            track: primary.track ?? fallback.track,
            discNumber: primary.discNumber ?? fallback.discNumber,
            year: primary.year ?? fallback.year,
            genre: primary.genre ?? fallback.genre,
            codec: primary.codec ?? fallback.codec,
            bitRate: primary.bitRate ?? fallback.bitRate,
            samplingRate: primary.samplingRate ?? fallback.samplingRate,
            bitDepth: primary.bitDepth ?? fallback.bitDepth,
            channelCount: primary.channelCount ?? fallback.channelCount,
            duration: primary.duration ?? fallback.duration,
            artwork: primary.artwork ?? fallback.artwork,
            lyrics: primary.lyrics ?? fallback.lyrics
        )
    }

    private static func readByteMetadata(_ url: URL) -> LocalMetadata {
        let limit = 2 * 1024 * 1024
        guard let head = readFileBytes(url, offset: 0, count: limit) else {
            return LocalMetadata()
        }

        var result = parseContainerMetadata(head, suffix: url.pathExtension.lowercased())
        // Large M4A/MP4 files commonly keep their moov box at the end.
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if ["m4a", "mp4", "alac"].contains(url.pathExtension.lowercased()),
           fileSize > limit,
           let tail = readFileBytes(url, offset: max(0, fileSize - limit), count: limit) {
            result = mergeMetadata(result, parseContainerMetadata(tail, suffix: url.pathExtension.lowercased()))
        }
        return result
    }

    private static func readFileBytes(_ url: URL, offset: Int, count: Int) -> [UInt8]? {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            try handle.seek(toOffset: UInt64(max(0, offset)))
            let data = try handle.read(upToCount: count) ?? Data()
            try handle.close()
            return Array(data)
        } catch {
            return nil
        }
    }

    private static func parseContainerMetadata(_ bytes: [UInt8], suffix: String) -> LocalMetadata {
        if bytes.count >= 3, String(bytes: bytes.prefix(3), encoding: .ascii) == "ID3" {
            return parseID3(bytes)
        }
        if bytes.count >= 4, String(bytes: bytes.prefix(4), encoding: .ascii) == "fLaC" {
            return parseFLAC(bytes)
        }
        if bytes.count >= 8, fourCC(bytes, at: 4) == "ftyp" || ["m4a", "mp4", "alac"].contains(suffix) {
            let parsed = parseMP4(bytes)
            if parsed.title != nil || parsed.artist != nil || parsed.album != nil || parsed.artwork != nil {
                return parsed
            }
            if let moov = findMP4Box(bytes, type: "moov") {
                return parseMP4(moov)
            }
            return parsed
        }
        return LocalMetadata()
    }

    private static func parseID3(_ bytes: [UInt8]) -> LocalMetadata {
        guard bytes.count >= 10 else { return LocalMetadata() }
        let version = bytes[3]
        let tagEnd = min(bytes.count, 10 + syncSafe(bytes, at: 6))
        var offset = 10
        var result = LocalMetadata()
        if version >= 3, bytes[5] & 0x40 != 0, offset + 4 <= tagEnd {
            let extendedSize = version >= 4 ? syncSafe(bytes, at: offset) : bigEndian32(bytes, at: offset)
            offset += 4 + extendedSize
        }

        while version == 2 ? offset + 6 <= tagEnd : offset + 10 <= tagEnd {
            let headerSize = version == 2 ? 6 : 10
            let id = String(bytes: bytes[offset..<(offset + (version == 2 ? 3 : 4))], encoding: .ascii) ?? ""
            guard !id.trimmingCharacters(in: .controlCharacters).isEmpty else { break }
            let frameSize: Int
            if version == 2 {
                frameSize = bigEndian24(bytes, at: offset + 3)
            } else {
                frameSize = version >= 4 ? syncSafe(bytes, at: offset + 4) : bigEndian32(bytes, at: offset + 4)
            }
            guard frameSize > 0, offset + headerSize + frameSize <= tagEnd else { break }
            let frame = Array(bytes[(offset + headerSize)..<(offset + headerSize + frameSize)])
            let field: String? = [
                "TIT2": "title", "TT2": "title",
                "TPE1": "artist", "TP1": "artist",
                "TPE2": "albumArtist", "TP2": "albumArtist",
                "TALB": "album", "TAL": "album",
                "TRCK": "track", "TRK": "track",
                "TPOS": "discNumber", "TPA": "discNumber",
                "TDRC": "year", "TYER": "year",
                "TCON": "genre", "TCO": "genre"
            ][id]
            if let field, let text = decodeID3Text(frame) {
                assign(text: text, field: field, to: &result)
            } else if id == "USLT" || id == "ULT" {
                result.lyrics = result.lyrics ?? decodeID3Text(frame)
            } else if id == "APIC" || id == "PIC" {
                result.artwork = result.artwork ?? parseID3Artwork(frame, version: version)
            }
            offset += headerSize + frameSize
        }
        return result
    }

    private static func parseFLAC(_ bytes: [UInt8]) -> LocalMetadata {
        guard bytes.count >= 4 else { return LocalMetadata() }
        var offset = 4
        var result = LocalMetadata()
        while offset + 4 <= bytes.count {
            let header = bytes[offset]
            let type = header & 0x7f
            let length = (Int(bytes[offset + 1]) << 16) | (Int(bytes[offset + 2]) << 8) | Int(bytes[offset + 3])
            let start = offset + 4
            let end = start + length
            guard end <= bytes.count else { break }
            let block = Array(bytes[start..<end])
            if type == 0, block.count >= 18 {
                // STREAMINFO packs 20-bit sample rate, 3-bit channel count,
                // and 5-bit bits-per-sample in bytes 10...17.
                let packed = (UInt64(block[10]) << 56)
                    | (UInt64(block[11]) << 48)
                    | (UInt64(block[12]) << 40)
                    | (UInt64(block[13]) << 32)
                    | (UInt64(block[14]) << 24)
                    | (UInt64(block[15]) << 16)
                    | (UInt64(block[16]) << 8)
                    | UInt64(block[17])
                let sampleRate = Int((packed >> 44) & 0xFFFFF)
                let channels = Int((packed >> 41) & 0x7) + 1
                let bits = Int((packed >> 36) & 0x1F) + 1
                result.codec = result.codec ?? "flac"
                if sampleRate > 0 { result.samplingRate = result.samplingRate ?? sampleRate }
                if channels > 0 { result.channelCount = result.channelCount ?? channels }
                if bits > 0 { result.bitDepth = result.bitDepth ?? bits }
            } else if type == 4, block.count >= 8 {
                var cursor = 4 + littleEndian32(block, at: 0)
                guard cursor + 4 <= block.count else { break }
                let count = littleEndian32(block, at: cursor)
                cursor += 4
                for _ in 0..<count where cursor + 4 <= block.count {
                    let size = littleEndian32(block, at: cursor)
                    cursor += 4
                    guard size >= 0, cursor + size <= block.count else { break }
                    let comment = String(bytes: block[cursor..<(cursor + size)], encoding: .utf8) ?? ""
                    if let equals = comment.firstIndex(of: "=") {
                        assign(text: String(comment[comment.index(after: equals)...]), field: String(comment[..<equals]).lowercased(), to: &result)
                    }
                    cursor += size
                }
            } else if type == 6, let image = parseFLACPicture(block) {
                result.artwork = result.artwork ?? image
            }
            offset = end
            if header & 0x80 != 0 { break }
        }
        return result
    }

    private static func parseMP4(_ bytes: [UInt8]) -> LocalMetadata {
        var result = LocalMetadata()
        parseMP4Boxes(bytes, start: 0, end: bytes.count, result: &result)
        return result
    }

    private static func findMP4Box(_ bytes: [UInt8], type wanted: String) -> [UInt8]? {
        guard bytes.count >= 8 else { return nil }
        for offset in 0...(bytes.count - 8) {
            guard fourCC(bytes, at: offset + 4) == wanted else { continue }
            let size = bigEndian32(bytes, at: offset)
            guard size >= 8, offset + size <= bytes.count else { continue }
            return Array(bytes[offset..<(offset + size)])
        }
        return nil
    }

    private static func parseMP4Boxes(
        _ bytes: [UInt8],
        start: Int,
        end: Int,
        result: inout LocalMetadata,
        inILST: Bool = false,
        itemType: String? = nil
    ) {
        var offset = start
        while offset + 8 <= end {
            let declaredSize = bigEndian32(bytes, at: offset)
            let type = fourCC(bytes, at: offset + 4)
            let boxEnd = min(end, offset + (declaredSize == 0 ? end - offset : declaredSize))
            guard boxEnd > offset + 8 else { break }
            let payload = offset + 8 + (type == "meta" ? 4 : 0)
            if ["moov", "trak", "mdia", "minf", "stbl", "udta", "meta", "ilst"].contains(type) {
                parseMP4Boxes(bytes, start: payload, end: boxEnd, result: &result, inILST: inILST || type == "ilst", itemType: itemType)
            } else if inILST, type != "data" {
                parseMP4Boxes(bytes, start: payload, end: boxEnd, result: &result, inILST: true, itemType: type)
            } else if inILST, type == "data", boxEnd >= offset + 16 {
                let value = Array(bytes[(offset + 16)..<boxEnd])
                switch itemType {
                case "©nam": result.title = result.title ?? cleanText(value)
                case "©ART": result.artist = result.artist ?? cleanText(value)
                case "aART": result.albumArtist = result.albumArtist ?? cleanText(value)
                case "©alb": result.album = result.album ?? cleanText(value)
                case "©day": result.year = result.year ?? parseNumber(cleanText(value))
                case "©gen": result.genre = result.genre ?? cleanText(value)
                case "trkn" where value.count >= 4: result.track = result.track ?? ((Int(value[2]) << 8) | Int(value[3]))
                case "disk" where value.count >= 4: result.discNumber = result.discNumber ?? ((Int(value[2]) << 8) | Int(value[3]))
                case "covr": result.artwork = result.artwork ?? Data(value)
                default: break
                }
            }
            offset = boxEnd
        }
    }

    private static func parseID3Artwork(_ frame: [UInt8], version: UInt8) -> Data? {
        guard frame.count > 4 else { return nil }
        if version == 2 {
            guard frame.count > 6 else { return nil }
            var cursor = 4
            while cursor < frame.count && frame[cursor] != 0 { cursor += 1 }
            cursor = min(frame.count, cursor + 1 + 1)
            while cursor < frame.count && frame[cursor] != 0 { cursor += 1 }
            cursor += 1
            return cursor < frame.count ? Data(frame[cursor...]) : nil
        }
        let encoding = frame[0]
        var cursor = 1
        while cursor < frame.count && frame[cursor] != 0 { cursor += 1 }
        cursor = min(frame.count, cursor + 1)
        guard cursor < frame.count else { return nil }
        cursor += 1 // picture type
        if encoding == 1 || encoding == 2 {
            while cursor + 1 < frame.count && !(frame[cursor] == 0 && frame[cursor + 1] == 0) { cursor += 2 }
            cursor = min(frame.count, cursor + 2)
        } else {
            while cursor < frame.count && frame[cursor] != 0 { cursor += 1 }
            cursor = min(frame.count, cursor + 1)
        }
        return cursor < frame.count ? Data(frame[cursor...]) : nil
    }

    private static func parseFLACPicture(_ block: [UInt8]) -> Data? {
        var cursor = 4
        guard cursor + 4 <= block.count else { return nil }
        let mimeLength = bigEndian32(block, at: cursor); cursor += 4 + mimeLength
        guard cursor + 4 <= block.count else { return nil }
        let descriptionLength = bigEndian32(block, at: cursor); cursor += 4 + descriptionLength
        guard cursor + 16 <= block.count else { return nil }
        cursor += 16
        guard cursor + 4 <= block.count else { return nil }
        let imageLength = bigEndian32(block, at: cursor); cursor += 4
        guard imageLength > 0, cursor + imageLength <= block.count else { return nil }
        return Data(block[cursor..<(cursor + imageLength)])
    }

    private static func decodeID3Text(_ frame: [UInt8]) -> String? {
        guard let encoding = frame.first else { return nil }
        let payload = Array(frame.dropFirst())
        let value: String?
        switch encoding {
        case 1: value = String(bytes: payload, encoding: .utf16)
        case 2: value = String(bytes: payload, encoding: .utf16BigEndian)
        case 3: value = String(bytes: payload, encoding: .utf8)
        default: value = String(bytes: payload, encoding: .isoLatin1)
        }
        return value?.replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonBlank
    }

    private static func assign(text: String, field: String, to metadata: inout LocalMetadata) {
        let value = text.replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonBlank
        guard let value else { return }
        switch field.lowercased() {
        case "title": metadata.title = metadata.title ?? value
        case "artist": metadata.artist = metadata.artist ?? value
        case "albumartist", "album artist", "aart": metadata.albumArtist = metadata.albumArtist ?? value
        case "album", "albumname": metadata.album = metadata.album ?? value
        case "track", "tracknumber", "trck": metadata.track = metadata.track ?? parseNumber(value)
        case "disc", "discnumber", "disk", "tpos": metadata.discNumber = metadata.discNumber ?? parseNumber(value)
        case "year", "creationdate", "date", "tdrc", "tyer": metadata.year = metadata.year ?? parseNumber(value)
        case "genre": metadata.genre = metadata.genre ?? value
        case "lyrics", "unsyncedlyrics", "uslt": metadata.lyrics = metadata.lyrics ?? value
        default: break
        }
    }

    private static func cleanText(_ bytes: [UInt8]) -> String {
        String(bytes: bytes, encoding: .utf8)?.replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            ?? String(bytes: bytes, encoding: .isoLatin1)?.replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
    }

    private static func fourCC(_ bytes: [UInt8], at offset: Int) -> String {
        guard offset >= 0, offset + 4 <= bytes.count else { return "" }
        return String(bytes: bytes[offset..<(offset + 4)], encoding: .isoLatin1) ?? ""
    }

    private static func bigEndian24(_ bytes: [UInt8], at offset: Int) -> Int {
        guard offset + 3 <= bytes.count else { return 0 }
        return (Int(bytes[offset]) << 16) | (Int(bytes[offset + 1]) << 8) | Int(bytes[offset + 2])
    }

    private static func bigEndian32(_ bytes: [UInt8], at offset: Int) -> Int {
        guard offset + 4 <= bytes.count else { return 0 }
        return (Int(bytes[offset]) << 24) | (Int(bytes[offset + 1]) << 16) | (Int(bytes[offset + 2]) << 8) | Int(bytes[offset + 3])
    }

    private static func littleEndian32(_ bytes: [UInt8], at offset: Int) -> Int {
        guard offset + 4 <= bytes.count else { return 0 }
        return Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8) | (Int(bytes[offset + 2]) << 16) | (Int(bytes[offset + 3]) << 24)
    }

    private static func syncSafe(_ bytes: [UInt8], at offset: Int) -> Int {
        guard offset + 4 <= bytes.count else { return 0 }
        return (Int(bytes[offset]) << 21) | (Int(bytes[offset + 1]) << 14) | (Int(bytes[offset + 2]) << 7) | Int(bytes[offset + 3])
    }

    private static func parseNumber(_ value: String?) -> Int? {
        guard let value else { return nil }
        let digits = value.split { !$0.isNumber }.first.map(String.init)
        return digits.flatMap(Int.init)
    }

    private static func isSupportedAudio(_ url: URL) -> Bool {
        ["aac", "aif", "aiff", "alac", "caf", "flac", "m4a", "mp3", "mp4", "oga", "ogg", "opus", "wav", "wave", "weba", "wma"].contains(url.pathExtension.lowercased())
    }

    private static func isSupportedImage(_ url: URL) -> Bool {
        ["avif", "gif", "heic", "jpeg", "jpg", "png", "webp"].contains(url.pathExtension.lowercased())
    }

    private static func relativePath(_ url: URL, root: URL) -> String {
        let prefix = root.standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.hasPrefix(prefix)
            ? String(url.standardizedFileURL.path.dropFirst(prefix.count))
            : url.lastPathComponent
    }

    private static func songID(for relativePath: String, libraryID: String) -> String {
        "local-song:\(libraryID):\(Crypto.md5Hex(relativePath))"
    }

    private static func artworkID(for url: URL, root: URL, libraryID: String) -> String {
        "local-art:\(libraryID):\(Crypto.md5Hex(relativePath(url, root: root)))"
    }

    private static func imageFileExtension(for data: Data) -> String {
        let header = [UInt8](data.prefix(12))
        if header.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if header.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if header.starts(with: Array("GIF".utf8)) { return "gif" }
        if header.count >= 12,
           String(bytes: header[8..<12], encoding: .ascii) == "WEBP" { return "webp" }
        // ImageIO/UIImage can still decode several valid containers without a
        // recognizable short signature. Use a neutral binary extension rather
        // than incorrectly claiming the bytes are JPEG.
        return "img"
    }

    private static func artworkKey(_ url: URL, root: URL) -> String {
        "\(url.deletingLastPathComponent().path)\u{1f}\(url.deletingPathExtension().lastPathComponent.lowercased())"
    }

    private static func preferredImage(_ urls: [URL]) -> URL? {
        let preferred = ["cover", "folder", "front", "album", "artwork", "artist"]
        return urls.sorted {
            let left = preferred.firstIndex(of: $0.deletingPathExtension().lastPathComponent.lowercased()) ?? preferred.count
            let right = preferred.firstIndex(of: $1.deletingPathExtension().lastPathComponent.lowercased()) ?? preferred.count
            return left == right ? $0.path < $1.path : left < right
        }.first
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum LocalSongBuilder {
    static func song(
        id: String,
        relativePath: String,
        url: URL,
        metadata: LocalMetadata,
        artworkID: String?,
        artist: String? = nil,
        albumArtist: String? = nil,
        album: String? = nil,
        artistID: String? = nil,
        albumArtistID: String? = nil,
        albumID: String? = nil,
        size: Int? = nil,
        contentType: String? = nil,
        modifiedAt: Date? = nil
    ) -> Song {
        Song(
            id: id,
            title: metadata.title ?? url.deletingPathExtension().lastPathComponent,
            album: album ?? metadata.album,
            artist: artist ?? metadata.artist,
            albumArtist: albumArtist ?? metadata.albumArtist,
            albumId: albumID,
            artistId: artistID,
            albumArtistId: albumArtistID,
            coverArt: artworkID,
            duration: metadata.duration,
            track: metadata.track,
            discNumber: metadata.discNumber,
            year: metadata.year,
            genre: metadata.genre,
            size: size,
            contentType: contentType,
            suffix: url.pathExtension.lowercased(),
            codec: metadata.codec,
            bitRate: metadata.bitRate,
            path: relativePath,
            playCount: nil,
            bpm: nil,
            explicitStatus: nil,
            starred: nil,
            contributes: nil,
            replayGain: nil,
            samplingRate: metadata.samplingRate,
            bitDepth: metadata.bitDepth,
            channelCount: metadata.channelCount,
            displayComposer: nil,
            contributors: nil
        )
    }

    static func sort(_ left: Song, _ right: Song) -> Bool {
        (left.discNumber ?? Int.max, left.track ?? Int.max, left.title.localizedLowercase)
            < (right.discNumber ?? Int.max, right.track ?? Int.max, right.title.localizedLowercase)
    }
}
