import Foundation

struct PlexHostedAuthSession: Sendable {
    let id: Int
    let code: String
    let authURL: URL
}

enum PlexHostedAuth {
    enum AuthError: Error {
        case invalidResponse
        case timedOut
    }

    static func start(session: URLSession = .shared) async throws -> PlexHostedAuthSession {
        let clientId = PlexClient.clientID()
        guard let url = URL(string: "https://plex.tv/api/v2/pins") else {
            throw AuthError.invalidResponse
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        for (key, value) in PlexClient.plexHeaders(clientId: clientId) {
            req.setValue(value, forHTTPHeaderField: key)
        }
        req.httpBody = "strong=true".data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw SubsonicError.serverUnreachable
        }

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw AuthError.invalidResponse
        }

        let pin = try JSONDecoder().decode(PlexPIN.self, from: data)
        guard let authURL = authURL(clientId: clientId, code: pin.code) else {
            throw AuthError.invalidResponse
        }

        return PlexHostedAuthSession(id: pin.id, code: pin.code, authURL: authURL)
    }

    static func waitForToken(
        session authSession: PlexHostedAuthSession,
        urlSession: URLSession = .shared,
        timeout: TimeInterval = 120
    ) async throws -> String {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            try Task.checkCancellation()
            if let token = try await poll(authSession, session: urlSession) {
                return token
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        throw AuthError.timedOut
    }

    // Resolve the signed-in account into Plex Media Servers. Plex returns a
    // different access token for each server along with its local, remote, and
    // relay connection URLs; the account token must not be used as the PMS
    // token directly.
    static func servers(
        forAccountToken accountToken: String,
        session: URLSession = .shared
    ) async throws -> [PlexServerResource] {
        guard var components = URLComponents(string: "https://clients.plex.tv/api/v2/resources") else {
            throw AuthError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "includeHttps", value: "1"),
            URLQueryItem(name: "includeRelay", value: "1"),
            URLQueryItem(name: "includeIPv6", value: "1"),
        ]
        guard let url = components.url else { throw AuthError.invalidResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        for (key, value) in PlexClient.plexHeaders(clientId: PlexClient.clientID()) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue(accountToken, forHTTPHeaderField: "X-Plex-Token")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SubsonicError.serverUnreachable
        }

        guard let http = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw SubsonicError.invalidCredentials
        }
        guard (200...299).contains(http.statusCode) else {
            throw SubsonicError.server(code: http.statusCode, message: "Plex resource discovery returned HTTP \(http.statusCode)")
        }

        let decoder = JSONDecoder()
        let resources: [PlexServerResource]
        if let decoded = try? decoder.decode([PlexServerResource].self, from: data) {
            resources = decoded
        } else if let envelope = try? decoder.decode(PlexResourceEnvelope.self, from: data) {
            resources = envelope.MediaContainer?.Device ?? []
        } else {
            throw AuthError.invalidResponse
        }

        return resources.filter {
            $0.isMediaServer && $0.usableAccessToken != nil && !$0.preferredConnections.isEmpty
        }
    }

    private static func poll(
        _ authSession: PlexHostedAuthSession,
        session: URLSession
    ) async throws -> String? {
        guard var comps = URLComponents(string: "https://plex.tv/api/v2/pins/\(authSession.id)") else {
            throw AuthError.invalidResponse
        }
        comps.queryItems = [URLQueryItem(name: "code", value: authSession.code)]
        guard let url = comps.url else { throw AuthError.invalidResponse }

        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        for (key, value) in PlexClient.plexHeaders(clientId: PlexClient.clientID()) {
            req.setValue(value, forHTTPHeaderField: key)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw SubsonicError.serverUnreachable
        }

        guard let http = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 404 { return nil }
            throw AuthError.invalidResponse
        }

        let pin = try JSONDecoder().decode(PlexPIN.self, from: data)
        return pin.authToken?.nonBlank
    }

    private static func authURL(clientId: String, code: String) -> URL? {
        var query = URLComponents()
        query.queryItems = [
            URLQueryItem(name: "clientID", value: clientId),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "context[device][product]", value: PlexClient.product),
        ]
        guard let encoded = query.percentEncodedQuery else { return nil }
        return URL(string: "https://app.plex.tv/auth#?\(encoded)")
    }
}

private struct PlexPIN: Decodable {
    let id: Int
    let code: String
    let authToken: String?

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case authToken
    }
}
