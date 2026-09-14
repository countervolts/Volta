import Foundation

enum LogCategory: String, CaseIterable, Codable, Sendable {
    case networking = "Networking"
    case playback   = "Playback"
    case library    = "Library"
    case lyrics     = "Lyrics"
    case downloads  = "Downloads"
    case artwork    = "Artwork"
    case ui         = "UI"
    case settings   = "Settings"
    case other      = "Other"
}

struct LogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let category: LogCategory
    let level: Level
    let message: String

    enum Level: String, CaseIterable, Codable, Sendable { case info, warning, error }

    var formatted: String {
        let t = timestamp.formatted(date: .omitted, time: .standard)
        return "[\(t)] [\(category.rawValue)] [\(level.rawValue.uppercased())] \(message)"
    }
}

extension Notification.Name {
    static let logEntryAdded = Notification.Name("LogEntryAdded")
    static let logEntriesChanged = Notification.Name("LogEntriesChanged")
}

final class AppLogger: @unchecked Sendable {
    static let shared = AppLogger()

    private var entries: [LogEntry] = []
    private let lock = NSLock()
    private let persistenceQueue = DispatchQueue(label: "com.ayo.volta.log-persistence")
    private let maxEntries = 4000
    private let maxPersistedEntries = 240
    private let persistenceURL: URL?

    private struct PersistedEntry: Codable, Sendable {
        let timestamp: Date
        let category: LogCategory
        let level: LogEntry.Level
        let message: String
    }

    private init() {
        let applicationSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        persistenceURL = applicationSupport?.appendingPathComponent(
            "VoltaLogBuffer.json",
            isDirectory: false
        )
        loadPersistedEntries()
    }

    func log(_ message: String, category: LogCategory = .other, level: LogEntry.Level = .info) {
        let verbose = UserDefaults.standard.object(forKey: "developerLogging") as? Bool ?? true
        guard verbose || level != .info else { return }
        append(message, category: category, level: level)
    }

    func logAlways(_ message: String, category: LogCategory = .other, level: LogEntry.Level = .info) {
        append(message, category: category, level: level)
    }

    private func append(_ message: String, category: LogCategory, level: LogEntry.Level) {
        let entry = LogEntry(timestamp: .now, category: category, level: level, message: message)
        lock.withLock {
            entries.append(entry)
            if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
            let persistedEntries = entries.suffix(maxPersistedEntries).map {
                PersistedEntry(
                    timestamp: $0.timestamp,
                    category: $0.category,
                    level: $0.level,
                    message: $0.message
                )
            }
            // Queue the snapshot while holding the same lock that orders
            // in-memory appends, so background writes cannot finish out of order.
            persist(persistedEntries)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .logEntryAdded, object: entry)
            if level != .info {
                VoltaNotificationCenter.shared.postLog(entry)
            }
        }
    }

    func entries(for category: LogCategory) -> [LogEntry] {
        lock.withLock { entries.filter { $0.category == category } }
    }

    func allEntries() -> [LogEntry] {
        lock.withLock { entries }
    }

    func countsByCategory() -> [LogCategory: Int] {
        lock.withLock {
            entries.reduce(into: [:]) { counts, entry in
                counts[entry.category, default: 0] += 1
            }
        }
    }

    func countsByLevel() -> [LogEntry.Level: Int] {
        lock.withLock {
            entries.reduce(into: [:]) { counts, entry in
                counts[entry.level, default: 0] += 1
            }
        }
    }

    func estimatedSizeBytes() -> Int {
        lock.withLock {
            entries.map(\.formatted).joined(separator: "\n").lengthOfBytes(using: .utf8)
        }
    }

    func clear(category: LogCategory) {
        lock.withLock { entries.removeAll { $0.category == category } }
        notifyEntriesChanged()
    }

    func clearAll() {
        lock.withLock { entries.removeAll() }
        notifyEntriesChanged()
    }

    func allFormatted(category: LogCategory) -> String {
        entries(for: category).map(\.formatted).joined(separator: "\n")
    }

    func allFormatted() -> String {
        allEntries().map(\.formatted).joined(separator: "\n")
    }

    func recentFormatted(limit: Int = 120) -> String {
        lock.withLock {
            entries.suffix(max(0, limit)).map(\.formatted).joined(separator: "\n")
        }
    }

    private func notifyEntriesChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .logEntriesChanged, object: nil)
        }
    }

    private func loadPersistedEntries() {
        guard let persistenceURL,
              let data = try? Data(contentsOf: persistenceURL),
              let persisted = try? JSONDecoder().decode([PersistedEntry].self, from: data) else {
            return
        }
        entries = persisted.map {
            LogEntry(timestamp: $0.timestamp, category: $0.category, level: $0.level, message: $0.message)
        }
    }

    private func persist(_ persistedEntries: [PersistedEntry]) {
        guard let persistenceURL else { return }
        persistenceQueue.async {
            guard let data = try? JSONEncoder().encode(persistedEntries) else { return }
            try? data.write(to: persistenceURL, options: .atomic)
        }
    }
}
