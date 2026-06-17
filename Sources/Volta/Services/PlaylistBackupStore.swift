import Foundation
import Observation

struct PlaylistBackupSnapshot: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var name: String
    var comment: String?
    var songIDs: [String]
    var updatedAt: Date
    var deletedAt: Date?
    var serverURL: String?

    var songCount: Int { songIDs.count }
}

enum PlaylistBackupError: LocalizedError {
    case createFailed

    var errorDescription: String? {
        switch self {
        case .createFailed: "The server did not return a playlist."
        }
    }
}

private struct PlaylistBackupPayload: Codable {
    var version = 1
    var snapshots: [PlaylistBackupSnapshot]
}

@MainActor
@Observable
final class PlaylistBackupStore {
    static let shared = PlaylistBackupStore()

    private(set) var snapshots: [PlaylistBackupSnapshot] = []

    private let fileURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("Volta/PlaylistBackups", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("playlists.json")
        reload()
    }

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "autoPlaylistBackupEnabled") as? Bool ?? true
    }

    var deletedSnapshots: [PlaylistBackupSnapshot] {
        snapshots
            .filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? $0.updatedAt) > ($1.deletedAt ?? $1.updatedAt) }
    }

    func reload() {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(PlaylistBackupPayload.self, from: data) else {
            snapshots = []
            return
        }
        snapshots = payload.snapshots
    }

    func backupPlaylistList(_ playlists: [Playlist], client: (any MusicService)? = nil) {
        guard isEnabled else { return }
        for playlist in playlists {
            upsert(snapshot(from: playlist, client: client), saveAfter: false)
        }
        save()
    }

    func backup(playlist: Playlist, client: (any MusicService)? = nil, deletedAt: Date? = nil) {
        guard isEnabled || deletedAt != nil else { return }
        upsert(snapshot(from: playlist, client: client, deletedAt: deletedAt))
    }

    func backup(playlistID: String, client: any MusicService) async {
        guard isEnabled else { return }
        guard let playlist = try? await client.playlist(id: playlistID) else { return }
        backup(playlist: playlist, client: client)
    }

    func backupAll(client: any MusicService) async {
        guard isEnabled else { return }
        guard let playlists = try? await client.playlists() else { return }
        backupPlaylistList(playlists, client: client)
        for playlist in playlists {
            await backup(playlistID: playlist.id, client: client)
        }
        AppLogger.shared.log("Playlist backups refreshed (\(playlists.count) playlists)", category: .other)
    }

    func markDeleted(_ playlist: Playlist, client: any MusicService) async {
        let full = (try? await client.playlist(id: playlist.id)) ?? playlist
        backup(playlist: full, client: client, deletedAt: Date())
    }

    func restore(_ snapshot: PlaylistBackupSnapshot, client: any MusicService) async throws -> Playlist {
        let name = try await uniqueRestoredName(for: snapshot.name, client: client)
        guard let created = try await client.createPlaylist(name: name) else {
            throw PlaylistBackupError.createFailed
        }
        for songID in snapshot.songIDs {
            try await client.addToPlaylist(playlistID: created.id, songID: songID)
        }
        if let comment = snapshot.comment, !comment.isEmpty {
            try? await client.updatePlaylistComment(playlistID: created.id, comment: comment)
        }

        let restored = (try? await client.playlist(id: created.id)) ?? created
        snapshots.removeAll { $0.id == snapshot.id }
        let restoredSnapshot = PlaylistBackupSnapshot(
            id: restored.id,
            name: restored.name,
            comment: restored.comment ?? snapshot.comment,
            songIDs: restored.entry?.map(\.id) ?? snapshot.songIDs,
            updatedAt: Date(),
            deletedAt: nil,
            serverURL: client.config.baseURL.absoluteString
        )
        upsert(restoredSnapshot)
        AppLogger.shared.log("Restored playlist backup '\(snapshot.name)' as '\(name)'", category: .other)
        return restored
    }

    func delete(_ snapshot: PlaylistBackupSnapshot) {
        snapshots.removeAll { $0.id == snapshot.id }
        save()
        AppLogger.shared.log("Deleted playlist backup '\(snapshot.name)'", category: .other)
    }

    func estimatedSizeBytes() -> Int {
        (try? Data(contentsOf: fileURL).count) ?? 0
    }

    private func snapshot(from playlist: Playlist, client: (any MusicService)?, deletedAt: Date? = nil) -> PlaylistBackupSnapshot {
        let existing = snapshots.first { $0.id == playlist.id }
        return PlaylistBackupSnapshot(
            id: playlist.id,
            name: playlist.name,
            comment: playlist.comment,
            songIDs: playlist.entry?.map(\.id) ?? existing?.songIDs ?? [],
            updatedAt: Date(),
            deletedAt: deletedAt,
            serverURL: client?.config.baseURL.absoluteString ?? existing?.serverURL
        )
    }

    private func upsert(_ snapshot: PlaylistBackupSnapshot, saveAfter: Bool = true) {
        if let index = snapshots.firstIndex(where: { $0.id == snapshot.id }) {
            snapshots[index] = snapshot
        } else {
            snapshots.append(snapshot)
        }
        if saveAfter { save() }
    }

    private func save() {
        let payload = PlaylistBackupPayload(snapshots: snapshots)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func uniqueRestoredName(for name: String, client: any MusicService) async throws -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Restored Playlist" : name
        let existing = Set((try await client.playlists()).map { $0.name.lowercased() })
        let restoredBase = existing.contains(base.lowercased()) ? "\(base) Restored" : base
        guard existing.contains(restoredBase.lowercased()) else { return restoredBase }
        for index in 2...99 {
            let candidate = "\(restoredBase) \(index)"
            if !existing.contains(candidate.lowercased()) {
                return candidate
            }
        }
        return "\(restoredBase) \(Date().formatted(date: .numeric, time: .shortened))"
    }
}

enum PlaylistWriter {
    static func saveMixAsPlaylist(_ mix: MusicMix, client: any MusicService, title: String? = nil) async throws -> String {
        let playlistTitle = title ?? mix.title
        let name = try await uniquePlaylistName(for: playlistTitle, client: client)
        guard let playlist = try await client.createPlaylist(name: name) else {
            throw PlaylistBackupError.createFailed
        }
        await PlaylistBackupStore.shared.backup(playlist: playlist, client: client)
        for song in mix.songs {
            try await client.addToPlaylist(playlistID: playlist.id, songID: song.id)
        }
        await PlaylistBackupStore.shared.backup(playlistID: playlist.id, client: client)
        AppLogger.shared.log("Saved mix '\(playlistTitle)' as playlist '\(name)' (\(mix.songs.count) songs)", category: .other)
        return name
    }

    private static func uniquePlaylistName(for title: String, client: any MusicService) async throws -> String {
        let base = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Saved Mix" : title
        let existing = Set((try await client.playlists()).map { $0.name.lowercased() })
        guard !existing.contains(base.lowercased()) else {
            for index in 2...99 {
                let candidate = "\(base) \(index)"
                if !existing.contains(candidate.lowercased()) {
                    return candidate
                }
            }
            return "\(base) \(Date().formatted(date: .numeric, time: .shortened))"
        }
        return base
    }
}
