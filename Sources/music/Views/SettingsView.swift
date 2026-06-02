import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    // Playback
    @AppStorage("autoplayEnabled")     private var autoplayEnabled     = false
    @AppStorage("crossfadeEnabled")    private var crossfadeEnabled    = false
    @AppStorage("gaplessPlayback")     private var gaplessPlayback     = "on"    // "off", "weak", "on"

    // Streaming & Downloads
    @AppStorage("streamingBitrate")    private var streamingBitrate    = 0       // 0 = original
    @AppStorage("streamingBitrateCell")private var streamingBitrateCell = 0      // cellular override
    @AppStorage("downloadBitrate")     private var downloadBitrate     = 0
    @AppStorage("transcodingFormat")   private var transcodingFormat   = "raw"   // "mp3", "aac", "opus", "raw"
    @AppStorage("downloadThreadingMode") private var downloadThreadingMode = "multi" // "multi", "single"

    // Appearance
    @AppStorage("artworkAnimation")    private var artworkAnimation    = true
    @AppStorage("showLosslessBadge")   private var showLosslessBadge   = true
    @AppStorage("dynamicBackground")   private var dynamicBackground   = true
    @AppStorage("accentColorName")     private var accentColorName     = "purple"

    // Library
    @AppStorage("albumSortOrder")      private var albumSortOrder      = "alphabetical"

    // Developer
    @AppStorage("developerLogging")    private var developerLogging    = true

    @State private var downloadsSize: String  = "…"
    @State private var artworkSize: String     = "…"
    @State private var dataSize: String        = "…"
    @State private var totalCacheSize: String  = "…"
    @State private var showClearCacheAlert   = false
    @State private var showClearArtworkAlert = false
    @State private var showClearLogsAlert   = false
    @State private var showLogoutAlert      = false
    @State private var connectionStatus     = ""
    @State private var isTesting            = false
    @State private var settingsSearch       = ""

    private var audio: AudioPlayer { appState.audioPlayer }

    // MARK: - Search filtering

    private var query: String {
        settingsSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    private var isSearching: Bool { !query.isEmpty }

    // a single row is shown when not searching, the section title matches, or
    // any of the row's keywords matches the query.
    private func rowVisible(_ section: String, _ keywords: [String]) -> Bool {
        guard isSearching else { return true }
        if section.lowercased().contains(query) { return true }
        return keywords.contains { $0.lowercased().contains(query) }
    }
    // a whole section is shown when not searching, its title matches, or any of
    // its rows match.
    private func sectionVisible(_ section: String, _ rows: [[String]]) -> Bool {
        guard isSearching else { return true }
        if section.lowercased().contains(query) { return true }
        return rows.contains { rowVisible(section, $0) }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                playbackSection
                streamingSection
                appearanceSection
                librarySection
                serverSection
                serverInfoSection
                cacheSection
                aboutSection
                developerSection
                logsSection
            }
            .searchable(text: $settingsSearch, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search settings")
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle("Settings")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
        }
        .preferredColorScheme(.dark)
        .onAppear { refreshCacheSize() }
        .alert("Clear Downloads", isPresented: $showClearCacheAlert) {
            Button("Clear", role: .destructive) { clearDownloads() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes all downloaded tracks. They can be re-downloaded.") }
        .alert("Clear Caches", isPresented: $showClearArtworkAlert) {
            Button("Clear", role: .destructive) { clearArtworkCache() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Removes cached artwork and saved home data. They’ll be re-fetched as needed.") }
        .alert("Clear All Logs", isPresented: $showClearLogsAlert) {
            Button("Clear", role: .destructive) { AppLogger.shared.clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("All log entries will be permanently removed.") }
        .alert("Log Out", isPresented: $showLogoutAlert) {
            Button("Log Out", role: .destructive) { appState.logout() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("You'll be disconnected from \(appState.currentServer?.displayName ?? "the server").") }
    }

    // MARK: - Playback

    @ViewBuilder
    private var playbackSection: some View {
        let s = "Playback"
        if sectionVisible(s, [["autoplay", "play"], ["crossfade", "fade"], ["gapless playback"], ["shuffle"], ["artwork zoom on play", "artwork", "zoom"]]) {
            Section(s) {
                if rowVisible(s, ["autoplay", "play"]) {
                    Toggle(isOn: Binding(
                        get: { audio.isAutoplay },
                        set: { _ in audio.toggleAutoplay() }
                    )) {
                        Label("Autoplay", systemImage: "play.circle")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["crossfade", "fade"]) {
                    Toggle(isOn: Binding(
                        get: { audio.isCrossfade },
                        set: { _ in audio.toggleCrossfade() }
                    )) {
                        Label("Crossfade", systemImage: "waveform.path.ecg")
                    }
                    .tint(Theme.accent)
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
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    // MARK: - Streaming

    @ViewBuilder
    private var streamingSection: some View {
        let s = "Streaming & Downloads"
        if sectionVisible(s, [["wi-fi quality", "wifi", "streaming", "quality", "bitrate"], ["cellular quality", "cellular", "mobile", "data"], ["download quality", "download", "bitrate"], ["transcoding format", "transcode", "format", "mp3", "aac", "opus"], ["download mode", "multithreaded", "threads", "single", "parallel"]]) {
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
            } header: {
                Text(s)
            } footer: {
                Text("Cellular quality applies when not on Wi-Fi. Transcoding format requires server support. Multithreaded downloads fetch several chunks in parallel for faster saves.")
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    // MARK: - Appearance

    @ViewBuilder
    private var appearanceSection: some View {
        let s = "Appearance"
        if sectionVisible(s, [["show lossless badge", "lossless", "badge"], ["dynamic player background", "dynamic", "background"], ["accent color", "accent", "color", "colour", "theme"]]) {
            Section(s) {
                if rowVisible(s, ["show lossless badge", "lossless", "badge"]) {
                    Toggle(isOn: $showLosslessBadge) {
                        Label("Show Lossless Badge", systemImage: "waveform.badge.plus")
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
                    Picker(selection: $accentColorName) {
                        ForEach(Theme.accentNames, id: \.self) { name in
                            Label {
                                Text(name.capitalized)
                            } icon: {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(Theme.accentColor(named: name))
                            }
                            .tag(name)
                        }
                    } label: {
                        Label("Accent Color", systemImage: "paintbrush")
                    }
                    .tint(Theme.accent)
                }
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    // MARK: - Library

    @ViewBuilder
    private var librarySection: some View {
        let s = "Library"
        if sectionVisible(s, [["album sort order", "sort", "order", "album"]]) {
            Section(s) {
                Picker(selection: $albumSortOrder) {
                    Text("A–Z").tag("alphabetical")
                    Text("Newest First").tag("newest")
                    Text("Most Played").tag("most_played")
                    Text("Year").tag("year")
                } label: {
                    Label("Album Sort Order", systemImage: "arrow.up.arrow.down")
                }
                .tint(Theme.accent)
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    // MARK: - Server

    @ViewBuilder
    private var serverSection: some View {
        let s = "Server"
        if sectionVisible(s, [["connected to", "server url", "username", "edit connection", "test connection", "log out", "logout", "sign out"]]) {
        Section(s) {
            if let server = appState.currentServer {
                LabeledContent("Connected to", value: server.displayName)
                    .foregroundStyle(Theme.primaryText)
                LabeledContent("Server URL", value: server.urlString)
                    .foregroundStyle(Theme.primaryText)
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
                    } catch {
                        connectionStatus = "✗ \(error.localizedDescription)"
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

            Button(role: .destructive) {
                showLogoutAlert = true
            } label: {
                Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
        .listRowBackground(Theme.secondaryBackground)
        }
    }

    // MARK: - Server Info

    @ViewBuilder
    private var serverInfoSection: some View {
        let s = "Server Info"
        if sectionVisible(s, [["library stats & speed test", "stats", "speed test", "library"]]) {
            Section {
                NavigationLink {
                    ServerInfoView()
                } label: {
                    Label("Library Stats & Speed Test", systemImage: "chart.bar")
                }
                .foregroundStyle(Theme.primaryText)
            } header: {
                Text(s)
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    // MARK: - Cache

    @ViewBuilder
    private var cacheSection: some View {
        let s = "Storage"
        if sectionVisible(s, [["downloaded tracks", "artwork cache", "app data", "total", "clear downloads", "clear artwork", "cache", "storage"]]) {
        Section {
            LabeledContent("Downloaded Tracks", value: downloadsSize)
                .foregroundStyle(Theme.primaryText)
            LabeledContent("Artwork Cache", value: artworkSize)
                .foregroundStyle(Theme.primaryText)
            LabeledContent("App Data", value: dataSize)
                .foregroundStyle(Theme.primaryText)
            LabeledContent("Total", value: totalCacheSize)
                .foregroundStyle(Theme.secondaryText)

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
        } header: {
            Text(s)
        } footer: {
            Text("Downloaded tracks are kept for offline play. Artwork and data caches speed up the app and rebuild automatically.")
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
            }
            if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                LabeledContent("Build", value: build)
                    .foregroundStyle(Theme.primaryText)
            }
        }
        .listRowBackground(Theme.secondaryBackground)
        }
    }

    // MARK: - Developer

    @ViewBuilder
    private var developerSection: some View {
        let s = "Developer"
        if sectionVisible(s, [["verbose logging", "logging", "export all logs", "clear all logs", "force refresh home", "logged play events", "queue length", "developer"]]) {
        Section {
            Toggle(isOn: $developerLogging) {
                Label("Verbose Logging", systemImage: "terminal")
            }
            .tint(Theme.accent)

            Button {
                exportLogs()
            } label: {
                Label("Export All Logs", systemImage: "square.and.arrow.up")
            }
            .foregroundStyle(Theme.primaryText)

            Button(role: .destructive) {
                showClearLogsAlert = true
            } label: {
                Label("Clear All Logs", systemImage: "trash")
            }

            Button {
                Task { await appState.homeViewModel.load(appState: appState, force: true) }
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
        } header: {
            Text(s)
        } footer: {
            Text("Verbose logging captures all network requests and playback events.")
        }
        .listRowBackground(Theme.secondaryBackground)
        }
    }

    // MARK: - Logs (always last)

    @ViewBuilder
    private var logsSection: some View {
        let s = "Diagnostics"
        if sectionVisible(s, [["logs", "diagnostics"]]) {
            Section {
                NavigationLink {
                    LogsView()
                } label: {
                    Label("Logs", systemImage: Symbols.logs)
                }
            } header: {
                Text(s)
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    // MARK: - Helpers

    private func refreshCacheSize() {
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            let docs    = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let caches  = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

            let downloads = SettingsView.directorySize(at: docs.appendingPathComponent("volta-downloads"))
            let artwork   = SettingsView.directorySize(at: caches.appendingPathComponent("artwork"))
                          + SettingsView.directorySize(at: caches.appendingPathComponent("api"))
            let data      = SettingsView.directorySize(at: support.appendingPathComponent("Volta"))
            let total     = downloads + artwork + data

            func fmt(_ n: Int) -> String {
                ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
            }
            await MainActor.run {
                downloadsSize  = fmt(downloads)
                artworkSize    = fmt(artwork)
                dataSize       = fmt(data)
                totalCacheSize = fmt(total)
            }
        }
    }

    private func clearArtworkCache() {
        Task {
            await ArtworkLoader.shared.clearCache()
            DiskCache.clear()
            AppLogger.shared.log("Artwork & data cache cleared by user", category: .other)
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

    private func exportLogs() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("volta-logs-\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        for cat in LogCategory.allCases {
            let text = AppLogger.shared.allFormatted(category: cat)
            let file = tmp.appendingPathComponent("\(cat.rawValue).txt")
            try? text.write(to: file, atomically: true, encoding: .utf8)
        }

        let vc = UIActivityViewController(activityItems: [tmp], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(vc, animated: true)
        }
    }

    private func clearDownloads() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir  = docs.appendingPathComponent("volta-downloads")
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        AppLogger.shared.log("Downloads cleared by user", category: .other)
        refreshCacheSize()
    }
}

// MARK: - Edit Connection View

struct EditConnectionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var serverURL: String = ""
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
        .preferredColorScheme(.dark)
        .onAppear { prefill() }
    }

    private func prefill() {
        guard let server = appState.currentServer else { return }
        serverURL = server.urlString
        username = server.username
    }

    private func saveConnection() {
        guard let url = SubsonicConfig.normalizedURL(from: serverURL) else {
            errorMessage = "Invalid server URL"
            return
        }
        let existingPassword = appState.store.config(for: appState.currentServer!)?.password ?? ""
        let pwd = password.isEmpty ? existingPassword : password
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
                    dismiss()
                }
            } catch {
                errorMessage = "Could not connect: \(error.localizedDescription)"
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
    @State private var isLoading = false
    @State private var speedTestResult: String? = nil
    @State private var isTesting = false
    @State private var speedGrade: String? = nil

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
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
        .preferredColorScheme(.dark)
        .task { await loadStats() }
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

struct LogsView: View {
    @State private var selected: LogCategory = .networking
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
        .preferredColorScheme(.dark)
        .onAppear { reload() }
        .onChange(of: selected) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .logEntryAdded)) { _ in reload() }
    }

    private func reload() {
        entries = AppLogger.shared.entries(for: selected)
    }
}

private struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // level pill
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
