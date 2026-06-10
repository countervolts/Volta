import Foundation

struct SubsonicConfig: Sendable, Hashable, Codable {
    var baseURL: URL
    var username: String
    var password: String

    // turns user input ("demo.navidrome.org", "http://10.0.0.5:4533/") into a
    // usable root url, defaulting to https when no scheme is given.
    static func normalizedURL(from raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        while text.hasSuffix("/") { text.removeLast() }
        return URL(string: text)
    }
}

struct SubsonicClient: Sendable {
    let config: SubsonicConfig
    let session: URLSession

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

    // returns the decoded response body, mapping transport and api failures into
    // SubsonicError. never throws anything outside SubsonicError.
    func request(_ endpoint: String, query: [URLQueryItem] = []) async throws -> SubsonicEnvelope.Body {
        try await DeveloperSimulation.prepareRequest(endpoint: endpoint)
        AppLogger.shared.log("> \(endpoint)", category: .networking)
        guard let url = makeURL(endpoint: endpoint, query: query) else {
            AppLogger.shared.log("✗ \(endpoint): invalid URL", category: .networking, level: .error)
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
            AppLogger.shared.log("✗ \(endpoint): server unreachable – \(error.localizedDescription)", category: .networking, level: .error)
            throw SubsonicError.serverUnreachable
        }

        if let http = response as? HTTPURLResponse {
            let ok = (200...299).contains(http.statusCode)
            AppLogger.shared.log("← \(endpoint) HTTP \(http.statusCode)", category: .networking, level: ok ? .info : .warning)
            if !ok { throw SubsonicError.serverUnreachable }
        }

        guard let envelope = try? JSONDecoder().decode(SubsonicEnvelope.self, from: data) else {
            AppLogger.shared.log("✗ \(endpoint): invalid JSON response (\(data.count)B)", category: .networking, level: .error)
            throw SubsonicError.invalidResponse
        }

        let body = envelope.response
        if !body.isOK {
            let code = body.error?.code ?? 0
            let msg  = body.error?.message ?? "unknown"
            AppLogger.shared.log("✗ \(endpoint): API error \(code) – \(msg)", category: .networking, level: .warning)
            if code == 40 || code == 41 || code == 44 || code == 45 {
                throw SubsonicError.invalidCredentials
            }
            throw SubsonicError.server(code: code, message: msg)
        }
        return body
    }

    // media urls (auth embedded so AVPlayer / image loaders can use them directly)
    func coverArtURL(id: String?, size: Int? = nil) -> URL? {
        guard let id, !id.isEmpty else { return nil }
        var query = [URLQueryItem(name: "id", value: id)]
        if let size { query.append(URLQueryItem(name: "size", value: String(size))) }
        return makeURL(endpoint: "getCoverArt", query: query)
    }

    func streamURL(id: String) -> URL? {
        var query = [URLQueryItem(name: "id", value: id)]
        // on cellular use the cellular quality when one is set (>0); otherwise the
        // Wi-Fi quality. NetworkMonitor mirrors the current type into UserDefaults.
        let onCellular = UserDefaults.standard.bool(forKey: "networkIsCellular")
        let cellBitrate = UserDefaults.standard.integer(forKey: "streamingBitrateCell")
        let wifiBitrate = UserDefaults.standard.integer(forKey: "streamingBitrate")
        var bitrate = (onCellular && cellBitrate > 0) ? cellBitrate : wifiBitrate
        // Performance Mode caps streaming quality (overrides the user pick)
        let cap = PerformanceMode.streamBitrateCap
        if cap > 0 { bitrate = bitrate > 0 ? min(bitrate, cap) : cap }
        if bitrate > 0 {
            query.append(URLQueryItem(name: "maxBitRate", value: String(bitrate)))
        }
        appendTranscodingFormat(to: &query)
        return makeURL(endpoint: "stream", query: query)
    }

    // URL used for downloads — honours the download bitrate setting, not the
    // streaming one. When original (0) no transcoding is requested, so the
    // downloaded size matches the song's reported size and progress is accurate.
    func downloadURL(id: String) -> URL? {
        var query = [URLQueryItem(name: "id", value: id)]
        let bitrate = UserDefaults.standard.integer(forKey: "downloadBitrate")
        if bitrate > 0 {
            query.append(URLQueryItem(name: "maxBitRate", value: String(bitrate)))
        }
        appendTranscodingFormat(to: &query)
        return makeURL(endpoint: "stream", query: query)
    }

    // Untranscoded original stream URL. Used for short-prefix BPM analysis where
    // the file extension must match the bytes so AVFoundation can decode them.
    func originalStreamURL(id: String) -> URL? {
        makeURL(endpoint: "stream", query: [URLQueryItem(name: "id", value: id)])
    }

    private func appendTranscodingFormat(to query: inout [URLQueryItem]) {
        let format = UserDefaults.standard.string(forKey: "transcodingFormat") ?? "raw"
        guard format != "raw" else { return }
        query.append(URLQueryItem(name: "format", value: format))
    }
}
