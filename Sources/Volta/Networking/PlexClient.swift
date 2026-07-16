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
    private let connections: [PlexConnectionEndpoint]
    private var activeBaseURL: URL
    private var connectionRefreshGeneration = 0

    static let product = "Volta"
    static let version = "1.0"
    static let tokenUsername = "Plex"

    init(config: SubsonicConfig, token: String, clientId: String, machineId: String,
         sectionKey: String, session: URLSession) {
        self.config = config
        self.token = token
        self.clientId = clientId
        self.machineId = machineId
        self.sectionKey = sectionKey
        self.session = session
        connections = Self.connectionEndpoints(for: config)
        activeBaseURL = config.baseURL
    }

    // MARK: - Connection / auth

    static func connect(config: SubsonicConfig, session: URLSession = .shared) async throws -> PlexClient {
        let clientId = Self.clientID()

        let token: String
        if config.username.caseInsensitiveCompare(Self.tokenUsername) == .orderedSame {
            guard let candidate = config.password.nonBlank else {
                throw SubsonicError.invalidCredentials
            }
            token = candidate
        } else {
            token = try await Self.plexSignIn(login: config.username, password: config.password,
                                             clientId: clientId, session: session)
        }

        let connections = Self.orderedConnections(
            Self.connectionEndpoints(for: config),
            preferLocal: !UserDefaults.standard.bool(forKey: "networkIsCellular")
        )
        var lastError: SubsonicError?
        for connection in connections {
            do {
                let machineId = try await Self.serverMachineId(
                    baseURL: connection.url,
                    token: token,
                    clientId: clientId,
                    session: session,
                    timeout: connection.kind == .local ? 4 : 12
                )
                guard let section = try await Self.firstMusicSection(
                    baseURL: connection.url,
                    token: token,
                    clientId: clientId,
                    session: session,
                    timeout: connection.kind == .local ? 4 : 12
                ) else {
                    throw SubsonicError.server(
                        code: 0,
                        message: "No music library found on this Plex server"
                    )
                }
                let tokenConfig = SubsonicConfig(
                    baseURL: connection.url,
                    username: Self.tokenUsername,
                    password: token,
                    plexConnections: connections
                )
                return PlexClient(
                    config: tokenConfig,
                    token: token,
                    clientId: clientId,
                    machineId: machineId,
                    sectionKey: section,
                    session: session
                )
            } catch let error as SubsonicError {
                if error.isAuthFailure { throw error }
                lastError = error
            }
        }
        throw lastError ?? SubsonicError.serverUnreachable
    }

    static func connectionEndpoints(for config: SubsonicConfig) -> [PlexConnectionEndpoint] {
        var endpoints = config.plexConnections
        if let baseIndex = endpoints.firstIndex(where: {
            $0.url.absoluteString == config.baseURL.absoluteString
        }) {
            let base = endpoints.remove(at: baseIndex)
            endpoints.insert(base, at: 0)
        } else {
            endpoints.insert(PlexConnectionEndpoint(url: config.baseURL, kind: .manual), at: 0)
        }
        var seen = Set<String>()
        return endpoints.filter { seen.insert($0.url.absoluteString).inserted }
    }

    static func orderedConnections(
        _ connections: [PlexConnectionEndpoint],
        preferLocal: Bool
    ) -> [PlexConnectionEndpoint] {
        connections.enumerated().sorted { lhs, rhs in
            let leftRank = lhs.element.preferenceRank(preferLocal: preferLocal)
            let rightRank = rhs.element.preferenceRank(preferLocal: preferLocal)
            return leftRank == rightRank ? lhs.offset < rhs.offset : leftRank < rightRank
        }.map(\.element)
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

    private static func serverMachineId(
        baseURL: URL,
        token: String,
        clientId: String,
        session: URLSession,
        timeout: TimeInterval = 20
    ) async throws -> String {
        let container = try await rawGet(
            "/identity",
            baseURL: baseURL,
            token: token,
            clientId: clientId,
            session: session,
            timeout: timeout
        )
        return container.machineIdentifier ?? ""
    }

    private static func firstMusicSection(
        baseURL: URL,
        token: String,
        clientId: String,
        session: URLSession,
        timeout: TimeInterval = 20
    ) async throws -> String? {
        let container = try await rawGet(
            "/library/sections",
            baseURL: baseURL,
            token: token,
            clientId: clientId,
            session: session,
            timeout: timeout
        )
        return (container.Directory ?? []).first { $0.type == "artist" }?.key
    }

    // Bare GET for pre-instance connect checks.
    private static func rawGet(
        _ path: String,
        baseURL: URL,
        token: String,
        clientId: String,
        session: URLSession,
        timeout: TimeInterval = 20
    ) async throws -> PXContainer {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw SubsonicError.invalidResponse }
        let base = comps.path.hasSuffix("/") ? String(comps.path.dropLast()) : comps.path
        comps.path = base + path
        comps.queryItems = [URLQueryItem(name: "X-Plex-Token", value: token)]
        guard let url = comps.url else { throw SubsonicError.invalidResponse }
        var req = URLRequest(url: url)
        for (k, v) in plexHeaders(clientId: clientId) { req.setValue(v, forHTTPHeaderField: k) }
        req.timeoutInterval = timeout
        let data: Data
        let resp: URLResponse
        do { (data, resp) = try await session.data(for: req) }
        catch { throw SubsonicError.serverUnreachable }
        guard let http = resp as? HTTPURLResponse else { throw SubsonicError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw SubsonicError.invalidCredentials }
        if !(200...299).contains(http.statusCode) { throw SubsonicError.server(code: http.statusCode, message: "HTTP \(http.statusCode)") }
        guard let decoded = try? JSONDecoder().decode(PXResponse.self, from: data),
              let container = decoded.MediaContainer else { throw SubsonicError.invalidResponse }
        return container
    }

    // MARK: - URL + request plumbing

    func url(_ path: String, query: [URLQueryItem] = []) -> URL? {
        makeURL(path, query: query, baseURL: currentBaseURL())
    }

    private func makeURL(
        _ path: String,
        query: [URLQueryItem],
        baseURL: URL
    ) -> URL? {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        let base = comps.path.hasSuffix("/") ? String(comps.path.dropLast()) : comps.path
        comps.path = base + path
        comps.queryItems = query + [URLQueryItem(name: "X-Plex-Token", value: token)]
        return comps.url
    }

    private func currentBaseURL() -> URL {
        lock.withLock { activeBaseURL }
    }

    private func requestConnections(activeFirst: Bool) -> [PlexConnectionEndpoint] {
        let active = currentBaseURL()
        var ordered = Self.orderedConnections(
            connections,
            preferLocal: !UserDefaults.standard.bool(forKey: "networkIsCellular")
        )
        guard activeFirst,
              let activeIndex = ordered.firstIndex(where: { $0.url.absoluteString == active.absoluteString }) else {
            return ordered
        }
        let activeConnection = ordered.remove(at: activeIndex)
        ordered.insert(activeConnection, at: 0)
        return ordered
    }

    private func setActiveConnection(_ url: URL, reason: String) {
        let previous = lock.withLock { () -> URL in
            let previous = activeBaseURL
            activeBaseURL = url
            return previous
        }
        guard previous.absoluteString != url.absoluteString else { return }
        AppLogger.shared.log(
            "Plex connection switched; from=\(previous.absoluteString); to=\(url.absoluteString); reason=\(reason)",
            category: .networking
        )
    }

    // Called after Wi-Fi/cellular transitions so a healthy LAN route can take
    // over immediately instead of waiting for the public route to fail.
    func refreshConnection(preferLocal: Bool) async {
        let generation = lock.withLock { () -> Int in
            connectionRefreshGeneration += 1
            return connectionRefreshGeneration
        }
        for connection in Self.orderedConnections(connections, preferLocal: preferLocal) {
            do {
                let identity = try await Self.rawGet(
                    "/identity",
                    baseURL: connection.url,
                    token: token,
                    clientId: clientId,
                    session: session,
                    timeout: 4
                )
                guard machineId.isEmpty || identity.machineIdentifier == machineId else { continue }
                let isCurrentGeneration = lock.withLock {
                    generation == connectionRefreshGeneration
                }
                guard isCurrentGeneration else { return }
                setActiveConnection(connection.url, reason: "network changed")
                return
            } catch {
                continue
            }
        }
    }

    @discardableResult
    private func send(_ method: String, _ path: String, query: [URLQueryItem] = []) async throws -> PXContainer? {
        try await DeveloperSimulation.prepareRequest(endpoint: path)
        let started = ProcessInfo.processInfo.systemUptime
        AppLogger.shared.log("Request started: [Plex] \(method) \(path)", category: .networking)
        let canRetry = method == "GET" || method == "HEAD"
        let attempts = canRetry ? requestConnections(activeFirst: true) : requestConnections(activeFirst: true).prefix(1).map { $0 }
        var lastError: SubsonicError = .serverUnreachable

        for (index, connection) in attempts.enumerated() {
            guard let url = makeURL(path, query: query, baseURL: connection.url) else {
                lastError = .invalidResponse
                continue
            }
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.timeoutInterval = connection.kind == .local ? 5 : 20
            req.cachePolicy = .reloadIgnoringLocalCacheData
            for (k, v) in Self.plexHeaders(clientId: clientId) { req.setValue(v, forHTTPHeaderField: k) }

            let data: Data
            let resp: URLResponse
            do {
                (data, resp) = try await session.data(for: req)
            } catch {
                AppLogger.shared.log(
                    "Request failed: [Plex] \(method) \(path); endpoint=\(connection.kind.rawValue); error=\(error.localizedDescription)",
                    category: .networking,
                    level: .error
                )
                lastError = .serverUnreachable
                if !canRetry {
                    Task { await self.refreshConnection(preferLocal: !UserDefaults.standard.bool(forKey: "networkIsCellular")) }
                }
                continue
            }
            if let http = resp as? HTTPURLResponse {
                AppLogger.shared.log(
                    "Response received: [Plex] \(method) \(path); endpoint=\(connection.kind.rawValue); status=\(http.statusCode); bytes=\(data.count); elapsedMs=\(Int((ProcessInfo.processInfo.systemUptime - started) * 1000))",
                    category: .networking,
                    level: (200...299).contains(http.statusCode) ? .info : .warning
                )
                if http.statusCode == 401 || http.statusCode == 403 {
                    throw SubsonicError.invalidCredentials
                }
                if !(200...299).contains(http.statusCode) {
                    lastError = .server(code: http.statusCode, message: "HTTP \(http.statusCode)")
                    let isRetryableGatewayFailure = [502, 503, 504].contains(http.statusCode)
                    if canRetry && isRetryableGatewayFailure && index < attempts.count - 1 { continue }
                    throw lastError
                }
            }
            setActiveConnection(connection.url, reason: index == 0 ? "request succeeded" : "request failover")
            return (try? JSONDecoder().decode(PXResponse.self, from: data))?.MediaContainer
        }
        throw lastError
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
            albumArtist: m.grandparentTitle,
            albumId: m.parentRatingKey,
            artistId: m.grandparentRatingKey,
            albumArtistId: m.grandparentRatingKey,
            coverArt: m.thumb ?? m.parentThumb ?? m.grandparentThumb,
            duration: m.duration.map { $0 / 1000 },
            track: m.index,
            discNumber: m.parentIndex,
            year: m.year,
            genre: m.Genre?.first?.tag,
            size: part?.size,
            contentType: nil,
            suffix: container?.lowercased(),
            codec: (audio?.codec ?? media?.audioCodec)?.lowercased(),
            bitRate: media?.bitrate,
            path: part?.file,
            playCount: m.viewCount,
            bpm: nil,                          // Plex does not expose BPM
            explicitStatus: nil,
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

    // MARK: - Folder browsing (artist -> album -> track)

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

    // MARK: - Lyrics

    func lyricsBySongId(id: String) async throws -> LyricsList? {
        guard let meta = try? await metadata("/library/metadata/\(id)").first else { return nil }
        let mediaItems: [PXMedia] = meta.Media ?? []
        let parts: [PXPart] = mediaItems.flatMap { $0.Part ?? [] }
        let streams: [PXStream] = parts
            .flatMap { $0.Stream ?? [] }
            .filter { $0.streamType == 4 }

        // Plex normally exposes LRC/TXT, but custom providers may expose TTML.
        // Try every lyric stream and sniff the bytes when codec metadata is
        // absent or inaccurate instead of assuming the first stream is LRC.
        var plainFallback: LyricsList?
        for stream in streams {
            guard let streamKey = stream.key, let streamURL = url(streamKey) else { continue }
            var request = URLRequest(url: streamURL)
            for (key, value) in Self.plexHeaders(clientId: clientId) {
                request.setValue(value, forHTTPHeaderField: key)
            }
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { continue }
            let hint = stream.codec ?? stream.format ?? http.value(forHTTPHeaderField: "Content-Type")
            if let parsed = LyricsParser.parse(data: data, formatHint: hint) {
                if parsed.lines.allSatisfy({ $0.time >= 0 }) {
                    return parsed.lyricsList
                }
                if plainFallback == nil { plainFallback = parsed.lyricsList }
            }
        }
        return plainFallback
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
        // Serve the original file unless the user actually asked for a transcode.
        if !StreamingPreferences.wantsTranscode(bitrateKbps: kbps), let part = cachedPart(id) {
            return url(part)   // original file, direct play
        }
        return transcodeURL(id: id, bitrateKbps: kbps > 0 ? kbps : 320)
    }

    func downloadURL(id: String) -> URL? {
        let kbps = StreamingPreferences.downloadBitrateKbps
        if !StreamingPreferences.wantsTranscode(bitrateKbps: kbps), let part = cachedPart(id) {
            return url(part)   // exact original bytes
        }
        return transcodeURL(id: id, bitrateKbps: kbps > 0 ? kbps : 320)
    }

    // Capped/format downloads use Plex's progressive transcoder; original uses the file part.
    func downloadIsProgressive(id: String) -> Bool {
        let kbps = StreamingPreferences.downloadBitrateKbps
        if !StreamingPreferences.wantsTranscode(bitrateKbps: kbps), cachedPart(id) != nil { return false }
        return true
    }

    // The original-file path needs the cached part key; transcodes don't.
    func streamMetadataReady(id: String) -> Bool {
        StreamingPreferences.wantsTranscode(bitrateKbps: StreamingPreferences.streamBitrateKbps)
            || cachedPart(id) != nil
    }

    // Cache the file part key for original-file streaming.
    func prepareForPlayback(id: String) async {
        guard cachedPart(id) == nil else { return }
        _ = try? await song(id: id)
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

}
