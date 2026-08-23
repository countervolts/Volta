import Foundation
import Combine

@MainActor
final class SmartPlaylistStore: ObservableObject {
    static let shared = SmartPlaylistStore()

    private static let key = "smartPlaylists"
    private static let automaticPresetRemovalKey = "removedAutomaticSmartPlaylistPresetsV1"
    private static let automaticPresetIDs: Set<String> = [
        "volta.dynamic.loved",
        "volta.dynamic.downloads",
        "volta.dynamic.unplayed",
        "volta.dynamic.heavy-rotation",
        "volta.dynamic.lossless"
    ]
    @Published private(set) var playlists: [SmartPlaylist] = []
    @Published private(set) var revision = 0

    private init() {
        reload()
    }

    func reload() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([SmartPlaylist].self, from: data) {
            playlists = decoded
        } else {
            playlists = []
        }
        removeAutomaticPresetsIfNeeded()
        revision &+= 1
    }

    func upsert(_ playlist: SmartPlaylist) {
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            playlists[index] = playlist
        } else {
            playlists.append(playlist)
        }
        save()
        revision &+= 1
    }

    func delete(_ playlist: SmartPlaylist) {
        playlists.removeAll { $0.id == playlist.id }
        save()
        revision &+= 1
    }

    func togglePin(_ playlist: SmartPlaylist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[index].pinned.toggle()
        save()
        revision &+= 1
    }

    private func save() {
        if let data = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// An earlier build inserted dynamic playlists automatically. Remove those
    /// generated records once so every dynamic playlist is explicitly created
    /// and named by the user from now on.
    private func removeAutomaticPresetsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.automaticPresetRemovalKey) else { return }
        playlists.removeAll { Self.automaticPresetIDs.contains($0.id) }
        defaults.set(true, forKey: Self.automaticPresetRemovalKey)
        save()
    }
}
