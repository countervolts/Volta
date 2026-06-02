import Foundation
import UIKit

// tracks the download state of a song for UI binding
enum DownloadState: Equatable, Sendable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
}

// thread-safe progress accumulator shared across concurrent segment downloads.
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

// persists downloaded audio files locally for offline playback.
// downloads are stored in Documents/volta-downloads/{songID}.{suffix}
// a manifest.json maps song IDs to their local file paths.
//
// two transfer strategies, chosen by the "downloadThreadingMode" setting:
//   • "multi"  (default) – splits the file into byte-range segments fetched in
//                          parallel, then stitches them together. faster on
//                          high-latency links. falls back to single if the
//                          server ignores Range or the size is unknown.
//   • "single"           – one plain download task with granular progress.
@MainActor
@Observable
final class DownloadService {
    static let shared = DownloadService()

    private(set) var states: [String: DownloadState] = [:]
    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    private var observations: [String: NSKeyValueObservation] = [:]
    private var segmentTasks: [String: Task<Void, Never>] = [:]
    private var client: SubsonicClient?

    private let directory: URL
    private let manifestURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = docs.appendingPathComponent("volta-downloads", isDirectory: true)
        manifestURL = directory.appendingPathComponent("manifest.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        loadManifest()
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
        guard case .notDownloaded = state(for: song) else { return }
        guard let client,
              let streamURL = client.streamURL(id: song.id) else { return }

        states[song.id] = .downloading(progress: 0)

        let songID   = song.id
        let title    = song.title
        let suffix   = song.suffix ?? "mp3"
        let total    = song.size ?? 0
        let destURL  = directory.appendingPathComponent(Self.safeFileName(id: songID, suffix: suffix))
        let manifestURL = manifestURL
        let mode = UserDefaults.standard.string(forKey: "downloadThreadingMode") ?? "multi"

        // multithreaded path needs a known size big enough to be worth splitting.
        if mode != "single", total > 1_048_576 {
            let segments = max(2, min(6, total / (512 * 1024)))
            AppLogger.shared.log("⬇ \(title) — starting (\(segments) segments, \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)))", category: .other)
            // strong capture is safe: DownloadService is a long-lived singleton,
            // and the Task inherits this MainActor so the state mutations below
            // are same-actor calls.
            let task = Task { [self] in
                do {
                    try await DownloadService.downloadSegmented(url: streamURL, total: total, dest: destURL) { progress in
                        await self.report(songID, progress)
                    }
                    AppLogger.shared.log("✓ \(title) — download complete (multithreaded)", category: .other)
                    complete(songID, song: song, path: destURL.path, manifestURL: manifestURL)
                } catch is CancellationError {
                    AppLogger.shared.log("✗ \(title) — cancelled", category: .other)
                    fail(songID, removing: destURL)
                } catch {
                    // server ignored Range or transfer failed → fall back to a
                    // single plain stream so the download still succeeds.
                    AppLogger.shared.log("⚠ \(title) — segmented failed (\(error.localizedDescription)), falling back to single", category: .other, level: .warning)
                    startSingle(song: song, url: streamURL, dest: destURL, manifestURL: manifestURL)
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
        activeTasks[song.id]?.cancel()
        segmentTasks[song.id]?.cancel()
        activeTasks.removeValue(forKey: song.id)
        observations.removeValue(forKey: song.id)
        segmentTasks.removeValue(forKey: song.id)
        states[song.id] = .notDownloaded
    }

    func removeDownload(for song: Song) {
        AppLogger.shared.log("🗑 \(song.title) — download removed", category: .other)
        cancelDownload(for: song)
        if let rec = manifest[song.id] {
            try? FileManager.default.removeItem(atPath: rec.path)
        }
        manifest.removeValue(forKey: song.id)
        saveManifest(to: manifestURL)
    }

    // builds the on-disk filename from a server-supplied song id + suffix.
    // strips path separators so a hostile/buggy server can't use an id like
    // "../../foo" to write outside the downloads directory. the leading
    // "<id>." guarantees the result is never "." or ".." on its own.
    private nonisolated static func safeFileName(id: String, suffix: String) -> String {
        func clean(_ s: String) -> String {
            s.replacingOccurrences(of: "/", with: "_")
             .replacingOccurrences(of: "\\", with: "_")
             .replacingOccurrences(of: "\0", with: "_")
        }
        return "\(clean(id)).\(clean(suffix))"
    }

    // MARK: - Single-threaded transfer (also the multi fallback)

    private func startSingle(song: Song, url: URL, dest: URL, manifestURL: URL) {
        let songID = song.id
        let title = song.title
        let task = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, _, error in
            guard let self else { return }
            if let tempURL, error == nil {
                try? FileManager.default.removeItem(at: dest)
                let moved = (try? FileManager.default.moveItem(at: tempURL, to: dest)) != nil
                Task { @MainActor in
                    if moved {
                        AppLogger.shared.log("✓ \(title) — download complete (single thread)", category: .other)
                        self.complete(songID, song: song, path: dest.path, manifestURL: manifestURL)
                    } else {
                        AppLogger.shared.log("✗ \(title) — failed to save file", category: .other, level: .error)
                        self.fail(songID, removing: dest)
                    }
                }
            } else {
                let msg = error?.localizedDescription ?? "unknown error"
                Task { @MainActor in
                    AppLogger.shared.log("✗ \(title) — download failed: \(msg)", category: .other, level: .error)
                    self.fail(songID, removing: dest)
                }
            }
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

    // MARK: - Multithreaded (segmented) transfer

    private nonisolated static func downloadSegmented(
        url: URL,
        total: Int,
        dest: URL,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws {
        let maxSegments = 6
        let minSegmentSize = 512 * 1024
        let segments = max(2, min(maxSegments, total / minSegmentSize))
        let chunk = total / segments
        let counter = ByteCounter(total: total)

        let parts: [URL] = (0..<segments).map { dest.appendingPathExtension("part\($0)") }
        for p in parts { try? FileManager.default.removeItem(at: p) }

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for i in 0..<segments {
                    let start = i * chunk
                    let end = (i == segments - 1) ? (total - 1) : (start + chunk - 1)
                    let partURL = parts[i]
                    group.addTask {
                        try Task.checkCancellation()
                        var req = URLRequest(url: url)
                        req.timeoutInterval = 60
                        req.cachePolicy = .reloadIgnoringLocalCacheData
                        req.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")

                        let (data, response) = try await URLSession.shared.data(for: req)
                        guard let http = response as? HTTPURLResponse else { throw SegmentError.badResponse }
                        // 206 = partial content. 200 means the server ignored Range
                        // and would send the whole file on every segment.
                        guard http.statusCode == 206 else { throw SegmentError.rangeNotSupported }

                        try data.write(to: partURL, options: .atomic)
                        let p = await counter.add(data.count)
                        await progress(p)
                    }
                }
                try await group.waitForAll()
            }

            // stitch the segments back together in order.
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
            states[songID] = .downloading(progress: min(1.0, progress))
        }
    }

    private func complete(_ songID: String, song: Song, path: String, manifestURL: URL) {
        manifest[songID] = Record(path: path, song: song)
        states[songID] = .downloaded
        activeTasks.removeValue(forKey: songID)
        observations.removeValue(forKey: songID)
        segmentTasks.removeValue(forKey: songID)
        saveManifest(to: manifestURL)
    }

    private func fail(_ songID: String, removing dest: URL) {
        states[songID] = .notDownloaded
        activeTasks.removeValue(forKey: songID)
        observations.removeValue(forKey: songID)
        segmentTasks.removeValue(forKey: songID)
        try? FileManager.default.removeItem(at: dest)
    }

    // MARK: - Manifest

    // each entry keeps the local file path AND the full Song metadata so the
    // library can list downloaded artists/albums/songs/genres offline without
    // re-querying the server.
    struct Record: Codable {
        let path: String
        var song: Song?
    }

    private var manifest: [String: Record] = [:]

    // all songs with a present local file, for the Downloaded library source.
    func downloadedSongs() -> [Song] {
        manifest.values.compactMap { rec in
            guard let song = rec.song,
                  FileManager.default.fileExists(atPath: rec.path) else { return nil }
            return song
        }
    }

    private func loadManifest() {
        guard let data = try? Data(contentsOf: manifestURL) else { return }
        // current format: [id: Record]
        if let decoded = try? JSONDecoder().decode([String: Record].self, from: data) {
            manifest = decoded
        } else if let legacy = try? JSONDecoder().decode([String: String].self, from: data) {
            // migrate old [id: path] manifests (no stored metadata).
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
