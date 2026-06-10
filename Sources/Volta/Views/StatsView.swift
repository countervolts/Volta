import SwiftUI
import Charts

struct StatsView: View {
    @State private var vm = StatsViewModel()
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        periodSelector
                        periodNavigation
                        Divider().background(Theme.secondaryText.opacity(0.2))

                        switch vm.period {
                        case .allTime: AllTimeStatsSection(vm: vm)
                        case .daily: DailyStatsSection(vm: vm)
                        case .weekly: WeeklyStatsSection(vm: vm)
                        case .monthly: MonthlyStatsSection(vm: vm)
                        case .yearly: YearlyStatsSection(vm: vm)
                        }

                        Color.clear.frame(height: 80)
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.large)
            .accountToolbar()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exportStats()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .tint(Theme.accent)
                }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(Theme.colorScheme)
        .onChange(of: vm.period) { _, _ in vm.offset = 0; vm.recompute() }
        .onChange(of: vm.offset) { _, _ in vm.recompute() }
        .task { vm.recompute() }
        .onAppear { vm.recompute() }
        .onReceive(NotificationCenter.default.publisher(for: .playEventRecorded)) { _ in
            vm.recompute()
        }
    }

    private func exportStats() {
        do {
            let urls = try StatsExporter.exportURLs()
            VoltaNotificationCenter.shared.post("Stats exported", tone: .success)
            ShareSheet.present(urls)
        } catch {
            AppLogger.shared.log("Stats export failed: \(error.localizedDescription)", category: .other, level: .error)
            VoltaNotificationCenter.shared.post("Stats export failed", tone: .error)
        }
    }

    private var periodSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(StatsPeriod.allCases) { p in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { vm.period = p }
                    } label: {
                        Text(p.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(vm.period == p ? Theme.background : Theme.primaryText)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(vm.period == p ? Theme.accent : Theme.secondaryBackground, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var periodNavigation: some View {
        if vm.period != .allTime {
            HStack {
                Button {
                    withAnimation { vm.offset += 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .frame(width: 36, height: 36)
                        .glassCircle()
                }
                .buttonStyle(.plain)

                Spacer()
                Text(vm.periodLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Spacer()

                Button {
                    withAnimation { if vm.offset > 0 { vm.offset -= 1 } }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(vm.offset > 0 ? Theme.primaryText : Theme.secondaryText)
                        .frame(width: 36, height: 36)
                        .glassCircle()
                }
                .buttonStyle(.plain)
                .disabled(vm.offset == 0)
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Stat card

struct StatCard: View {
    let label: String
    let value: String
    var sub: String? = nil
    var wide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Theme.secondaryText)
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(Theme.primaryText)
            if let sub { Text(sub).font(.caption2).foregroundStyle(Theme.secondaryText) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 0.5))
    }
}

// MARK: - Section helpers

func statsGrid2(pad: CGFloat = 20, @ViewBuilder content: () -> some View) -> some View {
    let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    return LazyVGrid(columns: cols, spacing: 12) { content() }.padding(.horizontal, pad)
}

func formatHoursMinutes(_ seconds: Int) -> (String, String) {
    let h = seconds / 3600; let m = (seconds % 3600) / 60
    return (h > 0 ? "\(h) hr" : "\(m) min", h > 0 ? "\(m) min" : "")
}

func formatDuration(_ seconds: Int) -> String {
    let h = seconds / 3600; let m = (seconds % 3600) / 60; let s = seconds % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
    return String(format: "%d:%02d", m, s)
}

// MARK: - Top entry row

struct TopEntryRow: View {
    let rank: Int
    let entry: TopEntry
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 20, alignment: .center)

            ArtworkView(coverArtID: entry.coverArt, size: 80, cornerRadius: 6)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.footnote.weight(.medium)).foregroundStyle(Theme.primaryText).lineLimit(1)
                if !entry.subtitle.isEmpty {
                    Text(entry.subtitle).font(.caption2).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(entry.plays)").font(.footnote.bold().monospacedDigit()).foregroundStyle(Theme.primaryText)
                Text(formatDuration(entry.totalDuration)).font(.caption2.monospacedDigit()).foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }
}

// MARK: - Chart wrapper

struct ChartCard<C: View>: View {
    let title: String
    @ViewBuilder var chart: () -> C

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondaryText).padding(.horizontal, 20)
            chart().frame(height: 160).padding(.horizontal, 20)
        }
    }
}

