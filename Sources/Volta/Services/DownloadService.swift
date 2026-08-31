import Foundation
import UIKit
import Combine

enum DownloadState: Equatable, Sendable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
}

enum DownloadBulkPhase: String, Equatable, Sendable {
    case idle
    case running
    case paused
    case finished
    case cancelled
}

struct DownloadBulkProgress: Equatable, Sendable {
    var phase: DownloadBulkPhase = .idle
    var total = 0
    var completed = 0
    var failed = 0
    var skipped = 0
    var active = 0
    var bytesTotal = 0
    var bytesFinished = 0
    var activeFraction = 0.0
    var startedAt: Date?
    var updatedAt = Date()

    var isRunning: Bool { phase == .running || phase == .paused }
    var isPaused: Bool { phase == .paused }
    var remaining: Int { max(0, total - completed - failed - skipped) }

    var fraction: Double {
        guard total > 0 else { return 0 }
        let units = Double(completed + failed + skipped) + activeFraction
        return min(1, max(0, units / Double(total)))
    }

    var etaSeconds: TimeInterval? {
        guard isRunning,
              let startedAt,
              fraction > 0.01,
              fraction < 0.995 else { return nil }
        let elapsed = updatedAt.timeIntervalSince(startedAt)
        guard elapsed > 2 else { return nil }
        return max(0, elapsed * (1 - fraction) / fraction)
    }
}

enum DownloadTransferPhase: String, Equatable, Sendable {
    case queued
    case downloading
    case waitingForNetwork
}

struct DownloadTransfer: Identifiable, Equatable, Sendable {
    let id: String
    let song: Song
    var phase: DownloadTransferPhase
    var bytesReceived: Int64
    var totalBytes: Int64?
    var fallbackProgress: Double
    var bytesPerSecond: Double
    var updatedAt: Date

    var fraction: Double {
        if let totalBytes, totalBytes > 0 {
            return min(1, max(0, Double(bytesReceived) / Double(totalBytes)))
        }
        return min(1, max(0, fallbackProgress))
    }

    var remainingBytes: Int64? {
        guard let totalBytes else { return nil }
        return max(0, totalBytes - bytesReceived)
    }

    var etaSeconds: TimeInterval? {
        guard phase == .downloading,
              let remainingBytes,
              remainingBytes > 0,
              bytesPerSecond > 1_024 else { return nil }
        return Double(remainingBytes) / bytesPerSecond
    }
}

struct DownloadTransferSummary: Equatable, Sendable {
    var itemCount = 0
    var activeCount = 0
    var queuedCount = 0
    var waitingCount = 0
    var bytesReceived: Int64 = 0
    var totalBytes: Int64 = 0
    var bytesRemaining: Int64 = 0
    var bytesPerSecond = 0.0

    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(bytesReceived) / Double(totalBytes)))
    }

    var etaSeconds: TimeInterval? {
        guard bytesRemaining > 0, bytesPerSecond > 1_024 else { return nil }
        return Double(bytesRemaining) / bytesPerSecond
    }
}

struct DownloadedTrackItem: Identifiable, Equatable, Sendable {
    let id: String
    let song: Song?
    let fileName: String
    let bytes: Int64
    let downloadedAt: Date?
}

@MainActor
private final class DownloadItemState: ObservableObject {
    var state: DownloadState

    init(_ state: DownloadState) {
        self.state = state
    }
}

private actor ByteCounter {
    private let total: Int
    private var received = 0
    init(total: Int) { self.total = total }
    func add(_ n: Int) -> Double {
        received += n
        guard total > 0 else { return 0 }
        return min(1.0, Double(received) / Double(total))
    }
}

private enum SegmentError: Error { case rangeNotSupported, badResponse }

private struct DownloadProgressPublish: Sendable {
    let progress: Double
    let rawCallbacks: Int
    let uiPublishes: Int
    let activeDownloads: Int
}

private actor DownloadProgressThrottler {
    private struct Entry {
        var rawProgress = 0.0
        var lastPublished = 0.0
        var lastPublishedAt = Date.distantPast
        var rawCallbacks = 0
        var uiPublishes = 0
    }

    private var entries: [String: Entry] = [:]
    private var activeIDs: Set<String> = []
    private var closedIDs: Set<String> = []
    private let minInterval: TimeInterval = 0.15
    private let minDelta = 0.005

    func start(_ id: String) {
        closedIDs.remove(id)
        if entries[id] == nil {
            entries[id] = Entry(lastPublishedAt: .distantPast)
        }
        activeIDs.insert(id)
        AppLogger.shared.log("Download active count: \(activeIDs.count)", category: .downloads)
    }

    func record(_ id: String, progress rawProgress: Double, force: Bool = false) -> DownloadProgressPublish? {
        guard !closedIDs.contains(id) else { return nil }
        var entry = entries[id] ?? Entry()
        activeIDs.insert(id)

        entry.rawCallbacks += 1
        entry.rawProgress = min(1, max(0, rawProgress))

        let now = Date()
        let delta = abs(entry.rawProgress - entry.lastPublished)
        let elapsed = now.timeIntervalSince(entry.lastPublishedAt)
        let shouldPublish = force
            || entry.rawProgress >= 1
            || (delta >= minDelta && elapsed >= minInterval)

        if entry.rawCallbacks % 500 == 0 {
            AppLogger.shared.log(
                "Download progress callbacks: id=\(id), raw=\(entry.rawCallbacks), ui=\(entry.uiPublishes), active=\(activeIDs.count)",
                category: .downloads
            )
        }

        guard shouldPublish else {
            entries[id] = entry
            return nil
        }

        entry.lastPublished = entry.rawProgress
        entry.lastPublishedAt = now
        entry.uiPublishes += 1
        entries[id] = entry

        return DownloadProgressPublish(
            progress: entry.rawProgress,
            rawCallbacks: entry.rawCallbacks,
            uiPublishes: entry.uiPublishes,
            activeDownloads: activeIDs.count
        )
    }

    func finish(_ id: String) {
        let entry = entries.removeValue(forKey: id) ?? Entry()
        activeIDs.remove(id)
        if closedIDs.count > 2_000 {
            closedIDs.removeAll(keepingCapacity: true)
        }
        closedIDs.insert(id)
        AppLogger.shared.log(
            "Download progress finished: id=\(id), raw=\(entry.rawCallbacks), ui=\(entry.uiPublishes), active=\(activeIDs.count)",
            category: .downloads
        )
    }
}

private struct PendingDownloadResume {
    let song: Song
    let url: URL
    let dest: URL
    let manifestURL: URL
    let method: String
    let resumeData: Data?
    let token: UUID
    let serverID: String?
}

private struct QueuedDownload {
    let song: Song
    let url: URL
    let client: any MusicService
    let notifyOnCompletion: Bool
    let belongsToBulkDownload: Bool
    let serverID: String?
}

struct DownloadedArtworkSource: Sendable {
    let url: URL
    let serverID: String?
    let groupID: String
    let owner: String
}

private struct DownloadSpeedSample {
    var bytes: Int64
    var date: Date
    var smoothedBytesPerSecond: Double
}

@MainActor
final class DownloadService: ObservableObject {
    static let shared = DownloadService()
    static let concurrentDownloadLimitKey = "concurrentDownloadLimit"

    @Published private(set) var bulkProgress = DownloadBulkProgress()
    @Published private(set) var downloadedRevision = 0
    @Published private(set) var transfers: [DownloadTransfer] = []

    private var stateItems: [String: DownloadItemState] = [:]
    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    private var progressPollingTasks: [String: Task<Void, Never>] = [:]
    private var segmentTasks: [String: Task<Void, Never>] = [:]
    private var startTimes: [String: Date] = [:]
    private var pendingResumes: [String: PendingDownloadResume] = [:]
    private var queuedDownloads: [QueuedDownload] = []
    private var runningDownloadIDs: Set<String> = []
    private var transferItems: [String: DownloadTransfer] = [:]
    private var transferOrder: [String] = []
    private var speedSamples: [String: DownloadSpeedSample] = [:]
    private var mutedCompletionNotifications: Set<String> = []
    private var downloadTokens: [String: UUID] = [:]
    private var client: (any MusicService)?
    private var currentServerID: String?

    private var pinnedCovers: Set<String> = []
    private var pinnedArtists: Set<String> = []

    private var bulkSongsByID: [String: Song] = [:]
    private var bulkActiveIDs: Set<String> = []
    private var bulkCompletedCount = 0
    private var bulkFailedCount = 0
    private var bulkSkippedCount = 0
    private var bulkBytesFinished = 0
    private var bulkBytesTotal = 0
    private var bulkTotalCount = 0
    private var bulkStartedAt: Date?
    private var lastBulkSnapshotAt = Date.distantPast
    private var manifestWriter = DownloadManifestWriter()
    private var manifestSaveSequence = 0
    private var artworkAliasMigrationTask: Task<Void, Never>?

    private nonisolated static let progressThrottler = DownloadProgressThrottler()
    private nonisolated static let defaultMaxConcurrent = 2

