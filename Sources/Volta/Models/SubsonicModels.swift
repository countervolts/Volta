import Foundation

struct Album: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let artist: String?
    let artistId: String?
    let coverArt: String?
    let songCount: Int?
    let duration: Int?
    let playCount: Int?
    let created: String?
    let year: Int?
    let genre: String?
    let starred: String?
    let comment: String?
    let recordLabel: String?

    let song: [Song]?

    var displayArtist: String { artist ?? "Unknown Artist" }
    var createdDate: Date? { ISO8601DateParser.date(from: created) }
}

struct Artist: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let coverArt: String?
    let albumCount: Int?
    let artistImageUrl: String?
    let starred: String?

    let album: [Album]?
}

struct Song: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let album: String?
    let artist: String?
    let albumId: String?
    let artistId: String?
    let coverArt: String?
    let duration: Int?
    let track: Int?
    let discNumber: Int?
    let year: Int?
    let genre: String?
    let size: Int?
    let contentType: String?
    let suffix: String?
    let bitRate: Int?
    let path: String?
    let playCount: Int?
    let starred: String?
    let contributes: String?
    let replayGain: ReplayGain?
    // OpenSubsonic audio detail fields
    let samplingRate: Int?
    let bitDepth: Int?
    let channelCount: Int?
    // OpenSubsonic creation credits
    let displayComposer: String?
    let contributors: [Contributor]?
}

// one OpenSubsonic credit: a role (composer / producer / engineer …) + the
// artist who filled it.
struct Contributor: Codable, Hashable, Sendable {
    let role: String?
    let subRole: String?
    let artist: ArtistRef?
}

struct ArtistRef: Codable, Hashable, Sendable {
    let id: String?
    let name: String?
}

extension Song {
    // lossless if the file format is one of the known lossless container/codecs
    var isLossless: Bool {
        guard let s = suffix?.lowercased() else { return false }
        return ["flac", "wav", "aiff", "aif", "alac", "ape", "wv", "tta"].contains(s)
    }
}

// OpenSubsonic replayGain object on a song (values in dB / linear peak)
struct ReplayGain: Codable, Hashable, Sendable {
    let trackGain: Double?
    let albumGain: Double?
    let trackPeak: Double?
    let albumPeak: Double?
}

// a public share returned by createShare
struct Share: Decodable, Identifiable, Sendable {
    let id: String
    let url: String?
}

struct Playlist: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let comment: String?
    let owner: String?
    let songCount: Int?
    let duration: Int?
    let created: String?
    let changed: String?
    let played: String?
    let coverArt: String?

    let entry: [Song]?

    var playedDate: Date? { ISO8601DateParser.date(from: played) }
    var changedDate: Date? { ISO8601DateParser.date(from: changed) }
}

struct ArtistInfo: Decodable, Sendable {
    let biography: String?
    let similarArtist: [Artist]?
    // real artist photos from getArtistInfo2 (last.fm / spotify backed)
    let smallImageUrl: String?
    let mediumImageUrl: String?
    let largeImageUrl: String?

    // best available real artist photo, largest first
    var bestImageUrl: String? {
        for url in [largeImageUrl, mediumImageUrl, smallImageUrl] {
            if let url, !url.isEmpty { return url }
        }
        return nil
    }
}

// structured lyrics line from OpenSubsonic getLyricsBySongId
struct StructuredLyricLine: Decodable, Sendable {
    let start: Int?   // milliseconds
    let value: String
}

struct StructuredLyrics: Decodable, Sendable {
    let displayArtist: String?
    let displayTitle: String?
    let lang: String?
    let synced: Bool?
    let line: [StructuredLyricLine]?
}

struct LyricsList: Decodable, Sendable {
    let structuredLyrics: [StructuredLyrics]?
}

// parsed lyric line for display
struct LyricLine: Identifiable, Hashable, Sendable {
    let id: Int
    let time: TimeInterval   // seconds; < 0 means unsynced
    let text: String
}

enum ISO8601DateParser {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let fallback: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(from string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return formatter.date(from: string) ?? fallback.date(from: string)
    }
}
