import SwiftUI

extension SettingsView {
    // formatted current download-speed limit for the menu label
    var speedLimitLabel: String {
        guard downloadSpeedLimitKBps > 0 else { return "Unlimited" }
        let mb = Double(downloadSpeedLimitKBps) / 1024
        return mb >= 1 ? String(format: "%g MB/s", mb) : "\(downloadSpeedLimitKBps) KB/s"
    }

    // formatted current storage cap for the menu label
    var capLabel: String {
        guard downloadCapMB > 0 else { return "Unlimited" }
        let gb = Double(downloadCapMB) / 1024
        return gb >= 1 ? String(format: "%g GB", gb) : "\(downloadCapMB) MB"
    }

    // MARK: - Streaming

    @ViewBuilder
    var streamingSection: some View {
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
                        Label(L(.settings_wifi_quality), systemImage: "wifi")
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
                        Label(L(.settings_cellular_quality), systemImage: "antenna.radiowaves.left.and.right")
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
                        Label(L(.settings_download_quality), systemImage: "arrow.down.circle")
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
                        Label(L(.settings_transcoding_format), systemImage: "waveform.and.magnifyingglass")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["download mode", "multithreaded", "threads", "single", "parallel"]) {
                    Picker(selection: $downloadThreadingMode) {
                        Text("Multithreaded").tag("multi")
                        Text("Single Thread").tag("single")
                    } label: {
                        Label(L(.settings_download_mode), systemImage: "square.stack.3d.down.right")
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
                            Label(L(.settings_download_speed_limit), systemImage: "speedometer")
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
                            Label(L(.settings_download_storage_cap), systemImage: "internaldrive")
                        }
                    }
                    .tint(Theme.primaryText)
                }

                if rowVisible(s, ["auto-evict", "auto evict", "evict", "storage cap"]) {
                    Toggle(isOn: $autoEvictDownloads) {
                        Label(L(.settings_auto_evict), systemImage: "trash.circle")
                    }
                    .tint(Theme.accent)
                    .disabled(downloadCapMB == 0)
                }
            } header: {
                Text(sectionTitle(s))
            } footer: {
                Text("Cellular quality applies when not on Wi-Fi. Transcoding format requires server support. Multithreaded downloads fetch several chunks in parallel for faster saves.")
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    // MARK: - Cache

    @ViewBuilder
    var cacheSection: some View {
        let s = "Storage"
        if sectionVisible(s, [["downloaded tracks", "download missing songs", "download all missing", "download all music", "playback cache", "enhanced caching", "prefetch", "artwork cache", "local artwork library", "cover", "artist pictures", "lyrics cache", "local lyrics", "save lyrics", "app data", "total", "clear downloads", "clear playback cache", "clear artwork", "delete local artwork", "clear lyrics", "cache", "storage"], ["download local artwork library", "cover", "covers", "album artwork", "artist pictures", "local images"]]) {
        Section {
            LabeledContent("Downloaded Tracks", value: downloadsSize)
                .foregroundStyle(Theme.primaryText)
            LabeledContent("Playback Cache", value: playbackCacheSize)
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

            downloadAllMusicRow

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
                clearPlaybackCache()
            } label: {
                Label("Clear Playback Cache", systemImage: "bolt.horizontal.circle")
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
            Text(sectionTitle(s))
        } footer: {
            Text("Downloaded tracks and saved lyrics are kept for offline use. Artwork and data caches rebuild automatically.")
        }
        .listRowBackground(Theme.secondaryBackground)
        }
    }

    private var downloadAllMusicRow: some View {
        let progress = downloadService.bulkProgress
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label("Download Missing Songs", systemImage: "square.and.arrow.down.on.square")
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                if isCalculatingDownloadAll {
                    ProgressView().controlSize(.small).tint(Theme.accent)
                } else if progress.isRunning {
                    HStack(spacing: 14) {
                        Button {
                            if progress.isPaused {
                                downloadService.resumeBulkDownloads()
                            } else {
                                downloadService.pauseBulkDownloads()
                            }
                        } label: {
                            Image(systemName: progress.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(progress.isPaused ? "Resume downloads" : "Pause downloads")

                        Button(role: .destructive) {
                            downloadService.cancelBulkDownloads()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cancel downloads")
                    }
                } else {
                    Button {
                        calculateDownloadAll()
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

            if progress.isRunning {
                ProgressView(value: progress.fraction)
                    .tint(Theme.accent)
                HStack {
                    Text(downloadAllProgressText(progress))
                    Spacer(minLength: 12)
                    Text(downloadAllETAText(progress))
                }
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            } else {
                Text(downloadAllStatusText(progress))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.vertical, 4)
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
                Text(hasLocalArtworkLibrary ? "Local artwork ready: \(localArtworkSize)" : "Saves every album cover and artist photo for instant, offline image loading.")
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
                        if let client = appState.client {
                            let source = LyricsDownloadSource(rawValue: lyricsDownloadSource) ?? .lrclib
                            lyricsDownloader.start(client: client, source: source)
                        }
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

            Picker("Lyrics Source", selection: $lyricsDownloadSource) {
                ForEach(LyricsDownloadSource.allCases) { source in
                    Text(source.displayName).tag(source.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .disabled(lyricsDownloader.isRunning)

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

    // MARK: - Download missing songs

    func calculateDownloadAll() {
        guard !isCalculatingDownloadAll, let client = appState.client else { return }
        isCalculatingDownloadAll = true
        Task {
            defer { isCalculatingDownloadAll = false }
            let allAlbums = await loadAllAlbumsForArtwork(client: client)
            hiddenAlbums.register(albums: allAlbums)
            let albums = hiddenAlbums.visibleAlbums(allAlbums)
            let allSongs = await loadAllSongs(client: client, albums: albums)
            let pending = allSongs.filter { DownloadService.shared.state(for: $0) == .notDownloaded }
            let bytes = pending.reduce(0) { $0 + ($1.size ?? 0) }
            let free = SettingsView.availableCapacityBytes()

            downloadAllSongs = pending
            downloadAllBytes = bytes
            downloadAllCount = pending.count
            downloadAllFreeBytes = free

            if pending.isEmpty {
                VoltaNotificationCenter.shared.post(L(.notif_everything_downloaded), tone: .success)
            } else if bytes + 250_000_000 > free {   // keep ~250 MB headroom for the OS
                showDownloadAllNoSpace = true
            } else if hasConfirmedDownloadAllMissingSongs {
                startDownloadAll()
            } else {
                showDownloadAllConfirm = true
            }
        }
    }

    func startDownloadAll() {
        let songs = downloadAllSongs
        guard !songs.isEmpty else { return }
        hasConfirmedDownloadAllMissingSongs = true
        downloadService.startBulkDownloadMissing(songs)
        downloadAllSongs = []
    }

    private func downloadAllStatusText(_ progress: DownloadBulkProgress) -> String {
        if isCalculatingDownloadAll {
            return "Scanning your library…"
        }
        switch progress.phase {
        case .finished where progress.total > 0:
            return "Done · \(progress.completed) downloaded · \(progress.failed) failed · \(progress.skipped) skipped"
        case .cancelled where progress.total > 0:
            return "Stopped · \(progress.completed) downloaded · \(progress.remaining) left"
        default:
            return "Downloads only songs missing from this device. New library additions will be picked up next time."
        }
    }

    private func downloadAllProgressText(_ progress: DownloadBulkProgress) -> String {
        let done = progress.completed + progress.failed + progress.skipped
        var pieces = ["\(done)/\(progress.total) done", "\(progress.remaining) left"]
        if progress.active > 0 { pieces.append("\(progress.active) active") }
        if progress.failed > 0 { pieces.append("\(progress.failed) failed") }
        return pieces.joined(separator: " · ")
    }

    private func downloadAllETAText(_ progress: DownloadBulkProgress) -> String {
        guard !progress.isPaused else { return "Paused" }
        guard let eta = progress.etaSeconds else { return "ETA calculating" }
        return "ETA \(SettingsView.formatDuration(seconds: Int(eta.rounded())))"
    }

    func loadAllSongs(client: any MusicService, albums: [Album]) async -> [Song] {
        var result: [Song] = []
        let batchSize = 8
        var index = 0
        while index < albums.count {
            let end = min(index + batchSize, albums.count)
            let batch = Array(albums[index..<end])
            let songBatches = await DeveloperExperiments.runConcurrently(batch, defaultMaxConcurrent: batchSize) { album in
                (try? await client.album(id: album.id))?.song ?? []
            }
            result.append(contentsOf: songBatches.flatMap { $0 })
            index = end
        }
        return result
    }

    nonisolated static func availableCapacityBytes() -> Int {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Int(values?.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    // MARK: - Local artwork library

    func downloadLocalArtworkLibrary() {
        guard !isPrefetchingArtwork, let client = appState.client else { return }
        isPrefetchingArtwork = true
        artworkPrefetchProgress = ArtworkPrefetchProgress(current: "Loading library…")

        Task {
            defer {
                isPrefetchingArtwork = false
                refreshCacheSize()
            }

            let albums: [Album]
            let artists: [Artist]
            if DeveloperExperiments.constrainedConcurrency(default: 2) == 1 {
                albums = await loadAllAlbumsForArtwork(client: client)
                artists = (try? await client.artists()) ?? []
            } else {
                async let albumsRequest = loadAllAlbumsForArtwork(client: client)
                async let artistsRequest = client.artists()
                albums = await albumsRequest
                artists = (try? await artistsRequest) ?? []
            }
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

    func loadAllAlbumsForArtwork(client: any MusicService) async -> [Album] {
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
    func persistArtistArtwork(_ artist: Artist, client: any MusicService) async -> Bool {
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

    func persistArtworkURLs(_ urls: [URL?], current: String) async {
        let batchSize = 8
        var index = 0
        while index < urls.count {
            let end = min(index + batchSize, urls.count)
            let batch = Array(urls[index..<end])
            let results = await DeveloperExperiments.runConcurrently(batch, defaultMaxConcurrent: batchSize) { url in
                await ArtworkLoader.shared.persist(url)
            }
            for ok in results {
                recordArtworkPrefetchStep(ok: ok, current: current)
            }
            index = end
        }
    }

    func recordArtworkPrefetchStep(ok: Bool, current: String) {
        artworkPrefetchProgress.completed += 1
        if !ok { artworkPrefetchProgress.failed += 1 }
        artworkPrefetchProgress.current = current
    }

    // MARK: - Cache management

    func refreshCacheSize() {
        Task {
            let sizes = await DeveloperExperiments.runSync(priority: .utility) {
                let fm = FileManager.default
                let docs    = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let caches  = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

                let downloads = SettingsView.directorySize(at: docs.appendingPathComponent("volta-downloads"))
                let artwork   = SettingsView.directorySize(at: caches.appendingPathComponent("artwork"))
                              + SettingsView.directorySize(at: caches.appendingPathComponent("api"))
                let data = SettingsView.directorySize(at: support.appendingPathComponent("Volta"))
                let playEvents = StatsStore.shared.storageSizeBytes()
                let logs = AppLogger.shared.estimatedSizeBytes()
                return (downloads: downloads, artwork: artwork, data: data, playEvents: playEvents, logs: logs)
            }
            let localArtwork = await ArtworkLoader.shared.pinnedArtworkSize()
            let lyrics = await LyricsService.shared.storageSizeBytes()
            let playback = PlaybackCacheService.shared.totalBytes()
            let total = sizes.downloads + playback + sizes.artwork + sizes.data + sizes.logs

            downloadsSize  = SettingsView.formatBytes(sizes.downloads)
            playbackCacheSize = SettingsView.formatBytes(playback)
            artworkSize    = SettingsView.formatBytes(sizes.artwork)
            localArtworkSize = SettingsView.formatBytes(localArtwork)
            lyricsSize = SettingsView.formatBytes(lyrics)
            localArtworkBytes = localArtwork
            localArtworkLibraryDownloaded = localArtwork > 0
            dataSize       = SettingsView.formatBytes(sizes.data)
            playEventsSize = SettingsView.formatBytes(sizes.playEvents)
            logsSize       = SettingsView.formatBytes(sizes.logs)
            totalCacheSize = SettingsView.formatBytes(total)
        }
    }

    func clearPlaybackCache() {
        PlaybackCacheService.shared.clear()
        VoltaNotificationCenter.shared.post("Playback cache cleared", tone: .success)
        refreshCacheSize()
    }

    func clearArtworkCache() {
        Task {
            await ArtworkLoader.shared.clearCache()
            DiskCache.clear()
            AppLogger.shared.log("Artwork & data cache cleared by user", category: .other)
            VoltaNotificationCenter.shared.post(L(.notif_artwork_cache_cleared), tone: .success)
            refreshCacheSize()
        }
    }

    func clearLocalArtworkLibrary() {
        Task {
            await ArtworkLoader.shared.clearPinnedArtwork()
            localArtworkLibraryDownloaded = false
            localArtworkBytes = 0
            AppLogger.shared.log("Local artwork library cleared by user", category: .other)
            VoltaNotificationCenter.shared.post(L(.notif_local_artwork_deleted), tone: .success)
            refreshCacheSize()
        }
    }

    func clearLocalLyrics() {
        Task {
            await LyricsService.shared.clearLocalLyrics()
            AppLogger.shared.log("Local lyrics cleared by user", category: .other)
            VoltaNotificationCenter.shared.post(L(.notif_local_lyrics_cleared), tone: .success)
            refreshCacheSize()
        }
    }

    nonisolated static func directorySize(at url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]) else { return 0 }
        return enumerator.compactMap { ($0 as? URL) }
            .compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
            .reduce(0, +)
    }

    nonisolated static func formatBytes(_ n: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }

    nonisolated static func formatDuration(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(secs)s" }
        return "\(secs)s"
    }

    func clearDownloads() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir  = docs.appendingPathComponent("volta-downloads")
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        AppLogger.shared.log("Downloads cleared by user", category: .other)
        VoltaNotificationCenter.shared.post(L(.notif_downloads_cleared), tone: .success)
        refreshCacheSize()
    }
}
