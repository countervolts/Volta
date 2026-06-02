import UIKit
import Observation

@MainActor
@Observable
final class ArtistDetailViewModel {
    let seedArtist: Artist

    var fullArtist: Artist?
    var topSongs: [Song] = []
    var info: ArtistInfo?
    var dominantColor: UIColor = .black
    var isLoading = false
    var isDescriptionExpanded = false
    var topSongsExpanded = false

    init(artist: Artist) {
        self.seedArtist = artist
    }

    var displayArtist: Artist { fullArtist ?? seedArtist }
    var albums: [Album] { fullArtist?.album ?? [] }
    var similarArtists: [Artist] { info?.similarArtist ?? [] }

    var artistImage: UIImage?

    func load(client: SubsonicClient) async {
        isLoading = true
        defer { isLoading = false }
        async let artistReq  = client.artist(id: seedArtist.id)
        async let infoReq    = client.artistInfo(id: seedArtist.id)
        async let songsReq   = client.topSongs(artistName: seedArtist.name, count: 15)
        fullArtist = try? await artistReq
        info       = try? await infoReq
        topSongs   = (try? await songsReq) ?? []

        // fetch the artist's real profile photo for display + color extraction.
        // prefer getArtistInfo2's dedicated artist images (last.fm/spotify), then
        // the artist's own artistImageUrl. album covers are only a last resort in
        // the view when none of these resolve.
        let candidates = [
            info?.bestImageUrl,
            fullArtist?.artistImageUrl,
            seedArtist.artistImageUrl,
        ].compactMap { $0 }.filter { !$0.isEmpty && !$0.hasSuffix("/") }

        for urlStr in candidates {
            guard let url = URL(string: urlStr),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let img = UIImage(data: data) else { continue }
            artistImage = img
            dominantColor = ColorExtractor.dominantColor(from: img)
            break
        }
    }

    func setDominantColor(_ color: UIColor) { dominantColor = color }
    func toggleBio() { isDescriptionExpanded.toggle() }
    func toggleTopSongsExpanded() { topSongsExpanded.toggle() }
}
