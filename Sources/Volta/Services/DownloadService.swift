import Foundation
import UIKit

enum DownloadState: Equatable, Sendable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
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

private struct PendingDownloadResume {
    let song: Song
    let url: URL
    let dest: URL
    let manifestURL: URL
    let resumeData: Data?
}

@MainActor
@Observable
final class DownloadService {
    static let shared = DownloadService()

    private(set) var states: [String: DownloadState] = [:]
    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    private var observations: [String: NSKeyValueObservation] = [:]
    private var segmentTasks: [String: Task<Void, Never>] = [:]
    private var startTimes: [String: Date] = [:]
    private var lastProgress: [String: Double] = [:]
    private var pendingResumes: [String: PendingDownloadResume] = [:]
    private var userCancelledDownloads: Set<String> = []
    private var client: SubsonicClient?

    private var pinnedCovers: Set<String> = []
    private var pinnedArtists: Set<String> = []

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

    func updateClient(_ client: SubsonicClient?) {
        self.client = client
    }

    func state(for song: Song) -> DownloadState {
        states[song.id] ?? .notDownloaded
    }

    func localURL(for song: Song) -> URL? {
        guard let rec = manifest[song.id] else { return nil }
        let url = URL(fileURLWithPath: rec.path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func download(song: Song) {
        if pendingResumes[song.id] != nil {
            resumePendingDownload(id: song.id)
            return
        }
        guard case .notDownloaded = state(for: song) else { return }
        guard let client,
              let streamURL = client.downloadURL(id: song.id) else { return }

        states[song.id] = .downloading(progress: 0)
        startTimes[song.id] = Date()
        lastProgress[song.id] = 0
        userCancelledDownloads.remove(song.id)
        prefetchArtwork(for: song)

        let songID   = song.id
        let title    = song.title
        let suffix   = song.suffix ?? "mp3"
        let total    = song.size ?? 0
        let destURL  = directory.appendingPathComponent(Self.safeFileName(id: songID, suffix: suffix))
        let manifestURL = manifestURL
        let mode = UserDefaults.standard.string(forKey: "downloadThreadingMode") ?? "multi"

        let speedLimit = UserDefaults.standard.integer(forKey: "downloadSpeedLimitKBps") * 1024

        if total > 0, (mode != "single" && total > 1_048_576) || speedLimit > 0 {
            let segments = max(2, min(6, total / (512 * 1024)))
            AppLogger.shared.log("⬇ \(title) — starting (\(segments) segments, \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file))\(speedLimit > 0 ? ", limited" : ""))", category: .other)
            let task = Task { [self] in
                do {
                    try await DownloadService.downloadSegmented(url: streamURL, title: title, total: total, dest: destURL, speedLimit: speedLimit) { progress in
                        await self.report(songID, progress)
                    }
                    complete(songID, song: song, path: destURL.path, manifestURL: manifestURL, method: "multithreaded")
                } catch is CancellationError {
                    AppLogger.shared.log("✗ \(title) — cancelled", category: .other)
                    fail(songID, removing: destURL)
                } catch {
                    if DownloadService.isTransientNetworkError(error) {
                        pauseForResume(song: song, url: streamURL, dest: destURL, manifestURL: manifestURL, resumeData: nil)
                    } else {
                        AppLogger.shared.log("⚠ \(title) — segmented failed (\(error.localizedDescription)), falling back to single", category: .other, level: .warning)
                        startSingle(song: song, url: streamURL, dest: destURL, manifestURL: manifestURL)
                    }
                }
            }
            segmentTasks[songID] = task
        } else {
            AppLogger.shared.log("⬇ \(title) — starting (single thread\(total > 0 ? ", \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file))" : ""))", category: .other)
            startSingle(song: song, url: streamURL, dest: destURL, manifestURL: manifestURL)
        }
    }

    func cancelDownload(for song: Song) {
        AppLogger.shared.log("✗ \(song.title) — download cancelled", category: .other)
        if case .downloading = state(for: song) {
            VoltaNotificationCenter.shared.post("Download cancelled", tone: .warning)
        }
        userCancelledDownloads.insert(song.id)
        activeTasks[song.id]?.cancel()
        segmentTasks[song.id]?.cancel()
        activeTasks.removeValue(forKey: song.id)
        observations.removeValue(forKey: song.id)
        segmentTasks.removeValue(forKey: song.id)
        startTimes.removeValue(forKey: song.id)
        lastProgress.removeValue(forKey: song.id)
        pendingResumes.removeValue(forKey: song.id)
        states[song.id] = .notDownloaded
    }

