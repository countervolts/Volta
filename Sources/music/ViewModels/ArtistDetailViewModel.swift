import UIKit
import Observation

@MainActor
@Observable
final class ArtistDetailViewModel {
    let seedArtist: Artist

    var fullArtist: Artist?
    var topSongs: [Song] = []
    var info: ArtistInfo?
    // bio is stripped of HTML once here, off the render path — doing it in the
    // view body spun NSAttributedString's WebKit parser (a nested run loop) during
    // the SwiftUI update and aborted the app.
    var biography: String?
    var dominantColor: UIColor = .black
    var isLoading = false
    var isDescriptionExpanded = false
    var topSongsExpanded = false

    init(artist: Artist) {
        self.seedArtist = artist
    }

    var displayArtist: Artist { fullArtist ?? seedArtist }
    // newest → oldest by year, then by created date as a tiebreaker
    var albums: [Album] {
        (fullArtist?.album ?? []).sorted {
            ($0.year ?? Int.min, $0.createdDate ?? .distantPast) >
            ($1.year ?? Int.min, $1.createdDate ?? .distantPast)
        }
    }
    var similarArtists: [Artist] { info?.similarArtist ?? [] }

    // albums the artist is featured on but didn't create (basic heuristic via search)
    var appearsOn: [Album] = []

    var artistImage: UIImage?
    // true once the profile-photo lookup has finished — until then the view shows a
    // neutral placeholder instead of flashing an album cover as the profile picture.
    var artworkResolved = false

    // all known songs to seed the play button (top songs first)
    var allSongs: [Song] { topSongs }

    func load(client: SubsonicClient) async {
        isLoading = true
        defer { isLoading = false }

        // Local prefetched/pinned profile photos win first; this keeps artist
        // pages responsive even when the server image URL is slow.
        if let img = await ArtworkLoader.shared.pinnedArtistImage(id: seedArtist.id) {
            artistImage = img
            dominantColor = ColorExtractor.dominantColor(from: img)
        } else {
            // show whatever photo we already have a URL for straight away so the header
            // isn't stuck on a placeholder while the rest of the metadata loads.
            await applyImage(from: seedArtist.artistImageUrl)
        }

        async let artistReq  = client.artist(id: seedArtist.id)
        async let infoReq    = client.artistInfo(id: seedArtist.id)
        async let songsReq   = client.topSongs(artistName: seedArtist.name, count: 15)
        fullArtist = try? await artistReq
        info       = try? await infoReq
        topSongs   = (try? await songsReq) ?? []

        let stripped = info?.biography?.strippingHTML
        biography = (stripped?.isEmpty == false) ? stripped : nil

        // upgrade to the best real photo (getArtistInfo2 → last.fm/spotify) if we
        // didn't already resolve one. cached via ArtworkLoader so revisits + the
        // prefetch setting make this instant.
        if artistImage == nil {
            for urlStr in [info?.bestImageUrl, fullArtist?.artistImageUrl].compactMap({ $0 }) {
                if await applyImage(from: urlStr) { break }
            }
        }
        // offline fallback: the photo pinned when this artist's songs were downloaded
        // (keyed by artist id, so it resolves with no network).
        if artistImage == nil, let img = await ArtworkLoader.shared.pinnedArtistImage(id: seedArtist.id) {
            artistImage = img
            dominantColor = ColorExtractor.dominantColor(from: img)
        }
        // resolve the header BEFORE the slow "Appeared On" search so the picture
        // never waits on it (this was the "shows only after pressing More" bug).
        artworkResolved = true

        // "Appeared On": search albums by the artist name, drop their own discography
        let ownAlbumIDs = Set(albums.map(\.id))
        let ownID = fullArtist?.id ?? seedArtist.id
        if let found = try? await client.search(query: seedArtist.name, artistCount: 0, albumCount: 30, songCount: 0).albums {
            appearsOn = found.filter { !ownAlbumIDs.contains($0.id) && $0.artistId != ownID }
        }
    }

    // loads + caches an artist photo from a URL string; returns true on success.
    @discardableResult
    private func applyImage(from urlStr: String?) async -> Bool {
        guard let urlStr, !urlStr.isEmpty, !urlStr.hasSuffix("/"),
              let url = URL(string: urlStr),
              let img = await ArtworkLoader.shared.image(for: url, maxPixelSize: 1100) else { return false }
        artistImage = img
        dominantColor = ColorExtractor.dominantColor(from: img)
        return true
    }

    func setDominantColor(_ color: UIColor) { dominantColor = color }
    func toggleBio() { isDescriptionExpanded.toggle() }
    func toggleTopSongsExpanded() { topSongsExpanded.toggle() }
}
