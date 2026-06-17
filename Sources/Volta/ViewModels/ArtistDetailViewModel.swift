import UIKit
import Observation

@MainActor
@Observable
final class ArtistDetailViewModel {
    let seedArtist: Artist

    var fullArtist: Artist?
    var albums: [Album] = []
    var topSongs: [Song] = []
    var allSongs: [Song] = []
    var info: ArtistInfo?
    // Keep HTML parsing out of the render path.
    var biography: String?
    var dominantColor: UIColor = .black
    var isLoading = false
    var isDescriptionExpanded = false
    var topSongsExpanded = false

    init(artist: Artist) {
        self.seedArtist = artist
    }

    var displayArtist: Artist { fullArtist ?? seedArtist }
    var similarArtists: [Artist] { info?.similarArtist ?? [] }

    var appearsOn: [Album] = []
    var albumReleases: [Album] { albums.filter { !Self.isSingle($0) } }
    var singles: [Album] { albums.filter { Self.isSingle($0) } }

    var artistImage: UIImage?
    var artworkResolved = false

    func load(client: any MusicService) async {
        isLoading = true
        defer { isLoading = false }

        if let img = await ArtworkLoader.shared.pinnedArtistImage(id: seedArtist.id) {
            artistImage = img
            dominantColor = ColorExtractor.dominantColor(from: img)
        } else {
            await applyImage(from: seedArtist.artistImageUrl)
        }

        if DeveloperExperiments.constrainedConcurrency(default: 4) < 4 {
            let loadedArtist = try? await client.artist(id: seedArtist.id)
            fullArtist = loadedArtist
            albums = Self.sortedAlbums(loadedArtist?.album ?? [])
            info = try? await client.artistInfo(id: seedArtist.id)
            topSongs = (try? await client.topSongs(artistName: seedArtist.name, count: 15)) ?? []
            allSongs = (try? await client.songsForArtist(id: seedArtist.id)) ?? topSongs
        } else {
            async let artistReq  = client.artist(id: seedArtist.id)
            async let infoReq    = client.artistInfo(id: seedArtist.id)
            async let songsReq   = client.topSongs(artistName: seedArtist.name, count: 15)
            async let allSongsReq = client.songsForArtist(id: seedArtist.id)
            let loadedArtist = try? await artistReq
            fullArtist = loadedArtist
            albums = Self.sortedAlbums(loadedArtist?.album ?? [])
            info       = try? await infoReq
            topSongs   = (try? await songsReq) ?? []
            allSongs   = (try? await allSongsReq) ?? topSongs
        }
        applyDownloadedFallbackIfNeeded()
        applyHiddenAlbumFilters()

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
            HiddenAlbumStore.shared.register(albums: found)
            appearsOn = HiddenAlbumStore.shared.visibleAlbums(found).filter { !ownAlbumIDs.contains($0.id) && $0.artistId != ownID }
        }
    }

    private func applyHiddenAlbumFilters() {
        HiddenAlbumStore.shared.register(albums: albums)
        albums = HiddenAlbumStore.shared.visibleAlbums(albums)
        topSongs = HiddenAlbumStore.shared.visibleSongs(topSongs)
        allSongs = HiddenAlbumStore.shared.visibleSongs(allSongs)
        if let fullArtist {
            self.fullArtist = fullArtist.replacingAlbums(albums)
        }
    }

    private func applyDownloadedFallbackIfNeeded() {
        let local = DownloadService.shared.downloadedSongs().filter { song in
            if let artistId = song.artistId, artistId == seedArtist.id { return true }
            return Self.primaryArtistName(song.artist)
                .localizedCaseInsensitiveCompare(Self.primaryArtistName(seedArtist.name)) == .orderedSame
        }
        guard !local.isEmpty else { return }

        let sortedSongs = local.sorted {
            let albumCompare = ($0.album ?? "").localizedCaseInsensitiveCompare($1.album ?? "")
            if albumCompare != .orderedSame { return albumCompare == .orderedAscending }
            let d0 = $0.discNumber ?? 1
            let d1 = $1.discNumber ?? 1
            if d0 != d1 { return d0 < d1 }
            return ($0.track ?? 0) < ($1.track ?? 0)
        }

        if topSongs.isEmpty { topSongs = Array(sortedSongs.prefix(15)) }
        if allSongs.isEmpty { allSongs = sortedSongs }
        if albums.isEmpty {
            albums = Self.synthesizedAlbums(from: sortedSongs, artist: seedArtist)
        }
        if fullArtist == nil {
            fullArtist = Artist(
                id: seedArtist.id,
                name: seedArtist.name,
                coverArt: seedArtist.coverArt ?? sortedSongs.first?.coverArt,
                albumCount: albums.count,
                artistImageUrl: seedArtist.artistImageUrl,
                starred: seedArtist.starred,
                album: albums
            )
        }
    }

    private static func synthesizedAlbums(from songs: [Song], artist: Artist) -> [Album] {
        let grouped = Dictionary(grouping: songs) { song in
            song.albumId ?? "downloaded-\(song.album ?? "unknown")"
        }
        return grouped.map { id, tracks in
            let sorted = tracks.sorted {
                let d0 = $0.discNumber ?? 1
                let d1 = $1.discNumber ?? 1
                if d0 != d1 { return d0 < d1 }
                return ($0.track ?? 0) < ($1.track ?? 0)
            }
            let first = sorted[0]
            return Album(
                id: id,
                name: first.album ?? "Unknown Album",
                artist: artist.name,
                artistId: artist.id,
                coverArt: first.coverArt,
                songCount: sorted.count,
                duration: sorted.compactMap(\.duration).reduce(0, +),
                playCount: nil,
                created: nil,
                year: first.year,
                genre: first.genre,
                starred: nil,
                comment: nil,
                recordLabel: nil,
                song: sorted
            )
        }
        .sorted {
            ($0.year ?? Int.min, $0.name) > ($1.year ?? Int.min, $1.name)
        }
    }

    private static func primaryArtistName(_ name: String?) -> String {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Unknown Artist"
        }
        var earliest = name.endIndex
        for token in [" featuring ", " feat. ", " feat ", " ft. ", " ft ",
                      " & ", " x ", " and ", ",", ";", " / ", "/"] {
            if let range = name.range(of: token, options: .caseInsensitive),
               range.lowerBound < earliest {
                earliest = range.lowerBound
            }
        }
        let primary = String(name[..<earliest]).trimmingCharacters(in: .whitespacesAndNewlines)
        return primary.isEmpty ? name : primary
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

    private static func sortedAlbums(_ albums: [Album]) -> [Album] {
        albums.sorted {
            ($0.year ?? Int.min, $0.createdDate ?? .distantPast) >
            ($1.year ?? Int.min, $1.createdDate ?? .distantPast)
        }
    }

    private static func isSingle(_ album: Album) -> Bool {
        if let songCount = album.songCount { return songCount == 1 }
        if let songs = album.song { return songs.count == 1 }
        return false
    }
}
