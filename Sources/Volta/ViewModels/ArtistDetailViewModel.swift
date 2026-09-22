import UIKit
import Combine

@MainActor
final class ArtistDetailViewModel: ObservableObject {
    let seedArtist: Artist

    @Published var fullArtist: Artist?
    @Published var albums: [Album] = []
    @Published var topSongs: [Song] = []
    @Published var allSongs: [Song] = []
    @Published var info: ArtistInfo?
    // Keep HTML parsing out of the render path.
    @Published var biography: String?
    @Published var dominantColor: UIColor = .black
    @Published var isLoading = false
    @Published var isDescriptionExpanded = false
    @Published var topSongsExpanded = false
    /// Whether the artist is favorited on the server, for the profile star.
    @Published var isStarred: Bool

    init(artist: Artist) {
        self.seedArtist = artist
        self.isStarred = artist.starred != nil
    }

    func setStarred(_ value: Bool) { isStarred = value }

    var displayArtist: Artist { fullArtist ?? seedArtist }
    var similarArtists: [Artist] { info?.similarArtist ?? [] }

    @Published var appearsOn: [Album] = []
    var albumReleases: [Album] { albums.filter { !Self.isSingle($0) } }
    var singles: [Album] { albums.filter { Self.isSingle($0) } }
    var likedSongs: [Song] { allSongs.filter { $0.starred != nil } }

    /// Newest release across albums and singles (used by the featured card).
    var latestRelease: Album? {
        albums.sorted {
            ($0.year ?? Int.min, $0.createdDate ?? .distantPast) >
            ($1.year ?? Int.min, $1.createdDate ?? .distantPast)
        }.first
    }

    /// Albums + singles in one "Albums & Singles" shelf, newest first.
    var albumsAndSingles: [Album] {
        albums.sorted {
            ($0.year ?? Int.min, $0.createdDate ?? .distantPast) >
            ($1.year ?? Int.min, $1.createdDate ?? .distantPast)
        }
    }

    /// Songs accumulated from every album on the profile (shown after the top
    /// songs shelf, matching Apple Music's long artist tracklist).
    @Published var accumulatedSongs: [Song] = []
    @Published var accumulatedExpanded = false

    var hasMoreAccumulated: Bool { accumulatedSongs.count > Self.accumulatedPageSize }
    private static let accumulatedPageSize = 8
    private var accumulatedVisibleCount: Int { accumulatedExpanded ? accumulatedSongs.count : Self.accumulatedPageSize }

    var visibleAccumulatedSongs: [Song] { Array(accumulatedSongs.prefix(accumulatedVisibleCount)) }

    func toggleAccumulated() { accumulatedExpanded.toggle() }

    @Published var artistImage: UIImage?
    @Published var artworkResolved = false

    func load(client: any MusicService) async {
        isLoading = true
        defer { isLoading = false }

        if let img = await ArtworkLoader.shared.pinnedArtistImage(id: seedArtist.id, serverID: AppState.shared.currentServer?.id) {
            setArtistImage(img)
        } else {
            await applyImage(from: seedArtist.artistImageUrl)
        }

        // Keep these requests ordered. The optimized build's sibling `async let`
        // teardown can abort in the Swift concurrency runtime when these large,
        // throwing results complete on different executors.
        let loadedArtist = try? await client.artist(id: seedArtist.id)
        fullArtist = loadedArtist
        if let loadedArtist { isStarred = loadedArtist.starred != nil }
        albums = Self.sortedAlbums(loadedArtist?.album ?? [])
        info = try? await client.artistInfo(id: seedArtist.id)
        topSongs = (try? await client.topSongs(artistName: seedArtist.name, count: 15)) ?? []
        allSongs = (try? await client.songsForArtist(id: seedArtist.id)) ?? topSongs
        applyDownloadedFallbackIfNeeded()
        applyHiddenAlbumFilters()
        buildAccumulatedSongs()

        let stripped = info?.biography?.strippingHTML
        biography = (stripped?.isEmpty == false) ? stripped : nil

        if artistImage == nil {
            for urlStr in [info?.bestImageUrl, fullArtist?.artistImageUrl].compactMap({ $0 }) {
                if await applyImage(from: urlStr) { break }
            }
        }
        if artistImage == nil, let img = await ArtworkLoader.shared.pinnedArtistImage(id: seedArtist.id, serverID: AppState.shared.currentServer?.id) {
            setArtistImage(img)
        }
        artworkResolved = true

        let ownAlbumIDs = Set(albums.map(\.id))
        let ownID = fullArtist?.id ?? seedArtist.id
        if let found = try? await client.search(query: seedArtist.name, artistCount: 0, albumCount: 30, songCount: 0).albums {
            HiddenAlbumStore.shared.register(albums: found)
            appearsOn = HiddenAlbumStore.shared.visibleAlbums(found).filter { !ownAlbumIDs.contains($0.id) && $0.artistId != ownID }
        }
    }

