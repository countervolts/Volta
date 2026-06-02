import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class PlaylistDetailViewModel {
    private(set) var playlist: Playlist
    private(set) var songs: [Song] = []
    private(set) var isLoading = false
    private(set) var dominantColor: UIColor = .black
    private(set) var isDescriptionExpanded = false

    init(playlist: Playlist) {
        self.playlist = playlist
        self.songs = playlist.entry ?? []
    }

    func load(client: SubsonicClient) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if let loaded = try? await client.playlist(id: playlist.id) {
            playlist = loaded
            songs = loaded.entry ?? []
        }
    }

    func removeSong(at index: Int, client: SubsonicClient) async {
        guard index >= 0, index < songs.count else { return }
        songs.remove(at: index)
        try? await client.removeFromPlaylist(playlistID: playlist.id, index: index)
    }

    func setDominantColor(_ color: UIColor) { dominantColor = color }
    func toggleDescription() { isDescriptionExpanded.toggle() }
}
