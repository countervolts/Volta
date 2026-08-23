import SwiftUI

struct DownloadManagerView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var downloadService = DownloadService.shared
    @StateObject private var lyricsDownloader = LyricsBulkDownloader.shared
    @StateObject private var artworkDownloader = ArtworkLibraryDownloader.shared

    @AppStorage(DownloadService.concurrentDownloadLimitKey) private var concurrentDownloads = 2
    @AppStorage("downloadBitrate") private var downloadBitrate = 0
    @AppStorage("downloadSpeedLimitKBps") private var downloadSpeedLimitKBps = 0
    @AppStorage("downloadCapMB") private var downloadCapMB = 0
    @AppStorage("autoEvictDownloads") private var autoEvictDownloads = false
    @AppStorage("saveLyricsLocally") private var saveLyricsLocally = true
    @AppStorage(LyricsBulkDownloader.downloadWithSongsKey) private var downloadLyricsWithSongs = false
    @AppStorage("lyricsDownloadSource") private var lyricsDownloadSource = LyricsDownloadSource.lrclib.rawValue
    @AppStorage("hasConfirmedDownloadAllMissingSongs") private var hasConfirmedDownloadAllMissingSongs = false

    @State private var catalog = DownloadCatalogSummary()
    @State private var catalogRevision = 0
    @State private var catalogCalculating: Set<DownloadCatalogComponent> = []
    @State private var isCalculatingMissingSongs = false
    @State private var pendingMissingSongs: [Song] = []
    @State private var pendingMissingBytes = 0
    @State private var availableBytes = 0
    @State private var showMissingSongsConfirmation = false
    @State private var showInsufficientStorage = false
    @State private var showCustomSpeed = false
    @State private var showCustomCap = false
    @State private var customSpeedText = ""
    @State private var customCapText = ""

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                transferOverview
                activeTransfers
                companionLyricsTransfers
                downloadedLibrary
                libraryDownloads
                downloadControls
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle(L(.download_manager_title))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .background(SwipeBackEnabler())
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
        }
        .preferredColorScheme(Theme.colorScheme)
        .onAppear {
            let resolved = min(8, max(1, concurrentDownloads))
            if concurrentDownloads != resolved { concurrentDownloads = resolved }
            downloadService.setConcurrentDownloadLimit(resolved)
        }
        .onChangeCompat(of: concurrentDownloads) { _, value in
            downloadService.setConcurrentDownloadLimit(value)
        }
        .task(id: catalogKey) { await reloadCatalog() }
        .alert("Download Missing Songs", isPresented: $showMissingSongsConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Download") { startMissingSongDownloads() }
        } message: {
            Text("Download \(pendingMissingSongs.count) songs (about \(downloadByteString(Int64(pendingMissingBytes))))? Active and queued songs will appear above.")
        }
        .alert("Not Enough Storage", isPresented: $showInsufficientStorage) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("These songs need about \(downloadByteString(Int64(pendingMissingBytes))). This device has \(downloadByteString(Int64(availableBytes))) available.")
        }
        .alert("Custom Speed Limit", isPresented: $showCustomSpeed) {
            TextField("MB/s", text: $customSpeedText).keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) {}
            Button("Set") {
                if let value = Double(customSpeedText), value >= 0 {
                    downloadSpeedLimitKBps = Int((value * 1024).rounded())
                }
            }
        } message: {
            Text("Enter 0 for unlimited, or a maximum speed in MB/s.")
        }
        .alert("Custom Storage Cap", isPresented: $showCustomCap) {
            TextField("GB", text: $customCapText).keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) {}
            Button("Set") {
                if let value = Double(customCapText), value >= 0 {
                    downloadCapMB = Int((value * 1024).rounded())
                }
            }
        } message: {
            Text("Enter 0 for unlimited, or a maximum size in GB.")
        }
    }

    private var catalogKey: DownloadCatalogKey {
        DownloadCatalogKey(
            downloadedRevision: downloadService.downloadedRevision,
            hasActiveLibraryDownloads: isLibraryDownloadRunning,
            lyricsRunning: lyricsDownloader.isRunning,
            lyricsRevision: lyricsDownloader.revision,
            artworkRevision: artworkDownloader.revision,
            localRevision: catalogRevision
        )
    }

    @ViewBuilder
    private var companionLyricsTransfers: some View {
        if !lyricsDownloader.companionTransfers.isEmpty {
            Section("Lyrics with Songs") {
                ForEach(lyricsDownloader.companionTransfers) { transfer in
                    CompanionLyricsTransferRow(transfer: transfer)
                }
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    private var transferOverview: some View {
        let summary = downloadService.transferSummary
        return Section {
            if summary.itemCount == 0 {
                Text(L(.download_manager_no_transfers))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(L(.download_manager_total)).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(L(.download_manager_transfer_count, summary.itemCount))
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    if summary.totalBytes > 0 {
                        ProgressView(value: summary.fraction).tint(Theme.accent)
                    } else {
                        ProgressView().tint(Theme.accent)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(totalByteLine(summary))
                        Spacer(minLength: 8)
                        Text(downloadSpeedString(summary.bytesPerSecond))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                    HStack(spacing: 8) {
                        Text(summaryStateLine(summary))
                        Spacer(minLength: 8)
                        if let eta = summary.etaSeconds {
                            Text(L(.download_manager_eta, downloadDurationString(eta)))
                        }
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                }
                .padding(.vertical, 3)
            }
        } header: {
            Text("Transfers")
        }
        .listRowBackground(Theme.secondaryBackground)
    }

    @ViewBuilder
    private var activeTransfers: some View {
        if !downloadService.transfers.isEmpty {
            Section(L(.download_manager_active)) {
                ForEach(downloadService.transfers) { transfer in
                    DownloadTransferRow(transfer: transfer)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                downloadService.cancelDownload(for: transfer.song)
                            } label: {
                                Label(L(.action_cancel), systemImage: "xmark")
                            }
                        }
                }
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    private var downloadedLibrary: some View {
        Section {
            NavigationLink {
                DownloadedAlbumsManagerView(onStorageChanged: storageDidChange)
            } label: {
                DownloadLibraryRow(
                    title: "Downloaded Albums",
                    icon: "square.stack",
                    count: catalog.albumCount,
                    bytes: catalog.songBytes,
                    isCalculating: catalogCalculating.contains(.songs)
                )
            }
            NavigationLink {
                DownloadedSongsManagerView(onStorageChanged: storageDidChange)
            } label: {
                DownloadLibraryRow(
                    title: "Downloaded Songs",
                    icon: "music.note",
                    count: catalog.songCount,
                    bytes: catalog.songBytes,
                    isCalculating: catalogCalculating.contains(.songs)
                )
            }
            NavigationLink {
                DownloadedLyricsManagerView(onStorageChanged: storageDidChange)
            } label: {
                DownloadLibraryRow(
                    title: "Downloaded Lyrics",
                    icon: Symbols.lyrics,
                    count: catalog.lyricsCount,
                    bytes: catalog.lyricsBytes,
                    isCalculating: catalogCalculating.contains(.lyrics)
                )
            }
            NavigationLink {
                DownloadedArtworkManagerView(category: .artwork, onStorageChanged: storageDidChange)
            } label: {
                DownloadLibraryRow(
                    title: "Downloaded Artwork",
                    icon: "photo.on.rectangle",
                    count: catalog.artworkCount,
                    bytes: catalog.artworkBytes,
                    isCalculating: catalogCalculating.contains(.artwork)
                )
            }
            NavigationLink {
                DownloadedArtworkManagerView(category: .artistPictures, onStorageChanged: storageDidChange)
            } label: {
                DownloadLibraryRow(
                    title: "Downloaded Artist Pictures",
                    icon: "person.crop.square",
                    count: catalog.artistPictureCount,
                    bytes: catalog.artistPictureBytes,
                    isCalculating: catalogCalculating.contains(.artwork)
                )
            }
        } header: {
            Text("On This Device")
        } footer: {
            if catalogCalculating.isEmpty {
                Text("\(catalog.totalCount) items · \(downloadByteString(catalog.totalBytes)) total")
            } else {
                Text("Calculating…")
            }
        }
        .listRowBackground(Theme.secondaryBackground)
    }

    private var libraryDownloads: some View {
        Section("Library Downloads") {
            missingSongsRow
            lyricsDownloadRow
            artworkDownloadRow
        }
        .listRowBackground(Theme.secondaryBackground)
    }

    private var downloadControls: some View {
        Section {
            Stepper(value: $concurrentDownloads, in: 1...8) {
                LabeledContent(L(.download_manager_concurrent)) {
                    Text("\(concurrentDownloads)")
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .tint(Theme.accent)

            Picker(selection: $downloadBitrate) {
                Text("Original").tag(0)
                Text("320 kbps").tag(320)
                Text("256 kbps").tag(256)
                Text("192 kbps").tag(192)
            } label: {
                Label(L(.settings_download_quality), systemImage: "waveform.badge.arrow.down")
            }
            .tint(Theme.accent)

            speedLimitMenu
            storageCapMenu

            Toggle(isOn: $autoEvictDownloads) {
                Label(L(.settings_auto_evict), systemImage: "trash.circle")
            }
            .tint(Theme.accent)
            .disabled(downloadCapMB == 0)

            Toggle(isOn: $saveLyricsLocally) {
                Label("Save Lyrics Locally", systemImage: Symbols.lyrics)
            }
            .tint(Theme.accent)

            Toggle(isOn: $downloadLyricsWithSongs) {
                Label("Download Lyrics with Songs", systemImage: "quote.bubble.fill")
            }
            .tint(Theme.accent)
        } header: {
            Text("Download Settings")
        } footer: {
            Text("Concurrency controls how many songs transfer at once. A storage cap only removes least-recently-played downloads when Auto-Evict is on.")
        }
        .listRowBackground(Theme.secondaryBackground)
    }

    private var speedLimitMenu: some View {
        Menu {
            Button("Unlimited") { downloadSpeedLimitKBps = 0 }
            ForEach([1, 2, 5, 10, 20, 50, 100], id: \.self) { mb in
                Button("\(mb) MB/s") { downloadSpeedLimitKBps = mb * 1024 }
            }
            Divider()
            Button("Custom…") {
                customSpeedText = downloadSpeedLimitKBps > 0
                    ? String(format: "%g", Double(downloadSpeedLimitKBps) / 1024) : ""
                showCustomSpeed = true
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

    private var storageCapMenu: some View {
        Menu {
            Button("Unlimited") { downloadCapMB = 0 }
            ForEach([1, 2, 5, 10, 20, 50, 100], id: \.self) { gb in
                Button("\(gb) GB") { downloadCapMB = gb * 1024 }
            }
            Divider()
            Button("Custom…") {
                customCapText = downloadCapMB > 0
                    ? String(format: "%g", Double(downloadCapMB) / 1024) : ""
                showCustomCap = true
            }
        } label: {
            LabeledContent {
                Text(storageCapLabel).foregroundStyle(Theme.secondaryText)
            } label: {
                Label(L(.settings_download_storage_cap), systemImage: "internaldrive")
            }
        }
        .tint(Theme.primaryText)
    }

    private var missingSongsRow: some View {
        let progress = downloadService.bulkProgress
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                Label("Download Missing Songs", systemImage: "square.and.arrow.down.on.square")
                Spacer()
                if isCalculatingMissingSongs {
                    ProgressView().controlSize(.small).tint(Theme.accent)
                } else if progress.isRunning {
                    Button {
                        progress.isPaused ? downloadService.resumeBulkDownloads() : downloadService.pauseBulkDownloads()
                    } label: {
                        Image(systemName: progress.isPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    Button(role: .destructive) { downloadService.cancelBulkDownloads() } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("Download") { calculateMissingSongs() }
                        .font(.subheadline.weight(.semibold))
                        .disabled(appState.client == nil)
                }
            }
            if progress.isRunning {
                ProgressView(value: progress.fraction).tint(Theme.accent)
                HStack {
                    Text(missingSongsProgressText(progress))
                    Spacer()
                    Text(progress.isPaused ? "Paused" : progress.etaSeconds.map { "ETA \(downloadDurationString($0))" } ?? "ETA calculating")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
            } else {
                Text(missingSongsStatusText(progress))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.vertical, 4)
    }

    private var lyricsDownloadRow: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                Label("Download All Lyrics", systemImage: "quote.bubble")
                Spacer()
                if lyricsDownloader.isRunning {
                    Button("Stop", role: .destructive) { lyricsDownloader.cancel() }
                        .font(.subheadline.weight(.semibold))
                } else {
                    Button("Download") {
                        guard let client = appState.client else { return }
                        lyricsDownloader.start(client: client, source: LyricsDownloadSource(rawValue: lyricsDownloadSource) ?? .lrclib)
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(appState.client == nil)
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
                ProgressView(value: lyricsDownloader.fraction).tint(Theme.accent)
            }
            Text(lyricsDownloader.statusText)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 4)
    }

    private var artworkDownloadRow: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                Label("Download Artwork Library", systemImage: "photo.on.rectangle.angled")
                Spacer()
                if artworkDownloader.isRunning {
                    Button("Stop", role: .destructive) { artworkDownloader.cancel() }
                        .font(.subheadline.weight(.semibold))
                } else {
                    Button("Download") {
                        guard let client = appState.client else { return }
                        artworkDownloader.start(client: client)
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(appState.client == nil)
                }
            }
            if artworkDownloader.isRunning {
                if artworkDownloader.total > 0 {
                    ProgressView(value: artworkDownloader.fraction).tint(Theme.accent)
                } else {
                    ProgressView().tint(Theme.accent)
                }
            }
            Text(artworkDownloader.statusText)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 4)
    }

    private var speedLimitLabel: String {
        guard downloadSpeedLimitKBps > 0 else { return "Unlimited" }
        let mb = Double(downloadSpeedLimitKBps) / 1024
        return mb >= 1 ? String(format: "%g MB/s", mb) : "\(downloadSpeedLimitKBps) KB/s"
    }

    private var storageCapLabel: String {
        guard downloadCapMB > 0 else { return "Unlimited" }
        let gb = Double(downloadCapMB) / 1024
        return gb >= 1 ? String(format: "%g GB", gb) : "\(downloadCapMB) MB"
    }

    private func storageDidChange() {
        catalogRevision &+= 1
    }

    private func reloadCatalog() async {
        let showCalculation = !isLibraryDownloadRunning
        catalogCalculating = showCalculation ? Set(DownloadCatalogComponent.allCases) : []

        let downloads = downloadService
        await withTaskGroup(of: DownloadCatalogResult.self) { group in
            group.addTask {
                let songs = await downloads.downloadedItemsSnapshot()
                return await DownloadCatalogSummary.songResult(from: songs)
            }
            group.addTask {
                let lyrics = await LyricsService.shared.downloadedLyricsItems()
                return await DownloadCatalogSummary.lyricsResult(from: lyrics)
            }
            group.addTask {
                let artwork = await ArtworkLoader.shared.downloadedArtworkItems()
                return await DownloadCatalogSummary.artworkResult(from: artwork)
            }

            for await result in group {
                guard !Task.isCancelled else { return }
                catalog.apply(result)
                catalogCalculating.remove(result.component)
            }
        }
    }

    private var isLibraryDownloadRunning: Bool {
        !downloadService.transfers.isEmpty
            || downloadService.bulkProgress.isRunning
            || lyricsDownloader.isRunning
            || !lyricsDownloader.companionTransfers.isEmpty
            || artworkDownloader.isRunning
    }

    private func totalByteLine(_ summary: DownloadTransferSummary) -> String {
        let received = downloadByteString(summary.bytesReceived)
        guard summary.totalBytes > 0 else { return received }
        return "\(received) / \(downloadByteString(summary.totalBytes)) · \(downloadByteString(summary.bytesRemaining)) \(L(.download_manager_remaining))"
    }

    private func summaryStateLine(_ summary: DownloadTransferSummary) -> String {
        var parts: [String] = []
        if summary.activeCount > 0 { parts.append("\(summary.activeCount) \(L(.download_manager_downloading).lowercased())") }
        if summary.queuedCount > 0 { parts.append("\(summary.queuedCount) \(L(.download_manager_queued).lowercased())") }
        if summary.waitingCount > 0 { parts.append("\(summary.waitingCount) \(L(.download_manager_waiting).lowercased())") }
        return parts.joined(separator: " · ")
    }

    private func calculateMissingSongs() {
        guard !isCalculatingMissingSongs, let client = appState.client else { return }
        isCalculatingMissingSongs = true
        Task {
            defer { isCalculatingMissingSongs = false }
            let albums = await Self.loadAllAlbums(client: client)
            let songs = await Self.loadAllSongs(client: client, albums: albums)
            let unavailableIDs = Set(downloadService.downloadedSongs().map(\.id))
                .union(downloadService.transfers.map(\.id))
            let result = await DeveloperExperiments.runSync {
                let pending = songs.filter { !unavailableIDs.contains($0.id) }
                return (pending, pending.reduce(0) { $0 + ($1.size ?? 0) })
            }
            pendingMissingSongs = result.0
            pendingMissingBytes = result.1
            availableBytes = Self.availableCapacityBytes()

            if pendingMissingSongs.isEmpty {
                VoltaNotificationCenter.shared.post(L(.notif_everything_downloaded), tone: .success)
            } else if pendingMissingBytes + 250_000_000 > availableBytes {
                showInsufficientStorage = true
            } else if hasConfirmedDownloadAllMissingSongs {
                startMissingSongDownloads()
            } else {
                showMissingSongsConfirmation = true
            }
        }
    }

    private func startMissingSongDownloads() {
        guard !pendingMissingSongs.isEmpty else { return }
        hasConfirmedDownloadAllMissingSongs = true
        downloadService.startBulkDownloadMissing(pendingMissingSongs)
        pendingMissingSongs = []
    }

    private func missingSongsStatusText(_ progress: DownloadBulkProgress) -> String {
        switch progress.phase {
        case .finished where progress.total > 0:
            return "Done · \(progress.completed) downloaded · \(progress.failed) failed · \(progress.skipped) skipped"
        case .cancelled where progress.total > 0:
            return "Stopped · \(progress.completed) downloaded · \(progress.remaining) left"
        default:
            return "Scans the library and queues only songs not already saved or transferring."
        }
    }

    private func missingSongsProgressText(_ progress: DownloadBulkProgress) -> String {
        let finished = progress.completed + progress.failed + progress.skipped
        return "\(finished)/\(progress.total) done · \(progress.remaining) left · \(progress.active) active"
    }

    private nonisolated static func loadAllAlbums(client: any MusicService) async -> [Album] {
        var albums: [Album] = []
        var offset = 0
        while true {
            let page = (try? await client.allAlbums(size: 500, offset: offset)) ?? []
            albums.append(contentsOf: page)
            if page.count < 500 || offset > 50_000 || Task.isCancelled { break }
            offset += 500
        }
        return albums
    }

    private nonisolated static func loadAllSongs(client: any MusicService, albums: [Album]) async -> [Song] {
        var songs: [Song] = []
        var index = 0
        let batchSize = 8
        while index < albums.count {
            if Task.isCancelled { break }
            let batch = Array(albums[index..<min(index + batchSize, albums.count)])
            let values = await DeveloperExperiments.runConcurrently(batch, defaultMaxConcurrent: batchSize) { album in
                (try? await client.album(id: album.id))?.song ?? album.song ?? []
            }
            songs.append(contentsOf: values.flatMap { $0 })
            index += batchSize
        }
        let collectedSongs = songs
        return await DeveloperExperiments.runSync {
            var seen = Set<String>()
            return collectedSongs.filter { seen.insert($0.id).inserted }
        }
    }

    private nonisolated static func availableCapacityBytes() -> Int {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Int(values?.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}

private struct DownloadCatalogKey: Hashable {
    let downloadedRevision: Int
    let hasActiveLibraryDownloads: Bool
    let lyricsRunning: Bool
    let lyricsRevision: Int
    let artworkRevision: Int
    let localRevision: Int
}

enum DownloadCatalogComponent: CaseIterable, Hashable, Sendable {
    case songs
    case lyrics
    case artwork
}

enum DownloadCatalogResult: Sendable {
    case songs(songCount: Int, albumCount: Int, bytes: Int64)
    case lyrics(count: Int, bytes: Int64)
    case artwork(artworkCount: Int, artistPictureCount: Int, artworkBytes: Int64, artistPictureBytes: Int64)

    var component: DownloadCatalogComponent {
        switch self {
        case .songs: return .songs
        case .lyrics: return .lyrics
        case .artwork: return .artwork
        }
    }
}

private struct CompanionLyricsTransferRow: View {
    let transfer: CompanionLyricsTransfer

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: Symbols.lyrics)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(transfer.song.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text("\(transfer.song.artist ?? transfer.song.album ?? "") · \(transfer.source.displayName)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            switch transfer.phase {
            case .queued, .downloading:
                ProgressView().controlSize(.small).tint(Theme.accent)
            case .saved:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .unavailable:
                Image(systemName: "minus.circle.fill").foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.vertical, 3)
    }

    private var statusText: String {
        switch transfer.phase {
        case .queued: return "Lyrics queued"
        case .downloading: return "Downloading lyrics…"
        case .saved: return "Lyrics saved"
        case .unavailable: return "No lyrics found"
        }
    }
}

struct DownloadCatalogSummary: Sendable {
    var songCount = 0
    var albumCount = 0
    var lyricsCount = 0
    var artworkCount = 0
    var artistPictureCount = 0
    var songBytes: Int64 = 0
    var lyricsBytes: Int64 = 0
    var artworkBytes: Int64 = 0
    var artistPictureBytes: Int64 = 0

    var totalCount: Int { songCount + lyricsCount + artworkCount + artistPictureCount }
    var totalBytes: Int64 { songBytes + lyricsBytes + artworkBytes + artistPictureBytes }

    static func songResult(from songs: [DownloadedTrackItem]) async -> DownloadCatalogResult {
        await DeveloperExperiments.runSync {
            let albums = Set(songs.map { DownloadedAlbumItem.groupingID(for: $0) })
            return .songs(
                songCount: songs.count,
                albumCount: albums.count,
                bytes: songs.reduce(0) { $0 + $1.bytes }
            )
        }
    }

    static func lyricsResult(from lyrics: [DownloadedLyricsItem]) async -> DownloadCatalogResult {
        await DeveloperExperiments.runSync {
            .lyrics(
                count: lyrics.count,
                bytes: lyrics.reduce(0) { $0 + $1.bytes }
            )
        }
    }

    static func artworkResult(from artwork: [DownloadedArtworkItem]) async -> DownloadCatalogResult {
        await DeveloperExperiments.runSync {
            let artistPictures = artwork.filter { $0.kind == "Artist Photo" }
            let albumArtwork = artwork.filter { $0.kind != "Artist Photo" }
            return .artwork(
                artworkCount: albumArtwork.count,
                artistPictureCount: artistPictures.count,
                artworkBytes: albumArtwork.reduce(0) { $0 + $1.bytes },
                artistPictureBytes: artistPictures.reduce(0) { $0 + $1.bytes }
            )
        }
    }

    mutating func apply(_ result: DownloadCatalogResult) {
        switch result {
        case let .songs(songCount, albumCount, bytes):
            self.songCount = songCount
            self.albumCount = albumCount
            self.songBytes = bytes
        case let .lyrics(count, bytes):
            lyricsCount = count
            lyricsBytes = bytes
        case let .artwork(artworkCount, artistPictureCount, artworkBytes, artistPictureBytes):
            self.artworkCount = artworkCount
            self.artistPictureCount = artistPictureCount
            self.artworkBytes = artworkBytes
            self.artistPictureBytes = artistPictureBytes
        }
    }
}

private struct DownloadLibraryRow: View {
    let title: String
    let icon: String
    let count: Int
    let bytes: Int64
    let isCalculating: Bool

    var body: some View {
        Label {
            LabeledContent(title) {
                Text(isCalculating ? "Calculating…" : "\(count) · \(downloadByteString(bytes))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(Theme.accent)
        }
    }
}

struct DownloadTransferRow: View {
    let transfer: DownloadTransfer

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ArtworkView(coverArtID: transfer.song.coverArt, size: 100, cornerRadius: 8)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 5) {
                Text(transfer.song.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text(transfer.song.artist ?? transfer.song.album ?? "")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                if transfer.totalBytes != nil {
                    ProgressView(value: transfer.fraction).tint(Theme.accent)
                } else {
                    ProgressView().tint(Theme.accent)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(phaseAndBytes)
                    Spacer(minLength: 8)
                    if transfer.phase == .downloading {
                        Text(downloadSpeedString(transfer.bytesPerSecond))
                    }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
                if transfer.phase == .downloading, let remaining = transfer.remainingBytes {
                    HStack(spacing: 8) {
                        Text("\(downloadByteString(remaining)) \(L(.download_manager_remaining))")
                        Spacer(minLength: 8)
                        if let eta = transfer.etaSeconds {
                            Text(L(.download_manager_eta, downloadDurationString(eta)))
                        }
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var phaseAndBytes: String {
        switch transfer.phase {
        case .queued: return L(.download_manager_queued)
        case .waitingForNetwork: return L(.download_manager_waiting)
        case .downloading:
            let received = downloadByteString(transfer.bytesReceived)
            return transfer.totalBytes.map { "\(received) / \(downloadByteString($0))" } ?? received
        }
    }
}

func downloadByteString(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
}

func downloadSpeedString(_ bytesPerSecond: Double) -> String {
    guard bytesPerSecond > 0 else { return "Calculating…" }
    let clamped = min(bytesPerSecond, Double(Int64.max))
    return "\(downloadByteString(Int64(clamped)))/s"
}

func downloadDurationString(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded()))
    if total >= 3_600 { return "\(total / 3_600)h \((total % 3_600) / 60)m" }
    if total >= 60 { return "\(total / 60)m \(total % 60)s" }
    return "\(total)s"
}
