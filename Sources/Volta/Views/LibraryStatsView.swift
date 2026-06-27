import SwiftUI
import Charts

// MARK: - Library stats tab content

struct LibraryStatsContentView: View {
    @Bindable var vm: LibraryStatsViewModel
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if vm.phase == .failed, vm.stats == nil {
                failedState
            } else if let stats = vm.stats {
                content(stats)
            } else {
                loadingState
            }
        }
        .onAppear { vm.loadIfNeeded(appState: appState) }
    }

    // MARK: States

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView(value: max(0.02, vm.progress))
                .progressViewStyle(.linear)
                .tint(Theme.accent)
                .frame(width: 180)
            Text(vm.progress > 0.01 ? "Scanning library… \(Int(vm.progress * 100))%" : "Reading your library…")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var failedState: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34))
                .foregroundStyle(Theme.secondaryText)
            Text("Could not read library statistics")
                .font(.headline).foregroundStyle(Theme.primaryText)
            if let msg = vm.errorMessage {
                Text(msg).font(.caption).foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            }
            Button("Try Again") { vm.refresh(appState: appState) }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ s: LibraryStatsData) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            sourceBanner(s)
            overviewSection(s)
            audioQualitySection(s)
            chartsSection(s)
            standoutsSection(s)
            bottomSection(s)
            Color.clear.frame(height: 80)
        }
    }

    private func sourceBanner(_ s: LibraryStatsData) -> some View {
        HStack(spacing: 12) {
            Image(systemName: vm.isOfflineData ? "arrow.down.circle.fill" : "music.note.house.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 42, height: 42)
                .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(s.source).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.primaryText).lineLimit(1)
                Text("\(s.totalSongs.formatted()) tracks · updated \(s.scannedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { vm.refresh(appState: appState) } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 34, height: 34)
                    .glassCircle()
            }
            .buttonStyle(.plain)
            .disabled(vm.phase == .loading)
        }
        .padding(14)
        .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 0.5))
        .padding(.horizontal, 20)
    }

    // MARK: Overview

    private func overviewSection(_ s: LibraryStatsData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LibSectionHeader(icon: "chart.bar.fill", title: "Collection Overview")
            statsGrid2 {
                IconStatCard(icon: "music.note", label: "Tracks", value: s.totalSongs.formatted(),
                             sub: "\(formatLibDuration(s.averageTrackSeconds)) avg length")
                IconStatCard(icon: "square.stack", label: "Albums", value: s.totalAlbums.formatted(),
                             sub: String(format: "%.1f tracks each", s.averageAlbumTracks))
                IconStatCard(icon: "music.mic", label: "Artists", value: s.totalArtists.formatted(),
                             sub: s.totalArtists > 0 ? "\(s.totalSongs / max(1, s.totalArtists)) tracks each" : nil)
                IconStatCard(icon: "clock", label: "Total Playtime", value: formatLibDuration(s.totalSeconds),
                             sub: "\(s.hoursTotal.formatted()) hours")
                IconStatCard(icon: "internaldrive", label: "Library Size", value: formatLibBytes(s.totalSize),
                             sub: "\(formatLibBytes(s.sizePerTrack)) per track")
                IconStatCard(icon: "calendar", label: "Release Span",
                             value: (s.firstReleaseYear != nil && s.lastReleaseYear != nil) ? "\(s.firstReleaseYear!)–\(s.lastReleaseYear!)" : "—",
                             sub: s.decadeSpan > 0 ? "\(s.decadeSpan) decades" : nil)
                IconStatCard(icon: "waveform", label: "Avg Bitrate",
                             value: s.averageBitrate > 0 ? "\(s.averageBitrate)" : "—", sub: "kbps")
                IconStatCard(icon: "dial.medium", label: "Common Profile", value: s.commonResolution, sub: "most frequent")
            }
        }
    }

    // MARK: Audio quality

    private func audioQualitySection(_ s: LibraryStatsData) -> some View {
        let losslessPct = s.totalSongs > 0 ? Double(s.losslessTracks) / Double(s.totalSongs) * 100 : 0
        let hiResPct = s.totalSongs > 0 ? Double(s.hiResTracks) / Double(s.totalSongs) * 100 : 0
        return VStack(alignment: .leading, spacing: 12) {
            LibSectionHeader(icon: "waveform.badge.magnifyingglass", title: "Audio Quality")
            statsGrid2 {
                QualityCard(value: String(format: "%.0f%%", losslessPct), label: "Lossless",
                            sub: "\(s.losslessTracks.formatted()) tracks")
                QualityCard(value: String(format: "%.0f%%", hiResPct), label: "Hi-Res Audio",
                            sub: "24-bit / >48 kHz")
                QualityCard(value: s.averageBitrate > 0 ? "\(s.averageBitrate)" : "—", label: "Avg Bitrate",
                            sub: "kbps")
                QualityCard(value: s.channels.first?.label ?? "—", label: "Channels",
                            sub: s.channels.first.map { "\(Int($0.percentage))% of library" } ?? " ")
            }
        }
    }

    // MARK: Charts

    @ViewBuilder
    private func chartsSection(_ s: LibraryStatsData) -> some View {
        if !s.decades.isEmpty {
            LibBarCard(title: "Releases by Decade", data: s.decades, color: Theme.accent)
        }
        if !s.fileFormats.isEmpty {
            LibDonutCard(title: "File Formats", data: s.fileFormats)
        }
        if !s.bitDepths.isEmpty {
            LibBarCard(title: "Bit Depth", data: s.bitDepths, color: Color(red: 0.39, green: 0.90, blue: 0.74))
        }
        if !s.sampleRates.isEmpty {
            LibBarCard(title: "Sample Rate", data: s.sampleRates, color: Color(red: 0.45, green: 0.75, blue: 0.99))
        }
        if !s.durationBuckets.isEmpty {
            LibBarCard(title: "Track Length Distribution", data: s.durationBuckets, color: Color(red: 0.97, green: 0.51, blue: 0.68))
        }
        if !s.genreTags.isEmpty {
            LibHBarCard(title: "Top Genres", data: s.genreTags, color: Color(red: 0.98, green: 0.78, blue: 0.18))
        }
        if !s.topArtists.isEmpty {
            LibArtistBarCard(title: "Largest Artist Catalogs", data: s.topArtists)
        }
    }

    // MARK: Standouts

    @ViewBuilder
    private func standoutsSection(_ s: LibraryStatsData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LibSectionHeader(icon: "star.fill", title: "Collection Standouts")
            if !s.largestAlbums.isEmpty {
                LibRankCard(title: "Biggest Albums", rows: s.largestAlbums.map {
                    LibRankRowData(cover: $0.coverArt, name: $0.name, sub: "\($0.artist) · \($0.tracks) tracks", value: formatLibBytes($0.size))
                })
            }
            if !s.longestTracks.isEmpty {
                LibRankCard(title: "Longest Tracks", rows: s.longestTracks.map {
                    LibRankRowData(cover: $0.coverArt, name: $0.name, sub: "\($0.artist) · \($0.album)", value: formatDuration($0.duration))
                })
            }
            if !s.topAlbums.isEmpty {
                LibRankCard(title: "Most Tracks per Album", rows: s.topAlbums.map {
                    LibRankRowData(cover: $0.coverArt, name: $0.name, sub: "\($0.artist) · \(formatLibDuration($0.duration))", value: "\($0.tracks)")
                })
            }
        }
    }

    // MARK: Coverage + recently added

    @ViewBuilder
    private func bottomSection(_ s: LibraryStatsData) -> some View {
        CoverageCard(coverage: s.metadataCoverage, total: s.totalSongs)
        if !s.recentlyAdded.isEmpty {
            LibRankCard(title: "Recently Added", numbered: false, rows: s.recentlyAdded.map {
                LibRankRowData(cover: $0.coverArt, name: $0.name, sub: $0.artist,
                               value: $0.addedAt?.formatted(date: .abbreviated, time: .omitted) ?? "")
            })
        }
    }
}

