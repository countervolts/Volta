import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct ArtworkPrefetchProgress: Equatable {
    var completed = 0
    var total = 0
    var failed = 0
    var current = "Ready"

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(completed) / Double(total))
    }

    var detail: String {
        guard total > 0 else { return current }
        let base = "\(completed) of \(total)"
        return failed > 0 ? "\(base) · \(failed) failed" : base
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @AppStorage("gaplessPlayback")     private var gaplessPlayback     = "on"
    @AppStorage("replayGainMode")      private var replayGainMode      = "off"
    @AppStorage("crossfadeDurationSeconds") private var crossfadeDurationSeconds = 6.0
    @AppStorage("automixStyle")        private var automixStyle        = "balanced"
    @AppStorage("automixMaxBlendSeconds") private var automixMaxBlendSeconds = 10.0
    @AppStorage("automixSilenceTrim")  private var automixSilenceTrim  = true
    @AppStorage("automixTempoMatch")   private var automixTempoMatch   = true
    @AppStorage("monoAudio")           private var monoAudio           = false
    @AppStorage("spatialWidener")      private var spatialWidener      = false
    @AppStorage("resumeAfterInterruption") private var resumeAfterInterruption = true

    @AppStorage("streamingBitrate")    private var streamingBitrate    = 0
    @AppStorage("streamingBitrateCell")private var streamingBitrateCell = 0
    @AppStorage("downloadBitrate")     private var downloadBitrate     = 0
    @AppStorage("transcodingFormat")   private var transcodingFormat   = "raw"
    @AppStorage("downloadThreadingMode") private var downloadThreadingMode = "multi"
    @AppStorage("downloadSpeedLimitKBps") private var downloadSpeedLimitKBps = 0
    @AppStorage("downloadCapMB")       private var downloadCapMB       = 0
    @AppStorage("autoEvictDownloads")  private var autoEvictDownloads  = false

    @AppStorage("artworkAnimation")    private var artworkAnimation    = true
    @AppStorage("liveArtwork")         private var liveArtwork         = true
    @AppStorage("themeMode")           private var themeMode           = "dark"
    @AppStorage("showLosslessBadge")   private var showLosslessBadge   = true
    @AppStorage("dynamicBackground")   private var dynamicBackground   = true
    @AppStorage("showTrackArtwork")    private var showTrackArtwork    = true
    @AppStorage("accentColorName")     private var accentColorName     = "purple"
    @AppStorage("customAccentRed")      private var customAccentRed     = 0.55
    @AppStorage("customAccentGreen")    private var customAccentGreen   = 0.36
    @AppStorage("customAccentBlue")     private var customAccentBlue    = 0.96

    @AppStorage("imageLoadMode")       private var imageLoadMode       = "balanced"
    @AppStorage("cacheMode")           private var cacheMode           = "balanced"
    @AppStorage("prefetchArtistImages") private var prefetchArtistImages = false
    @AppStorage("localArtworkLibraryDownloaded") private var localArtworkLibraryDownloaded = false

    @AppStorage("developerLogging")    private var developerLogging    = true
    @AppStorage("developerPerformanceOverlay") private var developerPerformanceOverlay = false
    // hidden until the user taps the Version/Build row 7 times (Android-style)
    @AppStorage("developerUnlocked")   private var developerUnlocked    = false
    @AppStorage("showWarningNotifications") private var showWarningNotifications = false
    @AppStorage("autoPlaylistBackupEnabled") private var autoPlaylistBackupEnabled = true
    @AppStorage("saveLyricsLocally") private var saveLyricsLocally = true

    @State private var downloadsSize: String  = "…"
    @State private var artworkSize: String     = "…"
    @State private var localArtworkSize: String = "…"
    @State private var lyricsSize: String = "…"
    @State private var localArtworkBytes: Int = 0
    @State private var dataSize: String        = "…"
    @State private var totalCacheSize: String  = "…"
    @State private var playEventsSize: String = "…"
    @State private var logsSize: String = "…"
    @State private var artworkLibraryEstimate = "Calculating…"
    @State private var showClearCacheAlert   = false
    @State private var showClearArtworkAlert = false
    @State private var showClearLocalArtworkAlert = false
    @State private var showClearPlayEventsFirstAlert = false
    @State private var showClearPlayEventsSecondAlert = false
    @State private var showClearLogsAlert   = false
    @State private var showLogoutAlert      = false
    @State private var connectionStatus     = ""
    @State private var isTesting            = false
    @State private var isPrefetchingArtwork = false
    @State private var artworkPrefetchProgress = ArtworkPrefetchProgress()
    @State private var settingsSearch       = ""
    @State private var versionTapCount      = 0
    @State private var showCustomSpeedAlert = false
    @State private var showCustomCapAlert   = false
    @State private var customSpeedText      = ""
    @State private var customCapText        = ""
    @State private var isDumpingAppFiles    = false
    @State private var appDumpStatus: String?
    @State private var isExportingSettings = false
    @State private var showSettingsImporter = false
    @State private var settingsBackupStatus: String?
    @State private var isExportingPlaylists = false
    @State private var isImportingPlaylists = false
    @State private var showPlaylistImporter = false
    @State private var playlistTransferStatus: String?
    @State private var playlistBackupStore = PlaylistBackupStore.shared
    @StateObject private var lyricsDownloader = LyricsBulkDownloader.shared
    @State private var playlistBackupStatus: String?
    @State private var isRefreshingPlaylistBackups = false
    @State private var restoringPlaylistBackupID: String?

    private var audio: AudioPlayer { appState.audioPlayer }
    private var hasLocalArtworkLibrary: Bool { localArtworkLibraryDownloaded || localArtworkBytes > 0 }
    private var customAccentColor: Color {
        Color(red: customAccentRed, green: customAccentGreen, blue: customAccentBlue)
    }

    // MARK: - Search filtering

    private var query: String {
        settingsSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    private var isSearching: Bool { !query.isEmpty }

    private func rowVisible(_ section: String, _ keywords: [String]) -> Bool {
        guard isSearching else { return true }
        if section.lowercased().contains(query) { return true }
        return keywords.contains { $0.lowercased().contains(query) }
    }
    private func sectionVisible(_ section: String, _ rows: [[String]]) -> Bool {
        guard isSearching else { return true }
        if section.lowercased().contains(query) { return true }
        return rows.contains { rowVisible(section, $0) }
    }

    var body: some View {
        settingsContent
            .navigationTitle("Settings")
            .navigationBarBackButtonHidden(true)
            .background(SwipeBackEnabler())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
            }
            .preferredColorScheme(Theme.colorScheme)
            .onAppear { refreshCacheSize() }
            .task(id: appState.currentServer?.id) { await estimateArtworkLibrarySize() }
            .alert("Clear Downloads", isPresented: $showClearCacheAlert) {
                Button("Clear", role: .destructive) { clearDownloads() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This removes all downloaded tracks. They can be re-downloaded.") }
            .alert("Clear Caches", isPresented: $showClearArtworkAlert) {
                Button("Clear", role: .destructive) { clearArtworkCache() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Removes cached artwork and saved home data. They’ll be re-fetched as needed.") }
            .alert("Delete Local Artwork Library", isPresented: $showClearLocalArtworkAlert) {
                Button("Delete", role: .destructive) { clearLocalArtworkLibrary() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Removes downloaded album covers and artist profile pictures used for faster local image loading.") }
            .alert("Clear Listening Stats?", isPresented: $showClearPlayEventsFirstAlert) {
                Button("Continue", role: .destructive) { showClearPlayEventsSecondAlert = true }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This will clear all logged play events and reset local listening stats. This cannot be undone.") }
            .alert("Really Clear All Stats?", isPresented: $showClearPlayEventsSecondAlert) {
                Button("Clear Everything", role: .destructive) { clearPlayEvents() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Be very sure: every local play event will be permanently removed and your stats cannot be recovered.") }
            .alert("Clear All Logs", isPresented: $showClearLogsAlert) {
                Button("Clear", role: .destructive) {
                    AppLogger.shared.clearAll()
                    VoltaNotificationCenter.shared.post("Logs cleared", tone: .success)
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("All log entries will be permanently removed.") }
            .alert("Log Out", isPresented: $showLogoutAlert) {
                Button("Log Out", role: .destructive) { appState.logout() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("You'll be disconnected from \(appState.currentServer?.displayName ?? "the server").") }
            .alert("Custom Speed Limit", isPresented: $showCustomSpeedAlert) {
                TextField("MB per second", text: $customSpeedText)
                    .keyboardType(.decimalPad)
                Button("Set") {
                    if let mb = Double(customSpeedText), mb > 0 {
                        downloadSpeedLimitKBps = Int(mb * 1024)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Enter a download speed limit in MB/s.") }
            .alert("Custom Storage Cap", isPresented: $showCustomCapAlert) {
                TextField("GB", text: $customCapText)
                    .keyboardType(.decimalPad)
                Button("Set") {
                    if let gb = Double(customCapText), gb > 0 {
                        downloadCapMB = Int(gb * 1024)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Enter a maximum download size in GB.") }
            .fileImporter(
                isPresented: $showSettingsImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                restoreSettingsBackup(result)
            }
    }

    private var settingsContent: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                playbackSection
                audioSection
                streamingSection
                appearanceSection
                serverSection
                cacheSection
                backupSection
                performanceSection
                developerSection
                aboutSection
            }
            .searchable(text: $settingsSearch, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search settings")
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
    }

    // formatted current download-speed limit for the menu label
    private var speedLimitLabel: String {
        guard downloadSpeedLimitKBps > 0 else { return "Unlimited" }
        let mb = Double(downloadSpeedLimitKBps) / 1024
        return mb >= 1 ? String(format: "%g MB/s", mb) : "\(downloadSpeedLimitKBps) KB/s"
    }

    // formatted current storage cap for the menu label
    private var capLabel: String {
        guard downloadCapMB > 0 else { return "Unlimited" }
        let gb = Double(downloadCapMB) / 1024
        return gb >= 1 ? String(format: "%g GB", gb) : "\(downloadCapMB) MB"
    }

    private var customAccentSwatch: some View {
        let selected = accentColorName == "custom"
        return Circle()
            .fill(customAccentColor)
            .frame(width: 32, height: 32)
            .overlay(
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(selected ? 1 : 0)
            )
            .overlay(
                Circle().stroke(.white.opacity(0.9), lineWidth: selected ? 2 : 0)
                    .padding(-3)
            )
            .scaleEffect(selected ? 1.12 : 1)
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    accentColorName = "custom"
                }
            }
    }

    private func setCustomAccent(_ color: Color) {
        let ui = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        customAccentRed = Double(r)
        customAccentGreen = Double(g)
        customAccentBlue = Double(b)
        accentColorName = "custom"
    }

    // MARK: - Playback

    @ViewBuilder
    private var playbackSection: some View {
        let s = "Playback"
        if sectionVisible(s, [["autoplay", "play"], ["crossfade", "fade", "automix", "transition", "duration", "style", "blend", "silence", "bpm", "tempo"], ["gapless playback"], ["shuffle"], ["artwork zoom on play", "artwork", "zoom"], ["resume playback after interruption", "resume", "interruption", "interrupt", "phone call", "siri", "other app", "force stop"]]) {
            Section(s) {
                if rowVisible(s, ["autoplay", "play"]) {
                    Toggle(isOn: Binding(
                        get: { audio.isAutoplay },
                        set: { audio.isAutoplay = $0 }
                    )) {
                        Label("Autoplay", systemImage: "play.circle")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["crossfade", "fade", "automix", "transition"]) {
                    Picker(selection: Binding(
                        get: { audio.transitionMode },
                        set: { audio.setTransitionMode($0) }
                    )) {
                        ForEach(PlaybackTransitionMode.allCases) { mode in
                            Text(mode.settingsLabel)
                                .tag(mode)
                                .disabled(mode == .automix && gaplessPlayback == "off")
                        }
                    } label: {
                        Label("Track Transition", systemImage: audio.transitionMode.icon)
                    }
                    .tint(Theme.accent)

                    crossfadeTuningControls
                }

                if rowVisible(s, ["automix", "transition", "style", "blend", "silence", "bpm", "tempo"]) {
                    NavigationLink {
                        AutoMixSettingsView()
                    } label: {
                        Label("AutoMix", systemImage: "waveform.path")
                    }
                    .foregroundStyle(Theme.primaryText)
                }

                if rowVisible(s, ["gapless playback"]) {
                    Picker(selection: $gaplessPlayback) {
                        Text("Off").tag("off")
                        Text("Weak").tag("weak")
                        Text("On").tag("on")
                    } label: {
                        Label("Gapless Playback", systemImage: "music.note")
                    }
                    .tint(Theme.accent)
                    .onChange(of: gaplessPlayback) { _, mode in
                        if mode == "off", audio.transitionMode == .automix {
                            audio.setTransitionMode(.crossfade)
                        }
                    }
                }

                if rowVisible(s, ["shuffle"]) {
                    Toggle(isOn: Binding(
                        get: { audio.isShuffle },
                        set: { _ in audio.toggleShuffle() }
                    )) {
                        Label("Shuffle by Default", systemImage: "shuffle")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["artwork zoom on play", "artwork", "zoom"]) {
                    Toggle(isOn: $artworkAnimation) {
                        Label("Artwork Zoom on Play", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["resume playback after interruption", "resume", "interruption", "interrupt", "phone call", "siri", "other app", "force stop"]) {
                    Toggle(isOn: $resumeAfterInterruption) {
                        Label("Resume After Interruption", systemImage: "play.circle.fill")
                    }
                    .tint(Theme.accent)
                }
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    @ViewBuilder
    private var crossfadeTuningControls: some View {
        switch audio.transitionMode {
        case .off:
            EmptyView()
        case .crossfade:
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Crossfade Duration", value: "\(Int(crossfadeDurationSeconds))s")
                    .foregroundStyle(Theme.primaryText)
                Slider(value: $crossfadeDurationSeconds, in: 1...12, step: 1)
                    .tint(Theme.accent)
                    .onChange(of: crossfadeDurationSeconds) { _, _ in
                        audio.setTransitionMode(audio.transitionMode)
                    }
            }
        case .automix:
            EmptyView()
        }
    }

    // MARK: - Audio

    @ViewBuilder
    private var audioSection: some View {
        let s = "Audio"
        if sectionVisible(s, [["volume normalization", "replaygain", "replay gain", "normalize", "loudness"], ["equalizer", "eq", "bands", "graphic"], ["mono audio", "mono", "accessibility", "downmix"], ["spatial widener", "spatial", "3d", "stereo", "widener", "spatialize"]]) {
            Section(s) {
                if rowVisible(s, ["equalizer", "eq", "bands", "graphic"]) {
                    NavigationLink {
                        EqualizerView()
                    } label: {
                        Label("Equalizer", systemImage: "slider.vertical.3")
                    }
                    .foregroundStyle(Theme.primaryText)
                }

                if rowVisible(s, ["volume normalization", "replaygain", "replay gain", "normalize", "loudness"]) {
                    Picker(selection: $replayGainMode) {
                        Text("Off").tag("off")
                        Text("Track").tag("track")
                        Text("Album").tag("album")
                    } label: {
                        Label("Volume Normalization", systemImage: "speaker.wave.2.bubble")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["mono audio", "mono", "accessibility", "downmix"]) {
                    Toggle(isOn: $monoAudio) {
                        Label("Mono Audio", systemImage: "ear")
                    }
                    .tint(Theme.accent)
                    .onChange(of: monoAudio) { _, _ in applyAudioEffectChange() }
                }

                if rowVisible(s, ["spatial widener", "spatial", "3d", "stereo", "widener", "spatialize"]) {
                    Toggle(isOn: $spatialWidener) {
                        Label("3D Spatial Widener", systemImage: "airpodspro")
                    }
                    .tint(Theme.accent)
                    .disabled(monoAudio)
                    .onChange(of: spatialWidener) { _, _ in applyAudioEffectChange() }
                }
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    // MARK: - Streaming

    @ViewBuilder
    private var streamingSection: some View {
        let s = "Streaming & Downloads"
        if sectionVisible(s, [["wi-fi quality", "wifi", "streaming", "quality", "bitrate"], ["cellular quality", "cellular", "mobile", "data"], ["download quality", "download", "bitrate"], ["transcoding format", "transcode", "format", "mp3", "aac", "opus"], ["download mode", "multithreaded", "threads", "single", "parallel"], ["download speed limit", "speed", "limit", "throttle"], ["storage cap", "cap", "max size", "storage"], ["auto-evict", "auto evict", "evict"]]) {
            Section {
                if rowVisible(s, ["wi-fi quality", "wifi", "streaming", "quality", "bitrate"]) {
                    Picker(selection: $streamingBitrate) {
                        Text("Original").tag(0)
                        Text("320 kbps").tag(320)
                        Text("256 kbps").tag(256)
                        Text("192 kbps").tag(192)
                        Text("128 kbps").tag(128)
                    } label: {
                        Label("Wi-Fi Quality", systemImage: "wifi")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["cellular quality", "cellular", "mobile", "data"]) {
                    Picker(selection: $streamingBitrateCell) {
                        Text("Same as Wi-Fi").tag(0)
                        Text("320 kbps").tag(320)
                        Text("256 kbps").tag(256)
                        Text("192 kbps").tag(192)
                        Text("128 kbps").tag(128)
                        Text("96 kbps").tag(96)
                    } label: {
                        Label("Cellular Quality", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["download quality", "download", "bitrate"]) {
                    Picker(selection: $downloadBitrate) {
                        Text("Original").tag(0)
                        Text("320 kbps").tag(320)
                        Text("256 kbps").tag(256)
                        Text("192 kbps").tag(192)
                    } label: {
                        Label("Download Quality", systemImage: "arrow.down.circle")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["transcoding format", "transcode", "format", "mp3", "aac", "opus"]) {
                    Picker(selection: $transcodingFormat) {
                        Text("MP3").tag("mp3")
                        Text("AAC").tag("aac")
                        Text("Opus").tag("opus")
                        Text("Original").tag("raw")
                    } label: {
                        Label("Transcoding Format", systemImage: "waveform.and.magnifyingglass")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["download mode", "multithreaded", "threads", "single", "parallel"]) {
                    Picker(selection: $downloadThreadingMode) {
                        Text("Multithreaded").tag("multi")
                        Text("Single Thread").tag("single")
                    } label: {
                        Label("Download Mode", systemImage: "square.stack.3d.down.right")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["download speed limit", "speed", "limit", "throttle"]) {
                    Menu {
                        Button("Unlimited") { downloadSpeedLimitKBps = 0 }
                        ForEach([1, 2, 5, 10, 20, 50, 100], id: \.self) { mb in
                            Button("\(mb) MB/s") { downloadSpeedLimitKBps = mb * 1024 }
                        }
                        Divider()
                        Button("Custom…") {
                            customSpeedText = downloadSpeedLimitKBps > 0
                                ? String(format: "%g", Double(downloadSpeedLimitKBps) / 1024) : ""
                            showCustomSpeedAlert = true
                        }
                    } label: {
                        LabeledContent {
                            Text(speedLimitLabel).foregroundStyle(Theme.secondaryText)
                        } label: {
                            Label("Download Speed Limit", systemImage: "speedometer")
                        }
                    }
                    .tint(Theme.primaryText)
                }

                if rowVisible(s, ["storage cap", "cap", "limit", "max size", "storage"]) {
                    Menu {
                        Button("Unlimited") { downloadCapMB = 0 }
                        ForEach([1, 2, 5, 10, 20, 50, 100], id: \.self) { gb in
                            Button("\(gb) GB") { downloadCapMB = gb * 1024 }
                        }
                        Divider()
                        Button("Custom…") {
                            customCapText = downloadCapMB > 0
                                ? String(format: "%g", Double(downloadCapMB) / 1024) : ""
                            showCustomCapAlert = true
                        }
                    } label: {
                        LabeledContent {
                            Text(capLabel).foregroundStyle(Theme.secondaryText)
                        } label: {
                            Label("Download Storage Cap", systemImage: "internaldrive")
                        }
                    }
                    .tint(Theme.primaryText)
                }

                if rowVisible(s, ["auto-evict", "auto evict", "evict", "storage cap"]) {
                    Toggle(isOn: $autoEvictDownloads) {
                        Label("Auto-Evict Oldest", systemImage: "trash.circle")
                    }
                    .tint(Theme.accent)
                    .disabled(downloadCapMB == 0)
                }
            } header: {
                Text(s)
            } footer: {
                Text("Cellular quality applies when not on Wi-Fi. Transcoding format requires server support. Multithreaded downloads fetch several chunks in parallel for faster saves.")
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    // MARK: - Performance

    @ViewBuilder
    private var performanceSection: some View {
        let s = "Performance"
        if sectionVisible(s, [["performance mode", "battery", "power save", "saver", "low power"], ["image loading", "images", "speed", "power", "threads", "fast", "conservative"], ["data caching", "cache", "aggressive", "memory"], ["prefetch artist images", "prefetch", "artist", "profile", "pictures"]]) {
            Section {
                if rowVisible(s, ["performance mode", "battery", "power save", "saver", "low power"]) {
                    NavigationLink {
                        PerformanceModeView()
                    } label: {
                        Label("Performance Mode", systemImage: "bolt.badge.a")
                    }
                    .foregroundStyle(Theme.primaryText)
                }

                if rowVisible(s, ["image loading", "images", "speed", "power", "threads", "fast", "conservative"]) {
                    Picker(selection: $imageLoadMode) {
                        Text("Fast").tag("fast")
                        Text("Balanced").tag("balanced")
                        Text("Conservative").tag("conservative")
                    } label: {
                        Label("Image Loading", systemImage: "bolt.horizontal")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["data caching", "cache", "aggressive", "memory"]) {
                    Picker(selection: $cacheMode) {
                        Text("Aggressive").tag("aggressive")
                        Text("Balanced").tag("balanced")
                        Text("Light").tag("light")
                    } label: {
                        Label("Data Caching", systemImage: "memorychip")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["prefetch artist images", "prefetch", "artist", "profile", "pictures"]) {
                    Toggle(isOn: $prefetchArtistImages) {
                        Label("Prefetch Artist Images", systemImage: "person.crop.square.badge.camera")
                    }
                    .tint(Theme.accent)
                }
            } header: {
                Text(s)
            } footer: {
                Text("Fast uses more connections and CPU for snappier loading; Conservative saves battery. Aggressive caching keeps more artwork in memory. Loading/caching changes apply on next launch.")
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    private var artworkLibraryDownloadRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label("Download Local Artwork Library", systemImage: "photo.on.rectangle.angled")
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                if isPrefetchingArtwork {
                    ProgressView().controlSize(.small).tint(Theme.accent)
                } else if hasLocalArtworkLibrary {
                    Label("Downloaded", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Button {
                        downloadLocalArtworkLibrary()
                    } label: {
                        Text("Download")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.client == nil)
                    .opacity(appState.client == nil ? 0.45 : 1)
                }
            }

            if isPrefetchingArtwork {
                if artworkPrefetchProgress.total > 0 {
                    ProgressView(value: artworkPrefetchProgress.fraction)
                        .tint(Theme.accent)
                } else {
                    ProgressView()
                        .tint(Theme.accent)
                }
                HStack {
                    Text(artworkPrefetchProgress.current)
                    Spacer()
                    Text(artworkPrefetchProgress.detail)
                }
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            } else {
                Text(hasLocalArtworkLibrary ? "Local artwork ready: \(localArtworkSize)" : "Estimated total: \(artworkLibraryEstimate)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.vertical, 4)
    }

    private var lyricsDownloadRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label("Download All Lyrics", systemImage: "quote.bubble")
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                if lyricsDownloader.isRunning {
                    Button(role: .destructive) {
                        lyricsDownloader.cancel()
                    } label: {
                        Text("Stop").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        if let client = appState.client { lyricsDownloader.start(client: client) }
                    } label: {
                        Text("Download")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.client == nil)
                    .opacity(appState.client == nil ? 0.45 : 1)
                }
            }

            if lyricsDownloader.isRunning {
                ProgressView(value: lyricsDownloader.fraction)
                    .tint(Theme.accent)
            }
            Text(lyricsDownloader.statusText)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Appearance

    @ViewBuilder
    private var appearanceSection: some View {
        let s = "Appearance"
        if sectionVisible(s, [["theme", "dark", "light", "amoled", "oled", "black", "appearance"], ["show lossless badge", "lossless", "badge"], ["live artwork", "animated artwork", "live", "gif", "motion"], ["dynamic player background", "dynamic", "background"], ["song artwork in lists", "artwork", "thumbnail", "cover", "track"], ["accent color", "accent", "color", "colour", "theme"]]) {
            Section {
                if rowVisible(s, ["theme", "dark", "light", "amoled", "oled", "black", "appearance"]) {
                    Picker(selection: $themeMode) {
                        Text("Dark").tag("dark")
                        Text("AMOLED").tag("amoled")
                        Text("Light").tag("light")
                    } label: {
                        Label("Theme", systemImage: "circle.lefthalf.filled")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["show lossless badge", "lossless", "badge"]) {
                    Toggle(isOn: $showLosslessBadge) {
                        Label("Show Lossless Badge", systemImage: "waveform.badge.plus")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["live artwork", "animated artwork", "live", "gif", "motion"]) {
                    Toggle(isOn: $liveArtwork) {
                        Label("Live Artwork", systemImage: "sparkles.rectangle.stack")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["song artwork in lists", "artwork", "thumbnail", "cover", "track"]) {
                    Toggle(isOn: $showTrackArtwork) {
                        Label("Song Artwork in Lists", systemImage: "photo")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["dynamic player background", "dynamic", "background"]) {
                    Toggle(isOn: $dynamicBackground) {
                        Label("Dynamic Player Background", systemImage: "paintpalette")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["accent color", "accent", "color", "colour", "theme"]) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Accent Color", systemImage: "paintbrush")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                customAccentSwatch
                                ForEach(Theme.accentNames, id: \.self) { name in
                                    let color = Theme.accentColor(named: name)
                                    let selected = accentColorName == name
                                    Circle()
                                        .fill(color)
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundStyle(.white)
                                                .opacity(selected ? 1 : 0)
                                        )
                                        .overlay(
                                            Circle().stroke(.white.opacity(0.9), lineWidth: selected ? 2 : 0)
                                                .padding(-3)
                                        )
                                        .scaleEffect(selected ? 1.12 : 1)
                                        .onTapGesture {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                accentColorName = name
                                            }
                                        }
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 10)
                        }

                        ColorPicker(
                            "Custom Accent",
                            selection: Binding(get: { customAccentColor }, set: { setCustomAccent($0) }),
                            supportsOpacity: false
                        )
                    }
                }
            } header: {
                Text(s)
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    // MARK: - Library

    @ViewBuilder
    private var notificationsSection: some View {
        let s = "Notifications"
        if sectionVisible(s, [["test all notifications", "notifications", "toast", "error", "warning", "success", "queue", "info"]]) {
            Section {
                Button {
                    VoltaNotificationCenter.shared.postTestNotifications()
                } label: {
                    Label("Test All Notifications", systemImage: "bell.badge")
                }
                .foregroundStyle(Theme.primaryText)

                ForEach(VoltaNotificationTone.allCases) { tone in
                    Button {
                        VoltaNotificationCenter.shared.post(tone.testMessage, tone: tone)
                    } label: {
                        Label("Test \(tone.settingsLabel)", systemImage: tone.icon)
                    }
                    .foregroundStyle(Theme.primaryText)
                }
            } header: {
                Text(s)
            } footer: {
                Text("Warnings and errors logged by the app show automatically. Use these buttons to preview every notification style.")
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    @ViewBuilder
    private var backupSection: some View {
        let s = "Backups"
        if sectionVisible(s, [["settings backup", "settings", "backup", "restore", "export", "import"], ["playlist backup", "playlist", "deleted", "restore", "auto", "json"]]) {
            Section {
                Toggle(isOn: $autoPlaylistBackupEnabled) {
                    Label("Auto Playlist Backups", systemImage: "clock.arrow.circlepath")
                }
                .tint(Theme.accent)

                Button {
                    refreshPlaylistBackups()
                } label: {
                    HStack {
                        Label("Update Playlist Backups", systemImage: "arrow.clockwise")
                        Spacer()
                        if isRefreshingPlaylistBackups {
                            ProgressView().controlSize(.small).tint(Theme.accent)
                        }
                    }
                }
                .foregroundStyle(Theme.primaryText)
                .disabled(!autoPlaylistBackupEnabled || isRefreshingPlaylistBackups || appState.client == nil)

                if playlistBackupStore.deletedSnapshots.isEmpty {
                    Text("No deleted playlist backups")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    ForEach(playlistBackupStore.deletedSnapshots) { snapshot in
                        HStack(spacing: 10) {
                            Button {
                                restoreDeletedPlaylist(snapshot)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "arrow.uturn.backward.circle")
                                        .foregroundStyle(Theme.accent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(snapshot.name)
                                            .foregroundStyle(Theme.primaryText)
                                        Text("\(snapshot.songCount) song\(snapshot.songCount == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundStyle(Theme.secondaryText)
                                    }
                                    Spacer()
                                    if restoringPlaylistBackupID == snapshot.id {
                                        ProgressView().controlSize(.small).tint(Theme.accent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(restoringPlaylistBackupID != nil || appState.client == nil)

                            Button(role: .destructive) {
                                deletePlaylistBackup(snapshot)
                            } label: {
                                Image(systemName: Symbols.trash)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.error)
                                    .frame(width: 34, height: 34)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(restoringPlaylistBackupID == snapshot.id)
                            .accessibilityLabel("Delete backup for \(snapshot.name)")
                        }
                    }
                }

                if let playlistBackupStatus {
                    Text(playlistBackupStatus)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }

                Button {
                    exportSettingsBackup()
                } label: {
                    HStack {
                        Label("Export Settings Backup", systemImage: "square.and.arrow.up")
                        Spacer()
                        if isExportingSettings {
                            ProgressView().controlSize(.small).tint(Theme.accent)
                        }
                    }
                }
                .foregroundStyle(Theme.primaryText)
                .disabled(isExportingSettings)

                Button {
                    showSettingsImporter = true
                } label: {
                    Label("Restore Settings Backup", systemImage: "arrow.down.doc")
                }
                .foregroundStyle(Theme.primaryText)

                if let settingsBackupStatus {
                    Text(settingsBackupStatus)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }

                Button {
                    exportPlaylists()
                } label: {
                    HStack {
                        Label("Export Playlists", systemImage: "square.and.arrow.up.on.square")
                        Spacer()
                        if isExportingPlaylists {
                            ProgressView().controlSize(.small).tint(Theme.accent)
                        }
                    }
                }
                .foregroundStyle(Theme.primaryText)
                .disabled(isExportingPlaylists || appState.client == nil)

                Button {
                    showPlaylistImporter = true
                } label: {
                    HStack {
                        Label("Import Playlists", systemImage: "square.and.arrow.down.on.square")
                        Spacer()
                        if isImportingPlaylists {
                            ProgressView().controlSize(.small).tint(Theme.accent)
                        }
                    }
                }
                .foregroundStyle(Theme.primaryText)
                .disabled(isImportingPlaylists || appState.client == nil)
                .fileImporter(
                    isPresented: $showPlaylistImporter,
                    allowedContentTypes: [.json],
                    allowsMultipleSelection: false
                ) { result in
                    importPlaylists(result)
                }

                if let playlistTransferStatus {
                    Text(playlistTransferStatus)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            } header: {
                Text(s)
            } footer: {
                Text("Playlist backups are kept as local JSON and refresh after playlist edits. Export/Import recreates server playlists as portable JSON files. Settings backups include app preferences and smart playlists. Server passwords stay in Keychain and are not exported.")
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    // MARK: - Server

    @ViewBuilder
    private var serverSection: some View {
        let s = "Server"
        if sectionVisible(s, [["connected to", "server url", "cellular url", "data", "wifi", "username", "edit connection", "test connection", "log out", "logout", "sign out"], ["library stats & speed test", "stats", "speed test", "library", "server health", "latency"]]) {
        Section(s) {
            if let server = appState.currentServer {
                LabeledContent("Connected to", value: server.displayName)
                    .foregroundStyle(Theme.primaryText)
                LabeledContent("Server URL", value: server.urlString)
                    .foregroundStyle(Theme.primaryText)
                if let cell = server.cellularURLString, !cell.isEmpty {
                    LabeledContent("Cellular URL", value: cell)
                        .foregroundStyle(Theme.primaryText)
                }
                if let cellularUsername = server.cellularUsername, !cellularUsername.isEmpty {
                    LabeledContent("Cellular Username", value: cellularUsername)
                        .foregroundStyle(Theme.primaryText)
                }
                LabeledContent("Username", value: server.username)
                    .foregroundStyle(Theme.primaryText)

                NavigationLink {
                    EditConnectionView()
                } label: {
                    Label("Edit Connection", systemImage: Symbols.edit)
                }
                .foregroundStyle(Theme.primaryText)
            }

            Button {
                isTesting = true
                connectionStatus = ""
                Task {
                    defer { isTesting = false }
                    do {
                        try await appState.client?.ping()
                        connectionStatus = "✓ Connected"
                        VoltaNotificationCenter.shared.post("Connection test passed", tone: .success)
                    } catch {
                        connectionStatus = "✗ \(error.localizedDescription)"
                        VoltaNotificationCenter.shared.post("Connection test failed", tone: .error)
                    }
                }
            } label: {
                HStack {
                    Label("Test Connection", systemImage: "network")
                    Spacer()
                    if isTesting {
                        ProgressView().controlSize(.small).tint(Theme.accent)
                    } else if !connectionStatus.isEmpty {
                        Text(connectionStatus)
                            .font(.caption)
                            .foregroundStyle(connectionStatus.hasPrefix("✓") ? .green : Theme.error)
                    }
                }
            }
            .foregroundStyle(Theme.primaryText)

            if rowVisible(s, ["library stats & speed test", "stats", "speed test", "library", "server health", "latency"]) {
                NavigationLink {
                    ServerInfoView()
                } label: {
                    Label("Library Stats & Speed Test", systemImage: "chart.bar")
                }
                .foregroundStyle(Theme.primaryText)
            }

            Button(role: .destructive) {
                showLogoutAlert = true
            } label: {
                Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
        .listRowBackground(Theme.secondaryBackground)
        }
    }

    // MARK: - Cache

    @ViewBuilder
    private var cacheSection: some View {
        let s = "Storage"
        if sectionVisible(s, [["downloaded tracks", "artwork cache", "local artwork library", "cover", "artist pictures", "lyrics cache", "local lyrics", "save lyrics", "app data", "total", "clear downloads", "clear artwork", "delete local artwork", "clear lyrics", "cache", "storage"], ["download local artwork library", "cover", "covers", "album artwork", "artist pictures", "local images"]]) {
        Section {
            LabeledContent("Downloaded Tracks", value: downloadsSize)
                .foregroundStyle(Theme.primaryText)
            LabeledContent("Artwork Cache", value: artworkSize)
                .foregroundStyle(Theme.primaryText)
            LabeledContent("Local Artwork Library", value: localArtworkSize)
                .foregroundStyle(Theme.primaryText)
            LabeledContent("Lyrics Cache", value: lyricsSize)
                .foregroundStyle(Theme.primaryText)
            LabeledContent("Logged Play Events", value: playEventsSize)
                .foregroundStyle(Theme.primaryText)
            LabeledContent("Logs", value: logsSize)
                .foregroundStyle(Theme.primaryText)
            LabeledContent("App Data", value: dataSize)
                .foregroundStyle(Theme.primaryText)
            LabeledContent("Total", value: totalCacheSize)
                .foregroundStyle(Theme.secondaryText)

            if rowVisible(s, ["download local artwork library", "cover", "covers", "album artwork", "artist pictures", "local images"]) {
                artworkLibraryDownloadRow
            }

            Toggle(isOn: $saveLyricsLocally) {
                Label("Save Lyrics Locally", systemImage: Symbols.lyrics)
            }
            .tint(Theme.accent)
            lyricsDownloadRow
            Button(role: .destructive) {
                showClearCacheAlert = true
            } label: {
                Label("Clear Downloads", systemImage: "trash")
            }
            Button(role: .destructive) {
                showClearArtworkAlert = true
            } label: {
                Label("Clear Artwork & Data Cache", systemImage: "photo.stack")
            }
            Button(role: .destructive) {
                showClearLocalArtworkAlert = true
            } label: {
                Label("Delete Local Artwork Library", systemImage: "photo.badge.minus")
            }
            Button(role: .destructive) {
                clearLocalLyrics()
            } label: {
                Label("Clear Local Lyrics", systemImage: "quote.bubble.badge.minus")
            }
            Button(role: .destructive) {
                showClearPlayEventsFirstAlert = true
            } label: {
                Label("Clear Logged Play Events", systemImage: "chart.bar.xaxis")
            }
        } header: {
            Text(s)
        } footer: {
            Text("Downloaded tracks and saved lyrics are kept for offline use. Artwork and data caches rebuild automatically.")
        }
        .listRowBackground(Theme.secondaryBackground)
        }
    }

    // MARK: - About

    @ViewBuilder
    private var aboutSection: some View {
        let s = "About"
        if sectionVisible(s, [["app", "version", "build", "volta"]]) {
        Section(s) {
            LabeledContent("App", value: "Volta")
                .foregroundStyle(Theme.primaryText)
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                LabeledContent("Version", value: version)
                    .foregroundStyle(Theme.primaryText)
                    .contentShape(Rectangle())
                    .onTapGesture { registerSecretDeveloperTap() }
            }
            if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                LabeledContent("Build", value: build)
                    .foregroundStyle(Theme.primaryText)
                    .contentShape(Rectangle())
                    .onTapGesture { registerSecretDeveloperTap() }
            }
        }
        .listRowBackground(Theme.secondaryBackground)
        }
    }

    // Tapping Version/Build 7 times reveals the hidden Developer section. Taps
    // tied to a single counter; a short hint appears as the user gets close.
    private func registerSecretDeveloperTap() {
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
    private var developerSection: some View {
        let s = "Developer"
        // Stays fully hidden (even from search) until unlocked via 7 taps on
        // the Version/Build row in About.
        if developerUnlocked,
           sectionVisible(s, [["developer tools", "simulation", "simulate", "slow server", "expired session", "no network", "profiling", "ram", "automix", "autoplay"], ["notifications", "toast", "warning", "preview"], ["live performance overlay", "overlay", "fps", "ram", "frame pacing"], ["verbose logging", "logging"], ["log device specs", "device", "specs", "ios", "liquid glass", "diagnostics"], ["dump app files", "export app data", "zip", "all files"], ["export all logs"], ["clear all logs"], ["force refresh home"], ["logged play events"], ["queue length"], ["logs", "diagnostics"], ["developer"]]) {
        Section {
            NavigationLink {
                DeveloperToolsView()
            } label: {
                Label("Developer Tools", systemImage: "hammer")
            }
            .foregroundStyle(Theme.primaryText)

            NavigationLink {
                NotificationSettingsView()
            } label: {
                Label("Notifications", systemImage: "bell.badge")
            }
            .foregroundStyle(Theme.primaryText)

            Toggle(isOn: $developerPerformanceOverlay) {
                Label("Live Performance Overlay", systemImage: "chart.xyaxis.line")
            }
            .tint(Theme.accent)

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
                    VoltaNotificationCenter.shared.post("Home refreshed", tone: .success)
                }
            } label: {
                Label("Force Refresh Home", systemImage: "arrow.clockwise")
            }
            .foregroundStyle(Theme.primaryText)

            LabeledContent("Logged Play Events") {
                Text("\(StatsStore.shared.allEvents().count)")
                    .foregroundStyle(Theme.secondaryText)
            }
            .foregroundStyle(Theme.primaryText)

            LabeledContent("Queue Length") {
                Text("\(appState.audioPlayer.queue.count) tracks")
                    .foregroundStyle(Theme.secondaryText)
            }
            .foregroundStyle(Theme.primaryText)

            if rowVisible(s, ["logs", "diagnostics"]) {
                NavigationLink {
                    LogsView()
                } label: {
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
            Text(s)
        } footer: {
            Text("Verbose logging keeps info-level network and playback entries. Warnings and errors are always kept. Tap Version 7 times in About to reveal this section.")
        }
        .listRowBackground(Theme.secondaryBackground)
        }
    }

    // MARK: - Helpers

    private func downloadLocalArtworkLibrary() {
        guard !isPrefetchingArtwork, let client = appState.client else { return }
        isPrefetchingArtwork = true
        artworkPrefetchProgress = ArtworkPrefetchProgress(current: "Loading library…")

        Task {
            defer {
                isPrefetchingArtwork = false
                refreshCacheSize()
            }

            async let albumsRequest = loadAllAlbumsForArtwork(client: client)
            async let artistsRequest = client.artists()

            let albums = await albumsRequest
            let artists = (try? await artistsRequest) ?? []
            let coverIDs = Array(Set(albums.compactMap(\.coverArt))).sorted()
            let artworkSizes: [Int?] = [nil, 300, 600]
            let total = coverIDs.count * artworkSizes.count + artists.count

            artworkPrefetchProgress = ArtworkPrefetchProgress(
                completed: 0,
                total: total,
                failed: 0,
                current: "Downloading album covers…"
            )

            let coverURLs = coverIDs.flatMap { coverID in
                artworkSizes.map { client.coverArtURL(id: coverID, size: $0) }
            }
            await persistArtworkURLs(coverURLs, current: "Downloading album covers…")

            if !artists.isEmpty {
                artworkPrefetchProgress.current = "Downloading artist photos…"
            }
            for artist in artists {
                let ok = await persistArtistArtwork(artist, client: client)
                recordArtworkPrefetchStep(ok: ok, current: "Downloading artist photos…")
            }

            artworkPrefetchProgress.current = "Finished"
            localArtworkLibraryDownloaded = artworkPrefetchProgress.completed > 0
            AppLogger.shared.log(
                "Local artwork library downloaded: \(artworkPrefetchProgress.completed) items, \(artworkPrefetchProgress.failed) failed",
                category: .other
            )
        }
    }

    private func loadAllAlbumsForArtwork(client: SubsonicClient) async -> [Album] {
        var all: [Album] = []
        var offset = 0
        let size = 500
        while true {
            let batch = (try? await client.allAlbums(size: size, offset: offset)) ?? []
            all.append(contentsOf: batch)
            if batch.count < size { break }
            offset += size
            if offset > 10000 { break }
        }
        return all
    }

    @discardableResult
    private func persistArtistArtwork(_ artist: Artist, client: SubsonicClient) async -> Bool {
        if await ArtworkLoader.shared.pinnedArtistImage(id: artist.id) != nil {
            return true
        }
        if let directURL = artist.artistImageUrl.flatMap(URL.init(string:)),
           await ArtworkLoader.shared.persistArtistImage(id: artist.id, from: directURL) {
            return true
        }
        if let info = try? await client.artistInfo(id: artist.id),
           let urlString = info.bestImageUrl,
           let url = URL(string: urlString),
           await ArtworkLoader.shared.persistArtistImage(id: artist.id, from: url) {
            return true
        }
        if let fallbackURL = client.coverArtURL(id: artist.coverArt, size: 600) {
            return await ArtworkLoader.shared.persistArtistImage(id: artist.id, from: fallbackURL)
        }
        return false
    }

    private func persistArtworkURLs(_ urls: [URL?], current: String) async {
        let batchSize = 8
        var index = 0
        while index < urls.count {
            let end = min(index + batchSize, urls.count)
            let batch = Array(urls[index..<end])
            let results = await withTaskGroup(of: Bool.self) { group in
                for url in batch {
                    group.addTask {
                        await ArtworkLoader.shared.persist(url)
                    }
                }
                var values: [Bool] = []
                for await ok in group { values.append(ok) }
                return values
            }
            for ok in results {
                recordArtworkPrefetchStep(ok: ok, current: current)
            }
            index = end
        }
    }

    private func recordArtworkPrefetchStep(ok: Bool, current: String) {
        artworkPrefetchProgress.completed += 1
        if !ok { artworkPrefetchProgress.failed += 1 }
        artworkPrefetchProgress.current = current
    }

    private func estimateArtworkLibrarySize() async {
        guard let client = appState.client else {
            artworkLibraryEstimate = "Unavailable"
            return
        }
        async let albumsRequest = loadAllAlbumsForArtwork(client: client)
        async let artistsRequest = client.artists()
        let albums = await albumsRequest
        let artists = (try? await artistsRequest) ?? []
        let coverIDs = Array(Set(albums.compactMap(\.coverArt))).sorted()
        let coverURLs = coverIDs.prefix(24).flatMap { coverID in
            [client.coverArtURL(id: coverID), client.coverArtURL(id: coverID, size: 300), client.coverArtURL(id: coverID, size: 600)]
        }
        let sampledCoverAverage = await averageContentLength(for: Array(coverURLs.compactMap { $0 }))
        let artistURLs = await sampledArtistArtworkURLs(artists: Array(artists.prefix(12)), client: client)
        let sampledArtistAverage = await averageContentLength(for: artistURLs)

        let coverAverage = sampledCoverAverage ?? 140_000
        let artistAverage = sampledArtistAverage ?? sampledCoverAverage ?? 140_000
        let estimatedBytes = (coverIDs.count * 3 * coverAverage) + (artists.count * artistAverage)
        let sampleCount = (sampledCoverAverage == nil ? 0 : min(coverURLs.count, 72))
            + (sampledArtistAverage == nil ? 0 : artistURLs.count)
        let suffix = sampleCount > 0 ? " sampled" : " estimated"
        artworkLibraryEstimate = SettingsView.formatBytes(estimatedBytes) + suffix
    }

    private func sampledArtistArtworkURLs(artists: [Artist], client: SubsonicClient) async -> [URL] {
        await withTaskGroup(of: URL?.self) { group in
            for artist in artists {
                group.addTask {
                    if let direct = artist.artistImageUrl.flatMap(URL.init(string:)) {
                        return direct
                    }
                    if let info = try? await client.artistInfo(id: artist.id),
                       let urlString = info.bestImageUrl,
                       let url = URL(string: urlString) {
                        return url
                    }
                    return client.coverArtURL(id: artist.coverArt, size: 600)
                }
            }
            var urls: [URL] = []
            for await url in group {
                if let url { urls.append(url) }
            }
            return urls
        }
    }

    private func averageContentLength(for urls: [URL]) async -> Int? {
        guard !urls.isEmpty else { return nil }
        let lengths = await withTaskGroup(of: Int?.self) { group in
            for url in urls.prefix(72) {
                group.addTask { await Self.contentLength(for: url) }
            }
            var values: [Int] = []
            for await value in group {
                if let value, value > 0 { values.append(value) }
            }
            return values
        }
        guard !lengths.isEmpty else { return nil }
        return lengths.reduce(0, +) / lengths.count
    }

    private nonisolated static func contentLength(for url: URL) async -> Int? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        if let (_, response) = try? await URLSession.shared.data(for: request),
           response.expectedContentLength > 0 {
            return Int(response.expectedContentLength)
        }
        return nil
    }

    private func refreshCacheSize() {
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            let docs    = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let caches  = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

            let downloads = SettingsView.directorySize(at: docs.appendingPathComponent("volta-downloads"))
            let artwork   = SettingsView.directorySize(at: caches.appendingPathComponent("artwork"))
                          + SettingsView.directorySize(at: caches.appendingPathComponent("api"))
            let localArtwork = await ArtworkLoader.shared.pinnedArtworkSize()
            let lyrics = await LyricsService.shared.storageSizeBytes()
            let data      = SettingsView.directorySize(at: support.appendingPathComponent("Volta"))
            let playEvents = StatsStore.shared.storageSizeBytes()
            let logs = AppLogger.shared.estimatedSizeBytes()
            let total     = downloads + artwork + data + logs

            await MainActor.run {
                downloadsSize  = SettingsView.formatBytes(downloads)
                artworkSize    = SettingsView.formatBytes(artwork)
                localArtworkSize = SettingsView.formatBytes(localArtwork)
                lyricsSize = SettingsView.formatBytes(lyrics)
                localArtworkBytes = localArtwork
                localArtworkLibraryDownloaded = localArtwork > 0
                dataSize       = SettingsView.formatBytes(data)
                playEventsSize = SettingsView.formatBytes(playEvents)
                logsSize       = SettingsView.formatBytes(logs)
                totalCacheSize = SettingsView.formatBytes(total)
            }
        }
    }

    private func clearArtworkCache() {
        Task {
            await ArtworkLoader.shared.clearCache()
            DiskCache.clear()
            AppLogger.shared.log("Artwork & data cache cleared by user", category: .other)
            VoltaNotificationCenter.shared.post("Artwork cache cleared", tone: .success)
            refreshCacheSize()
        }
    }

    private func clearLocalArtworkLibrary() {
        Task {
            await ArtworkLoader.shared.clearPinnedArtwork()
            localArtworkLibraryDownloaded = false
            localArtworkBytes = 0
            AppLogger.shared.log("Local artwork library cleared by user", category: .other)
            VoltaNotificationCenter.shared.post("Local artwork deleted", tone: .success)
            refreshCacheSize()
        }
    }

    private func clearLocalLyrics() {
        Task {
            await LyricsService.shared.clearLocalLyrics()
            AppLogger.shared.log("Local lyrics cleared by user", category: .other)
            VoltaNotificationCenter.shared.post("Local lyrics cleared", tone: .success)
            refreshCacheSize()
        }
    }

    private nonisolated static func directorySize(at url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]) else { return 0 }
        return enumerator.compactMap { ($0 as? URL) }
            .compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
            .reduce(0, +)
    }

    fileprivate nonisolated static func formatBytes(_ n: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }

    // re-attach/detach the audio processing tap when mono/spatial toggles flip
    private func applyAudioEffectChange() {
        EqualizerEngine.shared.refreshEffectFlags()
        NotificationCenter.default.post(name: .equalizerToggled, object: nil)
    }

    private func exportLogs() {
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
                VoltaNotificationCenter.shared.post("Logs zip ready", tone: .success)
                ShareSheet.present([zip])
            } catch {
                VoltaNotificationCenter.shared.post("Logs export used folder fallback", tone: .warning)
                ShareSheet.present([tmp])
            }
        }
    }

    private func exportSettingsBackup() {
        guard !isExportingSettings else { return }
        isExportingSettings = true
        settingsBackupStatus = "Preparing backup..."
        Task {
            defer { isExportingSettings = false }
            do {
                let url = try SettingsBackupManager.exportURL()
                settingsBackupStatus = "Backup ready"
                VoltaNotificationCenter.shared.post("Settings backup ready", tone: .success)
                ShareSheet.present([url])
            } catch {
                settingsBackupStatus = "Backup failed: \(error.localizedDescription)"
                AppLogger.shared.log("Settings backup failed: \(error.localizedDescription)", category: .other, level: .error)
            }
        }
    }

    private func restoreSettingsBackup(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            let count = try SettingsBackupManager.restore(from: url)
            SmartPlaylistStore.shared.reload()
            PlaylistFolderStore.shared.reload()
            settingsBackupStatus = "Restored \(count) settings"
            VoltaNotificationCenter.shared.post("Settings restored", tone: .success)
        } catch {
            settingsBackupStatus = "Restore failed: \(error.localizedDescription)"
            VoltaNotificationCenter.shared.post("Settings restore failed", tone: .error)
            AppLogger.shared.log("Settings restore failed: \(error.localizedDescription)", category: .other, level: .error)
        }
    }

    private func exportPlaylists() {
        guard !isExportingPlaylists, let client = appState.client else { return }
        isExportingPlaylists = true
        playlistTransferStatus = "Collecting playlists…"
        Task {
            defer { isExportingPlaylists = false }
            do {
                let url = try await PlaylistTransfer.exportURL(client: client)
                playlistTransferStatus = "Playlists exported"
                VoltaNotificationCenter.shared.post("Playlists exported", tone: .success)
                ShareSheet.present([url])
            } catch {
                playlistTransferStatus = "Export failed: \(error.localizedDescription)"
                VoltaNotificationCenter.shared.post("Playlist export failed", tone: .error)
            }
        }
    }

    private func importPlaylists(_ result: Result<[URL], Error>) {
        guard let client = appState.client else { return }
        do {
            guard let url = try result.get().first else { return }
            isImportingPlaylists = true
            playlistTransferStatus = "Importing playlists…"
            Task {
                defer { isImportingPlaylists = false }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let count = try await PlaylistTransfer.importPlaylists(from: url, client: client)
                    playlistTransferStatus = "Imported \(count) playlist\(count == 1 ? "" : "s")"
                    VoltaNotificationCenter.shared.post("Imported \(count) playlists", tone: .success)
                } catch {
                    playlistTransferStatus = "Import failed: \(error.localizedDescription)"
                    VoltaNotificationCenter.shared.post("Playlist import failed", tone: .error)
                }
            }
        } catch {
            playlistTransferStatus = "Import failed: \(error.localizedDescription)"
        }
    }

    private func refreshPlaylistBackups() {
        guard let client = appState.client else {
            playlistBackupStatus = "Connect to a server to update playlist backups"
            return
        }
        guard !isRefreshingPlaylistBackups else { return }
        isRefreshingPlaylistBackups = true
        playlistBackupStatus = "Updating playlist backups..."
        Task {
            await PlaylistBackupStore.shared.backupAll(client: client)
            let count = PlaylistBackupStore.shared.snapshots.count
            let size = SettingsView.formatBytes(PlaylistBackupStore.shared.estimatedSizeBytes())
            playlistBackupStatus = "Backed up \(count) playlist\(count == 1 ? "" : "s") · \(size)"
            isRefreshingPlaylistBackups = false
            VoltaNotificationCenter.shared.post("Playlist backups updated", tone: .success)
        }
    }

    private func restoreDeletedPlaylist(_ snapshot: PlaylistBackupSnapshot) {
        guard let client = appState.client else {
            playlistBackupStatus = "Connect to a server to restore playlists"
            return
        }
        guard restoringPlaylistBackupID == nil else { return }
        restoringPlaylistBackupID = snapshot.id
        playlistBackupStatus = "Restoring \(snapshot.name)..."
        Task {
            do {
                let playlist = try await PlaylistBackupStore.shared.restore(snapshot, client: client)
                playlistBackupStatus = "Restored \(playlist.name)"
                VoltaNotificationCenter.shared.post("Playlist restored", tone: .success)
            } catch {
                playlistBackupStatus = "Restore failed: \(error.localizedDescription)"
                VoltaNotificationCenter.shared.post("Playlist restore failed", tone: .error)
                AppLogger.shared.log("Playlist restore failed: \(error.localizedDescription)", category: .other, level: .error)
            }
            restoringPlaylistBackupID = nil
        }
    }

    private func deletePlaylistBackup(_ snapshot: PlaylistBackupSnapshot) {
        PlaylistBackupStore.shared.delete(snapshot)
        playlistBackupStatus = "Deleted backup for \(snapshot.name)"
        VoltaNotificationCenter.shared.post("Playlist backup deleted", tone: .success)
    }

    private func dumpAppFiles() {
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
                VoltaNotificationCenter.shared.post("App files zip ready", tone: .success)
                ShareSheet.present([url])
            } catch {
                appDumpStatus = "Export failed: \(error.localizedDescription)"
                AppLogger.shared.log("App file dump failed: \(error.localizedDescription)", category: .other, level: .error)
            }
        }
    }

    private nonisolated static func fileSize(at url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private func clearDownloads() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir  = docs.appendingPathComponent("volta-downloads")
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        AppLogger.shared.log("Downloads cleared by user", category: .other)
        VoltaNotificationCenter.shared.post("Downloads cleared", tone: .success)
        refreshCacheSize()
    }

    private func clearPlayEvents() {
        StatsStore.shared.clearAll()
        AppLogger.shared.log("Logged play events cleared by user", category: .other, level: .warning)
        VoltaNotificationCenter.shared.post("Listening stats cleared", tone: .success)
        refreshCacheSize()
    }
}

struct AutoMixSettingsView: View {
    @Environment(AppState.self) private var appState

    @AppStorage("gaplessPlayback") private var gaplessPlayback = "on"
    @AppStorage("automixStyle") private var automixStyle = "balanced"
    @AppStorage("automixMaxBlendSeconds") private var automixMaxBlendSeconds = 10.0
    @AppStorage("automixSilenceTrim") private var automixSilenceTrim = true
    @AppStorage("automixTempoMatch") private var automixTempoMatch = true
    @AppStorage("automixBeatAlign") private var automixBeatAlign = true
    @AppStorage("automixHarmonic") private var automixHarmonic = true
    @AppStorage("automixBassSwap") private var automixBassSwap = true

    private var audio: AudioPlayer { appState.audioPlayer }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                Section {
                    Picker(selection: Binding(
                        get: { audio.transitionMode },
                        set: { audio.setTransitionMode($0) }
                    )) {
                        ForEach(PlaybackTransitionMode.allCases) { mode in
                            Text(mode.settingsLabel)
                                .tag(mode)
                                .disabled(mode == .automix && gaplessPlayback == "off")
                        }
                    } label: {
                        Label("Track Transition", systemImage: audio.transitionMode.icon)
                    }
                    .tint(Theme.accent)
                } header: {
                    Text("Mode")
                } footer: {
                    Text("AutoMix requires Gapless Playback set to Weak or On.")
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    Picker(selection: $automixStyle) {
                        Text("Tight").tag("tight")
                        Text("Balanced").tag("balanced")
                        Text("Wide").tag("wide")
                    } label: {
                        Label("Style", systemImage: "slider.horizontal.3")
                    }
                    .tint(Theme.accent)
                    .onChange(of: automixStyle) { _, _ in audio.setTransitionMode(audio.transitionMode) }

                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Max Blend", value: "\(Int(automixMaxBlendSeconds))s")
                            .foregroundStyle(Theme.primaryText)
                        Slider(value: $automixMaxBlendSeconds, in: 4...18, step: 1)
                            .tint(Theme.accent)
                            .onChange(of: automixMaxBlendSeconds) { _, _ in
                                audio.setTransitionMode(audio.transitionMode)
                            }
                    }

                    Toggle(isOn: $automixSilenceTrim) {
                        Label("Silence Trim", systemImage: "scissors")
                    }
                    .tint(Theme.accent)
                    .onChange(of: automixSilenceTrim) { _, _ in audio.setTransitionMode(audio.transitionMode) }

                    Toggle(isOn: $automixTempoMatch) {
                        Label("BPM Match", systemImage: "metronome")
                    }
                    .tint(Theme.accent)
                    .onChange(of: automixTempoMatch) { _, _ in audio.setTransitionMode(audio.transitionMode) }

                    Toggle(isOn: $automixBeatAlign) {
                        Label("Beat Lock", systemImage: "waveform.path.ecg")
                    }
                    .tint(Theme.accent)
                    .disabled(!automixTempoMatch)
                    .onChange(of: automixBeatAlign) { _, _ in audio.setTransitionMode(audio.transitionMode) }

                    Toggle(isOn: $automixHarmonic) {
                        Label("Harmonic Mixing", systemImage: "pianokeys")
                    }
                    .tint(Theme.accent)
                    .onChange(of: automixHarmonic) { _, _ in audio.setTransitionMode(audio.transitionMode) }

                    Toggle(isOn: $automixBassSwap) {
                        Label("Bass Swap", systemImage: "dial.low")
                    }
                    .tint(Theme.accent)
                    .onChange(of: automixBassSwap) { _, _ in audio.setTransitionMode(audio.transitionMode) }
                } header: {
                    Text("Mixing")
                } footer: {
                    Text("BPM Match bends the outgoing track to the incoming tempo (±6%, pitch preserved). Beat Lock then fires the blend on the downbeat so the two tracks' beats land together, like a DJ. Harmonic Mixing reads each track's musical key (Camelot) and gives compatible pairs a longer blend, clashing pairs a shorter, cleaner handover. Bass Swap rolls the incoming track's low end off and brings it in as it takes over, so the two basslines don't muddy each other (applies when the equalizer is off).")
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    NavigationLink {
                        AutoMixPreviewView()
                    } label: {
                        Label("Preview AutoMix", systemImage: "waveform.badge.magnifyingglass")
                    }
                } footer: {
                    Text("Hear and see how two of your tracks blend with the current settings.")
                }
                .listRowBackground(Theme.secondaryBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle("AutoMix")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
        }
        .preferredColorScheme(Theme.colorScheme)
    }
}

struct NotificationSettingsView: View {
    @AppStorage("showWarningNotifications") private var showWarningNotifications = false
    @AppStorage("showOfflineErrorNotifications") private var showOfflineErrorNotifications = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                Section {
                    Toggle(isOn: $showWarningNotifications) {
                        Label("Show Warning Notifications", systemImage: Symbols.warning)
                    }
                    .tint(Theme.accent)

                    Toggle(isOn: $showOfflineErrorNotifications) {
                        Label("Show Offline Error Notifications", systemImage: "wifi.slash")
                    }
                    .tint(Theme.accent)
                } footer: {
                    Text("Warnings and offline error notifications stay hidden unless enabled. The app keeps logging them.")
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    Button {
                        VoltaNotificationCenter.shared.postTestNotifications()
                    } label: {
                        Label("Preview All", systemImage: "bell.badge")
                    }
                    .foregroundStyle(Theme.primaryText)

                    ForEach(VoltaNotificationTone.allCases) { tone in
                        Button {
                            VoltaNotificationCenter.shared.post(tone.testMessage, tone: tone, force: true)
                        } label: {
                            Label("Preview \(tone.settingsLabel)", systemImage: tone.icon)
                        }
                        .foregroundStyle(Theme.primaryText)
                    }
                } header: {
                    Text("Previews")
                }
                .listRowBackground(Theme.secondaryBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
        }
        .preferredColorScheme(Theme.colorScheme)
    }
}

// MARK: - Edit Connection View

struct EditConnectionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var serverURL: String = ""
    @State private var cellularURL: String = ""
    @State private var useSeparateCellularLogin = false
    @State private var cellularUsername: String = ""
    @State private var cellularPassword: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Form {
                Section {
                    TextField("Server URL", text: $serverURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Username", text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("Password", text: $password)
                } header: {
                    Text("Connection Details")
                } footer: {
                    Text("Enter new credentials to reconnect. Leave password blank to keep existing.")
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    TextField("Cellular URL (optional)", text: $cellularURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Toggle(isOn: $useSeparateCellularLogin.animation(.easeInOut(duration: 0.2))) {
                        Label("Separate Cellular Login", systemImage: "person.badge.key")
                    }
                    .tint(Theme.accent)
                    if useSeparateCellularLogin {
                        TextField("Cellular Username", text: $cellularUsername)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        SecureField("Cellular Password", text: $cellularPassword)
                    }
                } header: {
                    Text("Cellular")
                } footer: {
                    Text("Used automatically when off Wi-Fi. Leave cellular login blank to keep using the main username and password.")
                }
                .listRowBackground(Theme.secondaryBackground)

                if let err = errorMessage {
                    Section {
                        Text(err).foregroundStyle(Theme.error).font(.footnote)
                    }
                    .listRowBackground(Theme.secondaryBackground)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle("Edit Connection")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    saveConnection()
                } label: {
                    if isSaving {
                        ProgressView().controlSize(.small).tint(Theme.accent)
                    } else {
                        Text("Save").foregroundStyle(Theme.accent).fontWeight(.semibold)
                    }
                }
                .disabled(isSaving || serverURL.trimmingCharacters(in: .whitespaces).isEmpty || username.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .preferredColorScheme(Theme.colorScheme)
        .onAppear { prefill() }
    }

    private func prefill() {
        guard let server = appState.currentServer else { return }
        serverURL = server.urlString
        cellularURL = server.cellularURLString ?? ""
        username = server.username
        cellularUsername = server.cellularUsername ?? ""
        useSeparateCellularLogin = server.cellularUsername?.nonBlank != nil || appState.store.cellularPassword(for: server) != nil
    }

    private func saveConnection() {
        guard let currentServer = appState.currentServer else { return }
        guard let url = SubsonicConfig.normalizedURL(from: serverURL) else {
            errorMessage = "Invalid server URL"
            VoltaNotificationCenter.shared.post("Invalid server URL", tone: .error)
            return
        }
        // normalise the optional cellular URL (blank > cleared); reject a non-blank but malformed one
        let trimmedCell = cellularURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var normalizedCell: String? = nil
        if !trimmedCell.isEmpty {
            guard let cellURL = SubsonicConfig.normalizedURL(from: trimmedCell) else {
                errorMessage = "Invalid cellular URL"
                VoltaNotificationCenter.shared.post("Invalid cellular URL", tone: .error)
                return
            }
            normalizedCell = cellURL.absoluteString
        }
        let existingPassword = appState.store.config(for: currentServer)?.password ?? ""
        let existingCellularPassword = appState.store.cellularPassword(for: currentServer)
        let pwd = password.isEmpty ? existingPassword : password
        let cellUsername = useSeparateCellularLogin ? cellularUsername.nonBlank : nil
        let cellPassword: String? = {
            guard useSeparateCellularLogin else { return nil }
            if let entered = cellularPassword.nonBlank { return entered }
            return existingCellularPassword
        }()
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            let config = SubsonicConfig(baseURL: url, username: username, password: pwd)
            do {
                let testClient = SubsonicClient(config: config)
                try await testClient.ping()
                await MainActor.run {
                    appState.completeLogin(config: config)
                    appState.updateCellularConnection(
                        urlString: normalizedCell,
                        username: cellUsername,
                        password: cellPassword
                    )
                    VoltaNotificationCenter.shared.post("Connection saved", tone: .success)
                    dismiss()
                }
            } catch {
                errorMessage = "Could not connect: \(error.localizedDescription)"
                VoltaNotificationCenter.shared.post("Could not connect", tone: .error)
            }
        }
    }
}

// MARK: - Server Info View

struct ServerInfoView: View {
    @Environment(AppState.self) private var appState
    @State private var artistCount: Int? = nil
    @State private var albumCount: Int? = nil
    @State private var songCount: Int? = nil
    @State private var totalDuration: Int? = nil   // seconds
    @State private var totalLibrarySizeBytes: Int? = nil
    @State private var isLoading = false
    @State private var speedTestResult: String? = nil
    @State private var isTesting = false
    @State private var speedGrade: String? = nil
    @State private var health: ServerHealthSnapshot?
    @State private var healthError: String?
    @State private var isCheckingHealth = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                Section {
                    if isCheckingHealth && health == nil {
                        HStack {
                            ProgressView().controlSize(.small).tint(Theme.accent)
                            Text("Checking…").foregroundStyle(Theme.secondaryText)
                        }
                    } else if let health {
                        LabeledContent("Status", value: health.status.capitalized)
                            .foregroundStyle(Theme.primaryText)
                        LabeledContent("Latency", value: "\(health.latencyMS) ms")
                            .foregroundStyle(Theme.primaryText)
                        LabeledContent("API Version", value: health.apiVersion ?? "Unknown")
                            .foregroundStyle(Theme.primaryText)
                        LabeledContent("Server Type", value: health.serverType ?? "Subsonic")
                            .foregroundStyle(Theme.primaryText)
                        LabeledContent("Connection", value: NetworkMonitor.shared.connection.rawValue)
                            .foregroundStyle(Theme.primaryText)
                        if let activeURL = appState.client?.config.baseURL.absoluteString {
                            LabeledContent("Active URL", value: activeURL)
                                .foregroundStyle(Theme.primaryText)
                        }
                        LabeledContent("Checked", value: health.checkedAt.formatted(date: .omitted, time: .shortened))
                            .foregroundStyle(Theme.secondaryText)
                    } else if let healthError {
                        Text(healthError)
                            .foregroundStyle(Theme.error)
                    }

                    Button {
                        Task { await loadHealth() }
                    } label: {
                        HStack {
                            Label("Refresh Health", systemImage: "heart.text.square")
                            Spacer()
                            if isCheckingHealth {
                                ProgressView().controlSize(.small).tint(Theme.accent)
                            }
                        }
                    }
                    .foregroundStyle(Theme.primaryText)
                    .disabled(isCheckingHealth)
                } header: {
                    Text("Server Health")
                }
                .listRowBackground(Theme.secondaryBackground)

                Section("Library") {
                    if isLoading {
                        HStack {
                            ProgressView().controlSize(.small).tint(Theme.accent)
                            Text("Loading…").foregroundStyle(Theme.secondaryText)
                        }
                    } else {
                        if let a = artistCount {
                            LabeledContent("Artists", value: "\(a)").foregroundStyle(Theme.primaryText)
                        }
                        if let al = albumCount {
                            LabeledContent("Albums", value: "\(al)").foregroundStyle(Theme.primaryText)
                        }
                        if let s = songCount {
                            LabeledContent("Songs", value: "\(s)").foregroundStyle(Theme.primaryText)
                        }
                        if let dur = totalDuration {
                            LabeledContent("Total Duration", value: formatDuration(dur)).foregroundStyle(Theme.primaryText)
                        }
                        if let totalLibrarySizeBytes {
                            LabeledContent("Total Music Size", value: SettingsView.formatBytes(totalLibrarySizeBytes)).foregroundStyle(Theme.primaryText)
                        }
                    }
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    Button {
                        runSpeedTest()
                    } label: {
                        HStack {
                            Label("Test Streaming Speed", systemImage: "speedometer")
                            Spacer()
                            if isTesting {
                                ProgressView().controlSize(.small).tint(Theme.accent)
                            } else if let result = speedTestResult {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(result).font(.caption).foregroundStyle(Theme.secondaryText)
                                    if let grade = speedGrade {
                                        Text(grade).font(.caption.bold()).foregroundStyle(gradeColor)
                                    }
                                }
                            }
                        }
                    }
                    .foregroundStyle(Theme.primaryText)
                } header: {
                    Text("Speed Test")
                } footer: {
                    Text("Downloads several megabytes across multiple tracks for a more accurate streaming-speed estimate.")
                }
                .listRowBackground(Theme.secondaryBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle("Server Info")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
        }
        .preferredColorScheme(Theme.colorScheme)
        .task {
            await loadHealth()
            await loadStats()
        }
    }

    private var gradeColor: Color {
        switch speedGrade {
        case "Excellent": return .green
        case "Good": return Theme.accent
        case "Fair": return .yellow
        default: return Theme.error
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let d = seconds / 86400; let h = (seconds % 86400) / 3600; let m = (seconds % 3600) / 60
        if d > 0 { return "\(d)d \(h)h \(m)m" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func loadStats() async {
        guard let client = appState.client else { return }
        isLoading = true
        defer { isLoading = false }

        // Load artists
        let artists = (try? await client.artists()) ?? []
        artistCount = artists.count

        // Load all albums with pagination for full counts
        var allAlbums: [Album] = []
        var offset = 0
        while true {
            let batch = (try? await client.allAlbums(size: 500, offset: offset)) ?? []
            allAlbums.append(contentsOf: batch)
            if batch.count < 500 { break }
            offset += 500
            if offset > 50_000 { break }
        }
        albumCount = allAlbums.count
        songCount = allAlbums.compactMap(\.songCount).reduce(0, +)
        totalDuration = allAlbums.compactMap(\.duration).reduce(0, +)
        totalLibrarySizeBytes = await loadTotalLibrarySize(albums: allAlbums, client: client)
    }

    private func loadHealth() async {
        guard let client = appState.client else { return }
        isCheckingHealth = true
        healthError = nil
        defer { isCheckingHealth = false }
        do {
            health = try await client.serverHealth()
        } catch SubsonicError.serverUnreachable {
            health = nil
            healthError = "Server unreachable"
        } catch {
            health = nil
            healthError = error.localizedDescription
        }
    }

    private func loadTotalLibrarySize(albums: [Album], client: SubsonicClient) async -> Int? {
        var total = 0
        var seen = Set<String>()
        var index = 0
        let batchSize = 12

        while index < albums.count {
            let batch = Array(albums[index..<min(index + batchSize, albums.count)])
            let partials = await withTaskGroup(of: [Song].self) { group in
                for album in batch {
                    group.addTask {
                        (try? await client.album(id: album.id))?.song ?? album.song ?? []
                    }
                }
                var songs: [Song] = []
                for await value in group { songs.append(contentsOf: value) }
                return songs
            }
            for song in partials where seen.insert(song.id).inserted {
                total += song.size ?? 0
            }
            index += batchSize
        }
        return total > 0 ? total : nil
    }

    private func runSpeedTest() {
        guard let client = appState.client else { return }
        isTesting = true
        speedTestResult = nil
        speedGrade = nil
        Task {
            defer { isTesting = false }
            guard let songs = try? await client.randomSongs(size: 4), !songs.isEmpty else {
                speedTestResult = "No data"
                return
            }

            // pull up to 4 MB from several tracks; time only the byte transfer
            // (the random-songs request above is excluded for accuracy) and
            // average across samples to smooth out per-request variance.
            let bytesPerSample = 4 * 1024 * 1024
            var totalBytes = 0
            var totalTime: TimeInterval = 0

            for song in songs.prefix(4) {
                guard let url = client.streamURL(id: song.id) else { continue }
                var req = URLRequest(url: url)
                req.timeoutInterval = 30
                req.cachePolicy = .reloadIgnoringLocalCacheData
                req.setValue("bytes=0-\(bytesPerSample - 1)", forHTTPHeaderField: "Range")

                let t0 = Date()
                if let (data, _) = try? await URLSession.shared.data(for: req), !data.isEmpty {
                    totalTime  += Date().timeIntervalSince(t0)
                    totalBytes += data.count
                }
            }

            guard totalBytes > 0, totalTime > 0 else {
                speedTestResult = "Failed"
                speedGrade = "Poor"
                return
            }

            let kbps = Double(totalBytes) / totalTime / 1024
            let mbps = kbps / 1024
            speedTestResult = mbps >= 1
                ? String(format: "%.1f MB/s", mbps)
                : String(format: "%.0f KB/s", kbps)
            speedGrade = kbps > 2048 ? "Excellent" : kbps > 512 ? "Good" : kbps > 128 ? "Fair" : "Poor"
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
