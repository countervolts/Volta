import Foundation

// Produces a believable set of play events for screenshots. Driven entirely by
// the "Fake Listening Stats" developer experiment; never used in normal operation.
// Spreads plays across ~14 months so every listening-stats period (daily, weekly,
// monthly, yearly, all-time) and every chart has natural-looking data.
enum FakeStatsGenerator {
    private static let genres = [
        "Pop", "Rock", "Hip-Hop", "Electronic", "R&B", "Indie", "Jazz",
        "Classical", "Metal", "Folk", "House", "Lo-Fi", "Soul", "Country", "Ambient"
    ]

    private static let synthArtists = [
        "Aurora Sky", "Neon Tide", "The Velvet Hours", "Midnight Atlas", "Solar Fields",
        "Echo & Ash", "Paper Cities", "Wild Bloom", "Cosmic Drift", "Hazel Grove",
        "Stereo Maze", "Lantern Parade"
    ]
    private static let synthTitles = [
        "Golden Hour", "Afterglow", "Paper Planes", "Night Drive", "Slow Motion",
        "Electric Veins", "Higher Ground", "Faded Lines", "Ocean Eyes", "Lost Signal",
        "Daydream", "Gravity", "Open Road", "Silhouette", "Wildfire", "Velvet Sky",
        "Echoes", "Comet", "Saltwater", "Neon Heart"
    ]

    // A song plus the genre we will stamp onto its play events.
    private struct PoolSong {
        let song: Song
        let genre: String
    }

    static func generate(pool: [Song]) -> [PlayEvent] {
        let songs = makeSongPool(pool)
        guard !songs.isEmpty else { return [] }

        // Zipf-ish weighting so a handful of songs dominate the "top" lists.
        let weights = (0..<songs.count).map { 1.0 / Double($0 + 2) }
        let totalWeight = weights.reduce(0, +)

        var events: [PlayEvent] = []
        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        let currentHour = cal.component(.hour, from: now)

        for dayOffset in 0..<430 {
            guard let day = cal.date(byAdding: .day, value: -dayOffset, to: todayStart) else { continue }
            let weekday = cal.component(.weekday, from: day)   // 1 = Sun ... 7 = Sat
            let isWeekend = (weekday == 1 || weekday == 7)

            // Keep the most recent stretch fully active so the current streak looks healthy.
            let activeChance = isWeekend ? 0.85 : 0.72
            let active = dayOffset < 16 ? true : Double.random(in: 0...1) < activeChance
            if !active { continue }

            var plays = Int.random(in: isWeekend ? 6...20 : 3...14)
            if dayOffset < 7 { plays += Int.random(in: 2...6) }   // livelier current week

            for _ in 0..<plays {
                let entry = weightedPick(songs, weights: weights, total: totalWeight)
                var hour = weightedHour()
                if dayOffset == 0 { hour = min(hour, max(0, currentHour)) }   // today: only up to now
                let minute = Int.random(in: 0..<60)
                let second = Int.random(in: 0..<60)
                guard let ts = cal.date(bySettingHour: hour, minute: minute, second: second, of: day),
                      ts <= now else { continue }
                var event = PlayEvent(song: entry.song, timestamp: ts)
                event.genre = entry.genre
                events.append(event)
            }
        }
        return events
    }

    // MARK: - Pool

    private static func makeSongPool(_ pool: [Song]) -> [PoolSong] {
        // Prefer the user's real (downloaded) songs so artwork and names look authentic.
        if !pool.isEmpty {
            return pool.shuffled().prefix(150).map { song in
                let genre = song.genre?.nonBlank ?? genres[stableIndex(song.id, genres.count)]
                return PoolSong(song: song, genre: genre)
            }
        }

        // Fallback: fully synthetic catalog (no artwork available).
        var result: [PoolSong] = []
        for (i, artist) in synthArtists.enumerated() {
            let albumName = "\(synthTitles[i % synthTitles.count]) LP"
            let albumID = "fake-album-\(i)"
            let artistID = "fake-artist-\(i)"
            let genre = genres[i % genres.count]
            let trackCount = Int.random(in: 6...12)
            for t in 0..<trackCount {
                let song = Song(
                    id: "fake-song-\(i)-\(t)",
                    title: synthTitles[(i + t) % synthTitles.count],
                    album: albumName, artist: artist, albumArtist: artist, albumId: albumID,
                    artistId: artistID, albumArtistId: artistID,
                    coverArt: nil, duration: Int.random(in: 140...320), track: t + 1,
                    discNumber: 1, year: Int.random(in: 1995...2024), genre: genre, size: nil,
                    contentType: nil, suffix: nil, bitRate: nil, path: nil, playCount: nil,
                    bpm: nil, starred: nil, contributes: nil, replayGain: nil, samplingRate: nil,
                    bitDepth: nil, channelCount: nil, displayComposer: nil, contributors: nil
                )
                result.append(PoolSong(song: song, genre: genre))
            }
        }
        return result
    }

    // MARK: - Weighting helpers

    private static func weightedPick(_ songs: [PoolSong], weights: [Double], total: Double) -> PoolSong {
        var r = Double.random(in: 0..<total)
        for (i, w) in weights.enumerated() {
            r -= w
            if r <= 0 { return songs[i] }
        }
        return songs[songs.count - 1]
    }

    // Bias toward a morning commute, lunch, and a strong evening peak.
    private static func weightedHour() -> Int {
        let buckets: [(ClosedRange<Int>, Double)] = [
            (0...5, 0.3), (6...8, 1.4), (9...11, 1.0), (12...13, 1.3),
            (14...16, 1.0), (17...19, 1.8), (20...23, 2.0)
        ]
        let total = buckets.reduce(0.0) { $0 + $1.1 * Double($1.0.count) }
        var r = Double.random(in: 0..<total)
        for (range, w) in buckets {
            for h in range {
                r -= w
                if r <= 0 { return h }
            }
        }
        return 20
    }

    // Deterministic, non-negative index (djb2) so a song keeps a stable genre.
    private static func stableIndex(_ s: String, _ mod: Int) -> Int {
        var h = 5381
        for b in s.utf8 { h = (h &* 33) &+ Int(b) }
        return ((h % mod) + mod) % mod
    }
}
