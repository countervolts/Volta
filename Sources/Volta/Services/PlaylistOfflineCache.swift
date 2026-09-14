import Foundation
import Combine

struct PlaylistOfflineCacheSnapshot: Codable, Hashable, Sendable {
    var serverID: String
    var playlist: Playlist
    var firstSeenAt: Date
    var updatedAt: Date
}

struct PlaylistOfflineCachePayload: Codable, Sendable {
    var version = 1
    var snapshots: [PlaylistOfflineCacheSnapshot]
}

struct PlaylistPersistenceResult: Sendable {
    let succeeded: Bool
    let bytes: Int
    let duration: TimeInterval
}

struct PlaylistOfflineCacheLoadResult: Sendable {
    let snapshots: [PlaylistOfflineCacheSnapshot]
    let duration: TimeInterval
    let bytes: Int
}

protocol PlaylistOfflineCachePersisting: Sendable {
    func load() async -> PlaylistOfflineCacheLoadResult
    func save(_ snapshots: [PlaylistOfflineCacheSnapshot]) async -> PlaylistPersistenceResult
}

actor PlaylistOfflineCachePersistence: PlaylistOfflineCachePersisting {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() async -> PlaylistOfflineCacheLoadResult {
        let startedAt = Date()
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(PlaylistOfflineCachePayload.self, from: data) else {
            return PlaylistOfflineCacheLoadResult(
                snapshots: [],
                duration: Date().timeIntervalSince(startedAt),
                bytes: 0
            )
        }
        return PlaylistOfflineCacheLoadResult(
            snapshots: payload.snapshots,
            duration: Date().timeIntervalSince(startedAt),
            bytes: data.count
        )
    }

    func save(_ snapshots: [PlaylistOfflineCacheSnapshot]) async -> PlaylistPersistenceResult {
        let startedAt = Date()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(PlaylistOfflineCachePayload(snapshots: snapshots)) else {
            return PlaylistPersistenceResult(succeeded: false, bytes: 0, duration: Date().timeIntervalSince(startedAt))
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
            return PlaylistPersistenceResult(
                succeeded: true,
                bytes: data.count,
                duration: Date().timeIntervalSince(startedAt)
            )
        } catch {
            return PlaylistPersistenceResult(
                succeeded: false,
                bytes: data.count,
                duration: Date().timeIntervalSince(startedAt)
            )
        }
    }
}

/// Keeps provider playlists and their entries available after Offline Mode is
/// selected. This is independent from playlist backup/restore preferences.
@MainActor
final class PlaylistOfflineCache: ObservableObject {
    static let shared = PlaylistOfflineCache(
        persistence: PlaylistOfflineCachePersistence(fileURL: storageFileURL)
    )

    @Published private(set) var revision = 0

    private let persistence: any PlaylistOfflineCachePersisting
    private var snapshots: [PlaylistOfflineCacheSnapshot] = []
    private var loadTask: Task<Void, Never>?
    private var pendingSaveTask: Task<Void, Never>?
    private var persistenceGeneration: UInt64 = 0
    private var cacheAllTask: Task<Void, Never>?
    private var cacheAllGeneration: UInt64 = 0

    init(persistence: any PlaylistOfflineCachePersisting) {
        self.persistence = persistence
        self.loadTask = nil
        self.pendingSaveTask = nil
        self.cacheAllTask = nil
        self.loadTask = Task { @MainActor [weak self, persistence] in
            let loaded = await persistence.load()
            guard let self else { return }
            let hadMutation = self.persistenceGeneration != 0
            if !hadMutation {
                self.snapshots = loaded.snapshots
            } else {
                var merged = loaded.snapshots
                var indexes: [String: Int] = [:]
                indexes.reserveCapacity(merged.count + self.snapshots.count)
                for (index, snapshot) in merged.enumerated() {
                    indexes[self.snapshotKey(snapshot.serverID, playlistID: snapshot.playlist.id)] = index
                }
                for snapshot in self.snapshots {
                    let key = self.snapshotKey(snapshot.serverID, playlistID: snapshot.playlist.id)
                    if let index = indexes[key] {
                        merged[index] = snapshot
                    } else {
                        indexes[key] = merged.count
                        merged.append(snapshot)
                    }
                }
                self.snapshots = merged
            }
            self.revision &+= 1
            if loaded.duration >= 0.1 {
                AppLogger.shared.log(
                    "Offline playlist cache load took \(String(format: "%.0f", loaded.duration * 1_000))ms; playlists=\(loaded.snapshots.count); bytes=\(loaded.bytes)",
                    category: .library,
                    level: .warning
                )
            }
            self.loadTask = nil
            if hadMutation { self.save() }
        }
    }

