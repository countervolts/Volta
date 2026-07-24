import Foundation

// Decode-only Jellyfin/Emby DTOs. PascalCase matches the wire JSON.
// Fields stay optional because server versions disagree.

struct JFAuthResponse: Decodable {
    let User: JFUser?
    let AccessToken: String?
    struct JFUser: Decodable {
        let Id: String?

        enum CodingKeys: String, CodingKey { case Id }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            Id = container.flexibleStringIfPresent(forKey: .Id)
        }
    }
}

struct JFSystemInfo: Decodable {
    let Version: String?
    let ProductName: String?
}

struct JFItemCounts: Decodable {
    let ArtistCount: Int?
    let AlbumCount: Int?
    let SongCount: Int?

    enum CodingKeys: String, CodingKey {
        case ArtistCount, AlbumCount, SongCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ArtistCount = container.flexibleIntIfPresent(forKey: .ArtistCount)
        AlbumCount = container.flexibleIntIfPresent(forKey: .AlbumCount)
        SongCount = container.flexibleIntIfPresent(forKey: .SongCount)
    }
}

struct JFItemsResponse: Decodable {
    let Items: [JFItem]?
    let TotalRecordCount: Int?

    enum CodingKeys: String, CodingKey {
        case Items, TotalRecordCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let lossy = try? container.decodeIfPresent([LossyDecodable<JFItem>].self, forKey: .Items) {
            Items = lossy.compactMap(\.value)
        } else {
            Items = nil
        }
        TotalRecordCount = container.flexibleIntIfPresent(forKey: .TotalRecordCount)
    }
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

    enum CodingKeys: String, CodingKey {
        case Id, Name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        Id = container.flexibleStringIfPresent(forKey: .Id)
        Name = container.flexibleStringIfPresent(forKey: .Name)
    }
}

struct JFUserData: Decodable {
    let IsFavorite: Bool?
    let PlayCount: Int?
    let Played: Bool?

    enum CodingKeys: String, CodingKey {
        case IsFavorite, PlayCount, Played
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        IsFavorite = container.flexibleBoolIfPresent(forKey: .IsFavorite)
        PlayCount = container.flexibleIntIfPresent(forKey: .PlayCount)
        Played = container.flexibleBoolIfPresent(forKey: .Played)
    }
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        streamType = container.flexibleStringIfPresent(forKey: .streamType)
        Codec = container.flexibleStringIfPresent(forKey: .Codec)
        BitDepth = container.flexibleIntIfPresent(forKey: .BitDepth)
        SampleRate = container.flexibleIntIfPresent(forKey: .SampleRate)
        Channels = container.flexibleIntIfPresent(forKey: .Channels)
        BitRate = container.flexibleIntIfPresent(forKey: .BitRate)
    }
}

struct JFMediaSource: Decodable {
    let Container: String?
    let Size: Int?
    let Bitrate: Int?
    let MediaStreams: [JFMediaStream]?

