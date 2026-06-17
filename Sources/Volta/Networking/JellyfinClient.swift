import Foundation

// Jellyfin/Emby adapter. Both map into Volta's Subsonic-shaped models.
// `coverArt` stores the item id for its Primary image.
struct JellyfinClient: MusicService {
    enum Flavor: Sendable {
        case jellyfin
        case emby
    }

    let config: SubsonicConfig
    let flavor: Flavor
    let userId: String
    let token: String
    let deviceId: String
    let session: URLSession

    var backendKind: MusicBackendKind { flavor == .jellyfin ? .jellyfin : .emby }

    var capabilities: MusicServiceCapabilities {
        // No public sharing. BPM is not in BaseItemDto.
        // Synced lyrics are Jellyfin 10.9+, with a harmless Emby attempt.
        var caps: MusicServiceCapabilities = [
            .folderBrowsing, .favorites, .topSongsByArtist, .artistBiography,
            .songsByGenre, .recentlyPlayed, .playCounts, .replayGain,
        ]
        if flavor == .jellyfin { caps.insert(.syncedLyrics) }
        return caps
    }

    static let clientName = "Volta"
    static let clientVersion = "1.0"

    // MARK: - Connection / auth

    // Username/password -> access token + user id.
    static func connect(config: SubsonicConfig, flavor: Flavor, session: URLSession = .shared) async throws -> JellyfinClient {
        let deviceId = Self.deviceID()
        var stub = JellyfinClient(config: config, flavor: flavor, userId: "", token: "",
                                  deviceId: deviceId, session: session)

        guard let url = stub.url("/Users/AuthenticateByName") else {
            throw SubsonicError.invalidResponse
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(stub.authHeaderValue(token: nil), forHTTPHeaderField: stub.authHeaderField)
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "Username": config.username,
            "Pw": config.password,
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw SubsonicError.serverUnreachable
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if http.statusCode == 401 { throw SubsonicError.invalidCredentials }
            throw SubsonicError.server(code: http.statusCode, message: "Authentication failed")
        }
        guard let auth = try? JSONDecoder().decode(JFAuthResponse.self, from: data),
              let id = auth.User?.Id, let accessToken = auth.AccessToken else {
            throw SubsonicError.invalidCredentials
        }
        stub = JellyfinClient(config: config, flavor: flavor, userId: id, token: accessToken,
                              deviceId: deviceId, session: session)
        return stub
    }

    // Stable install id; do not create a new device every launch.
    private static func deviceID() -> String {
        let key = "jellyfinDeviceId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    private var authHeaderField: String {
        flavor == .emby ? "X-Emby-Authorization" : "Authorization"
    }

    private func authHeaderValue(token: String?) -> String {
        var parts = [
            "Client=\"\(Self.clientName)\"",
            "Device=\"iPhone\"",
            "DeviceId=\"\(deviceId)\"",
            "Version=\"\(Self.clientVersion)\"",
        ]
        if let token { parts.append("Token=\"\(token)\"") }
        return "MediaBrowser " + parts.joined(separator: ", ")
    }

    // MARK: - URL + request plumbing

