import Foundation
import Combine

@MainActor
final class PinnedLibraryStore: ObservableObject {
    static let shared = PinnedLibraryStore()

    private static let albumKey = "pinnedAlbumIDs"
    private static let playlistKey = "pinnedPlaylistIDs"

    @Published private(set) var albumIDs: Set<String>
    @Published private(set) var playlistIDs: Set<String>

    private init() {
        albumIDs = Set(UserDefaults.standard.stringArray(forKey: Self.albumKey) ?? [])
        playlistIDs = Set(UserDefaults.standard.stringArray(forKey: Self.playlistKey) ?? [])
    }

    func isPinned(_ album: Album) -> Bool { albumIDs.contains(album.id) }
    func isPinned(_ playlist: Playlist) -> Bool { playlistIDs.contains(playlist.id) }

    func toggle(_ album: Album) {
        if albumIDs.contains(album.id) {
            albumIDs.remove(album.id)
        } else {
            albumIDs.insert(album.id)
        }
        UserDefaults.standard.set(Array(albumIDs), forKey: Self.albumKey)
    }

    func toggle(_ playlist: Playlist) {
        if playlistIDs.contains(playlist.id) {
            playlistIDs.remove(playlist.id)
        } else {
            playlistIDs.insert(playlist.id)
        }
        UserDefaults.standard.set(Array(playlistIDs), forKey: Self.playlistKey)
    }
}
