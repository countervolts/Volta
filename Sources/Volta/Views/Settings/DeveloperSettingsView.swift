import SwiftUI
import UIKit

extension SettingsView {
    func registerSecretDeveloperTap() {
        guard !developerUnlocked else { return }
        versionTapCount += 1
        if versionTapCount >= 7 {
            developerUnlocked = true
            versionTapCount = 0
            VoltaNotificationCenter.shared.post("Developer Tools enabled", tone: .success)
        } else if versionTapCount >= 4 {
            let remaining = 7 - versionTapCount
            VoltaNotificationCenter.shared.post(
                "\(remaining) more tap\(remaining == 1 ? "" : "s") to enable Developer Tools", tone: .info)
        }
    }

    // MARK: - Developer

    @ViewBuilder
    var developerSection: some View {
        let s = "Developer"
        // Stays fully hidden (even from search) until unlocked via 7 taps on
        // the Version/Build row in About.
        if developerUnlocked,
           sectionVisible(s, [["developer tools", "simulation", "simulate", "slow server", "expired session", "no network", "profiling", "ram", "automix", "autoplay"], ["experiments", "raw animated artwork", "disable ram optimizations", "app worker limit", "workers", "threads", "concurrency"], ["enhanced caching", "playback cache", "cache performance", "prefetch", "force cache mode", "seamless", "buffer"], ["hangs", "crashes", "crash reports", "hang reports", "reliability", "send report", ".ips"], ["performance overlay", "overlay", "fps", "ram", "frame pacing", "metrics"], ["notifications", "toast", "warning", "preview"], ["verbose logging", "logging"], ["log device specs", "device", "specs", "ios", "liquid glass", "diagnostics"], ["dump app files", "export app data", "zip", "all files"], ["export all logs"], ["clear all logs"], ["force refresh home"], ["logged play events"], ["queue length"], ["developer"]]) {
        Section {
            NavigationLink(value: SettingsRoute.developerTools) {
                Label("Developer Tools", systemImage: "hammer")
            }
            .foregroundStyle(Theme.primaryText)

            NavigationLink(value: SettingsRoute.developerExperiments) {
                Label("Experiments", systemImage: "testtube.2")
            }
            .foregroundStyle(Theme.primaryText)

            NavigationLink(value: SettingsRoute.playbackCacheDiagnostics) {
                Label("Playback Cache", systemImage: "bolt.horizontal.circle")
            }
            .foregroundStyle(Theme.primaryText)

            NavigationLink(value: SettingsRoute.reliabilityReports) {
                Label("Hangs & Crashes", systemImage: "exclamationmark.triangle")
            }
            .foregroundStyle(Theme.primaryText)

            NavigationLink(value: SettingsRoute.performanceOverlay) {
                Label("Performance Overlay", systemImage: "chart.xyaxis.line")
            }
            .foregroundStyle(Theme.primaryText)

            NavigationLink(value: SettingsRoute.notifications) {
                Label("Notifications", systemImage: "bell.badge")
            }
            .foregroundStyle(Theme.primaryText)

            Toggle(isOn: $developerLogging) {
                Label("Verbose Logging", systemImage: "terminal")
            }
            .tint(Theme.accent)

            Button {
                AppDiagnostics.logLaunch(context: "manual")
            } label: {
                Label("Log Device Specs", systemImage: "iphone")
            }
            .foregroundStyle(Theme.primaryText)

            Button {
                exportLogs()
            } label: {
                Label("Export All Logs", systemImage: "square.and.arrow.up")
            }
            .foregroundStyle(Theme.primaryText)

            Button {
                dumpAppFiles()
            } label: {
                HStack {
                    Label("Dump App Files", systemImage: "archivebox")
                    Spacer()
                    if isDumpingAppFiles {
                        ProgressView().controlSize(.small).tint(Theme.accent)
                    }
                }
            }
            .foregroundStyle(Theme.primaryText)
            .disabled(isDumpingAppFiles)

            if let appDumpStatus {
                Text(appDumpStatus)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            Button(role: .destructive) {
                showClearLogsAlert = true
            } label: {
                Label("Clear All Logs", systemImage: "trash")
            }

            Button {
                Task {
                    await appState.homeViewModel.load(appState: appState, force: true)
                    VoltaNotificationCenter.shared.post(L(.notif_home_refreshed), tone: .success)
                }
            } label: {
                Label("Force Refresh Home", systemImage: "arrow.clockwise")
            }
            .foregroundStyle(Theme.primaryText)

            LabeledContent("Logged Play Events") {
                Text(loggedPlayEventCount.map(String.init) ?? "...")
                    .foregroundStyle(Theme.secondaryText)
            }
            .foregroundStyle(Theme.primaryText)

            LabeledContent("Queue Length") {
                Text("\(appState.audioPlayer.queue.count) tracks")
                    .foregroundStyle(Theme.secondaryText)
            }
            .foregroundStyle(Theme.primaryText)

            Button(role: .destructive) {
                developerUnlocked = false
                versionTapCount = 0
                VoltaNotificationCenter.shared.post("Developer Tools hidden", tone: .info)
            } label: {
                Label("Hide Developer Tools", systemImage: "eye.slash")
            }
        } header: {
            Text(sectionTitle(s))
        } footer: {
            Text("Verbose logging keeps info-level network and playback entries. Warnings and errors are always kept.")
        }
        .listRowBackground(Theme.secondaryBackground)
        }
    }

    // MARK: - Developer helpers

    func exportLogs() {
        Task {
            let fm = FileManager.default
            let stamp = Int(Date().timeIntervalSince1970)
            let tmp = fm.temporaryDirectory
                .appendingPathComponent("volta-logs-\(stamp)", isDirectory: true)
            let zip = fm.temporaryDirectory
                .appendingPathComponent("volta-logs-\(stamp).zip")
            try? fm.removeItem(at: tmp)
            try? fm.removeItem(at: zip)
            try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)

            let entries = AppLogger.shared.allEntries()
            let categoryCounts = AppLogger.shared.countsByCategory()
            let levelCounts = AppLogger.shared.countsByLevel()
            let summary = [
                "Volta Log Export",
                "Generated: \(Date().formatted(date: .abbreviated, time: .standard))",
                "Total entries: \(entries.count)",
                "Estimated size: \(SettingsView.formatBytes(AppLogger.shared.estimatedSizeBytes()))",
                "",
                "By level:",
                "Info: \(levelCounts[.info, default: 0])",
                "Warnings: \(levelCounts[.warning, default: 0])",
                "Errors: \(levelCounts[.error, default: 0])",
                "",
                "By category:"
            ]
            + LogCategory.allCases.map { "\($0.rawValue): \(categoryCounts[$0, default: 0])" }

            var files: [ZipSourceFile] = []
            let summaryFile = tmp.appendingPathComponent("Summary.txt")
            if (try? summary.joined(separator: "\n").write(to: summaryFile, atomically: true, encoding: .utf8)) != nil {
                files.append(ZipSourceFile(url: summaryFile, path: "Logs/Summary.txt"))
            }
            let allFile = tmp.appendingPathComponent("All.txt")
            if (try? AppLogger.shared.allFormatted().write(to: allFile, atomically: true, encoding: .utf8)) != nil {
                files.append(ZipSourceFile(url: allFile, path: "Logs/All.txt"))
            }
            files += LogCategory.allCases.compactMap { cat in
                let text = AppLogger.shared.allFormatted(category: cat)
                let file = tmp.appendingPathComponent("\(cat.rawValue).txt")
                guard (try? text.write(to: file, atomically: true, encoding: .utf8)) != nil else {
                    return nil
                }
                return ZipSourceFile(url: file, path: "Logs/\(cat.rawValue).txt")
            }

            do {
                try ZipArchiveWriter.write(files: files, to: zip)
                VoltaNotificationCenter.shared.post(L(.notif_logs_zip_ready), tone: .success)
                ShareSheet.present([zip])
            } catch {
                VoltaNotificationCenter.shared.post(L(.notif_logs_folder_fallback), tone: .warning)
                ShareSheet.present([tmp])
            }
        }
    }

