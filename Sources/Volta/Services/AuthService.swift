import Foundation

// Server login check. Some backends validate during client creation.
enum AuthService {
    @discardableResult
    static func validate(config: SubsonicConfig,
                         kind: MusicBackendKind = .subsonic,
                         session: URLSession = .shared) async throws -> SubsonicConfig {
        let client = try await MusicServiceFactory.make(config: config, kind: kind, session: session)
        try await client.ping()
        return client.config
    }
}
