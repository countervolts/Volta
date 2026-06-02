import Foundation
import Observation

@MainActor
@Observable
final class PlaylistsViewModel {
    private(set) var playlists: [Playlist] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var isCreating = false

    var searchText: String = ""
    var showCreateSheet = false
    var newPlaylistName = ""

    var filtered: [Playlist] {
        searchText.isEmpty ? playlists : playlists.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    func load(client: SubsonicClient) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        playlists = (try? await client.playlists()) ?? []
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
