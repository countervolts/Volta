import SwiftUI
import UIKit
import VoltaLiveActivitySupport
import WidgetKit

private struct VoltaWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: VoltaWidgetSnapshot
}

private struct VoltaWidgetTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> VoltaWidgetEntry {
        VoltaWidgetEntry(date: .now, snapshot: previewSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (VoltaWidgetEntry) -> Void) {
        completion(VoltaWidgetEntry(date: .now, snapshot: VoltaWidgetDataStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VoltaWidgetEntry>) -> Void) {
        let now = Date()
        let entry = VoltaWidgetEntry(date: now, snapshot: VoltaWidgetDataStore.load())
        completion(Timeline(entries: [entry], policy: .after(nextRefresh(after: now))))
    }

    private func nextRefresh(after date: Date) -> Date {
        Calendar.current.nextDate(
            after: date,
            matching: DateComponents(hour: 0, minute: 5),
            matchingPolicy: .nextTime
        ) ?? date.addingTimeInterval(6 * 60 * 60)
    }

    private var previewSnapshot: VoltaWidgetSnapshot {
        .init(
            library: .init(
                source: "My Library",
                songs: 12_847,
                albums: 1_086,
                artists: 734,
                totalSeconds: 2_868_600,
                losslessTracks: 9_604,
                hiResTracks: 2_317,
                scannedAt: .now,
                primaryFormat: "FLAC",
                commonResolution: "24-bit · 96 kHz"
            ),
            listening: .init(
                dayStart: Calendar.current.startOfDay(for: .now),
                todayPlays: 23,
                todaySeconds: 4_740,
                weekPlays: 147,
                weekSeconds: 30_180,
                allTimePlays: 5_817,
                allTimeSeconds: 1_238_400,
                activeStreak: 8,
                lastActiveAt: .now,
                updatedAt: .now,
                weekDailyPlays: [18, 24, 9, 31, 17, 25, 23]
            )
        )
    }
}

@available(iOS 16.1, *)
struct VoltaLibraryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.ayo.music.library", provider: VoltaWidgetTimelineProvider()) { entry in
            VoltaLibraryWidgetView(entry: entry)
        }
        .configurationDisplayName("Library Overview")
        .description("A concise readout of your music collection.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@available(iOS 16.1, *)
struct VoltaListeningWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.ayo.music.listening", provider: VoltaWidgetTimelineProvider()) { entry in
            VoltaListeningWidgetView(entry: entry)
        }
        .configurationDisplayName("Listening Activity")
        .description("Today’s listening and a seven-day play log.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Library overview

@available(iOS 16.1, *)
private struct VoltaLibraryWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: VoltaWidgetEntry
    private let tone: VoltaWidgetTone = .library

    var body: some View {
        Group {
            if let library = entry.snapshot.library {
                content(for: library)
            } else {
                VoltaWidgetEmptyState(
                    tone: tone,
                    title: "Library overview",
                    message: "Open Stats → Library in Volta to prepare the first readout."
                )
            }
        }
        .voltaWidgetSurface(tone)
        .widgetURL(URL(string: "volta://stats/library"))
    }

    @ViewBuilder
    private func content(for library: VoltaWidgetSnapshot.Library) -> some View {
        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 7) {
                VoltaWidgetHeader(title: "LIBRARY", detail: nil, tone: tone)
                Spacer(minLength: 0)
                libraryLead(library, compact: true)
                VoltaWidgetRule(tone: tone)
                HStack(spacing: 12) {
                    VoltaDatum(value: VoltaWidgetFormat.count(library.albums), label: "Albums", tone: tone)
                    VoltaDatum(value: VoltaWidgetFormat.count(library.artists), label: "Artists", tone: tone)
                }
            }

        case .systemLarge:
            VStack(alignment: .leading, spacing: 11) {
                VoltaWidgetHeader(title: "LIBRARY", detail: library.source, tone: tone)
                libraryLead(library)
                VoltaWidgetRule(tone: tone)
                HStack(spacing: 18) {
                    VoltaDatum(value: VoltaWidgetFormat.count(library.albums), label: "Albums", tone: tone)
                    VoltaDatum(value: VoltaWidgetFormat.count(library.artists), label: "Artists", tone: tone)
                }
                HStack(spacing: 18) {
                    VoltaDatum(value: VoltaWidgetFormat.count(library.losslessTracks), label: "Lossless", tone: tone)
                    VoltaDatum(value: VoltaWidgetFormat.count(library.hiResTracks), label: "Hi-Res", tone: tone)
                }
                HStack(spacing: 18) {
                    VoltaDatum(value: averageAlbumTracks(library), label: "Tracks per album", tone: tone)
                    VoltaDatum(value: averageTrackLength(library), label: "Average track", tone: tone)
                }
                Spacer(minLength: 0)
                VoltaWidgetRule(tone: tone)
                VoltaLibraryMix(library: library, tone: tone)
            }

        default:
            VStack(alignment: .leading, spacing: 7) {
                VoltaWidgetHeader(title: "LIBRARY", detail: library.source, tone: tone)
                libraryLead(library, compact: true)
                VoltaWidgetRule(tone: tone)
                HStack(spacing: 12) {
                    VoltaDatum(value: VoltaWidgetFormat.count(library.albums), label: "Albums", tone: tone)
                    VoltaDatum(value: VoltaWidgetFormat.count(library.artists), label: "Artists", tone: tone)
                    VoltaDatum(value: VoltaWidgetFormat.duration(library.totalSeconds), label: "Run time", tone: tone)
                }
            }
        }
    }

    private func libraryLead(_ library: VoltaWidgetSnapshot.Library, compact: Bool = false) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(VoltaWidgetFormat.count(library.songs))
                .font(.system(size: compact ? 39 : 48, weight: .medium, design: .serif))
                .foregroundStyle(tone.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("tracks")
                .font(.subheadline)
                .foregroundStyle(tone.secondary)
            Spacer(minLength: 0)
            if !compact {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(VoltaWidgetFormat.duration(library.totalSeconds))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tone.primary)
                    Text("total duration")
                        .font(.caption2)
                        .foregroundStyle(tone.secondary)
                }
            }
        }
    }

    private func averageAlbumTracks(_ library: VoltaWidgetSnapshot.Library) -> String {
        guard library.albums > 0 else { return "—" }
        let value = Double(library.songs) / Double(library.albums)
        return value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func averageTrackLength(_ library: VoltaWidgetSnapshot.Library) -> String {
        guard library.songs > 0 else { return "—" }
        return VoltaWidgetFormat.duration(library.totalSeconds / library.songs)
    }
}

