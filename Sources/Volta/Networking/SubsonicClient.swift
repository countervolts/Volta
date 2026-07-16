import Foundation

struct SubsonicConfig: Sendable, Hashable, Codable {
    var baseURL: URL
    var username: String
    var password: String
    // Populated only for Plex account discovery. Other backends leave this
    // empty and continue to use a single base URL.
    var plexConnections: [PlexConnectionEndpoint]

    init(
        baseURL: URL,
        username: String,
        password: String,
        plexConnections: [PlexConnectionEndpoint] = []
    ) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
        self.plexConnections = plexConnections
    }

    private enum CodingKeys: String, CodingKey {
        case baseURL, username, password, plexConnections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try container.decode(URL.self, forKey: .baseURL)
        username = try container.decode(String.self, forKey: .username)
        password = try container.decode(String.self, forKey: .password)
        plexConnections = try container.decodeIfPresent(
            [PlexConnectionEndpoint].self,
            forKey: .plexConnections
        ) ?? []
    }

    // Normalize user-entered server roots. Defaults to https when no scheme is given.
    static func normalizedURL(from raw: String, kind: MusicBackendKind? = nil) -> URL? {
        candidateURLs(from: raw, kind: kind).first
    }

    private static func normalizedURLCandidate(_ raw: String) -> URL? {
        let cleaned = sanitizedInput(raw)
        guard !cleaned.isEmpty else { return nil }
        let text = hasExplicitScheme(cleaned) ? cleaned : "https://" + cleaned
        return URLComponents(string: text)?.url
    }

    // Whether the user explicitly typed an http:// or https:// scheme.
    static func hasExplicitScheme(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text.hasPrefix("http://") || text.hasPrefix("https://")
    }

    // Server roots to try when logging in, in priority order. If the user typed
    // a scheme we honour it exactly; otherwise we probe https first then http.
    static func candidateURLs(from raw: String, kind: MusicBackendKind? = nil) -> [URL] {
        let cleaned = sanitizedInput(raw)
        guard !cleaned.isEmpty else { return [] }
        let rawCandidates: [String]
        if hasExplicitScheme(cleaned) {
            rawCandidates = [cleaned]
        } else {
            rawCandidates = ["https://" + cleaned, "http://" + cleaned]
        }
        return uniqueURLs(rawCandidates.flatMap { urlCandidates(from: $0, kind: kind) })
    }

    // Normalize pasted server roots.
    private static func sanitizedInput(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hash = text.firstIndex(of: "#") { text = String(text[..<hash]) }
        // Strip a pasted Subsonic API path (e.g. ".../rest" or ".../rest/ping.view"),
        // but only at a real path boundary so hosts like "my.com/restful" survive.
        if let restRange = text.range(of: "/rest", options: .caseInsensitive) {
            let after = text[restRange.upperBound...]
            if let next = after.first {
                if next == "/" || next == "." || next == "?" {
                    text = String(text[..<restRange.lowerBound])
                }
            } else {
                text = String(text[..<restRange.lowerBound])
            }
        }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    private static func urlCandidates(from raw: String, kind: MusicBackendKind?) -> [URL] {
        guard let url = normalizedURLCandidate(raw) else { return [] }
        guard let kind,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.port == nil,
              components.host != nil else {
            return [url]
        }
        let portCandidates = defaultPorts(for: kind, scheme: components.scheme)
        guard !portCandidates.isEmpty else { return [url] }
        return [url] + portCandidates.compactMap { port in
            components.port = port
            return components.url
        }
    }

    private static func defaultPorts(for kind: MusicBackendKind, scheme: String?) -> [Int] {
        switch kind {
        case .subsonic:
            return [4533, 4040]
        case .jellyfin, .emby:
            return (scheme?.lowercased() == "https") ? [8920] : [8096]
        case .plex:
            return [32400]
        }
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            let key = url.absoluteString
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }
}

struct SubsonicClient: Sendable {
    let config: SubsonicConfig
    let session: URLSession

    let backendKind: MusicBackendKind = .subsonic
    // Reference backend: most Volta features map directly here.
    let capabilities: MusicServiceCapabilities = .subsonicFull

    static let clientName = "Volta"
    static let apiVersion = "1.16.1"

    init(config: SubsonicConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    private func authQuery() -> [URLQueryItem] {
        let salt = Crypto.randomSalt()
        let token = Crypto.subsonicToken(password: config.password, salt: salt)
        return [
            URLQueryItem(name: "u", value: config.username),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: Self.apiVersion),
            URLQueryItem(name: "c", value: Self.clientName),
            URLQueryItem(name: "f", value: "json"),
        ]
    }

