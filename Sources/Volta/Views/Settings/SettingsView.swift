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

struct SettingsView: View {
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) var dismiss

    @AppStorage("infinitePlayStyle")   var infinitePlayStyle   = "random"
    @AppStorage("gaplessPlayback")     var gaplessPlayback     = "on"
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
    @State var playlistBackupStore = PlaylistBackupStore.shared
    @StateObject var lyricsDownloader = LyricsBulkDownloader.shared
    @State var hiddenAlbums = HiddenAlbumStore.shared
    @State var downloadService = DownloadService.shared
    @State var playlistBackupStatus: String?
    @State var isRefreshingPlaylistBackups = false
    @State var restoringPlaylistBackupID: String?

    var audio: AudioPlayer { appState.audioPlayer }
    var hasLocalArtworkLibrary: Bool { localArtworkLibraryDownloaded || localArtworkBytes > 0 }

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
    func sectionTitle(_ section: String) -> String {
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
            .navigationTitle(L(.settings_title))
            .navigationBarBackButtonHidden(true)
            .background(SwipeBackEnabler())
            .toolbar { settingsToolbar }
            .preferredColorScheme(Theme.colorScheme)
            .onAppear { refreshCacheSize() }
            .onChange(of: downloadService.bulkProgress.phase) { _, phase in
                handleBulkDownloadPhaseChange(phase)
            }
    }

    @ToolbarContentBuilder
    private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            GlassBackButton()
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
            .labelStyle(AccentIconLabelStyle())
            .searchable(text: $settingsSearch, placement: .navigationBarDrawer(displayMode: .automatic), prompt: L(.settings_search))
            .scrollContentBackground(.hidden)
            .background(Theme.background)
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
}
