import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ArtworkPrefetchProgress: Equatable {
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

// Accent icons, neutral row text.
private struct AccentIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label {
            configuration.title
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        } icon: {
            configuration.icon.foregroundStyle(Theme.accent)
        }
    }
}

enum SettingsViewMode: String {
    case list
    case categories
}

enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case playback
    case scrobbling
    case audio
    case streaming
    case appearance
    case server
    case storage
    case backups
    case performance
    case developer
    case about

    var id: String { rawValue }

    var sectionKey: String {
        switch self {
        case .playback: return "Playback"
        case .scrobbling: return "Scrobbling"
        case .audio: return "Audio"
        case .streaming: return "Streaming & Downloads"
        case .appearance: return "Appearance"
        case .server: return "Server"
        case .storage: return "Storage"
        case .backups: return "Backups"
        case .performance: return "Performance"
        case .developer: return "Developer"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .playback: return "play.circle"
        case .scrobbling: return "dot.radiowaves.left.and.right"
        case .audio: return "speaker.wave.2.fill"
        case .streaming: return "arrow.down.circle"
        case .appearance: return "paintbrush"
        case .server: return "server.rack"
        case .storage: return "internaldrive"
        case .backups: return "clock.arrow.circlepath"
        case .performance: return "bolt.badge.a"
        case .developer: return "hammer"
        case .about: return "info.circle"
        }
    }

    @MainActor
    var title: String {
        switch self {
        case .scrobbling:
            return "Scrobbling"
        default:
            return SettingsView.localizedSectionTitle(sectionKey)
        }
    }

    var summary: String {
        switch self {
        case .playback: return "Autoplay, transitions, shuffle"
        case .scrobbling: return "Last.fm and ListenBrainz"
        case .audio: return "Equalizer, normalization, spatial"
        case .streaming: return "Quality, downloads, limits"
        case .appearance: return "Theme, language, artwork"
        case .server: return "Connection, health, logout"
        case .storage: return "Caches, lyrics, local files"
        case .backups: return "Settings and playlists"
        case .performance: return "Speed, battery, image loading"
        case .developer: return "Tools, logs, experiments"
        case .about: return "Version and changelog"
        }
    }

    var searchRows: [[String]] {
        switch self {
        case .playback:
            return [["autoplay", "play"], ["autoplay", "infinite play", "infinite", "autoplay style", "fill", "similar", "random", "genre"], ["crossfade", "fade", "automix", "transition", "duration", "style", "blend", "silence", "bpm", "tempo"], ["gapless playback"], ["enhanced caching", "playback cache", "prefetch", "seamless", "buffer"], ["shuffle"], ["artwork zoom on play", "artwork", "zoom"], ["resume playback after interruption", "resume", "interruption", "interrupt", "phone call", "siri", "other app", "force stop"]]
        case .scrobbling:
            return [["last.fm", "listenbrainz", "scrobbling", "now playing"]]
        case .audio:
            return [["volume normalization", "replaygain", "replay gain", "normalize", "loudness"], ["equalizer", "eq", "bands", "graphic"], ["mono audio", "mono", "accessibility", "downmix"], ["spatial widener", "spatial", "3d", "stereo", "widener", "spatialize"]]
        case .streaming:
            return [["wi-fi quality", "wifi", "streaming", "quality", "bitrate"], ["cellular quality", "cellular", "mobile", "data"], ["download quality", "download", "bitrate"], ["transcoding format", "transcode", "format", "mp3", "aac", "opus"], ["download mode", "multithreaded", "threads", "single", "parallel"], ["download speed limit", "speed", "limit", "throttle"], ["storage cap", "cap", "max size", "storage"], ["auto-evict", "auto evict", "evict"]]
        case .appearance:
            return [["language", "languages", "idioma", "langue", "sprache", "lingua", "translate", "translation", "localization", "localisation"], ["hidden albums", "hide albums", "visibility", "library visibility", "artist visibility"], ["theme", "system", "device", "dark", "light", "amoled", "oled", "black", "appearance"], ["show lossless badge", "lossless", "badge"], ["live artwork", "animated artwork", "live", "gif", "webp", "motion", "animation"], ["stylized player cover", "stylised player cover", "full bleed", "edge to edge", "player cover", "cover style"], ["dynamic player background", "dynamic", "background"], ["song artwork in lists", "artwork", "thumbnail", "cover", "track"], ["accent color", "accent", "color", "colour", "theme"]]
        case .server:
            return [["connected to", "server url", "cellular url", "data", "wifi", "username", "edit connection", "test connection", "log out", "logout", "sign out"], ["server health & speed test", "speed test", "server health", "latency", "connection"]]
        case .storage:
            return [["downloaded tracks", "download missing songs", "download all missing", "download all music", "playback cache", "enhanced caching", "prefetch", "artwork cache", "local artwork library", "cover", "artist pictures", "lyrics cache", "local lyrics", "save lyrics", "app data", "total", "clear downloads", "clear playback cache", "clear artwork", "delete local artwork", "clear lyrics", "cache", "storage"], ["download local artwork library", "cover", "covers", "album artwork", "artist pictures", "local images"]]
        case .backups:
            return [["settings backup", "settings", "backup", "restore", "export", "import"], ["playlist backup", "playlist", "deleted", "restore", "auto", "json"]]
        case .performance:
            return [["performance mode", "battery", "power save", "saver", "low power"], ["image loading", "images", "speed", "power", "threads", "fast", "conservative"], ["data caching", "cache", "aggressive", "memory"], ["prefetch artist images", "prefetch", "artist", "profile", "pictures"]]
        case .developer:
            return [["developer tools", "developer", "tools", "diagnostics"], ["experiments", "flags"], ["playback cache diagnostics", "cache diagnostics"], ["performance overlay", "overlay", "fps"], ["notifications", "toast"], ["dump app files", "export", "logs"], ["logging", "logs"]]
        case .about:
            return [["version", "build", "about", "app"], ["changelog", "release notes"]]
        }
    }
}

