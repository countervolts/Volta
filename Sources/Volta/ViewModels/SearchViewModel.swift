import Foundation
import Observation

struct GenreSearchResult: Identifiable, Hashable {
    let name: String
    let albums: [Album]
    var id: String { name }
}

@MainActor
@Observable
final class SearchViewModel {
    private(set) var artists: [Artist] = []
    private(set) var albums: [Album] = []
    private(set) var songs: [Song] = []
    private(set) var genres: [GenreSearchResult] = []
    private(set) var isSearching = false
    private(set) var hasSearched = false

    var query: String = "" {
        didSet { scheduleSearch() }
    }

    private(set) var recentSearches: [String] = {
        (try? JSONDecoder().decode([String].self, from: UserDefaults.standard.data(forKey: "recentSearches") ?? Data())) ?? []
    }()

    private var debounceTask: Task<Void, Never>?
    private var client: SubsonicClient?

    func bind(client: SubsonicClient) {
        self.client = client
    }

    func saveSearch(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var updated = recentSearches.filter { $0 != trimmed }
        updated.insert(trimmed, at: 0)
        recentSearches = Array(updated.prefix(10))
        if let data = try? JSONEncoder().encode(recentSearches) {
            UserDefaults.standard.set(data, forKey: "recentSearches")
        }
    }

    func removeRecentSearch(_ term: String) {
        recentSearches.removeAll { $0 == term }
        if let data = try? JSONEncoder().encode(recentSearches) {
            UserDefaults.standard.set(data, forKey: "recentSearches")
        }
    }

    func clearRecentSearches() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: "recentSearches")
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
            hasSearched = false
            return
        }
        guard let client else { return }
        isSearching = true
        defer { isSearching = false }
        hasSearched = true
        saveSearch(q)

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
