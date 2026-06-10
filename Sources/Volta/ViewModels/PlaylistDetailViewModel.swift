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
        await PlaylistBackupStore.shared.backup(playlistID: playlist.id, client: client)
    }

    // edit sheet: name + description in one go (the cover is stored locally by the
    // view via PlaylistCoverStore, since Subsonic can't accept a playlist cover).
    func update(name: String, comment: String, client: SubsonicClient) async {
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
