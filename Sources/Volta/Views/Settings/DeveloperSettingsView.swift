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
           sectionVisible(s, [["developer tools", "simulation", "simulate", "slow server", "expired session", "no network", "profiling", "ram", "automix", "autoplay"], ["experiments", "raw animated artwork", "disable ram optimizations", "app worker limit", "workers", "threads", "concurrency"], ["performance overlay", "overlay", "fps", "ram", "frame pacing", "metrics"], ["notifications", "toast", "warning", "preview"], ["verbose logging", "logging"], ["log device specs", "device", "specs", "ios", "liquid glass", "diagnostics"], ["dump app files", "export app data", "zip", "all files"], ["export all logs"], ["clear all logs"], ["force refresh home"], ["logged play events"], ["queue length"], ["logs", "diagnostics"], ["developer"]]) {
        Section {
            NavigationLink(value: SettingsRoute.developerTools) {
                Label("Developer Tools", systemImage: "hammer")
            }
            .foregroundStyle(Theme.primaryText)

            NavigationLink(value: SettingsRoute.developerExperiments) {
                Label("Experiments", systemImage: "testtube.2")
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

            if rowVisible(s, ["logs", "diagnostics"]) {
                NavigationLink(value: SettingsRoute.logs) {
                    Label("Logs", systemImage: Symbols.logs)
                }
                .foregroundStyle(Theme.primaryText)
            }

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

            let files: [ZipSourceFile] = LogCategory.allCases.compactMap { cat in
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
                AppLogger.shared.log("App file dump exported: \(size)", category: .other)
                VoltaNotificationCenter.shared.post(L(.notif_app_files_zip_ready), tone: .success)
                ShareSheet.present([url])
            } catch {
                appDumpStatus = "Export failed: \(error.localizedDescription)"
                AppLogger.shared.log("App file dump failed: \(error.localizedDescription)", category: .other, level: .error)
            }
        }
    }

    nonisolated static func fileSize(at url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    func clearPlayEvents() {
        StatsStore.shared.clearAll()
        loggedPlayEventCount = 0
        AppLogger.shared.log("Logged play events cleared by user", category: .other, level: .warning)
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
                    Toggle(isOn: $rawAnimatedArtwork) {
                        Label("Raw Animated Artwork", systemImage: "livephoto")
                    }
                    .tint(Theme.accent)

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
        .onChange(of: rawAnimatedArtwork) { _, enabled in
            AppLogger.shared.logAlways("Developer experiment: raw animated artwork \(enabled ? "enabled" : "disabled")", category: .other)
        }
        .onChange(of: disableRAMOptimizations) { _, enabled in
            AppLogger.shared.logAlways("Developer experiment: RAM optimizations \(enabled ? "disabled" : "enabled")", category: .other)
        }
        .onChange(of: appWorkerLimit) { _, limit in
            let label = limit > 0 ? "\(limit)" : "off"
            AppLogger.shared.logAlways("Developer experiment: app worker limit \(label)", category: .other)
            VoltaNotificationCenter.shared.post(L(.notif_restart_to_apply), tone: .info)
        }
        .onChange(of: preciseTimestamps) { _, enabled in
            AppLogger.shared.logAlways("Developer experiment: precise timestamps \(enabled ? "enabled" : "disabled")", category: .other)
        }
        .onChange(of: instantScrobbling) { _, enabled in
            AppLogger.shared.logAlways("Developer experiment: instant scrobbling \(enabled ? "enabled" : "disabled")", category: .other)
        }
        .onChange(of: fakeListeningStats) { _, enabled in
            AppLogger.shared.logAlways("Developer experiment: fake listening stats \(enabled ? "enabled" : "disabled")", category: .other)
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
}

private enum LogSortMode: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case oldest = "Oldest"
    case severity = "Severity"
    var id: String { rawValue }
}

struct LogsView: View {
    @State private var selected: LogCategory = .networking
    @State private var levelFilter: LogLevelFilter = .all
    @State private var sortMode: LogSortMode = .newest
    @State private var entries: [LogEntry] = []
    @State private var copied = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Picker("Category", selection: $selected) {
                    ForEach(LogCategory.allCases, id: \.self) { cat in
                        Text(cat.rawValue).tag(cat)
                    }
                }
                .pickerStyle(.segmented)
                .padding(16)

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
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                HStack {
                    Text("\(entries.count) entries")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = entries.map(\.formatted).joined(separator: "\n")
                        copied = true
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            copied = false
                        }
                    } label: {
                        Label(copied ? "Copied!" : "Copy", systemImage: copied ? Symbols.check : Symbols.copy)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(copied ? .green : Theme.accent)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(copied ? Color.green.opacity(0.12) : Theme.accent.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.2), value: copied)

                    Button {
                        AppLogger.shared.clear(category: selected)
                        reload()
                    } label: {
                        Image(systemName: Symbols.trash)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.error)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Theme.error.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                Divider().background(Theme.secondaryText.opacity(0.2))

                if entries.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: Symbols.logs)
                            .font(.system(size: 32, weight: .ultraLight))
                            .foregroundStyle(Theme.secondaryText.opacity(0.5))
                        Text("No entries for \(selected.rawValue)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(entries) { entry in
                                    LogEntryRow(entry: entry)
                                        .id(entry.id)
                                }
                                Color.clear.frame(height: 40).id("bottom")
                            }
                        }
                        .onChange(of: entries.count) { _, _ in
                            withAnimation { proxy.scrollTo("bottom") }
                        }
                    }
                }
            }
        }
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
        }
        .preferredColorScheme(Theme.colorScheme)
        .onAppear { reload() }
        .onChange(of: selected) { _, _ in reload() }
        .onChange(of: levelFilter) { _, _ in reload() }
        .onChange(of: sortMode) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .logEntryAdded)) { _ in reload() }
    }

    private func reload() {
        var next = AppLogger.shared.entries(for: selected)
        switch levelFilter {
        case .all: break
        case .info: next = next.filter { $0.level == .info }
        case .warning: next = next.filter { $0.level == .warning }
        case .error: next = next.filter { $0.level == .error }
        }
        switch sortMode {
        case .newest:
            next.sort { $0.timestamp > $1.timestamp }
        case .oldest:
            next.sort { $0.timestamp < $1.timestamp }
        case .severity:
            next.sort {
                let l = severityRank($0.level)
                let r = severityRank($1.level)
                if l != r { return l > r }
                return $0.timestamp > $1.timestamp
            }
        }
        entries = next
    }

    private func severityRank(_ level: LogEntry.Level) -> Int {
        switch level {
        case .info: return 0
        case .warning: return 1
        case .error: return 2
        }
    }
}

private struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.level.rawValue.prefix(1).uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.black)
                .frame(width: 16, height: 16)
                .background(levelColor, in: RoundedRectangle(cornerRadius: 3))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.primaryText.opacity(0.9))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText.opacity(0.6))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(entry.level == .error ? Theme.error.opacity(0.06) : Color.clear)
    }

    private var levelColor: Color {
        switch entry.level {
        case .info:    return Theme.accent
        case .warning: return .yellow
        case .error:   return Theme.error
        }
    }
}
