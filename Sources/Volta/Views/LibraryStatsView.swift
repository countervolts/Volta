import SwiftUI
import Charts

// MARK: - Library stats tab content

private enum LibraryStatsScope: String, CaseIterable, Identifiable {
    case personal = "Personal"
    case global = "Global"

    var id: String { rawValue }
}

struct LibraryStatsContentView: View {
    @ObservedObject var vm: LibraryStatsViewModel
    @EnvironmentObject private var appState: AppState
    @State private var scope: LibraryStatsScope = .personal

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            scopeSelector

            Group {
                switch scope {
                case .personal:
                    personalBody
                case .global:
                    globalBody
                }
            }
        }
        .onAppear { vm.loadIfNeeded(appState: appState) }
        .onChangeCompat(of: scope) { _, newScope in
            if newScope == .global {
                vm.loadGlobalIfAllowed(appState: appState)
            }
        }
    }

    // MARK: States

    private var scopeSelector: some View {
        HStack(spacing: 8) {
            ForEach(LibraryStatsScope.allCases) { item in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        scope = item
                    }
                } label: {
                    Text(item.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(scope == item ? Theme.background : Theme.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(scope == item ? Theme.accent : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.secondaryBackground, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.06), lineWidth: 0.5))
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var personalBody: some View {
        if vm.phase == .failed, vm.stats == nil {
            failedState
        } else if let stats = vm.stats {
            content(stats)
        } else {
            loadingState
        }
    }

    @ViewBuilder
    private var globalBody: some View {
        if !vm.isGlobalSharingEnabled {
            globalOptInPrompt
        } else if !vm.isSharingCurrentLibrary(appState: appState) {
            globalDifferentLibraryPrompt
        } else if vm.globalPhase == .failed, vm.globalStats == nil {
            globalFailedState
        } else if let stats = vm.globalStats {
            globalContent(stats)
        } else {
            globalLoadingState
        }
    }

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

    private var globalLoadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Theme.accent)
            Text(vm.stats == nil ? "Preparing anonymous library totals…" : "Loading global library stats…")
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

    private var globalFailedState: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 34))
                .foregroundStyle(Theme.secondaryText)
            Text("Could not load global library stats")
                .font(.headline).foregroundStyle(Theme.primaryText)
            if let msg = vm.globalErrorMessage {
                Text(msg).font(.caption).foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            }
            Button("Try Again") { vm.refreshGlobal(appState: appState) }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }

    private var globalOptInPrompt: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Share Anonymous Library Totals")
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                    Text("Global stats are opt-in only.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                privacyRow(icon: "number", text: "Volta uploads only numbers: track count, album count, total playtime, total size, and app version.")
                privacyRow(icon: "music.note.list", text: "No song titles, artist names, album names, server URLs, account details, or files are uploaded.")
                privacyRow(icon: "link", text: "Sharing is linked to this library, so switching to another server will not upload another global entry.")
                privacyRow(icon: "hand.raised.fill", text: "No library data leaves this device unless you opt in.")
                privacyRow(icon: "dollarsign.slash", text: "This data is not collected for selling and is only used to show community totals.")
            }

            HStack(spacing: 10) {
                Button {
                    vm.enableGlobalSharing(appState: appState)
                } label: {
                    Text("Opt In")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)

                Button {
                    scope = .personal
                } label: {
                    Text("Not Now")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.secondaryText)
            }
        }
        .padding(18)
        .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 0.5))
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private var globalDifferentLibraryPrompt: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Global Sharing Is Linked")
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                    Text(vm.sharedLibraryName.map { "Currently sharing \($0)." } ?? "Currently sharing another library.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            Text("Volta only allows one opted-in library per app install. This keeps someone from uploading separate Navidrome, Plex, Emby, or downloaded libraries as multiple global entries. No data from the current library will be uploaded.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if vm.globalPhase == .failed, let message = vm.globalErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(role: .destructive) {
                vm.disableGlobalSharing()
            } label: {
                if vm.globalPhase == .loading {
                    ProgressView()
                        .tint(.red)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Stop Sharing and Delete My Stats")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(vm.globalPhase == .loading)
        }
        .padding(18)
        .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 0.5))
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private func privacyRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 18, height: 18)
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
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

    @ViewBuilder
    private func globalContent(_ s: GlobalLibraryStatsData) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            globalSourceBanner(s)
            globalOverviewSection(s)
            globalRecordsSection(s)
            globalPrivacyControls
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

    private func globalSourceBanner(_ s: GlobalLibraryStatsData) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 42, height: 42)
                .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Opted-in Volta Libraries").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.primaryText).lineLimit(1)
                Text("\(s.totals.libraryCount.formatted()) libraries · updated \(s.generatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { vm.refreshGlobal(appState: appState) } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 34, height: 34)
                    .glassCircle()
            }
            .buttonStyle(.plain)
            .disabled(vm.globalPhase == .loading)
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

    private func globalOverviewSection(_ s: GlobalLibraryStatsData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LibSectionHeader(icon: "chart.bar.fill", title: "Global Overview")
            statsGrid2 {
                IconStatCard(icon: "music.note.house", label: "Libraries", value: s.totals.libraryCount.formatted(),
                             sub: "anonymous opt-ins")
                IconStatCard(icon: "music.note", label: "Tracks", value: s.totals.songCount.formatted(),
                             sub: "\(roundedNumber(s.averages.songCount)) avg per library")
                IconStatCard(icon: "square.stack", label: "Albums", value: s.totals.albumCount.formatted(),
                             sub: "\(roundedNumber(s.averages.albumCount)) avg per library")
                IconStatCard(icon: "clock", label: "Total Playtime", value: formatLibDuration(s.totals.durationSeconds),
                             sub: "\(s.totals.durationSeconds / 3600) hours combined")
                IconStatCard(icon: "internaldrive", label: "Combined Size", value: formatLibBytes(s.totals.librarySizeBytes),
                             sub: "\(formatLibBytes(Int(s.averages.librarySizeBytes))) avg library")
                IconStatCard(icon: "person.3.sequence", label: "Largest Song Count", value: s.records.highestSongCount.formatted(),
                             sub: "single anonymous library")
            }
        }
    }

    private func globalRecordsSection(_ s: GlobalLibraryStatsData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LibSectionHeader(icon: "trophy.fill", title: "Global Records")
            statsGrid2 {
                IconStatCard(icon: "clock.badge", label: "Highest Listening Time",
                             value: formatLibDuration(s.records.highestListeningTimeSeconds),
                             sub: "one anonymous library")
                IconStatCard(icon: "internaldrive.fill", label: "Biggest Library Size",
                             value: formatLibBytes(s.records.highestLibrarySizeBytes),
                             sub: "one anonymous library")
                IconStatCard(icon: "music.note.list", label: "Biggest Library Tracks",
                             value: s.records.biggestLibrary.songCount.formatted(),
                             sub: "\(s.records.biggestLibrary.albumCount.formatted()) albums")
                IconStatCard(icon: "square.stack.3d.up", label: "Most Albums",
                             value: s.records.highestAlbumCount.formatted(),
                             sub: "one anonymous library")
            }
        }
    }

    private var globalPrivacyControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("Only anonymous numeric totals are shared.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 8)
            }

            if vm.globalPhase == .failed, let message = vm.globalErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(role: .destructive) {
                vm.disableGlobalSharing()
            } label: {
                if vm.globalPhase == .loading {
                    ProgressView()
                        .tint(.red)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Stop Sharing and Delete My Stats")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(vm.globalPhase == .loading)
        }
        .padding(16)
        .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 0.5))
        .padding(.horizontal, 20)
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
            chart
                .frame(height: 200)
        }
    }

    @ViewBuilder
    private var chart: some View {
        if #available(iOS 17.0, *) {
            Chart(data) { m in
                SectorMark(angle: .value("Count", m.count), innerRadius: .ratio(0.55), angularInset: 2)
                    .foregroundStyle(by: .value("Format", m.label))
                    .cornerRadius(4)
            }
            .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
        } else {
            Chart(data) { m in
                BarMark(x: .value("Count", m.count), y: .value("Format", m.label))
                    .foregroundStyle(Theme.accent.gradient)
                    .cornerRadius(4)
            }
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
    @State private var showMoreMetadata = false

    private let visibleCount = 6

    private var visibleItems: [LibCountMetric] { Array(coverage.items.prefix(visibleCount)) }
    private var hiddenItems: [LibCountMetric] { Array(coverage.items.dropFirst(visibleCount)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LibSectionHeader(icon: "checklist", title: "Metadata Coverage")
            VStack(spacing: 14) {
                if coverage.items.isEmpty {
                    Text("No metadata fields found.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(visibleItems) { item in
                        metadataCoverageRow(item)
                    }
                    if !hiddenItems.isEmpty {
                        DisclosureGroup(isExpanded: $showMoreMetadata) {
                            VStack(spacing: 14) {
                                ForEach(hiddenItems) { item in
                                    metadataCoverageRow(item)
                                }
                            }
                            .padding(.top, 12)
                        } label: {
                            HStack {
                                Text(showMoreMetadata ? "Show less" : "Show more")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                                Spacer()
                                Text("\(hiddenItems.count) more")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                        .tint(Theme.accent)
                    }
                }
            }
            .padding(16)
            .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 0.5))
            .padding(.horizontal, 20)
        }
    }

    private func metadataCoverageRow(_ item: LibCountMetric) -> some View {
        let pct = max(0, min(1, item.percentage / 100))
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.label).font(.footnote.weight(.medium)).foregroundStyle(Theme.primaryText)
                Spacer()
                Text("\(Int(item.percentage.rounded()))%").font(.footnote.monospacedDigit())
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
            Text("\(item.count.formatted()) of \(total.formatted()) tracks")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText.opacity(0.8))
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

private func roundedNumber(_ value: Double) -> String {
    if value >= 100 {
        return Int(value.rounded()).formatted()
    }
    if value >= 10 {
        return String(format: "%.1f", value)
    }
    return String(format: "%.2f", value)
}
