import Foundation

extension SubsonicClient {

    func ping() async throws {
        _ = try await request("ping")
    }

    private func albumList(type: String, size: Int, offset: Int = 0) async throws -> [Album] {
        let body = try await request("getAlbumList2", query: [
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "size", value: String(size)),
            URLQueryItem(name: "offset", value: String(offset)),
        ])
        return body.albumList2?.album ?? []
    }

    func randomAlbums(size: Int) async throws -> [Album] {
        try await albumList(type: "random", size: size)
    }

    func newestAlbums(size: Int) async throws -> [Album] {
        try await albumList(type: "newest", size: size)
    }

    func recentlyPlayedAlbums(size: Int) async throws -> [Album] {
        try await albumList(type: "recent", size: size)
    }

    func frequentAlbums(size: Int) async throws -> [Album] {
        try await albumList(type: "frequent", size: size)
    }

    func allAlbums(size: Int = 500, offset: Int = 0) async throws -> [Album] {
        try await albumList(type: "alphabeticalByName", size: size, offset: offset)
    }

    func playlists() async throws -> [Playlist] {
        let body = try await request("getPlaylists")
        return body.playlists?.playlist ?? []
    }

    func playlist(id: String) async throws -> Playlist? {
        let body = try await request("getPlaylist", query: [URLQueryItem(name: "id", value: id)])
        return body.playlist
    }

    func createPlaylist(name: String) async throws -> Playlist? {
        let body = try await request("createPlaylist", query: [URLQueryItem(name: "name", value: name)])
        return body.playlist
    }

    func addToPlaylist(playlistID: String, songID: String) async throws {
        _ = try await request("updatePlaylist", query: [
            URLQueryItem(name: "playlistId", value: playlistID),
            URLQueryItem(name: "songIdToAdd", value: songID),
        ])
    }

    func artist(id: String) async throws -> Artist? {
        let body = try await request("getArtist", query: [URLQueryItem(name: "id", value: id)])
        return body.artist
    }

    func artistInfo(id: String) async throws -> ArtistInfo? {
        let body = try await request("getArtistInfo2", query: [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "count", value: "20"),
        ])
        return body.artistInfo2
    }

    func artists() async throws -> [Artist] {
        let body = try await request("getArtists")
        let indices = body.artists?.index ?? []
        return indices.flatMap { $0.artist ?? [] }
    }

    func album(id: String) async throws -> Album? {
        let body = try await request("getAlbum", query: [URLQueryItem(name: "id", value: id)])
        return body.album
    }

    func albums(ids: [String]) async throws -> [Album] {
        try await withThrowingTaskGroup(of: Album?.self) { group in
            for id in ids {
                group.addTask { try? await self.album(id: id) }
            }
            var result: [Album] = []
            for try await album in group {
                if let album { result.append(album) }
            }
            return result
        }
    }

    func star(id: String) async throws {
        _ = try await request("star", query: [URLQueryItem(name: "id", value: id)])
    }

    func unstar(id: String) async throws {
        _ = try await request("unstar", query: [URLQueryItem(name: "id", value: id)])
    }

    func search(query: String, artistCount: Int = 5, albumCount: Int = 5, songCount: Int = 10) async throws -> (artists: [Artist], albums: [Album], songs: [Song]) {
        let body = try await request("search3", query: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "artistCount", value: String(artistCount)),
            URLQueryItem(name: "albumCount", value: String(albumCount)),
            URLQueryItem(name: "songCount", value: String(songCount)),
        ])
        let r = body.searchResult3
        return (r?.artist ?? [], r?.album ?? [], r?.song ?? [])
    }

    func randomSongs(size: Int = 500) async throws -> [Song] {
        let body = try await request("getRandomSongs", query: [
            URLQueryItem(name: "size", value: String(size))
        ])
        return body.randomSongs?.song ?? []
    }

    func deletePlaylist(id: String) async throws {
        _ = try await request("deletePlaylist", query: [URLQueryItem(name: "id", value: id)])
    }

    func removeFromPlaylist(playlistID: String, index: Int) async throws {
        _ = try await request("updatePlaylist", query: [
            URLQueryItem(name: "playlistId", value: playlistID),
            URLQueryItem(name: "songIndexToRemove", value: String(index)),
        ])
    }

    func renamePlaylist(playlistID: String, name: String) async throws {
        _ = try await request("updatePlaylist", query: [
            URLQueryItem(name: "playlistId", value: playlistID),
            URLQueryItem(name: "name", value: name),
        ])
    }

    func getMusicFolderStats() async throws -> (artists: Int, albums: Int, songs: Int) {
        let body = try await request("getArtists")
        let indices = body.artists?.index ?? []
        let artistCount = indices.flatMap { $0.artist ?? [] }.count
        let albumBody = try await request("getAlbumList2", query: [
            URLQueryItem(name: "type", value: "alphabeticalByName"),
            URLQueryItem(name: "size", value: "1"),
            URLQueryItem(name: "offset", value: "0"),
        ])
        // We can't get exact counts without a stats endpoint; return what we can
        return (artistCount, albumBody.albumList2?.album?.count ?? 0, 0)
    }

    // OpenSubsonic synced lyrics extension
    func topSongs(artistName: String, count: Int = 10) async throws -> [Song] {
        let body = try await request("getTopSongs", query: [
            URLQueryItem(name: "artist", value: artistName),
            URLQueryItem(name: "count", value: String(count)),
        ])
        return body.topSongs?.song ?? []
    }

    func lyricsBySongId(id: String) async throws -> LyricsList? {
        let body = try await request("getLyricsBySongId", query: [URLQueryItem(name: "id", value: id)])
        return body.lyricsList
    }

    // legacy plain lyrics
    func lyrics(artist: String, title: String) async throws -> String? {
        let body = try await request("getLyrics", query: [
            URLQueryItem(name: "artist", value: artist),
            URLQueryItem(name: "title", value: title),
        ])
        return body.lyrics?.value
    }
}
