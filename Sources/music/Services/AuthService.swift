import Foundation

// validates a server + credentials by pinging the subsonic endpoint.
enum AuthService {
    static func validate(config: SubsonicConfig) async throws {
        let client = SubsonicClient(config: config)
        try await client.ping()
    }
}
