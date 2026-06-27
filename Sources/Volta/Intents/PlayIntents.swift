import AppIntents
import Foundation

// MARK: - Errors

enum VoltaIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notAuthenticated
    case notFound(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notAuthenticated:    return "Not connected to a server. Open Volta and log in first."
        case .notFound(let name): return "Couldn't find \"\(name)\" in your library."
        }
    }
}

// MARK: - Entities
//
// AppShortcut phrase parameters must be AppEntity or AppEnum (not String) per the
// App Intents metadata processor's validation. These thin wrappers store the name
// as the entity ID; EntityStringQuery lets Siri resolve names from the live library.

struct ArtistEntity: AppEntity {
    var id: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Artist"
    var displayRepresentation: DisplayRepresentation { .init(title: "\(id)") }
    static var defaultQuery = ArtistEntityQuery()
}

struct ArtistEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ArtistEntity] {
        identifiers.map { ArtistEntity(id: $0) }
    }
    func entities(matching string: String) async throws -> [ArtistEntity] {
        guard let client = IntentBridge.shared.client else { return [] }
        let (artists, _, _) = try await client.search(
            query: string, artistCount: 10, albumCount: 0, songCount: 0
        )
        return artists.map { ArtistEntity(id: $0.name) }
    }
}

struct SongEntity: AppEntity {
    var id: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Song"
    var displayRepresentation: DisplayRepresentation { .init(title: "\(id)") }
    static var defaultQuery = SongEntityQuery()
}

struct SongEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [SongEntity] {
        identifiers.map { SongEntity(id: $0) }
    }
    func entities(matching string: String) async throws -> [SongEntity] {
        guard let client = IntentBridge.shared.client else { return [] }
        let (_, _, songs) = try await client.search(
            query: string, artistCount: 0, albumCount: 0, songCount: 10
        )
        return songs.map { SongEntity(id: $0.title) }
    }
}

struct AlbumEntity: AppEntity {
    var id: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Album"
    var displayRepresentation: DisplayRepresentation { .init(title: "\(id)") }
    static var defaultQuery = AlbumEntityQuery()
}

struct AlbumEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [AlbumEntity] {
        identifiers.map { AlbumEntity(id: $0) }
    }
    func entities(matching string: String) async throws -> [AlbumEntity] {
        guard let client = IntentBridge.shared.client else { return [] }
        let (_, albums, _) = try await client.search(
            query: string, artistCount: 0, albumCount: 10, songCount: 0
        )
        return albums.map { AlbumEntity(id: $0.name) }
    }
}

struct PlaylistEntity: AppEntity {
    var id: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Playlist"
    var displayRepresentation: DisplayRepresentation { .init(title: "\(id)") }
    static var defaultQuery = PlaylistEntityQuery()
}

struct PlaylistEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [PlaylistEntity] {
        identifiers.map { PlaylistEntity(id: $0) }
    }
    func entities(matching string: String) async throws -> [PlaylistEntity] {
        guard let client = IntentBridge.shared.client else { return [] }
        let playlists = try await client.playlists()
        let filtered = string.isEmpty ? playlists : playlists.filter {
            $0.name.localizedCaseInsensitiveContains(string)
        }
        return filtered.map { PlaylistEntity(id: $0.name) }
    }
}

// MARK: - Play Artist

struct PlayArtistIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Artist"
    static var description = IntentDescription("Play music from an artist in Volta")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Artist")
    var artist: ArtistEntity

    func perform() async throws -> some ProvidesDialog {
        guard let client = IntentBridge.shared.client else {
            throw VoltaIntentError.notAuthenticated
        }
        let artistName = artist.id
        let (artists, _, _) = try await client.search(
            query: artistName, artistCount: 3, albumCount: 0, songCount: 0
        )
        guard let best = artists.first else {
            throw VoltaIntentError.notFound(artistName)
        }
        let songs = (try? await client.topSongs(artistName: best.name, count: 25)) ?? []
        if !songs.isEmpty {
            await IntentBridge.shared.playQueue(songs, source: best.name)
            return .result(dialog: "Playing \(best.name) on Volta")
        }
        if let artistDetail = try? await client.artist(id: best.id),
           let first = artistDetail.album?.first,
           let album = try? await client.album(id: first.id),
           let albumSongs = album.song, !albumSongs.isEmpty {
            await IntentBridge.shared.playQueue(albumSongs, source: best.name)
            return .result(dialog: "Playing \(best.name) on Volta")
        }
        throw VoltaIntentError.notFound(artistName)
    }
}

// MARK: - Play Song

struct PlaySongIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Song"
    static var description = IntentDescription("Play a specific song in Volta")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Song")
    var song: SongEntity

    func perform() async throws -> some ProvidesDialog {
        guard let client = IntentBridge.shared.client else {
            throw VoltaIntentError.notAuthenticated
        }
        let (_, _, songs) = try await client.search(
            query: song.id, artistCount: 0, albumCount: 0, songCount: 5
        )
        guard let found = songs.first else {
            throw VoltaIntentError.notFound(song.id)
        }
        await IntentBridge.shared.playSong(found)
        return .result(dialog: "Playing \(found.title) on Volta")
    }
}

