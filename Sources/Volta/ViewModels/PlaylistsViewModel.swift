import Foundation
import Combine

@MainActor
final class PlaylistsViewModel: ObservableObject {
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var smartSourceSongs: [Song] = []
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

    var smartGenres: [String] {
        Set(smartSourceSongs.compactMap(\.genre)).sorted()
    }

    var smartArtists: [String] {
        Set(smartSourceSongs.compactMap(\.artist)).sorted()
    }

    var smartAlbums: [String] {
        Set(smartSourceSongs.compactMap(\.album)).sorted()
    }

    func load(client: any MusicService) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if DeveloperExperiments.constrainedConcurrency(default: 2) == 1 {
            playlists = (try? await client.playlists()) ?? []
            smartSourceSongs = (try? await client.randomSongs(size: 1000)) ?? []
        } else {
            async let playlistsTask = client.playlists()
            async let songsTask = client.randomSongs(size: 1000)
            playlists = (try? await playlistsTask) ?? []
            smartSourceSongs = (try? await songsTask) ?? []
        }
        hasLoaded = true
        if PlaylistBackupStore.shared.isEnabled {
            Task { await PlaylistBackupStore.shared.backupAll(client: client) }
        }
    }

    func createPlaylist(client: any MusicService) async {
        let trimmed = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isCreating = true
        defer { isCreating = false }
        if let pl = try? await client.createPlaylist(name: trimmed) {
            playlists.append(pl)
            PlaylistBackupStore.shared.backup(playlist: pl, client: client)
        }
        newPlaylistName = ""
        showCreateSheet = false
    }

    func deletePlaylist(_ playlist: Playlist, client: any MusicService) async {
        await PlaylistBackupStore.shared.markDeleted(playlist, client: client)
        playlists.removeAll { $0.id == playlist.id }
        try? await client.deletePlaylist(id: playlist.id)
    }
}
