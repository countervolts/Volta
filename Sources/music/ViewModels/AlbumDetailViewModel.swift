import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AlbumDetailViewModel {
    private(set) var album: Album
    private(set) var songs: [Song] = []
    private(set) var moreBySameArtist: [Album] = []
    private(set) var isLoading = false
    private(set) var dominantColor: UIColor = .black

    private(set) var isDescriptionExpanded = false

    var discNumbers: [Int] {
        let set = Set(songs.compactMap { $0.discNumber })
        return set.sorted()
    }

    func songs(forDisc disc: Int) -> [Song] {
        if discNumbers.count <= 1 { return songs }
        return songs.filter { ($0.discNumber ?? 1) == disc }
    }

    init(album: Album) {
        self.album = album
        self.songs = album.song ?? []
    }

    func load(client: SubsonicClient) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let albumID = album.id
        let artistID = album.artistId
        async let fullAlbum = client.album(id: albumID)
        async let artistAlbums: [Album] = {
            guard let id = artistID else { return [] }
            let artist = try? await client.artist(id: id)
            return artist?.album ?? []
        }()

        if let loaded = try? await fullAlbum {
            album = loaded
            songs = (loaded.song ?? []).sorted {
                let d0 = $0.discNumber ?? 1, d1 = $1.discNumber ?? 1
                if d0 != d1 { return d0 < d1 }
                return ($0.track ?? 0) < ($1.track ?? 0)
            }
        }
        moreBySameArtist = (await artistAlbums).filter { $0.id != album.id }
    }

    func setDominantColor(_ color: UIColor) {
        dominantColor = color
    }

    func toggleDescription() {
        isDescriptionExpanded.toggle()
    }
}
