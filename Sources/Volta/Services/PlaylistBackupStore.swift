import Foundation
import Combine

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

struct PlaylistBackupPayload: Codable, Sendable {
    var version = 1
    var snapshots: [PlaylistBackupSnapshot]
}

struct PlaylistBackupLoadResult: Sendable {
    let snapshots: [PlaylistBackupSnapshot]
    let bytes: Int
    let duration: TimeInterval
}

struct PlaylistBackupPersistenceResult: Sendable {
    let succeeded: Bool
    let bytes: Int
    let duration: TimeInterval
}

protocol PlaylistBackupPersisting: Sendable {
    func load() async -> PlaylistBackupLoadResult
    func save(_ snapshots: [PlaylistBackupSnapshot]) async -> PlaylistBackupPersistenceResult
}

actor PlaylistBackupPersistence: PlaylistBackupPersisting {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() async -> PlaylistBackupLoadResult {
        let startedAt = Date()
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(PlaylistBackupPayload.self, from: data) else {
            return PlaylistBackupLoadResult(
                snapshots: [],
                bytes: 0,
                duration: Date().timeIntervalSince(startedAt)
            )
        }
        return PlaylistBackupLoadResult(
            snapshots: payload.snapshots,
            bytes: data.count,
            duration: Date().timeIntervalSince(startedAt)
        )
    }

    func save(_ snapshots: [PlaylistBackupSnapshot]) async -> PlaylistBackupPersistenceResult {
        let startedAt = Date()
        let payload = PlaylistBackupPayload(snapshots: snapshots)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else {
            return PlaylistBackupPersistenceResult(succeeded: false, bytes: 0, duration: Date().timeIntervalSince(startedAt))
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
            return PlaylistBackupPersistenceResult(
                succeeded: true,
                bytes: data.count,
                duration: Date().timeIntervalSince(startedAt)
            )
        } catch {
            return PlaylistBackupPersistenceResult(
                succeeded: false,
                bytes: data.count,
                duration: Date().timeIntervalSince(startedAt)
            )
        }
    }
}

@MainActor
final class PlaylistBackupStore: ObservableObject {
    private static let defaultPersistence = PlaylistBackupPersistence(fileURL: storageFileURL)
    static let shared = PlaylistBackupStore(persistence: defaultPersistence)

    @Published private(set) var snapshots: [PlaylistBackupSnapshot] = []

    private let persistenceActor: any PlaylistBackupPersisting
    private var loadTask: Task<Void, Never>?
    private var pendingSaveTask: Task<Void, Never>?
    private var persistenceGeneration: UInt64 = 0
    private var backupAllTask: Task<Void, Never>?
    private var backupAllGeneration: UInt64 = 0
    private var persistedBytes = 0

    init(persistence: any PlaylistBackupPersisting) {
        persistenceActor = persistence
        loadTask = nil
        pendingSaveTask = nil
        backupAllTask = nil
        let persistence = persistenceActor
        loadTask = Task { @MainActor [weak self, persistence] in
            let loaded = await persistence.load()
            guard let self else { return }
            let hadMutation = self.persistenceGeneration != 0
            if !hadMutation {
                self.snapshots = loaded.snapshots
            } else {
                var merged = loaded.snapshots
                var indexes = Dictionary(uniqueKeysWithValues: merged.enumerated().map { ($0.element.id, $0.offset) })
                for snapshot in self.snapshots {
                    if let index = indexes[snapshot.id] {
                        merged[index] = snapshot
                    } else {
                        indexes[snapshot.id] = merged.count
                        merged.append(snapshot)
                    }
                }
                self.snapshots = merged
            }
            self.persistedBytes = loaded.bytes
            if loaded.duration >= 0.1 {
                AppLogger.shared.log(
                    "Playlist backup load took \(String(format: "%.0f", loaded.duration * 1_000))ms; playlists=\(loaded.snapshots.count); bytes=\(loaded.bytes)",
                    category: .library,
                    level: .warning
                )
            }
            self.loadTask = nil
            if hadMutation { self.persist() }
        }
    }