struct SettingsView: View {
    let focusedCategory: SettingsCategory?

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL

    @AppStorage("settingsViewMode") private var settingsViewMode = SettingsViewMode.list.rawValue

    @AppStorage("infinitePlayStyle")   var infinitePlayStyle   = "random"
    @AppStorage("gaplessPlayback")     var gaplessPlayback     = "on"
    @AppStorage("enhancedPlaybackCaching") var enhancedPlaybackCaching = true
    @AppStorage("replayGainMode")      var replayGainMode      = "off"
    @AppStorage("crossfadeDurationSeconds") var crossfadeDurationSeconds = 6.0
    @AppStorage("automixStyle")        var automixStyle        = "balanced"
    @AppStorage("automixMaxBlendSeconds") var automixMaxBlendSeconds = 10.0
    @AppStorage("automixSilenceTrim")  var automixSilenceTrim  = true
    @AppStorage("automixTempoMatch")   var automixTempoMatch   = true
    @AppStorage("monoAudio")           var monoAudio           = false
    @AppStorage("spatialWidener")      var spatialWidener      = false
    @AppStorage("spatialWidenerAmount") var spatialWidenerAmount = 0.65
    @AppStorage("spatialWidenerMode")  var spatialWidenerMode   = "enhanced"
    @AppStorage("resumeAfterInterruption") var resumeAfterInterruption = true

    @AppStorage("streamingBitrate")    var streamingBitrate    = 0
    @AppStorage("streamingBitrateCell")var streamingBitrateCell = 0
    @AppStorage("downloadBitrate")     var downloadBitrate     = 0
    @AppStorage("transcodingFormat")   var transcodingFormat   = "raw"
    @AppStorage("downloadThreadingMode") var downloadThreadingMode = "multi"
    @AppStorage("downloadSpeedLimitKBps") var downloadSpeedLimitKBps = 0
    @AppStorage("downloadCapMB")       var downloadCapMB       = 0
    @AppStorage("autoEvictDownloads")  var autoEvictDownloads  = false