// MARK: - Reusable pieces

struct LibSectionHeader: View {
    let icon: String
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent)
            Text(title).font(.headline).foregroundStyle(Theme.primaryText)
        }
        .padding(.horizontal, 20)
    }
}

struct IconStatCard: View {
    let icon: String
    let label: String
    let value: String
    var sub: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
                Spacer()
            }
            Text(value).font(.title3.bold()).foregroundStyle(Theme.primaryText).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(Theme.secondaryText)
            if let sub { Text(sub).font(.caption2).foregroundStyle(Theme.secondaryText.opacity(0.8)).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 0.5))
    }
}

struct QualityCard: View {
    let value: String
    let label: String
    let sub: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accent).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption.weight(.medium)).foregroundStyle(Theme.primaryText)
            Text(sub).font(.caption2).foregroundStyle(Theme.secondaryText).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 0.5))
    }
}

private struct LibCardContainer<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.primaryText)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 0.5))
        .padding(.horizontal, 20)
    }
}

struct LibBarCard: View {
    let title: String
    let data: [LibCountMetric]
    let color: Color
    var body: some View {
        LibCardContainer(title: title) {
            Chart(data) { m in
                BarMark(x: .value("Label", m.label), y: .value("Count", m.count))
                    .foregroundStyle(color.gradient)
                    .cornerRadius(4)
            }
            .chartYAxis { AxisMarks { AxisValueLabel().font(.caption2) } }
            .chartXAxis { AxisMarks { AxisValueLabel().font(.caption2) } }
            .frame(height: 170)
        }
    }
}

