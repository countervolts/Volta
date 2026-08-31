import Foundation

// Generic on-disk cache for Codable API snapshots, stored under Caches/api.
// Used to hydrate views instantly on launch before the network refresh lands.
// Caches directory storage; the system may reclaim it.
enum DiskCache {
    private static let maxBytes = 40 * 1_048_576
    private static let maxAge: TimeInterval = 30 * 24 * 60 * 60
    private static let pruneInterval: TimeInterval = 5 * 60
    private static let pruneLock = NSLock()
    private static var pruneScheduled = false
    private static var lastPruneAt = Date.distantPast
    static let directory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("api", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        let url = directory.appendingPathComponent(key + ".json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        let url = directory.appendingPathComponent(key + ".json")
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
        schedulePrune()
    }

    static func clear() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static func schedulePrune() {
        pruneLock.lock()
        let now = Date()
        guard !pruneScheduled, now.timeIntervalSince(lastPruneAt) >= pruneInterval else {
            pruneLock.unlock()
            return
        }
        pruneScheduled = true
        lastPruneAt = now
        pruneLock.unlock()
        DispatchQueue.global(qos: .utility).async {
            prune()
            pruneLock.lock()
            pruneScheduled = false
            pruneLock.unlock()
        }
    }

    private static func prune() {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let now = Date()
        let files = entries.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                  values.isRegularFile == true else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
        for file in files where now.timeIntervalSince(file.2) > maxAge {
            try? FileManager.default.removeItem(at: file.0)
        }
        let fresh = files.filter { now.timeIntervalSince($0.2) <= maxAge }
        var total = fresh.reduce(0) { $0 + $1.1 }
        guard total > maxBytes else { return }
        for file in fresh.sorted(by: { $0.2 < $1.2 }) {
            guard total > maxBytes else { break }
            try? FileManager.default.removeItem(at: file.0)
            total -= file.1
        }
    }
}
