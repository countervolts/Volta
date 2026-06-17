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
    var addedAt: Date
    // Server protocol for this connection.
    var backend: MusicBackendKind

    init(id: String = UUID().uuidString,
         displayName: String,
         urlString: String,
         cellularURLString: String? = nil,
         cellularUsername: String? = nil,
         username: String,
         isCurrent: Bool = false,
         addedAt: Date = .now,
         backend: MusicBackendKind = .subsonic) {
        self.id = id
        self.displayName = displayName
        self.urlString = urlString
        self.cellularURLString = cellularURLString
        self.cellularUsername = cellularUsername
        self.username = username
        self.isCurrent = isCurrent
        self.addedAt = addedAt
        self.backend = backend
    }

    enum CodingKeys: String, CodingKey {
        case id, displayName, urlString, cellularURLString, cellularUsername
        case username, isCurrent, addedAt, backend
    }

    // Older servers.json files have no backend key.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        urlString = try c.decode(String.self, forKey: .urlString)
        cellularURLString = try c.decodeIfPresent(String.self, forKey: .cellularURLString)
        cellularUsername = try c.decodeIfPresent(String.self, forKey: .cellularUsername)
        username = try c.decode(String.self, forKey: .username)
        isCurrent = try c.decode(Bool.self, forKey: .isCurrent)
        addedAt = try c.decode(Date.self, forKey: .addedAt)
        backend = try c.decodeIfPresent(MusicBackendKind.self, forKey: .backend) ?? .subsonic
    }
}

struct DiscoverCache: Codable {
    var serverID: String
    var albumIDs: [String]
    var lastRefresh: Date
}
