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

@MainActor
final class PlaybackCacheService {
    static let shared = PlaybackCacheService()

    private struct Record: Codable {
        let key: String
        let songID: String
        let title: String
        let path: String
        let bytes: Int
        let createdAt: Date
        var lastAccessed: Date
    }

    private let directory: URL
    private let manifestURL: URL
    private var manifest: [String: Record] = [:]
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
        directory = caches.appendingPathComponent("playback-cache", isDirectory: true)
        manifestURL = directory.appendingPathComponent("manifest.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        loadManifest()
    }

    func cachedURL(for song: Song, client: any MusicService) -> URL? {
        guard PlaybackCacheSettings.isEnabled,
              let streamURL = client.streamURL(id: song.id) else { return nil }
        let key = cacheKey(for: streamURL)
        guard var record = manifest[key] else {
            misses += 1
            lastUpdatedAt = Date()
            return nil
        }
        let url = URL(fileURLWithPath: record.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            manifest.removeValue(forKey: key)
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
        guard let streamURL = client.streamURL(id: song.id) else { return }
        let key = cacheKey(for: streamURL)
        activeTasks[key]?.cancel()
        activeTasks.removeValue(forKey: key)
        activeTitles.removeValue(forKey: key)
        transferStartedAt.removeValue(forKey: key)
    }

    func clear() {
        cancelPrefetches()
        manifest.removeAll()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        recordEvent("Playback cache cleared")
        AppLogger.shared.log("Playback cache cleared by user", category: .other)
    }

    func totalBytes() -> Int {
        Self.directorySize(at: directory, excluding: [manifestURL.lastPathComponent])
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
        guard let streamURL = client.streamURL(id: song.id) else { return false }
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
            if !client.streamMetadataReady(id: song.id) {
                await client.prepareForPlayback(id: song.id)
            }
            guard !Task.isCancelled,
                  generationToken == self.generation,
                  self.prepareTokens[song.id] == prepareToken,
                  PlaybackCacheSettings.isEnabled,
                  DownloadService.shared.localURL(for: song) == nil,
                  case .notDownloaded = DownloadService.shared.state(for: song),
                  let streamURL = client.streamURL(id: song.id) else { return }

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
        manifest[key] = Record(
            key: key,
            songID: song.id,
            title: song.title,
            path: path,
            bytes: bytes,
            createdAt: now,
            lastAccessed: now
        )
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
        saveManifest()
        return false
    }

    private func enforceLimit(keeping protectedKey: String?) {
        let maxBytes = PlaybackCacheSettings.maxBytes
        guard maxBytes > 0 else { return }
        var total = manifest.values.reduce(0) { $0 + Self.fileSize(atPath: $1.path) }
        guard total > maxBytes else { return }

        let active = Set(activeTasks.keys)
        let candidates = manifest.values
            .filter { $0.key != protectedKey && !active.contains($0.key) }
            .sorted { $0.lastAccessed < $1.lastAccessed }

        var changed = false
        for record in candidates {
            guard total > maxBytes else { break }
            let bytes = Self.fileSize(atPath: record.path)
            try? FileManager.default.removeItem(atPath: record.path)
            manifest.removeValue(forKey: record.key)
            total -= bytes
            changed = true
            evicted += 1
            recordEvent("Playback cache evicted: \(record.title)")
            AppLogger.shared.log("Playback cache evicted: '\(record.title)'", category: .playback)
        }
        if changed { saveManifest() }
    }

    private func loadManifest() {
        if let data = try? Data(contentsOf: manifestURL),
           let decoded = try? JSONDecoder().decode([String: Record].self, from: data) {
            manifest = decoded
        }

        let missing = manifest.compactMap { key, record in
            FileManager.default.fileExists(atPath: record.path) ? nil : key
        }
        for key in missing { manifest.removeValue(forKey: key) }
        let changed = !missing.isEmpty
        pruneOrphanedFiles()
        if changed { saveManifest() }
    }

    private func pruneOrphanedFiles() {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        let known = Set(manifest.values.map(\.path) + [manifestURL.path])
        for url in entries where !known.contains(url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func saveManifest() {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: manifestURL, options: .atomic)
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

    private nonisolated static func directorySize(at url: URL, excluding excludedNames: Set<String> = []) -> Int {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let file as URL in enumerator {
            guard !excludedNames.contains(file.lastPathComponent) else { continue }
            total += fileSize(at: file)
        }
        return total
    }
}