// MARK: - All Time Stats

struct AllTimeStatsSection: View {
    var vm: StatsViewModel
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // stat grid
            statsGrid2 {
                let (listenVal, listenSub) = formatHoursMinutes(vm.totalSeconds)
                StatCard(label: "Total Plays", value: "\(vm.totalPlays)")
                StatCard(label: "Listening Time", value: listenVal, sub: listenSub.isEmpty ? nil : listenSub)
                StatCard(label: "Unique Songs", value: "\(vm.uniqueSongs)")
                StatCard(label: "Unique Albums", value: "\(vm.uniqueAlbums)")
                StatCard(label: "Unique Artists", value: "\(vm.uniqueArtists)")
                StatCard(label: "Avg Plays/Day", value: String(format: "%.1f", vm.avgPlaysPerDay), sub: "\(vm.periodDays) days")
                StatCard(label: "Top Genre", value: vm.topGenre)
                StatCard(label: "Current Streak", value: "\(vm.streak)d", sub: "Best: \(vm.longestStreak)d")
            }

            // charts
            if !vm.hourlyData.isEmpty {
                ChartCard(title: "Time of Day") {
                    Chart(vm.hourlyData) { b in
                        BarMark(x: .value("Hour", b.id), y: .value("Plays", b.count))
                            .foregroundStyle(Theme.accent.gradient)
                    }
                    .chartXAxis {
                        AxisMarks(values: [0, 6, 12, 18, 23]) { v in
                            AxisValueLabel { if let i = v.as(Int.self) { Text("\(i)h").font(.caption2) } }
                        }
                    }
                }
            }

            if !vm.dayOfWeekData.isEmpty {
                ChartCard(title: "Day of Week") {
                    Chart(vm.dayOfWeekData) { b in
                        BarMark(x: .value("Day", b.label), y: .value("Plays", b.count))
                            .foregroundStyle(Theme.accent.gradient)
                    }
                }
            }

            if !vm.genreData.isEmpty {
                ChartCard(title: "Genre Breakdown") {
                    Chart(vm.genreData) { b in
                        SectorMark(angle: .value("Count", b.count), angularInset: 2)
                            .foregroundStyle(by: .value("Genre", b.genre))
                            .cornerRadius(4)
                    }
                    .chartLegend(position: .bottom, alignment: .leading)
                }
            }

            topSection(title: "Top Songs", entries: vm.topSongs, limit: 10)
            topSection(title: "Top Artists", entries: vm.topArtists, limit: 10)
            topSection(title: "Top Albums", entries: vm.topAlbums, limit: 10)
        }
    }

    func topSection(title: String, entries: [TopEntry], limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).foregroundStyle(Theme.primaryText).padding(.horizontal, 20)
            ForEach(Array(entries.prefix(limit).enumerated()), id: \.element.id) { i, e in
                TopEntryRow(rank: i + 1, entry: e)
                Divider().background(Theme.secondaryText.opacity(0.1)).padding(.leading, 72)
            }
        }
    }
}

// MARK: - Daily Stats

struct DailyStatsSection: View {
    var vm: StatsViewModel

