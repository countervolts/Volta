import Foundation

/// A portable representation of a playlist track.  IDs are still included for
/// quick, lossless restores to the same server, while the descriptive fields
/// allow an export to move between servers with different library IDs.
struct ExportedPlaylistTrack: Codable, Hashable, Sendable {
    let sourceID: String
    let title: String
    let artist: String?
    let album: String?
    let albumArtist: String?
    let duration: Int?
    let track: Int?
    let discNumber: Int?

    init(song: Song) {
        sourceID = song.id
        title = song.title
        artist = song.artist
        album = song.album
        albumArtist = song.albumArtist
        duration = song.duration
        track = song.track
        discNumber = song.discNumber
    }
}

/// Playlist data intentionally keeps `songIDs` alongside `tracks`.  Older
/// Volta releases only understand `songIDs`, and older export files omit
/// `tracks`; retaining both makes the format forward and backward compatible.
struct ExportedPlaylist: Codable, Sendable {
    let name: String
    let comment: String?
    let songIDs: [String]
    let tracks: [ExportedPlaylistTrack]?

    init(name: String, comment: String?, songs: [Song]) {
        self.name = name
        self.comment = comment
        songIDs = songs.map(\.id)
        tracks = songs.map(ExportedPlaylistTrack.init(song:))
    }

    init(name: String, comment: String?, songIDs: [String], tracks: [ExportedPlaylistTrack]? = nil) {
        self.name = name
        self.comment = comment
        self.songIDs = songIDs
        self.tracks = tracks
    }
}

struct PlaylistTransferSource: Codable, Equatable, Sendable {
    let serverURL: String
    let backend: MusicBackendKind

    init(client: any MusicService) {
        serverURL = client.config.baseURL.absoluteString
        backend = client.backendKind
    }

    func matches(_ client: any MusicService) -> Bool {
        backend == client.backendKind
            && PlaylistTransfer.normalizedServerURL(serverURL)
                == PlaylistTransfer.normalizedServerURL(client.config.baseURL.absoluteString)
    }
}

/// Version 2 adds source identity and descriptive track metadata.  The import
/// decoder also accepts the version-1 top-level array produced by Volta 1.3.
struct PlaylistTransferArchive: Codable, Sendable {
    static let currentVersion = 2

    let version: Int
    let exportedAt: Date
    let source: PlaylistTransferSource?
    let playlists: [ExportedPlaylist]

    init(
        version: Int = currentVersion,
        exportedAt: Date = .now,
        source: PlaylistTransferSource?,
        playlists: [ExportedPlaylist]
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.source = source
        self.playlists = playlists
    }
}

struct PlaylistImportResult: Equatable, Sendable {
    var playlistsCreated = 0
    var playlistsSkipped = 0
    var playlistsFailed = 0
    var tracksImported = 0
    var tracksUnmatched = 0
    var tracksFailed = 0

    var hasWarnings: Bool {
        playlistsSkipped > 0 || playlistsFailed > 0 || tracksUnmatched > 0 || tracksFailed > 0
    }

    var statusText: String {
        var details: [String] = ["Imported \(playlistsCreated) playlist\(playlistsCreated == 1 ? "" : "s")"]
        if playlistsSkipped > 0 {
            details.append("\(playlistsSkipped) duplicate\(playlistsSkipped == 1 ? "" : "s") skipped")
        }
        if playlistsFailed > 0 {
            details.append("\(playlistsFailed) playlist\(playlistsFailed == 1 ? "" : "s") failed")
        }
        if tracksUnmatched > 0 {
            details.append("\(tracksUnmatched) track\(tracksUnmatched == 1 ? "" : "s") not found")
        }
        if tracksFailed > 0 {
            details.append("\(tracksFailed) track\(tracksFailed == 1 ? "" : "s") not added")
        }
        return details.joined(separator: " · ")
    }
}

enum PlaylistTrackMatcher {
    /// Returns a high-confidence match only.  A title alone is not enough to
    /// restore a track because covers, remasters, and live versions often share
    /// one; at least one other matching piece of metadata is required.
    static func bestMatch(for track: ExportedPlaylistTrack, in candidates: [Song]) -> Song? {
        let scored = candidates.compactMap { candidate -> (song: Song, score: Int)? in
            guard normalized(candidate.title) == normalized(track.title) else { return nil }

            var score = 100
            var corroboratingFields = 0

            if matches(track.artist, candidate.artist) {
                score += 40
                corroboratingFields += 1
            }
            if matches(track.album, candidate.album) {
                score += 25
                corroboratingFields += 1
            }
            if matches(track.albumArtist, candidate.albumArtist) {
                score += 10
                corroboratingFields += 1
            }
            if let sourceDuration = track.duration, let candidateDuration = candidate.duration {
                let difference = abs(sourceDuration - candidateDuration)
                if difference <= 2 {
                    score += 15
                    corroboratingFields += 1
                } else if difference <= 5 {
                    score += 7
                }
            }
            if let sourceTrack = track.track, sourceTrack == candidate.track {
                score += 8
                corroboratingFields += 1
            }
            if let sourceDisc = track.discNumber, sourceDisc == candidate.discNumber {
                score += 4
            }

            // A match needs title plus reliable corroboration.  The slightly
            // higher score requirement for a track with artist/album metadata
            // prevents a title-and-duration coincidence from being restored.
            let needsNamedMatch = !isBlank(track.artist) || !isBlank(track.album)
            let threshold = needsNamedMatch ? 125 : 115
            guard corroboratingFields > 0, score >= threshold else { return nil }
            return (candidate, score)
        }

        guard let top = scored.max(by: { $0.score < $1.score }) else { return nil }
        // Do not silently pick between equally credible candidates.  Restoring
        // fewer songs is better than putting the wrong version in a playlist.
        let ties = scored.filter { $0.score == top.score }
        return ties.count == 1 ? top.song : nil
    }