    private static var storageFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Volta/PlaylistCache/playlists.json")
    }

    func waitUntilLoaded() async {
        await loadTask?.value
    }

    func waitUntilPersisted() async {
        await pendingSaveTask?.value
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

    func cacheList(_ playlists: [Playlist], serverID: String?, persist: Bool = true) {
        guard let serverID else { return }
        mergeList(playlists, serverID: serverID)
        if persist { save() }
    }

    func cache(_ playlist: Playlist, serverID: String?, persist: Bool = true) {
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
        if persist { save() }
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
        await cacheAll(playlists, serverID: serverID, backupClient: client) { id in
            try? await client.playlist(id: id)
        }
    }

    func cacheAll(
        _ playlists: [Playlist],
        serverID: String?,
        backupClient: (any MusicService)? = nil,
        fetch: @escaping @Sendable (String) async -> Playlist?
    ) async {
        guard let serverID else { return }
        cacheAllGeneration &+= 1
        let generation = cacheAllGeneration
        cacheAllTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performCacheAll(
                playlists,
                backupClient: backupClient,
                fetch: fetch,
                serverID: serverID,
                generation: generation
            )
        }
        cacheAllTask = task
        await task.value
        if cacheAllGeneration == generation { cacheAllTask = nil }
    }

    private func performCacheAll(
        _ playlists: [Playlist],
        backupClient: (any MusicService)?,
        fetch: @escaping @Sendable (String) async -> Playlist?,
        serverID: String,
        generation: UInt64
    ) async {
        await waitUntilLoaded()
        guard generation == cacheAllGeneration else { return }

        // One in-memory merge replaces the old O(N²) scan-and-save path.
        cacheList(playlists, serverID: serverID, persist: false)
        let backupsEnabled = PlaylistBackupStore.shared.isEnabled
        if backupsEnabled {
            PlaylistBackupStore.shared.backupPlaylistList(
                playlists,
                client: backupClient,
                persist: false
            )
        }

        var detailedPlaylists: [Playlist] = []
        detailedPlaylists.reserveCapacity(playlists.count)
        for playlist in playlists {
            guard !Task.isCancelled, generation == cacheAllGeneration else { return }
            guard let full = await fetch(playlist.id) else { continue }
            guard !Task.isCancelled, generation == cacheAllGeneration else { return }
            detailedPlaylists.append(full)
            // A fast/local client can return immediately for every playlist.
            // Give SwiftUI and cancellation a scheduling point between merges.
            await Task.yield()
        }

        guard !Task.isCancelled, generation == cacheAllGeneration else { return }
        mergeDetails(detailedPlaylists, serverID: serverID)
        if backupsEnabled {
            PlaylistBackupStore.shared.backupPlaylistList(
                detailedPlaylists,
                client: backupClient,
                persist: false
            )
        }
        save()
        await waitUntilPersisted()
        if backupsEnabled {
            PlaylistBackupStore.shared.persist()
            await PlaylistBackupStore.shared.waitUntilPersisted()
        }
        AppLogger.shared.log("Offline playlist cache refreshed (\(playlists.count) playlists)", category: .library)
    }

    private func mergeList(_ playlists: [Playlist], serverID: String) {
        let incomingIDs = Set(playlists.map(\.id))
        var retained = snapshots.filter {
            $0.serverID != serverID || incomingIDs.contains($0.playlist.id)
        }
        var indexes: [String: Int] = [:]
        indexes.reserveCapacity(retained.count)
        for (index, snapshot) in retained.enumerated() where snapshot.serverID == serverID {
            indexes[snapshot.playlist.id] = index
        }

        let now = Date()
        for playlist in playlists {
            if let index = indexes[playlist.id] {
                let existing = retained[index]
                retained[index] = PlaylistOfflineCacheSnapshot(
                    serverID: serverID,
                    playlist: merged(playlist, preservingEntriesFrom: existing.playlist),
                    firstSeenAt: existing.firstSeenAt,
                    updatedAt: now
                )
            } else {
                indexes[playlist.id] = retained.count
                retained.append(
                    PlaylistOfflineCacheSnapshot(
                        serverID: serverID,
                        playlist: playlist,
                        firstSeenAt: now,
                        updatedAt: now
                    )
                )
            }
        }
        snapshots = retained
    }

    private func mergeDetails(_ playlists: [Playlist], serverID: String) {
        var indexes: [String: Int] = [:]
        indexes.reserveCapacity(playlists.count)
        for (index, snapshot) in snapshots.enumerated() where snapshot.serverID == serverID {
            indexes[snapshot.playlist.id] = index
        }

        let now = Date()
        for playlist in playlists {
            if let index = indexes[playlist.id] {
                let existing = snapshots[index]
                snapshots[index] = PlaylistOfflineCacheSnapshot(
                    serverID: serverID,
                    playlist: merged(playlist, preservingEntriesFrom: existing.playlist),
                    firstSeenAt: existing.firstSeenAt,
                    updatedAt: now
                )
            } else {
                indexes[playlist.id] = snapshots.count
                snapshots.append(
                    PlaylistOfflineCacheSnapshot(
                        serverID: serverID,
                        playlist: playlist,
                        firstSeenAt: now,
                        updatedAt: now
                    )
                )
            }
        }
    }

    private func snapshotKey(_ serverID: String, playlistID: String) -> String {
        "\(serverID)\u{0}\(playlistID)"
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

    private func upsert(_ snapshot: PlaylistOfflineCacheSnapshot) {
        if let index = snapshots.firstIndex(where: {
            $0.serverID == snapshot.serverID && $0.playlist.id == snapshot.playlist.id
        }) {
            snapshots[index] = snapshot
        } else {
            snapshots.append(snapshot)
        }
    }

    private func save() {
        persistenceGeneration &+= 1
        let generation = persistenceGeneration
        let snapshot = snapshots
        pendingSaveTask?.cancel()
        let persistence = self.persistence
        pendingSaveTask = Task { @MainActor [weak self, persistence] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            let result = await persistence.save(snapshot)
            guard let self, self.persistenceGeneration == generation else { return }
            self.revision &+= 1
            if result.duration >= 0.1 {
                AppLogger.shared.log(
                    "Offline playlist cache persistence took \(String(format: "%.0f", result.duration * 1_000))ms; playlists=\(snapshot.count); bytes=\(result.bytes); success=\(result.succeeded)",
                    category: .library,
                    level: result.succeeded ? .info : .warning
                )
            }
        }
    }
}
