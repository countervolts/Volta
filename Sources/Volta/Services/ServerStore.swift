import Foundation

// JSON-backed server store; xtool-friendly.
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
        // Cellular can use its own URL/login when configured.
        let chosen = (cellular ? record.cellularURLString?.nonBlank : nil) ?? record.urlString
        let username = cellular ? (record.cellularUsername?.nonBlank ?? record.username) : record.username
        guard let url = URL(string: chosen),
              let mainPassword = KeychainService.password(for: record.id) else { return nil }
        let password = cellular ? (cellularPassword(for: record) ?? mainPassword) : mainPassword
        return SubsonicConfig(baseURL: url, username: username, password: password)
    }

    func cellularPassword(for record: ServerRecord) -> String? {
        KeychainService.password(for: Self.cellularAccount(for: record.id))
    }

    // Save the cellular-only connection override.
    @discardableResult
    func setCellularConnection(
        urlString: String?,
        username: String?,
        password: String?,
        for record: ServerRecord
    ) -> ServerRecord {
        guard let idx = servers.firstIndex(where: { $0.id == record.id }) else { return record }
        servers[idx].cellularURLString = urlString?.nonBlank
        servers[idx].cellularUsername = username?.nonBlank
        if let password = password?.nonBlank {
            KeychainService.save(password: password, for: Self.cellularAccount(for: record.id))
        } else {
            KeychainService.delete(for: Self.cellularAccount(for: record.id))
        }
        save()
        return servers[idx]
    }

    @discardableResult
    func upsert(config: SubsonicConfig, displayName: String, backend: MusicBackendKind = .subsonic) -> ServerRecord {
        let urlString = config.baseURL.absoluteString
        if let idx = servers.firstIndex(where: { $0.urlString == urlString && $0.username == config.username }) {
            servers[idx].displayName = displayName
            servers[idx].backend = backend
            KeychainService.save(password: config.password, for: servers[idx].id)
            setCurrent(servers[idx])
            return servers[idx]
        }
        var record = ServerRecord(displayName: displayName, urlString: urlString, username: config.username, backend: backend)
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
        KeychainService.delete(for: Self.cellularAccount(for: record.id))
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

    private static func cellularAccount(for id: String) -> String {
        "\(id).cellular"
    }
}

extension String {
    // Blank fields mean "no override".
    var nonBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