    nonisolated static var storageDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Volta/PlaylistBackups", isDirectory: true)
    }

    nonisolated static var storageFileURL: URL {
        storageDirectoryURL.appendingPathComponent("playlists.json")
    }

    nonisolated static func snapshotsOnDisk() async -> [PlaylistBackupSnapshot] {
        await defaultPersistence.load().snapshots
    }

    nonisolated static func deletedSnapshots(from snapshots: [PlaylistBackupSnapshot]) -> [PlaylistBackupSnapshot] {
        snapshots
            .filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? $0.updatedAt) > ($1.deletedAt ?? $1.updatedAt) }
    }

    nonisolated static func deletedSnapshotsOnDisk() async -> [PlaylistBackupSnapshot] {
        deletedSnapshots(from: await snapshotsOnDisk())
    }

    nonisolated static func estimatedSizeBytesOnDisk() async -> Int {
        await defaultPersistence.load().bytes
    }

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "autoPlaylistBackupEnabled") as? Bool ?? true
    }

    var deletedSnapshots: [PlaylistBackupSnapshot] {
        Self.deletedSnapshots(from: snapshots)
    }

    func waitUntilLoaded() async {
        await loadTask?.value
    }

    func waitUntilPersisted() async {
        await pendingSaveTask?.value
    }

    func reload() {
        loadTask?.cancel()
        let persistence = persistenceActor
        loadTask = Task { @MainActor [weak self, persistence] in
            let loaded = await persistence.load()
            guard let self else { return }
            self.snapshots = loaded.snapshots
            self.persistedBytes = loaded.bytes
            if loaded.duration >= 0.1 {
                AppLogger.shared.log(
                    "Playlist backup load took \(String(format: "%.0f", loaded.duration * 1_000))ms; playlists=\(loaded.snapshots.count); bytes=\(loaded.bytes)",
                    category: .library,
                    level: .warning
                )
            }
            self.loadTask = nil
        }
    }

    func backupPlaylistList(
        _ playlists: [Playlist],
        client: (any MusicService)? = nil,
        persist: Bool = true
    ) {
        guard isEnabled else { return }
        var indexes: [String: Int] = [:]
        indexes.reserveCapacity(snapshots.count)
        for (index, snapshot) in snapshots.enumerated() {
            indexes[snapshot.id] = index
        }
        for playlist in playlists {
            let existing = indexes[playlist.id].map { snapshots[$0] }
            let snapshot = snapshot(from: playlist, client: client, existing: existing)
            if let index = indexes[playlist.id] {
                snapshots[index] = snapshot
            } else {
                indexes[playlist.id] = snapshots.count
                snapshots.append(snapshot)
            }
        }
        if persist { self.persist() }
    }

    func backup(
        playlist: Playlist,
        client: (any MusicService)? = nil,
        deletedAt: Date? = nil,
        persist: Bool = true
    ) {
        guard isEnabled || deletedAt != nil else { return }
        upsert(snapshot(from: playlist, client: client, deletedAt: deletedAt))
        if persist { self.persist() }
    }

    func backupPlaylistListAndDetails(
        _ playlists: [Playlist],
        client: any MusicService
    ) async {
        guard isEnabled else { return }
        await waitUntilLoaded()
        backupPlaylistList(playlists, client: client, persist: false)
        var detailedPlaylists: [Playlist] = []
        detailedPlaylists.reserveCapacity(playlists.count)
        for playlist in playlists {
            guard !Task.isCancelled else { return }
            guard let full = try? await client.playlist(id: playlist.id) else { continue }
            detailedPlaylists.append(full)
            await Task.yield()
        }
        guard !Task.isCancelled else { return }
        backupPlaylistList(detailedPlaylists, client: client, persist: false)
        persist()
        await waitUntilPersisted()
    }

    func backup(playlistID: String, client: any MusicService) async {
        guard isEnabled else { return }
        guard let playlist = try? await client.playlist(id: playlistID) else { return }
        backup(playlist: playlist, client: client)
    }

    func backupAll(client: any MusicService) async {
        await backupAll(
            fetchPlaylists: { try? await client.playlists() },
            fetchPlaylist: { id in try? await client.playlist(id: id) },
            client: client
        )
    }

    func backupAll(
        fetchPlaylists: @escaping @Sendable () async -> [Playlist]?,
        fetchPlaylist: @escaping @Sendable (String) async -> Playlist?,
        client: (any MusicService)? = nil
    ) async {
        guard isEnabled else { return }
        backupAllGeneration &+= 1
        let generation = backupAllGeneration
        backupAllTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performBackupAll(
                fetchPlaylists: fetchPlaylists,
                fetchPlaylist: fetchPlaylist,
                client: client,
                generation: generation
            )
        }
        backupAllTask = task
        await task.value
        if backupAllGeneration == generation { backupAllTask = nil }
    }

    private func performBackupAll(
        fetchPlaylists: @escaping @Sendable () async -> [Playlist]?,
        fetchPlaylist: @escaping @Sendable (String) async -> Playlist?,
        client: (any MusicService)?,
        generation: UInt64
    ) async {
        await waitUntilLoaded()
        guard generation == backupAllGeneration,
              let playlists = await fetchPlaylists() else { return }
        backupPlaylistList(playlists, client: client, persist: false)
        var detailedPlaylists: [Playlist] = []
        detailedPlaylists.reserveCapacity(playlists.count)
        for playlist in playlists {
            guard !Task.isCancelled, generation == backupAllGeneration else { return }
            guard let full = await fetchPlaylist(playlist.id) else { continue }
            detailedPlaylists.append(full)
            await Task.yield()
        }
        guard !Task.isCancelled, generation == backupAllGeneration else { return }
        backupPlaylistList(detailedPlaylists, client: client, persist: false)
        persist()
        await waitUntilPersisted()
        AppLogger.shared.log("Playlist backups refreshed (\(playlists.count) playlists)", category: .library)
    }

    func markDeleted(_ playlist: Playlist, client: any MusicService) async {
        let full = (try? await client.playlist(id: playlist.id)) ?? playlist
        backup(playlist: full, client: client, deletedAt: Date())
    }

    func restore(_ snapshot: PlaylistBackupSnapshot, client: any MusicService) async throws -> Playlist {
        await waitUntilLoaded()
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
        self.persist()
        AppLogger.shared.log("Restored playlist backup '\(snapshot.name)' as '\(name)'", category: .library)
        return restored
    }

    func delete(_ snapshot: PlaylistBackupSnapshot) {
        snapshots.removeAll { $0.id == snapshot.id }
        persist()
        AppLogger.shared.log("Deleted playlist backup '\(snapshot.name)'", category: .library)
    }

    func estimatedSizeBytes() -> Int {
        persistedBytes
    }

    func persist() {
        persistenceGeneration &+= 1
        let generation = persistenceGeneration
        let snapshot = snapshots
        pendingSaveTask?.cancel()
        let persistence = persistenceActor
        pendingSaveTask = Task { @MainActor [weak self, persistence] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            let result = await persistence.save(snapshot)
            guard let self, self.persistenceGeneration == generation else { return }
            self.persistedBytes = result.bytes
            if result.duration >= 0.1 {
                AppLogger.shared.log(
                    "Playlist backup persistence took \(String(format: "%.0f", result.duration * 1_000))ms; playlists=\(snapshot.count); bytes=\(result.bytes); success=\(result.succeeded)",
                    category: .library,
                    level: result.succeeded ? .info : .warning
                )
            }
        }
    }

    private func snapshot(
        from playlist: Playlist,
        client: (any MusicService)?,
        deletedAt: Date? = nil,
        existing: PlaylistBackupSnapshot? = nil
    ) -> PlaylistBackupSnapshot {
        let existing = existing ?? snapshots.first { $0.id == playlist.id }
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

    private func upsert(_ snapshot: PlaylistBackupSnapshot) {
        if let index = snapshots.firstIndex(where: { $0.id == snapshot.id }) {
            snapshots[index] = snapshot
        } else {
            snapshots.append(snapshot)
        }
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
        AppLogger.shared.log("Saved mix '\(playlistTitle)' as playlist '\(name)' (\(mix.songs.count) songs)", category: .library)
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
