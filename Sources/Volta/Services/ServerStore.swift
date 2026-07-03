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

    func defaultServer() -> ServerRecord? {
        servers.first { $0.isDefault }
    }

    func fallbackServer(excluding record: ServerRecord? = nil) -> ServerRecord? {
        servers.first { server in
            server.isFallback && server.id != record?.id
        }
    }

    func startupServers() -> [ServerRecord] {
        uniqueServers([
            defaultServer(),
            currentServer(),
            fallbackServer()
        ])
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
            if !servers.contains(where: \.isDefault) {
                servers[idx].isDefault = true
            }
            KeychainService.save(password: config.password, for: servers[idx].id)
            setCurrent(servers[idx])
            return servers[idx]
        }
        var record = ServerRecord(displayName: displayName, urlString: urlString, username: config.username, backend: backend)
        record.isDefault = !servers.contains(where: \.isDefault)
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

    @discardableResult
    func setDefault(_ record: ServerRecord) -> ServerRecord? {
        guard let idx = servers.firstIndex(where: { $0.id == record.id }) else { return nil }
        for i in servers.indices {
            let matches = servers[i].id == record.id
            servers[i].isDefault = matches
            if matches { servers[i].isFallback = false }
        }
        save()
        return servers[idx]
    }

    @discardableResult
    func setFallback(_ record: ServerRecord?) -> ServerRecord? {
        guard let record else {
            for i in servers.indices { servers[i].isFallback = false }
            save()
            return nil
        }
        guard let idx = servers.firstIndex(where: { $0.id == record.id }),
              !servers[idx].isDefault else { return nil }
        for i in servers.indices {
            servers[i].isFallback = servers[i].id == record.id
        }
        save()
        return servers[idx]
    }

    @discardableResult
    func update(record: ServerRecord, config: SubsonicConfig, displayName: String? = nil, backend: MusicBackendKind? = nil) -> ServerRecord {
        guard let idx = servers.firstIndex(where: { $0.id == record.id }) else { return record }
        servers[idx].urlString = config.baseURL.absoluteString
        servers[idx].username = config.username
        if let displayName { servers[idx].displayName = displayName }
        if let backend { servers[idx].backend = backend }
        KeychainService.save(password: config.password, for: servers[idx].id)
        save()
        return servers[idx]
    }

    func clearCurrent() {
        for i in servers.indices { servers[i].isCurrent = false }
        save()
    }

    func remove(_ record: ServerRecord) {
        KeychainService.delete(for: record.id)
        KeychainService.delete(for: Self.cellularAccount(for: record.id))
        servers.removeAll { $0.id == record.id }
        normalizeServerRoles()
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
            normalizeServerRoles()
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

    private func normalizeServerRoles() {
        guard !servers.isEmpty else { return }

        let defaultIndices = servers.indices.filter { servers[$0].isDefault }
        if defaultIndices.isEmpty {
            let preferred = servers.firstIndex(where: \.isCurrent) ?? servers.indices.max { servers[$0].addedAt < servers[$1].addedAt }
            if let preferred { servers[preferred].isDefault = true }
        } else {
            for idx in defaultIndices.dropFirst() {
                servers[idx].isDefault = false
            }
        }

        guard servers.count > 1 else {
            for i in servers.indices { servers[i].isFallback = false }
            return
        }

        let defaultID = servers.first(where: \.isDefault)?.id
        var didKeepFallback = false
        for i in servers.indices {
            if servers[i].id == defaultID {
                servers[i].isFallback = false
            } else if servers[i].isFallback {
                if didKeepFallback {
                    servers[i].isFallback = false
                } else {
                    didKeepFallback = true
                }
            }
        }
    }

    private func uniqueServers(_ candidates: [ServerRecord?]) -> [ServerRecord] {
        var seen = Set<String>()
        return candidates.compactMap { server in
            guard let server, !seen.contains(server.id) else { return nil }
            seen.insert(server.id)
            return server
        }
    }
}

extension String {
    // Blank fields mean "no override".
    var nonBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
