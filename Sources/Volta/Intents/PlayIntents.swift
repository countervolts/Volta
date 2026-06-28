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

// MARK: - Play Artist

struct PlayArtistIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Artist"
    static var description = IntentDescription("Play music from an artist in Volta")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Artist Name")
    var artistName: String

    func perform() async throws -> some ProvidesDialog {
        guard let client = IntentBridge.shared.client else {
            throw VoltaIntentError.notAuthenticated
        }
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
        if let artist = try? await client.artist(id: best.id),
           let first = artist.album?.first,
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

    @Parameter(title: "Song Name")
    var songName: String

    func perform() async throws -> some ProvidesDialog {
        guard let client = IntentBridge.shared.client else {
            throw VoltaIntentError.notAuthenticated
        }
        let (_, _, songs) = try await client.search(
            query: songName, artistCount: 0, albumCount: 0, songCount: 5
        )
        guard let song = songs.first else {
            throw VoltaIntentError.notFound(songName)
        }
        await IntentBridge.shared.playSong(song)
        return .result(dialog: "Playing \(song.title) on Volta")
    }
}

// MARK: - Play Album

struct PlayAlbumIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Album"
    static var description = IntentDescription("Play an album in Volta")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Album Name")
    var albumName: String

    func perform() async throws -> some ProvidesDialog {
        guard let client = IntentBridge.shared.client else {
            throw VoltaIntentError.notAuthenticated
        }
        let (_, albums, _) = try await client.search(
            query: albumName, artistCount: 0, albumCount: 3, songCount: 0
        )
        guard let match = albums.first else {
            throw VoltaIntentError.notFound(albumName)
        }
        guard let album = try? await client.album(id: match.id),
              let songs = album.song, !songs.isEmpty else {
            throw VoltaIntentError.notFound(albumName)
        }
        let title = match.name
        await IntentBridge.shared.playQueue(songs, source: title)
        return .result(dialog: "Playing \(title) on Volta")
    }
}

// MARK: - Play Playlist

struct PlayPlaylistIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Playlist"
    static var description = IntentDescription("Play a playlist in Volta")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Playlist Name")
    var playlistName: String

    func perform() async throws -> some ProvidesDialog {
        guard let client = IntentBridge.shared.client else {
            throw VoltaIntentError.notAuthenticated
        }
        let playlists = try await client.playlists()
        guard let match = playlists.first(where: {
            $0.name.localizedCaseInsensitiveContains(playlistName)
        }) else {
            throw VoltaIntentError.notFound(playlistName)
        }
        guard let full = try? await client.playlist(id: match.id),
              let songs = full.entry, !songs.isEmpty else {
            throw VoltaIntentError.notFound(playlistName)
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
                "Play \(\.$artistName) on \(.applicationName)",
                "Play music by \(\.$artistName) on \(.applicationName)",
                "Play artist \(\.$artistName) in \(.applicationName)",
                "Play \(\.$artistName) in \(.applicationName)",
                "Start \(\.$artistName) on \(.applicationName)"
            ],
            shortTitle: "Play Artist",
            systemImageName: "person.fill"
        )
        AppShortcut(
            intent: PlaySongIntent(),
            phrases: [
                "Play the song \(\.$songName) on \(.applicationName)",
                "Play \(\.$songName) on \(.applicationName)",
                "Play song \(\.$songName) in \(.applicationName)"
            ],
            shortTitle: "Play Song",
            systemImageName: "music.note"
        )
        AppShortcut(
            intent: PlayAlbumIntent(),
            phrases: [
                "Play the album \(\.$albumName) on \(.applicationName)",
                "Play \(\.$albumName) album on \(.applicationName)",
                "Play album \(\.$albumName) in \(.applicationName)"
            ],
            shortTitle: "Play Album",
            systemImageName: "square.stack"
        )
        AppShortcut(
            intent: PlayPlaylistIntent(),
            phrases: [
                "Play playlist \(\.$playlistName) on \(.applicationName)",
                "Play the playlist \(\.$playlistName) on \(.applicationName)",
                "Start playlist \(\.$playlistName) in \(.applicationName)"
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
