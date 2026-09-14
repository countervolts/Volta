import Foundation
import UIKit

extension Notification.Name {
    static let playEventRecorded = Notification.Name("PlayEventRecorded")
}

// a play event recorded locally when >= 50% of the song is heard.
struct PlayEvent: Codable, Identifiable, Sendable {
    var id: UUID
    var songID: String
    var title: String
    var artist: String
    var album: String
    var albumID: String?
    var artistID: String?
    var coverArt: String?
    var duration: Int      // seconds
    var genre: String?
    var timestamp: Date    // when the play completed

    init(song: Song, timestamp: Date = .now) {
        id = UUID()
        songID = song.id
        title = song.title
        artist = song.primaryArtistName
        album = song.album ?? "Unknown Album"
        albumID = song.albumId
        artistID = song.primaryArtistID
        coverArt = song.coverArt
        duration = song.duration ?? 0
        genre = song.genre
        self.timestamp = timestamp
    }
}

private struct StatsLoadResult: Sendable {
    let realEvents: [PlayEvent]
    let fakeEvents: [PlayEvent]
    let realBytes: Int
    let fakeBytes: Int
    let duration: TimeInterval
}

private struct StatsWriteResult: Sendable {
    let succeeded: Bool
    let bytes: Int
    let duration: TimeInterval
}

private actor StatsPersistence {
    let fileURL: URL
    let fakeFileURL: URL
    private var realGeneration: UInt64 = 0
    private var fakeGeneration: UInt64 = 0

    init(fileURL: URL, fakeFileURL: URL) {
        self.fileURL = fileURL
        self.fakeFileURL = fakeFileURL
    }

    func load(fakeEnabled: Bool) -> StatsLoadResult {
        let startedAt = Date()
        let realData = try? Data(contentsOf: fileURL)
        let realEvents = realData.flatMap { try? JSONDecoder().decode([PlayEvent].self, from: $0) } ?? []
        let fakeData = fakeEnabled ? (try? Data(contentsOf: fakeFileURL)) : nil
        let fakeEvents = fakeData.flatMap { try? JSONDecoder().decode([PlayEvent].self, from: $0) } ?? []
        return StatsLoadResult(
            realEvents: realEvents,
            fakeEvents: fakeEvents,
            realBytes: realData?.count ?? 0,
            fakeBytes: fakeData?.count ?? 0,
            duration: Date().timeIntervalSince(startedAt)
        )
    }

    func saveReal(_ events: [PlayEvent], generation: UInt64) -> StatsWriteResult? {
        guard generation >= realGeneration else { return nil }
        realGeneration = generation
        return save(events, to: fileURL)
    }

    func saveFake(_ events: [PlayEvent], generation: UInt64) -> StatsWriteResult? {
        guard generation >= fakeGeneration else { return nil }
        fakeGeneration = generation
        return save(events, to: fakeFileURL)
    }

    func removeFake(generation: UInt64) -> StatsWriteResult? {
        guard generation >= fakeGeneration else { return nil }
        fakeGeneration = generation
        let startedAt = Date()
        do {
            try FileManager.default.removeItem(at: fakeFileURL)
        } catch CocoaError.fileNoSuchFile {
            // Already absent.
        } catch {
            return StatsWriteResult(succeeded: false, bytes: 0, duration: Date().timeIntervalSince(startedAt))
        }
        return StatsWriteResult(succeeded: true, bytes: 0, duration: Date().timeIntervalSince(startedAt))
    }

    private func save(_ events: [PlayEvent], to url: URL) -> StatsWriteResult {
        let startedAt = Date()
        guard let data = try? JSONEncoder().encode(events) else {
            return StatsWriteResult(succeeded: false, bytes: 0, duration: Date().timeIntervalSince(startedAt))
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            return StatsWriteResult(
                succeeded: true,
                bytes: data.count,
                duration: Date().timeIntervalSince(startedAt)
            )
        } catch {
            return StatsWriteResult(
                succeeded: false,
                bytes: data.count,
                duration: Date().timeIntervalSince(startedAt)
            )
        }
    }
}

// Persists play events asynchronously. Synchronous readers return an in-memory
// snapshot only; they never wait for disk or JSON work.
final class StatsStore: @unchecked Sendable {
    static let shared = StatsStore()

