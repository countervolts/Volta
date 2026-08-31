import Foundation
import Combine

@MainActor
final class PlaylistsViewModel: ObservableObject {
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var smartSourceSongs: [Song] = []
    @Published private(set) var smartGenres: [String] = []
    @Published private(set) var smartArtists: [String] = []
    @Published private(set) var smartAlbums: [String] = []
    @Published private(set) var smartSourceRevision = 0
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var isCreating = false

    @Published var searchText: String = ""
    @Published var showCreateSheet = false
    @Published var newPlaylistName = ""

    private static let pinnedKey = "pinnedPlaylistIDs"
    @Published private(set) var pinnedIDs: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: PlaylistsViewModel.pinnedKey) ?? []
    )

    func isPinned(_ playlist: Playlist) -> Bool { pinnedIDs.contains(playlist.id) }

    func togglePin(_ playlist: Playlist) {
        if pinnedIDs.contains(playlist.id) {
            pinnedIDs.remove(playlist.id)
        } else {
            pinnedIDs.insert(playlist.id)
        }
        UserDefaults.standard.set(Array(pinnedIDs), forKey: Self.pinnedKey)
    }

    var filtered: [Playlist] {
        let base = searchText.isEmpty
            ? playlists
            : playlists.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        return base.enumerated()
            .sorted { lhs, rhs in
                let lp = pinnedIDs.contains(lhs.element.id)
                let rp = pinnedIDs.contains(rhs.element.id)
                if lp != rp { return lp }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    func load(client: any MusicService) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let serverID = AppState.shared.currentServer?.id
        let cachedPlaylists = PlaylistOfflineCache.shared.playlists(for: serverID)
        if DeveloperExperiments.constrainedConcurrency(default: 2) == 1 {
            if let loaded = try? await client.playlists() {
                playlists = loaded
                PlaylistOfflineCache.shared.cacheList(loaded, serverID: serverID)
                Task { await PlaylistOfflineCache.shared.cacheAll(loaded, client: client, serverID: serverID) }
            } else {
                playlists = cachedPlaylists
            }
            await publishSmartSource((try? await client.randomSongs(size: 1000)) ?? [])
        } else {
            async let playlistsTask = client.playlists()
            async let songsTask = client.randomSongs(size: 1000)
            if let loaded = try? await playlistsTask {
                playlists = loaded
                PlaylistOfflineCache.shared.cacheList(loaded, serverID: serverID)
                Task { await PlaylistOfflineCache.shared.cacheAll(loaded, client: client, serverID: serverID) }
            } else {
                playlists = cachedPlaylists
            }
            await publishSmartSource((try? await songsTask) ?? [])
        }
        hasLoaded = true
        let completeLibrary = await Self.loadSmartPlaylistLibrary(client: client)
        let fallback = smartSourceSongs
        let merged = await DeveloperExperiments.runSync {
            Self.merging(primary: completeLibrary, fallback: fallback)
        }
        await publishSmartSource(merged)
    }

    func loadOffline(serverID: String?) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        playlists = PlaylistOfflineCache.shared.playlists(for: serverID)
        await publishSmartSource([])
        hasLoaded = true
    }

    private nonisolated static func loadSmartPlaylistLibrary(client: any MusicService) async -> [Song] {
        var albums: [Album] = []
        var offset = 0
        let pageSize = 500
        while true {
            let page = (try? await client.allAlbums(size: pageSize, offset: offset)) ?? []
            albums.append(contentsOf: page)
            guard page.count == pageSize, offset < 20_000 else { break }
            offset += pageSize
        }

        var songs: [Song] = []
        let batchSize = 6
        var index = 0
        while index < albums.count {
            let end = min(index + batchSize, albums.count)
            let batch = Array(albums[index..<end])
            let results = await DeveloperExperiments.runConcurrently(batch, defaultMaxConcurrent: batchSize) { album in
                (try? await client.album(id: album.id))?.song ?? []
            }
            let flattened = await DeveloperExperiments.runSync { results.flatMap { $0 } }
            songs.append(contentsOf: flattened)
            index = end
        }
        return songs
    }

    private nonisolated static func merging(primary: [Song], fallback: [Song]) -> [Song] {
        var seen = Set<String>()
        return (primary + fallback).filter { seen.insert($0.id).inserted }
    }

    private func publishSmartSource(_ songs: [Song]) async {
        let facets = await DeveloperExperiments.runSync {
            SmartPlaylistFacets(
                genres: Array(Set(songs.compactMap(\.genre))).sorted(),
                artists: Array(Set(songs.compactMap(\.artist))).sorted(),
                albums: Array(Set(songs.compactMap(\.album))).sorted()
            )
        }
        smartSourceSongs = songs
        smartGenres = facets.genres
        smartArtists = facets.artists
        smartAlbums = facets.albums
        smartSourceRevision &+= 1
    }

    func createPlaylist(client: any MusicService) async {
        let trimmed = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isCreating = true
        defer { isCreating = false }
        if let pl = try? await client.createPlaylist(name: trimmed) {
            playlists.append(pl)
            PlaylistOfflineCache.shared.cache(pl, serverID: AppState.shared.currentServer?.id)
            PlaylistBackupStore.shared.backup(playlist: pl, client: client)
        }
        newPlaylistName = ""
        showCreateSheet = false
    }

    func deletePlaylist(_ playlist: Playlist, client: any MusicService) async {
        await PlaylistBackupStore.shared.markDeleted(playlist, client: client)
        playlists.removeAll { $0.id == playlist.id }
        PlaylistOfflineCache.shared.remove(id: playlist.id, serverID: AppState.shared.currentServer?.id)
        try? await client.deletePlaylist(id: playlist.id)
    }
}

private struct SmartPlaylistFacets: Sendable {
    let genres: [String]
    let artists: [String]
    let albums: [String]
}