    func url(_ path: String, query: [URLQueryItem] = []) -> URL? {
        guard var comps = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false) else { return nil }
        var base = comps.path
        if base.hasSuffix("/") { base.removeLast() }
        comps.path = base + path
        if !query.isEmpty { comps.queryItems = query }
        return comps.url
    }

    private func request(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Any? = nil) async throws -> Data {
        try await DeveloperSimulation.prepareRequest(endpoint: path)
        guard let url = url(path, query: query) else { throw SubsonicError.invalidResponse }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue(authHeaderValue(token: token), forHTTPHeaderField: authHeaderField)
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        AppLogger.shared.log("> [JF] \(method) \(path)", category: .networking)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw SubsonicError.serverUnreachable
        }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 { throw SubsonicError.invalidCredentials }
            if !(200...299).contains(http.statusCode) {
                throw SubsonicError.server(code: http.statusCode, message: "HTTP \(http.statusCode)")
            }
        }
        return data
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type) async throws -> T {
        let data = try await request("GET", path, query: query)
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            throw SubsonicError.invalidResponse
        }
        return decoded
    }

    // Common Items query fields so one decode covers albums/songs/artists/playlists.
    private static let itemFields =
        "Genres,DateCreated,MediaSources,Path,Overview,ChildCount,ProductionYear,ParentIndexNumber,IndexNumber"

    private func itemsQuery(_ extra: [URLQueryItem]) -> [URLQueryItem] {
        [
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: Self.itemFields),
            URLQueryItem(name: "ImageTypeLimit", value: "1"),
            URLQueryItem(name: "EnableImageTypes", value: "Primary"),
        ] + extra
    }

    // MARK: - Health

    func ping() async throws {
        // a cheap authenticated call validates the token end to end.
        _ = try await request("GET", "/System/Info")
    }

    func serverHealth() async throws -> ServerHealthSnapshot {
        let start = Date()
        let info = try? await get("/System/Info/Public", as: JFSystemInfo.self)
        let latency = max(0, Int(Date().timeIntervalSince(start) * 1000))
        return ServerHealthSnapshot(
            status: "ok",
            apiVersion: info?.Version,
            serverType: info?.ProductName ?? (flavor == .emby ? "Emby Server" : "Jellyfin Server"),
            latencyMS: latency,
            checkedAt: Date()
        )
    }

    // MARK: - Albums

    private func albumList(sortBy: String, order: String, size: Int, offset: Int = 0, filters: String? = nil) async throws -> [Album] {
        var q: [URLQueryItem] = [
            URLQueryItem(name: "IncludeItemTypes", value: "MusicAlbum"),
            URLQueryItem(name: "SortBy", value: sortBy),
            URLQueryItem(name: "SortOrder", value: order),
            URLQueryItem(name: "Limit", value: String(size)),
            URLQueryItem(name: "StartIndex", value: String(offset)),
        ]
        if let filters { q.append(URLQueryItem(name: "Filters", value: filters)) }
        let res = try await get("/Users/\(userId)/Items", query: itemsQuery(q), as: JFItemsResponse.self)
        return (res.Items ?? []).map { $0.asAlbum }
    }

    func randomAlbums(size: Int) async throws -> [Album] {
        try await albumList(sortBy: "Random", order: "Ascending", size: size)
    }
    func newestAlbums(size: Int) async throws -> [Album] {
        try await albumList(sortBy: "DateCreated,SortName", order: "Descending", size: size)
    }
    func recentlyPlayedAlbums(size: Int) async throws -> [Album] {
        try await albumList(sortBy: "DatePlayed,SortName", order: "Descending", size: size, filters: "IsPlayed")
    }
    func frequentAlbums(size: Int) async throws -> [Album] {
        try await albumList(sortBy: "PlayCount,SortName", order: "Descending", size: size, filters: "IsPlayed")
    }
    func allAlbums(size: Int, offset: Int) async throws -> [Album] {
        try await albumList(sortBy: "SortName", order: "Ascending", size: size, offset: offset)
    }

    func album(id: String) async throws -> Album? {
        async let metaTask = try? get("/Users/\(userId)/Items/\(id)", as: JFItem.self)
        async let tracksTask = try? get("/Users/\(userId)/Items", query: itemsQuery([
            URLQueryItem(name: "ParentId", value: id),
            URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
            URLQueryItem(name: "SortBy", value: "ParentIndexNumber,IndexNumber,SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
        ]), as: JFItemsResponse.self)
        guard let meta = await metaTask else { return nil }
        let songs = (await tracksTask)?.Items?.map { $0.asSong } ?? []
        return meta.asAlbum(withSongs: songs)
    }

    func albums(ids: [String]) async throws -> [Album] {
        let albums = await DeveloperExperiments.runConcurrently(ids, defaultMaxConcurrent: ids.count) { id in
            try? await self.album(id: id)
        }
        return albums.compactMap { $0 }
    }

    // MARK: - Artists

    func artists() async throws -> [Artist] {
        let res = try await get("/Artists/AlbumArtists", query: [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "Fields", value: Self.itemFields),
            URLQueryItem(name: "ImageTypeLimit", value: "1"),
            URLQueryItem(name: "EnableImageTypes", value: "Primary"),
        ], as: JFItemsResponse.self)
        return (res.Items ?? []).map { $0.asArtist }
    }

    func artist(id: String) async throws -> Artist? {
        async let metaTask = try? get("/Users/\(userId)/Items/\(id)", as: JFItem.self)
        async let albumsTask = try? get("/Users/\(userId)/Items", query: itemsQuery([
            URLQueryItem(name: "AlbumArtistIds", value: id),
            URLQueryItem(name: "IncludeItemTypes", value: "MusicAlbum"),
            URLQueryItem(name: "SortBy", value: "ProductionYear,SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
        ]), as: JFItemsResponse.self)
        guard let meta = await metaTask else { return nil }
        let albums = (await albumsTask)?.Items?.map { $0.asAlbum } ?? []
        return meta.asArtist(withAlbums: albums)
    }

    func artistInfo(id: String) async throws -> ArtistInfo? {
        async let metaTask = try? get("/Users/\(userId)/Items/\(id)", as: JFItem.self)
        async let similarTask = try? get("/Artists/\(id)/Similar", query: [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "Limit", value: "20"),
        ], as: JFItemsResponse.self)
        let meta = await metaTask
        let similar = (await similarTask)?.Items?.map { $0.asArtist } ?? []
        let image = meta.flatMap { coverArtURL(id: $0.Id, size: 600)?.absoluteString }
        return ArtistInfo(
            biography: meta?.Overview,
            similarArtist: similar,
            smallImageUrl: nil,
            mediumImageUrl: nil,
            largeImageUrl: image
        )
    }

    func songsForArtist(id: String) async throws -> [Song] {
        let res = try await get("/Users/\(userId)/Items", query: itemsQuery([
            URLQueryItem(name: "ArtistIds", value: id),
            URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
            URLQueryItem(name: "SortBy", value: "Album,ParentIndexNumber,IndexNumber,SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
        ]), as: JFItemsResponse.self)
        return (res.Items ?? []).map { $0.asSong }
    }

    // No topSongs endpoint; resolve the artist and sort by play count.
    func topSongs(artistName: String, count: Int) async throws -> [Song] {
        let hits = try await get("/Users/\(userId)/Items", query: itemsQuery([
            URLQueryItem(name: "IncludeItemTypes", value: "MusicArtist"),
            URLQueryItem(name: "SearchTerm", value: artistName),
            URLQueryItem(name: "Limit", value: "1"),
        ]), as: JFItemsResponse.self)
        guard let artistId = hits.Items?.first?.Id else { return [] }
        let res = try await get("/Users/\(userId)/Items", query: itemsQuery([
            URLQueryItem(name: "ArtistIds", value: artistId),
            URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
            URLQueryItem(name: "SortBy", value: "PlayCount,SortName"),
            URLQueryItem(name: "SortOrder", value: "Descending"),
            URLQueryItem(name: "Limit", value: String(count)),
        ]), as: JFItemsResponse.self)
        return (res.Items ?? []).map { $0.asSong }
    }

    // MARK: - Songs

    func song(id: String) async throws -> Song? {
        (try? await get("/Users/\(userId)/Items/\(id)", as: JFItem.self))?.asSong
    }

    func randomSongs(size: Int) async throws -> [Song] {
        let res = try await get("/Users/\(userId)/Items", query: itemsQuery([
            URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
            URLQueryItem(name: "SortBy", value: "Random"),
            URLQueryItem(name: "Limit", value: String(size)),
        ]), as: JFItemsResponse.self)
        return (res.Items ?? []).map { $0.asSong }
    }

    func songsByGenre(_ genre: String, count: Int, offset: Int) async throws -> [Song] {
        let res = try await get("/Users/\(userId)/Items", query: itemsQuery([
            URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
            URLQueryItem(name: "Genres", value: genre),
            URLQueryItem(name: "SortBy", value: "Random"),
            URLQueryItem(name: "Limit", value: String(count)),
            URLQueryItem(name: "StartIndex", value: String(offset)),
        ]), as: JFItemsResponse.self)
        return (res.Items ?? []).map { $0.asSong }
    }

    // MARK: - Search

    func search(query: String, artistCount: Int, albumCount: Int, songCount: Int) async throws -> (artists: [Artist], albums: [Album], songs: [Song]) {
        @Sendable func find(_ types: String, _ limit: Int) async -> [JFItem] {
            guard limit > 0 else { return [] }
            let res = try? await get("/Users/\(userId)/Items", query: itemsQuery([
                URLQueryItem(name: "IncludeItemTypes", value: types),
                URLQueryItem(name: "SearchTerm", value: query),
                URLQueryItem(name: "Limit", value: String(limit)),
            ]), as: JFItemsResponse.self)
            return res?.Items ?? []
        }
        async let artistsTask = find("MusicArtist", artistCount)
        async let albumsTask = find("MusicAlbum", albumCount)
        async let songsTask = find("Audio", songCount)
        return (await artistsTask.map { $0.asArtist },
                await albumsTask.map { $0.asAlbum },
                await songsTask.map { $0.asSong })
    }

    // MARK: - Playlists

    func playlists() async throws -> [Playlist] {
        let res = try await get("/Users/\(userId)/Items", query: itemsQuery([
            URLQueryItem(name: "IncludeItemTypes", value: "Playlist"),
            URLQueryItem(name: "SortBy", value: "SortName"),
        ]), as: JFItemsResponse.self)
        return (res.Items ?? []).map { $0.asPlaylist }
    }

    func playlist(id: String) async throws -> Playlist? {
        async let metaTask = try? get("/Users/\(userId)/Items/\(id)", as: JFItem.self)
        async let itemsTask = try? get("/Playlists/\(id)/Items", query: [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "Fields", value: Self.itemFields),
            URLQueryItem(name: "ImageTypeLimit", value: "1"),
            URLQueryItem(name: "EnableImageTypes", value: "Primary"),
        ], as: JFItemsResponse.self)
        guard let meta = await metaTask else { return nil }
        let entries = (await itemsTask)?.Items?.map { $0.asSong } ?? []
        return meta.asPlaylist(withEntries: entries)
    }

    func createPlaylist(name: String) async throws -> Playlist? {
        try await createPlaylist(name: name, songIDs: [])
    }

    func createPlaylist(name: String, songIDs: [String]) async throws -> Playlist? {
        let data = try await request("POST", "/Playlists", body: [
            "Name": name,
            "Ids": songIDs,
            "MediaType": "Audio",
            "UserId": userId,
        ])
        guard let created = try? JSONDecoder().decode(JFCreatePlaylistResponse.self, from: data),
              let id = created.Id else {
            return try? await playlists().first { $0.name == name }
        }
        return try? await playlist(id: id)
    }

    func addToPlaylist(playlistID: String, songID: String) async throws {
        _ = try await request("POST", "/Playlists/\(playlistID)/Items", query: [
            URLQueryItem(name: "Ids", value: songID),
            URLQueryItem(name: "UserId", value: userId),
        ])
    }

    // Jellyfin removes by PlaylistItemId, not list index.
    func removeFromPlaylist(playlistID: String, index: Int) async throws {
        let items = try await get("/Playlists/\(playlistID)/Items", query: [
            URLQueryItem(name: "UserId", value: userId),
        ], as: JFItemsResponse.self)
        guard let entryId = items.Items?[safe: index]?.PlaylistItemId else { return }
        _ = try await request("DELETE", "/Playlists/\(playlistID)/Items", query: [
            URLQueryItem(name: "EntryIds", value: entryId),
        ])
    }

    func deletePlaylist(id: String) async throws {
        _ = try await request("DELETE", "/Items/\(id)")
    }

    func renamePlaylist(playlistID: String, name: String) async throws {
        // UpdatePlaylist is Jellyfin 10.9+. Older servers may ignore it.
        _ = try await request("POST", "/Playlists/\(playlistID)", body: ["Name": name])
    }

    // No comment/overview field in UpdatePlaylistDto.
    func updatePlaylistComment(playlistID: String, comment: String) async throws {}

    // MARK: - Favorites

    func star(id: String) async throws {
        _ = try await request("POST", "/Users/\(userId)/FavoriteItems/\(id)")
    }
    func unstar(id: String) async throws {
        _ = try await request("DELETE", "/Users/\(userId)/FavoriteItems/\(id)")
    }

    // MARK: - Folder browsing

    func musicFolders() async throws -> [MusicFolder] {
        let res = try await get("/Users/\(userId)/Views", as: JFItemsResponse.self)
        return (res.Items ?? [])
            .filter { ($0.CollectionType ?? "") == "music" }
            .map { MusicFolder(id: $0.Id, name: $0.Name ?? "Music") }
    }

    func indexes(musicFolderId: String?) async throws -> [BrowseEntry] {
        // Music library children are artists/folders.
        var q: [URLQueryItem] = [
            URLQueryItem(name: "SortBy", value: "IsFolder,SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
        ]
        if let musicFolderId, !musicFolderId.isEmpty {
            q.append(URLQueryItem(name: "ParentId", value: musicFolderId))
        } else {
            q.append(URLQueryItem(name: "IncludeItemTypes", value: "MusicArtist"))
            q.append(URLQueryItem(name: "Recursive", value: "true"))
        }
        let res = try await get("/Users/\(userId)/Items", query: [
            URLQueryItem(name: "Fields", value: Self.itemFields),
        ] + q, as: JFItemsResponse.self)
        return (res.Items ?? []).map { $0.asBrowseEntry }
    }

    func musicDirectory(id: String) async throws -> [BrowseEntry] {
        let res = try await get("/Users/\(userId)/Items", query: itemsQuery([
            URLQueryItem(name: "ParentId", value: id),
            URLQueryItem(name: "SortBy", value: "IsFolder,ParentIndexNumber,IndexNumber,SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
        ]), as: JFItemsResponse.self)
        return (res.Items ?? []).map { $0.asBrowseEntry }
    }

    func getMusicFolderStats() async throws -> (artists: Int, albums: Int, songs: Int) {
        let counts = try await get("/Items/Counts", query: [
            URLQueryItem(name: "UserId", value: userId),
        ], as: JFItemCounts.self)
        return (counts.ArtistCount ?? 0, counts.AlbumCount ?? 0, counts.SongCount ?? 0)
    }

    // MARK: - Lyrics

    func lyricsBySongId(id: String) async throws -> LyricsList? {
        guard let res = try? await get("/Audio/\(id)/Lyrics", as: JFLyricsResponse.self),
              let lines = res.Lyrics, !lines.isEmpty else { return nil }
        let synced = lines.contains { $0.Start != nil }
        let structured = StructuredLyrics(
            displayArtist: nil,
            displayTitle: nil,
            lang: nil,
            synced: synced,
            line: lines.map { StructuredLyricLine(start: $0.Start.map { Int($0 / 10_000) }, value: $0.Text ?? "") }
        )
        return LyricsList(structuredLyrics: [structured])
    }

    // No artist/title lyric lookup here.
    func lyrics(artist: String, title: String) async throws -> String? { nil }

    // MARK: - Sharing (unsupported)

    func sharingAvailable() async -> Bool { false }
    func createShare(id: String) async throws -> URL? { nil }

    // MARK: - Media URLs

    func coverArtURL(id: String?, size: Int?) -> URL? {
        guard let id, !id.isEmpty else { return nil }
        var q = [URLQueryItem(name: "api_key", value: token)]
        if let size { q.append(URLQueryItem(name: "maxWidth", value: String(size))) }
        return url("/Items/\(id)/Images/Primary", query: q)
    }

    func streamURL(id: String) -> URL? {
        let kbps = StreamingPreferences.streamBitrateKbps
        return audioURL(id: id, bitrateKbps: kbps)
    }

    func downloadURL(id: String) -> URL? {
        let kbps = StreamingPreferences.downloadBitrateKbps
        return audioURL(id: id, bitrateKbps: kbps)
    }

    func originalStreamURL(id: String) -> URL? {
        url("/Audio/\(id)/stream", query: [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "api_key", value: token),
        ])
    }

    // 0 kbps means original bytes; otherwise use the universal transcoder.
    private func audioURL(id: String, bitrateKbps: Int) -> URL? {
        guard bitrateKbps > 0 else { return originalStreamURL(id: id) }
        var q = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "api_key", value: token),
            URLQueryItem(name: "DeviceId", value: deviceId),
            URLQueryItem(name: "MaxStreamingBitrate", value: String(bitrateKbps * 1000)),
            URLQueryItem(name: "TranscodingContainer", value: "ts"),
            URLQueryItem(name: "TranscodingProtocol", value: "hls"),
            URLQueryItem(name: "Container", value: "flac,alac,aac,m4a,mp3,opus,ogg,wav,webma"),
        ]
        if let fmt = StreamingPreferences.transcodingFormat {
            q.append(URLQueryItem(name: "AudioCodec", value: jellyfinCodec(for: fmt)))
        } else {
            q.append(URLQueryItem(name: "AudioCodec", value: "aac"))
        }
        return url("/Audio/\(id)/universal", query: q)
    }

    private func jellyfinCodec(for format: String) -> String {
        switch format.lowercased() {
        case "opus": return "opus"
        case "mp3": return "mp3"
        case "aac", "m4a": return "aac"
        case "ogg": return "vorbis"
        default: return "aac"
        }
    }
}

// MARK: - Safe index

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