    func dumpAppFiles() {
        guard !isDumpingAppFiles else { return }
        isDumpingAppFiles = true
        appDumpStatus = "Preparing zip..."
        Task {
            defer { isDumpingAppFiles = false }
            do {
                let url = try await AppDataExporter.makeArchive()
                let size = SettingsView.formatBytes(SettingsView.fileSize(at: url))
                appDumpStatus = "Ready: \(size)"
                AppLogger.shared.log("App file dump exported: \(size)", category: .settings)
                VoltaNotificationCenter.shared.post(L(.notif_app_files_zip_ready), tone: .success)
                ShareSheet.present([url])
            } catch {
                appDumpStatus = "Export failed: \(error.localizedDescription)"
                AppLogger.shared.log("App file dump failed: \(error.localizedDescription)", category: .settings, level: .error)
            }
        }
    }

    nonisolated static func fileSize(at url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    func clearPlayEvents() {
        StatsStore.shared.clearAll()
        loggedPlayEventCount = 0
        AppLogger.shared.log("Logged play events cleared by user", category: .settings, level: .warning)
        VoltaNotificationCenter.shared.post(L(.notif_listening_stats_cleared), tone: .success)
        refreshCacheSize()
    }
}

struct DeveloperExperimentsView: View {
    @AppStorage(LiveArtworkSettings.rawAnimatedArtworkKey) private var rawAnimatedArtwork = false
    @AppStorage(DeveloperExperiments.disableRAMOptimizationsKey) private var disableRAMOptimizations = false
    @AppStorage(DeveloperExperiments.appWorkerLimitKey) private var appWorkerLimit = 0
    @AppStorage(DeveloperExperiments.preciseTimestampsKey) private var preciseTimestamps = false
    @AppStorage(DeveloperExperiments.fakeListeningStatsKey) private var fakeListeningStats = false
    @AppStorage(DeveloperExperiments.instantScrobblingKey) private var instantScrobbling = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                Section {
                    if LiveArtworkSettings.supportsAnimatedArtwork {
                        Toggle(isOn: $rawAnimatedArtwork) {
                            Label("Raw Animated Artwork", systemImage: "livephoto")
                        }
                        .tint(Theme.accent)
                    } else {
                        LabeledContent {
                            Text("Unavailable on iOS 16")
                                .foregroundStyle(Theme.secondaryText)
                        } label: {
                            Label("Raw Animated Artwork", systemImage: "livephoto")
                        }
                    }

                    Toggle(isOn: $disableRAMOptimizations) {
                        Label("Disable RAM Optimizations", systemImage: "memorychip")
                    }
                    .tint(Theme.accent)

                    Picker(selection: $appWorkerLimit) {
                        Text("Off").tag(0)
                        Text("1 Worker").tag(1)
                        Text("2 Workers").tag(2)
                        Text("4 Workers").tag(4)
                    } label: {
                        Label("App Worker Limit", systemImage: "slider.horizontal.3")
                    }
                } footer: {
                    Text("Limits Volta-owned worker jobs only. iOS, SwiftUI, networking, and audio frameworks may still create their own threads. Fully close and reopen Volta after changing it so existing queues and tasks pick up the new limit.")
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    Toggle(isOn: $preciseTimestamps) {
                        Label("Precise Timestamps", systemImage: "stopwatch")
                    }
                    .tint(Theme.accent)
                } footer: {
                    Text("Shows elapsed and remaining time in the player down to the fractions of a second (X:XX.XXXX).")
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    Toggle(isOn: $instantScrobbling) {
                        Label("Instant Scrobbling", systemImage: "bolt.badge.clock")
                    }
                    .tint(Theme.accent)

                    Toggle(isOn: $fakeListeningStats) {
                        Label("Fake Listening Stats", systemImage: "wand.and.stars")
                    }
                    .tint(Theme.accent)
                } footer: {
                    Text("Instant Scrobbling records local stats and sends third-party scrobbles 1 second into each song for debugging. Fake Listening Stats replaces the Listening tab in Stats with generated screenshot data; your real play history is kept separately.")
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    Button(role: .destructive) {
                        DeveloperCrashTest.fatalError()
                    } label: {
                        Label("Swift Fatal Error", systemImage: "xmark.octagon")
                    }

                    Button(role: .destructive) {
                        DeveloperCrashTest.failedPrecondition()
                    } label: {
                        Label("Failed Precondition", systemImage: "exclamationmark.octagon")
                    }

                    Button(role: .destructive) {
                        DeveloperCrashTest.forceUnwrapNil()
                    } label: {
                        Label("Force-Unwrap nil", systemImage: "questionmark.diamond")
                    }

                    Button(role: .destructive) {
                        DeveloperCrashTest.arrayIndexOutOfRange()
                    } label: {
                        Label("Array Index Out of Range", systemImage: "list.number")
                    }

                    Button(role: .destructive) {
                        DeveloperCrashTest.abortSignal()
                    } label: {
                        Label("Abort Process (SIGABRT)", systemImage: "xmark.octagon")
                    }

                    Button(role: .destructive) {
                        DeveloperCrashTest.segmentationFault()
                    } label: {
                        Label("Segmentation Fault (SIGSEGV)", systemImage: "memorychip")
                    }
                } header: {
                    Text("Native Crash Tests")
                } footer: {
                    Text("Each button terminates Volta immediately. The trigger does not save a report itself; reopen Volta afterward so the normal recovery path can create its deferred .ips file. iOS may later add a fuller MetricKit diagnostic with a call stack.")
                }
                .listRowBackground(Theme.secondaryBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle("Experiments")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
        }
        .preferredColorScheme(Theme.colorScheme)
        .onChangeCompat(of: rawAnimatedArtwork) { _, enabled in
            AppLogger.shared.logAlways("Developer experiment: raw animated artwork \(enabled ? "enabled" : "disabled")", category: .settings)
        }
        .onChangeCompat(of: disableRAMOptimizations) { _, enabled in
            AppLogger.shared.logAlways("Developer experiment: RAM optimizations \(enabled ? "disabled" : "enabled")", category: .settings)
        }
        .onChangeCompat(of: appWorkerLimit) { _, limit in
            let label = limit > 0 ? "\(limit)" : "off"
            AppLogger.shared.logAlways("Developer experiment: app worker limit \(label)", category: .settings)
            VoltaNotificationCenter.shared.post(L(.notif_restart_to_apply), tone: .info)
        }
        .onChangeCompat(of: preciseTimestamps) { _, enabled in
            AppLogger.shared.logAlways("Developer experiment: precise timestamps \(enabled ? "enabled" : "disabled")", category: .settings)
        }
        .onChangeCompat(of: instantScrobbling) { _, enabled in
            AppLogger.shared.logAlways("Developer experiment: instant scrobbling \(enabled ? "enabled" : "disabled")", category: .settings)
        }
        .onChangeCompat(of: fakeListeningStats) { _, enabled in
            AppLogger.shared.logAlways("Developer experiment: fake listening stats \(enabled ? "enabled" : "disabled")", category: .settings)
            StatsStore.shared.setFakeStats(enabled, songPool: DownloadService.shared.downloadedSongs())
            VoltaNotificationCenter.shared.post(
                enabled ? "Listening stats are now faked for screenshots" : "Listening stats restored to your real history",
                tone: enabled ? .warning : .success)
        }
    }
}