struct LibHBarCard: View {
    let title: String
    let data: [LibCountMetric]
    let color: Color
    var body: some View {
        LibCardContainer(title: title) {
            Chart(data) { m in
                BarMark(x: .value("Count", m.count), y: .value("Label", m.label))
                    .foregroundStyle(color.gradient)
                    .cornerRadius(4)
            }
            .chartXAxis { AxisMarks { AxisValueLabel().font(.caption2) } }
            .chartYAxis { AxisMarks { AxisValueLabel().font(.caption2) } }
            .frame(height: CGFloat(max(120, data.count * 28)))
        }
    }
}

struct LibArtistBarCard: View {
    let title: String
    let data: [LibArtistRank]
    var body: some View {
        LibCardContainer(title: title) {
            Chart(data) { a in
                BarMark(x: .value("Tracks", a.tracks), y: .value("Artist", a.name))
                    .foregroundStyle(Theme.accent.gradient)
                    .cornerRadius(4)
            }
            .chartXAxis { AxisMarks { AxisValueLabel().font(.caption2) } }
            .chartYAxis { AxisMarks { AxisValueLabel().font(.caption2) } }
            .frame(height: CGFloat(max(140, data.count * 28)))
        }
    }
}

struct LibDonutCard: View {
    let title: String
    let data: [LibCountMetric]
    var body: some View {
        LibCardContainer(title: title) {
            Chart(data) { m in
                SectorMark(angle: .value("Count", m.count), innerRadius: .ratio(0.55), angularInset: 2)
                    .foregroundStyle(by: .value("Format", m.label))
                    .cornerRadius(4)
            }
            .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
            .frame(height: 200)
        }
    }
}

struct LibRankRowData: Identifiable {
    let id = UUID()
    let cover: String?
    let name: String
    let sub: String
    let value: String
}

struct LibRankCard: View {
    let title: String
    var numbered: Bool = true
    let rows: [LibRankRowData]

    var body: some View {
        LibCardContainer(title: title) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    HStack(spacing: 12) {
                        if numbered {
                            Text("\(i + 1)").font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.secondaryText).frame(width: 18, alignment: .center)
                        }
                        ArtworkView(coverArtID: row.cover, size: 80, cornerRadius: 6)
                            .frame(width: 38, height: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name).font(.footnote.weight(.medium)).foregroundStyle(Theme.primaryText).lineLimit(1)
                            if !row.sub.isEmpty {
                                Text(row.sub).font(.caption2).foregroundStyle(Theme.secondaryText).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 6)
                        Text(row.value).font(.footnote.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.vertical, 7)
                    if i < rows.count - 1 {
                        Divider().background(Theme.secondaryText.opacity(0.1))
                            .padding(.leading, numbered ? 68 : 50)
                    }
                }
            }
        }
    }
}

struct CoverageCard: View {
    let coverage: LibMetadataCoverage
    let total: Int

    private var items: [(String, Int)] {
        [("Artwork", coverage.artwork), ("Release Year", coverage.releaseYear),
         ("Genres", coverage.genres), ("BPM", coverage.bpm)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LibSectionHeader(icon: "checklist", title: "Metadata Coverage")
            VStack(spacing: 14) {
                ForEach(items, id: \.0) { item in
                    let pct = total > 0 ? Double(item.1) / Double(total) : 0
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.0).font(.footnote.weight(.medium)).foregroundStyle(Theme.primaryText)
                            Spacer()
                            Text("\(Int((pct * 100).rounded()))%").font(.footnote.monospacedDigit())
                                .foregroundStyle(Theme.secondaryText)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.primaryText.opacity(0.08)).frame(height: 6)
                                Capsule().fill(Theme.accent.gradient)
                                    .frame(width: max(0, geo.size.width * pct), height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
            .padding(16)
            .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 0.5))
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Formatting

func formatLibBytes(_ bytes: Int) -> String {
    guard bytes > 0 else { return "—" }
    let units = ["B", "KB", "MB", "GB", "TB"]
    var size = Double(bytes); var unit = 0
    while size >= 1024 && unit < units.count - 1 { size /= 1024; unit += 1 }
    return size >= 100 ? "\(Int(size)) \(units[unit])" : String(format: "%.1f %@", size, units[unit])
}

func formatLibDuration(_ seconds: Int) -> String {
    let d = seconds / 86_400; let h = (seconds % 86_400) / 3600; let m = (seconds % 3600) / 60
    if d > 0 { return "\(d)d \(h)h" }
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}
