import Foundation
import Observation

enum LibraryFilter: String, CaseIterable, Identifiable {
    case artists = "Artists"
    case albums = "Albums"
    case songs = "Songs"
    case genres = "Genres"
    case folders = "Folders"
    var id: String { rawValue }
    @MainActor var label: String {
        switch self {
        case .artists: return L(.home_artists)
        case .albums:  return L(.media_albums)
        case .songs:   return L(.media_songs)
        case .genres:  return L(.media_genres)
        case .folders: return L(.library_folders)
        }
    }
}

enum LibrarySource: String, CaseIterable, Identifiable {
    case server = "Server"
    case downloaded = "Downloaded"
    var id: String { rawValue }
    @MainActor var label: String {
        switch self {
        case .server:     return L(.library_source_server)
        case .downloaded: return L(.library_source_downloaded)
        }
    }
}

enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case name = "Name"
    case album = "Album"
    case year = "Year"
    case mostPlayed = "Most Played"
    case recentlyAdded = "Recently Added"
    var id: String { rawValue }
    @MainActor var label: String {
        switch self {
        case .name:          return L(.sort_name)
        case .album:         return L(.media_album)
        case .year:          return L(.media_year)
        case .mostPlayed:    return L(.sort_most_played)
        case .recentlyAdded: return L(.home_recently_added)
        }
    }
}

@MainActor
@Observable
final class LibraryViewModel {
    private(set) var filter: LibraryFilter = .albums
    private(set) var source: LibrarySource = .server
    private(set) var artists: [Artist] = []
    private(set) var albums: [Album] = []
    private(set) var songs: [Song] = []
    private(set) var genres: [String] = []
    private(set) var musicFolders: [MusicFolder] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false

    var searchText: String = ""

    var selectedFolderID: String? = nil
    var rootFolderSource: FolderSource { .indexes(musicFolderID: selectedFolderID) }

    var sortOrder: LibrarySortOrder = .name
    var genreFilter: String? = nil
    var neverPlayedOnly = false

    var hasActiveFilters: Bool { genreFilter != nil || neverPlayedOnly || sortOrder != .name }

    init() {
        sortOrder = Self.sortOrder(from: UserDefaults.standard.string(forKey: "albumSortOrder"))
    }

    static func sortOrder(from setting: String?) -> LibrarySortOrder {
        switch setting {
        case "newest": return .recentlyAdded
        case "most_played": return .mostPlayed
        case "year": return .year
        default: return .name
        }
    }

    private static func settingValue(for order: LibrarySortOrder) -> String? {
        switch order {
        case .name: return "alphabetical"
        case .year: return "year"
        case .mostPlayed: return "most_played"
        case .recentlyAdded: return "newest"
        case .album: return nil
        }
    }

    func setSort(_ o: LibrarySortOrder) {
        sortOrder = o
        if let value = Self.settingValue(for: o) {
            UserDefaults.standard.set(value, forKey: "albumSortOrder")
        }
    }

    func setGenreFilter(_ g: String?) { genreFilter = g }
    func clearFilters() { sortOrder = .name; genreFilter = nil; neverPlayedOnly = false }

    var availableGenres: [String] { sourceGenres }

    // MARK: - Source-aware base sets

    private var sourceSongs: [Song] {
        let base = source == .server ? songs : DownloadService.shared.downloadedSongs().sorted { $0.title < $1.title }
        return HiddenAlbumStore.shared.visibleSongs(base)
    }

    private var sourceAlbums: [Album] {
        guard source == .downloaded else { return HiddenAlbumStore.shared.visibleAlbums(albums) }
        let ids = Set(sourceSongs.compactMap { $0.albumId })
        let known = albums.filter { ids.contains($0.id) }
        let knownIDs = Set(known.map { $0.id })
        let synthesized = synthesizedDownloadedAlbums(missing: ids.subtracting(knownIDs))
        return HiddenAlbumStore.shared.visibleAlbums((known + synthesized).sorted { $0.name < $1.name })
    }

