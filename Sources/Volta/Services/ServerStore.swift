import Foundation

// json-file backed store. no swiftdata macros needed; works with xtool cross-compilation.
@MainActor
final class ServerStore {
    private let serversURL: URL
    private let discoverURL: URL
    private var servers: [ServerRecord] = []
    private var discoverCaches: [DiscoverCache] = []

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Volta", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        serversURL = support.appendingPathComponent("servers.json")
        discoverURL = support.appendingPathComponent("discover.json")
        load()
    }

    // MARK: servers

    func allServers() -> [ServerRecord] {
        servers.sorted { $0.addedAt > $1.addedAt }
    }

    func currentServer() -> ServerRecord? {
        servers.first { $0.isCurrent }
    }

    func config(for record: ServerRecord, cellular: Bool = false) -> SubsonicConfig? {
        // on cellular, prefer the per-connection URL when one is set; otherwise fall
        // back to the primary URL so behaviour is unchanged for single-URL servers.
        let chosen = (cellular ? record.cellularURLString?.nonBlank : nil) ?? record.urlString
        guard let url = URL(string: chosen),
              let password = KeychainService.password(for: record.id) else { return nil }
        return SubsonicConfig(baseURL: url, username: record.username, password: password)
    }

    // updates the cellular-only URL for a record and returns the updated record.
    @discardableResult
    func setCellularURL(_ urlString: String?, for record: ServerRecord) -> ServerRecord {
        guard let idx = servers.firstIndex(where: { $0.id == record.id }) else { return record }
        servers[idx].cellularURLString = urlString?.nonBlank
        save()
        return servers[idx]
    }

    @discardableResult
    func upsert(config: SubsonicConfig, displayName: String) -> ServerRecord {
        let urlString = config.baseURL.absoluteString
        if let idx = servers.firstIndex(where: { $0.urlString == urlString && $0.username == config.username }) {
            servers[idx].displayName = displayName
            KeychainService.save(password: config.password, for: servers[idx].id)
            setCurrent(servers[idx])
            return servers[idx]
        }
        var record = ServerRecord(displayName: displayName, urlString: urlString, username: config.username)
        KeychainService.save(password: config.password, for: record.id)
        servers.append(record)
        setCurrent(record)
        record.isCurrent = true
        return record
    }

    func setCurrent(_ record: ServerRecord) {
        for i in servers.indices { servers[i].isCurrent = servers[i].id == record.id }
        save()
    }

    func clearCurrent() {
        for i in servers.indices { servers[i].isCurrent = false }
        save()
    }

    func remove(_ record: ServerRecord) {
        KeychainService.delete(for: record.id)
        servers.removeAll { $0.id == record.id }
        save()
    }

    // MARK: discover cache

    func discoverCache(serverID: String) -> DiscoverCache? {
        discoverCaches.first { $0.serverID == serverID }
    }

    func saveDiscoverCache(_ cache: DiscoverCache) {
        if let idx = discoverCaches.firstIndex(where: { $0.serverID == cache.serverID }) {
            discoverCaches[idx] = cache
        } else {
            discoverCaches.append(cache)
        }
        if let data = try? JSONEncoder().encode(discoverCaches) {
            try? data.write(to: discoverURL, options: .atomic)
        }
    }

    // MARK: persistence

    private func load() {
        if let data = try? Data(contentsOf: serversURL) {
            servers = (try? JSONDecoder().decode([ServerRecord].self, from: data)) ?? []
        }
        if let data = try? Data(contentsOf: discoverURL) {
            discoverCaches = (try? JSONDecoder().decode([DiscoverCache].self, from: data)) ?? []
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(servers) {
            try? data.write(to: serversURL, options: .atomic)
        }
    }
}

extension String {
    // trimmed value, or nil when empty/whitespace — keeps blank URL fields from
    // masquerading as a real cellular override.
    var nonBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