// MARK: - Listening activity

@available(iOS 16.1, *)
private struct VoltaListeningWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: VoltaWidgetEntry
    private let tone: VoltaWidgetTone = .listening

    private var listening: VoltaWidgetSnapshot.Listening? { entry.snapshot.listening }

    private var isTodayCurrent: Bool {
        guard let listening else { return false }
        return Calendar.current.isDate(listening.dayStart, inSameDayAs: entry.date)
    }

    private var todayPlays: Int { isTodayCurrent ? listening?.todayPlays ?? 0 : 0 }
    private var todaySeconds: Int { isTodayCurrent ? listening?.todaySeconds ?? 0 : 0 }

    private var activeStreak: Int {
        guard let listening, let lastActiveAt = listening.lastActiveAt else { return 0 }
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: entry.date) ?? entry.date
        return calendar.isDate(lastActiveAt, inSameDayAs: entry.date)
            || calendar.isDate(lastActiveAt, inSameDayAs: yesterday)
            ? listening.activeStreak
            : 0
    }

    var body: some View {
        Group {
            if let listening {
                content(for: listening)
            } else {
                VoltaWidgetEmptyState(
                    tone: tone,
                    title: "Listening activity",
                    message: "Play a song in Volta and your listening log will begin here."
                )
            }
        }
        .voltaWidgetSurface(tone)
        .widgetURL(URL(string: "volta://stats/listening"))
    }

    @ViewBuilder
    private func content(for listening: VoltaWidgetSnapshot.Listening) -> some View {
        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 7) {
                VoltaWidgetHeader(title: "TODAY", detail: dateLabel, tone: tone)
                Spacer(minLength: 0)
                listeningLead(compact: true)
                VoltaWidgetRule(tone: tone)
                HStack(spacing: 12) {
                    VoltaDatum(value: VoltaWidgetFormat.count(listening.weekPlays), label: "This week", tone: tone)
                    VoltaDatum(value: activeStreak > 0 ? "\(activeStreak)d" : "—", label: "Streak", tone: tone)
                }
            }

        case .systemLarge:
            VStack(alignment: .leading, spacing: 10) {
                VoltaWidgetHeader(title: "LISTENING", detail: dateLabel, tone: tone)
                listeningLead()
                VoltaWidgetRule(tone: tone)
                VoltaWeekBars(dailyPlays: listening.weekDailyPlays, date: entry.date, tone: tone, height: 93)
                VoltaWidgetRule(tone: tone)
                HStack(spacing: 14) {
                    VoltaDatum(value: VoltaWidgetFormat.count(listening.weekPlays), label: "This week", tone: tone)
                    VoltaDatum(value: activeStreak > 0 ? "\(activeStreak) days" : "—", label: "Current run", tone: tone)
                    VoltaDatum(value: VoltaWidgetFormat.count(listening.allTimePlays), label: "All-time", tone: tone)
                }
                Spacer(minLength: 0)
                Text("Activity is updated after each completed play.")
                    .font(.caption2)
                    .foregroundStyle(tone.secondary)
            }

        default:
            VStack(alignment: .leading, spacing: 7) {
                VoltaWidgetHeader(title: "LISTENING", detail: dateLabel, tone: tone)
                HStack(alignment: .lastTextBaseline) {
                    listeningLead(compact: true)
                    Spacer(minLength: 8)
                    VoltaDatum(value: VoltaWidgetFormat.count(listening.weekPlays), label: "This week", tone: tone)
                }
                VoltaWidgetRule(tone: tone)
                VoltaWeekBars(dailyPlays: listening.weekDailyPlays, date: entry.date, tone: tone, height: 31)
                HStack(spacing: 12) {
                    VoltaDatum(value: VoltaWidgetFormat.duration(listening.weekSeconds), label: "Week time", tone: tone)
                    VoltaDatum(value: activeStreak > 0 ? "\(activeStreak) days" : "—", label: "Current run", tone: tone)
                    VoltaDatum(value: VoltaWidgetFormat.count(listening.allTimePlays), label: "All-time", tone: tone)
                }
            }
        }
    }

    private func listeningLead(compact: Bool = false) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(VoltaWidgetFormat.count(todayPlays))
                .font(.system(size: compact ? 39 : 48, weight: .medium, design: .serif))
                .foregroundStyle(tone.primary)
                .lineLimit(1)
            VStack(alignment: .leading, spacing: 0) {
                Text(todayPlays == 1 ? "play" : "plays")
                    .font(.subheadline)
                    .foregroundStyle(tone.secondary)
                Text(VoltaWidgetFormat.duration(todaySeconds))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tone.accent)
            }
        }
    }

    private var dateLabel: String {
        entry.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

// MARK: - Shared elements

@available(iOS 16.1, *)
private enum VoltaWidgetTone {
    case library
    case listening

    var background: Color {
        Color(uiColor: .systemBackground)
    }

    var primary: Color {
        Color(uiColor: .label)
    }

    var secondary: Color {
        Color(uiColor: .secondaryLabel)
    }

    var rule: Color {
        Color(uiColor: .separator)
    }

    var accent: Color {
        switch self {
        case .library: Color(uiColor: .systemIndigo)
        case .listening: Color(uiColor: .systemOrange)
        }
    }
}

@available(iOS 16.1, *)
private struct VoltaWidgetHeader: View {
    let title: String
    let detail: String?
    let tone: VoltaWidgetTone

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.bold))
                .tracking(0.85)
                .foregroundStyle(tone.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if let detail {
                Spacer(minLength: 6)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(tone.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
        }
    }
}

