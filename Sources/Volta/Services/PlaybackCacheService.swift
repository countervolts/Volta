import Foundation

enum PlaybackCacheSettings {
    static let enabledKey = "enhancedPlaybackCaching"
    static let developerModeKey = "developerPlaybackCacheMode"

    static var isEnabled: Bool {
        if developerMode == .disabled { return false }
        return UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static var developerMode: PlaybackCacheDeveloperMode {
        let raw = UserDefaults.standard.string(forKey: developerModeKey) ?? PlaybackCacheDeveloperMode.followSettings.rawValue
        return PlaybackCacheDeveloperMode(rawValue: raw) ?? .followSettings
    }

    @MainActor
    static var prefetchCount: Int {
        guard isEnabled, !PerformanceMode.disablePrefetch else { return 0 }
        if forcesCellularProfile || NetworkMonitor.shared.connection == .cellular { return 1 }
        switch effectiveCacheMode {
        case "aggressive": return 4
        case "light": return 1
        default: return 3
        }
    }

    @MainActor
    static var maxConcurrentTransfers: Int {
        guard isEnabled else { return 0 }
        if forcesCellularProfile || NetworkMonitor.shared.connection == .cellular { return 1 }
        switch effectiveCacheMode {
        case "aggressive": return 3
        case "light": return 1
        default: return 2
        }
    }

    static var maxBytes: Int {
        guard isEnabled else { return 0 }
        let mb: Int
        switch effectiveCacheMode {
        case "aggressive": mb = 1024
        case "light": mb = 256
        default: mb = 512
        }
        return mb * 1_048_576
    }

    static var effectiveCacheMode: String {
        switch developerMode {
        case .light: return "light"
        case .balanced, .cellular: return "balanced"
        case .aggressive: return "aggressive"
        case .disabled: return "disabled"
        case .followSettings:
            return UserDefaults.standard.string(forKey: "cacheMode") ?? "balanced"
        }
    }

    static var forcesCellularProfile: Bool {
        developerMode == .cellular
    }
}

enum PlaybackCacheDeveloperMode: String, CaseIterable, Identifiable {
    case followSettings = "follow"
    case disabled
    case light
    case balanced
    case aggressive
    case cellular

    var id: String { rawValue }

    var label: String {
        switch self {
        case .followSettings: return "Follow Settings"
        case .disabled: return "Force Off"
        case .light: return "Force Light"
        case .balanced: return "Force Balanced"
        case .aggressive: return "Force Aggressive"
        case .cellular: return "Force Cellular"
        }
    }
}

struct PlaybackCacheDiagnosticsSnapshot {
    var enabled: Bool
    var developerMode: PlaybackCacheDeveloperMode
    var effectiveMode: String
    var network: NetworkMonitor.Connection
    var prefetchCount: Int
    var maxConcurrentTransfers: Int
    var maxBytes: Int
    var bytesOnDisk: Int
    var storedEntries: Int
    var activeTransfers: Int
    var preparingTransfers: Int
    var activeTitles: [String]
    var hits: Int
    var misses: Int
    var started: Int
    var completed: Int
    var failed: Int
    var skipped: Int
    var evicted: Int
    var bytesWritten: Int
    var lastTransferBytes: Int
    var lastTransferSeconds: TimeInterval?
    var lastEvent: String
    var updatedAt: Date