    var body: some View {
        VStack(spacing: 24) {
            statsGrid2 {
                StatCard(label: "Total Plays", value: "\(vm.totalPlays)")
                let (v, s) = formatHoursMinutes(vm.totalSeconds)
                StatCard(label: "Listen Time", value: v, sub: s.isEmpty ? nil : s)
                StatCard(label: "Unique Songs", value: "\(vm.uniqueSongs)")
                StatCard(label: "Unique Artists", value: "\(vm.uniqueArtists)")
                StatCard(label: "Unique Albums", value: "\(vm.uniqueAlbums)")
                StatCard(label: "Sessions", value: "\(vm.sessions)")
                StatCard(label: "Avg Track Length", value: formatDuration(Int(vm.avgTrackLength)))
                StatCard(label: "Longest Session", value: formatDuration(vm.longestSession))
            }

            if !vm.hourlyData.isEmpty {
                ChartCard(title: "Plays by Hour") {
                    Chart(vm.hourlyData) { b in
                        BarMark(x: .value("Hour", b.id), y: .value("Plays", b.count))
                            .foregroundStyle(Theme.accent.gradient)
                    }
                }
            }

            if !vm.genreData.isEmpty {
                ChartCard(title: "Genre Breakdown") {
                    Chart(vm.genreData) { b in
                        SectorMark(angle: .value("Count", b.count), angularInset: 2)
                            .foregroundStyle(by: .value("Genre", b.genre))
                            .cornerRadius(4)
                    }
                    .chartLegend(position: .bottom, alignment: .leading)
                }
            }

            topSection(title: "Top Songs", entries: vm.topSongs, limit: 10)
            topSection(title: "Top Artists", entries: vm.topArtists, limit: 10)
            topSection(title: "Top Albums", entries: vm.topAlbums, limit: 10)
        }
    }

    func topSection(title: String, entries: [TopEntry], limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).foregroundStyle(Theme.primaryText).padding(.horizontal, 20)
            ForEach(Array(entries.prefix(limit).enumerated()), id: \.element.id) { i, e in
                TopEntryRow(rank: i + 1, entry: e)
                Divider().background(Theme.secondaryText.opacity(0.1)).padding(.leading, 72)
            }
        }
    }
}

// MARK: - Weekly Stats

struct WeeklyStatsSection: View {
    var vm: StatsViewModel

    var body: some View {
        VStack(spacing: 24) {
            statsGrid2 {
                StatCard(label: "Tracks Played", value: "\(vm.totalPlays)")
                let (v, s) = formatHoursMinutes(vm.totalSeconds)
                StatCard(label: "Listening Time", value: v, sub: s.isEmpty ? nil : s)
                StatCard(label: "Unique Songs", value: "\(vm.uniqueSongs)")
                StatCard(label: "Unique Artists", value: "\(vm.uniqueArtists)")
                StatCard(label: "Unique Albums", value: "\(vm.uniqueAlbums)")
                StatCard(label: "Avg Tracks/Day", value: String(format: "%.1f", vm.avgTracksPerDay))
            }

            if !vm.dailyData.isEmpty {
                ChartCard(title: "Daily Listening") {
                    Chart(vm.dailyData) { b in
                        BarMark(x: .value("Day", b.date, unit: .day), y: .value("Plays", b.count))
                            .foregroundStyle(Theme.accent.gradient)
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .day)) { AxisValueLabel(format: .dateTime.weekday(.abbreviated)) } }
                }
            }

            if !vm.genreData.isEmpty {
                ChartCard(title: "Genre Breakdown") {
                    Chart(vm.genreData) { b in
                        SectorMark(angle: .value("Count", b.count), angularInset: 2)
                            .foregroundStyle(by: .value("Genre", b.genre)).cornerRadius(4)
                    }
                    .chartLegend(position: .bottom, alignment: .leading)
                }
            }

