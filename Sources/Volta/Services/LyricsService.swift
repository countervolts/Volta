import Foundation

// fetches synced or plain lyrics for a song.
// order: OpenSubsonic getLyricsBySongId → server getLyrics → LRCLib
actor LyricsService {
    static let shared = LyricsService()

    private var cache: [String: [LyricLine]] = [:]

    func lyrics(for song: Song, client: SubsonicClient) async -> [LyricLine] {
        if let cached = cache[song.id] { return cached }

        // try OpenSubsonic structured lyrics
        if let list = try? await client.lyricsBySongId(id: song.id),
           let synced = list.structuredLyrics?.first(where: { $0.synced == true }),
           let lines = synced.line, !lines.isEmpty {
            let result = lines.enumerated().map { i, l in
                LyricLine(id: i, time: Double(l.start ?? 0) / 1000.0, text: l.value)
            }
            cache[song.id] = result
            return result
        }

        // try plain lyrics from server
        if let plain = try? await client.lyrics(
            artist: song.artist ?? "",
            title: song.title
        ), !plain.isEmpty {
            let result = parsePlain(plain)
            cache[song.id] = result
            return result
        }

        // fall back to lrclib
        if let lines = await fetchLRCLib(song: song) {
            cache[song.id] = lines
            return lines
        }

        return []
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
