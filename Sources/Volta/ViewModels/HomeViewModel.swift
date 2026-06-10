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
    private(set) var mixes: [MusicMix] = []

    // mixes + pick albums interleaved randomly but stably for the day, so the
    // "Picks for You" row mixes both at the same card size instead of grouping them.
    var picksFeed: [PickFeedItem] {
        var items = mixes.map(PickFeedItem.mix) + picks.map(PickFeedItem.album)
        var rng = SeededRNG(seed: SeededRNG.daySeed() &+ 0x9151)
        items.shuffle(using: &rng)
        return items
    }
    private(set) var recentlyPlayed: [MediaItem] = []
    private(set) var moreLike: [MoreLikeSection] = []
    private(set) var discover: [Album] = []
    private(set) var newReleases: [Album] = []
    private(set) var topArtists: [Artist] = []

    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var serverUnavailable = false
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
        let todaySeed = SeededRNG.daySeed()
        let cachedSnapshot = DiskCache.load(HomeSnapshot.self, key: Self.cacheKey(serverID))
        let cachedRandomSectionsAreFresh = cachedSnapshot?.generatedDaySeed == todaySeed
        if !hasLoaded || serverChanged,
           let snapshot = cachedSnapshot {
            apply(snapshot)
            hasLoaded = true
        }

        isLoading = true
        defer { isLoading = false }

        guard (try? await client.ping()) != nil else {
            serverUnavailable = true
            hasLoaded = true
            return
        }
        serverUnavailable = false

        // each section loads independently; a failure leaves that section empty
        // rather than failing the whole screen.
        async let picksResult       = cachedRandomSectionsAreFresh && !force ? picks : loadPicks(client: client)
        async let mixesResult       = cachedRandomSectionsAreFresh && !force ? mixes : loadMixes(client: client)
        async let recentResult      = loadRecentlyPlayed(client: client)
        async let moreLikeResult    = loadMoreLike(client: client)
        async let discoverResult    = loadDiscover(client: client, serverID: serverID, store: appState.store)
        async let newReleasesResult = loadNewReleases(client: client)
        async let artistsResult     = loadTopArtists(client: client)

        picks         = await picksResult
        mixes         = await mixesResult
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
        var mixes: [MusicMix]?
        var recentlyPlayed: [MediaItem]
        var moreLike: [MoreLikeSection]
        var discover: [Album]
        var newReleases: [Album]
        var topArtists: [Artist]
        var generatedDaySeed: UInt64?
    }

    private static func cacheKey(_ serverID: String) -> String {
        "home-" + Crypto.md5Hex(serverID)
    }

    private func apply(_ snapshot: HomeSnapshot) {
        picks          = snapshot.picks
        mixes          = snapshot.mixes ?? []
        recentlyPlayed = snapshot.recentlyPlayed
        moreLike       = snapshot.moreLike
        discover       = snapshot.discover
        newReleases    = snapshot.newReleases
        topArtists     = snapshot.topArtists
    }

    private func saveSnapshot(serverID: String) {
        let snapshot = HomeSnapshot(
            picks: picks, mixes: mixes, recentlyPlayed: recentlyPlayed, moreLike: moreLike,
            discover: discover, newReleases: newReleases, topArtists: topArtists,
            generatedDaySeed: SeededRNG.daySeed()
        )
        let key = Self.cacheKey(serverID)
        Task.detached(priority: .utility) {
            DiskCache.save(snapshot, key: key)
        }
    }

    private func loadPicks(client: SubsonicClient) async -> [Album] {
        (try? await client.randomAlbums(size: Self.sectionCount)) ?? []
    }

    // MARK: - Daily mixes ("Rock Mix", "Artist Mix" …)

    private func loadMixes(client: SubsonicClient) async -> [MusicMix] {
        var rng = SeededRNG(seed: SeededRNG.daySeed())

        // sample the library to find the most common genres + active artists
        let sample = (try? await client.allAlbums(size: 300)) ?? []
        guard !sample.isEmpty else { return [] }

        var mixes: [MusicMix] = []

        if let discovery = await loadDiscoveryStation(client: client, rng: &rng) {
            mixes.append(discovery)
        }
        if let heavy = await loadHeavyRotation(client: client, rng: &rng) {
            mixes.append(heavy)
        }

        // up to 2 genre mixes from the top genres
        let genreCounts = Dictionary(grouping: sample.compactMap { $0.genre }, by: { $0 }).mapValues(\.count)
        let topGenres = genreCounts.sorted { $0.value > $1.value }.map(\.key)
        for genre in topGenres.shuffled(using: &rng).prefix(2) {
            let pool = (try? await client.songsByGenre(genre, count: 200)) ?? []
            if let mix = makeMix(id: "genre-\(genre)", title: "\(genre) Mix", subtitle: "Daily \(genre.lowercased()) mix", from: pool, rng: &rng) {
                mixes.append(mix)
            }
        }

        // up to 2 artist mixes from artists with the most albums in the sample
        let artistCounts = Dictionary(grouping: sample.compactMap { a -> (String, String)? in
            guard let id = a.artistId, let name = a.artist else { return nil }
            return (id, name)
        }, by: { $0.0 })
        let topArtistIDs = artistCounts.sorted { $0.value.count > $1.value.count }.map { ($0.key, $0.value.first!.1) }
        for (artistID, artistName) in topArtistIDs.shuffled(using: &rng).prefix(2) {
            var pool = (try? await client.topSongs(artistName: artistName, count: 50)) ?? []
            if pool.count < 10, let artist = try? await client.artist(id: artistID) {
                // fall back to gathering tracks from the artist's albums
                let albums = (artist.album ?? []).prefix(6)
                for album in albums {
                    if let full = try? await client.album(id: album.id) { pool.append(contentsOf: full.song ?? []) }
                }
            }
            if let mix = makeMix(id: "artist-\(artistID)", title: "\(artistName) Mix", subtitle: "Based on \(artistName)", from: pool, rng: &rng) {
                mixes.append(mix)
            }
        }

        return mixes.shuffled(using: &rng)
    }

    private func loadDiscoveryStation(client: SubsonicClient, rng: inout SeededRNG) async -> MusicMix? {
        let pool = (try? await client.randomSongs(size: 120)) ?? []
        return makeMix(
            id: "station-discovery-\(SeededRNG.daySeed())",
            title: "Discovery Station",
            subtitle: "Fresh picks for today",
            from: pool,
            rng: &rng
        )
    }

    private func loadHeavyRotation(client: SubsonicClient, rng: inout SeededRNG) async -> MusicMix? {
        let albums = (try? await client.frequentAlbums(size: 12)) ?? []
        var pool: [Song] = []
        for album in albums.prefix(8) {
            if let full = try? await client.album(id: album.id) {
                pool.append(contentsOf: full.song ?? [])
            }
        }
        return makeMix(
            id: "station-heavy-\(SeededRNG.daySeed())",
            title: "Heavy Rotation",
            subtitle: "Songs you keep coming back to",
            from: pool,
            rng: &rng
        )
    }

    // builds a 20–50 song mix from a candidate pool, or nil if too few tracks
    private func makeMix(id: String, title: String, subtitle: String, from pool: [Song], rng: inout SeededRNG) -> MusicMix? {
        // dedupe by song id
        var seen = Set<String>()
        let unique = pool.filter { seen.insert($0.id).inserted }
        guard unique.count >= 10 else { return nil }
        let target = min(unique.count, Int.random(in: 20...50, using: &rng))
        let songs = Array(unique.shuffled(using: &rng).prefix(target))
        let cover = songs.first(where: { $0.coverArt != nil })?.coverArt
        return MusicMix(id: id, title: title, subtitle: subtitle, coverArt: cover, songs: songs)
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
