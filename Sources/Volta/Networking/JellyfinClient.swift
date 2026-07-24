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
            .playlistReordering,
        ]
        if flavor == .jellyfin { caps.insert(.syncedLyrics) }
        return caps
    }

    static let clientName = "Volta"
    static let clientVersion = "1.0"

    private var backend: BackendBehavior { BackendBehavior(flavor: flavor) }

    private struct BackendBehavior {
        let flavor: Flavor

        var label: String {
            flavor == .emby ? "Emby" : "Jellyfin"
        }

        var authorizationHeaderField: String {
            flavor == .emby ? "X-Emby-Authorization" : "Authorization"
        }

        var authorizationScheme: String {
            flavor == .emby ? "Emby" : "MediaBrowser"
        }

        var sendsTokenHeader: Bool {
            flavor == .emby
        }

        var itemFields: String {
            switch flavor {
            case .jellyfin:
                return "Genres,DateCreated,MediaSources,Path,Overview,ChildCount,ProductionYear,ParentIndexNumber,IndexNumber,ImageTags,PrimaryImageTag,PrimaryImageItemId,AlbumPrimaryImageTag"
            case .emby:
                return "Genres,DateCreated,MediaSources,Path,Overview"
            }
        }

        func authorizationValue(clientName: String, clientVersion: String, deviceId: String, token: String?) -> String {
            var parts = [
                "Client=\"\(clientName)\"",
                "Device=\"iPhone\"",
                "DeviceId=\"\(deviceId)\"",
                "Version=\"\(clientVersion)\"",
            ]
            if let token { parts.append("Token=\"\(token)\"") }
            return authorizationScheme + " " + parts.joined(separator: ", ")
        }

        func applyAuthentication(
            to request: inout URLRequest,
            clientName: String,
            clientVersion: String,
            deviceId: String,
            token: String?
        ) {
            request.setValue(
                authorizationValue(
                    clientName: clientName,
                    clientVersion: clientVersion,
                    deviceId: deviceId,
                    token: token
                ),
                forHTTPHeaderField: authorizationHeaderField
            )
            if sendsTokenHeader, let token {
                request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
            }
        }

        func tokenQueryItems(token: String) -> [URLQueryItem] {
            var items = [URLQueryItem(name: "api_key", value: token)]
            if sendsTokenHeader {
                items.append(URLQueryItem(name: "X-Emby-Token", value: token))
            }
            return items
        }
    }

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
        stub.backend.applyAuthentication(
            to: &req,
            clientName: Self.clientName,
            clientVersion: Self.clientVersion,
            deviceId: deviceId,
            token: nil
        )
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

    // MARK: - URL + request plumbing

    func url(_ path: String, query: [URLQueryItem] = []) -> URL? {
        guard var comps = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false) else { return nil }
        var base = comps.percentEncodedPath
        if base.hasSuffix("/") { base.removeLast() }
        comps.percentEncodedPath = Self.joinedBasePath(base, endpoint: path)
        comps.queryItems = query.isEmpty ? nil : query
        return comps.url
    }

    private struct ResponsePayload {
        let data: Data
        let response: HTTPURLResponse?
        let url: URL
    }

    private func requestPayload(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Any? = nil) async throws -> ResponsePayload {
        try await DeveloperSimulation.prepareRequest(endpoint: path)
        let started = ProcessInfo.processInfo.systemUptime
        guard let url = url(path, query: query) else { throw SubsonicError.invalidResponse }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        backend.applyAuthentication(
            to: &req,
            clientName: Self.clientName,
            clientVersion: Self.clientVersion,
            deviceId: deviceId,
            token: token
        )
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        AppLogger.shared.log(
            "Request started: [\(backend.label)] \(method) \(path); url=\(Self.redactedURLString(url))",
            category: .networking
        )
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch is CancellationError {
            AppLogger.shared.log(
                "Request cancelled: [\(backend.label)] \(method) \(path); url=\(Self.redactedURLString(url))",
                category: .networking
            )
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled {
                AppLogger.shared.log(
                    "Request cancelled: [\(backend.label)] \(method) \(path); url=\(Self.redactedURLString(url))",
                    category: .networking
                )
                throw CancellationError()
            }
            let message = Self.networkFailureMessage(error, url: url)
            AppLogger.shared.log(
                "Request failed: [\(backend.label)] \(method) \(path); url=\(Self.redactedURLString(url)); error=\(message)",
                category: .networking,
                level: .error
            )
            throw SubsonicError.server(code: error.errorCode, message: message)
        } catch {
            AppLogger.shared.log(
                "Request failed: [\(backend.label)] \(method) \(path); url=\(Self.redactedURLString(url)); error=\(error.localizedDescription)",
                category: .networking,
                level: .error
            )
            throw SubsonicError.serverUnreachable
        }
        if let http = response as? HTTPURLResponse {
            let contentType = Self.contentType(from: http)
            AppLogger.shared.log(
                "Response received: [\(backend.label)] \(method) \(path); url=\(Self.redactedURLString(url)); status=\(http.statusCode); contentType=\(contentType); bytes=\(data.count); elapsedMs=\(Int((ProcessInfo.processInfo.systemUptime - started) * 1000))",
                category: .networking,
                level: (200...299).contains(http.statusCode) ? .info : .warning
            )
            if http.statusCode == 401 { throw SubsonicError.invalidCredentials }
            if !(200...299).contains(http.statusCode) {
                let message = httpFailureMessage(status: http.statusCode, contentType: contentType, data: data, path: path)
                AppLogger.shared.log(
                    "Request failed: [\(backend.label)] \(method) \(path); url=\(Self.redactedURLString(url)); status=\(http.statusCode); contentType=\(contentType); bytes=\(data.count); body=\(safeBodySnippet(data: data, contentType: contentType))",
                    category: .networking,
                    level: .error
                )
                throw SubsonicError.server(code: http.statusCode, message: message)
            }
            return ResponsePayload(data: data, response: http, url: url)
        }
        return ResponsePayload(data: data, response: nil, url: url)
    }

    private func request(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Any? = nil) async throws -> Data {
        try await requestPayload(method, path, query: query, body: body).data
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type) async throws -> T {
        let payload = try await requestPayload("GET", path, query: query)
        do {
            return try JSONDecoder().decode(T.self, from: payload.data)
        } catch {
            let contentType = payload.response.map(Self.contentType(from:)) ?? "unknown"
            AppLogger.shared.log(
                "Decode failed: [\(backend.label)] GET \(path); url=\(Self.redactedURLString(payload.url)); status=\(payload.response?.statusCode ?? 0); contentType=\(contentType); bytes=\(payload.data.count); error=\(error); body=\(safeBodySnippet(data: payload.data, contentType: contentType))",
                category: .networking,
                level: .error
            )
            throw SubsonicError.invalidResponse
        }
    }

    private func getWithFallbacks<T: Decodable>(_ path: String, queryVariants: [[URLQueryItem]], as type: T.Type) async throws -> T {
        var lastError: Error?
        for (index, query) in queryVariants.enumerated() {
            do {
                return try await get(path, query: query, as: type)
            } catch {
                lastError = error
                guard flavor == .emby,
                      index < queryVariants.count - 1,
                      Self.isEmbyCompatibilityError(error) else {
                    throw error
                }
                AppLogger.shared.log(
                    "Retrying request with Emby-compatible fallback: [Emby] GET \(path); attempt=\(index + 2)",
                    category: .networking,
                    level: .warning
                )
            }
        }
        throw lastError ?? SubsonicError.invalidResponse
    }

    private func getItems(_ path: String, query: [URLQueryItem]) async throws -> JFItemsResponse {
        try await getWithFallbacks(path, queryVariants: embyCompatibilityQueryVariants(query), as: JFItemsResponse.self)
    }

    private static func joinedBasePath(_ base: String, endpoint rawEndpoint: String) -> String {
        var endpoint = rawEndpoint.hasPrefix("/") ? rawEndpoint : "/" + rawEndpoint
        guard !base.isEmpty else { return endpoint }

        let baseParts = base.split(separator: "/", omittingEmptySubsequences: true)
        var endpointParts = endpoint.split(separator: "/", omittingEmptySubsequences: true)
        if let lastBase = baseParts.last,
           let firstEndpoint = endpointParts.first,
           lastBase.lowercased() == firstEndpoint.lowercased() {
            endpointParts.removeFirst()
            endpoint = endpointParts.isEmpty ? "" : "/" + endpointParts.joined(separator: "/")
        }
        return base + endpoint
    }

    private static func contentType(from response: HTTPURLResponse) -> String {
        response.value(forHTTPHeaderField: "Content-Type") ?? response.mimeType ?? "unknown"
    }

    private static func redactedURLString(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return url.absoluteString
        }
        components.queryItems = queryItems.map { item in
            let lower = item.name.lowercased()
            if lower.contains("token") || lower.contains("api_key") || lower.contains("password") || lower == "pw" {
                return URLQueryItem(name: item.name, value: "<redacted>")
            }
            return item
        }
        return components.url?.absoluteString ?? url.absoluteString
    }

    private static func networkFailureMessage(_ error: URLError, url: URL) -> String {
        let prefix: String
        switch error.code {
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            prefix = "TLS/certificate failure"
        case .cannotFindHost, .dnsLookupFailed:
            prefix = "DNS failure"
        case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .timedOut:
            prefix = "Network failure"
        case .httpTooManyRedirects, .redirectToNonExistentLocation:
            prefix = "Redirect failure"
        default:
            prefix = "Network failure"
        }
        return "\(prefix) for \(url.host ?? "server"): \(error.localizedDescription)"
    }

    private func httpFailureMessage(status: Int, contentType: String, data: Data, path: String) -> String {
        let body = safeBodySnippet(data: data, contentType: contentType)
        if Self.looksLikeHTML(contentType: contentType, body: body) {
            return "HTTP \(status) from \(backend.label) \(path): HTML response from proxy or server"
        }
        guard !body.isEmpty else {
            return "HTTP \(status) from \(backend.label) \(path)"
        }
        return "HTTP \(status) from \(backend.label) \(path): \(body)"
    }

    private func safeBodySnippet(data: Data, contentType: String) -> String {
        guard !data.isEmpty,
              var text = String(data: data, encoding: .utf8) else {
            return ""
        }
        if !token.isEmpty {
            text = text.replacingOccurrences(of: token, with: "<redacted>")
        }
        if !config.password.isEmpty {
            text = text.replacingOccurrences(of: config.password, with: "<redacted>")
        }
        text = text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        if text.count > 600 {
            return String(text.prefix(600)) + "…"
        }
        return text
    }

    private static func looksLikeHTML(contentType: String, body: String) -> Bool {
        let type = contentType.lowercased()
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return type.contains("text/html") || trimmed.hasPrefix("<!doctype html") || trimmed.hasPrefix("<html")
    }

    private static func isEmbyCompatibilityError(_ error: Error) -> Bool {
        guard case SubsonicError.server(let code, _) = error else { return false }
        return code == 400 || code == 404
    }

    private func embyCompatibilityQueryVariants(_ query: [URLQueryItem]) -> [[URLQueryItem]] {
        guard flavor == .emby else { return [query] }

        var variants: [[URLQueryItem]] = [query]
        let withoutFields = query.filter { $0.name.caseInsensitiveCompare("Fields") != .orderedSame }
        if withoutFields.count != query.count {
            variants.append(withoutFields)
        }

        if let sort = query.first(where: { $0.name.caseInsensitiveCompare("SortBy") == .orderedSame })?.value,
           sort.contains(",") {
            let primarySort = sort.split(separator: ",", maxSplits: 1).first.map(String.init) ?? sort
            variants.append(Self.replacingQueryItem("SortBy", in: query, with: primarySort))
            variants.append(Self.replacingQueryItem("SortBy", in: withoutFields, with: primarySort))
        }

        if query.contains(where: { $0.name.caseInsensitiveCompare("Filters") == .orderedSame }) {
            variants.append(query.filter { $0.name.caseInsensitiveCompare("Filters") != .orderedSame })
            variants.append(withoutFields.filter { $0.name.caseInsensitiveCompare("Filters") != .orderedSame })
        }

        if query.contains(where: { $0.name.caseInsensitiveCompare("SortBy") == .orderedSame }) {
            variants.append(Self.replacingQueryItem("SortBy", in: withoutFields, with: "SortName"))
        }

        return Self.uniqueQueryVariants(variants)
    }

    private static func replacingQueryItem(_ name: String, in query: [URLQueryItem], with value: String) -> [URLQueryItem] {
        query.map { item in
            item.name.caseInsensitiveCompare(name) == .orderedSame
                ? URLQueryItem(name: item.name, value: value)
                : item
        }
    }

    private static func uniqueQueryVariants(_ variants: [[URLQueryItem]]) -> [[URLQueryItem]] {
        var seen = Set<String>()
        return variants.filter { variant in
            let key = variant.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
            return seen.insert(key).inserted
        }
    }

    // Common item query fields so one decode covers albums/songs/artists/playlists.
    private func itemFieldsQuery(
        _ extra: [URLQueryItem],
        recursive: Bool = false,
        includeImages: Bool = true
    ) -> [URLQueryItem] {
        var query: [URLQueryItem] = []
        if recursive {
            query.append(URLQueryItem(name: "Recursive", value: "true"))
        }
        if includeImages {
            query.append(URLQueryItem(name: "ImageTypeLimit", value: "1"))
            query.append(URLQueryItem(name: "EnableImageTypes", value: "Primary"))
        }
        let fields = backend.itemFields
        if !fields.isEmpty {
            query.append(URLQueryItem(name: "Fields", value: fields))
        }
        query.append(contentsOf: extra)
        return query
    }

    private func itemsQuery(_ extra: [URLQueryItem]) -> [URLQueryItem] {
        itemFieldsQuery(extra, recursive: true)
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
        let res = try await getItems("/Users/\(userId)/Items", query: itemsQuery(q))
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
        if flavor == .emby {
            let meta = try await get("/Users/\(userId)/Items/\(id)", as: JFItem.self)
            let tracks = try await getItems("/Users/\(userId)/Items", query: itemsQuery([
                URLQueryItem(name: "ParentId", value: id),
                URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
                URLQueryItem(name: "SortBy", value: "ParentIndexNumber,IndexNumber,SortName"),
                URLQueryItem(name: "SortOrder", value: "Ascending"),
            ]))
            let songs = tracks.Items?.map { $0.asSong } ?? []
            return meta.asAlbum(withSongs: songs)
        }
        async let metaTask = try? get("/Users/\(userId)/Items/\(id)", as: JFItem.self)
        async let tracksTask = try? getItems("/Users/\(userId)/Items", query: itemsQuery([
            URLQueryItem(name: "ParentId", value: id),
            URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
            URLQueryItem(name: "SortBy", value: "ParentIndexNumber,IndexNumber,SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
        ]))
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
        let res = try await getItems("/Artists/AlbumArtists", query: itemFieldsQuery([
            URLQueryItem(name: "UserId", value: userId),
        ]))
        return (res.Items ?? []).map { $0.asArtist }
    }

    func artist(id: String) async throws -> Artist? {
        if flavor == .emby {
            let meta = try await get("/Users/\(userId)/Items/\(id)", as: JFItem.self)
            let albumRes = try await getItems("/Users/\(userId)/Items", query: itemsQuery([
                URLQueryItem(name: "AlbumArtistIds", value: id),
                URLQueryItem(name: "IncludeItemTypes", value: "MusicAlbum"),
                URLQueryItem(name: "SortBy", value: "ProductionYear,SortName"),
                URLQueryItem(name: "SortOrder", value: "Ascending"),
            ]))
            let albums = albumRes.Items?.map { $0.asAlbum } ?? []
            return meta.asArtist(withAlbums: albums)
        }
        async let metaTask = try? get("/Users/\(userId)/Items/\(id)", as: JFItem.self)
        async let albumsTask = try? getItems("/Users/\(userId)/Items", query: itemsQuery([
            URLQueryItem(name: "AlbumArtistIds", value: id),
            URLQueryItem(name: "IncludeItemTypes", value: "MusicAlbum"),
            URLQueryItem(name: "SortBy", value: "ProductionYear,SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
        ]))
        guard let meta = await metaTask else { return nil }
        let albums = (await albumsTask)?.Items?.map { $0.asAlbum } ?? []
        return meta.asArtist(withAlbums: albums)
    }

    func artistInfo(id: String) async throws -> ArtistInfo? {
        if flavor == .emby {
            let meta = try? await get("/Users/\(userId)/Items/\(id)", as: JFItem.self)
            let similar = (try? await getItems("/Artists/\(id)/Similar", query: itemFieldsQuery([
                URLQueryItem(name: "UserId", value: userId),
                URLQueryItem(name: "Limit", value: "20"),
            ])))?.Items?.map { $0.asArtist } ?? []
            let image = meta.flatMap { coverArtURL(id: $0.asArtist.coverArt, size: 600)?.absoluteString }
            return ArtistInfo(
                biography: meta?.Overview,
                similarArtist: similar,
                smallImageUrl: nil,
                mediumImageUrl: nil,
                largeImageUrl: image
            )
        }
        async let metaTask = try? get("/Users/\(userId)/Items/\(id)", as: JFItem.self)
        async let similarTask = try? getItems("/Artists/\(id)/Similar", query: itemFieldsQuery([
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "Limit", value: "20"),
        ]))
        let meta = await metaTask
        let similar = (await similarTask)?.Items?.map { $0.asArtist } ?? []
        let image = meta.flatMap { coverArtURL(id: $0.asArtist.coverArt, size: 600)?.absoluteString }
        return ArtistInfo(
            biography: meta?.Overview,
            similarArtist: similar,
            smallImageUrl: nil,
            mediumImageUrl: nil,
            largeImageUrl: image
        )
    }

    func songsForArtist(id: String) async throws -> [Song] {
        let res = try await getItems("/Users/\(userId)/Items", query: itemsQuery([
            URLQueryItem(name: "ArtistIds", value: id),
            URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
            URLQueryItem(name: "SortBy", value: "Album,ParentIndexNumber,IndexNumber,SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
        ]))
        return (res.Items ?? []).map { $0.asSong }
    }

    // No topSongs endpoint; resolve the artist and sort by play count.
    func topSongs(artistName: String, count: Int) async throws -> [Song] {
        let hits = try await getItems("/Users/\(userId)/Items", query: itemsQuery([
            URLQueryItem(name: "IncludeItemTypes", value: "MusicArtist"),
            URLQueryItem(name: "SearchTerm", value: artistName),
            URLQueryItem(name: "Limit", value: "1"),
        ]))
        guard let artistId = hits.Items?.first?.Id else { return [] }
        let res = try await getItems("/Users/\(userId)/Items", query: itemsQuery([
            URLQueryItem(name: "ArtistIds", value: artistId),
            URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
            URLQueryItem(name: "SortBy", value: "PlayCount,SortName"),
            URLQueryItem(name: "SortOrder", value: "Descending"),
            URLQueryItem(name: "Limit", value: String(count)),
        ]))
        return (res.Items ?? []).map { $0.asSong }
    }

    // MARK: - Songs

    func song(id: String) async throws -> Song? {
        do {
            return try await get("/Users/\(userId)/Items/\(id)", as: JFItem.self).asSong
        } catch SubsonicError.server(let code, _) where code == 404 {
            return nil
        }
    }

    func randomSongs(size: Int) async throws -> [Song] {
        let res = try await getItems("/Users/\(userId)/Items", query: itemsQuery([
            URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
            URLQueryItem(name: "SortBy", value: "Random"),
            URLQueryItem(name: "Limit", value: String(size)),
        ]))
        return (res.Items ?? []).map { $0.asSong }
    }

    func songsByGenre(_ genre: String, count: Int, offset: Int) async throws -> [Song] {
        let res = try await getItems("/Users/\(userId)/Items", query: itemsQuery([
            URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
            URLQueryItem(name: "Genres", value: genre),
            URLQueryItem(name: "SortBy", value: "Random"),
            URLQueryItem(name: "Limit", value: String(count)),
            URLQueryItem(name: "StartIndex", value: String(offset)),
        ]))
        return (res.Items ?? []).map { $0.asSong }
    }

    // MARK: - Search

    func search(query: String, artistCount: Int, albumCount: Int, songCount: Int) async throws -> (artists: [Artist], albums: [Album], songs: [Song]) {
        @Sendable func find(_ types: String, _ limit: Int) async -> [JFItem] {
            guard limit > 0 else { return [] }
            let res = try? await getItems("/Users/\(userId)/Items", query: itemsQuery([
                URLQueryItem(name: "IncludeItemTypes", value: types),
                URLQueryItem(name: "SearchTerm", value: query),
                URLQueryItem(name: "Limit", value: String(limit)),
            ]))
            return res?.Items ?? []
        }
        if flavor == .emby {
            let artistItems = await find("MusicArtist", artistCount)
            let albumItems = await find("MusicAlbum", albumCount)
            let songItems = await find("Audio", songCount)
            return (artistItems.map { $0.asArtist },
                    albumItems.map { $0.asAlbum },
                    songItems.map { $0.asSong })
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
        let res = try await getItems("/Users/\(userId)/Items", query: itemsQuery([
            URLQueryItem(name: "IncludeItemTypes", value: "Playlist"),
            URLQueryItem(name: "SortBy", value: "SortName"),
        ]))
        return (res.Items ?? []).map { $0.asPlaylist }
    }

    func playlist(id: String) async throws -> Playlist? {
        async let metaTask = try? get("/Users/\(userId)/Items/\(id)", as: JFItem.self)
        async let itemsTask = try? getItems("/Playlists/\(id)/Items", query: itemFieldsQuery([
            URLQueryItem(name: "UserId", value: userId),
        ]))
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
        let items = try await getItems("/Playlists/\(playlistID)/Items", query: itemFieldsQuery([
            URLQueryItem(name: "UserId", value: userId),
        ], includeImages: false))
        guard let entryId = items.Items?[safe: index]?.PlaylistItemId else { return }
        _ = try await request("DELETE", "/Playlists/\(playlistID)/Items", query: [
            URLQueryItem(name: "EntryIds", value: entryId),
        ])
    }

    func replacePlaylistSongs(playlistID: String, songIDs: [String]) async throws {
        let items = try await getItems("/Playlists/\(playlistID)/Items", query: itemFieldsQuery([
            URLQueryItem(name: "UserId", value: userId),
        ], includeImages: false)).Items ?? []

        var entries: [(songID: String, playlistItemID: String)] = items.compactMap { item in
            guard let playlistItemID = item.PlaylistItemId else { return nil }
            return (item.Id, playlistItemID)
        }

        var used = Set<Int>()
        let targetOrder: [(songID: String, playlistItemID: String)] = songIDs.compactMap { songID in
            guard let index = entries.indices.first(where: { entries[$0].songID == songID && !used.contains($0) }) else {
                return nil
            }
            used.insert(index)
            return entries[index]
        }
        guard targetOrder.count == entries.count, targetOrder.count == songIDs.count else {
            throw SubsonicError.invalidResponse
        }

        for targetIndex in targetOrder.indices {
            let target = targetOrder[targetIndex]
            guard let currentIndex = entries.firstIndex(where: { $0.playlistItemID == target.playlistItemID }),
                  currentIndex != targetIndex else { continue }
            _ = try await request("POST", "/Playlists/\(playlistID)/Items/\(target.playlistItemID)/Move/\(targetIndex)")
            let moved = entries.remove(at: currentIndex)
            entries.insert(moved, at: targetIndex)
        }
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
        let res = try await getItems("/Users/\(userId)/Items", query: itemFieldsQuery(q))
        return (res.Items ?? []).map { $0.asBrowseEntry }
    }

    func musicDirectory(id: String) async throws -> [BrowseEntry] {
        let res = try await getItems("/Users/\(userId)/Items", query: itemsQuery([
            URLQueryItem(name: "ParentId", value: id),
            URLQueryItem(name: "SortBy", value: "IsFolder,ParentIndexNumber,IndexNumber,SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
        ]))
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
            offset: nil,
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
        imageURL(id: id, size: size, format: nil, keepAnimation: false, enableImageEnhancers: nil)
    }

    func liveArtworkURLs(id: String?) -> [URL] {
        guard flavor == .emby else {
            return coverArtURL(id: id).map { [$0] } ?? []
        }
        // Emby's documented animated-image contract supports `original` and
        // `gif`, but not `webp`. Asking Emby to convert to WebP can flatten an
        // animated source to a single frame even with keepAnimation enabled.
        // Prefer the canonical, non-indexed endpoint because it works across
        // current servers, then retain the legacy /0 shape as a fallback.
        return Self.uniqueURLs([
            imageURL(id: id, size: nil, format: "original", keepAnimation: true, enableImageEnhancers: false, index: nil),
            imageURL(id: id, size: nil, format: "original", keepAnimation: true, enableImageEnhancers: false, index: 0),
            imageURL(id: id, size: nil, format: nil, keepAnimation: true, enableImageEnhancers: false, index: nil),
            imageURL(id: id, size: nil, format: nil, keepAnimation: true, enableImageEnhancers: false, index: 0),
            imageURL(id: id, size: nil, format: "gif", keepAnimation: true, enableImageEnhancers: false, index: nil),
            imageURL(id: id, size: nil, format: "gif", keepAnimation: true, enableImageEnhancers: false, index: 0),
        ].compactMap { $0 })
    }

    private func imageURL(
        id: String?,
        size: Int?,
        format: String?,
        keepAnimation: Bool,
        enableImageEnhancers: Bool?,
        index: Int? = nil
    ) -> URL? {
        guard let id, !id.isEmpty else { return nil }
        let image = Self.imageIDParts(from: id)
        var q = backend.tokenQueryItems(token: token)
        if let tag = image.tag {
            q.append(URLQueryItem(name: "tag", value: tag))
        }
        if let format {
            q.append(URLQueryItem(name: "format", value: format))
        }
        if keepAnimation {
            q.append(URLQueryItem(name: "keepAnimation", value: "true"))
        }
        if let enableImageEnhancers {
            q.append(URLQueryItem(name: "enableImageEnhancers", value: enableImageEnhancers ? "true" : "false"))
        }
        if let size {
            q.append(URLQueryItem(name: "maxWidth", value: String(size)))
            q.append(URLQueryItem(name: "maxHeight", value: String(size)))
        }
        let indexPath = index.map { "/\($0)" } ?? ""
        return url("/Items/\(image.id)/Images/Primary\(indexPath)", query: q)
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    func streamURL(id: String) -> URL? {
        audioURL(id: id, decision: StreamingPreferences.streamDecision(for: nil))
    }

    func streamURL(for song: Song) -> URL? {
        audioURL(id: song.id, decision: StreamingPreferences.streamDecision(for: song))
    }

    func downloadURL(id: String) -> URL? {
        audioURL(id: id, decision: StreamingPreferences.downloadDecision(for: nil))
    }

    func downloadURL(for song: Song) -> URL? {
        audioURL(id: song.id, decision: StreamingPreferences.downloadDecision(for: song))
    }

    func originalStreamURL(id: String) -> URL? {
        var q = backend.tokenQueryItems(token: token)
        q.append(contentsOf: [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "DeviceId", value: deviceId),
        ])
        return url("/Audio/\(id)/stream", query: q)
    }

    func mediaRequestHeaders() -> [String: String] {
        var headers = [
            backend.authorizationHeaderField: backend.authorizationValue(
                clientName: Self.clientName,
                clientVersion: Self.clientVersion,
                deviceId: deviceId,
                token: token
            )
        ]
        if backend.sendsTokenHeader {
            headers["X-Emby-Token"] = token
        }
        return headers
    }

    func downloadIsProgressive(id: String) -> Bool {
        StreamingPreferences.downloadDecision(for: nil).wantsTranscode
    }

    func downloadIsProgressive(for song: Song) -> Bool {
        StreamingPreferences.downloadDecision(for: song).wantsTranscode
    }

    // Original bytes unless the user asked for a transcode.
    private func audioURL(id: String, decision: StreamingTranscodeDecision) -> URL? {
        guard decision.wantsTranscode else {
            return originalStreamURL(id: id)
        }
        var q = backend.tokenQueryItems(token: token) + [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "DeviceId", value: deviceId),
        ]
        q.append(URLQueryItem(name: "MaxStreamingBitrate", value: String(decision.bitrateKbps * 1000)))
        let codec = decision.format.map { jellyfinCodec(for: $0) } ?? "aac"
        q.append(URLQueryItem(name: "AudioCodec", value: codec))

        if flavor == .emby || codec == "aac" {
            q.append(URLQueryItem(name: "static", value: "false"))
            q.append(URLQueryItem(name: "Container", value: embyContainer(forCodec: codec)))
            return url("/Audio/\(id)/stream", query: q)
        }

        q.append(contentsOf: [
            URLQueryItem(name: "TranscodingContainer", value: "ts"),
            URLQueryItem(name: "TranscodingProtocol", value: "hls"),
            URLQueryItem(name: "Container", value: "flac,alac,aac,m4a,mp3,opus,ogg,wav,webma"),
        ])
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

    private func embyContainer(forCodec codec: String) -> String {
        switch codec.lowercased() {
        case "mp3": return "mp3"
        case "opus": return "opus"
        case "vorbis": return "ogg"
        default: return "m4a"
        }
    }

    private static func imageIDParts(from raw: String) -> (id: String, tag: String?) {
        guard let range = raw.range(of: "::", options: .backwards) else {
            return (raw, nil)
        }
        let id = String(raw[..<range.lowerBound])
        let tag = String(raw[range.upperBound...])
        guard !id.isEmpty, !tag.isEmpty else { return (raw, nil) }
        return (id, tag)
    }
}

// MARK: - Safe index

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
