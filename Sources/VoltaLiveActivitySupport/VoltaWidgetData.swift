import Foundation

public struct VoltaWidgetSnapshot: Codable, Hashable, Sendable {
    public struct Library: Codable, Hashable, Sendable {
        public var source: String
        public var songs: Int
        public var albums: Int
        public var artists: Int
        public var totalSeconds: Int
        public var losslessTracks: Int
        public var hiResTracks: Int
        public var scannedAt: Date
        public var primaryFormat: String?
        public var commonResolution: String?

        public init(
            source: String,
            songs: Int,
            albums: Int,
            artists: Int,
            totalSeconds: Int,
            losslessTracks: Int,
            hiResTracks: Int,
            scannedAt: Date,
            primaryFormat: String? = nil,
            commonResolution: String? = nil
        ) {
            self.source = source
            self.songs = songs
            self.albums = albums
            self.artists = artists
            self.totalSeconds = totalSeconds
            self.losslessTracks = losslessTracks
            self.hiResTracks = hiResTracks
            self.scannedAt = scannedAt
            self.primaryFormat = primaryFormat
            self.commonResolution = commonResolution
        }
    }

    public struct Listening: Codable, Hashable, Sendable {
        public var dayStart: Date
        public var todayPlays: Int
        public var todaySeconds: Int
        public var weekPlays: Int
        public var weekSeconds: Int
        public var allTimePlays: Int
        public var allTimeSeconds: Int
        public var activeStreak: Int
        public var lastActiveAt: Date?
        public var updatedAt: Date
        /// Monday/Sunday-aligned totals for the current calendar week, used for
        /// the compact activity chart in the large Home Screen widget.
        public var weekDailyPlays: [Int]?

        public init(
            dayStart: Date,
            todayPlays: Int,
            todaySeconds: Int,
            weekPlays: Int,
            weekSeconds: Int,
            allTimePlays: Int,
            allTimeSeconds: Int,
            activeStreak: Int,
            lastActiveAt: Date?,
            updatedAt: Date,
            weekDailyPlays: [Int]? = nil
        ) {
            self.dayStart = dayStart
            self.todayPlays = todayPlays
            self.todaySeconds = todaySeconds
            self.weekPlays = weekPlays
            self.weekSeconds = weekSeconds
            self.allTimePlays = allTimePlays
            self.allTimeSeconds = allTimeSeconds
            self.activeStreak = activeStreak
            self.lastActiveAt = lastActiveAt
            self.updatedAt = updatedAt
            self.weekDailyPlays = weekDailyPlays
        }
    }

    public var library: Library?
    public var listening: Listening?

    public init(library: Library? = nil, listening: Listening? = nil) {
        self.library = library
        self.listening = listening
    }
}

/// App-group backed storage shared by the app and its WidgetKit extension.
public enum VoltaWidgetDataStore {
    public static let appGroupIdentifier = "group.com.ayo.music"

    private static let snapshotKey = "volta.widget.snapshot.v1"
    private static let queue = DispatchQueue(label: "com.ayo.music.widget-data")

    public static func load() -> VoltaWidgetSnapshot {
        queue.sync { loadLocked() }
    }

    public static func update(_ mutation: (inout VoltaWidgetSnapshot) -> Void) {
        queue.sync {
            var snapshot = loadLocked()
            mutation(&snapshot)
            saveLocked(snapshot)
        }
    }

    private static func loadLocked() -> VoltaWidgetSnapshot {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(VoltaWidgetSnapshot.self, from: data) else {
            return VoltaWidgetSnapshot()
        }
        return snapshot
    }

    private static func saveLocked(_ snapshot: VoltaWidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }
}