    static func searchQuery(for track: ExportedPlaylistTrack) -> String {
        [track.artist, track.title]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nonBlank }
            .joined(separator: " ")
    }

    private static func matches(_ source: String?, _ candidate: String?) -> Bool {
        guard !isBlank(source), !isBlank(candidate) else { return false }
        return normalized(source) == normalized(candidate)
    }

    private static func isBlank(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }

    private static func normalized(_ value: String?) -> String {
        guard let value else { return "" }
        return value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

// Exports playlists as JSON and restores them.  Same-server restores preserve
// exact IDs; cross-server restores search for a conservative metadata match.
enum PlaylistTransfer {
    static func exportURL(client: any MusicService) async throws -> URL {
        let playlists = try await client.playlists()
        var exported: [ExportedPlaylist] = []
        for playlist in playlists {
            let full = try? await client.playlist(id: playlist.id)
            let songs = full?.entry ?? playlist.entry ?? []
            exported.append(ExportedPlaylist(
                name: playlist.name,
                comment: full?.comment ?? playlist.comment,
                songs: songs
            ))
        }
        let archive = PlaylistTransferArchive(
            source: PlaylistTransferSource(client: client),
            playlists: exported
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("volta-playlists-\(Int(Date().timeIntervalSince1970)).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(archive).write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    static func importPlaylists(from url: URL, client: any MusicService) async throws -> PlaylistImportResult {
        let archive = try decodeArchive(from: Data(contentsOf: url))
        let targetMatchesSource = archive.source?.matches(client) ?? true
        var existingNames = Set((try await client.playlists()).map { normalizedPlaylistName($0.name) })
        var result = PlaylistImportResult()
        var resolvedTrackIDs: [String: String] = [:]
        var unmatchedTrackIDs = Set<String>()

        for playlist in archive.playlists {
            let name = playlist.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                result.playlistsFailed += 1
                continue
            }
            let normalizedName = normalizedPlaylistName(name)
            guard !existingNames.contains(normalizedName) else {
                result.playlistsSkipped += 1
                continue
            }

            let resolved = await resolveTrackIDs(
                for: playlist,
                targetMatchesSource: targetMatchesSource,
                client: client,
                resolvedTrackIDs: &resolvedTrackIDs,
                unmatchedTrackIDs: &unmatchedTrackIDs
            )
            result.tracksUnmatched += resolved.unmatched

            guard let created = try? await client.createPlaylist(name: name) else {
                result.playlistsFailed += 1
                continue
            }
            existingNames.insert(normalizedName)
            result.playlistsCreated += 1

            for songID in resolved.songIDs {
                do {
                    try await client.addToPlaylist(playlistID: created.id, songID: songID)
                    result.tracksImported += 1
                } catch {
                    result.tracksFailed += 1
                }
            }
            if let comment = playlist.comment?.trimmingCharacters(in: .whitespacesAndNewlines), !comment.isEmpty {
                try? await client.updatePlaylistComment(playlistID: created.id, comment: comment)
            }
        }
        return result
    }

    /// Public to the module so tests and future import UIs can validate a file
    /// before asking a server to create anything.
    static func decodeArchive(from data: Data) throws -> PlaylistTransferArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let archive = try? decoder.decode(PlaylistTransferArchive.self, from: data) {
            return archive
        }
        // Volta 1.3 exported a bare array of objects with name/comment/songIDs.
        let playlists = try decoder.decode([ExportedPlaylist].self, from: data)
        return PlaylistTransferArchive(version: 1, source: nil, playlists: playlists)
    }

    private static func resolveTrackIDs(
        for playlist: ExportedPlaylist,
        targetMatchesSource: Bool,
        client: any MusicService,
        resolvedTrackIDs: inout [String: String],
        unmatchedTrackIDs: inout Set<String>
    ) async -> (songIDs: [String], unmatched: Int) {
        // ID-based restore remains the right choice for files from the same
        // server and for legacy archives that have no source metadata.
        guard !targetMatchesSource, let tracks = playlist.tracks else {
            return (playlist.songIDs, 0)
        }

        var songIDs: [String] = []
        var unmatched = 0
        for track in tracks {
            if let id = resolvedTrackIDs[track.sourceID] {
                songIDs.append(id)
                continue
            }
            if unmatchedTrackIDs.contains(track.sourceID) {
                unmatched += 1
                continue
            }
            let query = PlaylistTrackMatcher.searchQuery(for: track)
            guard !query.isEmpty,
                  let search = try? await client.search(query: query, artistCount: 0, albumCount: 0, songCount: 50),
                  let match = PlaylistTrackMatcher.bestMatch(for: track, in: search.songs) else {
                unmatchedTrackIDs.insert(track.sourceID)
                unmatched += 1
                continue
            }
            resolvedTrackIDs[track.sourceID] = match.id
            songIDs.append(match.id)
        }
        return (songIDs, unmatched)
    }

    static func normalizedServerURL(_ url: String) -> String {
        if var components = URLComponents(string: url) {
            components.query = nil
            components.fragment = nil
            components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return (components.string ?? url)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .lowercased()
        }
        return url
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }

    private static func normalizedPlaylistName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }
}
