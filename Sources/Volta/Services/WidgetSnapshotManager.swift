import Foundation
import VoltaLiveActivitySupport
import WidgetKit

enum WidgetSnapshotManager {
    static let libraryWidgetKind = "com.ayo.music.library"
    static let listeningWidgetKind = "com.ayo.music.listening"

    static func updateLibrary(with stats: LibraryStatsData) {
        VoltaWidgetDataStore.update { snapshot in
            snapshot.library = .init(
                source: stats.source,
                songs: stats.totalSongs,
                albums: stats.totalAlbums,
                artists: stats.totalArtists,
                totalSeconds: stats.totalSeconds,
                losslessTracks: stats.losslessTracks,
                hiResTracks: stats.hiResTracks,
                scannedAt: stats.scannedAt,
                primaryFormat: stats.fileFormats.first?.label,
                commonResolution: commonAudioProfile(from: stats)
            )
        }
        reloadWidgets()
    }

    /// Some servers expose only sample rate or only bit depth. Preserve the
    /// available value instead of treating the whole profile as unknown.
    private static func commonAudioProfile(from stats: LibraryStatsData) -> String? {
        let values = [stats.bitDepths.first?.label, stats.sampleRates.first?.label]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    static func refreshListening() {
        updateListening(using: StatsStore.shared.allEvents())
    }

    static func updateListening(using events: [PlayEvent], now: Date = .now) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? dayStart
        let today = events.filter { $0.timestamp >= dayStart && $0.timestamp <= now }
        let week = events.filter { $0.timestamp >= weekStart && $0.timestamp <= now }
        let weekDailyPlays = (0..<7).map { offset in
            guard let start = calendar.date(byAdding: .day, value: offset, to: weekStart),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }
            return events.count { $0.timestamp >= start && $0.timestamp < end && $0.timestamp <= now }
        }
        let activeDays = Set(events.map { calendar.startOfDay(for: $0.timestamp) })

        var streakDay = dayStart
        if !activeDays.contains(streakDay) {
            streakDay = calendar.date(byAdding: .day, value: -1, to: streakDay) ?? streakDay
        }
        var activeStreak = 0
        while activeDays.contains(streakDay) {
            activeStreak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: streakDay) else { break }
            streakDay = previous
        }

        VoltaWidgetDataStore.update { snapshot in
            snapshot.listening = .init(
                dayStart: dayStart,
                todayPlays: today.count,
                todaySeconds: today.reduce(0) { $0 + $1.duration },
                weekPlays: week.count,
                weekSeconds: week.reduce(0) { $0 + $1.duration },
                allTimePlays: events.count,
                allTimeSeconds: events.reduce(0) { $0 + $1.duration },
                activeStreak: activeStreak,
                lastActiveAt: events.map(\.timestamp).max(),
                updatedAt: now,
                weekDailyPlays: weekDailyPlays
            )
        }
        reloadWidgets()
    }

    private static func reloadWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: libraryWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: listeningWidgetKind)
    }
}
