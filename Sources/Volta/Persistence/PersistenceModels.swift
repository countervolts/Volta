import Foundation

struct ServerRecord: Codable, Identifiable, Hashable {
    var id: String
    var displayName: String
    var urlString: String
    // optional alternate base URL used while on cellular (e.g. a public address when
    // the primary urlString is a LAN-only one). nil/blank > always use urlString.
    var cellularURLString: String?
    // optional alternate username used while on cellular. nil/blank > use username.
    var cellularUsername: String?
    var username: String
    var isCurrent: Bool
    var addedAt: Date

    init(id: String = UUID().uuidString,
         displayName: String,
         urlString: String,
         cellularURLString: String? = nil,
         cellularUsername: String? = nil,
         username: String,
         isCurrent: Bool = false,
         addedAt: Date = .now) {
        self.id = id
        self.displayName = displayName
        self.urlString = urlString
        self.cellularURLString = cellularURLString
        self.cellularUsername = cellularUsername
        self.username = username
        self.isCurrent = isCurrent
        self.addedAt = addedAt
    }
}

struct DiscoverCache: Codable {
    var serverID: String
    var albumIDs: [String]
    var lastRefresh: Date
}