    func loadOffline() async {
        isLoading = true
        defer { isLoading = false }

        // Do not retain server-only sections after the user enters Offline
        // Mode. The profile remains structurally the same, but every song and
        // album below comes from the download manifest.
        fullArtist = nil
        albums = []
        topSongs = []
        allSongs = []
        info = nil
        biography = nil
        appearsOn = []

        if let image = await ArtworkLoader.shared.pinnedArtistImage(id: seedArtist.id, serverID: AppState.shared.currentServer?.id) {
            setArtistImage(image)
        }

        applyDownloadedFallbackIfNeeded()
        applyHiddenAlbumFilters()
        buildAccumulatedSongs()
        artworkResolved = true
        AppLogger.shared.log(
            "Artist profile loaded offline; artistID=\(seedArtist.id); albums=\(albums.count); songs=\(allSongs.count)",
            category: .library
        )
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

    /// A shuffled mix of the artist's tracks (excluding the ones already shown in
    /// Top Songs), so the "Songs" shelf feels varied rather than album-ordered.
    private func buildAccumulatedSongs() {
        let topIDs = Set(topSongs.map(\.id))

        // Prefer the full artist song list; fall back to album tracklists when
        // the server does not return one.
        var pool = allSongs.filter { !topIDs.contains($0.id) }
        if pool.count < Self.accumulatedPageSize {
            let albumSongs = albumsAndSingles.flatMap { $0.song ?? [] }
            var seenIDs = Set(pool.map(\.id))
            for song in albumSongs where !topIDs.contains(song.id) && seenIDs.insert(song.id).inserted {
                pool.append(song)
            }
        }

        // De-duplicate by id in case the same song appears on multiple releases.
        var seen = Set<String>()
        let unique = pool.filter { seen.insert($0.id).inserted }

        accumulatedSongs = unique.shuffled()
    }

    private func applyDownloadedFallbackIfNeeded() {
        let local = DownloadService.shared.downloadedSongs().filter { song in
            if let artistId = song.primaryArtistID, artistId == seedArtist.id { return true }
            return song.primaryArtistName
                .localizedCaseInsensitiveCompare(ArtistNameResolver.primaryArtistName(trackArtist: seedArtist.name)) == .orderedSame
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
                coverArt: first.coverArt?.nonBlank ?? first.albumId?.nonBlank,
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

    @discardableResult
    private func applyImage(from urlStr: String?) async -> Bool {
        guard let urlStr, !urlStr.isEmpty, !urlStr.hasSuffix("/"),
              let url = URL(string: urlStr),
              let img = await ArtworkLoader.shared.image(for: url, maxPixelSize: 900) else { return false }
        setArtistImage(img)
        return true
    }

    private func setArtistImage(_ image: UIImage) {
        let square = Self.squareCrop(image)
        artistImage = square
        dominantColor = ColorExtractor.dominantColor(from: square)
    }

    private static func squareCrop(_ image: UIImage) -> UIImage {
        let size = image.size
        let side = min(size.width, size.height)
        guard side > 0, abs(size.width - size.height) > 0.5 else { return image }

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(
                x: (side - size.width) / 2,
                y: (side - size.height) / 2,
                width: size.width,
                height: size.height
            ))
        }
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