    func makeURL(endpoint: String, query: [URLQueryItem] = []) -> URL? {
        guard var comps = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var path = comps.path
        if path.hasSuffix("/") { path.removeLast() }
        comps.path = path + "/rest/" + endpoint
        comps.queryItems = authQuery() + query
        return comps.url
    }

    // Decode a response and normalize failures to SubsonicError.
    func request(_ endpoint: String, query: [URLQueryItem] = []) async throws -> SubsonicEnvelope.Body {
        try await DeveloperSimulation.prepareRequest(endpoint: endpoint)
        let started = ProcessInfo.processInfo.systemUptime
        AppLogger.shared.log("Request started: [Subsonic] \(endpoint)", category: .networking)
        guard let url = makeURL(endpoint: endpoint, query: query) else {
            AppLogger.shared.log("Request failed: \(endpoint): invalid URL", category: .networking, level: .error)
            throw SubsonicError.invalidResponse
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.cachePolicy = .reloadIgnoringLocalCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            AppLogger.shared.log("Request failed: \(endpoint): server unreachable - \(error.localizedDescription)", category: .networking, level: .error)
            throw SubsonicError.serverUnreachable
        }

        if let http = response as? HTTPURLResponse {
            let ok = (200...299).contains(http.statusCode)
            AppLogger.shared.log(
                "Response received: [Subsonic] \(endpoint); status=\(http.statusCode); bytes=\(data.count); elapsedMs=\(Int((ProcessInfo.processInfo.systemUptime - started) * 1000))",
                category: .networking,
                level: ok ? .info : .warning
            )
            if !ok { throw SubsonicError.serverUnreachable }
        }

        guard let envelope = try? JSONDecoder().decode(SubsonicEnvelope.self, from: data) else {
            AppLogger.shared.log("Request failed: \(endpoint): invalid JSON response (\(data.count)B)", category: .networking, level: .error)
            throw SubsonicError.invalidResponse
        }

        let body = envelope.response
        if !body.isOK {
            let code = body.error?.code ?? 0
            let msg  = body.error?.message ?? "unknown"
            AppLogger.shared.log("Request failed: \(endpoint): API error \(code) - \(msg)", category: .networking, level: .warning)
            if code == 40 || code == 41 || code == 44 || code == 45 {
                throw SubsonicError.invalidCredentials
            }
            throw SubsonicError.server(code: code, message: msg)
        }
        return body
    }

    // Auth-bearing media URLs for AVPlayer and image loaders.
    func coverArtURL(id: String?, size: Int?) -> URL? {
        guard let id, !id.isEmpty else { return nil }
        var query = [URLQueryItem(name: "id", value: id)]
        if let size { query.append(URLQueryItem(name: "size", value: String(size))) }
        return makeURL(endpoint: "getCoverArt", query: query)
    }

    func streamURL(id: String) -> URL? {
        var query = [URLQueryItem(name: "id", value: id)]
        // Shared quality resolver keeps every backend on the same rules.
        let bitrate = StreamingPreferences.streamBitrateKbps
        if bitrate > 0 {
            query.append(URLQueryItem(name: "maxBitRate", value: String(bitrate)))
        }
        appendStreamFormat(to: &query, bitrate: bitrate)
        return makeURL(endpoint: "stream", query: query)
    }

    // Download URL uses download quality, not streaming quality.
    func downloadURL(id: String) -> URL? {
        var query = [URLQueryItem(name: "id", value: id)]
        let bitrate = StreamingPreferences.downloadBitrateKbps
        if bitrate > 0 {
            query.append(URLQueryItem(name: "maxBitRate", value: String(bitrate)))
        }
        appendStreamFormat(to: &query, bitrate: bitrate)
        return makeURL(endpoint: "stream", query: query)
    }

    // Exact original URL for short-prefix BPM analysis.
    func originalStreamURL(id: String) -> URL? {
        makeURL(endpoint: "stream", query: [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "format", value: "raw"),
        ])
    }

    // Explicit "raw" prevents server-default transcoding.
    private func appendStreamFormat(to query: inout [URLQueryItem], bitrate: Int) {
        if let format = StreamingPreferences.transcodingFormat {
            query.append(URLQueryItem(name: "format", value: format))
        } else if bitrate == 0 {
            query.append(URLQueryItem(name: "format", value: "raw"))
        }
    }
}

// Conformance lives on the API methods and URL builders above.
extension SubsonicClient: MusicService {}