    enum CodingKeys: String, CodingKey {
        case Container, Size, Bitrate, MediaStreams
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        Container = container.flexibleStringIfPresent(forKey: .Container)
        Size = container.flexibleIntIfPresent(forKey: .Size)
        Bitrate = container.flexibleIntIfPresent(forKey: .Bitrate)
        MediaStreams = container.lossyArrayIfPresent(forKey: .MediaStreams)
    }
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = container.flexibleStringIfPresent(forKey: .Id), !id.isEmpty else {
            throw DecodingError.keyNotFound(
                CodingKeys.Id,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing item Id")
            )
        }
        Id = id
        Name = container.flexibleStringIfPresent(forKey: .Name)
        itemType = container.flexibleStringIfPresent(forKey: .itemType)
        AlbumArtist = container.flexibleStringIfPresent(forKey: .AlbumArtist)
        AlbumArtists = container.lossyArrayIfPresent(forKey: .AlbumArtists)
            ?? container.singleValueArrayIfPresent(forKey: .AlbumArtists)
        ArtistItems = container.lossyArrayIfPresent(forKey: .ArtistItems)
            ?? container.singleValueArrayIfPresent(forKey: .ArtistItems)
        Artists = container.flexibleStringArrayIfPresent(forKey: .Artists)
        AlbumId = container.flexibleStringIfPresent(forKey: .AlbumId)
        albumName = container.flexibleStringIfPresent(forKey: .albumName)
        ProductionYear = container.flexibleIntIfPresent(forKey: .ProductionYear)
        Genres = container.flexibleStringArrayIfPresent(forKey: .Genres)
        RunTimeTicks = container.flexibleInt64IfPresent(forKey: .RunTimeTicks)
        IndexNumber = container.flexibleIntIfPresent(forKey: .IndexNumber)
        ParentIndexNumber = container.flexibleIntIfPresent(forKey: .ParentIndexNumber)
        ChildCount = container.flexibleIntIfPresent(forKey: .ChildCount)
        UserData = try? container.decodeIfPresent(JFUserData.self, forKey: .UserData)
        MediaSources = container.lossyArrayIfPresent(forKey: .MediaSources)
        DateCreated = container.flexibleStringIfPresent(forKey: .DateCreated)
        Path = container.flexibleStringIfPresent(forKey: .Path)
        Overview = container.flexibleStringIfPresent(forKey: .Overview)
        CollectionType = container.flexibleStringIfPresent(forKey: .CollectionType)
        IsFolder = container.flexibleBoolIfPresent(forKey: .IsFolder)
        Container = container.flexibleStringIfPresent(forKey: .Container)
        PlaylistItemId = container.flexibleStringIfPresent(forKey: .PlaylistItemId)
        ImageTags = container.flexibleStringDictionaryIfPresent(forKey: .ImageTags)
        PrimaryImageTag = container.flexibleStringIfPresent(forKey: .PrimaryImageTag)
        PrimaryImageItemId = container.flexibleStringIfPresent(forKey: .PrimaryImageItemId)
        AlbumPrimaryImageTag = container.flexibleStringIfPresent(forKey: .AlbumPrimaryImageTag)
    }
}

private struct LossyDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private extension KeyedDecodingContainer {
    func flexibleStringIfPresent(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Int64.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }
        return nil
    }

    func flexibleIntIfPresent(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int64.self, forKey: key) {
            return Int(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    func flexibleInt64IfPresent(forKey key: Key) -> Int64? {
        if let value = try? decodeIfPresent(Int64.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Int64(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int64(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int64(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    func flexibleBoolIfPresent(forKey key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value != 0
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        return nil
    }

    func flexibleStringArrayIfPresent(forKey key: Key) -> [String]? {
        if let values = try? decodeIfPresent([String].self, forKey: key) {
            return values
        }
        if let value = flexibleStringIfPresent(forKey: key) {
            return value.isEmpty ? [] : [value]
        }
        return nil
    }

    func flexibleStringDictionaryIfPresent(forKey key: Key) -> [String: String]? {
        guard let raw = try? decodeIfPresent([String: FlexibleStringValue].self, forKey: key) else {
            return nil
        }
        return raw.mapValues(\.value)
    }

    func lossyArrayIfPresent<Value: Decodable>(forKey key: Key) -> [Value]? {
        guard let values = try? decodeIfPresent([LossyDecodable<Value>].self, forKey: key) else {
            return nil
        }
        return values.compactMap(\.value)
    }

    func singleValueArrayIfPresent<Value: Decodable>(forKey key: Key) -> [Value]? {
        guard let value = try? decodeIfPresent(Value.self, forKey: key) else {
            return nil
        }
        return [value]
    }
}

private struct FlexibleStringValue: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else if let int64 = try? container.decode(Int64.self) {
            value = String(int64)
        } else if let double = try? container.decode(Double.self) {
            value = String(double)
        } else if let bool = try? container.decode(Bool.self) {
            value = bool ? "true" : "false"
        } else {
            value = ""
        }
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
        if let tag = primaryImageTag, !tag.isEmpty {
            return Self.imageID(id: PrimaryImageItemId ?? Id, tag: tag)
        }
        if let PrimaryImageItemId, !PrimaryImageItemId.isEmpty {
            return PrimaryImageItemId
        }
        if itemType == "Audio" {
            return AlbumId
        }
        return ownCoverArtID ?? AlbumId
    }

    private var ownCoverArtID: String? {
        if let tag = primaryImageTag, !tag.isEmpty {
            return Self.imageID(id: PrimaryImageItemId ?? Id, tag: tag)
        }
        if let PrimaryImageItemId, !PrimaryImageItemId.isEmpty {
            return PrimaryImageItemId
        }
        guard itemType != "Audio" else { return nil }
        return Id
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
