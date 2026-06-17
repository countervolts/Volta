import Foundation

// Plex adapter. Handles token auth, MediaContainer envelopes, ratings-as-favorites,
// and cached file-part keys for synchronous stream/download URL builders.
final class PlexClient: MusicService, @unchecked Sendable {
    let config: SubsonicConfig
    let token: String
    let clientId: String
    let machineId: String
    let sectionKey: String          // chosen music library section
    let session: URLSession

    var backendKind: MusicBackendKind { .plex }

    // Favorites are a rating proxy. Sharing/lyrics are best-effort.
    var capabilities: MusicServiceCapabilities {
        [.folderBrowsing, .favorites, .topSongsByArtist, .artistBiography,
         .songsByGenre, .recentlyPlayed, .playCounts, .playlistComments, .syncedLyrics]
    }

    // ratingKey -> file part key, filled while mapping tracks.
    private let lock = NSLock()
    private var partCache: [String: String] = [:]
    private var genreCache: [String: String] = [:]   // lowercased genre name -> filter key

    static let product = "Volta"
    static let version = "1.0"

    init(config: SubsonicConfig, token: String, clientId: String, machineId: String,
         sectionKey: String, session: URLSession) {
        self.config = config
        self.token = token
        self.clientId = clientId
        self.machineId = machineId
        self.sectionKey = sectionKey
        self.session = session
    }

    // MARK: - Connection / auth

    static func connect(config: SubsonicConfig, session: URLSession = .shared) async throws -> PlexClient {
        let clientId = Self.clientID()

        // 1) password may already be an X-Plex-Token.
        var token: String?
        if let candidate = config.password.nonBlank,
           await Self.tokenWorks(candidate, baseURL: config.baseURL, clientId: clientId, session: session) {
            token = candidate
        }
        // 2) otherwise mint one through plex.tv.
        if token == nil {
            token = try await Self.plexSignIn(login: config.username, password: config.password,
                                              clientId: clientId, session: session)
        }
        guard let token else { throw SubsonicError.invalidCredentials }

        let machineId = try await Self.serverMachineId(baseURL: config.baseURL, token: token,
                                                       clientId: clientId, session: session)
        guard let section = try await Self.firstMusicSection(baseURL: config.baseURL, token: token,
                                                             clientId: clientId, session: session) else {
            throw SubsonicError.server(code: 0, message: "No music library found on this Plex server")
        }
        return PlexClient(config: config, token: token, clientId: clientId, machineId: machineId,
                          sectionKey: section, session: session)
    }

    static func clientID() -> String {
        let key = "plexClientId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    static func plexHeaders(clientId: String) -> [String: String] {
        [
            "X-Plex-Client-Identifier": clientId,
            "X-Plex-Product": product,
            "X-Plex-Version": version,
            "X-Plex-Platform": "iOS",
            "Accept": "application/json",
        ]
    }