    private var sourceArtists: [Artist] {
        guard source == .downloaded else { return collapsingComboArtists(HiddenAlbumStore.shared.visibleArtists(artists)) }
        let ids = Set(sourceSongs.compactMap { $0.primaryArtistID })
        let known = artists.filter { ids.contains($0.id) }
        let knownIDs = Set(known.map { $0.id })
        let synthesized = synthesizedDownloadedArtists(missing: ids.subtracting(knownIDs))
        return collapsingComboArtists((known + synthesized).sorted { $0.name < $1.name })
    }

    // Hide combo artists when both parts exist separately.
    private func collapsingComboArtists(_ list: [Artist]) -> [Artist] {
        let names = Set(list.map { $0.name.lowercased().trimmingCharacters(in: .whitespaces) })
        return list.filter { artist in
            let parts = ArtistNameResolver.splitArtistName(artist.name)
                .map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2 else { return true }
            return !parts.allSatisfy { names.contains($0) }
        }
    }

    private var sourceGenres: [String] {
        source == .server ? Set(sourceAlbums.compactMap { $0.genre }).sorted() : Set(sourceSongs.compactMap { $0.genre }).sorted()
    }

    // MARK: - Filtered (search-applied) sets

    var filteredArtists: [Artist] {
        searchText.isEmpty ? sourceArtists : sourceArtists.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    var filteredAlbums: [Album] {
        var list = sourceAlbums
        if !searchText.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(searchText) || ($0.artist ?? "").localizedCaseInsensitiveContains(searchText) }
        }
        if let g = genreFilter {
            list = list.filter { $0.genre?.localizedCaseInsensitiveContains(g) == true }
        }
        if neverPlayedOnly {
            list = list.filter { ($0.playCount ?? 0) == 0 }
        }
        return sortedAlbums(list)
    }
    var filteredSongs: [Song] {
        var list = sourceSongs
        if !searchText.isEmpty {
            list = list.filter { $0.title.localizedCaseInsensitiveContains(searchText) || ($0.artist ?? "").localizedCaseInsensitiveContains(searchText) }
        }
        if let g = genreFilter {
            list = list.filter { $0.genre?.localizedCaseInsensitiveContains(g) == true }
        }
        if neverPlayedOnly {
            list = list.filter { ($0.playCount ?? 0) == 0 }
        }
        return sortedSongs(list)
    }

    private func sortedAlbums(_ list: [Album]) -> [Album] {
        switch sortOrder {
        case .name:          return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .album:         return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .year:          return list.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .mostPlayed:    return list.sorted { ($0.playCount ?? 0) > ($1.playCount ?? 0) }
        case .recentlyAdded: return list.sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
        }
    }

    private func sortedSongs(_ list: [Song]) -> [Song] {
        switch sortOrder {
        case .name:                 return list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .album:
            return list.sorted {
                let albumCompare = ($0.album ?? "").localizedCaseInsensitiveCompare($1.album ?? "")
                if albumCompare != .orderedSame { return albumCompare == .orderedAscending }
                let d0 = $0.discNumber ?? 1
                let d1 = $1.discNumber ?? 1
                if d0 != d1 { return d0 < d1 }
                return ($0.track ?? 0) < ($1.track ?? 0)
            }
        case .year:                 return list.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .mostPlayed:           return list.sorted { ($0.playCount ?? 0) > ($1.playCount ?? 0) }
        case .recentlyAdded:        return list   // songs have no created date
        }
    }
    var filteredGenres: [String] {
        searchText.isEmpty ? sourceGenres : sourceGenres.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    func setFilter(_ f: LibraryFilter) { filter = f; searchText = "" }
    func setSource(_ s: LibrarySource) { source = s; searchText = "" }

    // MARK: - Synthesizing offline album/artist objects from song metadata

    private func synthesizedDownloadedAlbums(missing ids: Set<String>) -> [Album] {
        guard !ids.isEmpty else { return [] }
        var byID: [String: Album] = [:]
        for song in sourceSongs {
            guard let aid = song.albumId, ids.contains(aid), byID[aid] == nil else { continue }
            byID[aid] = Album(
                id: aid, name: song.album ?? "Unknown Album", artist: song.primaryArtistName,
                artistId: song.primaryArtistID, coverArt: song.coverArt, songCount: nil,
                duration: nil, playCount: nil, created: nil, year: song.year,
                genre: song.genre, starred: nil, comment: nil, recordLabel: nil, song: nil
            )
        }
        return Array(byID.values)
    }

    private func synthesizedDownloadedArtists(missing ids: Set<String>) -> [Artist] {
        guard !ids.isEmpty else { return [] }
        var byID: [String: Artist] = [:]
        for song in sourceSongs {
            guard let aid = song.primaryArtistID, ids.contains(aid), byID[aid] == nil else { continue }
            byID[aid] = Artist(
                id: aid, name: song.primaryArtistName, coverArt: song.coverArt,
                albumCount: nil, artistImageUrl: nil, starred: nil, album: nil
            )
        }
        return Array(byID.values)
    }

    func load(client: any MusicService) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let a: [Artist]
        let al: [Album]
        let s: [Song]
        if DeveloperExperiments.constrainedConcurrency(default: 3) == 1 {
            a = await loadArtists(client: client)
            al = await loadAlbums(client: client)
            s = await loadSongs(client: client)
        } else {
            async let artistsTask = loadArtists(client: client)
            async let albumsTask = loadAlbums(client: client)
            async let songsTask = loadSongs(client: client)
            (a, al, s) = await (artistsTask, albumsTask, songsTask)
        }
        artists = a.sorted { $0.name < $1.name }
        albums = al.sorted { $0.name < $1.name }
        songs = s.sorted { $0.title < $1.title }
        HiddenAlbumStore.shared.register(albums: al)
        HiddenAlbumStore.shared.register(artists: a)

        let visibleAlbums = HiddenAlbumStore.shared.visibleAlbums(al)
        let genreSet = Set(visibleAlbums.compactMap { $0.genre })
        genres = genreSet.sorted()
        hasLoaded = true

        // Music folders power the optional folder picker.
        if musicFolders.isEmpty {
            musicFolders = (try? await client.musicFolders()) ?? []
        }

        // Optional artist-photo warmup.
        if UserDefaults.standard.bool(forKey: "prefetchArtistImages"), !PerformanceMode.disablePrefetch {
            let toWarm = artists
            DeveloperExperiments.launch(priority: .utility) {
                for artist in toWarm {
                    guard let s = artist.artistImageUrl, !s.isEmpty, !s.hasSuffix("/"),
                          let url = URL(string: s) else { continue }
                    // Disk only; decoding here is too expensive.
                    await ArtworkLoader.shared.prefetchToDisk(url)
                }
            }
        }
    }

    private func loadArtists(client: any MusicService) async -> [Artist] {
        (try? await client.artists()) ?? []
    }

    private func loadSongs(client: any MusicService) async -> [Song] {
        (try? await client.randomSongs(size: 500)) ?? []
    }

    private func loadAlbums(client: any MusicService) async -> [Album] {
        var all: [Album] = []
        var offset = 0
        let size = 500
        while true {
            let batch = (try? await client.allAlbums(size: size, offset: offset)) ?? []
            all.append(contentsOf: batch)
            if batch.count < size { break }
            offset += size
            if offset > 10000 { break } // safety cap
        }
        return all
    }

    func albumsForGenre(_ genre: String) -> [Album] {
        sourceAlbums.filter { $0.genre?.localizedCaseInsensitiveContains(genre) == true }
    }

    // Album count per genre, computed in a single pass and memoized. The genres
    // list reads this once per row, so calling albumsForGenre (which rescans all
    // albums) per row used to be O(genres × albums) on every render and scroll.
    @ObservationIgnored private var genreCountCache: (key: String, counts: [String: Int])?

    func genreAlbumCounts() -> [String: Int] {
        let key = "\(source.rawValue)-\(HiddenAlbumStore.shared.revision)-\(DownloadService.shared.downloadedRevision)-\(albums.count)"
        if let cache = genreCountCache, cache.key == key { return cache.counts }

        let albumList = sourceAlbums
        var counts: [String: Int] = [:]
        for genre in sourceGenres {
            counts[genre] = albumList.reduce(0) {
                $0 + (($1.genre?.localizedCaseInsensitiveContains(genre) == true) ? 1 : 0)
            }
        }
        genreCountCache = (key, counts)
        return counts
    }
}
