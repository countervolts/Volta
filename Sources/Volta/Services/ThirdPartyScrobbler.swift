import Foundation

enum ScrobbleProviderSettings {
    enum Keys {
        static let lastFMEnabled = "thirdPartyScrobbleLastFMEnabled"
        static let lastFMAPIKey = "thirdPartyScrobbleLastFMAPIKey"
        static let lastFMUsername = "thirdPartyScrobbleLastFMUsername"
        static let koitoEnabled = "thirdPartyScrobbleKoitoEnabled"
        static let koitoURL = "thirdPartyScrobbleKoitoURL"
        static let malojaEnabled = "thirdPartyScrobbleMalojaEnabled"
        static let malojaURL = "thirdPartyScrobbleMalojaURL"
    }

    enum SecretAccounts {
        static let lastFMSecret = "thirdPartyScrobble.lastfm.secret"
        static let lastFMSessionKey = "thirdPartyScrobble.lastfm.sessionKey"
        static let koitoToken = "thirdPartyScrobble.koito.token"
        static let malojaKey = "thirdPartyScrobble.maloja.key"
    }

    static func secret(for account: String) -> String {
        KeychainService.password(for: account) ?? ""
    }

    static func saveSecret(_ value: String, for account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainService.delete(for: account)
        } else {
            KeychainService.save(password: trimmed, for: account)
        }
    }

    static var activeProviderNames: [String] {
        let defaults = UserDefaults.standard
        var names: [String] = []
        if defaults.bool(forKey: Keys.lastFMEnabled) { names.append("Last.fm") }
        if defaults.bool(forKey: Keys.koitoEnabled) { names.append("Koito") }
        if defaults.bool(forKey: Keys.malojaEnabled) { names.append("Maloja") }
        return names
    }
}

struct LastFMSession: Sendable {
    let username: String
    let sessionKey: String
}

enum ThirdPartyScrobbleError: LocalizedError {
    case invalidURL(String)
    case missingCredentials(String)
    case badResponse(String)
    case providerMessage(String, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let provider):
            return "\(provider) URL is invalid."
        case .missingCredentials(let provider):
            return "\(provider) credentials are incomplete."
        case .badResponse(let provider):
            return "\(provider) returned an unexpected response."
        case .providerMessage(let provider, let message):
            return "\(provider): \(message)"
        }
    }
}

final class ThirdPartyScrobbler: @unchecked Sendable {
    static let shared = ThirdPartyScrobbler()

    private let session: URLSession

    private init(session: URLSession = .shared) {
        self.session = session
    }

    func notifyNowPlaying(song: Song, startedAt: Date) {
        let configs = providerConfigs()
        guard !configs.isEmpty else { return }
        Task {
            await submitNowPlaying(song: song, startedAt: startedAt, configs: configs)
        }
    }

    func submitScrobble(
        song: Song,
        event: PlayEvent,
        startedAt: Date,
        listenedDuration: Int,
        trackDuration: Int
    ) {
        let configs = providerConfigs()
        guard !configs.isEmpty else { return }
        Task {
            await submitScrobble(
                song: song,
                event: event,
                startedAt: startedAt,
                listenedDuration: listenedDuration,
                trackDuration: trackDuration,
                configs: configs
            )
        }
    }

    func authenticateLastFM(
        username: String,
        password: String,
        apiKey: String,
        secret: String
    ) async throws -> LastFMSession {
        let provider = "Last.fm"
        guard !username.trimmedForScrobbling.isEmpty,
              !password.isEmpty,
              !apiKey.trimmedForScrobbling.isEmpty,
              !secret.trimmedForScrobbling.isEmpty else {
            throw ThirdPartyScrobbleError.missingCredentials(provider)
        }

        let data = try await sendLastFM(
            parameters: [
                "method": "auth.getMobileSession",
                "username": username.trimmedForScrobbling,
                "password": password,
                "api_key": apiKey.trimmedForScrobbling,
                "format": "json",
            ],
            secret: secret.trimmedForScrobbling
        )
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let session = object["session"] as? [String: Any],
              let key = session["key"] as? String,
              !key.isEmpty else {
            try throwProviderErrorIfPresent(data, provider: provider)
            throw ThirdPartyScrobbleError.badResponse(provider)
        }
        let name = (session["name"] as? String) ?? username.trimmedForScrobbling
        return LastFMSession(username: name, sessionKey: key)
    }

