import Foundation

struct SubsonicEnvelope: Decodable, Sendable {
    let response: Body

    enum CodingKeys: String, CodingKey {
        case response = "subsonic-response"
    }

    struct Body: Decodable, Sendable {
        let status: String?
        let version: String?
        let type: String?
        let error: ErrorPayload?

        let albumList2: AlbumListContainer?
        let randomSongs: SongsContainer?
        let playlists: PlaylistsContainer?
        let playlist: Playlist?
        let artists: ArtistsIndexContainer?
        let artist: Artist?
        let artistInfo2: ArtistInfo?
        let topSongs: SongsContainer?
        let songsByGenre: SongsContainer?
        let album: Album?
        let song: Song?
        let starred2: Starred2Container?
        let searchResult3: SearchResult3Container?
        let lyricsList: LyricsList?
        let lyrics: PlainLyricsPayload?
        let shares: SharesContainer?
        // folder/directory browsing
        let musicFolders: MusicFoldersContainer?
        let indexes: IndexesContainer?
        let directory: DirectoryContainer?

        var isOK: Bool { status == "ok" }
    }

    struct SharesContainer: Decodable, Sendable {
        let share: [Share]?
    }

    struct ErrorPayload: Decodable, Sendable {
        let code: Int?
        let message: String?
    }

    struct AlbumListContainer: Decodable, Sendable {
        let album: [Album]?
    }

    struct SongsContainer: Decodable, Sendable {
        let song: [Song]?
    }

    struct PlaylistsContainer: Decodable, Sendable {
        let playlist: [Playlist]?
    }

    struct ArtistsIndexContainer: Decodable, Sendable {
        let index: [ArtistIndex]?
    }

    struct ArtistIndex: Decodable, Sendable {
        let name: String?
        let artist: [Artist]?
    }

    struct Starred2Container: Decodable, Sendable {
        let album: [Album]?
        let song: [Song]?
        let artist: [Artist]?
    }

    struct SearchResult3Container: Decodable, Sendable {
        let artist: [Artist]?
        let album: [Album]?
        let song: [Song]?
    }

    struct PlainLyricsPayload: Decodable, Sendable {
        let artist: String?
        let title: String?
        let value: String?
    }
}