    private static func tokenWorks(_ token: String, baseURL: URL, clientId: String, session: URLSession) async -> Bool {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return false }
        comps.path = (comps.path.hasSuffix("/") ? String(comps.path.dropLast()) : comps.path) + "/identity"
        comps.queryItems = [URLQueryItem(name: "X-Plex-Token", value: token)]
        guard let url = comps.url else { return false }
        var req = URLRequest(url: url)
        for (k, v) in plexHeaders(clientId: clientId) { req.setValue(v, forHTTPHeaderField: k) }
        req.timeoutInterval = 15
        guard let (_, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    private static func plexSignIn(login: String, password: String, clientId: String, session: URLSession) async throws -> String {
        guard let url = URL(string: "https://plex.tv/api/v2/users/signin") else { throw SubsonicError.invalidResponse }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        for (k, v) in plexHeaders(clientId: clientId) { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "login=\(login.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? login)&password=\(password.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? password)"
        req.httpBody = body.data(using: .utf8)

        let data: Data
        let resp: URLResponse
        do { (data, resp) = try await session.data(for: req) }
        catch { throw SubsonicError.serverUnreachable }
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw SubsonicError.invalidCredentials
        }
        struct SignIn: Decodable { let authToken: String? }
        guard let token = (try? JSONDecoder().decode(SignIn.self, from: data))?.authToken else {
            throw SubsonicError.invalidCredentials
        }
        return token
    }

    private static func serverMachineId(baseURL: URL, token: String, clientId: String, session: URLSession) async throws -> String {
        let container = try await rawGet("/identity", baseURL: baseURL, token: token, clientId: clientId, session: session)
        return container.machineIdentifier ?? ""
    }

    private static func firstMusicSection(baseURL: URL, token: String, clientId: String, session: URLSession) async throws -> String? {
        let container = try await rawGet("/library/sections", baseURL: baseURL, token: token, clientId: clientId, session: session)
        return (container.Directory ?? []).first { $0.type == "artist" }?.key
    }

    // Bare GET for pre-instance connect checks.
    private static func rawGet(_ path: String, baseURL: URL, token: String, clientId: String, session: URLSession) async throws -> PXContainer {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw SubsonicError.invalidResponse }
        let base = comps.path.hasSuffix("/") ? String(comps.path.dropLast()) : comps.path
        comps.path = base + path
        comps.queryItems = [URLQueryItem(name: "X-Plex-Token", value: token)]
        guard let url = comps.url else { throw SubsonicError.invalidResponse }
        var req = URLRequest(url: url)
        for (k, v) in plexHeaders(clientId: clientId) { req.setValue(v, forHTTPHeaderField: k) }
        req.timeoutInterval = 20
        let data: Data
        let resp: URLResponse
        do { (data, resp) = try await session.data(for: req) }
        catch { throw SubsonicError.serverUnreachable }
        if let http = resp as? HTTPURLResponse {
            if http.statusCode == 401 { throw SubsonicError.invalidCredentials }
            if !(200...299).contains(http.statusCode) { throw SubsonicError.server(code: http.statusCode, message: "HTTP \(http.statusCode)") }
        }
        guard let decoded = try? JSONDecoder().decode(PXResponse.self, from: data),
              let container = decoded.MediaContainer else { throw SubsonicError.invalidResponse }
        return container
    }

    // MARK: - URL + request plumbing