    func validateLastFM(apiKey: String, secret: String, sessionKey: String) async throws -> String? {
        let provider = "Last.fm"
        guard !apiKey.trimmedForScrobbling.isEmpty,
              !secret.trimmedForScrobbling.isEmpty,
              !sessionKey.trimmedForScrobbling.isEmpty else {
            throw ThirdPartyScrobbleError.missingCredentials(provider)
        }
        let data = try await sendLastFM(
            parameters: [
                "method": "user.getInfo",
                "api_key": apiKey.trimmedForScrobbling,
                "sk": sessionKey.trimmedForScrobbling,
                "format": "json",
            ],
            secret: secret.trimmedForScrobbling
        )
        try throwProviderErrorIfPresent(data, provider: provider)
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let user = object?["user"] as? [String: Any]
        return user?["name"] as? String
    }

    func validateKoito(urlString: String, token: String) async throws {
        try await validateListenBrainz(provider: "Koito", urlString: urlString, token: token)
    }

    func validateMaloja(urlString: String, key: String) async throws {
        let provider = "Maloja"
        guard !key.trimmedForScrobbling.isEmpty else {
            throw ThirdPartyScrobbleError.missingCredentials(provider)
        }
        guard let url = Self.malojaTestURL(from: urlString) else {
            throw ThirdPartyScrobbleError.invalidURL(provider)
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ThirdPartyScrobbleError.invalidURL(provider)
        }
        components.queryItems = [URLQueryItem(name: "key", value: key.trimmedForScrobbling)]
        guard let testURL = components.url else {
            throw ThirdPartyScrobbleError.invalidURL(provider)
        }
        var request = URLRequest(url: testURL)
        request.httpMethod = "GET"
        let data = try await perform(request, provider: provider)
        try throwProviderErrorIfPresent(data, provider: provider)
    }

    private func submitNowPlaying(song: Song, startedAt: Date, configs: [ProviderConfig]) async {
        await withTaskGroup(of: Void.self) { group in
            for config in configs {
                group.addTask { [self] in
                    do {
                        switch config {
                        case .lastFM(let config):
                            try await sendLastFMNowPlaying(song: song, config: config)
                        case .koito(let config):
                            try await sendListenBrainz(song: song, startedAt: nil, listenedDuration: nil, trackDuration: song.duration, config: config, listenType: "playing_now")
                        case .maloja:
                            break
                        }
                    } catch {
                        logFailure("now playing", provider: config.name, error: error)
                    }
                }
            }
        }
    }

