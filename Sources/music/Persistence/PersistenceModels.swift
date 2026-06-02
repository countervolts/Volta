import Foundation

struct ServerRecord: Codable, Identifiable, Hashable {
    var id: String
    var displayName: String
    var urlString: String
    var username: String
    var isCurrent: Bool
    var addedAt: Date

    init(id: String = UUID().uuidString,
         displayName: String,
         urlString: String,
         username: String,
         isCurrent: Bool = false,
         addedAt: Date = .now) {
        self.id = id
        self.displayName = displayName
        self.urlString = urlString
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