@available(iOS 16.1, *)
private struct VoltaWidgetRule: View {
    let tone: VoltaWidgetTone

    var body: some View {
        Rectangle()
            .fill(tone.rule)
            .frame(height: 1)
    }
}

@available(iOS 16.1, *)
private struct VoltaDatum: View {
    let value: String
    let label: String
    let tone: VoltaWidgetTone
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(compact ? .subheadline.weight(.semibold) : .headline.weight(.semibold))
                .foregroundStyle(tone.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            Text(label)
                .font(.caption2)
                .foregroundStyle(tone.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@available(iOS 16.1, *)
private struct VoltaLibraryMix: View {
    let library: VoltaWidgetSnapshot.Library
    let tone: VoltaWidgetTone

    private var losslessShare: Double {
        guard library.songs > 0 else { return 0 }
        return min(1, Double(library.losslessTracks) / Double(library.songs))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("LOSSLESS SHARE")
                    .font(.caption2.weight(.bold))
                    .tracking(0.75)
                    .foregroundStyle(tone.secondary)
                Spacer()
                Text("\(Int((losslessShare * 100).rounded()))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tone.accent)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(tone.rule)
                    Rectangle()
                        .fill(tone.accent)
                        .frame(width: proxy.size.width * losslessShare)
                }
            }
            .frame(height: 5)
            HStack {
                Text("\(VoltaWidgetFormat.count(library.losslessTracks)) lossless")
                Spacer()
                Text("\(VoltaWidgetFormat.count(max(0, library.songs - library.losslessTracks))) other")
            }
            .font(.caption2)
            .foregroundStyle(tone.secondary)
        }
    }
}

@available(iOS 16.1, *)
private struct VoltaWeekBars: View {
    let dailyPlays: [Int]?
    let date: Date
    let tone: VoltaWidgetTone
    let height: CGFloat