    private func submitScrobble(
        song: Song,
        event: PlayEvent,
        startedAt: Date,
        listenedDuration: Int,
        trackDuration: Int,
        configs: [ProviderConfig]
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for config in configs {
                group.addTask { [self] in
                    do {
                        switch config {
                        case .lastFM(let config):
                            try await sendLastFMScrobble(
                                song: song,
                                event: event,
                                startedAt: startedAt,
                                trackDuration: trackDuration,
                                config: config
                            )
                        case .koito(let config):
                            try await sendListenBrainz(
                                song: song,
                                startedAt: startedAt,
                                listenedDuration: listenedDuration,
                                trackDuration: trackDuration,
                                config: config,
                                listenType: "single"
                            )
                        case .maloja(let config):
                            try await sendMalojaScrobble(
                                event: event,
                                startedAt: startedAt,
                                listenedDuration: listenedDuration,
                                trackDuration: trackDuration,
                                config: config
                            )
                        }
                        AppLogger.shared.log("Third-party scrobble submitted to \(config.name): '\(event.title)'", category: .playback)
                    } catch {
                        logFailure("scrobble", provider: config.name, error: error)
                    }
                }
            }
        }
    }

    private func sendLastFMNowPlaying(song: Song, config: LastFMConfig) async throws {
        var params = lastFMTrackParams(song: song, config: config)
        params["method"] = "track.updateNowPlaying"
        _ = try await sendLastFM(parameters: params, secret: config.secret)
    }

    private func sendLastFMScrobble(
        song: Song,
        event: PlayEvent,
        startedAt: Date,
        trackDuration: Int,
        config: LastFMConfig
    ) async throws {
        var params = lastFMTrackParams(song: song, config: config)
        params["method"] = "track.scrobble"
        params["timestamp"] = "\(Int(startedAt.timeIntervalSince1970))"
        if trackDuration > 0 { params["duration"] = "\(trackDuration)" }
        _ = try await sendLastFM(parameters: params, secret: config.secret)
        AppLogger.shared.log("Last.fm accepted scrobble: '\(event.title)'", category: .playback)
    }

    private func lastFMTrackParams(song: Song, config: LastFMConfig) -> [String: String] {
        var params: [String: String] = [
            "artist": song.primaryArtistName.trimmedForScrobbling,
            "track": song.title.trimmedForScrobbling,
            "api_key": config.apiKey,
            "sk": config.sessionKey,
            "format": "json",
        ]
        if let album = song.album?.trimmedForScrobbling, !album.isEmpty {
            params["album"] = album
        }
        if let track = song.track, track > 0 {
            params["trackNumber"] = "\(track)"
        }
        if let duration = song.duration, duration > 0 {
            params["duration"] = "\(duration)"
        }
        return params
    }

    private func sendLastFM(parameters rawParams: [String: String], secret: String) async throws -> Data {
        guard let url = URL(string: "https://ws.audioscrobbler.com/2.0/") else {
            throw ThirdPartyScrobbleError.invalidURL("Last.fm")
        }
        var params = rawParams
        params["api_sig"] = Self.lastFMSignature(parameters: params, secret: secret)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncodedBody(params)

        let data = try await perform(request, provider: "Last.fm")
        try throwProviderErrorIfPresent(data, provider: "Last.fm")
        return data
    }

    private func sendListenBrainz(
        song: Song,
        startedAt: Date?,
        listenedDuration: Int?,
        trackDuration: Int?,
        config: ListenBrainzConfig,
        listenType: String
    ) async throws {
        let listen = ListenBrainzListen(
            listenedAt: startedAt.map { Int($0.timeIntervalSince1970) },
            trackMetadata: ListenBrainzTrackMetadata(
                artistName: song.primaryArtistName.trimmedForScrobbling,
                trackName: song.title.trimmedForScrobbling,
                releaseName: song.album?.trimmedForScrobbling,
                additionalInfo: ListenBrainzAdditionalInfo(
                    mediaPlayer: "Volta",
                    submissionClient: "Volta",
                    duration: trackDuration.flatMap { $0 > 0 ? $0 : nil },
                    durationPlayed: listenedDuration.flatMap { $0 > 0 ? $0 : nil },
                    trackNumber: song.track.map(String.init),
                    artistNames: [song.primaryArtistName.trimmedForScrobbling].filter { !$0.isEmpty }
                )
            )
        )
        let body = ListenBrainzSubmission(listenType: listenType, payload: [listen])
        var request = URLRequest(url: config.submitURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Token \(config.token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let data = try await perform(request, provider: config.provider)
        try throwProviderErrorIfPresent(data, provider: config.provider)
    }

    private func sendMalojaScrobble(
        event: PlayEvent,
        startedAt: Date,
        listenedDuration: Int,
        trackDuration: Int,
        config: MalojaConfig
    ) async throws {
        let body = MalojaScrobbleSubmission(
            key: config.key,
            artists: [event.artist.trimmedForScrobbling].filter { !$0.isEmpty },
            title: event.title,
            album: event.album,
            duration: listenedDuration > 0 ? listenedDuration : nil,
            length: trackDuration > 0 ? trackDuration : nil,
            time: Int(startedAt.timeIntervalSince1970)
        )
        var request = URLRequest(url: config.submitURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let data = try await perform(request, provider: "Maloja")
        try throwProviderErrorIfPresent(data, provider: "Maloja")
    }

    private func validateListenBrainz(provider: String, urlString: String, token: String) async throws {
        guard !token.trimmedForScrobbling.isEmpty else {
            throw ThirdPartyScrobbleError.missingCredentials(provider)
        }
        guard let url = Self.listenBrainzValidateURL(from: urlString) else {
            throw ThirdPartyScrobbleError.invalidURL(provider)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Token \(token.trimmedForScrobbling)", forHTTPHeaderField: "Authorization")

        let data = try await perform(request, provider: provider)
        try throwProviderErrorIfPresent(data, provider: provider)
    }

    private func perform(_ request: URLRequest, provider: String) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ThirdPartyScrobbleError.badResponse(provider)
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.responseMessage(from: data) ?? "HTTP \(http.statusCode)"
            throw ThirdPartyScrobbleError.providerMessage(provider, message)
        }
        return data
    }

    private func throwProviderErrorIfPresent(_ data: Data, provider: String) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        if let message = object["message"] as? String, object["error"] != nil {
            throw ThirdPartyScrobbleError.providerMessage(provider, message)
        }
        if let error = object["error"] {
            throw ThirdPartyScrobbleError.providerMessage(provider, String(describing: error))
        }
        if let status = object["status"] as? String {
            let lower = status.lowercased()
            if lower == "error" || lower == "failure" || lower == "failed" {
                throw ThirdPartyScrobbleError.providerMessage(
                    provider,
                    Self.responseMessage(from: data) ?? "Request failed"
                )
            }
        }
    }

    private func logFailure(_ action: String, provider: String, error: Error) {
        AppLogger.shared.log(
            "Third-party \(action) failed for \(provider): \(error.localizedDescription)",
            category: .playback,
            level: .warning
        )
    }

    private func providerConfigs() -> [ProviderConfig] {
        let defaults = UserDefaults.standard
        var configs: [ProviderConfig] = []

        if defaults.bool(forKey: ScrobbleProviderSettings.Keys.lastFMEnabled),
           let config = lastFMConfig(defaults: defaults) {
            configs.append(.lastFM(config))
        }

        if defaults.bool(forKey: ScrobbleProviderSettings.Keys.koitoEnabled),
           let config = listenBrainzConfig(
            provider: "Koito",
            urlString: defaults.string(forKey: ScrobbleProviderSettings.Keys.koitoURL),
            token: ScrobbleProviderSettings.secret(for: ScrobbleProviderSettings.SecretAccounts.koitoToken)
           ) {
            configs.append(.koito(config))
        }

        if defaults.bool(forKey: ScrobbleProviderSettings.Keys.malojaEnabled),
           let urlString = defaults.string(forKey: ScrobbleProviderSettings.Keys.malojaURL),
           let submitURL = Self.malojaScrobbleURL(from: urlString) {
            let key = ScrobbleProviderSettings.secret(for: ScrobbleProviderSettings.SecretAccounts.malojaKey)
                .trimmedForScrobbling
            if !key.isEmpty {
                configs.append(.maloja(MalojaConfig(submitURL: submitURL, key: key)))
            }
        }

        return configs
    }

    private func lastFMConfig(defaults: UserDefaults) -> LastFMConfig? {
        let apiKey = (defaults.string(forKey: ScrobbleProviderSettings.Keys.lastFMAPIKey) ?? "")
            .trimmedForScrobbling
        let secret = ScrobbleProviderSettings.secret(for: ScrobbleProviderSettings.SecretAccounts.lastFMSecret)
            .trimmedForScrobbling
        let sessionKey = ScrobbleProviderSettings.secret(for: ScrobbleProviderSettings.SecretAccounts.lastFMSessionKey)
            .trimmedForScrobbling
        guard !apiKey.isEmpty, !secret.isEmpty, !sessionKey.isEmpty else { return nil }
        return LastFMConfig(apiKey: apiKey, secret: secret, sessionKey: sessionKey)
    }

    private func listenBrainzConfig(provider: String, urlString: String?, token: String) -> ListenBrainzConfig? {
        guard let urlString,
              let submitURL = Self.listenBrainzSubmitURL(from: urlString) else { return nil }
        let token = token.trimmedForScrobbling
        guard !token.isEmpty else { return nil }
        return ListenBrainzConfig(provider: provider, submitURL: submitURL, token: token)
    }

    private static func lastFMSignature(parameters: [String: String], secret: String) -> String {
        let base = parameters
            .filter { element in element.key != "format" && element.key != "callback" && element.key != "api_sig" }
            .sorted { $0.key < $1.key }
            .map { $0.key + $0.value }
            .joined() + secret
        return Crypto.md5Hex(base)
    }

    private static func formEncodedBody(_ parameters: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = parameters
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private static func responseMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)?.trimmedForScrobbling.nonEmptyForScrobbling
        }
        if let message = object["message"] as? String { return message }
        if let error = object["error"] as? [String: Any],
           let desc = error["desc"] as? String {
            return desc
        }
        if let desc = object["desc"] as? String { return desc }
        if let error = object["error"] { return String(describing: error) }
        return nil
    }

    static func listenBrainzSubmitURL(from raw: String) -> URL? {
        guard var components = normalizedComponents(from: raw) else { return nil }
        var path = normalizedPath(components.path)
        if path.hasSuffix("/submit-listens") {
            components.path = path
            components.query = nil
            return components.url
        }
        if path.isEmpty {
            path = "/apis/listenbrainz/1"
        } else if path.hasSuffix("/apis/listenbrainz") {
            path += "/1"
        } else if !path.hasSuffix("/apis/listenbrainz/1") {
            path += "/apis/listenbrainz/1"
        }
        components.path = normalizedPath(path + "/submit-listens")
        components.query = nil
        return components.url
    }

    static func listenBrainzValidateURL(from raw: String) -> URL? {
        guard var components = normalizedComponents(from: raw) else { return nil }
        var path = normalizedPath(components.path)
        if path.hasSuffix("/submit-listens") {
            path = String(path.dropLast("/submit-listens".count))
        }
        if path.isEmpty {
            path = "/apis/listenbrainz/1"
        } else if path.hasSuffix("/apis/listenbrainz") {
            path += "/1"
        } else if !path.hasSuffix("/apis/listenbrainz/1") {
            path += "/apis/listenbrainz/1"
        }
        components.path = normalizedPath(path + "/validate-token")
        components.query = nil
        return components.url
    }

    static func malojaScrobbleURL(from raw: String) -> URL? {
        malojaURL(from: raw, endpoint: "newscrobble")
    }

    static func malojaTestURL(from raw: String) -> URL? {
        guard let base = malojaURL(from: raw, endpoint: "test") else { return nil }
        return base
    }

    private static func malojaURL(from raw: String, endpoint: String) -> URL? {
        guard var components = normalizedComponents(from: raw) else { return nil }
        var path = normalizedPath(components.path)
        if path.hasSuffix("/newscrobble") || path.hasSuffix("/test") {
            path = String(path.dropLast(path.lastPathComponentForScrobbling.count + 1))
        }
        if path.isEmpty {
            path = "/apis/mlj_1"
        } else if !path.hasSuffix("/apis/mlj_1") {
            path += "/apis/mlj_1"
        }
        components.path = normalizedPath(path + "/\(endpoint)")
        components.query = nil
        return components.url
    }

    private static func normalizedComponents(from raw: String) -> URLComponents? {
        var trimmed = raw.trimmedForScrobbling
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") {
            trimmed = "https://" + trimmed
        }
        guard var components = URLComponents(string: trimmed),
              components.host != nil else { return nil }
        components.path = normalizedPath(components.path)
        return components
    }

    private static func normalizedPath(_ path: String) -> String {
        var result = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasSuffix("/") { result.removeLast() }
        if result == "/" { result = "" }
        if !result.isEmpty, !result.hasPrefix("/") { result = "/" + result }
        return result
    }
}

