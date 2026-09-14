import Foundation
import XCTest

@testable import Volta

final class PersistenceRegressionTests: XCTestCase {
    @MainActor
    func testOfflineBulkRefreshUsesOneLogicalCacheSave() async {
        let defaults = UserDefaults.standard
        let previousBackupSetting = defaults.object(forKey: "autoPlaylistBackupEnabled")
        defaults.set(false, forKey: "autoPlaylistBackupEnabled")
        defer {
            if let previousBackupSetting {
                defaults.set(previousBackupSetting, forKey: "autoPlaylistBackupEnabled")
            } else {
                defaults.removeObject(forKey: "autoPlaylistBackupEnabled")
            }
        }

        let persistence = CountingOfflinePersistence()
        let cache = PlaylistOfflineCache(persistence: persistence)
        await cache.waitUntilLoaded()
        let playlists = (0..<120).map { makePlaylist(index: $0, songCount: 20) }
        let details = Dictionary(uniqueKeysWithValues: playlists.map { ($0.id, $0) })

        await cache.cacheAll(playlists, serverID: "server-1") { details[$0] }
        await cache.waitUntilPersisted()

        let saveCount = await persistence.saveCount()
        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(cache.playlists(for: "server-1").count, 120)
    }

    @MainActor
    func testNewestOfflineRefreshWinsWhenOlderRefreshIsCancelled() async {
        let defaults = UserDefaults.standard
        let previousBackupSetting = defaults.object(forKey: "autoPlaylistBackupEnabled")
        defaults.set(false, forKey: "autoPlaylistBackupEnabled")
        defer {
            if let previousBackupSetting {
                defaults.set(previousBackupSetting, forKey: "autoPlaylistBackupEnabled")
            } else {
                defaults.removeObject(forKey: "autoPlaylistBackupEnabled")
            }
        }

        let persistence = CountingOfflinePersistence()
        let cache = PlaylistOfflineCache(persistence: persistence)
        await cache.waitUntilLoaded()
        let old = [makePlaylist(index: 1, songCount: 20)]
        let newest = [makePlaylist(index: 2, songCount: 20)]
        let oldStarted = TestSignal()
        let releaseOld = TestSignal()

        let oldTask = Task { @MainActor in
            await cache.cacheAll(old, serverID: "server-1") { _ in
                await oldStarted.signal()
                await releaseOld.wait()
                return old[0]
            }
        }
        await oldStarted.wait()
        let newestTask = Task { @MainActor in
            await cache.cacheAll(newest, serverID: "server-1") { _ in newest[0] }
        }

        await newestTask.value
        await releaseOld.signal()
        await oldTask.value

        XCTAssertEqual(cache.playlists(for: "server-1").map(\.id), ["playlist-2"])
        let saveCount = await persistence.saveCount()
        XCTAssertEqual(saveCount, 1)
    }

    @MainActor
    func testBackupBulkRefreshUsesOneLogicalBackupSave() async {
        let defaults = UserDefaults.standard
        let previousBackupSetting = defaults.object(forKey: "autoPlaylistBackupEnabled")
        defaults.set(true, forKey: "autoPlaylistBackupEnabled")
        defer {
            if let previousBackupSetting {
                defaults.set(previousBackupSetting, forKey: "autoPlaylistBackupEnabled")
            } else {
                defaults.removeObject(forKey: "autoPlaylistBackupEnabled")
            }
        }

        let persistence = CountingBackupPersistence()
        let store = PlaylistBackupStore(persistence: persistence)
        await store.waitUntilLoaded()
        let playlists = (0..<120).map { makePlaylist(index: $0, songCount: 20) }
        let details = Dictionary(uniqueKeysWithValues: playlists.map { ($0.id, $0) })

        await store.backupAll(
            fetchPlaylists: { playlists },
            fetchPlaylist: { details[$0] }
        )

        let saveCount = await persistence.saveCount()
        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(store.snapshots.count, 120)
    }

    func testLargeOfflineCacheSurvivesRoundTrip() async throws {
        let fileURL = temporaryFileURL(named: "offline-playlist-cache")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let snapshots = (0..<120).map { index in
            PlaylistOfflineCacheSnapshot(
                serverID: "server-1",
                playlist: makePlaylist(index: index, songCount: index.isMultiple(of: 3) ? 240 : 12),
                firstSeenAt: Date(timeIntervalSince1970: TimeInterval(index)),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(index + 1))
            )
        }
        let persistence = PlaylistOfflineCachePersistence(fileURL: fileURL)

        let write = await persistence.save(snapshots)
        let loaded = await persistence.load()

