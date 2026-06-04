import Foundation
import Observation

@MainActor
@Observable
final class SmartPlaylistStore {
    static let shared = SmartPlaylistStore()

    private static let key = "smartPlaylists"
    private(set) var playlists: [SmartPlaylist] = []

    private init() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([SmartPlaylist].self, from: data) else {
            playlists = []
            return
        }
        playlists = decoded
    }

    func upsert(_ playlist: SmartPlaylist) {
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            playlists[index] = playlist
        } else {
            playlists.append(playlist)
        }
        save()
    }

    func delete(_ playlist: SmartPlaylist) {
        playlists.removeAll { $0.id == playlist.id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
