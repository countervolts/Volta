import Foundation
import UIKit
import Combine

@MainActor
final class PlaylistDetailViewModel: ObservableObject {
    @Published private(set) var playlist: Playlist
    @Published private(set) var songs: [Song] = []
    @Published private(set) var isLoading = false
    @Published private(set) var dominantColor: UIColor = .black
    @Published private(set) var isDescriptionExpanded = false

    init(playlist: Playlist) {
        self.playlist = playlist
        self.songs = playlist.entry ?? []
    }

    func load(client: any MusicService) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if let loaded = try? await client.playlist(id: playlist.id) {
            playlist = loaded
            songs = loaded.entry ?? []
        }
    }

    func removeSong(at index: Int, client: any MusicService) async {
        guard index >= 0, index < songs.count else { return }
        songs.remove(at: index)
        try? await client.removeFromPlaylist(playlistID: playlist.id, index: index)
        await PlaylistBackupStore.shared.backup(playlistID: playlist.id, client: client)
    }

    func reorderSongs(_ reordered: [Song], client: any MusicService) async throws {
        let previous = songs
        songs = reordered
        do {
            try await client.replacePlaylistSongs(playlistID: playlist.id, songIDs: reordered.map(\.id))
            await load(client: client)
            await PlaylistBackupStore.shared.backup(playlistID: playlist.id, client: client)
        } catch {
            songs = previous
            throw error
        }
    }

    // Edit sheet state. Covers stay local via PlaylistCoverStore.
    func update(name: String, comment: String, client: any MusicService) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed != playlist.name {
            try? await client.renamePlaylist(playlistID: playlist.id, name: trimmed)
        }
        if comment != (playlist.comment ?? "") {
            try? await client.updatePlaylistComment(playlistID: playlist.id, comment: comment)
        }
        await load(client: client)
        PlaylistBackupStore.shared.backup(playlist: playlist, client: client)
    }

    func setDominantColor(_ color: UIColor) { dominantColor = color }
    func toggleDescription() { isDescriptionExpanded.toggle() }
}
