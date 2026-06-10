import Darwin
import SwiftUI
import UIKit

private struct DeveloperMetric: Identifiable {
    let id = UUID()
    let name: String
    let value: String
}

struct DeveloperToolsView: View {
    @Environment(AppState.self) private var appState

    @AppStorage(DeveloperSimulation.Keys.slowServerEnabled) private var slowServerEnabled = false
    @AppStorage(DeveloperSimulation.Keys.slowServerDelayMS) private var slowServerDelayMS = 1200
    @AppStorage(DeveloperSimulation.Keys.expiredSession) private var expiredSession = false
    @AppStorage(DeveloperSimulation.Keys.noNetwork) private var noNetwork = false
    @AppStorage("developerPerformanceOverlay") private var developerPerformanceOverlay = false

    @State private var report = "Ready"
    @State private var isRunning = false
    @State private var refreshedAt = Date()

    private var audio: AudioPlayer { appState.audioPlayer }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                networkSimulationSection
                runtimeSection
                dryRunSection
                reportSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle("Developer Tools")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
        }
        .preferredColorScheme(Theme.colorScheme)
        .onAppear {
            refreshedAt = .now
            logSimulationState()
        }
        .onChange(of: slowServerEnabled) { _, _ in logSimulationState() }
        .onChange(of: slowServerDelayMS) { _, _ in logSimulationState() }
        .onChange(of: expiredSession) { _, _ in logSimulationState() }
        .onChange(of: noNetwork) { _, _ in logSimulationState() }
    }

    private var networkSimulationSection: some View {
        Section {
            Toggle(isOn: $noNetwork) {
                Label("No Network", systemImage: "wifi.slash")
            }
            .tint(Theme.accent)

            Toggle(isOn: $expiredSession) {
                Label("Expired Session", systemImage: "key.slash")
            }
            .tint(Theme.accent)

            Toggle(isOn: $slowServerEnabled) {
                Label("Slow Server", systemImage: "tortoise")
            }
            .tint(Theme.accent)

            Stepper(value: $slowServerDelayMS, in: 100...10_000, step: 100) {
                LabeledContent("Delay", value: "\(slowServerDelayMS) ms")
                    .foregroundStyle(Theme.primaryText)
            }
            .disabled(!slowServerEnabled)

            Button(role: .destructive) {
                DeveloperSimulation.reset()
            } label: {
                Label("Reset Simulations", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("Network Simulation")
        } footer: {
            Text("These switches affect Subsonic API requests until reset.")
        }
        .listRowBackground(Theme.secondaryBackground)
    }

    private var runtimeSection: some View {
        Section {
            Toggle(isOn: $developerPerformanceOverlay) {
                Label("Live Performance Overlay", systemImage: "chart.xyaxis.line")
            }
            .tint(Theme.accent)

            ForEach(runtimeMetrics) { metric in
                LabeledContent(metric.name, value: metric.value)
                    .foregroundStyle(Theme.primaryText)
            }

            Button {
                refreshedAt = .now
                logRuntimeState()
            } label: {
                Label("Refresh Runtime Snapshot", systemImage: "gauge.with.dots.needle.33percent")
            }
            .foregroundStyle(Theme.primaryText)
        } header: {
            Text("Runtime")
        }
        .listRowBackground(Theme.secondaryBackground)
    }

    private var dryRunSection: some View {
        Section {
            diagnosticButton("Run Profiling Sweep", "speedometer") {
                await runProfilingSweep()
            }
            diagnosticButton("Dry Run Mix Generator", "wand.and.stars") {
                await runMixDryRun()
            }
            diagnosticButton("Dry Run Autoplay", "infinity") {
                await runAutoplayDryRun()
            }
            diagnosticButton("Dry Run AutoMix", "waveform.path") {
                await runAutoMixDryRun()
            }
            Button {
                logPlaybackState()
            } label: {
                Label("Log Playback State", systemImage: "waveform")
            }
            .foregroundStyle(Theme.primaryText)
        } header: {
            Text("Diagnostics")
        }
        .listRowBackground(Theme.secondaryBackground)
    }

    private var reportSection: some View {
        Section {
            Text(report)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Theme.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } header: {
            Text("Report")
        }
        .listRowBackground(Theme.secondaryBackground)
    }

    private func diagnosticButton(
        _ title: String,
        _ systemImage: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            guard !isRunning else { return }
            isRunning = true
            report = "Running \(title)..."
            Task {
                await action()
                isRunning = false
            }
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                if isRunning {
                    ProgressView().controlSize(.small).tint(Theme.accent)
                }
            }
        }
        .foregroundStyle(Theme.primaryText)
        .disabled(isRunning)
    }

    private var runtimeMetrics: [DeveloperMetric] {
        _ = refreshedAt
        let process = ProcessInfo.processInfo
        return [
            DeveloperMetric(name: "App Uptime", value: formatDuration(process.systemUptime)),
            DeveloperMetric(name: "App Footprint", value: formatBytes(Self.memoryFootprintBytes())),
            DeveloperMetric(name: "Physical RAM", value: formatBytes(process.physicalMemory)),
            DeveloperMetric(name: "Thermal State", value: thermalStateLabel(process.thermalState)),
            DeveloperMetric(name: "Low Power Mode", value: process.isLowPowerModeEnabled ? "On" : "Off"),
            DeveloperMetric(name: "Queue", value: "\(audio.queue.count) tracks"),
            DeveloperMetric(name: "Current Index", value: audio.queue.isEmpty ? "None" : "\(audio.currentIndex + 1) of \(audio.queue.count)"),
            DeveloperMetric(name: "Autoplay", value: autoplayLabel(audio.autoplayMode)),
            DeveloperMetric(name: "Transition", value: audio.transitionMode.settingsLabel),
            DeveloperMetric(name: "Network", value: NetworkMonitor.shared.connection.rawValue),
            DeveloperMetric(name: "Simulations", value: DeveloperSimulation.isActive ? "Active" : "Off"),
            DeveloperMetric(name: "Logs", value: "\(AppLogger.shared.allEntries().count) entries"),
        ]
    }

    private func runProfilingSweep() async {
        guard let client = appState.client else {
            report = "No active client."
            return
        }

        var lines = ["Profiling sweep", timestampLine()]
        lines.append(await measure("ping") {
            try await client.ping()
            return "ok"
        })
        lines.append(await measure("artists") {
            let artists = try await client.artists()
            return "\(artists.count) artists"
        })
        lines.append(await measure("albums sample") {
            let albums = try await client.allAlbums(size: 100)
            return "\(albums.count) albums"
        })
        lines.append(await measure("random songs") {
            let songs = try await client.randomSongs(size: 50)
            return "\(songs.count) songs"
        })
        lines.append("App footprint: \(formatBytes(Self.memoryFootprintBytes()))")
        lines.append("Log entries: \(AppLogger.shared.allEntries().count)")
        finishReport(lines, category: .networking)
    }

    private func runMixDryRun() async {
        guard let client = appState.client else {
            report = "No active client."
            return
        }

        var lines = ["Mix generator dry run", timestampLine()]
        let start = Date()
        do {
            let albums = try await client.allAlbums(size: 300)
            let genres = Dictionary(grouping: albums.compactMap(\.genre), by: { $0 })
                .mapValues(\.count)
                .sorted { $0.value > $1.value }
            lines.append("Album sample: \(albums.count)")
            lines.append("Top genres: \(genres.prefix(5).map { "\($0.key) \($0.value)" }.joined(separator: ", "))")

            let randomSongs = try await client.randomSongs(size: 120)
            lines.append("Discovery candidates: \(randomSongs.count)")
            if let topGenre = genres.first?.key {
                let genreSongs = try await client.songsByGenre(topGenre, count: 80)
                lines.append("\(topGenre) mix candidates: \(genreSongs.count)")
            }

            let elapsed = Date().timeIntervalSince(start)
            lines.append("Elapsed: \(String(format: "%.2f", elapsed))s")
            lines.append("Playlist writes: 0")
        } catch {
            lines.append("Failed: \(error.localizedDescription)")
        }
        finishReport(lines, category: .other)
    }

    private func runAutoplayDryRun() async {
        guard let client = appState.client else {
            report = "No active client."
            return
        }

        var lines = ["Autoplay dry run", timestampLine()]
        let current = audio.currentSong
        let existingIDs = Set(audio.queue.map(\.id))
        lines.append("Mode: \(autoplayLabel(audio.autoplayMode))")
        lines.append("Queue: \(audio.queue.count) tracks")
        lines.append("Current: \(current?.title ?? "None")")

        do {
            var candidates: [Song] = []
            if let artistName = audio.autoplayArtistName ?? current?.artist {
                let top = try await client.topSongs(artistName: artistName, count: 20)
                lines.append("Artist candidates: \(top.count)")
                candidates += top
            }
            if let genre = current?.genre, !genre.isEmpty {
                let genreSongs = try await client.songsByGenre(genre, count: 25)
                lines.append("Genre candidates: \(genreSongs.count)")
                candidates += genreSongs
            }
            let random = try await client.randomSongs(size: 30)
            lines.append("Random fallback: \(random.count)")
            candidates += random

            var seen = Set<String>()
            let unique = candidates.filter { seen.insert($0.id).inserted }
            let fresh = unique.filter { !existingIDs.contains($0.id) }
            lines.append("Unique candidates: \(unique.count)")
            lines.append("Fresh candidates: \(fresh.count)")
            lines.append("Queue writes: 0")
        } catch {
            lines.append("Failed: \(error.localizedDescription)")
        }
        finishReport(lines, category: .playback)
    }

    private func runAutoMixDryRun() async {
        var lines = ["AutoMix dry run", timestampLine()]
        guard let current = audio.currentSong else {
            lines.append("No current song.")
            finishReport(lines, category: .playback)
            return
        }
        guard audio.currentIndex + 1 < audio.queue.count else {
            lines.append("No next queue item.")
            lines.append("Current: \(current.title)")
            finishReport(lines, category: .playback)
            return
        }

        let next = audio.queue[audio.currentIndex + 1]
        let sameAlbum = current.albumId != nil && current.albumId == next.albumId
        let sameArtist = current.artistId != nil && current.artistId == next.artistId
        let sameGenre = current.genre != nil && current.genre?.caseInsensitiveCompare(next.genre ?? "") == .orderedSame
        let duration: TimeInterval
        if sameAlbum {
            duration = 4
        } else if sameArtist || sameGenre {
            duration = 11
        } else {
            duration = 8
        }

        lines.append("Transition: \(audio.transitionMode.settingsLabel)")
        lines.append("Gapless: \(UserDefaults.standard.string(forKey: "gaplessPlayback") ?? "off")")
        lines.append("Current: \(current.title)")
        lines.append("Next: \(next.title)")
        lines.append("Same album: \(sameAlbum ? "yes" : "no")")
        lines.append("Same artist: \(sameArtist ? "yes" : "no")")
        lines.append("Same genre: \(sameGenre ? "yes" : "no")")
        lines.append("Estimated fade: \(String(format: "%.1f", duration))s")
        lines.append("Playback writes: 0")
        finishReport(lines, category: .playback)
    }

    private func measure(_ label: String, _ operation: () async throws -> String) async -> String {
        let start = Date()
        do {
            let value = try await operation()
            let elapsed = Date().timeIntervalSince(start)
            return "\(label): \(value) in \(String(format: "%.2f", elapsed))s"
        } catch {
            let elapsed = Date().timeIntervalSince(start)
            return "\(label): failed in \(String(format: "%.2f", elapsed))s - \(error.localizedDescription)"
        }
    }

    private func finishReport(_ lines: [String], category: LogCategory) {
        let text = lines.joined(separator: "\n")
        report = text
        AppLogger.shared.logAlways(text, category: category)
    }

    private func logSimulationState() {
        let parts = [
            noNetwork ? "no-network" : nil,
            expiredSession ? "expired-session" : nil,
            slowServerEnabled ? "slow-server \(slowServerDelayMS)ms" : nil,
        ].compactMap { $0 }
        let value = parts.isEmpty ? "off" : parts.joined(separator: ", ")
        AppLogger.shared.logAlways("Developer simulations: \(value)", category: .networking)
    }

    private func logRuntimeState() {
        let text = runtimeMetrics.map { "\($0.name): \($0.value)" }.joined(separator: "\n")
        report = text
        AppLogger.shared.logAlways("Runtime snapshot\n\(text)", category: .other)
    }

    private func logPlaybackState() {
        let current = audio.currentSong?.title ?? "None"
        let next = audio.currentIndex + 1 < audio.queue.count ? audio.queue[audio.currentIndex + 1].title : "None"
        let text = [
            "Playback state",
            timestampLine(),
            "Current: \(current)",
            "Next: \(next)",
            "Queue: \(audio.queue.count) tracks",
            "Index: \(audio.queue.isEmpty ? 0 : audio.currentIndex + 1)",
            "Autoplay: \(autoplayLabel(audio.autoplayMode))",
            "Transition: \(audio.transitionMode.settingsLabel)",
            "Playing: \(audio.isPlaying ? "yes" : "no")",
        ].joined(separator: "\n")
        report = text
        AppLogger.shared.logAlways(text, category: .playback)
    }

    private func timestampLine() -> String {
        Date().formatted(date: .abbreviated, time: .standard)
    }

    private func autoplayLabel(_ mode: AutoplayMode) -> String {
        switch mode {
        case .off: return "Off"
        case .random: return "AutoPlay"
        case .algorithm: return "Algorithm"
        }
    }

    private func thermalStateLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    private static func memoryFootprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.phys_footprint)
    }
}
