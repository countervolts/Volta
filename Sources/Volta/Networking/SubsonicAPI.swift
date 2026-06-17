import Foundation

struct ServerHealthSnapshot: Sendable {
    let status: String
    let apiVersion: String?
    let serverType: String?
    let latencyMS: Int
    let checkedAt: Date
}

extension SubsonicClient {

    func ping() async throws {
        _ = try await request("ping")
    }

    func serverHealth() async throws -> ServerHealthSnapshot {
        let start = Date()
        let body = try await request("ping")
        let latency = max(0, Int(Date().timeIntervalSince(start) * 1000))
        return ServerHealthSnapshot(
            status: body.status ?? "unknown",
            apiVersion: body.version,
            serverType: body.type,
            latencyMS: latency,
            checkedAt: Date()
        )
    }

    // MARK: - Folder / directory browsing

    func musicFolders() async throws -> [MusicFolder] {
        let body = try await request("getMusicFolders")
        return body.musicFolders?.musicFolder ?? []
    }

    // Root directories for one folder, or all folders when nil.
    func indexes(musicFolderId: String?) async throws -> [BrowseEntry] {
        var query: [URLQueryItem] = []
        if let musicFolderId, !musicFolderId.isEmpty {
            query.append(URLQueryItem(name: "musicFolderId", value: musicFolderId))
        }
        let body = try await request("getIndexes", query: query)
        let dirs  = (body.indexes?.index ?? []).flatMap { $0.artist ?? [] }.map { $0.asBrowseEntry }
        let songs = (body.indexes?.child ?? []).map { $0.asBrowseEntry }
        return dirs + songs
    }

    // Directory contents: folders first, then songs.
    func musicDirectory(id: String) async throws -> [BrowseEntry] {
        let body = try await request("getMusicDirectory", query: [URLQueryItem(name: "id", value: id)])
        let children = body.directory?.child ?? []
        let dirs  = children.filter { $0.isDir }.map { $0.asBrowseEntry }
        let songs = children.filter { !$0.isDir }.map { $0.asBrowseEntry }
        return dirs + songs
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

    func allAlbums(size: Int, offset: Int) async throws -> [Album] {
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

    // Create a playlist with an ordered song seed.
    func createPlaylist(name: String, songIDs: [String]) async throws -> Playlist? {
        var query = [URLQueryItem(name: "name", value: name)]
        query.append(contentsOf: songIDs.map { URLQueryItem(name: "songId", value: $0) })
        let body = try await request("createPlaylist", query: query)
        if let pl = body.playlist { return pl }
        // Some servers return no body; find the new playlist by name.
        return try? await playlists().first { $0.name == name }
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

    func song(id: String) async throws -> Song? {
        let body = try await request("getSong", query: [URLQueryItem(name: "id", value: id)])
        return body.song
    }

    func songsForArtist(id: String) async throws -> [Song] {
        guard let loadedArtist = try await self.artist(id: id) else { return [] }
        let albums = (loadedArtist.album ?? []).sorted {
            let y0 = $0.year ?? Int.max
            let y1 = $1.year ?? Int.max
            if y0 != y1 { return y0 < y1 }
            return ($0.createdDate ?? .distantPast) < ($1.createdDate ?? .distantPast)
        }
        let fullAlbums = try await self.albums(ids: albums.map(\.id))
        let byID = Dictionary(uniqueKeysWithValues: fullAlbums.map { ($0.id, $0) })
        return albums.flatMap { album in
            (byID[album.id]?.song ?? album.song ?? []).sorted {
                let d0 = $0.discNumber ?? 1
                let d1 = $1.discNumber ?? 1
                if d0 != d1 { return d0 < d1 }
                return ($0.track ?? 0) < ($1.track ?? 0)
            }
        }
    }

    func albums(ids: [String]) async throws -> [Album] {
        let albums = await DeveloperExperiments.runConcurrently(ids, defaultMaxConcurrent: ids.count) { id in
            try? await self.album(id: id)
        }
        return albums.compactMap { $0 }
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

    func songsByGenre(_ genre: String, count: Int, offset: Int) async throws -> [Song] {
        let body = try await request("getSongsByGenre", query: [
            URLQueryItem(name: "genre", value: genre),
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "offset", value: String(offset)),
        ])
        return body.songsByGenre?.song ?? []
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

    func updatePlaylistComment(playlistID: String, comment: String) async throws {
        _ = try await request("updatePlaylist", query: [
            URLQueryItem(name: "playlistId", value: playlistID),
            URLQueryItem(name: "comment", value: comment),
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
        // No stats endpoint here; return the cheap counts.
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

    // Sharing is available when getShares succeeds.
    func sharingAvailable() async -> Bool {
        do { _ = try await request("getShares"); return true }
        catch { return false }
    }

    // Public share link, when the server allows it.
    func createShare(id: String) async throws -> URL? {
        let body = try await request("createShare", query: [URLQueryItem(name: "id", value: id)])
        guard let urlString = body.shares?.share?.first?.url,
              let url = URL(string: urlString) else { return nil }
        return url
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