private enum ProviderConfig: Sendable {
    case lastFM(LastFMConfig)
    case koito(ListenBrainzConfig)
    case maloja(MalojaConfig)

    var name: String {
        switch self {
        case .lastFM: return "Last.fm"
        case .koito: return "Koito"
        case .maloja: return "Maloja"
        }
    }
}

private struct LastFMConfig: Sendable {
    let apiKey: String
    let secret: String
    let sessionKey: String
}

private struct ListenBrainzConfig: Sendable {
    let provider: String
    let submitURL: URL
    let token: String
}

private struct MalojaConfig: Sendable {
    let submitURL: URL
    let key: String
}

private struct ListenBrainzSubmission: Encodable {
    let listenType: String
    let payload: [ListenBrainzListen]

    enum CodingKeys: String, CodingKey {
        case listenType = "listen_type"
        case payload
    }
}

private struct ListenBrainzListen: Encodable {
    let listenedAt: Int?
    let trackMetadata: ListenBrainzTrackMetadata

    enum CodingKeys: String, CodingKey {
        case listenedAt = "listened_at"
        case trackMetadata = "track_metadata"
    }
}

private struct ListenBrainzTrackMetadata: Encodable {
    let artistName: String
    let trackName: String
    let releaseName: String?
    let additionalInfo: ListenBrainzAdditionalInfo

    enum CodingKeys: String, CodingKey {
        case artistName = "artist_name"
        case trackName = "track_name"
        case releaseName = "release_name"
        case additionalInfo = "additional_info"
    }
}

private struct ListenBrainzAdditionalInfo: Encodable {
    let mediaPlayer: String
    let submissionClient: String
    let duration: Int?
    let durationPlayed: Int?
    let trackNumber: String?
    let artistNames: [String]

    enum CodingKeys: String, CodingKey {
        case mediaPlayer = "media_player"
        case submissionClient = "submission_client"
        case duration
        case durationPlayed = "duration_played"
        case trackNumber = "tracknumber"
        case artistNames = "artist_names"
    }
}

private struct MalojaScrobbleSubmission: Encodable {
    let key: String
    let artists: [String]
    let title: String
    let album: String?
    let duration: Int?
    let length: Int?
    let time: Int
}

private extension String {
    var trimmedForScrobbling: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nonEmptyForScrobbling: String? {
        isEmpty ? nil : self
    }

    var lastPathComponentForScrobbling: String {
        split(separator: "/").last.map(String.init) ?? ""
    }
}
