import Foundation
import Observation

enum LibraryFilter: String, CaseIterable, Identifiable {
    case artists = "Artists"
    case albums = "Albums"
    case songs = "Songs"
    case genres = "Genres"
    case folders = "Folders"
    var id: String { rawValue }
}

enum LibrarySource: String, CaseIterable, Identifiable {
    case server = "Server"
    case downloaded = "Downloaded"
    var id: String { rawValue }
}

enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case name = "Name"
    case year = "Year"
    case mostPlayed = "Most Played"
    case recentlyAdded = "Recently Added"
    var id: String { rawValue }
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

    // folder browser: nil = all folders combined (getIndexes without a folder id)
    var selectedFolderID: String? = nil
    var rootFolderSource: FolderSource { .indexes(musicFolderID: selectedFolderID) }

    // section filters / sort (applied to albums & songs)
    var sortOrder: LibrarySortOrder = .name
    var genreFilter: String? = nil
    var neverPlayedOnly = false

    var hasActiveFilters: Bool { genreFilter != nil || neverPlayedOnly || sortOrder != .name }

    func setSort(_ o: LibrarySortOrder) { sortOrder = o }
    func setGenreFilter(_ g: String?) { genreFilter = g }
    func clearFilters() { sortOrder = .name; genreFilter = nil; neverPlayedOnly = false }

    // genres available to filter by in the current source
    var availableGenres: [String] { sourceGenres }

    // MARK: - Source-aware base sets

    // downloaded songs come straight from the persisted manifest, so they're
    // accurate offline and independent of whatever random sample loaded.
    private var sourceSongs: [Song] {
        source == .server ? songs : DownloadService.shared.downloadedSongs().sorted { $0.title < $1.title }
    }

    private var sourceAlbums: [Album] {
        guard source == .downloaded else { return albums }
        let ids = Set(sourceSongs.compactMap { $0.albumId })
        // prefer rich server album objects; synthesize for anything missing.
        let known = albums.filter { ids.contains($0.id) }
        let knownIDs = Set(known.map { $0.id })
        let synthesized = synthesizedDownloadedAlbums(missing: ids.subtracting(knownIDs))
        return (known + synthesized).sorted { $0.name < $1.name }
    }

    private var sourceArtists: [Artist] {
        guard source == .downloaded else { return collapsingComboArtists(artists) }
        let ids = Set(sourceSongs.compactMap { $0.artistId })
        let known = artists.filter { ids.contains($0.id) }
        let knownIDs = Set(known.map { $0.id })
        let synthesized = synthesizedDownloadedArtists(missing: ids.subtracting(knownIDs))
        return collapsingComboArtists((known + synthesized).sorted { $0.name < $1.name })
    }

    // drops "A & B" / "A feat. B" combo entries when BOTH halves already exist as
    // their own artists — server tags featured albums under a combined artist, which
    // showed up alongside the individuals. kept if a half isn't a separate artist
    // (so genuine names like "Simon & Garfunkel" survive).
    private func collapsingComboArtists(_ list: [Artist]) -> [Artist] {
        let names = Set(list.map { $0.name.lowercased().trimmingCharacters(in: .whitespaces) })
        return list.filter { artist in
            let parts = Self.splitArtistName(artist.name)
            guard parts.count >= 2 else { return true }
            return !parts.allSatisfy { names.contains($0) }
        }
    }

    private static func splitArtistName(_ name: String) -> [String] {
        var s = name
        for token in [" featuring ", " feat. ", " feat ", " ft. ", " ft ",
                      " & ", " x ", " and ", ",", ";", " / ", "/"] {
            s = s.replacingOccurrences(of: token, with: "|", options: .caseInsensitive)
        }
        return s.components(separatedBy: "|")
            .map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var sourceGenres: [String] {
        source == .server ? genres : Set(sourceSongs.compactMap { $0.genre }).sorted()
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
        case .year:          return list.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .mostPlayed:    return list.sorted { ($0.playCount ?? 0) > ($1.playCount ?? 0) }
        case .recentlyAdded: return list.sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
        }
    }

    private func sortedSongs(_ list: [Song]) -> [Song] {
        switch sortOrder {
        case .name:                 return list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .year:                 return list.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .mostPlayed:           return list.sorted { ($0.playCount ?? 0) > ($1.playCount ?? 0) }
        case .recentlyAdded:        return list   // songs carry no created date; keep source order
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
                id: aid, name: song.album ?? "Unknown Album", artist: song.artist,
                artistId: song.artistId, coverArt: song.coverArt, songCount: nil,
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
            guard let aid = song.artistId, ids.contains(aid), byID[aid] == nil else { continue }
            byID[aid] = Artist(
                id: aid, name: song.artist ?? "Unknown Artist", coverArt: song.coverArt,
                albumCount: nil, artistImageUrl: nil, starred: nil, album: nil
            )
        }
        return Array(byID.values)
    }

    func load(client: SubsonicClient) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        async let artistsTask = loadArtists(client: client)
        async let albumsTask = loadAlbums(client: client)
        async let songsTask = loadSongs(client: client)

        let (a, al, s) = await (artistsTask, albumsTask, songsTask)
        artists = a.sorted { $0.name < $1.name }
        albums = al.sorted { $0.name < $1.name }
        songs = s.sorted { $0.title < $1.title }
        let genreSet = Set(al.compactMap { $0.genre })
        genres = genreSet.sorted()
        hasLoaded = true

        // music folders power the optional folder picker (cheap, single request)
        if musicFolders.isEmpty {
            musicFolders = (try? await client.musicFolders()) ?? []
        }

        // optionally warm artist profile photos so opening a profile is instant
        if UserDefaults.standard.bool(forKey: "prefetchArtistImages") {
            let toWarm = artists
            Task.detached(priority: .utility) {
                for artist in toWarm {
                    guard let s = artist.artistImageUrl, !s.isEmpty, !s.hasSuffix("/"),
                          let url = URL(string: s) else { continue }
                    _ = await ArtworkLoader.shared.image(for: url)
                }
            }
        }
    }

    private func loadArtists(client: SubsonicClient) async -> [Artist] {
        (try? await client.artists()) ?? []
    }

    private func loadSongs(client: SubsonicClient) async -> [Song] {
        (try? await client.randomSongs(size: 500)) ?? []
    }

    private func loadAlbums(client: SubsonicClient) async -> [Album] {
        var all: [Album] = []
        var offset = 0
        let size = 500
        while true {
            let batch = (try? await client.allAlbums(size: size, offset: offset)) ?? []
            all.append(contentsOf: batch)
            if batch.count < size { break }
            offset += size
            if offset > 10000 { break } // safety cap for enormous libraries
        }
        return all
    }

    func albumsForGenre(_ genre: String) -> [Album] {
        sourceAlbums.filter { $0.genre?.localizedCaseInsensitiveContains(genre) == true }
    }
}
