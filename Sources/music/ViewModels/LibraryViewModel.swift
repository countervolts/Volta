import Foundation
import Observation

enum LibraryFilter: String, CaseIterable, Identifiable {
    case artists = "Artists"
    case albums = "Albums"
    case songs = "Songs"
    case genres = "Genres"
    var id: String { rawValue }
}

enum LibrarySource: String, CaseIterable, Identifiable {
    case server = "Server"
    case downloaded = "Downloaded"
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
    private(set) var isLoading = false
    private(set) var hasLoaded = false

    var searchText: String = ""

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
        guard source == .downloaded else { return artists }
        let ids = Set(sourceSongs.compactMap { $0.artistId })
        let known = artists.filter { ids.contains($0.id) }
        let knownIDs = Set(known.map { $0.id })
        let synthesized = synthesizedDownloadedArtists(missing: ids.subtracting(knownIDs))
        return (known + synthesized).sorted { $0.name < $1.name }
    }

    private var sourceGenres: [String] {
        source == .server ? genres : Set(sourceSongs.compactMap { $0.genre }).sorted()
    }

    // MARK: - Filtered (search-applied) sets

    var filteredArtists: [Artist] {
        searchText.isEmpty ? sourceArtists : sourceArtists.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    var filteredAlbums: [Album] {
        searchText.isEmpty ? sourceAlbums : sourceAlbums.filter { $0.name.localizedCaseInsensitiveContains(searchText) || ($0.artist ?? "").localizedCaseInsensitiveContains(searchText) }
    }
    var filteredSongs: [Song] {
        searchText.isEmpty ? sourceSongs : sourceSongs.filter { $0.title.localizedCaseInsensitiveContains(searchText) || ($0.artist ?? "").localizedCaseInsensitiveContains(searchText) }
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
