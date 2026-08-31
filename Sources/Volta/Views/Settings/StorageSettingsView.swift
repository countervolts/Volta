import SwiftUI

struct DeviceStorageCapacity: Sendable {
    let totalBytes: Int64
    let importantAvailableBytes: Int64

    var reserveBytes: Int64 { totalBytes / 20 }

    func allowsDownload(expectedBytes: Int) -> Bool {
        let expected = Int64(max(0, expectedBytes))
        guard totalBytes > 0, importantAvailableBytes >= reserveBytes else { return false }
        return expected <= importantAvailableBytes - reserveBytes
    }

    static func current() -> DeviceStorageCapacity {
        let root = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        let values = try? root.resourceValues(forKeys: keys)
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: root.path)
        let total = values?.volumeTotalCapacity.map(Int64.init)
            ?? (attributes?[.systemSize] as? NSNumber)?.int64Value
            ?? 0
        let available = values?.volumeAvailableCapacityForImportantUsage
            ?? values?.volumeAvailableCapacity.map(Int64.init)
            ?? (attributes?[.systemFreeSize] as? NSNumber)?.int64Value
            ?? 0
        return DeviceStorageCapacity(totalBytes: max(0, total), importantAvailableBytes: max(0, available))
    }
}

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

    var transcodeSummary: String {
        guard transcodingEnabled else { return "Off" }
        let scope = transcodingCellularOnly ? "Cellular Only · " : ""
        if TranscodingSettingsMode(rawValue: transcodingMode) == .advanced {
            let count = StreamingPreferences.decodeRuleTargets(transcodeFileTypeRules).count
            return count > 0 ? "\(scope)Advanced · \(count) Rules" : "\(scope)Advanced"
        }
        let target = transcodingFormat == "raw" ? "Automatic" : transcodingFormat.uppercased()
        return "\(scope)Simple · \(target)"
    }

    // MARK: - Streaming

    @ViewBuilder
    var streamingSection: some View {
        let s = "Streaming"
        if sectionVisible(s, [["wi-fi quality", "wifi", "streaming", "quality", "bitrate"], ["cellular quality", "cellular", "mobile", "data"], ["transcode", "transcoding", "codec", "file type", "rules", "format", "mp3", "aac", "opus", "flac", "alac"]]) {
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

                if rowVisible(s, ["transcode", "transcoding", "codec", "file type", "rules", "format", "mp3", "aac", "opus", "flac", "alac"]) {
                    SettingsDetailNavigationLink(.transcoding) {
                        LabeledContent {
                            Text(transcodeSummary).foregroundStyle(Theme.secondaryText)
                        } label: {
                            Label("Transcode", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .foregroundStyle(Theme.primaryText)
                }

            } header: {
                Text(sectionTitle(s))
            } footer: {
                Text("Cellular quality applies when not on Wi-Fi. Transcode targets require server support. Download controls now live in Download Manager.")
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    // MARK: - Cache

    @ViewBuilder
    var cacheSection: some View {
        let s = "Storage"
        if sectionVisible(s, [["download manager", "active downloads", "queued downloads", "downloaded tracks", "downloaded albums", "lyrics", "artwork", "playback cache", "enhanced caching", "prefetch", "artwork cache", "app data", "total", "clear playback cache", "clear artwork", "cache", "storage"]]) {
        Section {
            SettingsDetailNavigationLink(.downloadManager) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L(.download_manager_open))
                            .foregroundStyle(Theme.primaryText)
                        Text(L(.download_manager_open_detail))
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                } icon: {
                    Image(systemName: "arrow.down.circle")
                }
            }

            Picker("Download Location", selection: $selectedDownloadStorage) {
                Text("Private Storage").tag(DownloadStorageLocation.privateStorage)
                Text("Files App").tag(DownloadStorageLocation.filesApp)
            }
            .tint(Theme.accent)
            .disabled(storageManager.isMigrating)

            Text(selectedDownloadStorage.detail)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

            if storageManager.isMigrating {
                VStack(alignment: .leading, spacing: 7) {
                    ProgressView(value: storageManager.progress).tint(Theme.accent)
                    Text(storageManager.status)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            } else {
                Button("Transfer Downloaded Data") {
                    showStorageTransferMethod = true
                }
                .disabled(selectedDownloadStorage == storageManager.location || !storageManager.canMigrate)

                if let reason = storageManager.migrationBlockReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            Button("Open Volta Folder in Files") {
                FilesFolderBrowser.presentVoltaFolder()
            }
            .disabled(storageManager.isMigrating)

            LabeledContent("Downloaded Music", value: downloadsSize)
                .foregroundStyle(Theme.primaryText)
            LabeledContent("Playback Cache", value: playbackCacheSize)
                .foregroundStyle(Theme.primaryText)
            LabeledContent("Artwork Cache", value: artworkSize)
                .foregroundStyle(Theme.primaryText)
            LabeledContent("Live Artwork Cache", value: liveArtworkCacheSize)
                .foregroundStyle(Theme.primaryText)
            LabeledContent("Offline Artwork", value: localArtworkSize)
                .foregroundStyle(Theme.primaryText)
            LabeledContent("Downloaded Lyrics", value: lyricsSize)
                .foregroundStyle(Theme.primaryText)
            LabeledContent("Listening History", value: playEventsSize)
                .foregroundStyle(Theme.primaryText)
            LabeledContent("API/Data Cache", value: apiCacheSize)
                .foregroundStyle(Theme.primaryText)
            LabeledContent("Playlist/User Data", value: playlistDataSize)
                .foregroundStyle(Theme.primaryText)
            LabeledContent("Diagnostics", value: diagnosticsSize)
                .foregroundStyle(Theme.primaryText)
            LabeledContent("Other App Data", value: dataSize)
                .foregroundStyle(Theme.primaryText)
            LabeledContent("Total", value: totalCacheSize)
                .foregroundStyle(Theme.secondaryText)

            Button(role: .destructive) {
                clearPlaybackCache()
            } label: {
                Label("Clear Playback Cache", systemImage: "bolt.horizontal.circle")
            }
            Button(role: .destructive) {
                showClearArtworkAlert = true
            } label: {
                Label("Clear Artwork Cache", systemImage: "photo.stack")
            }
            Button(role: .destructive) {
                showClearLiveArtworkAlert = true
            } label: {
                Label("Clear Live Artwork Cache", systemImage: "sparkles.tv")
            }
            Button(role: .destructive) {
                showClearAPIDataAlert = true
            } label: {
                Label("Clear API/Data Cache", systemImage: "tray.and.arrow.down")
            }
            Button(role: .destructive) {
                showClearLocalArtworkAlert = true
            } label: {
                Label("Clear Offline Artwork", systemImage: "externaldrive.badge.xmark")
            }
            Button(role: .destructive) {
                showClearPlayEventsFirstAlert = true
            } label: {
                Label("Clear Logged Play Events", systemImage: "chart.bar.xaxis")
            }
        } header: {
            Text(sectionTitle(s))
        } footer: {
            Text("Private Storage stays inside Volta. Files App stores downloads in On My iPhone > Volta, where editing files can break offline playback. Cache clears never remove downloaded music.")
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
            let bytes = DownloadService.estimatedBulkBytes(pending)
            let capacity = DeviceStorageCapacity.current()
            let free = Int(clamping: capacity.importantAvailableBytes)

            downloadAllSongs = pending
            downloadAllBytes = bytes
            downloadAllCount = pending.count
            downloadAllFreeBytes = free

            if pending.isEmpty {
                VoltaNotificationCenter.shared.post(L(.notif_everything_downloaded), tone: .success)
            } else if !capacity.allowsDownload(expectedBytes: bytes) {
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
        Int(clamping: DeviceStorageCapacity.current().importantAvailableBytes)
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
            let serverID = appState.currentServer?.id
            let owner = "local-artwork-library:\(serverID ?? "legacy")"
            let coverIDs = Array(Set(albums.compactMap(\.coverArt))).sorted()
            let total = coverIDs.count + artists.count

            artworkPrefetchProgress = ArtworkPrefetchProgress(
                completed: 0,
                total: total,
                failed: 0,
                current: "Downloading album covers…"
            )

            await persistArtworkCovers(
                coverIDs,
                client: client,
                serverID: serverID,
                owner: owner,
                current: "Downloading album covers…"
            )

            if !artists.isEmpty {
                artworkPrefetchProgress.current = "Downloading artist photos…"
            }
            for artist in artists {
                let ok = await persistArtistArtwork(artist, client: client, serverID: serverID, owner: owner)
                recordArtworkPrefetchStep(ok: ok, current: "Downloading artist photos…")
            }

            artworkPrefetchProgress.current = "Finished"
            localArtworkLibraryDownloaded = artworkPrefetchProgress.total > 0
                && artworkPrefetchProgress.completed == artworkPrefetchProgress.total
                && artworkPrefetchProgress.failed == 0
            AppLogger.shared.log(
                "Local artwork library downloaded: \(artworkPrefetchProgress.completed) items, \(artworkPrefetchProgress.failed) failed",
                category: .artwork
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
    func persistArtistArtwork(
        _ artist: Artist,
        client: any MusicService,
        serverID: String?,
        owner: String
    ) async -> Bool {
        if await ArtworkLoader.shared.retainOwnership(
            lookupID: ArtworkLoader.artistLookupID(artist.id, serverID: serverID),
            owner: owner
        ) {
            return true
        }
        if let directURL = artist.artistImageUrl.flatMap(URL.init(string:)),
           await ArtworkLoader.shared.persistArtistImage(id: artist.id, from: directURL, serverID: serverID, owner: owner) {
            return true
        }
        if let info = try? await client.artistInfo(id: artist.id),
           let urlString = info.bestImageUrl,
           let url = URL(string: urlString),
           await ArtworkLoader.shared.persistArtistImage(id: artist.id, from: url, serverID: serverID, owner: owner) {
            return true
        }
        if let fallbackURL = client.coverArtURL(id: artist.coverArt, size: 600) {
            return await ArtworkLoader.shared.persistArtistImage(id: artist.id, from: fallbackURL, serverID: serverID, owner: owner)
        }
        return false
    }

    func persistArtworkCovers(
        _ coverIDs: [String],
        client: any MusicService,
        serverID: String?,
        owner: String,
        current: String
    ) async {
        let batchSize = 8
        var index = 0
        while index < coverIDs.count {
            let end = min(index + batchSize, coverIDs.count)
            let batch = Array(coverIDs[index..<end])
            let results = await DeveloperExperiments.runConcurrently(batch, defaultMaxConcurrent: batchSize) { coverID in
                let url = client.coverArtURL(id: coverID, size: 1024) ?? client.coverArtURL(id: coverID)
                return await ArtworkLoader.shared.persist(
                    url,
                    label: coverID,
                    kind: "Album Cover",
                    groupID: "server:\(serverID ?? "legacy")|album-cover:\(coverID)",
                    lookupID: ArtworkLoader.coverArtLookupID(coverID, serverID: serverID),
                    owner: owner
                )
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

    var storageTransferMessage: String {
        let destination = selectedDownloadStorage == .filesApp
            ? "On My iPhone > Volta"
            : "Volta private storage"
        return "Music, artwork, and lyrics will transfer to \(destination). Do not edit Volta files while this runs."
    }

    func transferDownloadedData(method: DownloadStorageTransferMethod) {
        storageManager.migrate(to: selectedDownloadStorage, method: method)
    }

    func refreshCacheSize() {
        Task {
            let sizes = await DeveloperExperiments.runSync(priority: .utility) {
                let fm = FileManager.default
                let caches  = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                let volta = support.appendingPathComponent("Volta", isDirectory: true)
                let location = DownloadStorageLocation.current
                let offline = SettingsView.directorySize(at: location.artworkDirectory())
                    + SettingsView.fileSize(at: volta.appendingPathComponent("OfflineArtworkCatalog.json"))
                let lyrics = SettingsView.directorySize(at: location.lyricsDirectory())
                let downloads = SettingsView.directorySize(at: location.musicDirectory())
                let history = SettingsView.fileSize(at: volta.appendingPathComponent("play_events.json"))
                    + SettingsView.fileSize(at: volta.appendingPathComponent("play_events_fake.json"))
                let playlists = SettingsView.directorySize(at: volta.appendingPathComponent("PlaylistCovers", isDirectory: true))
                    + SettingsView.directorySize(at: volta.appendingPathComponent("PlaylistBackups", isDirectory: true))
                let voltaTotal = SettingsView.directorySize(at: volta)
                let privateArtworkCatalog = SettingsView.fileSize(at: volta.appendingPathComponent("OfflineArtworkCatalog.json"))
                let activeBytesInsidePrivateStorage = location == .privateStorage
                    ? downloads + SettingsView.directorySize(at: location.artworkDirectory()) + lyrics
                    : 0
                let otherAppData = max(0, voltaTotal - privateArtworkCatalog - activeBytesInsidePrivateStorage - history - playlists)

                return (
                    downloads: downloads,
                    playback: SettingsView.directorySize(at: caches.appendingPathComponent("playback-cache", isDirectory: true)),
                    artwork: SettingsView.directorySize(at: caches.appendingPathComponent("artwork", isDirectory: true)),
                    liveArtwork: SettingsView.directorySize(at: caches.appendingPathComponent("live-artwork", isDirectory: true)),
                    api: SettingsView.directorySize(at: caches.appendingPathComponent("api", isDirectory: true)),
                    offline: offline,
                    lyrics: lyrics,
                    history: history,
                    playlists: playlists,
                    diagnostics: SettingsView.directorySize(at: support.appendingPathComponent("ReliabilityReports", isDirectory: true)),
                    otherAppData: otherAppData
                )
            }
            let total = sizes.downloads + sizes.playback + sizes.artwork + sizes.liveArtwork
                + sizes.offline + sizes.lyrics + sizes.history + sizes.api + sizes.playlists
                + sizes.diagnostics + sizes.otherAppData

            downloadsSize = SettingsView.formatBytes(sizes.downloads)
            playbackCacheSize = SettingsView.formatBytes(sizes.playback)
            artworkSize    = SettingsView.formatBytes(sizes.artwork)
            liveArtworkCacheSize = SettingsView.formatBytes(sizes.liveArtwork)
            apiCacheSize = SettingsView.formatBytes(sizes.api)
            localArtworkSize = SettingsView.formatBytes(sizes.offline)
            lyricsSize = SettingsView.formatBytes(sizes.lyrics)
            localArtworkBytes = sizes.offline
            localArtworkLibraryDownloaded = await ArtworkLoader.shared.hasLocalArtworkLibrary(
                serverID: appState.currentServer?.id
            )
            dataSize = SettingsView.formatBytes(sizes.otherAppData)
            playlistDataSize = SettingsView.formatBytes(sizes.playlists)
            diagnosticsSize = SettingsView.formatBytes(sizes.diagnostics)
            playEventsSize = SettingsView.formatBytes(sizes.history)
            logsSize = "Not stored on disk"
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
            AppLogger.shared.log("Artwork cache cleared by user", category: .artwork)
            VoltaNotificationCenter.shared.post(L(.notif_artwork_cache_cleared), tone: .success)
            refreshCacheSize()
        }
    }

    func clearLiveArtworkCache() {
        Task {
            await ArtworkLoader.shared.clearLiveCache()
            AppLogger.shared.log("Live artwork cache cleared by user", category: .artwork)
            refreshCacheSize()
        }
    }

    func clearAPIDataCache() {
        DiskCache.clear()
        AppLogger.shared.log("API data cache cleared by user", category: .networking)
        refreshCacheSize()
    }

    func clearLocalArtworkLibrary() {
        Task {
            await ArtworkLoader.shared.clearPinnedArtwork()
            localArtworkLibraryDownloaded = false
            localArtworkBytes = 0
            AppLogger.shared.log("Local artwork library cleared by user", category: .artwork)
            VoltaNotificationCenter.shared.post(L(.notif_local_artwork_deleted), tone: .success)
            refreshCacheSize()
        }
    }

    func clearLocalLyrics() {
        Task {
            await LyricsService.shared.clearLocalLyrics()
            AppLogger.shared.log("Local lyrics cleared by user", category: .lyrics)
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
        downloadService.removeAllDownloads()
        AppLogger.shared.log("Downloads cleared by user", category: .downloads)
        VoltaNotificationCenter.shared.post(L(.notif_downloads_cleared), tone: .success)
        refreshCacheSize()
    }
}
