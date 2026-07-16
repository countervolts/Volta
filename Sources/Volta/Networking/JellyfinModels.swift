import Foundation

// Decode-only Jellyfin/Emby DTOs. PascalCase matches the wire JSON.
// Fields stay optional because server versions disagree.

struct JFAuthResponse: Decodable {
    let User: JFUser?
    let AccessToken: String?
    struct JFUser: Decodable { let Id: String? }
}

struct JFSystemInfo: Decodable {
    let Version: String?
    let ProductName: String?
}

struct JFItemCounts: Decodable {
    let ArtistCount: Int?
    let AlbumCount: Int?
    let SongCount: Int?
}

struct JFItemsResponse: Decodable {
    let Items: [JFItem]?
    let TotalRecordCount: Int?
}

struct JFCreatePlaylistResponse: Decodable {
    let Id: String?
}

struct JFLyricsResponse: Decodable {
    let Lyrics: [JFLyricLine]?
    struct JFLyricLine: Decodable {
        let Text: String?
        let Start: Int64?   // ticks (100ns); convert to ms with /10_000
    }
}

struct JFNameGuidPair: Decodable {
    let Id: String?
    let Name: String?
}

struct JFUserData: Decodable {
    let IsFavorite: Bool?
    let PlayCount: Int?
    let Played: Bool?
}

struct JFMediaStream: Decodable {
    let streamType: String?   // JSON "Type"
    let Codec: String?
    let BitDepth: Int?
    let SampleRate: Int?
    let Channels: Int?
    let BitRate: Int?

    enum CodingKeys: String, CodingKey {
        case streamType = "Type"
        case Codec, BitDepth, SampleRate, Channels, BitRate
    }
}

struct JFMediaSource: Decodable {
    let Container: String?
    let Size: Int?
    let Bitrate: Int?
    let MediaStreams: [JFMediaStream]?
}

// Album, artist, song, playlist, or folder.
struct JFItem: Decodable {
    let Id: String
    let Name: String?
    let itemType: String?     // JSON "Type"
    let AlbumArtist: String?
    let AlbumArtists: [JFNameGuidPair]?
    let ArtistItems: [JFNameGuidPair]?
    let Artists: [String]?
    let AlbumId: String?
    let albumName: String?     // JSON "Album"
    let ProductionYear: Int?
    let Genres: [String]?
    let RunTimeTicks: Int64?
    let IndexNumber: Int?
    let ParentIndexNumber: Int?
    let ChildCount: Int?
    let UserData: JFUserData?
    let MediaSources: [JFMediaSource]?
    let DateCreated: String?
    let Path: String?
    let Overview: String?
    let CollectionType: String?
    let IsFolder: Bool?
    let Container: String?
    let PlaylistItemId: String?
    let ImageTags: [String: String]?
    let PrimaryImageTag: String?
    let PrimaryImageItemId: String?
    let AlbumPrimaryImageTag: String?

    enum CodingKeys: String, CodingKey {
        case Id, Name
        case itemType = "Type"
        case AlbumArtist, AlbumArtists, ArtistItems, Artists, AlbumId
        case albumName = "Album"
        case ProductionYear, Genres, RunTimeTicks, IndexNumber, ParentIndexNumber, ChildCount
        case UserData, MediaSources, DateCreated, Path, Overview
        case CollectionType, IsFolder, Container, PlaylistItemId
        case ImageTags, PrimaryImageTag, PrimaryImageItemId, AlbumPrimaryImageTag
    }
}

// MARK: - Mapping to app models

extension JFItem {
    private var durationSeconds: Int? {
        RunTimeTicks.map { Int($0 / 10_000_000) }
    }

    // album-artist pair for albums and artists
    private var albumArtistName: String? {
        AlbumArtist ?? AlbumArtists?.first?.Name ?? ArtistItems?.first?.Name ?? Artists?.first
    }
    private var albumArtistId: String? {
        AlbumArtists?.first?.Id ?? ArtistItems?.first?.Id
    }

    // track artist, preferring performer over album artist
    private var trackArtistName: String? {
        Artists?.first ?? AlbumArtist ?? AlbumArtists?.first?.Name
    }

    private var starredMarker: String? {
        (UserData?.IsFavorite == true) ? "starred" : nil
    }