    func removeDownload(for song: Song) {
        AppLogger.shared.log("🗑 \(song.title) — download removed", category: .other)
        VoltaNotificationCenter.shared.post("Download removed", tone: .info)
        cancelDownload(for: song)
        if let rec = manifest[song.id] {
            try? FileManager.default.removeItem(atPath: rec.path)
        }
        manifest.removeValue(forKey: song.id)
        saveManifest(to: manifestURL)
        unpinOrphanedArtwork(after: song)
    }

    private func unpinOrphanedArtwork(after song: Song) {
        let remaining = downloadedSongs()
        if let cover = song.coverArt, !remaining.contains(where: { $0.coverArt == cover }) {
            pinnedCovers.remove(cover)
            let urls = Self.artworkSizes.compactMap { client?.coverArtURL(id: cover, size: $0) }
            Task.detached(priority: .utility) { await ArtworkLoader.shared.unpin(urls) }
        }
        if let artistId = song.artistId, !remaining.contains(where: { $0.artistId == artistId }) {
            pinnedArtists.remove(artistId)
            Task.detached(priority: .utility) { await ArtworkLoader.shared.unpinArtist(id: artistId) }
        }
    }

    // Avoid letting a server-supplied song id become a path.
    private nonisolated static func safeFileName(id: String, suffix: String) -> String {
        func clean(_ s: String) -> String {
            s.replacingOccurrences(of: "/", with: "_")
             .replacingOccurrences(of: "\\", with: "_")
             .replacingOccurrences(of: "\0", with: "_")
        }
        return "\(clean(id)).\(clean(suffix))"
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

    private func startSingle(song: Song, url: URL, dest: URL, manifestURL: URL) {
        startSingle(song: song, url: url, dest: dest, manifestURL: manifestURL, resumeData: nil)
    }

    private func startSingle(song: Song, url: URL, dest: URL, manifestURL: URL, resumeData: Data?) {
        let songID = song.id
        let title = song.title
        let task: URLSessionDownloadTask
        let completion: @Sendable (URL?, URLResponse?, Error?) -> Void = { [weak self] tempURL, _, error in
            guard let self else { return }
            if let tempURL, error == nil {
                try? FileManager.default.removeItem(at: dest)
                let moved = (try? FileManager.default.moveItem(at: tempURL, to: dest)) != nil
                Task { @MainActor in
                    if moved {
                        self.complete(songID, song: song, path: dest.path, manifestURL: manifestURL, method: "single thread")
                    } else {
                        AppLogger.shared.log("✗ \(title) — failed to save file", category: .other, level: .error)
                        self.fail(songID, removing: dest)
                    }
                }
            } else {
                let msg = error?.localizedDescription ?? "unknown error"
                Task { @MainActor in
                    if self.userCancelledDownloads.remove(songID) != nil {
                        AppLogger.shared.log("✗ \(title) — cancelled", category: .other)
                        self.fail(songID, removing: dest)
                        return
                    }
                    let resumeData = DownloadService.resumeData(from: error)
                    if resumeData != nil || DownloadService.isTransientNetworkError(error) {
                        self.pauseForResume(song: song, url: url, dest: dest, manifestURL: manifestURL, resumeData: resumeData)
                    } else {
                        AppLogger.shared.log("✗ \(title) — download failed: \(msg)", category: .other, level: .error)
                        self.fail(songID, removing: dest)
                    }
                }
            }
        }
        if let resumeData {
            task = URLSession.shared.downloadTask(withResumeData: resumeData, completionHandler: completion)
        } else {
            task = URLSession.shared.downloadTask(with: url, completionHandler: completion)
        }

        let obs = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Task { @MainActor [weak self] in
                self?.report(songID, progress.fractionCompleted)
            }
        }
        observations[songID] = obs
        activeTasks[songID] = task
        task.resume()
    }

