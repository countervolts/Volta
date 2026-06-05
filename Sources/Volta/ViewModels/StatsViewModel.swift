import Foundation
import Observation

enum StatsPeriod: String, CaseIterable, Identifiable {
    case allTime = "All Time"
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case yearly = "Yearly"
    var id: String { rawValue }
}

struct TopEntry: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let coverArt: String?
    let plays: Int
    let totalDuration: Int  // seconds
}

struct HourlyBucket: Identifiable {
    let id: Int    // 0-23 hour
    let count: Int
}

struct DayBucket: Identifiable {
    let id: Int    // 0=Sun … 6=Sat
    let count: Int
    let label: String
}

struct GenreBucket: Identifiable {
    let id: String
    let genre: String
    let count: Int
}

struct DateBucket: Identifiable {
    let id: String
    let date: Date
    let count: Int
    let minutes: Double
}

struct MonthBucket: Identifiable {
    let id: Int    // 1-12
    let label: String
    let count: Int
    let minutes: Double
}

@MainActor
@Observable
final class StatsViewModel {
    var period: StatsPeriod = .allTime
    var offset: Int = 0   // navigate backwards (0 = current)

    // computed stats refreshed when period/offset changes
    private(set) var totalPlays: Int = 0
    private(set) var totalSeconds: Int = 0
    private(set) var uniqueSongs: Int = 0
    private(set) var uniqueAlbums: Int = 0
    private(set) var uniqueArtists: Int = 0
    private(set) var sessions: Int = 0
    private(set) var avgPlaysPerDay: Double = 0
    private(set) var avgTracksPerDay: Double = 0
    private(set) var avgListenPerDay: Double = 0  // minutes
    private(set) var avgTrackLength: Double = 0   // seconds
    private(set) var longestSession: Int = 0       // seconds
    private(set) var topGenre: String = "-"
    private(set) var streak: Int = 0
    private(set) var longestStreak: Int = 0
    private(set) var bestMonth: String = "-"
    private(set) var bestMonthCount: Int = 0
    private(set) var activeDays: Int = 0
    private(set) var periodDays: Int = 1
    private(set) var avgTracksPerMonth: Double = 0

    private(set) var topSongs: [TopEntry] = []
    private(set) var topArtists: [TopEntry] = []
    private(set) var topAlbums: [TopEntry] = []

    private(set) var hourlyData: [HourlyBucket] = []
    private(set) var dayOfWeekData: [DayBucket] = []
    private(set) var genreData: [GenreBucket] = []
    private(set) var dailyData: [DateBucket] = []
    private(set) var monthlyData: [MonthBucket] = []

    private(set) var periodLabel: String = ""

    private let store = StatsStore.shared
    private let cal = Calendar.current

    // MARK: - Recompute

    func recompute() {
        let (start, end) = dateRange()
        let events = store.events(from: start, to: end)
        periodLabel = makePeriodLabel(start: start, end: end)
        if period == .allTime, let earliest = events.min(by: { $0.timestamp < $1.timestamp }) {
            periodDays = max(1, cal.dateComponents([.day], from: cal.startOfDay(for: earliest.timestamp), to: end).day ?? 1)
        } else {
            periodDays = max(1, cal.dateComponents([.day], from: start, to: end).day ?? 1)
        }

        totalPlays = events.count
        totalSeconds = events.reduce(0) { $0 + $1.duration }
        uniqueSongs = Set(events.map(\.songID)).count
        uniqueAlbums = Set(events.compactMap(\.albumID)).count
        uniqueArtists = Set(events.compactMap(\.artistID)).count

        avgPlaysPerDay = Double(totalPlays) / Double(periodDays)
        avgTracksPerDay = avgPlaysPerDay
        avgListenPerDay = Double(totalSeconds) / 60.0 / Double(periodDays)
        avgTrackLength = events.isEmpty ? 0 : Double(totalSeconds) / Double(events.count)
        avgTracksPerMonth = Double(totalPlays) / max(1, Double(periodDays) / 30.4)

        topSongs = topEntries(events: events, keyPath: \.songID, titleFn: { $0.title }, subtitleFn: { $0.artist }, coverFn: { $0.coverArt })
        topArtists = topEntriesArtist(events: events)
        topAlbums = topEntriesAlbum(events: events)

        topGenre = topGenreString(events: events)
        genreData = genreBuckets(events: events)
        hourlyData = hourlyBuckets(events: events)
        dayOfWeekData = dayOfWeekBuckets(events: events)
        dailyData = dailyBuckets(events: events, start: start, end: end)
        monthlyData = monthlyBuckets(events: events)

        streak = currentStreak()
        longestStreak = longestStreakCalc()
        activeDays = Set(events.map { cal.startOfDay(for: $0.timestamp) }).count
        sessions = estimateSessions(events: events)
        longestSession = longestSessionSeconds(events: events)

        let bestMonthData = monthlyData.max(by: { $0.count < $1.count })
        bestMonth = bestMonthData?.label ?? "-"
        bestMonthCount = bestMonthData?.count ?? 0
    }