    @AppStorage("artworkAnimation")    var artworkAnimation    = true
    @AppStorage("liveArtwork")         var liveArtwork         = true
    @AppStorage("stylizedPlayerCover") var stylizedPlayerCover = false
    @AppStorage("themeMode")           var themeMode           = "dark"
    @AppStorage("showLosslessBadge")   var showLosslessBadge   = true
    @AppStorage("dynamicBackground")   var dynamicBackground   = true
    @AppStorage("showTrackArtwork")    var showTrackArtwork    = true
    @AppStorage("accentColorName")     var accentColorName     = "purple"
    @AppStorage("customAccentRed")      var customAccentRed     = 0.55
    @AppStorage("customAccentGreen")    var customAccentGreen   = 0.36
    @AppStorage("customAccentBlue")     var customAccentBlue    = 0.96

    @AppStorage("imageLoadMode")       var imageLoadMode       = "balanced"
    @AppStorage("cacheMode")           var cacheMode           = "balanced"
    @AppStorage("prefetchArtistImages") var prefetchArtistImages = false
    @AppStorage("localArtworkLibraryDownloaded") var localArtworkLibraryDownloaded = false

    @AppStorage("developerLogging")    var developerLogging    = true
    @AppStorage("developerUnlocked")   var developerUnlocked    = false
    @AppStorage("showWarningNotifications") var showWarningNotifications = false
    @AppStorage("autoPlaylistBackupEnabled") var autoPlaylistBackupEnabled = true
    @AppStorage("saveLyricsLocally") var saveLyricsLocally = true
    @AppStorage("hasConfirmedDownloadAllMissingSongs") var hasConfirmedDownloadAllMissingSongs = false

    @State var downloadsSize: String  = "…"
    @State var playbackCacheSize: String = "…"
    @State var artworkSize: String     = "…"
    @State var localArtworkSize: String = "…"
    @State var lyricsSize: String = "…"
    @State var localArtworkBytes: Int = 0
    @State var dataSize: String        = "…"
    @State var totalCacheSize: String  = "…"
    @State var playEventsSize: String = "…"
    @State var logsSize: String = "…"
    @State var showClearCacheAlert   = false
    @State var showClearArtworkAlert = false
    @State var showClearLocalArtworkAlert = false
    @State var showClearPlayEventsFirstAlert = false
    @State var showClearPlayEventsSecondAlert = false
    @State var showClearLogsAlert   = false
    @State var showLogoutAlert      = false
    @State var connectionStatus     = ""
    @State var isTesting            = false
    @State var isPrefetchingArtwork = false
    @State var artworkPrefetchProgress = ArtworkPrefetchProgress()

    // missing-song bulk download flow
    @State var isCalculatingDownloadAll = false
    @State var downloadAllSongs: [Song] = []
    @State var downloadAllBytes = 0
    @State var downloadAllCount = 0
    @State var downloadAllFreeBytes = 0
    @State var showDownloadAllConfirm = false
    @State var showDownloadAllNoSpace = false
    @State var settingsSearch       = ""
    @State var versionTapCount      = 0
    @State var showCustomSpeedAlert = false
    @State var showCustomCapAlert   = false
    @State var customSpeedText      = ""
    @State var customCapText        = ""
    @State var isDumpingAppFiles    = false
    @State var appDumpStatus: String?
    @State var isExportingSettings = false
    @State var showSettingsImporter = false
    @State var settingsBackupStatus: String?
    @State var isExportingPlaylists = false
    @State var isImportingPlaylists = false
    @State var showPlaylistImporter = false
    @State var playlistTransferStatus: String?
    @State var deletedPlaylistBackups: [PlaylistBackupSnapshot] = []
    @State var hasLoadedPlaylistBackups = false
    @State var didScheduleInitialRefresh = false
    @State var loggedPlayEventCount: Int?
    @StateObject var lyricsDownloader = LyricsBulkDownloader.shared
    @StateObject var hiddenAlbums = HiddenAlbumStore.shared
    @StateObject var downloadService = DownloadService.shared
    @State var playlistBackupStatus: String?
    @State var isRefreshingPlaylistBackups = false
    @State var restoringPlaylistBackupID: String?

