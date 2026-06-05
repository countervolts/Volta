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
        artist = song.artist ?? "Unknown Artist"
        album = song.album ?? "Unknown Album"
        albumID = song.albumId
        artistID = song.artistId
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
    private var events: [PlayEvent] = []
    private let queue = DispatchQueue(label: "stats-store", qos: .utility)

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Volta", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent("play_events.json")
        load()
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
                                               object: nil, queue: nil) { [weak self] _ in
            self?.flush()
        }
    }

    func flush() {
        queue.sync { [weak self] in self?.save() }
    }

    // MARK: - Write

    func record(_ event: PlayEvent) {
        queue.async { [weak self] in
            guard let self else { return }
            self.events.append(event)
            self.save()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .playEventRecorded, object: nil)
            }
        }
    }

    // MARK: - Read (synchronous snapshots for use on background threads)

    func allEvents() -> [PlayEvent] {
        queue.sync { events }
    }

    func storageSizeBytes() -> Int {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        return attrs?[.size] as? Int ?? 0
    }

    func events(from start: Date, to end: Date) -> [PlayEvent] {
        queue.sync { events.filter { $0.timestamp >= start && $0.timestamp <= end } }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([PlayEvent].self, from: data) else { return }
        events = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
