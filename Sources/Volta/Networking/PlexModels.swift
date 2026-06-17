import Foundation

// Decode-only Plex API DTOs.
// Plex wraps responses in MediaContainer and omits empty fields freely.

struct PXResponse: Decodable {
    let MediaContainer: PXContainer?
}

struct PXContainer: Decodable {
    let machineIdentifier: String?
    let friendlyName: String?
    let version: String?
    let size: Int?
    let totalSize: Int?
    let Metadata: [PXMetadata]?
    let Directory: [PXDirectory]?
    let Hub: [PXHub]?
}

struct PXDirectory: Decodable {
    let key: String?
    let title: String?
    let type: String?
}

struct PXHub: Decodable {
    let type: String?
    let Metadata: [PXMetadata]?
    let Directory: [PXDirectory]?
}

struct PXTag: Decodable {
    let tag: String?
}

struct PXStream: Decodable {
    let streamType: Int?      // 1 video, 2 audio, 3 subtitle, 4 lyrics
    let codec: String?
    let bitDepth: Int?
    let samplingRate: Int?
    let channels: Int?
    let id: Int?
    let key: String?
    let format: String?
}

struct PXPart: Decodable {
    let key: String?
    let file: String?
    let size: Int?
    let container: String?
    let Stream: [PXStream]?
}

struct PXMedia: Decodable {
    let bitrate: Int?
    let audioChannels: Int?
    let audioCodec: String?
    let container: String?
    let Part: [PXPart]?
}

struct PXMetadata: Decodable {
    let ratingKey: String?
    let key: String?
    let type: String?
    let title: String?
    let parentTitle: String?
    let grandparentTitle: String?
    let parentRatingKey: String?
    let grandparentRatingKey: String?
    let thumb: String?
    let parentThumb: String?
    let grandparentThumb: String?
    let summary: String?
    let index: Int?
    let parentIndex: Int?
    let year: Int?
    let addedAt: Int?
    let duration: Int?         // milliseconds
    let leafCount: Int?
    let viewCount: Int?
    let userRating: Double?
    let studio: String?
    let playlistItemID: Int?
    let Genre: [PXTag]?
    let Media: [PXMedia]?
}

// MARK: - Helpers

enum PlexConvert {
    // Plex addedAt is unix time; app models use ISO8601 strings.
    static func iso(fromEpoch epoch: Int?) -> String? {
        guard let epoch else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }
}

extension PXMetadata {
    // 10/10 rating stands in for music favorites.
    var starredMarker: String? {
        (userRating ?? 0) >= 10 ? "starred" : nil
    }

    var asAlbum: Album { asAlbum(withSongs: nil) }

    func asAlbum(withSongs songs: [Song]?) -> Album {
        Album(
            id: ratingKey ?? "",
            name: title ?? "Unknown Album",
            artist: parentTitle,
            artistId: parentRatingKey,
            coverArt: thumb,
            songCount: leafCount ?? songs?.count,
            duration: duration.map { $0 / 1000 },
            playCount: viewCount,
            created: PlexConvert.iso(fromEpoch: addedAt),
            year: year,
            genre: Genre?.first?.tag,
            starred: starredMarker,
            comment: summary,
            recordLabel: studio,
            song: songs
        )
    }

    var asArtist: Artist { asArtist(withAlbums: nil) }

    func asArtist(withAlbums albums: [Album]?) -> Artist {
        Artist(
            id: ratingKey ?? "",
            name: title ?? "Unknown Artist",
            coverArt: thumb,
            albumCount: albums?.count ?? leafCount,
            artistImageUrl: nil,
            starred: starredMarker,
            album: albums
        )
    }

    func asPlaylist(withEntries entries: [Song]?) -> Playlist {
        Playlist(
            id: ratingKey ?? "",
            name: title ?? "Playlist",
            comment: summary,
            owner: nil,
            songCount: leafCount ?? entries?.count,
            duration: duration.map { $0 / 1000 },
            created: PlexConvert.iso(fromEpoch: addedAt),
            changed: nil,
            played: nil,
            coverArt: thumb,
            entry: entries
        )
    }
}
