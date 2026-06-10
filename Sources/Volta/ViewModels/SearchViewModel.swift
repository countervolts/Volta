import Foundation
import Observation

struct GenreSearchResult: Identifiable, Hashable {
    let name: String
    let albums: [Album]
    var id: String { name }
}

enum SearchHistoryKind: String, Codable, Sendable {
    case artist
    case album
    case song
    case lyric
    case genre
    case query

    var label: String {
        switch self {
        case .artist: return "Artist"
        case .album: return "Album"
        case .song: return "Song"
        case .lyric: return "Lyric"
        case .genre: return "Genre"
        case .query: return "Search"
        }
    }
}

struct SearchHistoryItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let kind: SearchHistoryKind
    let coverArt: String?
    let query: String

    // Stable server id for direct reopening. Older history entries fall back to
    // parsing the typed `id` prefix.
    let targetID: String?

    init(
        id: String,
        title: String,
        subtitle: String?,
        kind: SearchHistoryKind,
        coverArt: String?,
        query: String,
        targetID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.coverArt = coverArt
        self.query = query
        self.targetID = targetID
    }
}

@MainActor
@Observable
final class SearchViewModel {
    private(set) var artists: [Artist] = []
    private(set) var albums: [Album] = []
    private(set) var songs: [Song] = []
    private(set) var genres: [GenreSearchResult] = []
    private(set) var lyricHits: [LyricSearchHit] = []
    private(set) var lyricSongsByID: [String: Song] = [:]
    private(set) var installedGenres: [GenreSearchResult] = []
    private(set) var isLoadingBrowseGenres = false
    private(set) var isSearching = false
    private(set) var hasSearched = false

    var query: String = "" {
        didSet { scheduleSearch() }
    }

    private(set) var recentSearches: [SearchHistoryItem] = SearchViewModel.loadRecentSearches()

    private var debounceTask: Task<Void, Never>?
    private var client: SubsonicClient?
    private var browseGenreClientID: String?

    func bind(client: SubsonicClient) {
        self.client = client
        let id = client.config.baseURL.absoluteString
        guard browseGenreClientID != id else { return }
        browseGenreClientID = id
        Task { await loadBrowseGenres(client: client) }
    }