            if !vm.dailyData.isEmpty {
                ChartCard(title: "Daily Listen Time (min)") {
                    Chart(vm.dailyData) { b in
                        BarMark(x: .value("Day", b.date, unit: .day), y: .value("Minutes", b.minutes))
                            .foregroundStyle(Theme.accent.opacity(0.7).gradient)
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .day)) { AxisValueLabel(format: .dateTime.weekday(.abbreviated)) } }
                }
            }

            if !vm.hourlyData.isEmpty {
                ChartCard(title: "Hourly Activity") {
                    Chart(vm.hourlyData) { b in
                        LineMark(x: .value("Hour", b.id), y: .value("Plays", b.count))
                            .foregroundStyle(Theme.accent)
                        AreaMark(x: .value("Hour", b.id), y: .value("Plays", b.count))
                            .foregroundStyle(Theme.accent.opacity(0.2).gradient)
                    }
                }
            }

            topSection(title: "Top Songs", entries: vm.topSongs, limit: 10)
            topSection(title: "Top Artists", entries: vm.topArtists, limit: 10)
            topSection(title: "Top Albums", entries: vm.topAlbums, limit: 10)
        }
    }

    func topSection(title: String, entries: [TopEntry], limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).foregroundStyle(Theme.primaryText).padding(.horizontal, 20)
            ForEach(Array(entries.prefix(limit).enumerated()), id: \.element.id) { i, e in
                TopEntryRow(rank: i + 1, entry: e)
                Divider().background(Theme.secondaryText.opacity(0.1)).padding(.leading, 72)
            }
        }
    }
}

// MARK: - Monthly Stats

struct MonthlyStatsSection: View {
    var vm: StatsViewModel

    var body: some View {
        VStack(spacing: 24) {
            statsGrid2 {
                StatCard(label: "Tracks Played", value: "\(vm.totalPlays)")
                let (v, s) = formatHoursMinutes(vm.totalSeconds)
                StatCard(label: "Listening Time", value: v, sub: s.isEmpty ? nil : s)
                StatCard(label: "Unique Albums", value: "\(vm.uniqueAlbums)")
                StatCard(label: "Unique Artists", value: "\(vm.uniqueArtists)")
                StatCard(label: "Avg Tracks/Day", value: String(format: "%.1f", vm.avgTracksPerDay))
                StatCard(label: "Avg Listen/Day", value: String(format: "%.0f min", vm.avgListenPerDay))
                StatCard(label: "Best Streak", value: "\(vm.streak) days")
            }

            if !vm.dailyData.isEmpty {
                ChartCard(title: "Daily Activity") {
                    Chart(vm.dailyData) { b in
                        BarMark(x: .value("Day", b.date, unit: .day), y: .value("Plays", b.count))
                            .foregroundStyle(Theme.accent.gradient)
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { AxisValueLabel(format: .dateTime.day()) } }
                }
            }

            if !vm.genreData.isEmpty {
                ChartCard(title: "Genre Breakdown") {
                    Chart(vm.genreData) { b in
                        SectorMark(angle: .value("Count", b.count), angularInset: 2)
                            .foregroundStyle(by: .value("Genre", b.genre)).cornerRadius(4)
                    }
                    .chartLegend(position: .bottom, alignment: .leading)
                }
            }

            if !vm.dailyData.isEmpty {
                ChartCard(title: "Daily Listen Time (min)") {
                    Chart(vm.dailyData) { b in
                        BarMark(x: .value("Day", b.date, unit: .day), y: .value("Minutes", b.minutes))
                            .foregroundStyle(Theme.accent.opacity(0.7).gradient)
                    }
                }
            }

            topSection(title: "Top Songs", entries: vm.topSongs, limit: 10)
            topSection(title: "Top Artists", entries: vm.topArtists, limit: 10)
            topSection(title: "Top Albums", entries: vm.topAlbums, limit: 10)
        }
    }

    func topSection(title: String, entries: [TopEntry], limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).foregroundStyle(Theme.primaryText).padding(.horizontal, 20)
            ForEach(Array(entries.prefix(limit).enumerated()), id: \.element.id) { i, e in
                TopEntryRow(rank: i + 1, entry: e)
                Divider().background(Theme.secondaryText.opacity(0.1)).padding(.leading, 72)
            }
        }
    }
}

