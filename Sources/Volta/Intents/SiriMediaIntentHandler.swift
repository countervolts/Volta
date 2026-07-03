import Foundation
import Intents

final class SiriMediaIntentHandler: NSObject, INPlayMediaIntentHandling {
    private enum MediaRequest {
        case artist(String)
        case song(String)
        case album(String)
        case playlist(String)
        case any(String)
        case resume
    }

    func confirm(intent: INPlayMediaIntent, completion: @escaping (INPlayMediaIntentResponse) -> Void) {
        Task {
            let code: INPlayMediaIntentResponseCode = await IntentBridge.shared.readyClient() == nil
                ? .failureRequiringAppLaunch
                : .ready
            completion(INPlayMediaIntentResponse(code: code, userActivity: nil))
        }
    }

    func handle(intent: INPlayMediaIntent, completion: @escaping (INPlayMediaIntentResponse) -> Void) {
        Task {
            let code = await handle(intent)
            completion(INPlayMediaIntentResponse(code: code, userActivity: nil))
        }
    }

    private func handle(_ intent: INPlayMediaIntent) async -> INPlayMediaIntentResponseCode {
        guard let client = await IntentBridge.shared.readyClient() else {
            return .failureRequiringAppLaunch
        }

        guard let request = mediaRequest(from: intent) else {
            return .failureUnknownMediaType
        }

        switch request {
        case .resume:
            await IntentBridge.shared.resume()
            return .success
        case .artist(let query):
            return await playArtist(query, client: client)
        case .song(let query):
            return await playSong(query, client: client)
        case .album(let query):
            return await playAlbum(query, client: client)
        case .playlist(let query):
            return await playPlaylist(query, client: client)
        case .any(let query):
            return await playBestMatch(query, client: client)
        }
    }

    private func mediaRequest(from intent: INPlayMediaIntent) -> MediaRequest? {
        if intent.resumePlayback == true {
            return .resume
        }

        let items = (intent.mediaItems ?? []) + [intent.mediaContainer].compactMap { $0 }
        for item in items {
            guard let title = item.title?.nonBlank ?? item.identifier?.nonBlank else { continue }
            switch item.type {
            case .artist:
                return .artist(title)
            case .album:
                return .album(title)
            case .playlist:
                return .playlist(title)
            case .song, .music:
                return .song(title)
            default:
                return .any(title)
            }
        }

        guard let search = intent.mediaSearch else { return nil }
        if let artist = search.artistName?.nonBlank {
            return .artist(artist)
        }
        if let album = search.albumName?.nonBlank {
            return .album(album)
        }
        if let name = search.mediaName?.nonBlank {
            switch search.mediaType {
            case .artist:
                return .artist(name)
            case .album:
                return .album(name)
            case .playlist:
                return .playlist(name)
            case .song:
                return .song(name)
            default:
                return .any(name)
            }
        }
        if let genre = search.genreNames?.first?.nonBlank {
            return .any(genre)
        }
        return nil
    }

    private func playArtist(_ query: String, client: any MusicService) async -> INPlayMediaIntentResponseCode {
        let artists = ((try? await client.search(query: query, artistCount: 5, albumCount: 0, songCount: 0).artists) ?? [])
        guard let artist = bestMatch(query, in: artists, name: \.name) else {
            return await playBestMatch(query, client: client)
        }

        let songs = (try? await client.topSongs(artistName: artist.name, count: 25)) ?? []
        if !songs.isEmpty {
            await IntentBridge.shared.playQueue(songs, source: artist.name)
            return .success
        }

        if let full = try? await client.artist(id: artist.id),
           let first = full.album?.first,
           let album = try? await client.album(id: first.id),
           let albumSongs = album.song, !albumSongs.isEmpty {
            await IntentBridge.shared.playQueue(albumSongs, source: artist.name)
            return .success
        }
        return .failureNoUnplayedContent
    }

    private func playSong(_ query: String, client: any MusicService) async -> INPlayMediaIntentResponseCode {
        let songs = ((try? await client.search(query: query, artistCount: 0, albumCount: 0, songCount: 8).songs) ?? [])
        guard let song = bestMatch(query, in: songs, name: \.title),
              let full = try? await client.song(id: song.id) else {
            return await playBestMatch(query, client: client)
        }
        await IntentBridge.shared.playSong(full)
        return .success
    }

    private func playAlbum(_ query: String, client: any MusicService) async -> INPlayMediaIntentResponseCode {
        let albums = ((try? await client.search(query: query, artistCount: 0, albumCount: 8, songCount: 0).albums) ?? [])
        guard let album = bestMatch(query, in: albums, name: \.name),
              let full = try? await client.album(id: album.id),
              let songs = full.song, !songs.isEmpty else {
            return await playBestMatch(query, client: client)
        }
        await IntentBridge.shared.playQueue(songs, source: full.name)
        return .success
    }

    private func playPlaylist(_ query: String, client: any MusicService) async -> INPlayMediaIntentResponseCode {
        let playlists = (try? await client.playlists()) ?? []
        guard let playlist = bestMatch(query, in: playlists, name: \.name),
              let full = try? await client.playlist(id: playlist.id),
              let songs = full.entry, !songs.isEmpty else {
            return .failureNoUnplayedContent
        }
        await IntentBridge.shared.playQueue(songs, source: full.name)
        return .success
    }

    private func playBestMatch(_ query: String, client: any MusicService) async -> INPlayMediaIntentResponseCode {
        guard let results = try? await client.search(query: query, artistCount: 5, albumCount: 5, songCount: 5) else {
            return .failure
        }

        if let artist = bestMatch(query, in: results.artists, name: \.name) {
            return await playArtist(artist.name, client: client)
        }
        if let album = bestMatch(query, in: results.albums, name: \.name),
           let full = try? await client.album(id: album.id),
           let songs = full.song, !songs.isEmpty {
            await IntentBridge.shared.playQueue(songs, source: full.name)
            return .success
        }
        if let song = bestMatch(query, in: results.songs, name: \.title),
           let full = try? await client.song(id: song.id) {
            await IntentBridge.shared.playSong(full)
            return .success
        }
        return .failureNoUnplayedContent
    }

    private func bestMatch<T>(_ query: String, in values: [T], name: (T) -> String) -> T? {
        let folded = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return values.first {
            name($0).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == folded
        } ?? values.first
    }
}

