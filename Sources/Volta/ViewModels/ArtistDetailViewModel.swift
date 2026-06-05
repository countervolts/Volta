import UIKit
import Observation

@MainActor
@Observable
final class ArtistDetailViewModel {
    let seedArtist: Artist

    var fullArtist: Artist?
    var topSongs: [Song] = []
    var allSongs: [Song] = []
    var info: ArtistInfo?
    // Keep HTML parsing out of SwiftUI's render path.
    var biography: String?
    var dominantColor: UIColor = .black
    var isLoading = false
    var isDescriptionExpanded = false
    var topSongsExpanded = false

    init(artist: Artist) {
        self.seedArtist = artist
    }

    var displayArtist: Artist { fullArtist ?? seedArtist }
    var albums: [Album] {
        (fullArtist?.album ?? []).sorted {
            ($0.year ?? Int.min, $0.createdDate ?? .distantPast) >
            ($1.year ?? Int.min, $1.createdDate ?? .distantPast)
        }
    }
    var similarArtists: [Artist] { info?.similarArtist ?? [] }

    var appearsOn: [Album] = []

    var artistImage: UIImage?
    var artworkResolved = false

    func load(client: SubsonicClient) async {
        isLoading = true
        defer { isLoading = false }

        if let img = await ArtworkLoader.shared.pinnedArtistImage(id: seedArtist.id) {
            artistImage = img
            dominantColor = ColorExtractor.dominantColor(from: img)
        } else {
            await applyImage(from: seedArtist.artistImageUrl)
        }

        async let artistReq  = client.artist(id: seedArtist.id)
        async let infoReq    = client.artistInfo(id: seedArtist.id)
        async let songsReq   = client.topSongs(artistName: seedArtist.name, count: 15)
        async let allSongsReq = client.songsForArtist(id: seedArtist.id)
        fullArtist = try? await artistReq
        info       = try? await infoReq
        topSongs   = (try? await songsReq) ?? []
        allSongs   = (try? await allSongsReq) ?? topSongs

        let stripped = info?.biography?.strippingHTML
        biography = (stripped?.isEmpty == false) ? stripped : nil

        if artistImage == nil {
            for urlStr in [info?.bestImageUrl, fullArtist?.artistImageUrl].compactMap({ $0 }) {
                if await applyImage(from: urlStr) { break }
            }
        }
        if artistImage == nil, let img = await ArtworkLoader.shared.pinnedArtistImage(id: seedArtist.id) {
            artistImage = img
            dominantColor = ColorExtractor.dominantColor(from: img)
        }
        artworkResolved = true

        let ownAlbumIDs = Set(albums.map(\.id))
        let ownID = fullArtist?.id ?? seedArtist.id
        if let found = try? await client.search(query: seedArtist.name, artistCount: 0, albumCount: 30, songCount: 0).albums {
            appearsOn = found.filter { !ownAlbumIDs.contains($0.id) && $0.artistId != ownID }
        }
    }

    @discardableResult
    private func applyImage(from urlStr: String?) async -> Bool {
        guard let urlStr, !urlStr.isEmpty, !urlStr.hasSuffix("/"),
              let url = URL(string: urlStr),
              let img = await ArtworkLoader.shared.image(for: url, maxPixelSize: 900) else { return false }
        artistImage = img
        dominantColor = ColorExtractor.dominantColor(from: img)
        return true
    }

    func setDominantColor(_ color: UIColor) { dominantColor = color }
    func toggleBio() { isDescriptionExpanded.toggle() }
    func toggleTopSongsExpanded() { topSongsExpanded.toggle() }
}
