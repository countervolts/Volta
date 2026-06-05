import Foundation

// Models for the folder/directory browser (getMusicFolders / getIndexes /
// getMusicDirectory). These mirror the raw Subsonic file tree, which is useful on
// servers where the tag-based (id3) metadata is messy or incomplete.

struct MusicFolder: Identifiable, Hashable, Sendable, Decodable {
    let id: String
    let name: String

    enum CodingKeys: String, CodingKey { case id, name }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexibleID(.id)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Music"
    }
}

// a node in the file tree: either a sub-directory to drill into or a playable song.
struct BrowseEntry: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let isDirectory: Bool
    let coverArt: String?
    let song: Song?   // present when !isDirectory
}

// raw getMusicDirectory / getIndexes child. Decoded leniently because servers vary
// wildly in which fields they populate and whether ids arrive as strings or ints.
struct Child: Decodable, Sendable {
    let id: String
    let isDir: Bool
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

    enum CodingKeys: String, CodingKey {
        case id, isDir, title, album, artist, albumId, artistId, coverArt
        case duration, track, discNumber, year, genre, size, contentType, suffix
        case bitRate, path, playCount, starred
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexibleID(.id)
        isDir = (try? c.decode(Bool.self, forKey: .isDir)) ?? false
        title = (try? c.decode(String.self, forKey: .title)) ?? "Unknown"
        album = try? c.decode(String.self, forKey: .album)
        artist = try? c.decode(String.self, forKey: .artist)
        albumId = c.flexibleIDIfPresent(.albumId)
        artistId = c.flexibleIDIfPresent(.artistId)
        coverArt = c.flexibleIDIfPresent(.coverArt)
        duration = try? c.decode(Int.self, forKey: .duration)
        track = try? c.decode(Int.self, forKey: .track)
        discNumber = try? c.decode(Int.self, forKey: .discNumber)
        year = try? c.decode(Int.self, forKey: .year)
        genre = try? c.decode(String.self, forKey: .genre)
        size = try? c.decode(Int.self, forKey: .size)
        contentType = try? c.decode(String.self, forKey: .contentType)
        suffix = try? c.decode(String.self, forKey: .suffix)
        bitRate = try? c.decode(Int.self, forKey: .bitRate)
        path = try? c.decode(String.self, forKey: .path)
        playCount = try? c.decode(Int.self, forKey: .playCount)
        starred = try? c.decode(String.self, forKey: .starred)
    }

    var asSong: Song {
        Song(id: id, title: title, album: album, artist: artist, albumId: albumId,
             artistId: artistId, coverArt: coverArt, duration: duration, track: track,
             discNumber: discNumber, year: year, genre: genre, size: size,
             contentType: contentType, suffix: suffix, bitRate: bitRate, path: path,
             playCount: playCount, starred: starred, contributes: nil, replayGain: nil,
             samplingRate: nil, bitDepth: nil, channelCount: nil, displayComposer: nil,
             contributors: nil)
    }

    var asBrowseEntry: BrowseEntry {
        BrowseEntry(id: id, name: title, isDirectory: isDir, coverArt: coverArt,
                    song: isDir ? nil : asSong)
    }
}

// getIndexes nests its top-level directories under `index[].artist[]` — a shortcut
// with just id + name (and sometimes a cover).
struct DirectoryRef: Decodable, Sendable {
    let id: String
    let name: String
    let coverArt: String?

    enum CodingKeys: String, CodingKey { case id, name, coverArt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexibleID(.id)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Unknown"
        coverArt = c.flexibleIDIfPresent(.coverArt)
    }

    var asBrowseEntry: BrowseEntry {
        BrowseEntry(id: id, name: name, isDirectory: true, coverArt: coverArt, song: nil)
    }
}

// MARK: - Response containers

struct MusicFoldersContainer: Decodable, Sendable {
    let musicFolder: [MusicFolder]?
}

struct IndexesContainer: Decodable, Sendable {
    let index: [FolderIndex]?
    let child: [Child]?
}

struct FolderIndex: Decodable, Sendable {
    let name: String?
    let artist: [DirectoryRef]?
}

struct DirectoryContainer: Decodable, Sendable {
    let id: String?
    let name: String?
    let child: [Child]?

    enum CodingKeys: String, CodingKey { case id, name, child }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexibleIDIfPresent(.id)
        name = try? c.decode(String.self, forKey: .name)
        child = try? c.decode([Child].self, forKey: .child)
    }
}

// MARK: - Flexible id decoding

extension KeyedDecodingContainer {
    // Subsonic ids are usually strings, but a few (notably music-folder ids) come
    // back as integers. Accept either and normalise to a String.
    func flexibleID(_ key: Key) -> String {
        if let s = try? decode(String.self, forKey: key) { return s }
        if let i = try? decode(Int.self, forKey: key) { return String(i) }
        return ""
    }

    func flexibleIDIfPresent(_ key: Key) -> String? {
        if let s = try? decode(String.self, forKey: key) { return s }
        if let i = try? decode(Int.self, forKey: key) { return String(i) }
        return nil
    }
}
