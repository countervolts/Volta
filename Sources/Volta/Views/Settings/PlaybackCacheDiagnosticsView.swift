import Foundation
import SwiftUI

struct PlaybackCacheDiagnosticsView: View {
    @Environment(AppState.self) private var appState

    @AppStorage(PlaybackCacheSettings.enabledKey) private var enhancedPlaybackCaching = true
    @AppStorage(PlaybackCacheSettings.developerModeKey) private var developerModeRaw = PlaybackCacheDeveloperMode.followSettings.rawValue

    @State private var snapshot: PlaybackCacheDiagnosticsSnapshot?
    @State private var report = "Ready. Start playback with queued upcoming tracks, then run a probe or prefetch manually."
    @State private var testTrackCount = 3
    @State private var isRunning = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                controlsSection
                testsSection
                runtimeSection
                transferSection
                reportSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle("Playback Cache")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
        }
        .preferredColorScheme(Theme.colorScheme)
        .onAppear { refresh() }
        .task {
            while !Task.isCancelled {
                await MainActor.run { refresh() }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        .onChange(of: enhancedPlaybackCaching) { _, enabled in
            if enabled {
                appState.audioPlayer.refreshPlaybackCache()
                report = "Enhanced caching enabled. Upcoming tracks will be prefetched when playback is active."
            } else {
                PlaybackCacheService.shared.cancelPrefetches()
                report = "Enhanced caching disabled. Active playback-cache transfers were cancelled."
            }
            refresh()
        }
        .onChange(of: developerModeRaw) { _, rawValue in
            let mode = PlaybackCacheDeveloperMode(rawValue: rawValue) ?? .followSettings
            if mode == .disabled {
                PlaybackCacheService.shared.cancelPrefetches()
            } else {
                appState.audioPlayer.refreshPlaybackCache()
            }
            report = "Developer override changed to \(mode.label)."
            refresh()
        }
    }

    private var controlsSection: some View {
        Section {
            Toggle(isOn: $enhancedPlaybackCaching) {
                Label("Enhanced Caching", systemImage: "bolt.horizontal.circle")
            }
            .tint(Theme.accent)

            Picker(selection: $developerModeRaw) {
                ForEach(PlaybackCacheDeveloperMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            } label: {
                Label("Developer Override", systemImage: "slider.horizontal.3")
            }
            .tint(Theme.accent)

            if let snapshot {
                metricRow("Effective Mode", snapshot.effectiveMode.capitalized)
                metricRow("Network", snapshot.network.rawValue.capitalized)
                metricRow("Prefetch Count", "\(snapshot.prefetchCount)")
                metricRow("Max Concurrent", "\(snapshot.maxConcurrentTransfers)")
                metricRow("Cache Cap", snapshot.maxBytes > 0 ? formatBytes(snapshot.maxBytes) : "Off")
            }
        } header: {
            Text("Mode")
        } footer: {
            Text("Force Off disables the playback cache regardless of the user toggle. Force Cellular uses the cellular profile even on Wi-Fi.")
        }
        .listRowBackground(Theme.secondaryBackground)
    }

    private var testsSection: some View {
        Section {
            Stepper(value: $testTrackCount, in: 1...8) {
                LabeledContent("Test Tracks") {
                    Text("\(testTrackCount)")
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            LabeledContent("Upcoming Queue") {
                Text("\(upcomingSongs(limit: 99).count) tracks")
                    .foregroundStyle(Theme.secondaryText)
            }
            .foregroundStyle(Theme.primaryText)

            Button {
                prefetchUpcoming()
            } label: {
                Label("Prefetch Upcoming Now", systemImage: "arrow.down.circle")
            }
            .foregroundStyle(Theme.primaryText)
            .disabled(isRunning)

            Button {
                runCacheProbe()
            } label: {
                HStack {
                    Label("Run Cache Probe", systemImage: "stopwatch")
                    Spacer()
                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Theme.accent)
                    }
                }
            }
            .foregroundStyle(Theme.primaryText)
            .disabled(isRunning)

            Button {
                resetMetrics()
            } label: {
                Label("Reset Metrics", systemImage: "arrow.counterclockwise")
            }
            .foregroundStyle(Theme.primaryText)
            .disabled(isRunning)

            Button(role: .destructive) {
                clearCache()
            } label: {
                Label("Clear Playback Cache", systemImage: "trash")
            }
            .disabled(isRunning)
        } header: {
            Text("Tests")
        } footer: {
            Text("Probe downloads upcoming queue items into the playback cache and measures completed transfers. It does not change the queue or start playback.")
        }
        .listRowBackground(Theme.secondaryBackground)
    }

    @ViewBuilder
    private var runtimeSection: some View {
        if let snapshot {
            Section {
                metricRow("Enabled", snapshot.enabled ? "On" : "Off")
                metricRow("Override", snapshot.developerMode.label)
                metricRow("Size on Disk", formatBytes(snapshot.bytesOnDisk))
                metricRow("Stored Entries", "\(snapshot.storedEntries)")
                metricRow("Active Transfers", "\(snapshot.activeTransfers)")
                metricRow("Preparing", "\(snapshot.preparingTransfers)")
                metricRow("Updated", snapshot.updatedAt.formatted(date: .omitted, time: .standard))

                if !snapshot.activeTitles.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Active Titles")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                        ForEach(Array(snapshot.activeTitles.enumerated()), id: \.offset) { _, title in
                            Text(title)
                                .font(.caption)
                                .foregroundStyle(Theme.primaryText)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Runtime")
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    @ViewBuilder
    private var transferSection: some View {
        if let snapshot {
            Section {
                metricRow("Hits", "\(snapshot.hits)")
                metricRow("Misses", "\(snapshot.misses)")
                metricRow("Hit Rate", formatPercent(snapshot.hitRate))
                metricRow("Started", "\(snapshot.started)")
                metricRow("Completed", "\(snapshot.completed)")
                metricRow("Failed", "\(snapshot.failed)")
                metricRow("Skipped", "\(snapshot.skipped)")
                metricRow("Evicted", "\(snapshot.evicted)")
                metricRow("Bytes Written", formatBytes(snapshot.bytesWritten))
                metricRow("Last Transfer", lastTransferText(snapshot))
                metricRow("Last Event", snapshot.lastEvent)
            } header: {
                Text("Performance")
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    private var reportSection: some View {
        Section {
            Text(report)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.primaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                refresh()
                report = "Metrics refreshed."
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .foregroundStyle(Theme.primaryText)
            .disabled(isRunning)
        } header: {
            Text("Report")
        }
        .listRowBackground(Theme.secondaryBackground)
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .foregroundStyle(Theme.primaryText)
    }

    private func refresh() {
        snapshot = PlaybackCacheService.shared.diagnostics()
    }

    private func prefetchUpcoming() {
        guard let client = appState.client else {
            report = "No active server connection."
            return
        }

        let songs = upcomingSongs(limit: testTrackCount)
        guard !songs.isEmpty else {
            report = "No upcoming tracks in the queue. Start playback or add songs after the current track."
            return
        }

        let uncached = songs.filter { !PlaybackCacheService.shared.isCached($0, client: client) }
        guard !uncached.isEmpty else {
            report = "Selected upcoming tracks are already cached."
            refresh()
            return
        }

        PlaybackCacheService.shared.prefetchForDiagnostics(uncached, client: client, count: uncached.count)
        report = "Prefetch requested for \(uncached.count) upcoming track\(uncached.count == 1 ? "" : "s")."
        refresh()
    }

    private func runCacheProbe() {
        guard !isRunning else { return }
        guard let client = appState.client else {
            report = "No active server connection."
            return
        }

        let songs = upcomingSongs(limit: testTrackCount)
        guard !songs.isEmpty else {
            report = "No upcoming tracks in the queue. Start playback or add songs after the current track."
            return
        }

        isRunning = true
        report = "Running cache probe for \(songs.count) upcoming track\(songs.count == 1 ? "" : "s")..."

        Task { @MainActor in
            defer {
                isRunning = false
                refresh()
            }

            let before = PlaybackCacheService.shared.diagnostics()
            let startedAt = Date()
            var attempts = 0
            var lastStarted = before.started
            var lastTerminal = before.completed + before.failed + before.skipped

            while attempts < 3 {
                let uncached = songs.filter { !PlaybackCacheService.shared.isCached($0, client: client) }
                guard !uncached.isEmpty else { break }

                PlaybackCacheService.shared.prefetchForDiagnostics(uncached, client: client, count: uncached.count)
                attempts += 1

                var settled = false
                for _ in 0..<60 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    let latest = PlaybackCacheService.shared.diagnostics()
                    snapshot = latest

                    let cachedCount = songs.filter { PlaybackCacheService.shared.isCached($0, client: client) }.count
                    let terminal = latest.completed + latest.failed + latest.skipped
                    let madeProgress = latest.started != lastStarted || terminal != lastTerminal || cachedCount == songs.count
                    lastStarted = latest.started
                    lastTerminal = terminal

                    if cachedCount == songs.count {
                        settled = true
                        break
                    }
                    if latest.activeTransfers == 0 && latest.preparingTransfers == 0 {
                        settled = true
                        if !madeProgress { attempts = 3 }
                        break
                    }
                }

                if !settled { break }
            }

            let after = PlaybackCacheService.shared.diagnostics()
            let elapsed = Date().timeIntervalSince(startedAt)
            let cachedCount = songs.filter { PlaybackCacheService.shared.isCached($0, client: client) }.count
            let bytesDelta = max(0, after.bytesWritten - before.bytesWritten)
            let completedDelta = max(0, after.completed - before.completed)
            let failedDelta = max(0, after.failed - before.failed)
            let skippedDelta = max(0, after.skipped - before.skipped)
            let startedDelta = max(0, after.started - before.started)

            report = [
                "Cache probe complete",
                "Tracks selected: \(songs.count)",
                "Cached after probe: \(cachedCount)/\(songs.count)",
                "Transfers started: \(startedDelta)",
                "Completed: \(completedDelta)",
                "Failed: \(failedDelta)",
                "Skipped: \(skippedDelta)",
                "Bytes written: \(formatBytes(bytesDelta))",
                "Elapsed: \(formatSeconds(elapsed))",
                "Average write rate: \(formatSpeed(bytes: bytesDelta, seconds: elapsed))",
                "Mode: \(after.developerMode.label) -> \(after.effectiveMode)"
            ].joined(separator: "\n")
            refresh()
        }
    }

    private func clearCache() {
        PlaybackCacheService.shared.clear()
        report = "Playback cache cleared."
        refresh()
    }

    private func resetMetrics() {
        PlaybackCacheService.shared.resetDiagnostics()
        report = "Playback-cache metrics reset."
        refresh()
    }

    private func upcomingSongs(limit: Int) -> [Song] {
        let queue = appState.audioPlayer.queue
        guard !queue.isEmpty else { return [] }
        let start = min(appState.audioPlayer.currentIndex + 1, queue.count)
        return Array(queue.dropFirst(start).prefix(limit))
    }

    private func lastTransferText(_ snapshot: PlaybackCacheDiagnosticsSnapshot) -> String {
        guard snapshot.lastTransferBytes > 0 else { return "n/a" }
        let size = formatBytes(snapshot.lastTransferBytes)
        let seconds = formatSeconds(snapshot.lastTransferSeconds)
        let speed = formatSpeed(bytes: snapshot.lastTransferBytes, seconds: snapshot.lastTransferSeconds)
        return "\(size) in \(seconds) (\(speed))"
    }

    private func formatBytes(_ value: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    private func formatPercent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private func formatSeconds(_ value: TimeInterval?) -> String {
        guard let value else { return "n/a" }
        return formatSeconds(value)
    }

    private func formatSeconds(_ value: TimeInterval) -> String {
        if value < 10 {
            return String(format: "%.2fs", value)
        }
        return String(format: "%.1fs", value)
    }

    private func formatSpeed(bytes: Int, seconds: TimeInterval?) -> String {
        guard let seconds else { return "n/a" }
        return formatSpeed(bytes: bytes, seconds: seconds)
    }

    private func formatSpeed(bytes: Int, seconds: TimeInterval) -> String {
        guard seconds > 0, bytes > 0 else { return "n/a" }
        return "\(formatBytes(Int(Double(bytes) / seconds)))/s"
    }
}