        XCTAssertTrue(write.succeeded)
        XCTAssertEqual(loaded.snapshots, snapshots)
        XCTAssertGreaterThan(write.bytes, 100_000)
    }

    func testLargeBackupSurvivesRoundTripWithSingleBulkWrite() async throws {
        let fileURL = temporaryFileURL(named: "playlist-backups")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let snapshots = (0..<120).map { index in
            PlaylistBackupSnapshot(
                id: "playlist-\(index)",
                name: "Playlist \(index)",
                comment: index.isMultiple(of: 2) ? "Synthetic regression data" : nil,
                songIDs: (0..<(index.isMultiple(of: 4) ? 320 : 18)).map { "song-\(index)-\($0)" },
                updatedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                deletedAt: index == 7 ? Date(timeIntervalSince1970: 999) : nil,
                serverURL: "https://music.example.test"
            )
        }
        let persistence = PlaylistBackupPersistence(fileURL: fileURL)

        let write = await persistence.save(snapshots)
        let loaded = await persistence.load()

        XCTAssertTrue(write.succeeded)
        XCTAssertEqual(loaded.snapshots, snapshots)
        XCTAssertGreaterThan(write.bytes, 100_000)
    }

    func testBuild13BackupPayloadRemainsDecodable() throws {
        let data = Data(#"{"version":1,"snapshots":[{"id":"playlist-1","name":"Saved","comment":null,"songIDs":["song-1","song-2"],"updatedAt":725846400,"deletedAt":null,"serverURL":"https://music.example.test"}]}"#.utf8)

        let payload = try JSONDecoder().decode(PlaylistBackupPayload.self, from: data)

        XCTAssertEqual(payload.version, 1)
        XCTAssertEqual(payload.snapshots.first?.songIDs, ["song-1", "song-2"])
    }

    func testBuild13OfflineCachePayloadRemainsDecodable() throws {
        let data = Data(#"{"version":1,"snapshots":[{"serverID":"server-1","playlist":{"id":"playlist-1","name":"Cached","entry":[{"id":"song-1","title":"Track"}]},"firstSeenAt":725846400,"updatedAt":725846401}]}"#.utf8)

        let payload = try JSONDecoder().decode(PlaylistOfflineCachePayload.self, from: data)

        XCTAssertEqual(payload.version, 1)
        XCTAssertEqual(payload.snapshots.first?.serverID, "server-1")
        XCTAssertEqual(payload.snapshots.first?.playlist.entry?.first?.id, "song-1")
    }

    private func temporaryFileURL(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("volta-persistence-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name + ".json")
    }

    private func makePlaylist(index: Int, songCount: Int) -> Playlist {
        Playlist(
            id: "playlist-\(index)",
            name: "Playlist \(index)",
            comment: index.isMultiple(of: 2) ? "Synthetic regression data" : nil,
            owner: "tester",
            songCount: songCount,
            duration: songCount * 180,
            created: "2024-01-01T00:00:00Z",
            changed: "2024-01-02T00:00:00Z",
            played: nil,
            coverArt: nil,
            entry: (0..<songCount).map { songIndex in
                Song(
                    id: "song-\(index)-\(songIndex)",
                    title: "Song \(songIndex)",
                    album: "Album \(index)",
                    artist: "Artist \(index)",
                    albumArtist: nil,
                    albumId: "album-\(index)",
                    artistId: "artist-\(index)",
                    albumArtistId: nil,
                    coverArt: nil,
                    duration: 180,
                    track: songIndex + 1,
                    discNumber: 1,
                    year: 2024,
                    genre: "Regression",
                    size: 1_000_000,
                    contentType: "audio/mp4",
                    suffix: "m4a",
                    codec: "alac",
                    bitRate: 256,
                    path: nil,
                    playCount: nil,
                    bpm: nil,
                    explicitStatus: nil,
                    starred: nil,
                    contributes: nil,
                    replayGain: nil,
                    samplingRate: 44_100,
                    bitDepth: 24,
                    channelCount: 2,
                    displayComposer: nil,
                    contributors: nil
                )
            }
        )
    }
}

private actor CountingOfflinePersistence: PlaylistOfflineCachePersisting {
    private var saves = 0

    func load() async -> PlaylistOfflineCacheLoadResult {
        PlaylistOfflineCacheLoadResult(snapshots: [], duration: 0, bytes: 0)
    }

    func save(_ snapshots: [PlaylistOfflineCacheSnapshot]) async -> PlaylistPersistenceResult {
        saves += 1
        return PlaylistPersistenceResult(succeeded: true, bytes: snapshots.count, duration: 0)
    }

    func saveCount() -> Int { saves }
}

private actor CountingBackupPersistence: PlaylistBackupPersisting {
    private var saves = 0

    func load() async -> PlaylistBackupLoadResult {
        PlaylistBackupLoadResult(snapshots: [], bytes: 0, duration: 0)
    }

    func save(_ snapshots: [PlaylistBackupSnapshot]) async -> PlaylistBackupPersistenceResult {
        saves += 1
        return PlaylistBackupPersistenceResult(succeeded: true, bytes: snapshots.count, duration: 0)
    }

    func saveCount() -> Int { saves }
}

private actor TestSignal {
    private var signaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        signaled = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }

    func wait() async {
        if signaled { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
