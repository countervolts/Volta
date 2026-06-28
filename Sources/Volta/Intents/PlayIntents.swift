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

// MARK: - Library entities

struct ArtistEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Artist")
    static var defaultQuery = ArtistEntityQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ArtistEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ArtistEntity] {
        guard let client = IntentBridge.shared.client else { return [] }
        var matches: [ArtistEntity] = []
        for id in identifiers where !id.isEmpty {
            if let artist = try? await client.artist(id: id) {
                matches.append(ArtistEntity(id: artist.id, name: artist.name))
            }
        }
        return matches
    }

    func entities(matching string: String) async throws -> [ArtistEntity] {
        guard let client = IntentBridge.shared.client else { return [] }
        let (artists, _, _) = try await client.search(
            query: string, artistCount: 8, albumCount: 0, songCount: 0
        )
        return artists.map { ArtistEntity(id: $0.id, name: $0.name) }
    }
}

struct SongEntity: AppEntity {
    let id: String
    let name: String
    let subtitle: String

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Song")
    static var defaultQuery = SongEntityQuery()
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(subtitle)")
    }
}

struct SongEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [SongEntity] {
        guard let client = IntentBridge.shared.client else { return [] }
        var matches: [SongEntity] = []
        for id in identifiers where !id.isEmpty {
            if let song = try? await client.song(id: id) {
                matches.append(SongEntity(id: song.id, name: song.title, subtitle: song.artist ?? ""))
            }
        }
        return matches
    }

    func entities(matching string: String) async throws -> [SongEntity] {
        guard let client = IntentBridge.shared.client else { return [] }
        let (_, _, songs) = try await client.search(
            query: string, artistCount: 0, albumCount: 0, songCount: 8
        )
        return songs.map { SongEntity(id: $0.id, name: $0.title, subtitle: $0.artist ?? "") }
    }
}

struct AlbumEntity: AppEntity {
    let id: String
    let name: String
    let subtitle: String

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Album")
    static var defaultQuery = AlbumEntityQuery()
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(subtitle)")
    }
}

struct AlbumEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [AlbumEntity] {
        guard let client = IntentBridge.shared.client else { return [] }
        var matches: [AlbumEntity] = []
        for id in identifiers where !id.isEmpty {
            if let album = try? await client.album(id: id) {
                matches.append(AlbumEntity(id: album.id, name: album.name, subtitle: album.artist ?? ""))
            }
        }
        return matches
    }

    func entities(matching string: String) async throws -> [AlbumEntity] {
        guard let client = IntentBridge.shared.client else { return [] }
        let (_, albums, _) = try await client.search(
            query: string, artistCount: 0, albumCount: 8, songCount: 0
        )
        return albums.map { AlbumEntity(id: $0.id, name: $0.name, subtitle: $0.artist ?? "") }
    }
}

struct PlaylistEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Playlist")
    static var defaultQuery = PlaylistEntityQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct PlaylistEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [PlaylistEntity] {
        guard let client = IntentBridge.shared.client else { return [] }
        let ids = Set(identifiers)
        let all = (try? await client.playlists()) ?? []
        return all.filter { ids.contains($0.id) }.map { PlaylistEntity(id: $0.id, name: $0.name) }
    }

    func entities(matching string: String) async throws -> [PlaylistEntity] {
        guard let client = IntentBridge.shared.client else { return [] }
        let all = (try? await client.playlists()) ?? []
        return all
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map { PlaylistEntity(id: $0.id, name: $0.name) }
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
        let songs = (try? await client.topSongs(artistName: artist.name, count: 25)) ?? []
        if !songs.isEmpty {
            await IntentBridge.shared.playQueue(songs, source: artist.name)
            return .result(dialog: "Playing \(artist.name) on Volta")
        }
        if let full = try? await client.artist(id: artist.id),
           let first = full.album?.first,
           let album = try? await client.album(id: first.id),
           let albumSongs = album.song, !albumSongs.isEmpty {
            await IntentBridge.shared.playQueue(albumSongs, source: artist.name)
            return .result(dialog: "Playing \(artist.name) on Volta")
        }
        throw VoltaIntentError.notFound(artist.name)
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
        guard let full = try? await client.song(id: song.id) else {
            throw VoltaIntentError.notFound(song.name)
        }
        await IntentBridge.shared.playSong(full)
        return .result(dialog: "Playing \(full.title) on Volta")
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
        guard let full = try? await client.album(id: album.id),
              let songs = full.song, !songs.isEmpty else {
            throw VoltaIntentError.notFound(album.name)
        }
        await IntentBridge.shared.playQueue(songs, source: full.name)
        return .result(dialog: "Playing \(full.name) on Volta")
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
        guard let full = try? await client.playlist(id: playlist.id),
              let songs = full.entry, !songs.isEmpty else {
            throw VoltaIntentError.notFound(playlist.name)
        }
        await IntentBridge.shared.playQueue(songs, source: full.name)
        return .result(dialog: "Playing \(full.name) on Volta")
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
                "Play \(\.$artist) in \(.applicationName)",
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