    private func pauseForResume(song: Song, url: URL, dest: URL, manifestURL: URL, resumeData: Data?) {
        let songID = song.id
        activeTasks.removeValue(forKey: songID)
        observations.removeValue(forKey: songID)
        segmentTasks.removeValue(forKey: songID)
        pendingResumes[songID] = PendingDownloadResume(
            song: song,
            url: url,
            dest: dest,
            manifestURL: manifestURL,
            resumeData: resumeData
        )
        let progress = lastProgress[songID] ?? 0
        states[songID] = .downloading(progress: progress)
        AppLogger.shared.log("⏸ \(song.title) — connection lost, will resume when network returns", category: .other, level: .warning)
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
        AppLogger.shared.log("↻ \(pending.song.title) — resuming download", category: .other)
        startSingle(
            song: pending.song,
            url: pending.url,
            dest: pending.dest,
            manifestURL: pending.manifestURL,
            resumeData: pending.resumeData
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
            AppLogger.shared.log("↳ \(title) — segment \(i + 1)/\(segments) done (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))", category: .other)
            return data.count
        }

        do {
            if speedLimit > 0 {
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

            AppLogger.shared.log("🧵 \(title) — stitching \(segments) segments", category: .other)
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

    private func report(_ songID: String, _ progress: Double) {
        if case .downloading = states[songID] {
            let clamped = min(1.0, max(0, progress))
            lastProgress[songID] = clamped
            states[songID] = .downloading(progress: clamped)
        }
    }

    private func complete(_ songID: String, song: Song, path: String, manifestURL: URL, method: String) {
        manifest[songID] = Record(path: path, song: song, lastPlayed: nil)
        states[songID] = .downloaded
        activeTasks.removeValue(forKey: songID)
        observations.removeValue(forKey: songID)
        segmentTasks.removeValue(forKey: songID)
        pendingResumes.removeValue(forKey: songID)
        lastProgress.removeValue(forKey: songID)
        userCancelledDownloads.remove(songID)
        saveManifest(to: manifestURL)
        enforceStorageCap(keeping: songID)

        let bytes = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        let elapsed = startTimes.removeValue(forKey: songID).map { Date().timeIntervalSince($0) } ?? 0
        let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        if elapsed > 0.05, bytes > 0 {
            let speedStr = ByteCountFormatter.string(fromByteCount: Int64(Double(bytes) / elapsed), countStyle: .file)
            AppLogger.shared.log("✓ \(song.title) — complete (\(method), \(sizeStr) in \(String(format: "%.1f", elapsed))s · avg \(speedStr)/s)", category: .other)
        } else {
            AppLogger.shared.log("✓ \(song.title) — complete (\(method), \(sizeStr))", category: .other)
        }
        VoltaNotificationCenter.shared.post("Downloaded \(song.title)", tone: .success)
    }

    private func prefetchArtwork(for song: Song) {
        guard let client else { return }

        if let cover = song.coverArt, pinnedCovers.insert(cover).inserted {
            let urls = Self.artworkSizes.compactMap { client.coverArtURL(id: cover, size: $0) }
            Task.detached(priority: .utility) {
                for url in urls { await ArtworkLoader.shared.persist(url) }
            }
        }

        if let artistId = song.artistId, pinnedArtists.insert(artistId).inserted {
            Task.detached(priority: .utility) { [client] in
                guard let info = try? await client.artistInfo(id: artistId),
                      let urlStr = info.bestImageUrl, let url = URL(string: urlStr) else { return }
                await ArtworkLoader.shared.persistArtistImage(id: artistId, from: url)
            }
        }
    }

    private func fail(_ songID: String, removing dest: URL) {
        states[songID] = .notDownloaded
        activeTasks.removeValue(forKey: songID)
        observations.removeValue(forKey: songID)
        segmentTasks.removeValue(forKey: songID)
        startTimes.removeValue(forKey: songID)
        pendingResumes.removeValue(forKey: songID)
        lastProgress.removeValue(forKey: songID)
        userCancelledDownloads.remove(songID)
        try? FileManager.default.removeItem(at: dest)
    }

    // MARK: - Manifest

    struct Record: Codable {
        let path: String
        var song: Song?
        var lastPlayed: Date?
    }

    private var manifest: [String: Record] = [:]

    // MARK: - Storage cap / LRU eviction

    func markPlayed(_ songID: String) {
        guard manifest[songID] != nil else { return }
        manifest[songID]?.lastPlayed = .now
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
            .filter { $0.key != protectedID && states[$0.key] == .downloaded }
            .sorted { ($0.value.lastPlayed ?? .distantPast) < ($1.value.lastPlayed ?? .distantPast) }

        for (id, rec) in candidates {
            guard total > capBytes else { break }
            let size = fileSize(rec.path)
            try? FileManager.default.removeItem(atPath: rec.path)
            manifest.removeValue(forKey: id)
            states[id] = .notDownloaded
            total -= size
            AppLogger.shared.log("🗑 Evicted '\(rec.song?.title ?? id)' to stay under \(capMB)MB cap", category: .other)
            VoltaNotificationCenter.shared.post("Evicted old download", tone: .info)
        }
        saveManifest(to: manifestURL)
    }

    func downloadedSongs() -> [Song] {
        manifest.values.compactMap { rec in
            guard let song = rec.song,
                  FileManager.default.fileExists(atPath: rec.path) else { return nil }
            return song
        }
    }

    private func loadManifest() {
        guard let data = try? Data(contentsOf: manifestURL) else { return }
        if let decoded = try? JSONDecoder().decode([String: Record].self, from: data) {
            manifest = decoded
        } else if let legacy = try? JSONDecoder().decode([String: String].self, from: data) {
            manifest = legacy.mapValues { Record(path: $0, song: nil) }
        }
        for (id, rec) in manifest {
            if FileManager.default.fileExists(atPath: rec.path) {
                states[id] = .downloaded
            }
        }
    }

    private func saveManifest(to url: URL) {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