    static let artworkSizes = [80, 100, 200, 300, 400, 600, 800]
    private static let canonicalArtworkPixelSize = 1024

    private var directory: URL
    private var manifestURL: URL

    init() {
        directory = DownloadStorageLocation.current.musicDirectory()
        manifestURL = directory.appendingPathComponent("manifest.json")
        // Versions before Files storage kept song bytes in Documents. Move that
        // legacy private location into Application Support once, before Files
        // sharing makes Documents user-visible.
        if UserDefaults.standard.object(forKey: DownloadStorageLocation.preferenceKey) == nil,
           DownloadStorageLocation.current == .privateStorage {
            let legacy = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("volta-downloads", isDirectory: true)
            try? DownloadStorageTransfer.transfer(from: legacy, to: directory, method: .move)
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        loadManifest()
        NetworkMonitor.shared.onConnectionChange { [weak self] conn in
            guard conn != .none else { return }
            self?.resumePendingDownloads()
        }
    }

    func updateClient(_ client: (any MusicService)?, serverID: String? = nil) {
        self.client = client
        if let serverID, !serverID.isEmpty {
            currentServerID = serverID
            UserDefaults.standard.set(serverID, forKey: "downloadArtworkServerID")
        } else if currentServerID == nil {
            currentServerID = UserDefaults.standard.string(forKey: "downloadArtworkServerID")
        }
        // Once a server is reachable, fill in metadata for any downloads we
        // recovered from disk (or migrated from a legacy manifest) so they
        // reappear in the Downloaded / offline lists.
        artworkAliasMigrationTask?.cancel()
        artworkAliasMigrationTask = nil
        if let client {
            reconcileDownloadedMetadata()
            migrateDownloadedArtworkAliases(using: client)
        }
    }

    /// Called only by DownloadStorageManager after all transfer activity stops.
    func migrateStorage(to location: DownloadStorageLocation, method: DownloadStorageTransferMethod) throws {
        let destination = location.musicDirectory()
        try DownloadStorageTransfer.transfer(from: directory, to: destination, method: method)
        directory = destination
        manifestURL = directory.appendingPathComponent("manifest.json")
        for id in manifest.keys {
            guard let oldPath = manifest[id]?.path else { continue }
            manifest[id]?.path = directory.appendingPathComponent(URL(fileURLWithPath: oldPath).lastPathComponent).path
        }
        downloadedSongsCache = nil
        downloadedRecentCache = nil
        downloadedRevision += 1
        saveManifest(to: manifestURL)
    }

    var concurrentDownloadLimit: Int {
        let saved = UserDefaults.standard.integer(forKey: Self.concurrentDownloadLimitKey)
        return min(8, max(1, saved == 0 ? Self.defaultMaxConcurrent : saved))
    }

    var transferSummary: DownloadTransferSummary {
        transfers.reduce(into: DownloadTransferSummary()) { summary, transfer in
            summary.itemCount += 1
            switch transfer.phase {
            case .queued: summary.queuedCount += 1
            case .downloading: summary.activeCount += 1
            case .waitingForNetwork: summary.waitingCount += 1
            }
            summary.bytesReceived += max(0, transfer.bytesReceived)
            if let total = transfer.totalBytes {
                summary.totalBytes += max(0, total)
                summary.bytesRemaining += max(0, total - transfer.bytesReceived)
            }
            summary.bytesPerSecond += max(0, transfer.bytesPerSecond)
        }
    }

    func setConcurrentDownloadLimit(_ limit: Int) {
        let clamped = min(8, max(1, limit))
        UserDefaults.standard.set(clamped, forKey: Self.concurrentDownloadLimitKey)
        AppLogger.shared.log("Download concurrency changed to \(clamped)", category: .downloads)
        pumpDownloads()
    }

    func state(for song: Song) -> DownloadState {
        state(forID: song.id)
    }

    private func state(forID id: String) -> DownloadState {
        stateItem(for: id).state
    }

    private func setState(_ state: DownloadState, forID id: String) {
        let item = stateItem(for: id)
        guard item.state != state else { return }
        objectWillChange.send()
        item.state = state
    }

    private func stateItem(for id: String) -> DownloadItemState {
        if let item = stateItems[id] { return item }
        let item = DownloadItemState(manifest[id] == nil ? .notDownloaded : .downloaded)
        stateItems[id] = item
        return item
    }

    private func beginDownloadToken(for songID: String) -> UUID {
        let token = UUID()
        downloadTokens[songID] = token
        return token
    }

    private func isCurrentDownload(_ songID: String, token: UUID) -> Bool {
        downloadTokens[songID] == token
    }

    private func clearDownloadToken(_ songID: String, token: UUID) {
        if downloadTokens[songID] == token {
            downloadTokens.removeValue(forKey: songID)
        }
    }

    func localURL(for song: Song) -> URL? {
        guard let rec = manifest[song.id] else { return nil }
        let url = URL(fileURLWithPath: rec.path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Finds one downloaded track that can supply an album's embedded cover
    /// when no separately pinned cover image is available offline.
    func localArtworkSource(forCoverArtID id: String?, serverID: String?) -> DownloadedArtworkSource? {
        guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { return nil }
        let matching = manifest.values.filter { record in
            guard let song = record.song else { return false }
            return Self.coverArtID(for: song) == id
        }
        guard let record = matching.first(where: { $0.serverID == serverID })
            ?? matching.first(where: { $0.serverID == nil }) else { return nil }
        let url = URL(fileURLWithPath: record.path)
        guard FileManager.default.fileExists(atPath: url.path), let song = record.song else { return nil }
        let groupID = Self.artworkGroupID(for: song, serverID: record.serverID)
        return DownloadedArtworkSource(
            url: url,
            serverID: record.serverID,
            groupID: groupID,
            owner: Self.coverArtworkOwner(groupID: groupID, serverID: record.serverID)
        )
    }

    func download(song: Song, notifyOnCompletion: Bool = true) {
        if pendingResumes[song.id] != nil {
            pumpDownloads()
            return
        }
        guard case .notDownloaded = state(for: song) else { return }
        guard transferItems[song.id] == nil else { return }
        guard let client, let streamURL = client.downloadURL(for: song) else { return }
        // Demo servers are stream-only; never save their content to the device.
        if DemoServers.isDemo(client.config.baseURL) {
            VoltaNotificationCenter.shared.post(L(.notif_demo_no_downloads), tone: .info)
            return
        }
        enqueueDownload(
            song: song,
            streamURL: streamURL,
            client: client,
            notifyOnCompletion: notifyOnCompletion,
            belongsToBulkDownload: false,
            serverID: currentServerID
        )
    }

    private func enqueueDownload(
        song: Song,
        streamURL: URL,
        client: any MusicService,
        notifyOnCompletion: Bool,
        belongsToBulkDownload: Bool,
        serverID: String?,
        pumpImmediately: Bool = true
    ) {
        guard transferItems[song.id] == nil else { return }
        queuedDownloads.append(QueuedDownload(
            song: song,
            url: streamURL,
            client: client,
            notifyOnCompletion: notifyOnCompletion,
            belongsToBulkDownload: belongsToBulkDownload,
            serverID: serverID
        ))
        setState(.downloading(progress: 0), forID: song.id)
        transferItems[song.id] = DownloadTransfer(
            id: song.id,
            song: song,
            phase: .queued,
            bytesReceived: 0,
            totalBytes: song.size.flatMap { $0 > 0 ? Int64($0) : nil },
            fallbackProgress: 0,
            bytesPerSecond: 0,
            updatedAt: .now
        )
        transferOrder.append(song.id)
        publishTransfers()
        if pumpImmediately { pumpDownloads() }
    }

    private func pumpDownloads() {
        guard NetworkMonitor.shared.connection != .none else { return }

        while runningDownloadIDs.count < concurrentDownloadLimit {
            if let resumeID = transferOrder.first(where: {
                pendingResumes[$0] != nil && !(bulkProgress.isPaused && bulkActiveIDs.contains($0))
            }), let pending = pendingResumes.removeValue(forKey: resumeID) {
                runningDownloadIDs.insert(resumeID)
                markTransferStarted(resumeID)
                AppLogger.shared.log("Download resuming: \(pending.song.title)", category: .downloads)
                startSingle(
                    song: pending.song,
                    url: pending.url,
                    dest: pending.dest,
                    manifestURL: pending.manifestURL,
                    method: pending.method,
                    resumeData: pending.resumeData,
                    token: pending.token,
                    serverID: pending.serverID
                )
                continue
            }

            guard let queueIndex = queuedDownloads.firstIndex(where: {
                !($0.belongsToBulkDownload && bulkProgress.isPaused)
            }) else { break }
            let request = queuedDownloads.remove(at: queueIndex)
            runningDownloadIDs.insert(request.song.id)
            startDownload(
                song: request.song,
                streamURL: request.url,
                client: request.client,
                notifyOnCompletion: request.notifyOnCompletion,
                serverID: request.serverID
            )
        }
        refreshBulkProgress(force: true)
    }

    private func markTransferStarted(_ songID: String) {
        guard var transfer = transferItems[songID] else { return }
        transfer.phase = .downloading
        transfer.updatedAt = .now
        transferItems[songID] = transfer
        speedSamples[songID] = DownloadSpeedSample(bytes: transfer.bytesReceived, date: .now, smoothedBytesPerSecond: 0)
        publishTransfers()
    }

    private func startDownload(song: Song, streamURL: URL, client: any MusicService, notifyOnCompletion: Bool, serverID: String?) {
        guard runningDownloadIDs.contains(song.id) else { return }

        let songID = song.id
        let token = beginDownloadToken(for: songID)
        markTransferStarted(songID)
        startTimes[songID] = Date()
        if notifyOnCompletion {
            mutedCompletionNotifications.remove(songID)
        } else {
            mutedCompletionNotifications.insert(songID)
        }
        Task { await Self.progressThrottler.start(songID) }
        prefetchArtwork(for: song, serverID: serverID)
        if UserDefaults.standard.bool(forKey: LyricsBulkDownloader.downloadWithSongsKey) {
            let sourceValue = UserDefaults.standard.string(forKey: "lyricsDownloadSource")
            let source = LyricsDownloadSource(rawValue: sourceValue ?? "") ?? .lrclib
            LyricsBulkDownloader.shared.enqueueCompanionLyrics(for: song, client: client, source: source)
        }

        let title    = song.title
        let progressiveDownload = client.downloadIsProgressive(for: song)
        let suffix   = Self.downloadFileSuffix(for: song, client: client)
        let total    = progressiveDownload ? 0 : (song.size ?? 0)
        let destURL  = directory.appendingPathComponent(Self.safeFileName(id: songID, suffix: suffix))
        let manifestURL = manifestURL
        let speedLimit = UserDefaults.standard.integer(forKey: "downloadSpeedLimitKBps") * 1024
        // File-level concurrency is controlled by the Download Manager. A
        // segmented transfer is only used internally when a speed cap needs
        // chunk-level throttling; otherwise each song owns one network task.
        let useSegmentedTransfer = !progressiveDownload
            && total > 0
            && !DeveloperExperiments.isAppWorkerSerialized
            && speedLimit > 0

        if useSegmentedTransfer {
            let segments = max(2, min(DeveloperExperiments.constrainedConcurrency(default: 6), total / (512 * 1024)))
            AppLogger.shared.log("Download starting: \(title) (\(segments) segments, \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file))\(speedLimit > 0 ? ", limited" : ""))", category: .downloads)
            let task = Task { [self] in
                do {
                    try await DownloadService.downloadSegmented(url: streamURL, title: title, total: total, dest: destURL, speedLimit: speedLimit) { progress in
                        if let publish = await Self.progressThrottler.record(songID, progress: progress) {
                            await MainActor.run {
                                self.publishProgress(songID, publish, completedBytes: nil, totalBytes: Int64(total))
                            }
                        }
                    }
                    complete(songID, song: song, path: destURL.path, manifestURL: manifestURL, method: "multithreaded", token: token, serverID: serverID)
                } catch is CancellationError {
                    guard isCurrentDownload(songID, token: token) else { return }
                    AppLogger.shared.log("Download cancelled: \(title)", category: .downloads)
                    fail(songID, removing: destURL, token: token)
                } catch {
                    guard isCurrentDownload(songID, token: token) else { return }
                    if DownloadService.isTransientNetworkError(error) {
                        pauseForResume(song: song, url: streamURL, dest: destURL, manifestURL: manifestURL, method: "single thread", resumeData: nil, token: token, serverID: serverID)
                    } else {
                        AppLogger.shared.log("Segmented download failed: \(title) (\(error.localizedDescription)); falling back to single", category: .downloads, level: .warning)
                        startSingle(song: song, url: streamURL, dest: destURL, manifestURL: manifestURL, token: token, serverID: serverID)
                    }
                }
            }
            segmentTasks[songID] = task
        } else if progressiveDownload {
            AppLogger.shared.log("Download starting: \(title) (\(Self.progressiveDownloadMethod), \(suffix))", category: .downloads)
            startSingle(song: song, url: streamURL, dest: destURL, manifestURL: manifestURL, method: Self.progressiveDownloadMethod, token: token, serverID: serverID)
        } else {
            AppLogger.shared.log("Download starting: \(title) (single thread\(total > 0 ? ", \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file))" : ""))", category: .downloads)
            startSingle(song: song, url: streamURL, dest: destURL, manifestURL: manifestURL, token: token, serverID: serverID)
        }
    }

    func cancelDownload(for song: Song) {
        cancelDownload(for: song, notify: true, updateBulk: true)
    }

    private func cancelDownload(for song: Song, notify: Bool, updateBulk: Bool) {
        AppLogger.shared.log("Download cancelled: \(song.title)", category: .downloads)
        if notify, case .downloading = state(for: song) {
            VoltaNotificationCenter.shared.post(L(.notif_download_cancelled), tone: .warning)
        }
        activeTasks[song.id]?.cancel()
        segmentTasks[song.id]?.cancel()
        activeTasks.removeValue(forKey: song.id)
        stopProgressPolling(song.id)
        segmentTasks.removeValue(forKey: song.id)
        queuedDownloads.removeAll { $0.song.id == song.id }
        runningDownloadIDs.remove(song.id)
        startTimes.removeValue(forKey: song.id)
        pendingResumes.removeValue(forKey: song.id)
        downloadTokens.removeValue(forKey: song.id)
        mutedCompletionNotifications.remove(song.id)
        LyricsBulkDownloader.shared.cancelCompanionLyrics(for: song.id)
        setState(.notDownloaded, forID: song.id)
        removeTransfer(song.id)
        Task { await Self.progressThrottler.finish(song.id) }
        if updateBulk {
            handleBulkSongFinished(song.id, success: false)
        }
        pumpDownloads()
    }

    func removeDownload(for song: Song) {
        removeDownload(id: song.id)
    }

    func removeDownload(id: String) {
        let record = manifest[id]
        let song = record?.song
        let title = song?.title ?? id
        AppLogger.shared.log("Download removed: \(title)", category: .downloads)
        VoltaNotificationCenter.shared.post(L(.notif_download_removed), tone: .info)
        if let song {
            cancelDownload(for: song)
        }
        if let rec = manifest[id] {
            try? FileManager.default.removeItem(atPath: rec.path)
        }
        manifest.removeValue(forKey: id)
        setState(.notDownloaded, forID: id)
        downloadedRevision += 1
        saveManifest(to: manifestURL)
        if let song { unpinOrphanedArtwork(after: song, serverID: record?.serverID) }
    }

    func removeDownloads(ids: [String]) {
        let uniqueIDs = Array(Set(ids))
        guard !uniqueIDs.isEmpty else { return }
        var removedSongs: [(song: Song, serverID: String?)] = []
        for id in uniqueIDs {
            let song = manifest[id]?.song
            if let song {
                cancelDownload(for: song, notify: false, updateBulk: false)
                removedSongs.append((song, manifest[id]?.serverID))
            }
            if let record = manifest[id] {
                try? FileManager.default.removeItem(atPath: record.path)
            }
            manifest.removeValue(forKey: id)
            setState(.notDownloaded, forID: id)
        }
        downloadedRevision += 1
        saveManifest(to: manifestURL)
        for removed in removedSongs { unpinOrphanedArtwork(after: removed.song, serverID: removed.serverID) }
        AppLogger.shared.log("Downloaded tracks removed: count=\(uniqueIDs.count)", category: .downloads)
        VoltaNotificationCenter.shared.post(L(.notif_download_removed), tone: .info)
    }

    private func unpinOrphanedArtwork(after song: Song, serverID: String?) {
        let remaining = manifest.values.filter { FileManager.default.fileExists(atPath: $0.path) }
        let artworkGroupID = Self.artworkGroupID(for: song, serverID: serverID)
        if let cover = Self.coverArtID(for: song), !remaining.contains(where: { record in
            guard record.serverID == serverID, let remainingSong = record.song else { return false }
            return Self.artworkGroupID(for: remainingSong, serverID: serverID) == artworkGroupID
        }) {
            pinnedCovers.remove(artworkGroupID)
            let owner = Self.coverArtworkOwner(groupID: artworkGroupID, serverID: serverID)
            let lookupIDs = [
                ArtworkLoader.coverArtLookupID(cover, serverID: serverID),
                ArtworkLoader.liveArtworkLookupID(cover, serverID: serverID)
            ]
            DeveloperExperiments.launch(priority: .utility) {
                await ArtworkLoader.shared.removeOwnership(lookupIDs: lookupIDs, owner: owner)
            }
        }
        if let artistId = song.primaryArtistID, !remaining.contains(where: { record in
            record.serverID == serverID && record.song?.primaryArtistID == artistId
        }) {
            pinnedArtists.remove(ArtworkLoader.artistLookupID(artistId, serverID: serverID))
            let owner = Self.artistArtworkOwner(artistID: artistId, serverID: serverID)
            let lookupID = ArtworkLoader.artistLookupID(artistId, serverID: serverID)
            DeveloperExperiments.launch(priority: .utility) {
                await ArtworkLoader.shared.removeOwnership(lookupID: lookupID, owner: owner)
            }
        }
    }

    // Never trust song ids as paths.
    private nonisolated static func safeFileName(id: String, suffix: String) -> String {
        func clean(_ s: String) -> String {
            s.replacingOccurrences(of: "/", with: "_")
             .replacingOccurrences(of: "\\", with: "_")
             .replacingOccurrences(of: "\0", with: "_")
        }
        return "\(clean(id)).\(clean(suffix))"
    }

    // Label for progressive, length-unknown downloads.
    private nonisolated static let progressiveDownloadMethod = "Plex transcode"

    private nonisolated static func downloadFileSuffix(for song: Song, client: any MusicService) -> String {
        // Progressive downloads use the transcode container extension.
        if client.downloadIsProgressive(for: song) {
            let decision = StreamingPreferences.downloadDecision(for: song)
            switch client.backendKind {
            case .plex:
                return StreamingPreferences.plexUniversalTranscodeExtension(for: decision.format)
            case .jellyfin, .emby:
                return decision.format == "aac" || decision.format == nil ? "m4a" : (decision.format ?? "m4a")
            case .subsonic:
                return decision.format ?? "mp3"
            }
        }
        return song.suffix ?? "mp3"
    }

    private nonisolated static func resumeData(from error: Error?) -> Data? {
        guard let error else { return nil }
        let ns = error as NSError
        return ns.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
    }

    private nonisolated static func isTransientNetworkError(_ error: Error?) -> Bool {
        guard let error else { return false }
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else { return false }
        switch URLError.Code(rawValue: ns.code) {
        case .networkConnectionLost, .notConnectedToInternet, .timedOut,
             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    // MARK: - Single-threaded transfer (also the multi fallback)

    private func startSingle(song: Song, url: URL, dest: URL, manifestURL: URL, token: UUID, serverID: String?) {
        startSingle(song: song, url: url, dest: dest, manifestURL: manifestURL, resumeData: nil, token: token, serverID: serverID)
    }

    private func startSingle(song: Song, url: URL, dest: URL, manifestURL: URL, method: String = "single thread", resumeData: Data? = nil, token: UUID, serverID: String?) {
        let songID = song.id
        let title = song.title
        let task: URLSessionDownloadTask
        let completion: @Sendable (URL?, URLResponse?, Error?) -> Void = { [weak self] tempURL, response, error in
            guard let self else { return }
            if let tempURL, error == nil {
                if let failure = DownloadService.downloadValidationFailure(tempURL: tempURL, response: response, method: method) {
                    try? FileManager.default.removeItem(at: tempURL)
                    Task { @MainActor in
                        guard self.isCurrentDownload(songID, token: token) else { return }
                        AppLogger.shared.log("Download rejected: \(title): \(failure)", category: .downloads, level: .error)
                        self.fail(songID, removing: dest, token: token)
                    }
                    return
                }

                try? FileManager.default.removeItem(at: dest)
                let moved = (try? FileManager.default.moveItem(at: tempURL, to: dest)) != nil
                Task { @MainActor in
                    guard self.isCurrentDownload(songID, token: token) else { return }
                    if moved {
                        self.complete(songID, song: song, path: dest.path, manifestURL: manifestURL, method: method, token: token, serverID: serverID)
                    } else {
                        AppLogger.shared.log("Download failed to save file: \(title)", category: .downloads, level: .error)
                        self.fail(songID, removing: dest, token: token)
                    }
                }
            } else {
                let msg = error?.localizedDescription ?? "unknown error"
                Task { @MainActor in
                    guard self.isCurrentDownload(songID, token: token) else { return }
                    let resumeData = DownloadService.resumeData(from: error)
                    if resumeData != nil || DownloadService.isTransientNetworkError(error) {
                        self.pauseForResume(song: song, url: url, dest: dest, manifestURL: manifestURL, method: method, resumeData: resumeData, token: token, serverID: serverID)
                    } else {
                        AppLogger.shared.log("Download failed: \(title): \(msg)", category: .downloads, level: .error)
                        self.fail(songID, removing: dest, token: token)
                    }
                }
            }
        }
        if let resumeData {
            task = URLSession.shared.downloadTask(withResumeData: resumeData, completionHandler: completion)
        } else {
            var req = URLRequest(url: url)
            // Plex's transcoder needs identity headers; others no-op.
            for (k, v) in client?.mediaRequestHeaders() ?? [:] {
                req.setValue(v, forHTTPHeaderField: k)
            }
            task = URLSession.shared.downloadTask(with: req, completionHandler: completion)
        }

        activeTasks[songID] = task
        task.resume()
        startProgressPolling(songID, task: task)
    }

    /// `URLSessionTask.progress` is sometimes a percentage-style `Progress`
    /// whose units are 0...100. Those values are not byte counts (and were the
    /// source of the persistent "5 bytes / 100 bytes" display). Poll the task's
    /// transfer counters instead; they are the actual network byte totals and
    /// also keep speed moving when a response has no known content length.
    private func startProgressPolling(_ songID: String, task: URLSessionDownloadTask) {
        stopProgressPolling(songID)
        progressPollingTasks[songID] = Task { @MainActor [weak self, weak task] in
            while !Task.isCancelled {
                guard let self, let task else { return }

                let completedBytes = max(0, task.countOfBytesReceived)
                let expectedCandidates = [
                    task.countOfBytesExpectedToReceive,
                    task.response?.expectedContentLength ?? NSURLSessionTransferSizeUnknown
                ]
                // A real audio payload cannot be 100 bytes. Reject the
                // percentage-unit placeholder while retaining metadata size as
                // the fallback for chunked/progressive responses.
                let responseTotal = expectedCandidates.first {
                    $0 > 1_024 && $0 >= completedBytes
                }
                let resolvedTotal = responseTotal ?? self.transferItems[songID]?.totalBytes
                let fraction = resolvedTotal.flatMap { total in
                    total > 0 ? min(1, Double(completedBytes) / Double(total)) : nil
                } ?? 0

                if let publish = await Self.progressThrottler.record(
                    songID,
                    progress: fraction,
                    force: true
                ) {
                    self.publishProgress(
                        songID,
                        publish,
                        completedBytes: completedBytes,
                        totalBytes: responseTotal
                    )
                }

                if task.state == .completed || task.state == .canceling { return }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func stopProgressPolling(_ songID: String) {
        progressPollingTasks.removeValue(forKey: songID)?.cancel()
    }

    private nonisolated static func downloadValidationFailure(
        tempURL: URL,
        response: URLResponse?,
        method: String
    ) -> String? {
        let bytes = fileSize(at: tempURL)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            return "HTTP \(http.statusCode)\(smallTextPreview(at: tempURL))"
        }

        if method == progressiveDownloadMethod, bytes < 1_024 {
            return "Plex returned only \(bytes) bytes\(smallTextPreview(at: tempURL))"
        }

        return nil
    }

    private nonisolated static func smallTextPreview(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url),
              !data.isEmpty,
              data.count <= 4_096,
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return "" }
        let oneLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return " (\(String(oneLine.prefix(180))))"
    }

    private nonisolated static func fileSize(at url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }

    private func pauseForResume(song: Song, url: URL, dest: URL, manifestURL: URL, resumeData: Data?, token: UUID, serverID: String?) {
        pauseForResume(song: song, url: url, dest: dest, manifestURL: manifestURL, method: "single thread", resumeData: resumeData, token: token, serverID: serverID)
    }

    private func pauseForResume(song: Song, url: URL, dest: URL, manifestURL: URL, method: String, resumeData: Data?, token: UUID, serverID: String?) {
        let songID = song.id
        guard isCurrentDownload(songID, token: token) else { return }
        activeTasks.removeValue(forKey: songID)
        stopProgressPolling(songID)
        segmentTasks.removeValue(forKey: songID)
        runningDownloadIDs.remove(songID)
        pendingResumes[songID] = PendingDownloadResume(
            song: song,
            url: url,
            dest: dest,
            manifestURL: manifestURL,
            method: method,
            resumeData: resumeData,
            token: token,
            serverID: serverID
        )
        let progress: Double
        if case .downloading(let current) = state(forID: songID) {
            progress = current
        } else {
            progress = 0
        }
        setState(.downloading(progress: progress), forID: songID)
        if var transfer = transferItems[songID] {
            transfer.phase = .waitingForNetwork
            transfer.bytesPerSecond = 0
            transfer.updatedAt = .now
            transferItems[songID] = transfer
            publishTransfers()
        }
        AppLogger.shared.log("Download paused: \(song.title); connection lost, will resume when network returns", category: .downloads, level: .warning)
        if NetworkMonitor.shared.connection != .none {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self?.pumpDownloads()
            }
        }
        pumpDownloads()
    }

    private func resumePendingDownloads() {
        pumpDownloads()
    }

    // MARK: - Multithreaded (segmented) transfer

    private nonisolated static func downloadSegmented(
        url: URL,
        title: String,
        total: Int,
        dest: URL,
        speedLimit: Int = 0,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws {
        let maxSegments = 6
        let minSegmentSize = 512 * 1024
        let segments = max(2, min(maxSegments, max(1, total / minSegmentSize)))
        let chunk = total / segments
        let counter = ByteCounter(total: total)

        let parts: [URL] = (0..<segments).map { dest.appendingPathExtension("part\($0)") }
        for p in parts { try? FileManager.default.removeItem(at: p) }

        func fetchSegment(_ i: Int) async throws -> Int {
            try Task.checkCancellation()
            let start = i * chunk
            let end = (i == segments - 1) ? (total - 1) : (start + chunk - 1)
            var req = URLRequest(url: url)
            req.timeoutInterval = 60
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw SegmentError.badResponse }
            guard http.statusCode == 206 else { throw SegmentError.rangeNotSupported }
            try data.write(to: parts[i], options: .atomic)
            let p = await counter.add(data.count)
            await progress(p)
            AppLogger.shared.log("Download segment complete: \(title); segment=\(i + 1)/\(segments); bytes=\(data.count)", category: .downloads)
            return data.count
        }

        do {
            if speedLimit > 0 || DeveloperExperiments.isAppWorkerSerialized {
                let started = Date()
                var downloaded = 0
                for i in 0..<segments {
                    downloaded += try await fetchSegment(i)
                    let elapsed = Date().timeIntervalSince(started)
                    let minElapsed = Double(downloaded) / Double(speedLimit)
                    if minElapsed > elapsed {
                        try? await Task.sleep(nanoseconds: UInt64((minElapsed - elapsed) * 1_000_000_000))
                    }
                }
            } else {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for i in 0..<segments {
                        group.addTask { _ = try await fetchSegment(i) }
                    }
                    try await group.waitForAll()
                }
            }

            AppLogger.shared.log("Download stitching segments: \(title); segments=\(segments)", category: .downloads)
            try? FileManager.default.removeItem(at: dest)
            FileManager.default.createFile(atPath: dest.path, contents: nil)
            let handle = try FileHandle(forWritingTo: dest)
            defer { try? handle.close() }
            for part in parts {
                let data = try Data(contentsOf: part)
                try handle.write(contentsOf: data)
            }
            for part in parts { try? FileManager.default.removeItem(at: part) }
            await progress(1.0)
        } catch {
            for part in parts { try? FileManager.default.removeItem(at: part) }
            throw error
        }
    }

    // MARK: - Completion handlers (MainActor state mutations)

    private func publishProgress(
        _ songID: String,
        _ publish: DownloadProgressPublish,
        completedBytes: Int64?,
        totalBytes: Int64?
    ) {
        guard case .downloading = state(forID: songID) else { return }
        let started = Date()
        setState(.downloading(progress: publish.progress), forID: songID)
        updateTransferProgress(
            songID,
            fraction: publish.progress,
            completedBytes: completedBytes,
            totalBytes: totalBytes
        )
        refreshBulkProgress(force: false)

        let elapsed = Date().timeIntervalSince(started)
        if elapsed > 0.02 {
            AppLogger.shared.log(
                "Slow download progress publish: id=\(songID), \(String(format: "%.3f", elapsed))s, raw=\(publish.rawCallbacks), ui=\(publish.uiPublishes)",
                category: .downloads,
                level: .warning
            )
        } else if publish.uiPublishes % 25 == 0 {
            AppLogger.shared.log(
                "Download progress publishes: id=\(songID), raw=\(publish.rawCallbacks), ui=\(publish.uiPublishes), active=\(publish.activeDownloads)",
                category: .downloads
            )
        }
    }

    private func updateTransferProgress(
        _ songID: String,
        fraction: Double,
        completedBytes: Int64?,
        totalBytes: Int64?
    ) {
        guard var transfer = transferItems[songID] else { return }
        let now = Date()
        if let totalBytes, totalBytes > 1_024 { transfer.totalBytes = totalBytes }

        let resolvedBytes: Int64
        if let completedBytes, completedBytes >= 0 {
            resolvedBytes = completedBytes
        } else if let total = transfer.totalBytes {
            resolvedBytes = Int64((Double(total) * min(1, max(0, fraction))).rounded())
        } else {
            resolvedBytes = transfer.bytesReceived
        }

        var smoothedSpeed = transfer.bytesPerSecond
        if let previous = speedSamples[songID] {
            let elapsed = now.timeIntervalSince(previous.date)
            let delta = resolvedBytes - previous.bytes
            if elapsed >= 0.08, delta >= 0 {
                let instant = Double(delta) / elapsed
                smoothedSpeed = previous.smoothedBytesPerSecond > 0
                    ? (previous.smoothedBytesPerSecond * 0.68) + (instant * 0.32)
                    : instant
            }
        }

        transfer.phase = .downloading
        transfer.bytesReceived = max(0, resolvedBytes)
        transfer.fallbackProgress = fraction
        transfer.bytesPerSecond = max(0, smoothedSpeed)
        transfer.updatedAt = now
        transferItems[songID] = transfer
        speedSamples[songID] = DownloadSpeedSample(
            bytes: transfer.bytesReceived,
            date: now,
            smoothedBytesPerSecond: transfer.bytesPerSecond
        )
        publishTransfers()
    }

    private func publishTransfers() {
        transfers = transferOrder.compactMap { transferItems[$0] }
    }

    private func removeTransfer(_ songID: String) {
        transferItems.removeValue(forKey: songID)
        transferOrder.removeAll { $0 == songID }
        speedSamples.removeValue(forKey: songID)
        publishTransfers()
    }

    private func complete(_ songID: String, song: Song, path: String, manifestURL: URL, method: String, token: UUID, serverID: String?) {
        guard isCurrentDownload(songID, token: token) else { return }
        manifest[songID] = Record(path: path, song: song, lastPlayed: nil, downloadedAt: .now, serverID: serverID)
        setState(.downloaded, forID: songID)
        activeTasks.removeValue(forKey: songID)
        stopProgressPolling(songID)
        segmentTasks.removeValue(forKey: songID)
        pendingResumes.removeValue(forKey: songID)
        runningDownloadIDs.remove(songID)
        clearDownloadToken(songID, token: token)
        removeTransfer(songID)
        Task { await Self.progressThrottler.finish(songID) }
        saveManifest(to: manifestURL)
        enforceStorageCap(keeping: songID)

        let bytes = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        let elapsed = startTimes.removeValue(forKey: songID).map { Date().timeIntervalSince($0) } ?? 0
        let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        if elapsed > 0.05, bytes > 0 {
            let speedStr = ByteCountFormatter.string(fromByteCount: Int64(Double(bytes) / elapsed), countStyle: .file)
            AppLogger.shared.log("Download complete: \(song.title) (\(method), \(sizeStr) in \(String(format: "%.1f", elapsed))s, average \(speedStr)/s)", category: .downloads)
        } else {
            AppLogger.shared.log("Download complete: \(song.title) (\(method), \(sizeStr))", category: .downloads)
        }
        let muted = mutedCompletionNotifications.remove(songID) != nil
        downloadedRevision += 1
        handleBulkSongFinished(songID, success: true)
        pumpDownloads()
        if !muted {
            VoltaNotificationCenter.shared.post(L(.notif_downloaded, song.title), tone: .success)
        }
    }

    private func prefetchArtwork(for song: Song, serverID: String?) {
        guard let client else { return }

        let artworkGroupID = Self.artworkGroupID(for: song, serverID: serverID)
        let coverOwner = Self.coverArtworkOwner(groupID: artworkGroupID, serverID: serverID)
        if let cover = Self.coverArtID(for: song), pinnedCovers.insert(artworkGroupID).inserted {
            // One durable source; view sizes downsample at decode time.
            let canonicalURL = client.coverArtURL(id: cover, size: Self.canonicalArtworkPixelSize)
                ?? client.coverArtURL(id: cover)
            let liveURLs = client.liveArtworkURLs(id: cover)
            DeveloperExperiments.launch(priority: .utility) {
                if let canonicalURL {
                    await ArtworkLoader.shared.persist(
                        canonicalURL,
                        label: song.album ?? song.title,
                        kind: "Album Cover",
                        groupID: artworkGroupID,
                        lookupID: ArtworkLoader.coverArtLookupID(cover, serverID: serverID),
                        owner: coverOwner
                    )
                }
                // Backend live-artwork endpoints often include several static
                // fallbacks. Persist only the first response that actually has
                // multiple frames, keeping the group as one animated asset.
                for url in liveURLs {
                    if await ArtworkLoader.shared.persist(
                        url,
                        label: song.album ?? song.title,
                        kind: "Animated",
                        groupID: artworkGroupID,
                        requireAnimation: true,
                        lookupID: ArtworkLoader.liveArtworkLookupID(cover, serverID: serverID),
                        owner: coverOwner
                    ) { break }
                }
            }
        }

        if let artistId = song.primaryArtistID,
           pinnedArtists.insert(ArtworkLoader.artistLookupID(artistId, serverID: serverID)).inserted {
            let owner = Self.artistArtworkOwner(artistID: artistId, serverID: serverID)
            DeveloperExperiments.launch(priority: .utility) { [client] in
                guard let info = try? await client.artistInfo(id: artistId),
                      let urlStr = info.bestImageUrl, let url = URL(string: urlStr) else { return }
                await ArtworkLoader.shared.persistArtistImage(
                    id: artistId,
                    from: url,
                    label: song.artist,
                    serverID: serverID,
                    owner: owner
                )
            }
        }
    }

    private nonisolated static func artworkGroupID(for song: Song, serverID: String? = nil) -> String {
        let scope = serverID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = (scope?.isEmpty == false) ? "server:\(scope!)|" : ""
        if let albumID = song.albumId?.trimmingCharacters(in: .whitespacesAndNewlines), !albumID.isEmpty {
            return "\(prefix)album:\(albumID)"
        }
        let album = (song.album ?? song.title).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let artist = (song.albumArtist ?? song.artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(prefix)album-label:\(artist)|\(album)"
    }

    private nonisolated static func coverArtworkOwner(groupID: String, serverID: String?) -> String {
        "download-cover:\(serverID ?? "legacy"):\(groupID)"
    }

    private nonisolated static func artistArtworkOwner(artistID: String, serverID: String?) -> String {
        "download-artist:\(serverID ?? "legacy"):\(artistID)"
    }

    nonisolated static func estimatedBulkBytes(_ songs: [Song]) -> Int {
        let known = songs.compactMap { $0.size }.filter { $0 > 0 }.sorted()
        let median = known.isEmpty ? 0 : known[known.count / 2]
        return songs.reduce(0) { total, song in
            let value: Int
            if let size = song.size, size > 0 {
                value = size
            } else {
                value = estimatedUnknownDownloadBytes(for: song, medianKnownBytes: median)
            }
            let result = total.addingReportingOverflow(value)
            return result.overflow ? Int.max : result.partialValue
        }
    }

    private nonisolated static func estimatedUnknownDownloadBytes(for song: Song, medianKnownBytes: Int) -> Int {
        let duration = max(0, song.duration ?? 0)
        let lossless = ["flac", "alac", "wav", "aiff", "aif"].contains((song.codec ?? song.suffix ?? "").lowercased())
        let floorBitsPerSecond: Int64 = lossless ? 1_500_000 : 512_000
        let durationProduct = floorBitsPerSecond.multipliedReportingOverflow(by: Int64(duration))
        let durationEstimate: Int64 = duration > 0
            ? (durationProduct.overflow ? Int64.max : durationProduct.partialValue / 8)
            : (lossless ? 90_000_000 : 30_000_000)
        let bitrateEstimate: Int64
        if let bitRate = song.bitRate, bitRate > 0, duration > 0 {
            let perSecond = Int64(bitRate).multipliedReportingOverflow(by: 1_000)
            let product = perSecond.partialValue.multipliedReportingOverflow(by: Int64(duration))
            bitrateEstimate = perSecond.overflow || product.overflow ? Int64.max : product.partialValue / 8
        } else {
            bitrateEstimate = 0
        }
        let estimate = max(Int64(medianKnownBytes), max(durationEstimate, bitrateEstimate))
        return Int(clamping: estimate)
    }

    /// Subsonic-family servers sometimes omit a song-level coverArt field even
    /// though the album ID itself is a valid image identity.
    private nonisolated static func coverArtID(for song: Song) -> String? {
        let cover = song.coverArt?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cover, !cover.isEmpty { return cover }
        let albumID = song.albumId?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (albumID?.isEmpty == false) ? albumID : nil
    }

    private func migrateDownloadedArtworkAliases(using client: any MusicService) {
        let records = manifest.values.filter {
            $0.song != nil && FileManager.default.fileExists(atPath: $0.path)
        }
        guard !records.isEmpty else { return }
        var seenCoverIDs = Set<String>()
        let candidates = records.filter { record in
            guard let song = record.song, let cover = Self.coverArtID(for: song) else { return false }
            return seenCoverIDs.insert("\(record.serverID ?? "legacy")|\(cover)").inserted
        }

        artworkAliasMigrationTask = Task { [weak self] in
            for record in candidates {
                guard !Task.isCancelled else { return }
                guard let song = record.song else { continue }
                guard let cover = Self.coverArtID(for: song) else { continue }
                let serverID = record.serverID
                let groupID = Self.artworkGroupID(for: song, serverID: serverID)
                let legacyGroupID = Self.artworkGroupID(for: song)
                let owner = Self.coverArtworkOwner(groupID: groupID, serverID: serverID)
                let isCurrentServer = serverID == self?.currentServerID
                let urls = isCurrentServer || serverID == nil
                    ? ([client.coverArtURL(id: cover)] + Self.artworkSizes.map { client.coverArtURL(id: cover, size: $0) }).compactMap { $0 }
                    : []
                let associated = await ArtworkLoader.shared.associatePinnedCoverArt(
                    id: cover,
                    urls: urls,
                    label: song.album ?? song.title,
                    groupID: groupID,
                    serverID: serverID,
                    owner: owner,
                    legacyGroupIDs: [legacyGroupID]
                )
                _ = await ArtworkLoader.shared.associatePinnedAnimatedArtwork(
                    id: cover,
                    urls: isCurrentServer || serverID == nil ? client.liveArtworkURLs(id: cover) : [],
                    label: song.album ?? song.title,
                    groupID: groupID,
                    serverID: serverID,
                    owner: owner,
                    legacyGroupIDs: [legacyGroupID]
                )
                if !associated {
                    // Old records without a persisted server identity retain
                    // legacy lookup behavior; never relabel them to current.
                    guard serverID != nil, isCurrentServer else { continue }
                    let canonicalURL = client.coverArtURL(id: cover, size: Self.canonicalArtworkPixelSize)
                        ?? client.coverArtURL(id: cover)
                    if let canonicalURL {
                        _ = await ArtworkLoader.shared.persist(
                            canonicalURL,
                            label: song.album ?? song.title,
                            kind: "Album Cover",
                            groupID: groupID,
                            lookupID: ArtworkLoader.coverArtLookupID(cover, serverID: serverID),
                            owner: owner
                        )
                    }
                }
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.artworkAliasMigrationTask = nil }
        }
    }

    private func fail(_ songID: String, removing dest: URL, updateBulk: Bool = true, token: UUID? = nil) {
        if let token {
            guard isCurrentDownload(songID, token: token) else { return }
            clearDownloadToken(songID, token: token)
        } else {
            downloadTokens.removeValue(forKey: songID)
        }
        setState(.notDownloaded, forID: songID)
        activeTasks.removeValue(forKey: songID)
        stopProgressPolling(songID)
        segmentTasks.removeValue(forKey: songID)
        queuedDownloads.removeAll { $0.song.id == songID }
        runningDownloadIDs.remove(songID)
        startTimes.removeValue(forKey: songID)
        pendingResumes.removeValue(forKey: songID)
        mutedCompletionNotifications.remove(songID)
        LyricsBulkDownloader.shared.cancelCompanionLyrics(for: songID)
        removeTransfer(songID)
        Task { await Self.progressThrottler.finish(songID) }
        try? FileManager.default.removeItem(at: dest)
        if updateBulk {
            handleBulkSongFinished(songID, success: false)
        }
        pumpDownloads()
    }

    // MARK: - Bulk missing-song downloads

    func startBulkDownloadMissing(_ songs: [Song]) {
        guard bulkProgress.isRunning == false else { return }
        guard let client else { return }
        if DemoServers.isDemo(client.config.baseURL) {
            VoltaNotificationCenter.shared.post(L(.notif_demo_no_downloads), tone: .info)
            return
        }

        var seen = Set<String>()
        let pending = songs.filter { song in
            guard seen.insert(song.id).inserted else { return false }
            guard case .notDownloaded = state(for: song) else { return false }
            return client.downloadURL(for: song) != nil
        }
        guard !pending.isEmpty else { return }

        let expectedBytes = Self.estimatedBulkBytes(pending)
        guard DeviceStorageCapacity.current().allowsDownload(expectedBytes: expectedBytes) else {
            VoltaNotificationCenter.shared.post("Not enough free storage to preserve the device safety reserve", tone: .warning)
            AppLogger.shared.log("Bulk download rejected by device-capacity reserve; expected=\(expectedBytes)", category: .downloads, level: .warning)
            return
        }

        bulkSongsByID = Dictionary(uniqueKeysWithValues: pending.map { ($0.id, $0) })
        bulkActiveIDs = Set(pending.map(\.id))
        bulkCompletedCount = 0
        bulkFailedCount = 0
        bulkSkippedCount = 0
        bulkBytesFinished = 0
        bulkBytesTotal = expectedBytes
        bulkTotalCount = pending.count
        bulkStartedAt = Date()
        lastBulkSnapshotAt = .distantPast
        bulkProgress = DownloadBulkProgress(
            phase: .running,
            total: bulkTotalCount,
            bytesTotal: bulkBytesTotal,
            startedAt: bulkStartedAt,
            updatedAt: Date()
        )

        AppLogger.shared.log(
            "Bulk missing-song download queued: total=\(bulkTotalCount), bytes=\(bulkBytesTotal), concurrency=\(concurrentDownloadLimit)",
            category: .downloads
        )
        VoltaNotificationCenter.shared.post(L(.notif_downloading_n, pending.count), tone: .success)
        for song in pending {
            guard let streamURL = client.downloadURL(for: song) else {
                bulkActiveIDs.remove(song.id)
                bulkSkippedCount += 1
                bulkBytesFinished += song.size ?? 0
                continue
            }
            enqueueDownload(
                song: song,
                streamURL: streamURL,
                client: client,
                notifyOnCompletion: false,
                belongsToBulkDownload: true,
                serverID: currentServerID,
                pumpImmediately: false
            )
        }
        pumpDownloads()
    }

    func pauseBulkDownloads() {
        guard bulkProgress.phase == .running else { return }
        bulkProgress.phase = .paused
        refreshBulkProgress(force: true)
        AppLogger.shared.log("Bulk missing-song download paused: completed=\(bulkCompletedCount)/\(bulkTotalCount), active=\(runningDownloadIDs.intersection(bulkActiveIDs).count)", category: .downloads)
    }

    func resumeBulkDownloads() {
        guard bulkProgress.phase == .paused else { return }
        bulkProgress.phase = .running
        AppLogger.shared.log("Bulk missing-song download resumed", category: .downloads)
        pumpDownloads()
    }

    func cancelBulkDownloads() {
        guard bulkProgress.isRunning else { return }
        bulkProgress.phase = .paused
        let outstandingSongs = bulkActiveIDs.compactMap { bulkSongsByID[$0] }
        for song in outstandingSongs {
            cancelDownload(for: song, notify: false, updateBulk: false)
        }
        bulkActiveIDs.removeAll()
        finishBulkDownloads(cancelled: true)
        pumpDownloads()
    }

    private func handleBulkSongFinished(_ songID: String, success: Bool) {
        guard bulkActiveIDs.remove(songID) != nil else { return }
        if success {
            bulkCompletedCount += 1
            bulkBytesFinished += bulkSongsByID[songID]?.size ?? 0
        } else {
            bulkFailedCount += 1
        }
        if bulkActiveIDs.isEmpty {
            finishBulkDownloads(cancelled: false)
        } else {
            refreshBulkProgress(force: true)
        }
    }

    private func refreshBulkProgress(force: Bool) {
        guard bulkProgress.isRunning else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastBulkSnapshotAt) >= 0.25 else { return }
        lastBulkSnapshotAt = now

        let activeFraction = bulkActiveIDs.reduce(0.0) { total, id in
            total + (transferItems[id]?.fraction ?? 0)
        }
        bulkProgress = DownloadBulkProgress(
            phase: bulkProgress.phase,
            total: bulkTotalCount,
            completed: bulkCompletedCount,
            failed: bulkFailedCount,
            skipped: bulkSkippedCount,
            active: runningDownloadIDs.intersection(bulkActiveIDs).count,
            bytesTotal: bulkBytesTotal,
            bytesFinished: bulkBytesFinished,
            activeFraction: activeFraction,
            startedAt: bulkStartedAt,
            updatedAt: now
        )
    }

    private func finishBulkDownloads(cancelled: Bool) {
        let now = Date()
        let finalProgress = DownloadBulkProgress(
            phase: cancelled ? .cancelled : .finished,
            total: bulkTotalCount,
            completed: bulkCompletedCount,
            failed: bulkFailedCount,
            skipped: bulkSkippedCount,
            active: 0,
            bytesTotal: bulkBytesTotal,
            bytesFinished: bulkBytesFinished,
            activeFraction: 0,
            startedAt: bulkStartedAt,
            updatedAt: now
        )

        bulkProgress = finalProgress
        AppLogger.shared.log(
            "Bulk missing-song download \(cancelled ? "cancelled" : "finished"): completed=\(bulkCompletedCount), failed=\(bulkFailedCount), skipped=\(bulkSkippedCount), total=\(bulkTotalCount)",
            category: .downloads,
            level: bulkFailedCount > 0 ? .warning : .info
        )

        if cancelled {
            VoltaNotificationCenter.shared.post("Missing song downloads stopped", tone: .warning)
        } else if bulkFailedCount > 0 {
            VoltaNotificationCenter.shared.post("Downloaded \(bulkCompletedCount) missing songs, \(bulkFailedCount) failed", tone: .warning)
        } else {
            VoltaNotificationCenter.shared.post("Downloaded \(bulkCompletedCount) missing songs", tone: .success)
        }

        bulkSongsByID.removeAll()
        bulkActiveIDs.removeAll()
        bulkStartedAt = nil
    }

    // MARK: - Manifest

    struct Record: Codable, Sendable {
        var path: String
        var song: Song?
        var lastPlayed: Date?
        var downloadedAt: Date?
        var serverID: String?
    }

    private var manifest: [String: Record] = [:]
    private var isReconcilingMetadata = false

    // Derived song lists are rebuilt from the manifest (which means a fileExists
    // syscall per record). Views read these from computed properties many times
    // per render, so memoize per downloadedRevision to keep that work off the
    // main thread's hot path — a stale entry can only exist for one revision.
    private var downloadedSongsCache: (revision: Int, songs: [Song])?
    private var downloadedRecentCache: (revision: Int, songs: [Song])?

    // MARK: - Storage cap / LRU eviction

    func markPlayed(_ songID: String) {
        guard manifest[songID] != nil else { return }
        manifest[songID]?.lastPlayed = .now
        // Doesn't change which songs exist (downloadedRevision is untouched), only
        // their recent-play ordering — so just drop that one cache.
        downloadedRecentCache = nil
        saveManifest(to: manifestURL)
    }

    func totalDownloadedBytes() -> Int {
        manifest.values.reduce(0) { sum, rec in
            sum + ((try? FileManager.default.attributesOfItem(atPath: rec.path)[.size] as? Int) ?? 0)
        }
    }

    func downloadedItems() -> [DownloadedTrackItem] {
        manifest.map { id, record in
            let url = URL(fileURLWithPath: record.path)
            return DownloadedTrackItem(
                id: id,
                song: record.song,
                fileName: url.lastPathComponent,
                bytes: Int64(Self.fileSize(at: url)),
                downloadedAt: record.downloadedAt
            )
        }
        .filter { $0.bytes > 0 }
        .sorted { lhs, rhs in
            if lhs.downloadedAt != rhs.downloadedAt {
                return (lhs.downloadedAt ?? .distantPast) > (rhs.downloadedAt ?? .distantPast)
            }
            let lhsName = lhs.song?.title ?? lhs.fileName
            let rhsName = rhs.song?.title ?? rhs.fileName
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }
    }

    func downloadedItemsSnapshot() async -> [DownloadedTrackItem] {
        let records = manifest.map { id, record in
            DownloadedRecordSnapshot(
                id: id,
                song: record.song,
                path: record.path,
                downloadedAt: record.downloadedAt
            )
        }
        return await DeveloperExperiments.runSync(priority: .utility) {
            records.compactMap { record in
                let url = URL(fileURLWithPath: record.path)
                let bytes = Int64(Self.fileSize(at: url))
                guard bytes > 0 else { return nil }
                return DownloadedTrackItem(
                    id: record.id,
                    song: record.song,
                    fileName: url.lastPathComponent,
                    bytes: bytes,
                    downloadedAt: record.downloadedAt
                )
            }
            .sorted { lhs, rhs in
                if lhs.downloadedAt != rhs.downloadedAt {
                    return (lhs.downloadedAt ?? .distantPast) > (rhs.downloadedAt ?? .distantPast)
                }
                let lhsName = lhs.song?.title ?? lhs.fileName
                let rhsName = rhs.song?.title ?? rhs.fileName
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }
        }
    }

    func removeAllDownloads() {
        if bulkProgress.isRunning { bulkProgress.phase = .paused }
        let transfersToCancel = transferItems.values.map(\.song)
        queuedDownloads.removeAll()
        for song in transfersToCancel {
            cancelDownload(for: song, notify: false, updateBulk: false)
        }
        if bulkProgress.isRunning {
            bulkActiveIDs.removeAll()
            finishBulkDownloads(cancelled: true)
        }

        let ids = Array(manifest.keys)
        let removedSongs = manifest.values.compactMap { record in
            record.song.map { (song: $0, serverID: record.serverID) }
        }
        for (id, record) in manifest {
            try? FileManager.default.removeItem(atPath: record.path)
            setState(.notDownloaded, forID: id)
        }
        manifest.removeAll()
        downloadedSongsCache = nil
        downloadedRecentCache = nil
        downloadedRevision += 1
        saveManifest(to: manifestURL)
        // Manifest is now empty, so canonical download-owned artwork can be
        // released while explicitly synced local-artwork-library owners remain.
        for removed in removedSongs { unpinOrphanedArtwork(after: removed.song, serverID: removed.serverID) }
        AppLogger.shared.log("All downloaded tracks removed: count=\(ids.count)", category: .downloads)
    }

    private func enforceStorageCap(keeping protectedID: String?) {
        guard UserDefaults.standard.bool(forKey: "autoEvictDownloads") else { return }
        let capMB = UserDefaults.standard.integer(forKey: "downloadCapMB")
        guard capMB > 0 else { return }
        let capBytes = capMB * 1_048_576

        func fileSize(_ path: String) -> Int {
            (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        }
        var total = manifest.values.reduce(0) { $0 + fileSize($1.path) }
        guard total > capBytes else { return }

        let candidates = manifest
            .filter { $0.key != protectedID && state(forID: $0.key) == .downloaded }
            .sorted { ($0.value.lastPlayed ?? .distantPast) < ($1.value.lastPlayed ?? .distantPast) }

        var evictedSongs: [(song: Song, serverID: String?)] = []
        for (id, rec) in candidates {
            guard total > capBytes else { break }
            let size = fileSize(rec.path)
            try? FileManager.default.removeItem(atPath: rec.path)
            manifest.removeValue(forKey: id)
            if let song = rec.song { evictedSongs.append((song, rec.serverID)) }
            setState(.notDownloaded, forID: id)
            downloadedRevision += 1
            total -= size
            AppLogger.shared.log("Download evicted: '\(rec.song?.title ?? id)' to stay under \(capMB)MB cap", category: .downloads)
            VoltaNotificationCenter.shared.post(L(.notif_evicted_old_download), tone: .info)
        }
        saveManifest(to: manifestURL)
        for evicted in evictedSongs { unpinOrphanedArtwork(after: evicted.song, serverID: evicted.serverID) }
    }

    func downloadedSongs() -> [Song] {
        let revision = downloadedRevision
        if let cache = downloadedSongsCache, cache.revision == revision {
            return cache.songs
        }
        let songs = manifest.values.compactMap { (rec: Record) -> Song? in
            guard let song = rec.song,
                  FileManager.default.fileExists(atPath: rec.path) else { return nil }
            return song
        }
        downloadedSongsCache = (revision, songs)
        return songs
    }

    // Download-manifest order for Library's Recently Downloaded shelf.
    // This keeps valid metadata when a filesystem size probe returns zero.
    func downloadedSongsByDownloadDate() -> [Song] {
        manifest.values
            .filter { record in
                guard let song = record.song else { return false }
                return FileManager.default.fileExists(atPath: record.path) || !song.id.isEmpty
            }
            .sorted {
                let lhsDate = $0.downloadedAt ?? .distantPast
                let rhsDate = $1.downloadedAt ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return ($0.song?.title ?? "").localizedCaseInsensitiveCompare($1.song?.title ?? "") == .orderedAscending
            }
            .compactMap(\.song)
    }

    func downloadedSongsByRecentPlay() -> [Song] {
        let revision = downloadedRevision
        if let cache = downloadedRecentCache, cache.revision == revision {
            return cache.songs
        }
        let songs = manifest.values
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted {
                let lhsDate = $0.lastPlayed ?? .distantPast
                let rhsDate = $1.lastPlayed ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return ($0.song?.title ?? "").localizedCaseInsensitiveCompare($1.song?.title ?? "") == .orderedAscending
            }
            .compactMap(\.song)
        downloadedRecentCache = (revision, songs)
        return songs
    }

    private func loadManifest() {
        var changed = false
        var decodeFailed = false

        if let data = try? Data(contentsOf: manifestURL) {
            if let decoded = try? JSONDecoder().decode([String: Record].self, from: data) {
                manifest = decoded
            } else if let legacy = try? JSONDecoder().decode([String: String].self, from: data) {
                manifest = legacy.mapValues { Record(path: $0, song: nil, lastPlayed: nil, downloadedAt: nil, serverID: nil) }
            } else {
                // The manifest is present but unreadable (corrupt / partially
                // written / schema drift). Never blindly continue — that path
                // used to overwrite it with an empty manifest and orphan every
                // downloaded file on disk. Preserve it for diagnostics and
                // rebuild from the files that are actually present.
                decodeFailed = true
                let backup = manifestURL.deletingPathExtension()
                    .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.moveItem(at: manifestURL, to: backup)
                AppLogger.shared.log(
                    "Download manifest unreadable; backed up to \(backup.lastPathComponent) and rebuilding from disk",
                    category: .downloads, level: .error
                )
            }
        }

        // Drop records whose file is gone, and delete obviously-corrupt tiny files.
        var invalidIDs: [String] = []
        for (id, rec) in manifest {
            let url = URL(fileURLWithPath: rec.path)
            if Self.isObviouslyInvalidAudioDownload(url) {
                try? FileManager.default.removeItem(at: url)
                invalidIDs.append(id)
                AppLogger.shared.log("Removed invalid tiny download '\(rec.song?.title ?? id)'", category: .downloads, level: .warning)
            } else if FileManager.default.fileExists(atPath: rec.path) {
                setState(.downloaded, forID: id)
            } else {
                invalidIDs.append(id)
            }
        }
        for id in invalidIDs { manifest.removeValue(forKey: id) }
        if !invalidIDs.isEmpty { changed = true }

        // Re-adopt audio files on disk the manifest doesn't know about. Files
        // outlive the JSON, so this recovers downloads after a manifest loss.
        // Metadata (title/artist/…) is backfilled from the server later via
        // reconcileDownloadedMetadata(); until then the files still count toward
        // storage and play by path.
        if adoptOrphanedDownloadFiles() { changed = true }

        downloadedRevision += 1
        // Persist only when something actually changed, and never write an empty
        // manifest over downloads we simply failed to read this launch.
        if changed && !(decodeFailed && manifest.isEmpty) {
            saveManifest(to: manifestURL)
        }
    }

    // Pull in any download files sitting in the directory that aren't tracked by
    // the manifest. Returns true if it adopted at least one.
    @discardableResult
    private func adoptOrphanedDownloadFiles() -> Bool {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]
        ) else { return false }
        let knownPaths = Set(manifest.values.map(\.path))
        var added = false
        for url in entries where url.pathExtension.lowercased() != "json" {
            guard !knownPaths.contains(url.path) else { continue }
            if Self.isObviouslyInvalidAudioDownload(url) {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            guard Self.fileSize(at: url) >= 1_024 else { continue }
            let id = Self.songID(fromFileName: url.lastPathComponent)
            guard !id.isEmpty, manifest[id] == nil else { continue }
            manifest[id] = Record(path: url.path, song: nil, lastPlayed: nil, downloadedAt: nil, serverID: nil)
            setState(.downloaded, forID: id)
            added = true
        }
        if added {
            AppLogger.shared.log("Recovered orphaned downloads from disk; metadata will backfill when online", category: .downloads)
        }
        return added
    }

    // Look up server metadata for manifest records that have none (recovered
    // orphans, or entries migrated from a legacy path-only manifest).
    private func reconcileDownloadedMetadata() {
        guard let client, !isReconcilingMetadata else { return }
        let missing = manifest.compactMap { $0.value.song == nil ? $0.key : nil }
        guard !missing.isEmpty else { return }
        isReconcilingMetadata = true
        Task { @MainActor in
            defer { isReconcilingMetadata = false }
            var filled = 0
            for id in missing {
                guard manifest[id]?.song == nil else { continue }
                // try? on a throwing `Song?` call yields Song??; flatten so a
                // "not found" (nil) result doesn't count as a successful fill.
                guard let song = (try? await client.song(id: id)) ?? nil else { continue }
                guard manifest[id] != nil else { continue }   // removed while we waited
                manifest[id]?.song = song
                filled += 1
                if filled % 25 == 0 {
                    downloadedRevision += 1
                    saveManifest(to: manifestURL)
                }
            }
            if filled > 0 {
                downloadedRevision += 1
                saveManifest(to: manifestURL)
                AppLogger.shared.log("Backfilled metadata for \(filled) recovered download(s)", category: .downloads)
            }
        }
    }

    private nonisolated static func songID(fromFileName name: String) -> String {
        (name as NSString).deletingPathExtension
    }

    private nonisolated static func isObviouslyInvalidAudioDownload(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let ext = url.pathExtension.lowercased()
        guard ["aac", "alac", "flac", "m4a", "mp3", "ogg", "opus", "wav", "webma"].contains(ext) else {
            return false
        }
        let bytes = fileSize(at: url)
        return bytes > 0 && bytes < 1_024
    }

    private func saveManifest(to url: URL) {
        let snapshot = manifest
        let writer = manifestWriter
        manifestSaveSequence += 1
        let sequence = manifestSaveSequence
        Task(priority: .utility) {
            await writer.save(snapshot, to: url, sequence: sequence)
        }
    }
}

private struct DownloadedRecordSnapshot: Sendable {
    let id: String
    let song: Song?
    let path: String
    let downloadedAt: Date?
}

private actor DownloadManifestWriter {
    private var latestSequence = 0

    func save(_ manifest: [String: DownloadService.Record], to url: URL, sequence: Int) {
        guard sequence >= latestSequence else { return }
        latestSequence = sequence
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