// MARK: - Play Album

struct PlayAlbumIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Album"
    static var description = IntentDescription("Play an album in Volta")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Album")
    var album: AlbumEntity

    func perform() async throws -> some ProvidesDialog {
        guard let client = IntentBridge.shared.client else {
            throw VoltaIntentError.notAuthenticated
        }
        let (_, albums, _) = try await client.search(
            query: album.id, artistCount: 0, albumCount: 3, songCount: 0
        )
        guard let match = albums.first else {
            throw VoltaIntentError.notFound(album.id)
        }
        guard let fullAlbum = try? await client.album(id: match.id),
              let songs = fullAlbum.song, !songs.isEmpty else {
            throw VoltaIntentError.notFound(album.id)
        }
        await IntentBridge.shared.playQueue(songs, source: match.name)
        return .result(dialog: "Playing \(match.name) on Volta")
    }
}

// MARK: - Play Playlist

struct PlayPlaylistIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Playlist"
    static var description = IntentDescription("Play a playlist in Volta")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Playlist")
    var playlist: PlaylistEntity

    func perform() async throws -> some ProvidesDialog {
        guard let client = IntentBridge.shared.client else {
            throw VoltaIntentError.notAuthenticated
        }
        let playlists = try await client.playlists()
        guard let match = playlists.first(where: {
            $0.name.localizedCaseInsensitiveContains(playlist.id)
        }) else {
            throw VoltaIntentError.notFound(playlist.id)
        }
        guard let full = try? await client.playlist(id: match.id),
              let songs = full.entry, !songs.isEmpty else {
            throw VoltaIntentError.notFound(playlist.id)
        }
        await IntentBridge.shared.playQueue(songs, source: match.name)
        return .result(dialog: "Playing \(match.name) on Volta")
    }
}

// MARK: - Pause

struct PauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause"
    static var description = IntentDescription("Pause playback in Volta")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some ProvidesDialog {
        await IntentBridge.shared.pause()
        return .result(dialog: "Paused")
    }
}

// MARK: - Resume

struct ResumeIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume"
    static var description = IntentDescription("Resume playback in Volta")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some ProvidesDialog {
        await IntentBridge.shared.resume()
        return .result(dialog: "Resuming")
    }
}

// MARK: - Skip

struct SkipIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip"
    static var description = IntentDescription("Skip to next song in Volta")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some ProvidesDialog {
        await IntentBridge.shared.skip()
        return .result(dialog: "Skipped")
    }
}

// MARK: - Shortcuts provider

struct VoltaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayArtistIntent(),
            phrases: [
                "Play \(\.$artist) on \(.applicationName)",
                "Play music by \(\.$artist) on \(.applicationName)",
                "Play artist \(\.$artist) in \(.applicationName)",
                "Start \(\.$artist) on \(.applicationName)"
            ],
            shortTitle: "Play Artist",
            systemImageName: "person.fill"
        )
        AppShortcut(
            intent: PlaySongIntent(),
            phrases: [
                "Play the song \(\.$song) on \(.applicationName)",
                "Play \(\.$song) on \(.applicationName)",
                "Play song \(\.$song) in \(.applicationName)"
            ],
            shortTitle: "Play Song",
            systemImageName: "music.note"
        )
        AppShortcut(
            intent: PlayAlbumIntent(),
            phrases: [
                "Play the album \(\.$album) on \(.applicationName)",
                "Play \(\.$album) album on \(.applicationName)",
                "Play album \(\.$album) in \(.applicationName)"
            ],
            shortTitle: "Play Album",
            systemImageName: "square.stack"
        )
        AppShortcut(
            intent: PlayPlaylistIntent(),
            phrases: [
                "Play playlist \(\.$playlist) on \(.applicationName)",
                "Play the playlist \(\.$playlist) on \(.applicationName)",
                "Start playlist \(\.$playlist) in \(.applicationName)"
            ],
            shortTitle: "Play Playlist",
            systemImageName: "music.note.list"
        )
        AppShortcut(
            intent: PauseIntent(),
            phrases: [
                "Pause \(.applicationName)",
                "Pause music on \(.applicationName)"
            ],
            shortTitle: "Pause",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: ResumeIntent(),
            phrases: [
                "Resume \(.applicationName)",
                "Resume music on \(.applicationName)",
                "Continue playing on \(.applicationName)"
            ],
            shortTitle: "Resume",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: SkipIntent(),
            phrases: [
                "Skip on \(.applicationName)",
                "Next song on \(.applicationName)",
                "Skip song in \(.applicationName)"
            ],
            shortTitle: "Skip",
            systemImageName: "forward.fill"
        )
    }
}
