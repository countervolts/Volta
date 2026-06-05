import Foundation

// a locally-generated mix shown in "Picks for You" (e.g. "Rock Mix", "Artist Mix").
// regenerated daily from the user's library.
struct MusicMix: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let coverArt: String?
    let songs: [Song]
}

// one entry in the unified "Picks for You" row — either a daily mix or a pick
// album. they share the same card size and are interleaved randomly.
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

// deterministic RNG so a day's mixes are stable but change each day (SplitMix64).
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

    // seed derived from the current day → rotates once per day
    static func daySeed() -> UInt64 {
        UInt64(Int(Date().timeIntervalSince1970) / 86_400)
    }
}
