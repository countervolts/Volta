import Foundation
import Observation
import UIKit

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

@MainActor
@Observable
private final class DownloadItemState {
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
        AppLogger.shared.log("Download active count: \(activeIDs.count)", category: .other)
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
                category: .other
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
            category: .other
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
}

@MainActor
@Observable
final class DownloadService {
    static let shared = DownloadService()

    private(set) var bulkProgress = DownloadBulkProgress()
    private(set) var downloadedRevision = 0

    @ObservationIgnored private var stateItems: [String: DownloadItemState] = [:]
    @ObservationIgnored private var activeTasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var observations: [String: NSKeyValueObservation] = [:]
    @ObservationIgnored private var segmentTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var startTimes: [String: Date] = [:]
    @ObservationIgnored private var pendingResumes: [String: PendingDownloadResume] = [:]
    @ObservationIgnored private var mutedCompletionNotifications: Set<String> = []
    @ObservationIgnored private var downloadTokens: [String: UUID] = [:]
    @ObservationIgnored private var client: (any MusicService)?

    @ObservationIgnored private var pinnedCovers: Set<String> = []
    @ObservationIgnored private var pinnedArtists: Set<String> = []

    @ObservationIgnored private var bulkQueue: [Song] = []
    @ObservationIgnored private var bulkSongsByID: [String: Song] = [:]
    @ObservationIgnored private var bulkActiveIDs: Set<String> = []
    @ObservationIgnored private var bulkCompletedCount = 0
    @ObservationIgnored private var bulkFailedCount = 0
    @ObservationIgnored private var bulkSkippedCount = 0
    @ObservationIgnored private var bulkBytesFinished = 0
    @ObservationIgnored private var bulkBytesTotal = 0
    @ObservationIgnored private var bulkTotalCount = 0
    @ObservationIgnored private var bulkStartedAt: Date?
    @ObservationIgnored private var lastBulkSnapshotAt = Date.distantPast
    @ObservationIgnored private var manifestWriter = DownloadManifestWriter()
    @ObservationIgnored private var manifestSaveSequence = 0

    private nonisolated static let progressThrottler = DownloadProgressThrottler()
    private nonisolated static let bulkMaxConcurrent = 2

    static let artworkSizes = [80, 100, 200, 300, 400, 600, 800]

    private let directory: URL
    private let manifestURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = docs.appendingPathComponent("volta-downloads", isDirectory: true)
        manifestURL = directory.appendingPathComponent("manifest.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        loadManifest()
        NetworkMonitor.shared.onConnectionChange { [weak self] conn in
            guard conn != .none else { return }
            self?.resumePendingDownloads()
        }
    }

    func updateClient(_ client: (any MusicService)?) {
        self.client = client
        // Once a server is reachable, fill in metadata for any downloads we
        // recovered from disk (or migrated from a legacy manifest) so they
        // reappear in the Downloaded / offline lists.
        if client != nil { reconcileDownloadedMetadata() }
    }

    func state(for song: Song) -> DownloadState {
        state(forID: song.id)
    }

    private func state(forID id: String) -> DownloadState {
        stateItem(for: id).state
    }

