import Foundation

// Public login demos. Their media is stream-only and never persisted.
enum DemoServers {
    struct Entry {
        let kind: MusicBackendKind
        let address: String
        let username: String
        let password: String
    }

    // Navidrome: demo/demo. Jellyfin: demo with no password.
    static let all: [Entry] = [
        Entry(kind: .subsonic, address: "https://demo.navidrome.org", username: "demo", password: "demo"),
        Entry(kind: .jellyfin, address: "https://demo.jellyfin.org/stable", username: "demo", password: ""),
    ]

    static func entry(for kind: MusicBackendKind) -> Entry? {
        all.first { $0.kind == kind }
    }

    // Lowercased demo hosts.
    private static let demoHosts: Set<String> = Set(
        all.compactMap { URL(string: $0.address)?.host?.lowercased() }
    )

    // True when a URL targets one of the demo servers (matched by host). Services
    // use this to skip writing demo-server songs/lyrics/artwork to disk.
    static func isDemo(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return demoHosts.contains(host)
    }
}