    var hitRate: Double {
        let total = hits + misses
        return total == 0 ? 0 : Double(hits) / Double(total)
    }
}

private struct PlaybackCacheRecord: Codable, Sendable {
    let key: String
    let songID: String
    let title: String
    let path: String
    let bytes: Int
    let createdAt: Date
    var lastAccessed: Date
}

private struct PlaybackCachePersistenceResult: Sendable {
    let succeeded: Bool
    let bytes: Int
    let duration: TimeInterval
}

private struct PlaybackCacheLoadResult: Sendable {
    let manifest: [String: PlaybackCacheRecord]
    let bytesOnDisk: Int
    let duration: TimeInterval
}

/// Owns manifest encoding, disk I/O, and cache-directory cleanup. The player
/// remains main-actor isolated for URLSession task bookkeeping, but it never
/// waits for this actor to touch the filesystem.
private actor PlaybackCachePersistence {
    let directory: URL
    let manifestURL: URL

    init(directory: URL, manifestURL: URL) {
        self.directory = directory
        self.manifestURL = manifestURL
    }

    func load() -> PlaybackCacheLoadResult {
        let startedAt = Date()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var manifest: [String: PlaybackCacheRecord] = [:]
        if let data = try? Data(contentsOf: manifestURL),
           let decoded = try? JSONDecoder().decode([String: PlaybackCacheRecord].self, from: data) {
            manifest = decoded
        }

        let missing = manifest.compactMap { key, record in
            FileManager.default.fileExists(atPath: record.path) ? nil : key
        }
        for key in missing { manifest.removeValue(forKey: key) }

        let known = Set(manifest.values.map(\.path) + [manifestURL.path])
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            for url in entries where !known.contains(url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }

        if !missing.isEmpty {
            _ = save(manifest)
        }
        return PlaybackCacheLoadResult(
            manifest: manifest,
            bytesOnDisk: directorySize(excluding: manifestURL.lastPathComponent),
            duration: Date().timeIntervalSince(startedAt)
        )
    }

    func save(_ manifest: [String: PlaybackCacheRecord]) -> PlaybackCachePersistenceResult {
        let startedAt = Date()
        guard let data = try? JSONEncoder().encode(manifest) else {
            return PlaybackCachePersistenceResult(
                succeeded: false,
                bytes: 0,
                duration: Date().timeIntervalSince(startedAt)
            )
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: manifestURL, options: .atomic)
            return PlaybackCachePersistenceResult(
                succeeded: true,
                bytes: data.count,
                duration: Date().timeIntervalSince(startedAt)
            )
        } catch {
            return PlaybackCachePersistenceResult(
                succeeded: false,
                bytes: data.count,
                duration: Date().timeIntervalSince(startedAt)
            )
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func directorySize(excluding excludedName: String) -> Int {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        return entries
            .filter { $0.lastPathComponent != excludedName }
            .reduce(0) { total, url in
                total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
    }
}

@MainActor
final class PlaybackCacheService {
    static let shared = PlaybackCacheService()

    private let directory: URL
    private let manifestURL: URL
    private let persistence: PlaybackCachePersistence
    private var manifest: [String: PlaybackCacheRecord] = [:]
    private var manifestLoadTask: Task<Void, Never>?
    private var pendingManifestSaveTask: Task<Void, Never>?
    private var manifestGeneration: UInt64 = 0
    private var didClearBeforeManifestLoad = false
    private var bytesOnDisk = 0
    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    private var activeTitles: [String: String] = [:]
    private var transferStartedAt: [String: Date] = [:]
    private var preparingSongIDs: Set<String> = []
    private var prepareTokens: [String: UUID] = [:]
    private var generation: UInt64 = 0
    private var hits = 0
    private var misses = 0
    private var started = 0
    private var completed = 0
    private var failed = 0
    private var skipped = 0
    private var evicted = 0
    private var bytesWritten = 0
    private var lastTransferBytes = 0
    private var lastTransferSeconds: TimeInterval?
    private var lastEvent = "Ready"
    private var lastUpdatedAt = Date()

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = caches.appendingPathComponent("playback-cache", isDirectory: true)
        let manifestURL = directory.appendingPathComponent("manifest.json")
        self.directory = directory
        self.manifestURL = manifestURL
        let persistence = PlaybackCachePersistence(directory: directory, manifestURL: manifestURL)
        self.persistence = persistence
        self.manifestLoadTask = nil
        self.pendingManifestSaveTask = nil
        self.manifestLoadTask = Task { @MainActor [weak self, persistence] in
            let loaded = await persistence.load()
            guard let self else { return }
            let hadMutation = self.manifestGeneration != 0
            if !hadMutation {
                self.manifest = loaded.manifest
            } else if !self.didClearBeforeManifestLoad {
                var merged = loaded.manifest
                for (key, record) in self.manifest { merged[key] = record }
                self.manifest = merged
            }
            if !self.didClearBeforeManifestLoad {
                self.bytesOnDisk = loaded.bytesOnDisk
            }
            self.manifestLoadTask = nil
            if loaded.duration >= 0.1 {
                let duration = String(format: "%.0f", loaded.duration * 1_000)
                AppLogger.shared.log(
                    "Playback cache manifest load took \(duration)ms; entries=\(loaded.manifest.count); bytes=\(loaded.bytesOnDisk)",
                    category: .playback,
                    level: .warning
                )
            }
            if hadMutation && !self.didClearBeforeManifestLoad {
                self.saveManifest()
            }
        }
    }

    func cachedURL(for song: Song, client: any MusicService) -> URL? {
        guard PlaybackCacheSettings.isEnabled,
              let streamURL = client.streamURL(for: song) else { return nil }
        let key = cacheKey(for: streamURL)
        guard var record = manifest[key] else {
            misses += 1
            lastUpdatedAt = Date()
            return nil
        }
        let url = URL(fileURLWithPath: record.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            manifest.removeValue(forKey: key)
            bytesOnDisk = max(0, bytesOnDisk - record.bytes)
            saveManifest()
            misses += 1
            recordEvent("Cache miss: file missing for \(song.title)")
            return nil
        }
        record.lastAccessed = Date()
        manifest[key] = record
        saveManifest()
        hits += 1
        recordEvent("Cache hit: \(song.title)")
        return url
    }

    // Read-only cache probe for background analyzers. Avoids rewriting cache
    // manifest every time planning asks for same track source.
    func analysisURL(for song: Song, client: any MusicService) -> URL? {
        guard PlaybackCacheSettings.isEnabled,
              let streamURL = client.streamURL(for: song),
              let record = manifest[cacheKey(for: streamURL)] else { return nil }
        let url = URL(fileURLWithPath: record.path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func prefetch(_ songs: [Song], client: any MusicService) {
        let limit = PlaybackCacheSettings.prefetchCount
        guard limit > 0,
              NetworkMonitor.shared.connection != .none,
              !DemoServers.isDemo(client.config.baseURL) else {
            if !songs.isEmpty { recordEvent("Prefetch skipped: disabled, offline, or demo server") }
            return
        }

        var seen: Set<String> = []
        let candidates = songs.filter { seen.insert($0.id).inserted }.prefix(limit)
        for song in candidates {
            guard activeTasks.count < PlaybackCacheSettings.maxConcurrentTransfers else { break }
            startPrefetch(song: song, client: client)
        }
    }

    func cancelPrefetches() {
        generation &+= 1
        for task in activeTasks.values { task.cancel() }
        activeTasks.removeAll()
        activeTitles.removeAll()
        transferStartedAt.removeAll()
        preparingSongIDs.removeAll()
        prepareTokens.removeAll()
        recordEvent("Playback cache prefetches cancelled")
    }

    func cancelPrefetch(for song: Song, client: any MusicService) {
        preparingSongIDs.remove(song.id)
        prepareTokens.removeValue(forKey: song.id)
        guard let streamURL = client.streamURL(for: song) else { return }
        let key = cacheKey(for: streamURL)
        activeTasks[key]?.cancel()
        activeTasks.removeValue(forKey: key)
        activeTitles.removeValue(forKey: key)
        transferStartedAt.removeValue(forKey: key)
    }

    func clear() {
        cancelPrefetches()
        manifest.removeAll()
        bytesOnDisk = 0
        manifestGeneration &+= 1
        didClearBeforeManifestLoad = true
        pendingManifestSaveTask?.cancel()
        let persistence = self.persistence
        Task { @MainActor in
            await persistence.clear()
        }
        recordEvent("Playback cache cleared")
        AppLogger.shared.log("Playback cache cleared by user", category: .playback)
    }

    func totalBytes() -> Int {
        bytesOnDisk
    }

    func diagnostics() -> PlaybackCacheDiagnosticsSnapshot {
        PlaybackCacheDiagnosticsSnapshot(
            enabled: PlaybackCacheSettings.isEnabled,
            developerMode: PlaybackCacheSettings.developerMode,
            effectiveMode: PlaybackCacheSettings.effectiveCacheMode,
            network: NetworkMonitor.shared.connection,
            prefetchCount: PlaybackCacheSettings.prefetchCount,
            maxConcurrentTransfers: PlaybackCacheSettings.maxConcurrentTransfers,
            maxBytes: PlaybackCacheSettings.maxBytes,
            bytesOnDisk: totalBytes(),
            storedEntries: manifest.count,
            activeTransfers: activeTasks.count,
            preparingTransfers: preparingSongIDs.count,
            activeTitles: activeTitles.values.sorted(),
            hits: hits,
            misses: misses,
            started: started,
            completed: completed,
            failed: failed,
            skipped: skipped,
            evicted: evicted,
            bytesWritten: bytesWritten,
            lastTransferBytes: lastTransferBytes,
            lastTransferSeconds: lastTransferSeconds,
            lastEvent: lastEvent,
            updatedAt: lastUpdatedAt
        )
    }

    func resetDiagnostics() {
        hits = 0
        misses = 0
        started = 0
        completed = 0
        failed = 0
        skipped = 0
        evicted = 0
        bytesWritten = 0
        lastTransferBytes = 0
        lastTransferSeconds = nil
        recordEvent("Diagnostics reset")
    }

    func prefetchForDiagnostics(_ songs: [Song], client: any MusicService, count: Int) {
        guard PlaybackCacheSettings.isEnabled,
              NetworkMonitor.shared.connection != .none,
              !DemoServers.isDemo(client.config.baseURL) else {
            recordEvent("Diagnostic prefetch skipped: disabled, offline, or demo server")
            return
        }
        var seen: Set<String> = []
        let candidates = songs.filter { seen.insert($0.id).inserted }.prefix(max(1, count))
        for song in candidates {
            guard activeTasks.count < PlaybackCacheSettings.maxConcurrentTransfers else { break }
            startPrefetch(song: song, client: client)
        }
    }

    func isCached(_ song: Song, client: any MusicService) -> Bool {
        guard let streamURL = client.streamURL(for: song) else { return false }
        let key = cacheKey(for: streamURL)
        guard let record = manifest[key] else { return false }
        return FileManager.default.fileExists(atPath: record.path)
    }

    private func startPrefetch(song: Song, client: any MusicService) {
        guard PlaybackCacheSettings.isEnabled,
              DownloadService.shared.localURL(for: song) == nil,
              case .notDownloaded = DownloadService.shared.state(for: song),
              preparingSongIDs.insert(song.id).inserted else {
            skipped += 1
            recordEvent("Prefetch skipped: \(song.title)")
            return
        }

        let generationToken = generation
        let prepareToken = UUID()
        prepareTokens[song.id] = prepareToken
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.prepareTokens[song.id] == prepareToken {
                    self.prepareTokens.removeValue(forKey: song.id)
                    self.preparingSongIDs.remove(song.id)
                }
            }
            if !client.streamMetadataReady(for: song) {
                await client.prepareForPlayback(song: song)
            }
            guard !Task.isCancelled,
                  generationToken == self.generation,
                  self.prepareTokens[song.id] == prepareToken,
                  PlaybackCacheSettings.isEnabled,
                  DownloadService.shared.localURL(for: song) == nil,
                  case .notDownloaded = DownloadService.shared.state(for: song),
                  let streamURL = client.streamURL(for: song) else { return }

            let key = self.cacheKey(for: streamURL)
            guard self.cachedFileExists(forKey: key) == false,
                  self.activeTasks[key] == nil,
                  self.activeTasks.count < PlaybackCacheSettings.maxConcurrentTransfers else {
                self.skipped += 1
                self.recordEvent("Prefetch skipped: \(song.title)")
                return
            }
            self.startTransfer(song: song, url: streamURL, key: key, headers: client.mediaRequestHeaders())
        }
    }

    private func startTransfer(song: Song, url: URL, key: String, headers: [String: String]) {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let cacheDirectory = directory
        let task = URLSession.shared.downloadTask(with: request) { [weak self] tempURL, response, error in
            guard let self else { return }
            if let tempURL, error == nil {
                if let failure = Self.validationFailure(tempURL: tempURL, response: response) {
                    try? FileManager.default.removeItem(at: tempURL)
                    Task { @MainActor in
                        self.activeTasks.removeValue(forKey: key)
                        self.activeTitles.removeValue(forKey: key)
                        self.transferStartedAt.removeValue(forKey: key)
                        self.skipped += 1
                        self.recordEvent("Playback cache skipped '\(song.title)': \(failure)")
                        AppLogger.shared.log("Playback cache skipped '\(song.title)': \(failure)", category: .playback, level: .warning)
                    }
                    return
                }

                let dest = Self.destinationURL(directory: cacheDirectory, song: song, sourceURL: url, response: response, key: key)
                try? FileManager.default.removeItem(at: dest)
                let moved = (try? FileManager.default.moveItem(at: tempURL, to: dest)) != nil
                let bytes = Self.fileSize(at: dest)
                Task { @MainActor in
                    self.activeTasks.removeValue(forKey: key)
                    self.activeTitles.removeValue(forKey: key)
                    guard moved, bytes > 0 else {
                        try? FileManager.default.removeItem(at: dest)
                        self.failed += 1
                        self.transferStartedAt.removeValue(forKey: key)
                        self.recordEvent("Playback cache failed to store '\(song.title)'")
                        return
                    }
                    self.complete(song: song, key: key, path: dest.path, bytes: bytes)
                }
            } else {
                Task { @MainActor in
                    self.activeTasks.removeValue(forKey: key)
                    self.activeTitles.removeValue(forKey: key)
                    self.transferStartedAt.removeValue(forKey: key)
                    guard (error as NSError?)?.code != NSURLErrorCancelled else { return }
                    if let error {
                        self.failed += 1
                        self.recordEvent("Playback cache failed '\(song.title)': \(error.localizedDescription)")
                        AppLogger.shared.log("Playback cache failed '\(song.title)': \(error.localizedDescription)", category: .playback, level: .warning)
                    }
                }
            }
        }

        activeTasks[key] = task
        activeTitles[key] = song.title
        transferStartedAt[key] = Date()
        started += 1
        recordEvent("Playback cache prefetch started: \(song.title)")
        task.resume()
        AppLogger.shared.log("Playback cache prefetch started: '\(song.title)'", category: .playback)
    }

    private func complete(song: Song, key: String, path: String, bytes: Int) {
        let now = Date()
        let elapsed = transferStartedAt.removeValue(forKey: key).map { now.timeIntervalSince($0) }
        manifest[key] = PlaybackCacheRecord(
            key: key,
            songID: song.id,
            title: song.title,
            path: path,
            bytes: bytes,
            createdAt: now,
            lastAccessed: now
        )
        bytesOnDisk += bytes
        saveManifest()
        enforceLimit(keeping: key)
        completed += 1
        bytesWritten += bytes
        lastTransferBytes = bytes
        lastTransferSeconds = elapsed
        recordEvent("Playback cache stored: \(song.title)")
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        AppLogger.shared.log("Playback cache stored: '\(song.title)' (\(size))", category: .playback)
    }

    private func cachedFileExists(forKey key: String) -> Bool {
        guard let record = manifest[key] else { return false }
        if FileManager.default.fileExists(atPath: record.path) { return true }
        manifest.removeValue(forKey: key)
        bytesOnDisk = max(0, bytesOnDisk - record.bytes)
        saveManifest()
        return false
    }

    private func enforceLimit(keeping protectedKey: String?) {
        let maxBytes = PlaybackCacheSettings.maxBytes
        guard maxBytes > 0 else { return }
        var total = bytesOnDisk
        guard total > maxBytes else { return }

        let active = Set(activeTasks.keys)
        let candidates = manifest.values
            .filter { $0.key != protectedKey && !active.contains($0.key) }
            .sorted { $0.lastAccessed < $1.lastAccessed }

        var changed = false
        for record in candidates {
            guard total > maxBytes else { break }
            let bytes = record.bytes
            try? FileManager.default.removeItem(atPath: record.path)
            manifest.removeValue(forKey: record.key)
            total -= bytes
            changed = true
            evicted += 1
            recordEvent("Playback cache evicted: \(record.title)")
            AppLogger.shared.log("Playback cache evicted: '\(record.title)'", category: .playback)
        }
        bytesOnDisk = max(0, total)
        if changed { saveManifest() }
    }

    private func saveManifest() {
        manifestGeneration &+= 1
        let generation = manifestGeneration
        let snapshot = manifest
        pendingManifestSaveTask?.cancel()
        let persistence = self.persistence
        pendingManifestSaveTask = Task { @MainActor [weak self, persistence] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            let result = await persistence.save(snapshot)
            guard let self, self.manifestGeneration == generation else { return }
            if result.duration >= 0.1 {
                AppLogger.shared.log(
                    "Playback cache manifest persistence took \(String(format: "%.0f", result.duration * 1_000))ms; entries=\(snapshot.count); bytes=\(result.bytes); success=\(result.succeeded)",
                    category: .playback,
                    level: result.succeeded ? .info : .warning
                )
            }
        }
    }

    private func recordEvent(_ text: String) {
        lastEvent = text
        lastUpdatedAt = Date()
    }

    private func cacheKey(for url: URL) -> String {
        Crypto.md5Hex(url.absoluteString)
    }

    private nonisolated static func destinationURL(directory: URL, song: Song, sourceURL: URL, response: URLResponse?, key: String) -> URL {
        let ext = Self.fileExtension(for: song, sourceURL: sourceURL, response: response)
        return directory.appendingPathComponent("\(key).\(ext)")
    }

    private nonisolated static func fileExtension(for song: Song, sourceURL: URL, response: URLResponse?) -> String {
        if let suggested = response?.suggestedFilename {
            let ext = (suggested as NSString).pathExtension.lowercased()
            if isSafeExtension(ext) { return ext }
        }
        let urlExt = sourceURL.pathExtension.lowercased()
        if isSafeExtension(urlExt) { return urlExt }
        let songExt = song.suffix?.lowercased() ?? ""
        if isSafeExtension(songExt) { return songExt }
        let mime = response?.mimeType?.lowercased() ?? ""
        if mime.contains("mpeg") { return "mp3" }
        if mime.contains("aac") { return "aac" }
        if mime.contains("flac") { return "flac" }
        if mime.contains("opus") { return "opus" }
        if mime.contains("ogg") { return "ogg" }
        if mime.contains("wav") { return "wav" }
        return "m4a"
    }

    private nonisolated static func isSafeExtension(_ ext: String) -> Bool {
        ["aac", "aif", "aiff", "alac", "flac", "m4a", "mp3", "ogg", "opus", "wav", "webma"].contains(ext)
    }

    private nonisolated static func validationFailure(tempURL: URL, response: URLResponse?) -> String? {
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            return "HTTP \(http.statusCode)"
        }

        let mime = response?.mimeType?.lowercased() ?? ""
        if mime.contains("mpegurl") || mime.contains("m3u") {
            return "HLS playlists are streamed directly"
        }
        if mime.contains("text") || mime.contains("json") || mime.contains("html") {
            return "server returned \(mime)"
        }

        let bytes = fileSize(at: tempURL)
        if bytes < 1_024 {
            return "response was only \(bytes) bytes"
        }

        if let preview = smallTextPreview(at: tempURL),
           preview.hasPrefix("#EXTM3U") || preview.localizedCaseInsensitiveContains("<html") {
            return "server returned a playlist or error page"
        }

        return nil
    }

    private nonisolated static func smallTextPreview(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 4_096)
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    private nonisolated static func fileSize(at url: URL) -> Int {
        fileSize(atPath: url.path)
    }

    private nonisolated static func fileSize(atPath path: String) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
    }

}
