import Foundation

enum LogCategory: String, CaseIterable, Sendable {
    case networking = "Networking"
    case playback   = "Playback"
    case other      = "Other"
}

struct LogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let category: LogCategory
    let level: Level
    let message: String

    enum Level: String, Sendable { case info, warning, error }

    var formatted: String {
        let t = timestamp.formatted(date: .omitted, time: .standard)
        return "[\(t)] [\(level.rawValue.uppercased())] \(message)"
    }
}

extension Notification.Name {
    static let logEntryAdded = Notification.Name("LogEntryAdded")
}

final class AppLogger: @unchecked Sendable {
    static let shared = AppLogger()

    private var entries: [LogEntry] = []
    private let lock = NSLock()
    private let maxEntries = 4000

    func log(_ message: String, category: LogCategory = .other, level: LogEntry.Level = .info) {
        let entry = LogEntry(timestamp: .now, category: category, level: level, message: message)
        lock.withLock {
            entries.append(entry)
            if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .logEntryAdded, object: nil)
        }
    }

    func entries(for category: LogCategory) -> [LogEntry] {
        lock.withLock { entries.filter { $0.category == category } }
    }

    func allEntries() -> [LogEntry] {
        lock.withLock { entries }
    }

    func clear(category: LogCategory) {
        lock.withLock { entries.removeAll { $0.category == category } }
    }

    func clearAll() {
        lock.withLock { entries.removeAll() }
    }

    func allFormatted(category: LogCategory) -> String {
        entries(for: category).map(\.formatted).joined(separator: "\n")
    }
}
