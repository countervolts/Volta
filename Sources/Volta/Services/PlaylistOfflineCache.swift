import Foundation
import Combine

private struct PlaylistOfflineCacheSnapshot: Codable, Sendable {
    var serverID: String
    var playlist: Playlist
    var firstSeenAt: Date
    var updatedAt: Date
}

private struct PlaylistOfflineCachePayload: Codable {
    var version = 1
    var snapshots: [PlaylistOfflineCacheSnapshot]
}

/// Keeps provider playlists and their entries available after Offline Mode is
/// selected. This is independent from playlist backup/restore preferences.
@MainActor
final class PlaylistOfflineCache: ObservableObject {
    static let shared = PlaylistOfflineCache()

    @Published private(set) var revision = 0

    private let fileURL: URL
    private var snapshots: [PlaylistOfflineCacheSnapshot] = []

    private init() {
        let directory = Self.storageDirectoryURL
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("playlists.json")
        reload()
    }

    private static var storageDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Volta/PlaylistCache", isDirectory: true)
    }

    func playlists(for serverID: String?) -> [Playlist] {
        guard let serverID else { return [] }
        return snapshots
            .filter { $0.serverID == serverID }
            .map(\.playlist)
    }

    func playlist(id: String, serverID: String?) -> Playlist? {
        guard let serverID else { return nil }
        return snapshots.first {
            $0.serverID == serverID && $0.playlist.id == id
        }?.playlist
    }

    func recentDate(for playlist: Playlist, serverID: String?) -> Date? {
        if let date = playlist.createdDate ?? playlist.changedDate { return date }
        guard let serverID else { return nil }
        return snapshots.first {
            $0.serverID == serverID && $0.playlist.id == playlist.id
        }?.firstSeenAt
    }

    func cacheList(_ playlists: [Playlist], serverID: String?) {
        guard let serverID else { return }
        let now = Date()
        let incomingIDs = Set(playlists.map(\.id))
        snapshots.removeAll {
            $0.serverID == serverID && !incomingIDs.contains($0.playlist.id)
        }

        for playlist in playlists {
            let existing = snapshots.first {
                $0.serverID == serverID && $0.playlist.id == playlist.id
            }
            let cached = merged(playlist, preservingEntriesFrom: existing?.playlist)
            upsert(
                PlaylistOfflineCacheSnapshot(
                    serverID: serverID,
                    playlist: cached,
                    firstSeenAt: existing?.firstSeenAt ?? now,
                    updatedAt: now
                ),
                saveAfter: false
            )
        }
        save()
    }

    func cache(_ playlist: Playlist, serverID: String?) {
        guard let serverID else { return }
        let existing = snapshots.first {
            $0.serverID == serverID && $0.playlist.id == playlist.id
        }
        upsert(
            PlaylistOfflineCacheSnapshot(
                serverID: serverID,
                playlist: merged(playlist, preservingEntriesFrom: existing?.playlist),
                firstSeenAt: existing?.firstSeenAt ?? Date(),
                updatedAt: Date()
            )
        )
    }

    func remove(id: String, serverID: String?) {
        guard let serverID else { return }
        let previousCount = snapshots.count
        snapshots.removeAll { $0.serverID == serverID && $0.playlist.id == id }
        if snapshots.count != previousCount { save() }
    }

    func cacheAll(
        _ playlists: [Playlist],
        client: any MusicService,
        serverID: String?
    ) async {
        cacheList(playlists, serverID: serverID)
        if PlaylistBackupStore.shared.isEnabled {
            PlaylistBackupStore.shared.backupPlaylistList(playlists, client: client)
        }
        for playlist in playlists {
            guard let full = try? await client.playlist(id: playlist.id) else { continue }
            cache(full, serverID: serverID)
            PlaylistBackupStore.shared.backup(playlist: full, client: client)
        }
        AppLogger.shared.log("Offline playlist cache refreshed (\(playlists.count) playlists)", category: .library)
    }

    private func reload() {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(PlaylistOfflineCachePayload.self, from: data) else {
            snapshots = []
            return
        }
        snapshots = payload.snapshots
    }

    private func merged(_ incoming: Playlist, preservingEntriesFrom existing: Playlist?) -> Playlist {
        Playlist(
            id: incoming.id,
            name: incoming.name,
            comment: incoming.comment,
            owner: incoming.owner,
            songCount: incoming.songCount,
            duration: incoming.duration,
            created: incoming.created,
            changed: incoming.changed,
            played: incoming.played,
            coverArt: incoming.coverArt,
            entry: incoming.entry ?? existing?.entry
        )
    }

    private func upsert(_ snapshot: PlaylistOfflineCacheSnapshot, saveAfter: Bool = true) {
        if let index = snapshots.firstIndex(where: {
            $0.serverID == snapshot.serverID && $0.playlist.id == snapshot.playlist.id
        }) {
            snapshots[index] = snapshot
        } else {
            snapshots.append(snapshot)
        }
        if saveAfter { save() }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(PlaylistOfflineCachePayload(snapshots: snapshots)) else { return }
        try? data.write(to: fileURL, options: .atomic)
        revision &+= 1
    }
}