    func url(_ path: String, query: [URLQueryItem] = []) -> URL? {
        guard var comps = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false) else { return nil }
        let base = comps.path.hasSuffix("/") ? String(comps.path.dropLast()) : comps.path
        comps.path = base + path
        comps.queryItems = query + [URLQueryItem(name: "X-Plex-Token", value: token)]
        return comps.url
    }

    @discardableResult
    private func send(_ method: String, _ path: String, query: [URLQueryItem] = []) async throws -> PXContainer? {
        try await DeveloperSimulation.prepareRequest(endpoint: path)
        guard let url = url(path, query: query) else { throw SubsonicError.invalidResponse }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.cachePolicy = .reloadIgnoringLocalCacheData
        for (k, v) in Self.plexHeaders(clientId: clientId) { req.setValue(v, forHTTPHeaderField: k) }
        AppLogger.shared.log("> [Plex] \(method) \(path)", category: .networking)
        let data: Data
        let resp: URLResponse
        do { (data, resp) = try await session.data(for: req) }
        catch { throw SubsonicError.serverUnreachable }
        if let http = resp as? HTTPURLResponse {
            if http.statusCode == 401 { throw SubsonicError.invalidCredentials }
            if !(200...299).contains(http.statusCode) { throw SubsonicError.server(code: http.statusCode, message: "HTTP \(http.statusCode)") }
        }
        return (try? JSONDecoder().decode(PXResponse.self, from: data))?.MediaContainer
    }

    private func get(_ path: String, query: [URLQueryItem] = []) async throws -> PXContainer {
        guard let container = try await send("GET", path, query: query) else { throw SubsonicError.invalidResponse }
        return container
    }

    private func metadata(_ path: String, query: [URLQueryItem] = []) async throws -> [PXMetadata] {
        try await get(path, query: query).Metadata ?? []
    }

    // server://{machineId}/com.plexapp.plugins.library/library/metadata/{ids}
    private func libraryURI(ids: [String]) -> String {
        "server://\(machineId)/com.plexapp.plugins.library/library/metadata/\(ids.joined(separator: ","))"
    }

    // MARK: - Track mapping (caches the file part key for streaming)

    private func track(from m: PXMetadata) -> Song {
        let media = m.Media?.first
        let part = media?.Part?.first
        let audio = part?.Stream?.first { ($0.streamType ?? 0) == 2 }
        if let rk = m.ratingKey, let partKey = part?.key {
            lock.withLock { partCache[rk] = partKey }
        }
        let container = part?.container ?? media?.container
        return Song(
            id: m.ratingKey ?? "",
            title: m.title ?? "Unknown",
            album: m.parentTitle,
            artist: m.grandparentTitle,
            albumId: m.parentRatingKey,
            artistId: m.grandparentRatingKey,
            coverArt: m.thumb ?? m.parentThumb ?? m.grandparentThumb,
            duration: m.duration.map { $0 / 1000 },
            track: m.index,
            discNumber: m.parentIndex,
            year: m.year,
            genre: m.Genre?.first?.tag,
            size: part?.size,
            contentType: nil,
            suffix: container?.lowercased(),
            bitRate: media?.bitrate,
            path: part?.file,
            playCount: m.viewCount,
            bpm: nil,                          // Plex does not expose BPM
            starred: m.starredMarker,
            contributes: nil,
            replayGain: nil,                   // Plex does not expose ReplayGain
            samplingRate: audio?.samplingRate,
            bitDepth: audio?.bitDepth,
            channelCount: audio?.channels ?? media?.audioChannels,
            displayComposer: nil,
            contributors: nil
        )
    }

    private func cachedPart(_ id: String) -> String? {
        lock.withLock { partCache[id] }
    }

    // MARK: - Health

    func ping() async throws { _ = try await get("/identity") }

    func serverHealth() async throws -> ServerHealthSnapshot {
        let start = Date()
        let container = try? await get("/")
        let latency = max(0, Int(Date().timeIntervalSince(start) * 1000))
        return ServerHealthSnapshot(
            status: "ok",
            apiVersion: container?.version,
            serverType: "Plex Media Server",
            latencyMS: latency,
            checkedAt: Date()
        )
    }

    // MARK: - Albums

    private func sectionAlbums(sort: String, size: Int, offset: Int = 0) async throws -> [Album] {
        try await metadata("/library/sections/\(sectionKey)/all", query: [
            URLQueryItem(name: "type", value: "9"),
            URLQueryItem(name: "sort", value: sort),
            URLQueryItem(name: "X-Plex-Container-Start", value: String(offset)),
            URLQueryItem(name: "X-Plex-Container-Size", value: String(size)),
        ]).map { $0.asAlbum }
    }

    func randomAlbums(size: Int) async throws -> [Album] {
        let albums = try await sectionAlbums(sort: "random", size: size)
        return albums.isEmpty ? (try await sectionAlbums(sort: "addedAt:desc", size: size)).shuffled() : albums
    }
    func newestAlbums(size: Int) async throws -> [Album] {
        try await sectionAlbums(sort: "addedAt:desc", size: size)
    }
    func recentlyPlayedAlbums(size: Int) async throws -> [Album] {
        try await sectionAlbums(sort: "lastViewedAt:desc", size: size)
    }
    func frequentAlbums(size: Int) async throws -> [Album] {
        try await sectionAlbums(sort: "viewCount:desc", size: size)
    }
    func allAlbums(size: Int, offset: Int) async throws -> [Album] {
        try await sectionAlbums(sort: "titleSort", size: size, offset: offset)
    }

    func album(id: String) async throws -> Album? {
        async let metaTask = try? metadata("/library/metadata/\(id)").first
        async let tracksTask = try? metadata("/library/metadata/\(id)/children")
        guard let meta = await metaTask ?? nil else { return nil }
        let songs = (await tracksTask ?? nil)?.map { track(from: $0) } ?? []
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
        try await metadata("/library/sections/\(sectionKey)/all", query: [
            URLQueryItem(name: "type", value: "8"),
            URLQueryItem(name: "sort", value: "titleSort"),
        ]).map { $0.asArtist }
    }

    func artist(id: String) async throws -> Artist? {
        async let metaTask = try? metadata("/library/metadata/\(id)").first
        async let albumsTask = try? metadata("/library/metadata/\(id)/children")
        guard let meta = await metaTask ?? nil else { return nil }
        let albums = (await albumsTask ?? nil)?.map { $0.asAlbum } ?? []
        return meta.asArtist(withAlbums: albums)
    }

    func artistInfo(id: String) async throws -> ArtistInfo? {
        guard let meta = try? await metadata("/library/metadata/\(id)").first else { return nil }
        return ArtistInfo(
            biography: meta.summary,
            similarArtist: [],   // related hubs are too inconsistent
            smallImageUrl: nil,
            mediumImageUrl: nil,
            largeImageUrl: meta.thumb.flatMap { coverArtURL(id: $0, size: 600)?.absoluteString }
        )
    }

    func songsForArtist(id: String) async throws -> [Song] {
        try await metadata("/library/metadata/\(id)/allLeaves").map { track(from: $0) }
    }

    func topSongs(artistName: String, count: Int) async throws -> [Song] {
        guard let artistId = try await firstArtistId(named: artistName) else { return [] }
        let tracks = try await metadata("/library/metadata/\(artistId)/allLeaves", query: [
            URLQueryItem(name: "sort", value: "viewCount:desc"),
        ])
        return Array(tracks.prefix(count)).map { track(from: $0) }
    }

    private func firstArtistId(named name: String) async throws -> String? {
        try await metadata("/library/sections/\(sectionKey)/all", query: [
            URLQueryItem(name: "type", value: "8"),
            URLQueryItem(name: "title", value: name),
            URLQueryItem(name: "X-Plex-Container-Size", value: "1"),
        ]).first?.ratingKey
    }

    // MARK: - Songs

    func song(id: String) async throws -> Song? {
        (try? await metadata("/library/metadata/\(id)").first).flatMap { $0 }.map { track(from: $0) }
    }

    func randomSongs(size: Int) async throws -> [Song] {
        let tracks = try await metadata("/library/sections/\(sectionKey)/all", query: [
            URLQueryItem(name: "type", value: "10"),
            URLQueryItem(name: "sort", value: "random"),
            URLQueryItem(name: "X-Plex-Container-Size", value: String(size)),
        ])
        let mapped = tracks.map { track(from: $0) }
        return mapped.isEmpty ? mapped : mapped.shuffled()
    }

    func songsByGenre(_ genre: String, count: Int, offset: Int) async throws -> [Song] {
        guard let genreKey = try await genreFilterKey(for: genre) else { return [] }
        return try await metadata("/library/sections/\(sectionKey)/all", query: [
            URLQueryItem(name: "type", value: "10"),
            URLQueryItem(name: "genre", value: genreKey),
            URLQueryItem(name: "X-Plex-Container-Start", value: String(offset)),
            URLQueryItem(name: "X-Plex-Container-Size", value: String(count)),
        ]).map { track(from: $0) }
    }

    // Plex filters tracks by genre id, not name.
    private func genreFilterKey(for name: String) async throws -> String? {
        let lower = name.lowercased()
        if let cached = lock.withLock({ genreCache[lower] }) { return cached }
        let dirs = try await get("/library/sections/\(sectionKey)/genre").Directory ?? []
        var map: [String: String] = [:]
        for d in dirs { if let t = d.title, let k = d.key { map[t.lowercased()] = k } }
        lock.withLock { genreCache = map }
        return map[lower]
    }

    // MARK: - Search

    func search(query: String, artistCount: Int, albumCount: Int, songCount: Int) async throws -> (artists: [Artist], albums: [Album], songs: [Song]) {
        let limit = max(artistCount, albumCount, songCount, 10)
        let container = try await get("/hubs/search", query: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
        var artists: [Artist] = []
        var albums: [Album] = []
        var songs: [Song] = []
        for hub in container.Hub ?? [] {
            let items = hub.Metadata ?? []
            switch hub.type {
            case "artist": artists = items.prefix(artistCount).map { $0.asArtist }
            case "album":  albums = items.prefix(albumCount).map { $0.asAlbum }
            case "track":  songs = items.prefix(songCount).map { track(from: $0) }
            default: break
            }
        }
        return (artists, albums, songs)
    }

    // MARK: - Playlists

    func playlists() async throws -> [Playlist] {
        try await metadata("/playlists", query: [
            URLQueryItem(name: "playlistType", value: "audio"),
        ]).map { $0.asPlaylist(withEntries: nil) }
    }

    func playlist(id: String) async throws -> Playlist? {
        async let metaTask = try? metadata("/playlists/\(id)").first
        async let itemsTask = try? metadata("/playlists/\(id)/items")
        guard let meta = await metaTask ?? nil else { return nil }
        let entries = (await itemsTask ?? nil)?.map { track(from: $0) } ?? []
        return meta.asPlaylist(withEntries: entries)
    }

    // Plex needs a seed track to create a playlist.
    func createPlaylist(name: String) async throws -> Playlist? {
        nil
    }

    func createPlaylist(name: String, songIDs: [String]) async throws -> Playlist? {
        guard !songIDs.isEmpty else { return nil }
        let container = try await send("POST", "/playlists", query: [
            URLQueryItem(name: "type", value: "audio"),
            URLQueryItem(name: "title", value: name),
            URLQueryItem(name: "smart", value: "0"),
            URLQueryItem(name: "uri", value: libraryURI(ids: songIDs)),
        ])
        guard let id = container?.Metadata?.first?.ratingKey else {
            return try? await playlists().first { $0.name == name }
        }
        return try? await playlist(id: id)
    }

    func addToPlaylist(playlistID: String, songID: String) async throws {
        _ = try await send("PUT", "/playlists/\(playlistID)/items", query: [
            URLQueryItem(name: "uri", value: libraryURI(ids: [songID])),
        ])
    }

    func removeFromPlaylist(playlistID: String, index: Int) async throws {
        let items = try await metadata("/playlists/\(playlistID)/items")
        guard index >= 0, index < items.count, let entry = items[index].playlistItemID else { return }
        _ = try await send("DELETE", "/playlists/\(playlistID)/items/\(entry)")
    }

    func deletePlaylist(id: String) async throws {
        _ = try await send("DELETE", "/playlists/\(id)")
    }

    func renamePlaylist(playlistID: String, name: String) async throws {
        _ = try await send("PUT", "/playlists/\(playlistID)", query: [
            URLQueryItem(name: "title", value: name),
        ])
    }

    func updatePlaylistComment(playlistID: String, comment: String) async throws {
        _ = try await send("PUT", "/playlists/\(playlistID)", query: [
            URLQueryItem(name: "summary", value: comment),
        ])
    }

    // MARK: - Favorites (10/10 rating proxy)

    func star(id: String) async throws {
        _ = try await send("PUT", "/:/rate", query: [
            URLQueryItem(name: "identifier", value: "com.plexapp.plugins.library"),
            URLQueryItem(name: "key", value: id),
            URLQueryItem(name: "rating", value: "10"),
        ])
    }
    func unstar(id: String) async throws {
        _ = try await send("PUT", "/:/rate", query: [
            URLQueryItem(name: "identifier", value: "com.plexapp.plugins.library"),
            URLQueryItem(name: "key", value: id),
            URLQueryItem(name: "rating", value: "-1"),
        ])
    }

    // MARK: - Folder browsing (mapped onto the artist → album → track hierarchy)

    func musicFolders() async throws -> [MusicFolder] {
        let dirs = try await get("/library/sections").Directory ?? []
        return dirs.filter { $0.type == "artist" }.compactMap { d in
            guard let key = d.key else { return nil }
            return MusicFolder(id: key, name: d.title ?? "Music")
        }
    }

    func indexes(musicFolderId: String?) async throws -> [BrowseEntry] {
        let section = (musicFolderId?.nonBlank) ?? sectionKey
        return try await metadata("/library/sections/\(section)/all", query: [
            URLQueryItem(name: "type", value: "8"),
            URLQueryItem(name: "sort", value: "titleSort"),
        ]).map { BrowseEntry(id: $0.ratingKey ?? "", name: $0.title ?? "Unknown",
                             isDirectory: true, coverArt: $0.thumb, song: nil) }
    }

    func musicDirectory(id: String) async throws -> [BrowseEntry] {
        let items = try await metadata("/library/metadata/\(id)/children")
        return items.map { m in
            let isTrack = (m.type ?? "") == "track"
            return BrowseEntry(
                id: m.ratingKey ?? "",
                name: m.title ?? "Unknown",
                isDirectory: !isTrack,
                coverArt: m.thumb ?? m.parentThumb,
                song: isTrack ? track(from: m) : nil
            )
        }
    }

    func getMusicFolderStats() async throws -> (artists: Int, albums: Int, songs: Int) {
        @Sendable func count(type: Int) async -> Int {
            let c = try? await get("/library/sections/\(sectionKey)/all", query: [
                URLQueryItem(name: "type", value: String(type)),
                URLQueryItem(name: "X-Plex-Container-Size", value: "0"),
            ])
            return c?.totalSize ?? c?.size ?? 0
        }
        async let a = count(type: 8)
        async let al = count(type: 9)
        async let s = count(type: 10)
        return (await a, await al, await s)
    }

    // MARK: - Lyrics (best-effort: find a lyric stream and parse its LRC)

    func lyricsBySongId(id: String) async throws -> LyricsList? {
        guard let meta = try? await metadata("/library/metadata/\(id)").first,
              let lyricStream = meta.Media?.first?.Part?.first?.Stream?.first(where: { ($0.streamType ?? 0) == 4 }),
              let streamKey = lyricStream.key,
              let url = url(streamKey) else { return nil }
        var req = URLRequest(url: url)
        for (k, v) in Self.plexHeaders(clientId: clientId) { req.setValue(v, forHTTPHeaderField: k) }
        guard let (data, _) = try? await session.data(for: req),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return Self.parseLRC(text)
    }

    func lyrics(artist: String, title: String) async throws -> String? { nil }

    // MARK: - Sharing (unsupported)

    func sharingAvailable() async -> Bool { false }
    func createShare(id: String) async throws -> URL? { nil }

    // MARK: - Media URLs

    func coverArtURL(id: String?, size: Int?) -> URL? {
        // `id` here is a Plex thumb path like /library/metadata/123/thumb/456.
        guard let id, !id.isEmpty else { return nil }
        return url(id)
    }

    func streamURL(id: String) -> URL? {
        let kbps = StreamingPreferences.streamBitrateKbps
        if kbps == 0, let part = cachedPart(id) { return url(part) }   // original file
        return transcodeURL(id: id, bitrateKbps: kbps > 0 ? kbps : 320)
    }

    func downloadURL(id: String) -> URL? {
        let kbps = StreamingPreferences.downloadBitrateKbps
        if kbps == 0, let part = cachedPart(id) { return url(part) }   // exact original bytes
        return transcodeURL(id: id, bitrateKbps: kbps > 0 ? kbps : 320)
    }

    // Capped downloads use Plex's progressive transcoder; uncapped uses the file part.
    func downloadIsProgressive(id: String) -> Bool {
        let kbps = StreamingPreferences.downloadBitrateKbps
        if kbps == 0, cachedPart(id) != nil { return false }
        return true
    }

    func originalStreamURL(id: String) -> URL? {
        if let part = cachedPart(id) { return url(part) }
        return transcodeURL(id: id, bitrateKbps: 320)
    }

    func mediaRequestHeaders() -> [String: String] {
        // Plex needs identity headers here, and no JSON Accept header.
        var headers = Self.plexHeaders(clientId: clientId)
        headers.removeValue(forKey: "Accept")
        return headers
    }

    // Plex universal transcoder stream. Also used by the stream-cache experiment.
    private func transcodeURL(id: String, bitrateKbps: Int) -> URL? {
        let ext = StreamingPreferences.plexUniversalTranscodeExtension
        // One transcode session per track; shared sessions cancel each other.
        let session = "\(clientId)-\(id)"
        return url("/music/:/transcode/universal/start.\(ext)", query: [
            URLQueryItem(name: "path", value: "/library/metadata/\(id)"),
            URLQueryItem(name: "mediaIndex", value: "0"),
            URLQueryItem(name: "partIndex", value: "0"),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "protocol", value: "http"),
            URLQueryItem(name: "directPlay", value: "0"),
            URLQueryItem(name: "directStream", value: "1"),
            URLQueryItem(name: "hasMDE", value: "1"),
            // Plex music bitrate knob. The video-audio knob is ignored here.
            URLQueryItem(name: "musicBitrate", value: String(bitrateKbps)),
            URLQueryItem(name: "maxAudioBitrate", value: String(bitrateKbps)),
            URLQueryItem(name: "session", value: session),
            URLQueryItem(name: "X-Plex-Session-Identifier", value: session),
            URLQueryItem(name: "X-Plex-Client-Identifier", value: clientId),
        ])
    }

    // MARK: - LRC parsing

    private static func parseLRC(_ text: String) -> LyricsList {
        var lines: [StructuredLyricLine] = []
        var synced = false
        let pattern = try? NSRegularExpression(pattern: "\\[(\\d{1,2}):(\\d{2})(?:[.:](\\d{1,3}))?\\]")
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let ns = line as NSString
            let matches = pattern?.matches(in: line, range: NSRange(location: 0, length: ns.length)) ?? []
            let content = pattern?.stringByReplacingMatches(in: line, range: NSRange(location: 0, length: ns.length), withTemplate: "")
                .trimmingCharacters(in: .whitespaces) ?? line
            if matches.isEmpty {
                if !content.isEmpty { lines.append(StructuredLyricLine(start: nil, value: content)) }
                continue
            }
            synced = true
            for m in matches {
                let min = Int(ns.substring(with: m.range(at: 1))) ?? 0
                let sec = Int(ns.substring(with: m.range(at: 2))) ?? 0
                var ms = 0
                if m.range(at: 3).location != NSNotFound {
                    let frac = ns.substring(with: m.range(at: 3))
                    ms = (Int(frac) ?? 0) * (frac.count == 2 ? 10 : 1)
                }
                lines.append(StructuredLyricLine(start: (min * 60 + sec) * 1000 + ms, value: content))
            }
        }
        lines.sort { ($0.start ?? 0) < ($1.start ?? 0) }
        let structured = StructuredLyrics(displayArtist: nil, displayTitle: nil, lang: nil,
                                          synced: synced, line: lines)
        return LyricsList(structuredLyrics: [structured])
    }
}