// MARK: - Logs view

private enum LogLevelFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case info = "Info"
    case warning = "Warning"
    case error = "Error"
    var id: String { rawValue }

    var level: LogEntry.Level? {
        switch self {
        case .all: return nil
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        }
    }
}

private enum LogSortMode: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case oldest = "Oldest"
    case severity = "Severity"
    case category = "Category"
    var id: String { rawValue }
}

private enum LogCopyScope: Equatable {
    case visible
    case all
}

struct LogsView: View {
    @State private var selectedCategory: LogCategory?
    @State private var levelFilter: LogLevelFilter = .all
    @State private var sortMode: LogSortMode = .newest
    @State private var searchText = ""
    @State private var entries: [LogEntry] = []
    @State private var copiedScope: LogCopyScope?
    @State private var showingClearAllConfirmation = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    overviewSection
                    filtersSection
                    categoryBreakdownSection
                    recentIssuesSection
                    entriesSection
                    actionsSection
                }
                .padding(16)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
        }
        .preferredColorScheme(Theme.colorScheme)
        .onAppear { reload() }
        .onChangeCompat(of: selectedCategory) { _, _ in reload() }
        .onChangeCompat(of: levelFilter) { _, _ in reload() }
        .onChangeCompat(of: sortMode) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .logEntryAdded)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .logEntriesChanged)) { _ in reload() }
        .alert("Clear all logs?", isPresented: $showingClearAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                AppLogger.shared.clearAll()
                selectedCategory = nil
                reload()
            }
        } message: {
            Text("This removes every in-memory diagnostic entry.")
        }
    }

    private var overviewSection: some View {
        LogSection(title: "Overview", symbol: "gauge.with.dots.needle.67percent") {
            LazyVGrid(columns: metricColumns, spacing: 10) {
                LogMetricCell(title: "Entries", value: "\(entries.count)", symbol: Symbols.logs, tint: Theme.accent)
                LogMetricCell(title: "Warnings", value: "\(levelCount(.warning))", symbol: Symbols.warning, tint: .yellow)
                LogMetricCell(title: "Errors", value: "\(levelCount(.error))", symbol: "xmark.octagon.fill", tint: Theme.error)
                LogMetricCell(title: "Size", value: SettingsView.formatBytes(AppLogger.shared.estimatedSizeBytes()), symbol: "externaldrive", tint: .teal)
            }
        }
    }

    private var filtersSection: some View {
        LogSection(title: "Filters", symbol: "line.3.horizontal.decrease.circle") {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        LogFilterChip(
                            title: "All",
                            count: entries.count,
                            symbol: "tray.full",
                            tint: Theme.accent,
                            selected: selectedCategory == nil
                        ) {
                            selectedCategory = nil
                        }
                        ForEach(LogCategory.allCases, id: \.self) { category in
                            LogFilterChip(
                                title: category.rawValue,
                                count: categoryEntries(category).count,
                                symbol: category.symbol,
                                tint: category.tint,
                                selected: selectedCategory == category
                            ) {
                                selectedCategory = category
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }

                HStack(spacing: 10) {
                    Picker("Level", selection: $levelFilter) {
                        ForEach(LogLevelFilter.allCases) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    Picker("Sort", selection: $sortMode) {
                        ForEach(LogSortMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                }
                .pickerStyle(.menu)

                HStack(spacing: 8) {
                    Image(systemName: Symbols.search)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                    TextField("Search messages", text: $searchText)
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var categoryBreakdownSection: some View {
        LogSection(title: "Categories", symbol: "square.grid.2x2") {
            VStack(spacing: 8) {
                ForEach(LogCategory.allCases, id: \.self) { category in
                    LogCategoryBreakdownRow(
                        category: category,
                        total: categoryEntries(category).count,
                        warnings: levelCount(.warning, in: category),
                        errors: levelCount(.error, in: category),
                        selected: selectedCategory == category
                    ) {
                        selectedCategory = category
                    }
                }
            }
        }
    }

    private var recentIssuesSection: some View {
        LogSection(title: "Recent Issues", symbol: "exclamationmark.triangle") {
            if recentIssues.isEmpty {
                LogEmptyState(
                    title: "No warnings or errors",
                    message: "Warnings and errors will appear here as soon as the app records them.",
                    symbol: Symbols.check
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(recentIssues.prefix(5)) { entry in
                        LogEntryRow(entry: entry)
                    }
                }
            }
        }
    }

    private var entriesSection: some View {
        LogSection(title: "Entries", symbol: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(visibleEntries.count) visible")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                        Text(scopeDescription)
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Button {
                        copy(.visible)
                    } label: {
                        Label(copiedScope == .visible ? "Copied" : "Copy", systemImage: copiedScope == .visible ? Symbols.check : Symbols.copy)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(copiedScope == .visible ? .green : Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(visibleEntries.isEmpty)
                }

                if visibleEntries.isEmpty {
                    LogEmptyState(
                        title: "No matching entries",
                        message: "Try a different category, level, sort, or search filter.",
                        symbol: Symbols.logs
                    )
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(visibleEntries) { entry in
                            LogEntryRow(entry: entry)
                        }
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        LogSection(title: "Actions", symbol: "wrench.and.screwdriver") {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    LogActionButton(
                        title: copiedScope == .all ? "Copied All" : "Copy All",
                        symbol: copiedScope == .all ? Symbols.check : Symbols.copy,
                        tint: copiedScope == .all ? .green : Theme.accent
                    ) {
                        copy(.all)
                    }
                    .disabled(entries.isEmpty)

                    LogActionButton(
                        title: selectedCategory == nil ? "Clear All" : "Clear \(selectedCategory?.rawValue ?? "")",
                        symbol: Symbols.trash,
                        tint: Theme.error
                    ) {
                        if let selectedCategory {
                            AppLogger.shared.clear(category: selectedCategory)
                            reload()
                        } else {
                            showingClearAllConfirmation = true
                        }
                    }
                    .disabled(entries.isEmpty || (selectedCategory != nil && visibleEntries.isEmpty))
                }
            }
        }
    }

    private var metricColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }

    private var visibleEntries: [LogEntry] {
        var next = entries
        if let selectedCategory {
            next = next.filter { $0.category == selectedCategory }
        }
        if let level = levelFilter.level {
            next = next.filter { $0.level == level }
        }
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !term.isEmpty {
            next = next.filter {
                $0.message.localizedCaseInsensitiveContains(term)
                || $0.category.rawValue.localizedCaseInsensitiveContains(term)
                || $0.level.rawValue.localizedCaseInsensitiveContains(term)
            }
        }
        return sorted(next)
    }

    private var recentIssues: [LogEntry] {
        entries
            .filter { $0.level == .warning || $0.level == .error }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private var scopeDescription: String {
        let category = selectedCategory?.rawValue ?? "All categories"
        let level = levelFilter == .all ? "all levels" : levelFilter.rawValue.lowercased()
        return "\(category), \(level), \(sortMode.rawValue.lowercased()) first"
    }

    private func reload() {
        entries = AppLogger.shared.allEntries()
    }

    private func categoryEntries(_ category: LogCategory) -> [LogEntry] {
        entries.filter { $0.category == category }
    }

    private func levelCount(_ level: LogEntry.Level, in category: LogCategory? = nil) -> Int {
        entries.filter { entry in
            entry.level == level && (category == nil || entry.category == category)
        }.count
    }

    private func sorted(_ source: [LogEntry]) -> [LogEntry] {
        var next = source
        switch sortMode {
        case .newest:
            next.sort { $0.timestamp > $1.timestamp }
        case .oldest:
            next.sort { $0.timestamp < $1.timestamp }
        case .severity:
            next.sort {
                if $0.level.severityRank != $1.level.severityRank {
                    return $0.level.severityRank > $1.level.severityRank
                }
                return $0.timestamp > $1.timestamp
            }
        case .category:
            next.sort {
                if $0.category.rawValue != $1.category.rawValue {
                    return $0.category.rawValue < $1.category.rawValue
                }
                return $0.timestamp > $1.timestamp
            }
        }
        return next
    }

    private func copy(_ scope: LogCopyScope) {
        let source = scope == .all ? sorted(entries) : visibleEntries
        UIPasteboard.general.string = source.map(\.formatted).joined(separator: "\n")
        copiedScope = scope
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if copiedScope == scope {
                copiedScope = nil
            }
        }
    }
}

private struct LogSection<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            content
        }
    }
}

private struct LogMetricCell: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(minHeight: 58)
        .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct LogFilterChip: View {
    let title: String
    let count: Int
    let symbol: String
    let tint: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text("\(count)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((selected ? Color.black.opacity(0.16) : Theme.primaryText.opacity(0.08)), in: Capsule())
            }
            .foregroundStyle(selected ? .black : tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(selected ? tint : tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct LogCategoryBreakdownRow: View {
    let category: LogCategory
    let total: Int
    let warnings: Int
    let errors: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: category.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(category.tint)
                    .frame(width: 28, height: 28)
                    .background(category.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text("\(total) entr\(total == 1 ? "y" : "ies")")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }

                Spacer()

                HStack(spacing: 5) {
                    if warnings > 0 {
                        LogSmallCount(label: "W", value: warnings, tint: .yellow)
                    }
                    if errors > 0 {
                        LogSmallCount(label: "E", value: errors, tint: Theme.error)
                    }
                }

                Image(systemName: selected ? Symbols.check : Symbols.chevron)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(selected ? category.tint : Theme.secondaryText.opacity(0.7))
            }
            .padding(10)
            .background(
                selected ? category.tint.opacity(0.14) : Theme.secondaryBackground,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct LogSmallCount: View {
    let label: String
    let value: Int
    let tint: Color

    var body: some View {
        Text("\(label) \(value)")
            .font(.caption2.monospacedDigit().weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

private struct LogActionButton: View {
    let title: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct LogEmptyState: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(Theme.secondaryText)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(entry.level.shortLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.black)
                    .frame(width: 18, height: 18)
                    .background(entry.level.tint, in: RoundedRectangle(cornerRadius: 4, style: .continuous))

                Label(entry.category.rawValue, systemImage: entry.category.symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(entry.category.tint)

                Spacer()

                Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }

            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.primaryText.opacity(0.92))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var rowBackground: Color {
        switch entry.level {
        case .info:
            return Theme.secondaryBackground
        case .warning:
            return Color.yellow.opacity(0.10)
        case .error:
            return Theme.error.opacity(0.10)
        }
    }
}

private extension LogCategory {
    var symbol: String {
        switch self {
        case .networking: return Symbols.network
        case .playback: return Symbols.playbackLog
        case .library: return Symbols.library
        case .lyrics: return Symbols.lyrics
        case .downloads: return Symbols.download
        case .artwork: return "photo.on.rectangle.angled"
        case .ui: return Symbols.uiLog
        case .settings: return Symbols.settings
        case .other: return Symbols.otherLog
        }
    }

    var tint: Color {
        switch self {
        case .networking: return .cyan
        case .playback: return .green
        case .library: return .orange
        case .lyrics: return .pink
        case .downloads: return .blue
        case .artwork: return .yellow
        case .ui: return .purple
        case .settings: return .gray
        case .other: return Theme.secondaryText
        }
    }
}

private extension LogEntry.Level {
    var shortLabel: String {
        switch self {
        case .info: return "I"
        case .warning: return "W"
        case .error: return "E"
        }
    }

    var tint: Color {
        switch self {
        case .info: return Theme.accent
        case .warning: return .yellow
        case .error: return Theme.error
        }
    }

    var severityRank: Int {
        switch self {
        case .info: return 0
        case .warning: return 1
        case .error: return 2
        }
    }
}
