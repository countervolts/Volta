import Foundation

// Daily local mix, shown in Picks for You.
struct MusicMix: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let coverArt: String?
    let songs: [Song]
}

@MainActor
extension MusicMix {
    var localizedTitle: String {
        if id.hasPrefix("station-discovery-") { return L(.home_discovery_station) }
        if id.hasPrefix("station-heavy-") { return L(.home_heavy_rotation) }
        if let genre = genreName { return L(.home_genre_mix_title, genre) }
        if let artist = artistName { return L(.home_artist_mix_title, artist) }
        return title
    }

    var localizedSubtitle: String {
        if id.hasPrefix("station-discovery-") { return L(.home_discovery_station_subtitle) }
        if id.hasPrefix("station-heavy-") { return L(.home_heavy_rotation_subtitle) }
        if let genre = genreName { return L(.home_genre_mix_subtitle, genre.lowercased()) }
        if let artist = artistName { return L(.home_artist_mix_subtitle, artist) }
        return subtitle
    }

    private var genreName: String? {
        guard id.hasPrefix("genre-") else { return nil }
        let titleSuffix = " Mix"
        if title.hasSuffix(titleSuffix) {
            return String(title.dropLast(titleSuffix.count))
        }
        let dailyPrefix = "Daily "
        let dailySuffix = " mix"
        if subtitle.hasPrefix(dailyPrefix), subtitle.hasSuffix(dailySuffix) {
            return String(subtitle.dropFirst(dailyPrefix.count).dropLast(dailySuffix.count))
        }
        let madePrefix = "Made from "
        let madeSuffix = " songs"
        if subtitle.hasPrefix(madePrefix), subtitle.hasSuffix(madeSuffix) {
            return String(subtitle.dropFirst(madePrefix.count).dropLast(madeSuffix.count))
        }
        return String(id.dropFirst("genre-".count)).removingPercentEncoding
            ?? String(id.dropFirst("genre-".count))
    }

    private var artistName: String? {
        let prefix = "Based on "
        if subtitle.hasPrefix(prefix) {
            return String(subtitle.dropFirst(prefix.count))
        }
        let suffix = " Mix"
        if id.hasPrefix("artist-"), title.hasSuffix(suffix) {
            return String(title.dropLast(suffix.count))
        }
        return nil
    }
}

// One Picks for You card: either a mix or an album.
enum PickFeedItem: Identifiable, Hashable {
    case album(Album)
    case mix(MusicMix)

    var id: String {
        switch self {
        case .album(let a): return "album-\(a.id)"
        case .mix(let m):   return "mix-\(m.id)"
        }
    }
}

// Stable for a day, different tomorrow.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    // one seed per UTC day
    static func daySeed() -> UInt64 {
        UInt64(Int(Date().timeIntervalSince1970) / 86_400)
    }
}
