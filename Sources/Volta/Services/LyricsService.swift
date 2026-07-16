import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// One match from a local-lyrics search.
struct LyricSearchHit: Identifiable, Sendable, Hashable {
    let id: String        // songID
    let title: String
    let artist: String?
    let snippet: String
}

enum LyricsDownloadSource: String, CaseIterable, Identifiable, Sendable {
    case server
    case lrclib

    var id: String { rawValue }
    var displayName: String { self == .server ? "Server" : "LRCLIB" }
}

// Fetches synced or plain lyrics for a song.
// Order: memory -> local raw file -> server by song ID -> legacy server text -> LRCLIB.
actor LyricsService {
    static let shared = LyricsService()

    private var cache: [String: [LyricLine]] = [:]
    private let directory: URL

    // Kept decode-compatible so existing installations can migrate their old
    // parsed-lines JSON cache to real .lrc/.txt files on first read.
    private struct LegacyStoredLyrics: Codable {
        let songID: String
        let title: String
        let artist: String?
        let source: String
        let savedAt: Date
        let lines: [LyricLine]
    }

    private struct StoredLyricsMetadata: Codable {
        let schemaVersion: Int
        let songID: String
        let title: String
        let artist: String?
        let source: String
        let savedAt: Date
        let format: LyricsFileFormat
        let fileName: String
    }

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("Volta/Lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func lyrics(
        for song: Song,
        client: any MusicService,
        forceSave: Bool = false,
        downloadSource: LyricsDownloadSource? = nil
    ) async -> [LyricLine] {
        // A source-specific bulk download must honor the selected source, even
        // when a live view previously populated the in-memory fallback cache.
        if downloadSource == nil, let cached = cache[song.id] {
            if forceSave, !hasLocalLyrics(for: song.id) {
                _ = saveLocalLyrics(cached, for: song, source: "Cached", raw: nil)
            }
            return cached
        }
        if downloadSource == nil, let local = loadLocalLyrics(for: song) {
            cache[song.id] = local
            return local
        }

        // Demo servers are stream-only. The bulk downloader already blocks
        // demos; keep this guard for ordinary live lyric requests too.
        let isDemo = DemoServers.isDemo(client.config.baseURL)
        let persistLocally = !isDemo && (forceSave || shouldSaveLocalLyrics)

        if downloadSource != .lrclib {
            if let list = try? await client.lyricsBySongId(id: song.id),
               let result = Self.displayLines(from: list), !result.isEmpty {
                cache[song.id] = result
                if persistLocally {
                    _ = saveLocalLyrics(
                        result,
                        for: song,
                        source: client.backendKind.displayName,
                        raw: list.rawPayload
                    )
                }
                return result
            }

            // Legacy getLyrics responses are arbitrary strings. Sniff them so a
            // custom server returning TTML or LRC is not displayed as XML/plain text.
            if let rawText = try? await client.lyrics(
                artist: song.artist ?? "",
                title: song.title
            ), !rawText.isEmpty,
               let parsed = LyricsParser.parse(text: rawText), !parsed.lines.isEmpty {
                cache[song.id] = parsed.lines
                if persistLocally {
                    _ = saveLocalLyrics(
                        parsed.lines,
                        for: song,
                        source: client.backendKind.displayName,
                        raw: parsed.raw
                    )
                }
                return parsed.lines
            }
        }

        if downloadSource != .server, let parsed = await fetchLRCLib(song: song) {
            cache[song.id] = parsed.lines
            if persistLocally {
                _ = saveLocalLyrics(
                    parsed.lines,
                    for: song,
                    source: "LRCLIB",
                    raw: parsed.raw
                )
            }
            return parsed.lines
        }

        return []
    }

    func storageSizeBytes() -> Int {
        Self.directorySize(at: directory)
    }

    func localLyricsCount() -> Int {
        storedSongKeys().count
    }

    func hasLocalLyrics(for songID: String) -> Bool {
        let key = cacheKey(for: songID)
        return LyricsFileFormat.allCases.contains {
            FileManager.default.fileExists(atPath: rawURL(forKey: key, format: $0).path)
        } || FileManager.default.fileExists(atPath: legacyURL(forKey: key).path)
    }

    // Keeps only songs that don't already have a raw lyric file (or a legacy
    // JSON entry), using one directory listing for bulk-download performance.
    func songsMissingLyrics(
        _ songs: [Song],
        source: LyricsDownloadSource? = nil
    ) -> [Song] {
        guard let source else {
            let existing = storedSongKeys()
            return songs.filter { !existing.contains(cacheKey(for: $0.id)) }
        }

        let storedSources = storedSourcesByKey()
        return songs.filter { song in
            guard let existingSource = storedSources[cacheKey(for: song.id)] else { return true }
            switch source {
            case .lrclib:
                return existingSource.caseInsensitiveCompare("LRCLIB") != .orderedSame
            case .server:
                return existingSource.caseInsensitiveCompare("LRCLIB") == .orderedSame
            }
        }
    }

    // Full-text search across locally saved raw lyrics. Metadata remains a
    // small JSON sidecar so search can show song/artist without a server call.
    func searchLocal(_ query: String, limit: Int = 60) -> [LyricSearchHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard needle.count >= 2 else { return [] }
        let files = directoryContents()
        var hits: [LyricSearchHit] = []
        var seenSongIDs = Set<String>()

        for file in files where file.lastPathComponent.hasSuffix(".metadata.json") {
            guard let data = try? Data(contentsOf: file),
                  let metadata = try? JSONDecoder().decode(StoredLyricsMetadata.self, from: data),
                  seenSongIDs.insert(metadata.songID).inserted,
                  let raw = try? Data(contentsOf: directory.appendingPathComponent(metadata.fileName)),
                  let parsed = LyricsParser.parse(data: raw, formatHint: metadata.format.rawValue),
                  let line = parsed.lines.first(where: { $0.text.lowercased().contains(needle) })
            else { continue }
            hits.append(LyricSearchHit(
                id: metadata.songID,
                title: metadata.title,
                artist: metadata.artist,
                snippet: line.text.trimmingCharacters(in: .whitespaces)
            ))
            if hits.count >= limit { break }
        }

        // Search old caches that have not yet been opened/migrated.
        if hits.count < limit {
            for file in files where Self.isLegacyJSON(file) {
                guard let data = try? Data(contentsOf: file),
                      let stored = try? JSONDecoder().decode(LegacyStoredLyrics.self, from: data),
                      seenSongIDs.insert(stored.songID).inserted,
                      let line = stored.lines.first(where: { $0.text.lowercased().contains(needle) })
                else { continue }
                hits.append(LyricSearchHit(
                    id: stored.songID,
                    title: stored.title,
                    artist: stored.artist,
                    snippet: line.text.trimmingCharacters(in: .whitespaces)
                ))
                if hits.count >= limit { break }
            }
        }

        return hits.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func clearLocalLyrics() {
        cache.removeAll()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Structured server responses

    private static func displayLines(from list: LyricsList) -> [LyricLine]? {
        let documents = list.structuredLyrics ?? []
        let candidates = documents.compactMap { document -> (lines: [LyricLine], synced: Bool)? in
            guard let sourceLines = document.line, !sourceLines.isEmpty else { return nil }
            let fullyTimed = sourceLines.allSatisfy { $0.start != nil }
            let synced = fullyTimed && (document.synced != false)

            if synced {
                let offset = document.offset ?? 0
                let ordered = sourceLines.enumerated().sorted {
                    let lhs = ($0.element.start ?? 0) + offset
                    let rhs = ($1.element.start ?? 0) + offset
                    return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
                }
                let lines = ordered.enumerated().map { index, entry in
                    let milliseconds = max(0, (entry.element.start ?? 0) + offset)
                    return LyricLine(
                        id: index,
                        time: Double(milliseconds) / 1_000,
                        text: entry.element.value
                    )
                }
                return (lines, true)
            }

            let lines = sourceLines.enumerated().map {
                LyricLine(id: $0.offset, time: -1, text: $0.element.value)
            }
            return (lines, false)
        }

        return candidates.first(where: { $0.synced })?.lines ?? candidates.first?.lines
    }

    // MARK: - Local raw storage

    private var shouldSaveLocalLyrics: Bool {
        UserDefaults.standard.object(forKey: "saveLyricsLocally") as? Bool ?? true
    }

    private func loadLocalLyrics(for song: Song) -> [LyricLine]? {
        let key = cacheKey(for: song.id)
        let metadataURL = self.metadataURL(forKey: key)
        if let data = try? Data(contentsOf: metadataURL),
           let metadata = try? JSONDecoder().decode(StoredLyricsMetadata.self, from: data),
           let raw = try? Data(contentsOf: directory.appendingPathComponent(metadata.fileName)),
           let parsed = LyricsParser.parse(data: raw, formatHint: metadata.format.rawValue),
           !parsed.lines.isEmpty {
            return parsed.lines
        }

        // Recover raw files even if their metadata sidecar was interrupted.
        for format in LyricsFileFormat.allCases {
            let url = rawURL(forKey: key, format: format)
            guard let raw = try? Data(contentsOf: url),
                  let parsed = LyricsParser.parse(data: raw, formatHint: format.rawValue),
                  !parsed.lines.isEmpty else { continue }
            return parsed.lines
        }

        // One-time migration from the original normalized JSON cache.
        let legacyURL = legacyURL(forKey: key)
        guard let data = try? Data(contentsOf: legacyURL),
              let stored = try? JSONDecoder().decode(LegacyStoredLyrics.self, from: data),
              !stored.lines.isEmpty else { return nil }
        _ = saveLocalLyrics(stored.lines, for: song, source: stored.source, raw: nil)
        return stored.lines
    }

    @discardableResult
    private func saveLocalLyrics(
        _ lines: [LyricLine],
        for song: Song,
        source: String,
        raw: RawLyricsPayload?
    ) -> Bool {
        guard !lines.isEmpty,
              let payload = raw ?? LyricsParser.canonicalPayload(for: lines),
              !payload.data.isEmpty else { return false }

        let key = cacheKey(for: song.id)
        let rawFileURL = rawURL(forKey: key, format: payload.format)
        let metadata = StoredLyricsMetadata(
            schemaVersion: 1,
            songID: song.id,
            title: song.title,
            artist: song.artist,
            source: source,
            savedAt: Date(),
            format: payload.format,
            fileName: rawFileURL.lastPathComponent
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let metadataData = try? encoder.encode(metadata) else { return false }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try payload.data.write(to: rawFileURL, options: .atomic)
            try metadataData.write(to: metadataURL(forKey: key), options: .atomic)
        } catch {
            return false
        }

        // A song has one active local lyric payload. Remove obsolete generated
        // formats and the legacy cache only after both new writes succeed.
        for format in LyricsFileFormat.allCases where format != payload.format {
            try? FileManager.default.removeItem(at: rawURL(forKey: key, format: format))
        }
        try? FileManager.default.removeItem(at: legacyURL(forKey: key))
        return true
    }

    private func storedSongKeys() -> Set<String> {
        var keys = Set<String>()
        for file in directoryContents() {
            if LyricsFileFormat.allCases.contains(where: { $0.pathExtension == file.pathExtension.lowercased() }) {
                keys.insert(file.deletingPathExtension().lastPathComponent)
            } else if Self.isLegacyJSON(file) {
                keys.insert(file.deletingPathExtension().lastPathComponent)
            }
        }
        return keys
    }

    private func storedSourcesByKey() -> [String: String] {
        var sources: [String: String] = [:]
        for file in directoryContents() where file.lastPathComponent.hasSuffix(".metadata.json") {
            guard let data = try? Data(contentsOf: file),
                  let metadata = try? JSONDecoder().decode(StoredLyricsMetadata.self, from: data)
            else { continue }
            sources[cacheKey(for: metadata.songID)] = metadata.source
        }
        return sources
    }

    private func directoryContents() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private static func isLegacyJSON(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "json"
            && !url.lastPathComponent.hasSuffix(".metadata.json")
    }

    private func cacheKey(for songID: String) -> String {
        Crypto.md5Hex(songID)
    }

    private func rawURL(forKey key: String, format: LyricsFileFormat) -> URL {
        directory.appendingPathComponent(key).appendingPathExtension(format.pathExtension)
    }

    private func metadataURL(forKey key: String) -> URL {
        directory.appendingPathComponent(key + ".metadata.json")
    }

    private func legacyURL(forKey key: String) -> URL {
        directory.appendingPathComponent(key + ".json")
    }

    private nonisolated static func directorySize(at url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        return enumerator.compactMap { $0 as? URL }
            .compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
            .reduce(0, +)
    }

    // MARK: - LRCLIB

    private func fetchLRCLib(song: Song) async -> ParsedLyricsDocument? {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        var query = [URLQueryItem(name: "track_name", value: song.title)]
        if let artist = song.artist { query.append(URLQueryItem(name: "artist_name", value: artist)) }
        if let album = song.album { query.append(URLQueryItem(name: "album_name", value: album)) }
        if let duration = song.duration { query.append(URLQueryItem(name: "duration", value: String(duration))) }
        components.queryItems = query

        guard let url = components.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // LRCLIB exposes syncedLyrics as LRC text and plainLyrics as text. Save
        // those exact strings locally instead of a parsed-lines JSON rendering.
        if let synced = json["syncedLyrics"] as? String, !synced.isEmpty,
           let parsed = LyricsParser.parse(text: synced, formatHint: "lrc") {
            return parsed
        }
        if let plain = json["plainLyrics"] as? String, !plain.isEmpty,
           let parsed = LyricsParser.parse(text: plain, formatHint: "text") {
            return parsed
        }
        return nil
    }
}
