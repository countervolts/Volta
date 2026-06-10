import Foundation

// one match from a local-lyrics search
struct LyricSearchHit: Identifiable, Sendable, Hashable {
    let id: String        // songID
    let title: String
    let artist: String?
    let snippet: String
}

// Fetches synced or plain lyrics for a song.
// Order: memory -> local disk -> OpenSubsonic getLyricsBySongId -> server getLyrics -> LRCLib.
actor LyricsService {
    static let shared = LyricsService()

    private var cache: [String: [LyricLine]] = [:]
    private let directory: URL

    private struct StoredLyrics: Codable {
        let songID: String
        let title: String
        let artist: String?
        let source: String
        let savedAt: Date
        let lines: [LyricLine]
    }

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("Volta/Lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func lyrics(for song: Song, client: SubsonicClient) async -> [LyricLine] {
        if let cached = cache[song.id] { return cached }
        if let local = loadLocalLyrics(for: song) {
            cache[song.id] = local
            return local
        }

        // try OpenSubsonic structured lyrics
        if let list = try? await client.lyricsBySongId(id: song.id),
           let synced = list.structuredLyrics?.first(where: { $0.synced == true }),
           let lines = synced.line, !lines.isEmpty {
            let result = lines.enumerated().map { i, l in
                LyricLine(id: i, time: Double(l.start ?? 0) / 1000.0, text: l.value)
            }
            cache[song.id] = result
            saveLocalLyrics(result, for: song, source: "OpenSubsonic")
            return result
        }

        // try plain lyrics from server
        if let plain = try? await client.lyrics(
            artist: song.artist ?? "",
            title: song.title
        ), !plain.isEmpty {
            let result = parsePlain(plain)
            cache[song.id] = result
            saveLocalLyrics(result, for: song, source: "Subsonic")
            return result
        }

        // fall back to lrclib
        if let lines = await fetchLRCLib(song: song) {
            cache[song.id] = lines
            saveLocalLyrics(lines, for: song, source: "LRCLib")
            return lines
        }

        return []
    }

    func storageSizeBytes() -> Int {
        Self.directorySize(at: directory)
    }

    // number of songs with lyrics saved on device
    func localLyricsCount() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.count
    }

    // returns true when lyrics for this song are already saved on device
    func hasLocalLyrics(for songID: String) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: songID).path)
    }

    // keeps only songs that don't already have lyrics on device (one dir listing)
    func songsMissingLyrics(_ songs: [Song]) -> [Song] {
        let existing = Set(((try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? [])
            .map { $0.lastPathComponent })
        return songs.filter { !existing.contains(Crypto.md5Hex($0.id) + ".json") }
    }

    // full-text search across locally saved lyrics (only downloaded songs)
    func searchLocal(_ query: String, limit: Int = 60) -> [LyricSearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 2 else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        var hits: [LyricSearchHit] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let stored = try? JSONDecoder().decode(StoredLyrics.self, from: data),
                  let line = stored.lines.first(where: { $0.text.lowercased().contains(q) })
            else { continue }
            hits.append(LyricSearchHit(
                id: stored.songID,
                title: stored.title,
                artist: stored.artist,
                snippet: line.text.trimmingCharacters(in: .whitespaces)
            ))
            if hits.count >= limit { break }
        }
        return hits.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func clearLocalLyrics() {
        cache.removeAll()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Local storage

    private var shouldSaveLocalLyrics: Bool {
        UserDefaults.standard.object(forKey: "saveLyricsLocally") as? Bool ?? true
    }

    private func loadLocalLyrics(for song: Song) -> [LyricLine]? {
        let url = localURL(for: song.id)
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(StoredLyrics.self, from: data),
              !stored.lines.isEmpty else {
            return nil
        }
        return stored.lines
    }

    private func saveLocalLyrics(_ lines: [LyricLine], for song: Song, source: String) {
        guard shouldSaveLocalLyrics, !lines.isEmpty else { return }
        let stored = StoredLyrics(
            songID: song.id,
            title: song.title,
            artist: song.artist,
            source: source,
            savedAt: Date(),
            lines: lines
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(stored) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: localURL(for: song.id), options: .atomic)
    }

    private func localURL(for songID: String) -> URL {
        directory.appendingPathComponent(Crypto.md5Hex(songID) + ".json")
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

    // MARK: - LRCLib

    private func fetchLRCLib(song: Song) async -> [LyricLine]? {
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        var items: [URLQueryItem] = [URLQueryItem(name: "track_name", value: song.title)]
        if let a = song.artist { items.append(URLQueryItem(name: "artist_name", value: a)) }
        if let al = song.album { items.append(URLQueryItem(name: "album_name", value: al)) }
        if let d = song.duration { items.append(URLQueryItem(name: "duration", value: String(d))) }
        comps.queryItems = items

        guard let url = comps.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let synced = json["syncedLyrics"] as? String, !synced.isEmpty {
            return parseLRC(synced)
        }
        if let plain = json["plainLyrics"] as? String, !plain.isEmpty {
            return parsePlain(plain)
        }
        return nil
    }

    // MARK: - Parsers

    // parse [mm:ss.xx] lyric text
    private func parseLRC(_ lrc: String) -> [LyricLine] {
        let pattern = #"^\[(\d{2}):(\d{2})\.(\d{2,3})\]\s*(.*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var lines: [LyricLine] = []
        for (i, rawLine) in lrc.components(separatedBy: "\n").enumerated() {
            let range = NSRange(rawLine.startIndex..., in: rawLine)
            guard let match = regex.firstMatch(in: rawLine, range: range) else { continue }
            func capture(_ n: Int) -> String {
                let r = Range(match.range(at: n), in: rawLine)!
                return String(rawLine[r])
            }
            let mm = Double(capture(1)) ?? 0
            let ss = Double(capture(2)) ?? 0
            let frac = Double(capture(3)) ?? 0
            let divisor: Double = capture(3).count == 3 ? 1000 : 100
            let t = mm * 60 + ss + frac / divisor
            let text = capture(4)
            lines.append(LyricLine(id: i, time: t, text: text))
        }
        return lines.sorted { $0.time < $1.time }
    }

    private func parsePlain(_ text: String) -> [LyricLine] {
        text.components(separatedBy: "\n")
            .enumerated()
            .map { LyricLine(id: $0.offset, time: -1, text: $0.element) }
    }
}