// MARK: - Yearly Stats

struct YearlyStatsSection: View {
    var vm: StatsViewModel

    var body: some View {
        VStack(spacing: 24) {
            statsGrid2 {
                StatCard(label: "Tracks Played", value: "\(vm.totalPlays)")
                let (v, s) = formatHoursMinutes(vm.totalSeconds)
                StatCard(label: "Listening Time", value: v, sub: s.isEmpty ? nil : s)
                StatCard(label: "Unique Albums", value: "\(vm.uniqueAlbums)")
                StatCard(label: "Unique Artists", value: "\(vm.uniqueArtists)")
                StatCard(label: "Unique Songs", value: "\(vm.uniqueSongs)")
                StatCard(label: "Active Days", value: "\(vm.activeDays)", sub: "\(Int(Double(vm.activeDays)/3.65))% of year")
                StatCard(label: "Best Month", value: vm.bestMonth, sub: "\(vm.bestMonthCount) plays")
                StatCard(label: "Avg Tracks/Month", value: String(format: "%.0f", vm.avgTracksPerMonth))
                StatCard(label: "Best Streak", value: "\(vm.longestStreak)d")
            }

            if !vm.monthlyData.isEmpty {
                ChartCard(title: "Monthly Plays") {
                    Chart(vm.monthlyData) { b in
                        BarMark(x: .value("Month", b.label), y: .value("Plays", b.count))
                            .foregroundStyle(Theme.accent.gradient)
                    }
                }

                ChartCard(title: "Monthly Listen Time (min)") {
                    Chart(vm.monthlyData) { b in
                        BarMark(x: .value("Month", b.label), y: .value("Minutes", b.minutes))
                            .foregroundStyle(Theme.accent.opacity(0.7).gradient)
                    }
                }
            }

            if !vm.dayOfWeekData.isEmpty {
                ChartCard(title: "Day of Week Activity") {
                    Chart(vm.dayOfWeekData) { b in
                        BarMark(x: .value("Day", b.label), y: .value("Plays", b.count))
                            .foregroundStyle(Theme.accent.gradient)
                    }
                }
            }

            if !vm.hourlyData.isEmpty {
                ChartCard(title: "Time of Day Activity") {
                    Chart(vm.hourlyData) { b in
                        LineMark(x: .value("Hour", b.id), y: .value("Plays", b.count))
                            .foregroundStyle(Theme.accent)
                        AreaMark(x: .value("Hour", b.id), y: .value("Plays", b.count))
                            .foregroundStyle(Theme.accent.opacity(0.2).gradient)
                    }
                }
            }

            if !vm.genreData.isEmpty {
                ChartCard(title: "Genre Breakdown") {
                    Chart(vm.genreData) { b in
                        SectorMark(angle: .value("Count", b.count), angularInset: 2)
                            .foregroundStyle(by: .value("Genre", b.genre)).cornerRadius(4)
                    }
                    .chartLegend(position: .bottom, alignment: .leading)
                }

                ChartCard(title: "Genre Play Count") {
                    Chart(vm.genreData) { b in
                        BarMark(x: .value("Count", b.count), y: .value("Genre", b.genre))
                            .foregroundStyle(Theme.accent.gradient)
                    }
                }
            }

            topSection(title: "Top Songs", entries: vm.topSongs, limit: 15)
            topSection(title: "Top Artists", entries: vm.topArtists, limit: 15)
            topSection(title: "Top Albums", entries: vm.topAlbums, limit: 15)
        }
    }

    func topSection(title: String, entries: [TopEntry], limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).foregroundStyle(Theme.primaryText).padding(.horizontal, 20)
            ForEach(Array(entries.prefix(limit).enumerated()), id: \.element.id) { i, e in
                TopEntryRow(rank: i + 1, entry: e)
                Divider().background(Theme.secondaryText.opacity(0.1)).padding(.leading, 72)
            }
        }
    }
}