    private var values: [Int] {
        let source = Array((dailyPlays ?? []).prefix(7))
        return source + Array(repeating: 0, count: max(0, 7 - source.count))
    }

    private var labels: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols
        let firstIndex = calendar.firstWeekday - 1
        return (0..<7).map { String(symbols[(firstIndex + $0) % symbols.count]).uppercased() }
    }

    private var todayIndex: Int {
        let calendar = Calendar.current
        return (calendar.component(.weekday, from: date) - calendar.firstWeekday + 7) % 7
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                VStack(spacing: 4) {
                    Rectangle()
                        .fill(index == todayIndex ? tone.accent : tone.rule)
                        .frame(height: barHeight(for: value))
                    Text(labels[index])
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(index == todayIndex ? tone.primary : tone.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .bottom)
            }
        }
        .frame(height: height + 13, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week's listening activity")
    }

    private func barHeight(for value: Int) -> CGFloat {
        let maximum = max(values.max() ?? 0, 1)
        return max(2, CGFloat(value) / CGFloat(maximum) * height)
    }
}

@available(iOS 16.1, *)
private struct VoltaWidgetEmptyState: View {
    let tone: VoltaWidgetTone
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(.title3, design: .serif).weight(.medium))
                .foregroundStyle(tone.primary)
            VoltaWidgetRule(tone: tone)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(tone.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

@available(iOS 16.1, *)
private enum VoltaWidgetFormat {
    static func count(_ value: Int) -> String {
        switch value {
        case 1_000_000...:
            return compact(value, divisor: 1_000_000, suffix: "M")
        case 1_000...:
            return compact(value, divisor: 1_000, suffix: "K")
        default:
            return String(value)
        }
    }

    static func duration(_ seconds: Int) -> String {
        let totalMinutes = max(0, seconds) / 60
        let totalHours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if totalHours >= 48 { return "\(totalHours / 24)d \(totalHours % 24)h" }
        if totalHours > 0 { return "\(totalHours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private static func compact(_ value: Int, divisor: Int, suffix: String) -> String {
        let rounded = (Double(value) / Double(divisor) * 10).rounded() / 10
        let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
        return text + suffix
    }
}

@available(iOS 16.1, *)
private extension View {
    @ViewBuilder
    func voltaWidgetSurface(_ tone: VoltaWidgetTone) -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(for: .widget) { tone.background }
        } else {
            background(tone.background)
        }
    }
}
