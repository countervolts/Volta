import Foundation
import Combine

struct PlaylistFolder: Identifiable, Hashable, Codable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var playlistIDs: [String] = []
    var smartPlaylistIDs: [String] = []
    var createdAt: Date = Date()
}

@MainActor
final class PlaylistFolderStore: ObservableObject {
    static let shared = PlaylistFolderStore()

    private static let key = "playlistFolders"
    @Published private(set) var folders: [PlaylistFolder] = []

    private init() {
        reload()
    }

    func reload() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([PlaylistFolder].self, from: data) else {
            folders = []
            return
        }
        folders = decoded
    }

    func create(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        folders.append(PlaylistFolder(name: trimmed))
        save()
    }

    func delete(_ folder: PlaylistFolder) {
        folders.removeAll { $0.id == folder.id }
        save()
    }

    func addPlaylist(id playlistID: String, to folder: PlaylistFolder) {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        removePlaylist(id: playlistID, saveAfter: false)
        folders[index].playlistIDs.append(playlistID)
        save()
    }

    func addSmartPlaylist(id smartID: String, to folder: PlaylistFolder) {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        removeSmartPlaylist(id: smartID, saveAfter: false)
        folders[index].smartPlaylistIDs.append(smartID)
        save()
    }

    func removePlaylist(id playlistID: String) {
        removePlaylist(id: playlistID, saveAfter: true)
    }

    func removeSmartPlaylist(id smartID: String) {
        removeSmartPlaylist(id: smartID, saveAfter: true)
    }

    func containsPlaylist(id: String) -> Bool {
        folders.contains { $0.playlistIDs.contains(id) }
    }

    func containsSmartPlaylist(id: String) -> Bool {
        folders.contains { $0.smartPlaylistIDs.contains(id) }
    }

    func folder(id: String) -> PlaylistFolder? {
        folders.first { $0.id == id }
    }

    private func removePlaylist(id playlistID: String, saveAfter: Bool) {
        for index in folders.indices {
            folders[index].playlistIDs.removeAll { $0 == playlistID }
        }
        if saveAfter { save() }
    }

    private func removeSmartPlaylist(id smartID: String, saveAfter: Bool) {
        for index in folders.indices {
            folders[index].smartPlaylistIDs.removeAll { $0 == smartID }
        }
        if saveAfter { save() }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
