import Foundation

// Decode-only Plex API DTOs.
// Plex wraps responses in MediaContainer and omits empty fields freely.

// A saved Plex server can advertise several routes to the same machine. Keep
// the route type alongside the URL so the client can prefer LAN on Wi-Fi,
// direct remote access on cellular, and Relay only as a final fallback.
enum PlexConnectionKind: String, Codable, Sendable {
    case local
    case remote
    case relay
    case manual
}

struct PlexConnectionEndpoint: Codable, Hashable, Sendable {
    let url: URL
    let kind: PlexConnectionKind

    var isSecure: Bool { url.scheme?.lowercased() == "https" }

    func preferenceRank(preferLocal: Bool) -> Int {
        let routeRank: Int
        switch (preferLocal, kind) {
        case (true, .local): routeRank = 0
        case (true, .remote), (true, .manual): routeRank = 2
        case (true, .relay): routeRank = 4
        case (false, .remote), (false, .manual): routeRank = 0
        case (false, .relay): routeRank = 2
        case (false, .local): routeRank = 4
        }
        return routeRank + (isSecure ? 0 : 1)
    }
}

// A Plex account token is not necessarily valid against a Plex Media Server.
// `/api/v2/resources` supplies the per-server token and every connection URL
// Plex knows about for that server.
struct PlexServerResource: Decodable, Sendable {
    let name: String?
    let product: String?
    let clientIdentifier: String?
    let provides: String?
    let accessToken: String?
    let owned: Bool?
    let presence: Bool?
    let connections: [PlexResourceConnection]

    var displayName: String {
        name?.nonBlank ?? "Plex Media Server"
    }

    var isMediaServer: Bool {
        let capabilities = provides?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() } ?? []
        return capabilities.contains("server")
            || product?.caseInsensitiveCompare("Plex Media Server") == .orderedSame
    }

    var usableAccessToken: String? { accessToken?.nonBlank }

    // Plex recommends local connections first and relay connections last.
    // Within each tier, prefer HTTPS so the automatic path stays encrypted.
    var preferredConnections: [PlexResourceConnection] {
        connections.enumerated().sorted { lhs, rhs in
            let leftRank = lhs.element.preferenceRank
            let rightRank = rhs.element.preferenceRank
            return leftRank == rightRank ? lhs.offset < rhs.offset : leftRank < rightRank
        }.map(\.element)
    }

    private enum CodingKeys: String, CodingKey {
        case name, product, clientIdentifier, provides, accessToken, owned, presence
        case connections
        case upperConnections = "Connection"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        product = try container.decodeIfPresent(String.self, forKey: .product)
        clientIdentifier = try container.decodeIfPresent(String.self, forKey: .clientIdentifier)
        provides = try container.decodeIfPresent(String.self, forKey: .provides)
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken)
        owned = try container.decodeIfPresent(Bool.self, forKey: .owned)
        presence = try container.decodeIfPresent(Bool.self, forKey: .presence)
        connections = try container.decodeIfPresent([PlexResourceConnection].self, forKey: .connections)
            ?? container.decodeIfPresent([PlexResourceConnection].self, forKey: .upperConnections)
            ?? []
    }
}

struct PlexResourceConnection: Decodable, Sendable {
    let protocolName: String?
    let address: String?
    let port: Int?
    let uri: String?
    let local: Bool?
    let relay: Bool?
    let ipv6: Bool?

    var url: URL? {
        guard let text = uri?.nonBlank,
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        return url
    }

    var endpoint: PlexConnectionEndpoint? {
        guard let url else { return nil }
        let kind: PlexConnectionKind
        if relay == true {
            kind = .relay
        } else if local == true {
            kind = .local
        } else {
            kind = .remote
        }
        return PlexConnectionEndpoint(url: url, kind: kind)
    }

    fileprivate var preferenceRank: Int {
        let securePenalty = url?.scheme?.lowercased() == "https" ? 0 : 1
        if relay == true { return 4 + securePenalty }
        if local == true { return securePenalty }
        return 2 + securePenalty
    }

    private enum CodingKeys: String, CodingKey {
        case address, port, uri, local, relay
        case protocolName = "protocol"
        case ipv6 = "IPv6"
    }
}

// Some Plex endpoints wrap resources in MediaContainer while the current
// account resources endpoint returns a top-level array. Supporting both keeps
// discovery compatible with Plex server/API versions in the wild.
struct PlexResourceEnvelope: Decodable {
    let MediaContainer: PlexResourceContainer?
}

struct PlexResourceContainer: Decodable {
    let Device: [PlexServerResource]?
}

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
