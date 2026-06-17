import Foundation

struct MediaItem: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case album, playlist }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String?
    let coverArt: String?
    let sortDate: Date?

    // Full models for navigation/detail.
    let albumRef: Album?
    let playlistRef: Playlist?

    init(album: Album) {
        id = album.id
        kind = .album
        title = album.name
        subtitle = album.displayArtist
        coverArt = album.coverArt
        sortDate = album.createdDate
        albumRef = album
        playlistRef = nil
    }

    init(playlist: Playlist) {
        id = playlist.id
        kind = .playlist
        title = playlist.name
        subtitle = nil
        coverArt = playlist.coverArt ?? playlist.id
        sortDate = playlist.playedDate ?? playlist.changedDate
        albumRef = nil
        playlistRef = playlist
    }
}