    private func setState(_ state: DownloadState, forID id: String) {
        stateItem(for: id).state = state
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

    func download(song: Song, notifyOnCompletion: Bool = true) {
        if pendingResumes[song.id] != nil {
            resumePendingDownload(id: song.id)
            return
        }
        guard case .notDownloaded = state(for: song) else { return }
        guard let client, let streamURL = client.downloadURL(id: song.id) else { return }
        // Demo servers are stream-only; never save their content to the device.
        if DemoServers.isDemo(client.config.baseURL) {
            VoltaNotificationCenter.shared.post(L(.notif_demo_no_downloads), tone: .info)
            return
        }
        startDownload(song: song, streamURL: streamURL, client: client, notifyOnCompletion: notifyOnCompletion)
    }

    private func startDownload(song: Song, streamURL: URL, client: any MusicService, notifyOnCompletion: Bool) {
        guard case .notDownloaded = state(for: song) else { return }

        let songID = song.id
        let token = beginDownloadToken(for: songID)
        setState(.downloading(progress: 0), forID: songID)
        startTimes[songID] = Date()
        if notifyOnCompletion {
            mutedCompletionNotifications.remove(songID)
        } else {
            mutedCompletionNotifications.insert(songID)
        }
        Task { await Self.progressThrottler.start(songID) }
        prefetchArtwork(for: song)

        let title    = song.title
        let progressiveDownload = client.downloadIsProgressive(id: songID)
        let suffix   = Self.downloadFileSuffix(for: song, client: client)
        let total    = progressiveDownload ? 0 : (song.size ?? 0)
        let destURL  = directory.appendingPathComponent(Self.safeFileName(id: songID, suffix: suffix))
        let manifestURL = manifestURL
        let mode = UserDefaults.standard.string(forKey: "downloadThreadingMode") ?? "multi"

        let speedLimit = UserDefaults.standard.integer(forKey: "downloadSpeedLimitKBps") * 1024
        let useSegmentedTransfer = !progressiveDownload
            && total > 0
            && !DeveloperExperiments.isAppWorkerSerialized
            && ((mode != "single" && total > 1_048_576) || speedLimit > 0)

        if useSegmentedTransfer {
            let segments = max(2, min(DeveloperExperiments.constrainedConcurrency(default: 6), total / (512 * 1024)))
            AppLogger.shared.log("Download starting: \(title) (\(segments) segments, \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file))\(speedLimit > 0 ? ", limited" : ""))", category: .other)
            let task = Task { [self] in
                do {
                    try await DownloadService.downloadSegmented(url: streamURL, title: title, total: total, dest: destURL, speedLimit: speedLimit) { progress in
                        if let publish = await Self.progressThrottler.record(songID, progress: progress) {
                            await MainActor.run {
                                self.publishProgress(songID, publish)
                            }
                        }
                    }
                    complete(songID, song: song, path: destURL.path, manifestURL: manifestURL, method: "multithreaded", token: token)
                } catch is CancellationError {
                    guard isCurrentDownload(songID, token: token) else { return }
                    AppLogger.shared.log("Download cancelled: \(title)", category: .other)
                    fail(songID, removing: destURL, token: token)
                } catch {
                    guard isCurrentDownload(songID, token: token) else { return }
                    if DownloadService.isTransientNetworkError(error) {
                        pauseForResume(song: song, url: streamURL, dest: destURL, manifestURL: manifestURL, method: "single thread", resumeData: nil, token: token)
                    } else {
                        AppLogger.shared.log("Segmented download failed: \(title) (\(error.localizedDescription)); falling back to single", category: .other, level: .warning)
                        startSingle(song: song, url: streamURL, dest: destURL, manifestURL: manifestURL, token: token)
                    }
                }
            }
            segmentTasks[songID] = task
        } else if progressiveDownload {
            AppLogger.shared.log("Download starting: \(title) (\(Self.progressiveDownloadMethod), \(suffix))", category: .other)
            startSingle(song: song, url: streamURL, dest: destURL, manifestURL: manifestURL, method: Self.progressiveDownloadMethod, token: token)
        } else {
            AppLogger.shared.log("Download starting: \(title) (single thread\(total > 0 ? ", \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file))" : ""))", category: .other)
            startSingle(song: song, url: streamURL, dest: destURL, manifestURL: manifestURL, token: token)
        }
    }

    func cancelDownload(for song: Song) {
        cancelDownload(for: song, notify: true, updateBulk: true)
    }

    private func cancelDownload(for song: Song, notify: Bool, updateBulk: Bool) {
        AppLogger.shared.log("Download cancelled: \(song.title)", category: .other)
        if notify, case .downloading = state(for: song) {
            VoltaNotificationCenter.shared.post(L(.notif_download_cancelled), tone: .warning)
        }
        activeTasks[song.id]?.cancel()
        segmentTasks[song.id]?.cancel()
        activeTasks.removeValue(forKey: song.id)
        observations.removeValue(forKey: song.id)
        segmentTasks.removeValue(forKey: song.id)
        startTimes.removeValue(forKey: song.id)
        pendingResumes.removeValue(forKey: song.id)
        downloadTokens.removeValue(forKey: song.id)
        mutedCompletionNotifications.remove(song.id)
        setState(.notDownloaded, forID: song.id)
        Task { await Self.progressThrottler.finish(song.id) }
        if updateBulk {
            handleBulkSongFinished(song.id, success: false)
        }
    }

    func removeDownload(for song: Song) {
        AppLogger.shared.log("Download removed: \(song.title)", category: .other)
        VoltaNotificationCenter.shared.post(L(.notif_download_removed), tone: .info)
        cancelDownload(for: song)
        if let rec = manifest[song.id] {
            try? FileManager.default.removeItem(atPath: rec.path)
        }
        manifest.removeValue(forKey: song.id)
        downloadedRevision += 1
        saveManifest(to: manifestURL)
        unpinOrphanedArtwork(after: song)
    }

    private func unpinOrphanedArtwork(after song: Song) {
        let remaining = downloadedSongs()
        if let cover = song.coverArt, !remaining.contains(where: { $0.coverArt == cover }) {
            pinnedCovers.remove(cover)
            let urls = Self.artworkSizes.compactMap { client?.coverArtURL(id: cover, size: $0) }
            DeveloperExperiments.launch(priority: .utility) { await ArtworkLoader.shared.unpin(urls) }
        }
        if let artistId = song.artistId, !remaining.contains(where: { $0.artistId == artistId }) {
            pinnedArtists.remove(artistId)
            DeveloperExperiments.launch(priority: .utility) { await ArtworkLoader.shared.unpinArtist(id: artistId) }
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
        if client.downloadIsProgressive(id: song.id) {
            return StreamingPreferences.plexUniversalTranscodeExtension
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

    private func startSingle(song: Song, url: URL, dest: URL, manifestURL: URL, token: UUID) {
        startSingle(song: song, url: url, dest: dest, manifestURL: manifestURL, resumeData: nil, token: token)
    }

    private func startSingle(song: Song, url: URL, dest: URL, manifestURL: URL, method: String = "single thread", resumeData: Data? = nil, token: UUID) {
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
                        AppLogger.shared.log("Download rejected: \(title): \(failure)", category: .other, level: .error)
                        self.fail(songID, removing: dest, token: token)
                    }
                    return
                }

                try? FileManager.default.removeItem(at: dest)
                let moved = (try? FileManager.default.moveItem(at: tempURL, to: dest)) != nil
                Task { @MainActor in
                    guard self.isCurrentDownload(songID, token: token) else { return }
                    if moved {
                        self.complete(songID, song: song, path: dest.path, manifestURL: manifestURL, method: method, token: token)
                    } else {
                        AppLogger.shared.log("Download failed to save file: \(title)", category: .other, level: .error)
                        self.fail(songID, removing: dest, token: token)
                    }
                }
            } else {
                let msg = error?.localizedDescription ?? "unknown error"
                Task { @MainActor in
                    guard self.isCurrentDownload(songID, token: token) else { return }
                    let resumeData = DownloadService.resumeData(from: error)
                    if resumeData != nil || DownloadService.isTransientNetworkError(error) {
                        self.pauseForResume(song: song, url: url, dest: dest, manifestURL: manifestURL, method: method, resumeData: resumeData, token: token)
                    } else {
                        AppLogger.shared.log("Download failed: \(title): \(msg)", category: .other, level: .error)
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

        let obs = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            guard let service = self else { return }
            let fraction = progress.fractionCompleted
            Task(priority: .utility) { [service] in
                if let publish = await Self.progressThrottler.record(songID, progress: fraction) {
                    await MainActor.run {
                        service.publishProgress(songID, publish)
                    }
                }
            }
        }
        observations[songID] = obs
        activeTasks[songID] = task
        task.resume()
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

    private func pauseForResume(song: Song, url: URL, dest: URL, manifestURL: URL, resumeData: Data?, token: UUID) {
        pauseForResume(song: song, url: url, dest: dest, manifestURL: manifestURL, method: "single thread", resumeData: resumeData, token: token)
    }

    private func pauseForResume(song: Song, url: URL, dest: URL, manifestURL: URL, method: String, resumeData: Data?, token: UUID) {
        let songID = song.id
        guard isCurrentDownload(songID, token: token) else { return }
        activeTasks.removeValue(forKey: songID)
        observations.removeValue(forKey: songID)
        segmentTasks.removeValue(forKey: songID)
        pendingResumes[songID] = PendingDownloadResume(
            song: song,
            url: url,
            dest: dest,
            manifestURL: manifestURL,
            method: method,
            resumeData: resumeData,
            token: token
        )
        let progress: Double
        if case .downloading(let current) = state(forID: songID) {
            progress = current
        } else {
            progress = 0
        }
        setState(.downloading(progress: progress), forID: songID)
        AppLogger.shared.log("Download paused: \(song.title); connection lost, will resume when network returns", category: .other, level: .warning)
        if NetworkMonitor.shared.connection != .none {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self?.resumePendingDownload(id: songID)
            }
        }
    }

    private func resumePendingDownloads() {
        for id in pendingResumes.keys.sorted() {
            resumePendingDownload(id: id)
        }
    }

    private func resumePendingDownload(id: String) {
        guard activeTasks[id] == nil,
              segmentTasks[id] == nil,
              let pending = pendingResumes.removeValue(forKey: id) else { return }
        if startTimes[id] == nil { startTimes[id] = Date() }
        AppLogger.shared.log("Download resuming: \(pending.song.title)", category: .other)
        startSingle(
            song: pending.song,
            url: pending.url,
            dest: pending.dest,
            manifestURL: pending.manifestURL,
            method: pending.method,
            resumeData: pending.resumeData,
            token: pending.token
        )
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
            AppLogger.shared.log("Download segment complete: \(title); segment=\(i + 1)/\(segments); bytes=\(data.count)", category: .other)
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

            AppLogger.shared.log("Download stitching segments: \(title); segments=\(segments)", category: .other)
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

    private func publishProgress(_ songID: String, _ publish: DownloadProgressPublish) {
        guard case .downloading = state(forID: songID) else { return }
        let started = Date()
        setState(.downloading(progress: publish.progress), forID: songID)
        refreshBulkProgress(force: false)

        let elapsed = Date().timeIntervalSince(started)
        if elapsed > 0.02 {
            AppLogger.shared.log(
                "Slow download progress publish: id=\(songID), \(String(format: "%.3f", elapsed))s, raw=\(publish.rawCallbacks), ui=\(publish.uiPublishes)",
                category: .other,
                level: .warning
            )
        } else if publish.uiPublishes % 25 == 0 {
            AppLogger.shared.log(
                "Download progress publishes: id=\(songID), raw=\(publish.rawCallbacks), ui=\(publish.uiPublishes), active=\(publish.activeDownloads)",
                category: .other
            )
        }
    }

    private func complete(_ songID: String, song: Song, path: String, manifestURL: URL, method: String, token: UUID) {
        guard isCurrentDownload(songID, token: token) else { return }
        manifest[songID] = Record(path: path, song: song, lastPlayed: nil)
        setState(.downloaded, forID: songID)
        activeTasks.removeValue(forKey: songID)
        observations.removeValue(forKey: songID)
        segmentTasks.removeValue(forKey: songID)
        pendingResumes.removeValue(forKey: songID)
        clearDownloadToken(songID, token: token)
        Task { await Self.progressThrottler.finish(songID) }
        saveManifest(to: manifestURL)
        enforceStorageCap(keeping: songID)

        let bytes = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        let elapsed = startTimes.removeValue(forKey: songID).map { Date().timeIntervalSince($0) } ?? 0
        let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        if elapsed > 0.05, bytes > 0 {
            let speedStr = ByteCountFormatter.string(fromByteCount: Int64(Double(bytes) / elapsed), countStyle: .file)
            AppLogger.shared.log("Download complete: \(song.title) (\(method), \(sizeStr) in \(String(format: "%.1f", elapsed))s, average \(speedStr)/s)", category: .other)
        } else {
            AppLogger.shared.log("Download complete: \(song.title) (\(method), \(sizeStr))", category: .other)
        }
        let muted = mutedCompletionNotifications.remove(songID) != nil
        downloadedRevision += 1
        handleBulkSongFinished(songID, success: true)
        if !muted {
            VoltaNotificationCenter.shared.post(L(.notif_downloaded, song.title), tone: .success)
        }
    }

    private func prefetchArtwork(for song: Song) {
        guard let client else { return }

        if let cover = song.coverArt, pinnedCovers.insert(cover).inserted {
            // Save the original first so downloaded live covers work offline.
            let originalURL = client.coverArtURL(id: cover)
            let urls = ([originalURL].compactMap { $0 }) + Self.artworkSizes.compactMap { client.coverArtURL(id: cover, size: $0) }
            DeveloperExperiments.launch(priority: .utility) {
                for url in urls { await ArtworkLoader.shared.persist(url) }
            }
        }

        if let artistId = song.artistId, pinnedArtists.insert(artistId).inserted {
            DeveloperExperiments.launch(priority: .utility) { [client] in
                guard let info = try? await client.artistInfo(id: artistId),
                      let urlStr = info.bestImageUrl, let url = URL(string: urlStr) else { return }
                await ArtworkLoader.shared.persistArtistImage(id: artistId, from: url)
            }
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
        observations.removeValue(forKey: songID)
        segmentTasks.removeValue(forKey: songID)
        startTimes.removeValue(forKey: songID)
        pendingResumes.removeValue(forKey: songID)
        mutedCompletionNotifications.remove(songID)
        Task { await Self.progressThrottler.finish(songID) }
        try? FileManager.default.removeItem(at: dest)
        if updateBulk {
            handleBulkSongFinished(songID, success: false)
        }
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
            return client.downloadURL(id: song.id) != nil
        }
        guard !pending.isEmpty else { return }

        bulkQueue = pending
        bulkSongsByID = Dictionary(uniqueKeysWithValues: pending.map { ($0.id, $0) })
        bulkActiveIDs.removeAll()
        bulkCompletedCount = 0
        bulkFailedCount = 0
        bulkSkippedCount = 0
        bulkBytesFinished = 0
        bulkBytesTotal = pending.reduce(0) { $0 + ($1.size ?? 0) }
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
            "Bulk missing-song download queued: total=\(bulkTotalCount), bytes=\(bulkBytesTotal), concurrency=\(bulkConcurrencyLimit)",
            category: .other
        )
        VoltaNotificationCenter.shared.post(L(.notif_downloading_n, pending.count), tone: .success)
        pumpBulkDownloads()
    }

    func pauseBulkDownloads() {
        guard bulkProgress.phase == .running else { return }
        bulkProgress.phase = .paused
        refreshBulkProgress(force: true)
        AppLogger.shared.log("Bulk missing-song download paused: completed=\(bulkCompletedCount)/\(bulkTotalCount), active=\(bulkActiveIDs.count)", category: .other)
    }

    func resumeBulkDownloads() {
        guard bulkProgress.phase == .paused else { return }
        bulkProgress.phase = .running
        AppLogger.shared.log("Bulk missing-song download resumed", category: .other)
        pumpBulkDownloads()
    }

    func cancelBulkDownloads() {
        guard bulkProgress.isRunning else { return }
        let activeSongs = bulkActiveIDs.compactMap { bulkSongsByID[$0] }
        bulkQueue.removeAll()
        for song in activeSongs {
            cancelDownload(for: song, notify: false, updateBulk: false)
        }
        bulkActiveIDs.removeAll()
        finishBulkDownloads(cancelled: true)
    }

    private var bulkConcurrencyLimit: Int {
        DeveloperExperiments.constrainedConcurrency(default: Self.bulkMaxConcurrent)
    }

    private func pumpBulkDownloads() {
        if bulkProgress.phase == .paused {
            if bulkActiveIDs.isEmpty, bulkQueue.isEmpty {
                finishBulkDownloads(cancelled: false)
            } else {
                refreshBulkProgress(force: true)
            }
            return
        }

        guard bulkProgress.phase == .running, let client else {
            refreshBulkProgress(force: true)
            return
        }

        while bulkActiveIDs.count < bulkConcurrencyLimit, !bulkQueue.isEmpty {
            let song = bulkQueue.removeFirst()
            guard case .notDownloaded = state(for: song),
                  let streamURL = client.downloadURL(id: song.id) else {
                bulkSkippedCount += 1
                bulkBytesFinished += song.size ?? 0
                continue
            }
            bulkActiveIDs.insert(song.id)
            startDownload(song: song, streamURL: streamURL, client: client, notifyOnCompletion: false)
        }

        if bulkActiveIDs.isEmpty, bulkQueue.isEmpty {
            finishBulkDownloads(cancelled: false)
        } else {
            refreshBulkProgress(force: true)
        }
    }

    private func handleBulkSongFinished(_ songID: String, success: Bool) {
        guard bulkActiveIDs.remove(songID) != nil else { return }
        if success {
            bulkCompletedCount += 1
            bulkBytesFinished += bulkSongsByID[songID]?.size ?? 0
        } else {
            bulkFailedCount += 1
        }
        pumpBulkDownloads()
    }

    private func refreshBulkProgress(force: Bool) {
        guard bulkProgress.isRunning else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastBulkSnapshotAt) >= 0.25 else { return }
        lastBulkSnapshotAt = now

        let activeFraction = bulkActiveIDs.reduce(0.0) { total, id in
            switch state(forID: id) {
            case .downloading(let progress): return total + progress
            case .downloaded: return total + 1
            case .notDownloaded: return total
            }
        }
        bulkProgress = DownloadBulkProgress(
            phase: bulkProgress.phase,
            total: bulkTotalCount,
            completed: bulkCompletedCount,
            failed: bulkFailedCount,
            skipped: bulkSkippedCount,
            active: bulkActiveIDs.count,
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
            category: .other,
            level: bulkFailedCount > 0 ? .warning : .info
        )

        if cancelled {
            VoltaNotificationCenter.shared.post("Missing song downloads stopped", tone: .warning)
        } else if bulkFailedCount > 0 {
            VoltaNotificationCenter.shared.post("Downloaded \(bulkCompletedCount) missing songs, \(bulkFailedCount) failed", tone: .warning)
        } else {
            VoltaNotificationCenter.shared.post("Downloaded \(bulkCompletedCount) missing songs", tone: .success)
        }

        bulkQueue.removeAll()
        bulkSongsByID.removeAll()
        bulkActiveIDs.removeAll()
        bulkStartedAt = nil
    }

    // MARK: - Manifest

    struct Record: Codable, Sendable {
        let path: String
        var song: Song?
        var lastPlayed: Date?
    }

    @ObservationIgnored private var manifest: [String: Record] = [:]
    @ObservationIgnored private var isReconcilingMetadata = false

    // Derived song lists are rebuilt from the manifest (which means a fileExists
    // syscall per record). Views read these from computed properties many times
    // per render, so memoize per downloadedRevision to keep that work off the
    // main thread's hot path — a stale entry can only exist for one revision.
    @ObservationIgnored private var downloadedSongsCache: (revision: Int, songs: [Song])?
    @ObservationIgnored private var downloadedRecentCache: (revision: Int, songs: [Song])?

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

        for (id, rec) in candidates {
            guard total > capBytes else { break }
            let size = fileSize(rec.path)
            try? FileManager.default.removeItem(atPath: rec.path)
            manifest.removeValue(forKey: id)
            setState(.notDownloaded, forID: id)
            downloadedRevision += 1
            total -= size
            AppLogger.shared.log("Download evicted: '\(rec.song?.title ?? id)' to stay under \(capMB)MB cap", category: .other)
            VoltaNotificationCenter.shared.post(L(.notif_evicted_old_download), tone: .info)
        }
        saveManifest(to: manifestURL)
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
                manifest = legacy.mapValues { Record(path: $0, song: nil) }
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
                    category: .other, level: .error
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
                AppLogger.shared.log("Removed invalid tiny download '\(rec.song?.title ?? id)'", category: .other, level: .warning)
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
            manifest[id] = Record(path: url.path, song: nil)
            setState(.downloaded, forID: id)
            added = true
        }
        if added {
            AppLogger.shared.log("Recovered orphaned downloads from disk; metadata will backfill when online", category: .other)
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
                AppLogger.shared.log("Backfilled metadata for \(filled) recovered download(s)", category: .other)
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

private actor DownloadManifestWriter {
    private var latestSequence = 0

    func save(_ manifest: [String: DownloadService.Record], to url: URL, sequence: Int) {
        guard sequence >= latestSequence else { return }
        latestSequence = sequence
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
