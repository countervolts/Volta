import Foundation
import Observation

@MainActor
@Observable
final class PlaylistsViewModel {
    private(set) var playlists: [Playlist] = []
    private(set) var smartSourceSongs: [Song] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var isCreating = false

    var searchText: String = ""
    var showCreateSheet = false
    var newPlaylistName = ""

    // locally pinned playlist IDs (persisted) — pinned playlists sort to the top
    private static let pinnedKey = "pinnedPlaylistIDs"
    private(set) var pinnedIDs: Set<String> = Set(
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
        // stable sort: pinned first, preserving original order within each group
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

    func load(client: SubsonicClient) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        async let playlistsTask = client.playlists()
        async let songsTask = client.randomSongs(size: 500)
        playlists = (try? await playlistsTask) ?? []
        smartSourceSongs = (try? await songsTask) ?? []
        hasLoaded = true
    }

    func createPlaylist(client: SubsonicClient) async {
        guard !newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isCreating = true
        defer { isCreating = false }
        if let pl = try? await client.createPlaylist(name: newPlaylistName) {
            playlists.append(pl)
        }
        newPlaylistName = ""
        showCreateSheet = false
    }

    func deletePlaylist(_ playlist: Playlist, client: SubsonicClient) async {
        playlists.removeAll { $0.id == playlist.id }
        try? await client.deletePlaylist(id: playlist.id)
    }
}
