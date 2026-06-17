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
