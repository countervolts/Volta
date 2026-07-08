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

// persists play events as a flat JSON array.
// append-only during normal use; compaction can prune very old events.
final class StatsStore {
    static let shared = StatsStore()

    private let fileURL: URL
    private let fakeFileURL: URL
    // The user's real, never-falsified play history.
    private var realEvents: [PlayEvent] = []
    // A generated screenshot dataset, only consulted while the experiment is on.
    private var fakeEvents: [PlayEvent] = []
    private let queue = DeveloperExperiments.queue(label: "stats-store", qos: .utility)

    private var fakeEnabled: Bool { DeveloperExperiments.fakeListeningStats }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Volta", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent("play_events.json")
        fakeFileURL = support.appendingPathComponent("play_events_fake.json")
        load()
        if fakeEnabled { loadFake() }
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
                                               object: nil, queue: nil) { [weak self] _ in
            self?.flush()
        }
    }

    func flush() {
        // Only the real history mutates during normal use, so that is all we persist here.
        syncOnStore { [weak self] in self?.saveReal() }
    }

    // MARK: - Write

    func record(_ event: PlayEvent) {
        // Always record to the real history, even while faking, so toggling the
        // experiment off restores an accurate, intact dataset.
        asyncOnStore { [weak self] in
            guard let self else { return }
            self.realEvents.append(event)
            self.saveReal()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .playEventRecorded, object: nil)
            }
        }
    }

    // MARK: - Fake stats (screenshot mode)

    // Enable/disable the falsified dataset. Real data is never touched.
    func setFakeStats(_ enabled: Bool, songPool: [Song]) {
        asyncOnStore { [weak self] in
            guard let self else { return }
            if enabled {
                let events = FakeStatsGenerator.generate(pool: songPool)
                self.fakeEvents = events
                if let data = try? JSONEncoder().encode(events) {
                    try? data.write(to: self.fakeFileURL, options: .atomic)
                }
            } else {
                self.fakeEvents = []
                try? FileManager.default.removeItem(at: self.fakeFileURL)
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .playEventRecorded, object: nil)
            }
        }
    }

    // MARK: - Read (synchronous snapshots for use on background threads)

    func allEvents() -> [PlayEvent] {
        syncOnStore { fakeEnabled ? fakeEvents : realEvents }
    }

    func storageSizeBytes() -> Int {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        return attrs?[.size] as? Int ?? 0
    }

    func clearAll() {
        // While faking, "clear" only drops the fake dataset — the real history is protected.
        syncOnStore {
            if fakeEnabled {
                fakeEvents.removeAll()
                try? FileManager.default.removeItem(at: fakeFileURL)
            } else {
                realEvents.removeAll()
                saveReal()
            }
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .playEventRecorded, object: nil)
        }
    }

    func events(from start: Date, to end: Date) -> [PlayEvent] {
        syncOnStore {
            let source = fakeEnabled ? fakeEvents : realEvents
            return source.filter { $0.timestamp >= start && $0.timestamp <= end }
        }
    }

    // MARK: - Persistence

    private func syncOnStore<T>(_ operation: () -> T) -> T {
        return queue.sync(execute: operation)
    }

    private func asyncOnStore(_ operation: @escaping () -> Void) {
        queue.async(execute: operation)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([PlayEvent].self, from: data) else { return }
        realEvents = decoded
    }

    private func loadFake() {
        guard let data = try? Data(contentsOf: fakeFileURL),
              let decoded = try? JSONDecoder().decode([PlayEvent].self, from: data) else { return }
        fakeEvents = decoded
    }

    private func saveReal() {
        guard let data = try? JSONEncoder().encode(realEvents) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
