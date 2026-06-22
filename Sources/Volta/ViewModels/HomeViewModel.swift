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

    // Stable daily shuffle of mixes and albums.
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

        // Show the cached snapshot while the refresh runs.
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

        if DeveloperExperiments.isAppWorkerLimitEnabled {
            picks = cachedRandomSectionsAreFresh && !force ? picks : await loadPicks(client: client)
            mixes = cachedRandomSectionsAreFresh && !force ? mixes : await loadMixes(client: client)
            recentlyPlayed = await loadRecentlyPlayed(client: client)
            moreLike = await loadMoreLike(client: client)
            discover = await loadDiscover(client: client, serverID: serverID, store: appState.store)
            newReleases = await loadNewReleases(client: client)
            topArtists = await loadTopArtists(client: client)
        } else {
            // A failed section just renders empty.
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
        }

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
        HiddenAlbumStore.shared.register(albums: snapshot.picks + snapshot.discover + snapshot.newReleases)
        HiddenAlbumStore.shared.register(albums: snapshot.recentlyPlayed.compactMap(\.albumRef))
        HiddenAlbumStore.shared.register(albums: snapshot.moreLike.flatMap(\.albums))
        HiddenAlbumStore.shared.register(artists: snapshot.topArtists)

        picks          = HiddenAlbumStore.shared.visibleAlbums(snapshot.picks)
        mixes          = visibleMixes(snapshot.mixes ?? [])
        recentlyPlayed = visibleMediaItems(snapshot.recentlyPlayed)
        moreLike       = visibleMoreLike(snapshot.moreLike)
        discover       = HiddenAlbumStore.shared.visibleAlbums(snapshot.discover)
        newReleases    = HiddenAlbumStore.shared.visibleAlbums(snapshot.newReleases)
        topArtists     = HiddenAlbumStore.shared.visibleArtists(snapshot.topArtists)
    }

    private func saveSnapshot(serverID: String) {
        let snapshot = HomeSnapshot(
            picks: picks, mixes: mixes, recentlyPlayed: recentlyPlayed, moreLike: moreLike,
            discover: discover, newReleases: newReleases, topArtists: topArtists,
            generatedDaySeed: SeededRNG.daySeed()
        )
        let key = Self.cacheKey(serverID)
        DeveloperExperiments.launch(priority: .utility) {
            DiskCache.save(snapshot, key: key)
        }
    }

    private func loadPicks(client: any MusicService) async -> [Album] {
        let albums = (try? await client.randomAlbums(size: Self.sectionCount * 3)) ?? []
        HiddenAlbumStore.shared.register(albums: albums)
        return Array(HiddenAlbumStore.shared.visibleAlbums(albums).prefix(Self.sectionCount))
    }

    // MARK: - Daily mixes ("Rock Mix", "Artist Mix", ...)

    private func loadMixes(client: any MusicService) async -> [MusicMix] {
        var rng = SeededRNG(seed: SeededRNG.daySeed())

        // Sample enough library to find common genres and active artists.
        let rawSample = (try? await client.allAlbums(size: 300)) ?? []
        HiddenAlbumStore.shared.register(albums: rawSample)
        let sample = HiddenAlbumStore.shared.visibleAlbums(rawSample)
        guard !sample.isEmpty else { return [] }

        var mixes: [MusicMix] = []

        if let discovery = await loadDiscoveryStation(client: client, rng: &rng) {
            mixes.append(discovery)
        }
        if let heavy = await loadHeavyRotation(client: client, rng: &rng) {
            mixes.append(heavy)
        }

        // Up to two genre mixes.
        let genreCounts = Dictionary(grouping: sample.compactMap { $0.genre }, by: { $0 }).mapValues(\.count)
        let topGenres = genreCounts.sorted { $0.value > $1.value }.map(\.key)
        for genre in topGenres.shuffled(using: &rng).prefix(2) {
            let pool = HiddenAlbumStore.shared.visibleSongs((try? await client.songsByGenre(genre, count: 200)) ?? [])
            if let mix = makeMix(id: "genre-\(genre)", title: "\(genre) Mix", subtitle: "Daily \(genre.lowercased()) mix", from: pool, rng: &rng) {
                mixes.append(mix)
            }
        }

        // Up to two artist mixes.
        let artistCounts = Dictionary(grouping: sample.compactMap { a -> (String, String)? in
            guard let id = a.artistId, let name = a.artist else { return nil }
            return (id, name)
        }, by: { $0.0 })
        let topArtistIDs = artistCounts.sorted { $0.value.count > $1.value.count }.map { ($0.key, $0.value.first!.1) }
        for (artistID, artistName) in topArtistIDs.shuffled(using: &rng).prefix(2) {
            var pool = HiddenAlbumStore.shared.visibleSongs((try? await client.topSongs(artistName: artistName, count: 50)) ?? [])
            if pool.count < 10, let artist = try? await client.artist(id: artistID) {
                // Fallback: gather tracks from the artist's albums.
                HiddenAlbumStore.shared.register(artists: [artist])
                let albums = HiddenAlbumStore.shared.visibleAlbums(artist.album ?? []).prefix(6)
                for album in albums {
                    if let full = try? await client.album(id: album.id) {
                        pool.append(contentsOf: HiddenAlbumStore.shared.visibleSongs(full.song ?? []))
                    }
                }
            }
            if let mix = makeMix(id: "artist-\(artistID)", title: "\(artistName) Mix", subtitle: "Based on \(artistName)", from: pool, rng: &rng) {
                mixes.append(mix)
            }
        }

        return mixes.shuffled(using: &rng)
    }

    private func loadDiscoveryStation(client: any MusicService, rng: inout SeededRNG) async -> MusicMix? {
        let pool = HiddenAlbumStore.shared.visibleSongs((try? await client.randomSongs(size: 120)) ?? [])
        return makeMix(
            id: "station-discovery-\(SeededRNG.daySeed())",
            title: "Discovery Station",
            subtitle: "Fresh picks for today",
            from: pool,
            rng: &rng
        )
    }

    private func loadHeavyRotation(client: any MusicService, rng: inout SeededRNG) async -> MusicMix? {
        let rawAlbums = (try? await client.frequentAlbums(size: 12)) ?? []
        HiddenAlbumStore.shared.register(albums: rawAlbums)
        let albums = HiddenAlbumStore.shared.visibleAlbums(rawAlbums)
        var pool: [Song] = []
        for album in albums.prefix(8) {
            if let full = try? await client.album(id: album.id) {
                pool.append(contentsOf: HiddenAlbumStore.shared.visibleSongs(full.song ?? []))
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

    // Build a 20-50 song mix when the pool is deep enough.
    private func makeMix(id: String, title: String, subtitle: String, from pool: [Song], rng: inout SeededRNG) -> MusicMix? {
        // Dedupe by song id.
        var seen = Set<String>()
        let unique = pool.filter { seen.insert($0.id).inserted }
        guard unique.count >= 10 else { return nil }
        let target = min(unique.count, Int.random(in: 20...50, using: &rng))
        let songs = Array(unique.shuffled(using: &rng).prefix(target))
        let cover = songs.first(where: { $0.coverArt != nil })?.coverArt
        return MusicMix(id: id, title: title, subtitle: subtitle, coverArt: cover, songs: songs)
    }

    private func loadTopArtists(client: any MusicService) async -> [Artist] {
        let all = (try? await client.artists()) ?? []
        HiddenAlbumStore.shared.register(artists: all)
        // Shuffle for variety; cap the row.
        return Array(HiddenAlbumStore.shared.visibleArtists(all).shuffled().prefix(20))
    }

    private func loadNewReleases(client: any MusicService) async -> [Album] {
        let albums = (try? await client.newestAlbums(size: Self.fullCount * 2)) ?? []
        HiddenAlbumStore.shared.register(albums: albums)
        return Array(HiddenAlbumStore.shared.visibleAlbums(albums).prefix(Self.fullCount))
    }

    private func fetchRecentAlbums(client: any MusicService) async -> [Album] {
        let albums = (try? await client.recentlyPlayedAlbums(size: Self.fullCount * 2)) ?? []
        HiddenAlbumStore.shared.register(albums: albums)
        return Array(HiddenAlbumStore.shared.visibleAlbums(albums).prefix(Self.fullCount))
    }

    private func fetchPlaylists(client: any MusicService) async -> [Playlist] {
        (try? await client.playlists()) ?? []
    }

    // MARK: recently played (albums + playlists merged by recency)

    private func loadRecentlyPlayed(client: any MusicService) async -> [MediaItem] {
        let recentAlbums: [Album]
        let allPlaylists: [Playlist]
        if DeveloperExperiments.constrainedConcurrency(default: 2) == 1 {
            recentAlbums = await fetchRecentAlbums(client: client)
            allPlaylists = await fetchPlaylists(client: client)
        } else {
            async let albumsTask = fetchRecentAlbums(client: client)
            async let playlistsTask = fetchPlaylists(client: client)
            recentAlbums = await albumsTask
            allPlaylists = await playlistsTask
        }

        // Albums are already recency-ordered; synthesize timestamps for merge sort.
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

    private func loadMoreLike(client: any MusicService) async -> [MoreLikeSection] {
        let rawFrequent = (try? await client.frequentAlbums(size: 100)) ?? []
        HiddenAlbumStore.shared.register(albums: rawFrequent)
        let frequent = HiddenAlbumStore.shared.visibleAlbums(rawFrequent)
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

    // Rank artists by summed album plays.
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

    // Own albums plus similar-artist albums, genre-biased.
    private func albumsLike(artistID: String, client: any MusicService) async -> [Album] {
        let ownArtist = try? await client.artist(id: artistID)
        let info = try? await client.artistInfo(id: artistID)

        if let ownArtist { HiddenAlbumStore.shared.register(artists: [ownArtist]) }
        let own = HiddenAlbumStore.shared.visibleAlbums(ownArtist?.album ?? [])
        let primaryGenres = Set(own.compactMap { $0.genre?.lowercased() })

        let similarIDs = (info?.similarArtist ?? []).prefix(5).map(\.id)
        let albumBatches = await DeveloperExperiments.runConcurrently(Array(similarIDs), defaultMaxConcurrent: similarIDs.count) { id in
            let artist = try? await client.artist(id: id)
            if let artist { await MainActor.run { HiddenAlbumStore.shared.register(artists: [artist]) } }
            return HiddenAlbumStore.visibleAlbums(artist?.album ?? [])
        }
        let similarAlbums = HiddenAlbumStore.shared.visibleAlbums(albumBatches.flatMap { $0 })

        // Prefer similar albums that share the seed genre.
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

    // MARK: discover (3-hour cache)

    private func loadDiscover(client: any MusicService, serverID: String, store: ServerStore) async -> [Album] {
        let cache = store.discoverCache(serverID: serverID)
        let isFresh = cache.map { Date().timeIntervalSince($0.lastRefresh) < Self.discoverInterval } ?? false

        if let cache, isFresh, !cache.albumIDs.isEmpty {
            let albums = HiddenAlbumStore.shared.visibleAlbums((try? await client.albums(ids: cache.albumIDs)) ?? [])
            if !albums.isEmpty { return albums }
        }

        let fresh = (try? await client.randomAlbums(size: Self.sectionCount * 3)) ?? []
        HiddenAlbumStore.shared.register(albums: fresh)
        let visible = Array(HiddenAlbumStore.shared.visibleAlbums(fresh).prefix(Self.sectionCount))
        if !visible.isEmpty {
            store.saveDiscoverCache(DiscoverCache(serverID: serverID, albumIDs: visible.map(\.id), lastRefresh: .now))
        }
        return visible
    }

    private func visibleMixes(_ mixes: [MusicMix]) -> [MusicMix] {
        mixes.compactMap(visibleMix)
    }

    private func visibleMix(_ mix: MusicMix) -> MusicMix? {
        let songs = HiddenAlbumStore.shared.visibleSongs(mix.songs)
        guard !songs.isEmpty else { return nil }
        return MusicMix(id: mix.id, title: mix.title, subtitle: mix.subtitle, coverArt: mix.coverArt, songs: songs)
    }

    private func visibleMediaItems(_ items: [MediaItem]) -> [MediaItem] {
        items.filter { item in
            if let album = item.albumRef {
                return !HiddenAlbumStore.shared.isHidden(album)
            }
            return true
        }
    }

    private func visibleMoreLike(_ sections: [MoreLikeSection]) -> [MoreLikeSection] {
        sections.compactMap { section in
            let albums = HiddenAlbumStore.shared.visibleAlbums(section.albums)
            guard !albums.isEmpty else { return nil }
            return MoreLikeSection(id: section.id, artistName: section.artistName, albums: albums)
        }
    }
}