    private var primaryImageTag: String? {
        ImageTags?["Primary"] ?? PrimaryImageTag
    }

    private var albumCoverArtID: String? {
        if let AlbumPrimaryImageTag, !AlbumPrimaryImageTag.isEmpty {
            return Self.imageID(id: AlbumId ?? PrimaryImageItemId ?? Id, tag: AlbumPrimaryImageTag)
        }
        if let PrimaryImageItemId, !PrimaryImageItemId.isEmpty {
            return Self.imageID(id: PrimaryImageItemId, tag: primaryImageTag)
        }
        return ownCoverArtID ?? AlbumId
    }

    private var ownCoverArtID: String? {
        Self.imageID(id: PrimaryImageItemId ?? Id, tag: primaryImageTag)
    }

    static func imageID(id: String?, tag: String?) -> String? {
        guard let id, !id.isEmpty else { return nil }
        guard let tag, !tag.isEmpty else { return id }
        return "\(id)::\(tag)"
    }

    var asAlbum: Album { asAlbum(withSongs: nil) }

    func asAlbum(withSongs songs: [Song]?) -> Album {
        Album(
            id: Id,
            name: Name ?? "Unknown Album",
            artist: albumArtistName,
            artistId: albumArtistId,
            coverArt: ownCoverArtID,
            songCount: ChildCount ?? songs?.count,
            duration: durationSeconds,
            playCount: UserData?.PlayCount,
            created: DateCreated,
            year: ProductionYear,
            genre: Genres?.first,
            starred: starredMarker,
            comment: nil,
            recordLabel: nil,
            song: songs
        )
    }

    var asArtist: Artist { asArtist(withAlbums: nil) }

    func asArtist(withAlbums albums: [Album]?) -> Artist {
        Artist(
            id: Id,
            name: Name ?? "Unknown Artist",
            coverArt: ownCoverArtID,
            albumCount: albums?.count ?? ChildCount,
            artistImageUrl: nil,
            starred: starredMarker,
            album: albums
        )
    }

    var asSong: Song {
        let source = MediaSources?.first
        let audio = source?.MediaStreams?.first { ($0.streamType ?? "") == "Audio" }
        let container = source?.Container ?? Container
        let bitrateKbps = (source?.Bitrate ?? audio?.BitRate).map { $0 / 1000 }
        return Song(
            id: Id,
            title: Name ?? "Unknown",
            album: albumName,
            artist: trackArtistName,
            albumArtist: albumArtistName,
            albumId: AlbumId,
            artistId: ArtistItems?.first?.Id ?? albumArtistId,
            albumArtistId: albumArtistId,
            coverArt: albumCoverArtID,
            duration: durationSeconds,
            track: IndexNumber,
            discNumber: ParentIndexNumber,
            year: ProductionYear,
            genre: Genres?.first,
            size: source?.Size,
            contentType: nil,
            suffix: container?.lowercased(),
            codec: audio?.Codec?.lowercased(),
            bitRate: bitrateKbps,
            path: Path,
            playCount: UserData?.PlayCount,
            bpm: nil,                       // Jellyfin does not expose BPM metadata
            explicitStatus: nil,
            starred: starredMarker,
            contributes: nil,
            replayGain: nil,
            samplingRate: audio?.SampleRate,
            bitDepth: audio?.BitDepth,
            channelCount: audio?.Channels,
            displayComposer: nil,
            contributors: nil
        )
    }

    var asPlaylist: Playlist { asPlaylist(withEntries: nil) }

    func asPlaylist(withEntries entries: [Song]?) -> Playlist {
        Playlist(
            id: Id,
            name: Name ?? "Playlist",
            comment: Overview,
            owner: nil,
            songCount: ChildCount ?? entries?.count,
            duration: durationSeconds,
            created: DateCreated,
            changed: nil,
            played: nil,
            coverArt: ownCoverArtID,
            entry: entries
        )
    }

    var asBrowseEntry: BrowseEntry {
        let isDir = (IsFolder ?? false)
            || itemType == "MusicArtist" || itemType == "MusicAlbum" || itemType == "Folder"
        return BrowseEntry(
            id: Id,
            name: Name ?? "Unknown",
            isDirectory: isDir,
            coverArt: ownCoverArtID,
            song: isDir ? nil : asSong
        )
    }
}
