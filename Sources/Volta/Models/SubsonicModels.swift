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
    let albumArtist: String?
    let albumId: String?
    let artistId: String?
    let albumArtistId: String?
    let coverArt: String?
    let duration: Int?
    let track: Int?
    let discNumber: Int?
    let year: Int?
    let genre: String?
    let size: Int?
    let contentType: String?
    let suffix: String?
    // Encoded audio format when the backend exposes it (for example, ALAC or AAC).
    // This is distinct from `suffix`, which describes the file container and may
    // be ambiguous for formats such as M4A.
    let codec: String?
    let bitRate: Int?
    let path: String?
    let playCount: Int?
    // OpenSubsonic BPM, when the server has it.
    let bpm: Int?
    // OpenSubsonic content advisory: "explicit", "clean", or an empty string.
    let explicitStatus: String?
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

// One OpenSubsonic credit: role + artist.
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
    var isExplicit: Bool {
        guard let status = normalizedExplicitStatus else { return false }
        return ["explicit", "e", "1", "4", "true", "yes"].contains(status)
    }

    var hasKnownExplicitStatus: Bool {
        guard let status = normalizedExplicitStatus else { return false }
        return ["explicit", "e", "1", "4", "true", "yes", "clean", "c", "2", "false", "no"].contains(status)
    }

    private var normalizedExplicitStatus: String? {
        explicitStatus?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().nonBlank
    }

    private static let losslessCodecs: Set<String> = [
        "flac", "alac", "apple_lossless", "ape", "wavpack", "wv", "tta", "tak", "shorten",
        "pcm", "lpcm", "pcm_s8", "pcm_s16le", "pcm_s16be", "pcm_s24le",
        "pcm_s24be", "pcm_s32le", "pcm_s32be", "pcm_f32le", "pcm_f32be",
        "pcm_f64le", "pcm_f64be"
    ]

    private static let lossyCodecs: Set<String> = [
        "aac", "aac_latm", "mp4a", "mp4a.40.2", "mp4a.40.5", "ac3", "eac3",
        "mp2", "mp3", "opus", "vorbis", "wma", "wmapro", "wmav1", "wmav2"
    ]

    private static let losslessSuffixes: Set<String> = [
        "flac", "wav", "wave", "aiff", "aif", "alac", "ape", "wv", "tta",
        "tak", "shn"
    ]

    private static let losslessContentTypes: Set<String> = [
        "audio/alac", "audio/x-alac", "audio/flac", "audio/x-flac",
        "audio/wav", "audio/wave", "audio/x-wav", "audio/aiff", "audio/x-aiff"
    ]

    var isLossless: Bool {
        if let codec = codec?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
            if Self.losslessCodecs.contains(codec) { return true }
            if Self.lossyCodecs.contains(codec) { return false }
        }

        if let contentType = contentType?
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           Self.losslessContentTypes.contains(contentType) {
            return true
        }

        guard let suffix = suffix?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }

        // OpenSubsonic's standard song payload has no codec field. Navidrome
        // distinguishes codec-less M4A in the same way: AAC has no meaningful
        // bit depth, while ALAC reports a positive source bit depth. An explicit
        // codec above always takes precedence over this compatibility fallback.
        if suffix == "m4a", (bitDepth ?? 0) > 0 { return true }

        return Self.losslessSuffixes.contains(suffix)
    }

    var isHiResLossless: Bool {
        guard isLossless,
              let bitDepth,
              let samplingRate else {
            return false
        }
        return bitDepth >= 24 && samplingRate > 48_000 && samplingRate <= 192_000
    }
}

// OpenSubsonic ReplayGain values.
struct ReplayGain: Codable, Hashable, Sendable {
    let trackGain: Double?
    let albumGain: Double?
    let trackPeak: Double?
    let albumPeak: Double?
}

// Public share returned by createShare.
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
    // real artist photos from getArtistInfo2
    let smallImageUrl: String?
    let mediumImageUrl: String?
    let largeImageUrl: String?

    // largest real artist image first
    var bestImageUrl: String? {
        for url in [largeImageUrl, mediumImageUrl, smallImageUrl] {
            if let url, !url.isEmpty { return url }
        }
        return nil
    }
}

// Synced lyric line from getLyricsBySongId.
struct StructuredLyricLine: Decodable, Sendable {
    let start: Int?   // milliseconds
    let value: String
}

struct StructuredLyrics: Decodable, Sendable {
    let displayArtist: String?
    let displayTitle: String?
    let lang: String?
    let offset: Int?
    let synced: Bool?
    let line: [StructuredLyricLine]?
}

struct LyricsList: Decodable, Sendable {
    let structuredLyrics: [StructuredLyrics]?
    // Present only for clients (currently Plex) that receive the original
    // lyric bytes. OpenSubsonic/Jellyfin decode normalized JSON and leave nil.
    let rawPayload: RawLyricsPayload?

    private enum CodingKeys: String, CodingKey {
        case structuredLyrics
    }

    init(structuredLyrics: [StructuredLyrics]?, rawPayload: RawLyricsPayload? = nil) {
        self.structuredLyrics = structuredLyrics
        self.rawPayload = rawPayload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        structuredLyrics = try container.decodeIfPresent([StructuredLyrics].self, forKey: .structuredLyrics)
        rawPayload = nil
    }
}

// Parsed lyric line for display.
struct LyricLine: Identifiable, Hashable, Codable, Sendable {
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
