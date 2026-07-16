import Foundation

struct ServerRecord: Codable, Identifiable, Hashable {
    var id: String
    var displayName: String
    var urlString: String
    // Cellular-only base URL override.
    var cellularURLString: String?
    // Cellular-only username override.
    var cellularUsername: String?
    var username: String
    var isCurrent: Bool
    var isDefault: Bool
    var isFallback: Bool
    var addedAt: Date
    // Server protocol for this connection.
    var backend: MusicBackendKind
    // Alternate routes Plex advertised for this same server. Empty for all
    // other backends and for Plex records saved by older app versions.
    var plexConnections: [PlexConnectionEndpoint]

    init(id: String = UUID().uuidString,
         displayName: String,
         urlString: String,
         cellularURLString: String? = nil,
         cellularUsername: String? = nil,
         username: String,
         isCurrent: Bool = false,
         isDefault: Bool = false,
         isFallback: Bool = false,
         addedAt: Date = .now,
         backend: MusicBackendKind = .subsonic,
         plexConnections: [PlexConnectionEndpoint] = []) {
        self.id = id
        self.displayName = displayName
        self.urlString = urlString
        self.cellularURLString = cellularURLString
        self.cellularUsername = cellularUsername
        self.username = username
        self.isCurrent = isCurrent
        self.isDefault = isDefault
        self.isFallback = isFallback
        self.addedAt = addedAt
        self.backend = backend
        self.plexConnections = plexConnections
    }

    enum CodingKeys: String, CodingKey {
        case id, displayName, urlString, cellularURLString, cellularUsername
        case username, isCurrent, isDefault, isFallback, addedAt, backend, plexConnections
    }

    // Older servers.json files have no backend/default/fallback keys.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        urlString = try c.decode(String.self, forKey: .urlString)
        cellularURLString = try c.decodeIfPresent(String.self, forKey: .cellularURLString)
        cellularUsername = try c.decodeIfPresent(String.self, forKey: .cellularUsername)
        username = try c.decode(String.self, forKey: .username)
        isCurrent = try c.decode(Bool.self, forKey: .isCurrent)
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        isFallback = try c.decodeIfPresent(Bool.self, forKey: .isFallback) ?? false
        addedAt = try c.decode(Date.self, forKey: .addedAt)
        backend = try c.decodeIfPresent(MusicBackendKind.self, forKey: .backend) ?? .subsonic
        plexConnections = try c.decodeIfPresent(
            [PlexConnectionEndpoint].self,
            forKey: .plexConnections
        ) ?? []
    }
}

struct DiscoverCache: Codable {
    var serverID: String
    var albumIDs: [String]
    var lastRefresh: Date
}
