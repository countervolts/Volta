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

    // Lossless only when every track is lossless.
    var isLossless: Bool {
        !songs.isEmpty && songs.allSatisfy(\.isLossless)
    }

    func songs(forDisc disc: Int) -> [Song] {
        if discNumbers.count <= 1 { return songs }
        return songs.filter { ($0.discNumber ?? 1) == disc }
    }

    init(album: Album) {
        self.album = album
        self.songs = album.song ?? []
    }

    func load(client: any MusicService) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let albumID = album.id
        let artistID = album.artistId
        let loadedAlbum: Album?
        let relatedAlbums: [Album]
        let loadArtistAlbums: () async -> [Album] = {
            guard let id = artistID else { return [] }
            let artist = try? await client.artist(id: id)
            return artist?.album ?? []
        }

        if DeveloperExperiments.constrainedConcurrency(default: 2) == 1 {
            loadedAlbum = try? await client.album(id: albumID)
            relatedAlbums = await loadArtistAlbums()
        } else {
            async let fullAlbum = client.album(id: albumID)
            async let artistAlbums = loadArtistAlbums()
            loadedAlbum = try? await fullAlbum
            relatedAlbums = await artistAlbums
        }

        let sortTracks: ([Song]) -> [Song] = { list in
            list.sorted {
                let d0 = $0.discNumber ?? 1, d1 = $1.discNumber ?? 1
                if d0 != d1 { return d0 < d1 }
                return ($0.track ?? 0) < ($1.track ?? 0)
            }
        }

        if let loaded = loadedAlbum, !(loaded.song ?? []).isEmpty {
            album = loaded
            songs = sortTracks(loaded.song ?? [])
        } else if songs.isEmpty {
            // Offline fallback: show this album's downloaded tracks.
            let local = DownloadService.shared.downloadedSongs().filter { $0.albumId == album.id }
            if !local.isEmpty { songs = sortTracks(local) }
        }
        moreBySameArtist = relatedAlbums.filter { $0.id != album.id }
    }

    func setDominantColor(_ color: UIColor) {
        dominantColor = color
    }

    func toggleDescription() {
        isDescriptionExpanded.toggle()
    }
}