    private let persistence: StatsPersistence
    private let lock = NSLock()
    private var realEvents: [PlayEvent] = []
    private var fakeEvents: [PlayEvent] = []
    private var fakeEnabled: Bool { DeveloperExperiments.fakeListeningStats }
    private var realGeneration: UInt64 = 0
    private var fakeGeneration: UInt64 = 0
    private var initialLoadFinished = false
    private var realClearedBeforeInitialLoad = false
    private var persistedBytes = 0
    private var fakePersistedBytes = 0

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Volta", isDirectory: true)
        let fileURL = support.appendingPathComponent("play_events.json")
        let fakeFileURL = support.appendingPathComponent("play_events_fake.json")
        let persistence = StatsPersistence(fileURL: fileURL, fakeFileURL: fakeFileURL)
        self.persistence = persistence
        Task.detached(priority: .utility) { [weak self, persistence] in
            let loaded = await persistence.load(fakeEnabled: self?.fakeEnabled ?? false)
            guard let self else { return }
            self.lock.withLock {
                if self.realGeneration == 0 {
                    self.realEvents = loaded.realEvents
                } else if self.realClearedBeforeInitialLoad {
                    // A clear issued before disk loading must not resurrect
                    // the old file. Keep any events recorded after the clear.
                } else {
                    var merged = Dictionary(uniqueKeysWithValues: loaded.realEvents.map { ($0.id, $0) })
                    for event in self.realEvents { merged[event.id] = event }
                    self.realEvents = merged.values.sorted { $0.timestamp < $1.timestamp }
                }
                if self.fakeGeneration == 0 {
                    self.fakeEvents = loaded.fakeEvents
                }
                self.initialLoadFinished = true
                self.persistedBytes = loaded.realBytes
                self.fakePersistedBytes = loaded.fakeBytes
            }
            if loaded.duration >= 0.1 {
                AppLogger.shared.log(
                    "Stats load took \(String(format: "%.0f", loaded.duration * 1_000))ms; events=\(loaded.realEvents.count); fakeEvents=\(loaded.fakeEvents.count); bytes=\(loaded.realBytes)",
                    category: .library,
                    level: .warning
                )
            }
            WidgetSnapshotManager.refreshListening()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .playEventRecorded, object: nil)
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.flush()
        }
    }

    func flush() {
        let snapshot = lock.withLock { (events: realEvents, generation: realGeneration) }
        scheduleRealSave(snapshot.events, generation: snapshot.generation)
    }

    func record(_ event: PlayEvent) {
        let snapshot = lock.withLock { () -> (events: [PlayEvent], generation: UInt64) in
            realEvents.append(event)
            realGeneration &+= 1
            return (realEvents, realGeneration)
        }
        scheduleRealSave(snapshot.events, generation: snapshot.generation)
        refreshWidgetInBackground()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .playEventRecorded, object: nil)
        }
    }

    // MARK: - Fake stats (screenshot mode)

    func setFakeStats(_ enabled: Bool, songPool: [Song]) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            if enabled {
                let events = FakeStatsGenerator.generate(pool: songPool)
                let generation = self.lock.withLock { () -> UInt64 in
                    self.fakeEvents = events
                    self.fakeGeneration &+= 1
                    return self.fakeGeneration
                }
                self.scheduleFakeSave(events, generation: generation)
            } else {
                let generation = self.lock.withLock { () -> UInt64 in
                    self.fakeEvents.removeAll()
                    self.fakeGeneration &+= 1
                    return self.fakeGeneration
                }
                self.scheduleFakeRemoval(generation: generation)
            }
            self.refreshWidgetInBackground()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .playEventRecorded, object: nil)
            }
        }
    }

    // MARK: - Read (in-memory snapshots only)

    func allEvents() -> [PlayEvent] {
        lock.withLock { fakeEnabled ? fakeEvents : realEvents }
    }

    func storageSizeBytes() -> Int {
        lock.withLock { fakeEnabled ? fakePersistedBytes : persistedBytes }
    }

    func clearAll() {
        let action = lock.withLock { () -> (real: [PlayEvent]?, realGeneration: UInt64, fakeGeneration: UInt64) in
            if fakeEnabled {
                fakeEvents.removeAll()
                fakeGeneration &+= 1
                return (nil, realGeneration, fakeGeneration)
            }
            realEvents.removeAll()
            realGeneration &+= 1
            if !initialLoadFinished { realClearedBeforeInitialLoad = true }
            return (realEvents, realGeneration, fakeGeneration)
        }
        if let real = action.real {
            scheduleRealSave(real, generation: action.realGeneration)
        } else {
            scheduleFakeRemoval(generation: action.fakeGeneration)
        }
        refreshWidgetInBackground()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .playEventRecorded, object: nil)
        }
    }

    func events(from start: Date, to end: Date) -> [PlayEvent] {
        allEvents().filter { $0.timestamp >= start && $0.timestamp <= end }
    }

    private func scheduleRealSave(_ events: [PlayEvent], generation requestedGeneration: UInt64? = nil) {
        let generation = requestedGeneration ?? lock.withLock { realGeneration }
        let persistence = self.persistence
        Task.detached(priority: .utility) { [weak self, persistence] in
            guard let result = await persistence.saveReal(events, generation: generation) else { return }
            guard let self else { return }
            self.lock.withLock { self.persistedBytes = result.bytes }
            self.logSlowSave(result, operation: "Stats persistence", count: events.count)
        }
    }

    private func scheduleFakeSave(_ events: [PlayEvent], generation: UInt64) {
        let persistence = self.persistence
        Task.detached(priority: .utility) { [weak self, persistence] in
            guard let result = await persistence.saveFake(events, generation: generation) else { return }
            guard let self else { return }
            self.lock.withLock { self.fakePersistedBytes = result.bytes }
            self.logSlowSave(result, operation: "Fake stats persistence", count: events.count)
        }
    }

    private func scheduleFakeRemoval(generation: UInt64) {
        let persistence = self.persistence
        Task.detached(priority: .utility) { [weak self, persistence] in
            guard let result = await persistence.removeFake(generation: generation) else { return }
            guard let self else { return }
            self.lock.withLock { self.fakePersistedBytes = 0 }
            self.logSlowSave(result, operation: "Fake stats removal", count: 0)
        }
    }

    private func refreshWidgetInBackground() {
        WidgetSnapshotManager.refreshListening()
    }

    private func logSlowSave(_ result: StatsWriteResult, operation: String, count: Int) {
        guard result.duration >= 0.1 else { return }
        AppLogger.shared.log(
            "\(operation) took \(String(format: "%.0f", result.duration * 1_000))ms; events=\(count); bytes=\(result.bytes); success=\(result.succeeded)",
            category: .library,
            level: result.succeeded ? .info : .warning
        )
    }
}