    init(focusedCategory: SettingsCategory? = nil) {
        self.focusedCategory = focusedCategory
    }

    var audio: AudioPlayer { appState.audioPlayer }
    var hasLocalArtworkLibrary: Bool { localArtworkLibraryDownloaded || localArtworkBytes > 0 }
    var viewMode: SettingsViewMode { SettingsViewMode(rawValue: settingsViewMode) ?? .list }

    // MARK: - Search filtering

    var query: String {
        settingsSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    var isSearching: Bool { !query.isEmpty }

    func rowVisible(_ section: String, _ keywords: [String]) -> Bool {
        guard isSearching else { return true }
        if section.lowercased().contains(query) { return true }
        return keywords.contains { $0.lowercased().contains(query) }
    }
    func sectionVisible(_ section: String, _ rows: [[String]]) -> Bool {
        guard isSearching else { return true }
        if section.lowercased().contains(query) { return true }
        return rows.contains { rowVisible(section, $0) }
    }

    // Localized header text for a section. The English `section` string stays the stable
    // key used by search matching; only the displayed title is translated.
    @MainActor
    static func localizedSectionTitle(_ section: String) -> String {
        switch section {
        case "Playback":              return L(.settings_section_playback)
        case "Audio":                 return L(.settings_section_audio)
        case "Streaming & Downloads": return L(.settings_section_streaming)
        case "Performance":           return L(.settings_section_performance)
        case "Appearance":            return L(.settings_section_appearance)
        case "Notifications":         return L(.settings_section_notifications)
        case "Backups":               return L(.settings_section_backups)
        case "Server":                return L(.settings_section_server)
        case "Storage":               return L(.settings_section_storage)
        case "About":                 return L(.settings_section_about)
        case "Developer":             return L(.settings_section_developer)
        default:                      return section
        }
    }

    func sectionTitle(_ section: String) -> String {
        Self.localizedSectionTitle(section)
    }

    var body: some View {
        settingsBody
            .alert("Download Missing Songs", isPresented: $showDownloadAllConfirm) {
                Button(L(.action_download)) { startDownloadAll() }
                Button(L(.action_cancel), role: .cancel) {}
            } message: {
                Text("Download \(downloadAllCount) missing song\(downloadAllCount == 1 ? "" : "s") (\(SettingsView.formatBytes(downloadAllBytes)))? You have \(SettingsView.formatBytes(downloadAllFreeBytes)) free.")
            }
            .alert("Not Enough Storage", isPresented: $showDownloadAllNoSpace) {
                Button(L(.action_ok), role: .cancel) {}
            } message: {
                Text("Downloading missing songs needs about \(SettingsView.formatBytes(downloadAllBytes)) but only \(SettingsView.formatBytes(downloadAllFreeBytes)) is free. Free up space or download albums individually.")
            }
            .fileImporter(
                isPresented: $showSettingsImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                restoreSettingsBackup(result)
            }
    }

    private var settingsBody: some View {
        settingsAlerts
    }

    private var settingsChrome: some View {
        settingsContent
            .navigationTitle(settingsTitle)
            .navigationBarBackButtonHidden(true)
            .background(SwipeBackEnabler())
            .toolbar { settingsToolbar }
            .preferredColorScheme(Theme.colorScheme)
            .onAppear { scheduleInitialRefresh() }
            .onChangeCompat(of: downloadService.bulkProgress.phase) { _, phase in
                handleBulkDownloadPhaseChange(phase)
            }
    }

    @ToolbarContentBuilder
    private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            GlassBackButton()
        }
        if focusedCategory == nil {
            ToolbarItem(placement: .topBarTrailing) {
                settingsModeMenu
            }
        }
    }

    private var settingsAlerts: some View {
        settingsChrome
            .alert("Clear Downloads", isPresented: $showClearCacheAlert) {
                Button(L(.action_clear), role: .destructive) { clearDownloads() }
                Button(L(.action_cancel), role: .cancel) {}
            } message: { Text("This removes all downloaded tracks. They can be re-downloaded.") }
            .alert("Clear Caches", isPresented: $showClearArtworkAlert) {
                Button(L(.action_clear), role: .destructive) { clearArtworkCache() }
                Button(L(.action_cancel), role: .cancel) {}
            } message: { Text("Removes cached artwork and saved home data. They’ll be re-fetched as needed.") }
            .alert("Delete Local Artwork Library", isPresented: $showClearLocalArtworkAlert) {
                Button(L(.action_delete), role: .destructive) { clearLocalArtworkLibrary() }
                Button(L(.action_cancel), role: .cancel) {}
            } message: { Text("Removes downloaded album covers and artist profile pictures used for faster local image loading.") }
            .alert("Clear Listening Stats?", isPresented: $showClearPlayEventsFirstAlert) {
                Button(L(.action_continue), role: .destructive) { showClearPlayEventsSecondAlert = true }
                Button(L(.action_cancel), role: .cancel) {}
            } message: { Text("This will clear all logged play events and reset local listening stats. This cannot be undone.") }
            .alert("Really Clear All Stats?", isPresented: $showClearPlayEventsSecondAlert) {
                Button("Clear Everything", role: .destructive) { clearPlayEvents() }
                Button(L(.action_cancel), role: .cancel) {}
            } message: { Text("Be very sure: every local play event will be permanently removed and your stats cannot be recovered.") }
            .alert("Clear All Logs", isPresented: $showClearLogsAlert) {
                Button(L(.action_clear), role: .destructive) {
                    AppLogger.shared.clearAll()
                    VoltaNotificationCenter.shared.post(L(.notif_logs_cleared), tone: .success)
                }
                Button(L(.action_cancel), role: .cancel) {}
            } message: { Text("All log entries will be permanently removed.") }
            .alert("Log Out", isPresented: $showLogoutAlert) {
                Button(L(.action_logout), role: .destructive) { appState.logout() }
                Button(L(.action_cancel), role: .cancel) {}
            } message: { Text("You'll be disconnected from \(appState.currentServer?.displayName ?? "the server").") }
            .alert("Custom Speed Limit", isPresented: $showCustomSpeedAlert) {
                TextField("MB per second", text: $customSpeedText)
                    .keyboardType(.decimalPad)
                Button(L(.action_set)) {
                    if let mb = Double(customSpeedText), mb > 0 {
                        downloadSpeedLimitKBps = Int(mb * 1024)
                    }
                }
                Button(L(.action_cancel), role: .cancel) {}
            } message: { Text("Enter a download speed limit in MB/s.") }
            .alert("Custom Storage Cap", isPresented: $showCustomCapAlert) {
                TextField("GB", text: $customCapText)
                    .keyboardType(.decimalPad)
                Button(L(.action_set)) {
                    if let gb = Double(customCapText), gb > 0 {
                        downloadCapMB = Int(gb * 1024)
                    }
                }
                Button(L(.action_cancel), role: .cancel) {}
            } message: { Text("Enter a maximum download size in GB.") }
    }

    private var settingsContent: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                if let focusedCategory {
                    settingsSection(for: focusedCategory)
                } else {
                    switch viewMode {
                    case .list:
                        settingsSections
                    case .categories:
                        settingsCategoryRows
                    }
                }
            }
            .labelStyle(AccentIconLabelStyle())
            .searchable(text: $settingsSearch, placement: .navigationBarDrawer(displayMode: .automatic), prompt: L(.settings_search))
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
    }

    private var settingsTitle: String {
        focusedCategory?.title ?? L(.settings_title)
    }

    private var settingsModeMenu: some View {
        Menu {
            Button {
                settingsViewMode = SettingsViewMode.list.rawValue
            } label: {
                Label("List", systemImage: viewMode == .list ? "checkmark.circle.fill" : "list.bullet")
            }

            Button {
                settingsViewMode = SettingsViewMode.categories.rawValue
            } label: {
                Label("Categories", systemImage: viewMode == .categories ? "checkmark.circle.fill" : "square.grid.2x2")
            }
        } label: {
            Image(systemName: viewMode == .categories ? "square.grid.2x2" : "list.bullet")
        }
        .accessibilityLabel("Settings View")
    }

    @ViewBuilder
    private var settingsSections: some View {
        playbackSection
        scrobblingSection
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

    @ViewBuilder
    private var settingsCategoryRows: some View {
        Section {
            ForEach(visibleSettingsCategories) { category in
                NavigationLink(value: SettingsRoute.category(category)) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.title)
                                .foregroundStyle(Theme.primaryText)
                            Text(category.summary)
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    } icon: {
                        Image(systemName: category.icon)
                    }
                }
                .foregroundStyle(Theme.primaryText)
            }
        }
        .listRowBackground(Theme.secondaryBackground)
    }

    private var visibleSettingsCategories: [SettingsCategory] {
        SettingsCategory.allCases.filter { category in
            if category == .developer && !developerUnlocked { return false }
            return sectionVisible(category.sectionKey, category.searchRows)
        }
    }

    @ViewBuilder
    private func settingsSection(for category: SettingsCategory) -> some View {
        switch category {
        case .playback:
            playbackSection
        case .scrobbling:
            scrobblingSection
        case .audio:
            audioSection
        case .streaming:
            streamingSection
        case .appearance:
            appearanceSection
        case .server:
            serverSection
        case .storage:
            cacheSection
        case .backups:
            backupSection
        case .performance:
            performanceSection
        case .developer:
            developerSection
        case .about:
            aboutSection
        }
    }

    private func handleBulkDownloadPhaseChange(_ phase: DownloadBulkPhase) {
        switch phase {
        case .finished, .cancelled:
            refreshCacheSize()
        case .idle, .running, .paused:
            break
        }
    }

    func scheduleInitialRefresh() {
        guard !didScheduleInitialRefresh else {
            refreshCacheSize()
            loadDeletedPlaylistBackups()
            loadLoggedPlayEventCount()
            return
        }
        didScheduleInitialRefresh = true
        Task {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 160_000_000)
            refreshCacheSize()
            loadDeletedPlaylistBackups()
            loadLoggedPlayEventCount()
        }
    }

    func loadDeletedPlaylistBackups(force: Bool = false) {
        guard force || !hasLoadedPlaylistBackups else { return }
        Task {
            let snapshots = await DeveloperExperiments.runSync(priority: .utility) {
                PlaylistBackupStore.deletedSnapshotsOnDisk()
            }
            deletedPlaylistBackups = snapshots
            hasLoadedPlaylistBackups = true
        }
    }

    func updateDeletedPlaylistBackupsFromStore() {
        deletedPlaylistBackups = PlaylistBackupStore.deletedSnapshots(from: PlaylistBackupStore.shared.snapshots)
        hasLoadedPlaylistBackups = true
    }

    func loadLoggedPlayEventCount() {
        guard developerUnlocked else { return }
        Task {
            await Task.yield()
            loggedPlayEventCount = StatsStore.shared.allEvents().count
        }
    }
}
