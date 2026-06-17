import Foundation
import Observation

struct GenreSearchResult: Identifiable, Hashable, Sendable {
    let name: String
    let albumCount: Int
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

    // Stable server id for reopening old searches.
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
    private var client: (any MusicService)?
    private var browseGenreClientID: String?

    func bind(client: any MusicService) {
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

    func refreshForVisibilityChange() {
        recentSearches = recentSearches.filter { Self.isVisibleRecent($0) }
        scheduleSearch()
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
        if item.kind == .album, let id = item.targetID ?? item.id.stripPrefix("album-") {
            return !HiddenAlbumStore.isAlbumHidden(id: id)
        }
        return item.kind == .artist || item.kind == .album || item.kind == .query
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

        let res1: (artists: [Artist], albums: [Album], songs: [Song])?
        let res2: (artists: [Artist], albums: [Album], songs: [Song])?
        let albumSample: [Album]
        if DeveloperExperiments.isAppWorkerLimitEnabled {
            res1 = try? await client.search(query: q, artistCount: 10, albumCount: 10, songCount: 20)
            res2 = useBoth
                ? (try? await client.search(query: normalized, artistCount: 10, albumCount: 10, songCount: 20))
                : nil
            albumSample = (try? await client.allAlbums(size: 500)) ?? []
        } else {
            async let r1 = client.search(query: q, artistCount: 10, albumCount: 10, songCount: 20)
            async let r2 = useBoth
                ? client.search(query: normalized, artistCount: 10, albumCount: 10, songCount: 20)
                : nil
            async let genreAlbums = client.allAlbums(size: 500)

            res1 = (try? await r1)
            res2 = (try? await r2)
            albumSample = (try? await genreAlbums) ?? []
        }
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

        HiddenAlbumStore.shared.register(albums: albumSample)
        HiddenAlbumStore.shared.register(albums: mergedAlbums)

        mergedAlbums = HiddenAlbumStore.shared.visibleAlbums(mergedAlbums)
        mergedSongs = HiddenAlbumStore.shared.visibleSongs(mergedSongs)
        mergedArtists = await visibleArtistsResolvingDiscographies(mergedArtists, client: client)

        let matchedGenres = await Self.genreSummaries(query: q, albums: HiddenAlbumStore.shared.visibleAlbums(albumSample))
        guard query == q else { return }

        artists = mergedArtists
        albums  = mergedAlbums
        songs   = mergedSongs
        genres  = matchedGenres

        let hits = await LyricsService.shared.searchLocal(q)
        guard query == q else { return }
        lyricHits = hits
        lyricSongsByID = [:]

        let resolvedSongs = await resolveLyricSongs(hits, client: client)
        guard query == q else { return }
        let visibleResolvedSongs = resolvedSongs.filter { !HiddenAlbumStore.shared.isSongHidden($0.value) }
        lyricSongsByID = visibleResolvedSongs
        lyricHits = hits.filter { visibleResolvedSongs[$0.id] != nil || resolvedSongs[$0.id] == nil }
    }

    func lyricSong(for hit: LyricSearchHit) -> Song? {
        lyricSongsByID[hit.id]
    }

    private func resolveLyricSongs(_ hits: [LyricSearchHit], client: any MusicService) async -> [String: Song] {
        let ids = Array(Set(hits.map(\.id)))
        guard !ids.isEmpty else { return [:] }

        let songs = await DeveloperExperiments.runConcurrently(ids, defaultMaxConcurrent: ids.count) { id in
            try? await client.song(id: id)
        }
        var resolved: [String: Song] = [:]
        for song in songs {
            if let song {
                resolved[song.id] = song
            }
        }
        return resolved
    }

    private func visibleArtistsResolvingDiscographies(_ artists: [Artist], client: any MusicService) async -> [Artist] {
        guard !artists.isEmpty else { return [] }
        let resolved = await DeveloperExperiments.runConcurrently(artists, defaultMaxConcurrent: min(4, artists.count)) { artist in
            if artist.album != nil { return artist }
            return (try? await client.artist(id: artist.id)) ?? artist
        }
        HiddenAlbumStore.shared.register(artists: resolved)
        return HiddenAlbumStore.shared.visibleArtists(resolved)
    }

    private func loadBrowseGenres(client: any MusicService) async {
        isLoadingBrowseGenres = true
        defer { isLoadingBrowseGenres = false }

        let all = await Self.fetchAllAlbums(client: client)
        HiddenAlbumStore.shared.register(albums: all)
        installedGenres = await Self.genreSummaries(albums: HiddenAlbumStore.shared.visibleAlbums(all))
    }

    private nonisolated static func fetchAllAlbums(client: any MusicService) async -> [Album] {
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
        return all
    }

    private nonisolated static func genreSummaries(query: String? = nil, albums: [Album]) async -> [GenreSearchResult] {
        await DeveloperExperiments.runSync(priority: .userInitiated) {
            let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var counts: [String: Int] = [:]
            for album in albums {
                let genre = album.genre?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !genre.isEmpty else { continue }
                guard trimmed.isEmpty || genre.localizedCaseInsensitiveContains(trimmed) else { continue }
                counts[genre, default: 0] += 1
            }
            return counts
                .map { GenreSearchResult(name: $0.key, albumCount: $0.value) }
                .sorted {
                    if trimmed.isEmpty, $0.albumCount != $1.albumCount {
                        return $0.albumCount > $1.albumCount
                    }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
        }
    }
}

extension String {
    fileprivate func stripPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }

    func normalizedForSearch() -> String {
        self.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .reduce("") { $0 + String($1) }
    }
}