    func saveSearch(_ term: String, item: SearchHistoryItem? = nil) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let savedItem = item ?? Self.queryHistoryItem(trimmed)
        guard Self.isVisibleRecent(savedItem) else { return }
        var updated = recentSearches.filter {
            $0.id != savedItem.id &&
            $0.query.caseInsensitiveCompare(trimmed) != .orderedSame &&
            $0.title.caseInsensitiveCompare(savedItem.title) != .orderedSame
        }
        updated.insert(savedItem, at: 0)
        recentSearches = Array(updated.prefix(10))
        persistRecentSearches()
    }

    func saveSelectedArtist(_ artist: Artist, typedQuery: String) {
        saveSearch(
            typedQuery,
            item: SearchHistoryItem(
                id: "artist-\(artist.id)",
                title: artist.name,
                subtitle: SearchHistoryKind.artist.label,
                kind: .artist,
                coverArt: artist.coverArt,
                query: artist.name,
                targetID: artist.id
            )
        )
    }

    func saveSelectedAlbum(_ album: Album, typedQuery: String) {
        saveSearch(
            typedQuery,
            item: SearchHistoryItem(
                id: "album-\(album.id)",
                title: album.name,
                subtitle: album.artist,
                kind: .album,
                coverArt: album.coverArt,
                query: album.name,
                targetID: album.id
            )
        )
    }

    func removeRecentSearch(_ item: SearchHistoryItem) {
        recentSearches.removeAll { $0.id == item.id }
        persistRecentSearches()
    }

    func clearRecentSearches() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: "recentSearches")
    }

    private func persistRecentSearches() {
        if let data = try? JSONEncoder().encode(recentSearches) {
            UserDefaults.standard.set(data, forKey: "recentSearches")
        }
    }

    private static func loadRecentSearches() -> [SearchHistoryItem] {
        guard let data = UserDefaults.standard.data(forKey: "recentSearches") else { return [] }
        if let items = try? JSONDecoder().decode([SearchHistoryItem].self, from: data) {
            return items.filter { Self.isVisibleRecent($0) }
        }
        let oldTerms = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        return oldTerms.map(queryHistoryItem)
    }

    private static func queryHistoryItem(_ term: String) -> SearchHistoryItem {
        SearchHistoryItem(
            id: "query-\(term.normalizedForSearch())",
            title: term,
            subtitle: nil,
            kind: .query,
            coverArt: nil,
            query: term
        )
    }

    private static func isVisibleRecent(_ item: SearchHistoryItem) -> Bool {
        item.kind == .artist || item.kind == .album || item.kind == .query
    }

    private func scheduleSearch() {
        debounceTask?.cancel()
        let q = query
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(q)
        }
    }

    private func performSearch(_ q: String) async {
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else {
            artists = []
            albums = []
            songs = []
            genres = []
            lyricHits = []
            lyricSongsByID = [:]
            hasSearched = false
            return
        }
        guard let client else { return }
        isSearching = true
        defer { isSearching = false }
        hasSearched = true

        let normalized = q.normalizedForSearch()
        let useBoth = normalized != q.lowercased() && !normalized.isEmpty

        async let r1 = client.search(query: q, artistCount: 10, albumCount: 10, songCount: 20)
        async let r2 = useBoth
            ? client.search(query: normalized, artistCount: 10, albumCount: 10, songCount: 20)
            : nil
        async let genreAlbums = client.allAlbums(size: 500)

        let res1 = (try? await r1)
        let res2 = (try? await r2)
        let albumSample = (try? await genreAlbums) ?? []
        guard query == q else { return }

        var mergedArtists = res1?.artists ?? []
        var mergedAlbums  = res1?.albums  ?? []
        var mergedSongs   = res1?.songs   ?? []

        if let r = res2 {
            let existingArtistIDs = Set(mergedArtists.map(\.id))
            let existingAlbumIDs  = Set(mergedAlbums.map(\.id))
            let existingSongIDs   = Set(mergedSongs.map(\.id))
            mergedArtists += r.artists.filter { !existingArtistIDs.contains($0.id) }
            mergedAlbums  += r.albums.filter  { !existingAlbumIDs.contains($0.id) }
            mergedSongs   += r.songs.filter   { !existingSongIDs.contains($0.id) }
        }

        artists = mergedArtists
        albums  = mergedAlbums
        songs   = mergedSongs
        genres  = matchingGenres(query: q, albums: albumSample)

        let hits = await LyricsService.shared.searchLocal(q)
        guard query == q else { return }
        lyricHits = hits
        lyricSongsByID = [:]

        let resolvedSongs = await resolveLyricSongs(hits, client: client)
        guard query == q else { return }
        lyricSongsByID = resolvedSongs
    }

    func lyricSong(for hit: LyricSearchHit) -> Song? {
        lyricSongsByID[hit.id]
    }

    private func resolveLyricSongs(_ hits: [LyricSearchHit], client: SubsonicClient) async -> [String: Song] {
        let ids = Array(Set(hits.map(\.id)))
        guard !ids.isEmpty else { return [:] }

        return await withTaskGroup(of: Song?.self, returning: [String: Song].self) { group in
            for id in ids {
                group.addTask {
                    try? await client.song(id: id)
                }
            }

            var resolved: [String: Song] = [:]
            for await song in group {
                if let song {
                    resolved[song.id] = song
                }
            }
            return resolved
        }
    }

    private func loadBrowseGenres(client: SubsonicClient) async {
        isLoadingBrowseGenres = true
        defer { isLoadingBrowseGenres = false }

        var all: [Album] = []
        var offset = 0
        let size = 500
        while true {
            let batch = (try? await client.allAlbums(size: size, offset: offset)) ?? []
            all.append(contentsOf: batch)
            if batch.count < size { break }
            offset += size
            if offset > 20_000 { break }
        }

        let grouped = Dictionary(grouping: all) { album in
            album.genre?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        installedGenres = grouped
            .filter { !$0.key.isEmpty }
            .map { GenreSearchResult(name: $0.key, albums: $0.value.sorted { $0.name < $1.name }) }
            .sorted {
                if $0.albums.count != $1.albums.count { return $0.albums.count > $1.albums.count }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private func matchingGenres(query: String, albums: [Album]) -> [GenreSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let grouped = Dictionary(grouping: albums) { album in
            album.genre?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        return grouped
            .filter { !$0.key.isEmpty && $0.key.localizedCaseInsensitiveContains(trimmed) }
            .map { GenreSearchResult(name: $0.key, albums: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

extension String {
    func normalizedForSearch() -> String {
        self.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .reduce("") { $0 + String($1) }
    }
}