    // MARK: - Date range

    private func dateRange() -> (Date, Date) {
        let now = Date()
        switch period {
        case .allTime:
            return (Date.distantPast, now)
        case .daily:
            let day = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: now))!
            return (day, cal.date(byAdding: .day, value: 1, to: day)!)
        case .weekly:
            let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            let shifted = cal.date(byAdding: .weekOfYear, value: -offset, to: weekStart)!
            return (shifted, cal.date(byAdding: .weekOfYear, value: 1, to: shifted)!)
        case .monthly:
            let comps = cal.dateComponents([.year, .month], from: now)
            let monthStart = cal.date(from: comps)!
            let shifted = cal.date(byAdding: .month, value: -offset, to: monthStart)!
            return (shifted, cal.date(byAdding: .month, value: 1, to: shifted)!)
        case .yearly:
            let yearStart = cal.date(from: cal.dateComponents([.year], from: now))!
            let shifted = cal.date(byAdding: .year, value: -offset, to: yearStart)!
            return (shifted, cal.date(byAdding: .year, value: 1, to: shifted)!)
        }
    }

    private func makePeriodLabel(start: Date, end: Date) -> String {
        switch period {
        case .allTime: return "All Time"
        case .daily: return start.formatted(date: .abbreviated, time: .omitted)
        case .weekly:
            let endDay = cal.date(byAdding: .day, value: -1, to: end) ?? end
            return "\(start.formatted(date: .abbreviated, time: .omitted)) – \(endDay.formatted(date: .abbreviated, time: .omitted))"
        case .monthly: return start.formatted(.dateTime.month(.wide).year())
        case .yearly: return start.formatted(.dateTime.year())
        }
    }

    // MARK: - Top entries

    private func topEntries(events: [PlayEvent], keyPath: KeyPath<PlayEvent, String>,
                            titleFn: (PlayEvent) -> String,
                            subtitleFn: (PlayEvent) -> String,
                            coverFn: (PlayEvent) -> String?,
                            limit: Int = 15) -> [TopEntry] {
        var plays: [String: Int] = [:]
        var dur: [String: Int] = [:]
        var meta: [String: (String, String, String?)] = [:]
        for e in events {
            let key = e[keyPath: keyPath]
            plays[key, default: 0] += 1
            dur[key, default: 0] += e.duration
            if meta[key] == nil { meta[key] = (titleFn(e), subtitleFn(e), coverFn(e)) }
        }
        return plays.sorted { $0.value > $1.value }
            .prefix(limit)
            .compactMap { k, v in
                guard let m = meta[k] else { return nil }
                return TopEntry(id: k, title: m.0, subtitle: m.1, coverArt: m.2, plays: v, totalDuration: dur[k] ?? 0)
            }
    }

    private func topEntriesArtist(events: [PlayEvent], limit: Int = 15) -> [TopEntry] {
        var plays: [String: Int] = [:]
        var dur: [String: Int] = [:]
        var meta: [String: (String, String?)] = [:]
        for e in events {
            // group by the primary artist so "Artist1, Artist2" features count toward
            // the lead artist instead of becoming their own bogus artist entry
            let key = Self.primaryArtist(e.artist)
            plays[key, default: 0] += 1
            dur[key, default: 0] += e.duration
            if meta[key] == nil { meta[key] = (key, e.coverArt) }
        }
        return plays.sorted { $0.value > $1.value }
            .prefix(limit)
            .compactMap { k, v in
                guard let m = meta[k] else { return nil }
                return TopEntry(id: k, title: m.0, subtitle: "", coverArt: m.1, plays: v, totalDuration: dur[k] ?? 0)
            }
    }

    // the lead artist from a combined credit like "A, B" / "A feat. B" / "A & B"
    static func primaryArtist(_ s: String) -> String {
        var name = s
        let separators = [",", " feat.", " feat ", " ft.", " ft ", " featuring ", " & ", " x ", ";", " with "]
        for sep in separators {
            if let r = name.range(of: sep, options: [.caseInsensitive]) {
                name = String(name[..<r.lowerBound])
            }
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? s : trimmed
    }

    private func topEntriesAlbum(events: [PlayEvent], limit: Int = 15) -> [TopEntry] {
        var plays: [String: Int] = [:]
        var dur: [String: Int] = [:]
        var meta: [String: (String, String, String?)] = [:]
        for e in events {
            let key = e.album
            plays[key, default: 0] += 1
            dur[key, default: 0] += e.duration
            if meta[key] == nil { meta[key] = (e.album, e.artist, e.coverArt) }
        }
        return plays.sorted { $0.value > $1.value }
            .prefix(limit)
            .compactMap { k, v in
                guard let m = meta[k] else { return nil }
                return TopEntry(id: k, title: m.0, subtitle: m.1, coverArt: m.2, plays: v, totalDuration: dur[k] ?? 0)
            }
    }

    // MARK: - Chart data

    private func topGenreString(events: [PlayEvent]) -> String {
        var counts: [String: Int] = [:]
        for e in events { if let g = e.genre { counts[g, default: 0] += 1 } }
        return counts.max(by: { $0.value < $1.value })?.key ?? "-"
    }

    private func genreBuckets(events: [PlayEvent]) -> [GenreBucket] {
        var counts: [String: Int] = [:]
        for e in events { if let g = e.genre { counts[g, default: 0] += 1 } }
        return counts.sorted { $0.value > $1.value }
            .prefix(8)
            .map { GenreBucket(id: $0.key, genre: $0.key, count: $0.value) }
    }

    private func hourlyBuckets(events: [PlayEvent]) -> [HourlyBucket] {
        var counts = [Int: Int]()
        for e in events {
            let h = cal.component(.hour, from: e.timestamp)
            counts[h, default: 0] += 1
        }
        return (0..<24).map { HourlyBucket(id: $0, count: counts[$0] ?? 0) }
    }

    private func dayOfWeekBuckets(events: [PlayEvent]) -> [DayBucket] {
        let labels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        var counts = [Int: Int]()
        for e in events {
            let d = cal.component(.weekday, from: e.timestamp) - 1
            counts[d, default: 0] += 1
        }
        return (0..<7).map { DayBucket(id: $0, count: counts[$0] ?? 0, label: labels[$0]) }
    }

    private func dailyBuckets(events: [PlayEvent], start: Date, end: Date) -> [DateBucket] {
        var map: [Date: (Int, Double)] = [:]
        for e in events {
            let day = cal.startOfDay(for: e.timestamp)
            map[day, default: (0, 0)].0 += 1
            map[day, default: (0, 0)].1 += Double(e.duration) / 60.0
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return map.sorted { $0.key < $1.key }
            .map { DateBucket(id: fmt.string(from: $0.key), date: $0.key, count: $0.value.0, minutes: $0.value.1) }
    }

    private func monthlyBuckets(events: [PlayEvent]) -> [MonthBucket] {
        var map: [Int: (Int, Double)] = [:]
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM"
        for e in events {
            let m = cal.component(.month, from: e.timestamp)
            map[m, default: (0, 0)].0 += 1
            map[m, default: (0, 0)].1 += Double(e.duration) / 60.0
        }
        return (1...12).compactMap { m -> MonthBucket? in
            guard let v = map[m] else { return nil }
            let date = cal.date(from: DateComponents(month: m))!
            return MonthBucket(id: m, label: fmt.string(from: date), count: v.0, minutes: v.1)
        }
    }

    // MARK: - Streaks

    private func currentStreak() -> Int {
        let all = store.allEvents()
        let days = Set(all.map { cal.startOfDay(for: $0.timestamp) }).sorted(by: >)
        guard !days.isEmpty else { return 0 }
        var streak = 0
        var cursor = cal.startOfDay(for: Date())
        for day in days {
            if day == cursor {
                streak += 1
                cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
            } else if day < cursor {
                break
            }
        }
        return streak
    }

    private func longestStreakCalc() -> Int {
        let all = store.allEvents()
        let days = Set(all.map { cal.startOfDay(for: $0.timestamp) }).sorted()
        guard !days.isEmpty else { return 0 }
        var best = 1, current = 1
        for i in 1..<days.count {
            let diff = cal.dateComponents([.day], from: days[i-1], to: days[i]).day ?? 0
            if diff == 1 { current += 1; best = max(best, current) }
            else { current = 1 }
        }
        return best
    }

    // MARK: - Sessions (30-min gap = new session)

    private func estimateSessions(events: [PlayEvent]) -> Int {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else { return 0 }
        var count = 1
        for i in 1..<sorted.count {
            let gap = sorted[i].timestamp.timeIntervalSince(sorted[i-1].timestamp)
            if gap > 30 * 60 { count += 1 }
        }
        return count
    }

    private func longestSessionSeconds(events: [PlayEvent]) -> Int {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else { return 0 }
        var best = 0, current = sorted[0].duration
        for i in 1..<sorted.count {
            let gap = sorted[i].timestamp.timeIntervalSince(sorted[i-1].timestamp)
            if gap <= 30 * 60 {
                current += sorted[i].duration
            } else {
                best = max(best, current)
                current = sorted[i].duration
            }
        }
        return max(best, current)
    }
}
