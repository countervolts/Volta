import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    struct MoreLikeSection: Identifiable, Hashable, Codable {
        let id: String          // artist id
        let artistName: String
        let albums: [Album]
    }

    private(set) var picks: [Album] = []
    private(set) var recentlyPlayed: [MediaItem] = []
    private(set) var moreLike: [MoreLikeSection] = []
    private(set) var discover: [Album] = []
    private(set) var newReleases: [Album] = []
    private(set) var topArtists: [Artist] = []

    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private var loadedServerID: String?
    private var didFetch = false

    private static let sectionCount = 9
    private static let fullCount = 40
    private static let discoverInterval: TimeInterval = 3 * 60 * 60

    func load(appState: AppState, force: Bool = false) async {
        guard let client = appState.client else { return }
        guard !isLoading else { return }

        let serverID = appState.currentServer?.id ?? client.config.baseURL.absoluteString
        let serverChanged = serverID != loadedServerID
        if didFetch && !force && !serverChanged { return }

        // hydrate from the on-disk snapshot for instant content while the
        // network refresh runs underneath.
        if !hasLoaded || serverChanged,
           let snapshot = DiskCache.load(HomeSnapshot.self, key: Self.cacheKey(serverID)) {
            apply(snapshot)
            hasLoaded = true
        }

        isLoading = true
        defer { isLoading = false }

        // each section loads independently; a failure leaves that section empty
        // rather than failing the whole screen.
        async let picksResult       = loadPicks(client: client)
        async let recentResult      = loadRecentlyPlayed(client: client)
        async let moreLikeResult    = loadMoreLike(client: client)
        async let discoverResult    = loadDiscover(client: client, serverID: serverID, store: appState.store)
        async let newReleasesResult = loadNewReleases(client: client)
        async let artistsResult     = loadTopArtists(client: client)

        picks         = await picksResult
        recentlyPlayed = await recentResult
        moreLike      = await moreLikeResult
        discover      = await discoverResult
        newReleases   = await newReleasesResult
        topArtists    = await artistsResult

        loadedServerID = serverID
        hasLoaded = true
        didFetch = true
        saveSnapshot(serverID: serverID)
    }

    // MARK: - Disk snapshot (instant launch content)

    private struct HomeSnapshot: Codable {
        var picks: [Album]
        var recentlyPlayed: [MediaItem]
        var moreLike: [MoreLikeSection]
        var discover: [Album]
        var newReleases: [Album]
        var topArtists: [Artist]
    }

    private static func cacheKey(_ serverID: String) -> String {
        "home-" + Crypto.md5Hex(serverID)
    }

    private func apply(_ snapshot: HomeSnapshot) {
        picks          = snapshot.picks
        recentlyPlayed = snapshot.recentlyPlayed
        moreLike       = snapshot.moreLike
        discover       = snapshot.discover
        newReleases    = snapshot.newReleases
        topArtists     = snapshot.topArtists
    }

    private func saveSnapshot(serverID: String) {
        let snapshot = HomeSnapshot(
            picks: picks, recentlyPlayed: recentlyPlayed, moreLike: moreLike,
            discover: discover, newReleases: newReleases, topArtists: topArtists
        )
        let key = Self.cacheKey(serverID)
        Task.detached(priority: .utility) {
            DiskCache.save(snapshot, key: key)
        }
    }

    private func loadPicks(client: SubsonicClient) async -> [Album] {
        (try? await client.randomAlbums(size: Self.sectionCount)) ?? []
    }

    private func loadTopArtists(client: SubsonicClient) async -> [Artist] {
        let all = (try? await client.artists()) ?? []
        // shuffle for variety; cap at 20 so the row isn't overwhelming
        return Array(all.shuffled().prefix(20))
    }

    private func loadNewReleases(client: SubsonicClient) async -> [Album] {
        (try? await client.newestAlbums(size: Self.fullCount)) ?? []
    }

    private func fetchRecentAlbums(client: SubsonicClient) async -> [Album] {
        (try? await client.recentlyPlayedAlbums(size: Self.fullCount)) ?? []
    }

    private func fetchPlaylists(client: SubsonicClient) async -> [Playlist] {
        (try? await client.playlists()) ?? []
    }

    // MARK: recently played (albums + playlists merged by recency)

    private func loadRecentlyPlayed(client: SubsonicClient) async -> [MediaItem] {
        async let albumsTask = fetchRecentAlbums(client: client)
        async let playlistsTask = fetchPlaylists(client: client)

        let recentAlbums = await albumsTask
        let allPlaylists = await playlistsTask

        // albums arrive already ordered by recency; give them synthetic
        // descending timestamps so playlists with a real played date can
        // interleave correctly.
        let now = Date()
        let albumItems: [(MediaItem, Date)] = recentAlbums.enumerated().map { index, album in
            (MediaItem(album: album), now.addingTimeInterval(-Double(index)))
        }
        let playlistItems: [(MediaItem, Date)] = allPlaylists.compactMap { playlist in
            guard let played = playlist.playedDate else { return nil }
            return (MediaItem(playlist: playlist), played)
        }

        let merged = (albumItems + playlistItems)
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        return Array(merged.prefix(Self.fullCount))
    }

    // MARK: more like [top artists]

    private func loadMoreLike(client: SubsonicClient) async -> [MoreLikeSection] {
        let frequent = (try? await client.frequentAlbums(size: 100)) ?? []
        let topArtists = rankTopArtists(from: frequent, limit: 2)

        var sections: [MoreLikeSection] = []
        for (artistID, artistName) in topArtists {
            let albums = await albumsLike(artistID: artistID, client: client)
            if !albums.isEmpty {
                sections.append(MoreLikeSection(id: artistID, artistName: artistName, albums: albums))
            }
        }
        return sections
    }

    // sums play counts per artist and returns the highest ranked.
    private func rankTopArtists(from albums: [Album], limit: Int) -> [(id: String, name: String)] {
        var totals: [String: (name: String, plays: Int)] = [:]
        for album in albums {
            guard let id = album.artistId else { continue }
            let plays = album.playCount ?? 0
            let name = album.artist ?? "Unknown Artist"
            totals[id, default: (name, 0)].plays += max(plays, 1)
            totals[id]?.name = name
        }
        return totals
            .sorted { $0.value.plays > $1.value.plays }
            .prefix(limit)
            .map { (id: $0.key, name: $0.value.name) }
    }

    // own albums plus albums from similar artists, deduped, genre-biased.
    private func albumsLike(artistID: String, client: SubsonicClient) async -> [Album] {
        let ownArtist = try? await client.artist(id: artistID)
        let info = try? await client.artistInfo(id: artistID)

        let own = ownArtist?.album ?? []
        let primaryGenres = Set(own.compactMap { $0.genre?.lowercased() })

        let similarIDs = (info?.similarArtist ?? []).prefix(5).map(\.id)
        let similarAlbums = await withTaskGroup(of: [Album].self) { group in
            for id in similarIDs {
                group.addTask {
                    let artist = try? await client.artist(id: id)
                    return artist?.album ?? []
                }
            }
            var collected: [Album] = []
            for await albums in group { collected.append(contentsOf: albums) }
            return collected
        }

        // prefer similar albums that share a genre with the seed artist.
        let sortedSimilar = similarAlbums.sorted { lhs, rhs in
            let l = primaryGenres.contains(lhs.genre?.lowercased() ?? "") ? 0 : 1
            let r = primaryGenres.contains(rhs.genre?.lowercased() ?? "") ? 0 : 1
            return l < r
        }

        var seen = Set<String>()
        var result: [Album] = []
        for album in own + sortedSimilar {
            guard !seen.contains(album.id) else { continue }
            seen.insert(album.id)
            result.append(album)
            if result.count == Self.sectionCount { break }
        }
        return result
    }

    // MARK: discover (rotates every 3 hours, persisted in swiftdata)

    private func loadDiscover(client: SubsonicClient, serverID: String, store: ServerStore) async -> [Album] {
        let cache = store.discoverCache(serverID: serverID)
        let isFresh = cache.map { Date().timeIntervalSince($0.lastRefresh) < Self.discoverInterval } ?? false

        if let cache, isFresh, !cache.albumIDs.isEmpty {
            let albums = (try? await client.albums(ids: cache.albumIDs)) ?? []
            if !albums.isEmpty { return albums }
        }

        let fresh = (try? await client.randomAlbums(size: Self.sectionCount)) ?? []
        if !fresh.isEmpty {
            store.saveDiscoverCache(DiscoverCache(serverID: serverID, albumIDs: fresh.map(\.id), lastRefresh: .now))
        }
        return fresh
    }
}
