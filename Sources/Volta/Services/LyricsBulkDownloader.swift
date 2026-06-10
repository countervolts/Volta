import Foundation
import Combine

// Downloads lyrics for the whole library with bounded concurrency (~12 in flight)
// and publishes progress for a settings UI. Songs that already have lyrics on
// device resolve from disk and don't hit the network.
@MainActor
final class LyricsBulkDownloader: ObservableObject {
    static let shared = LyricsBulkDownloader()

    @Published private(set) var isRunning = false
    @Published private(set) var total = 0
    @Published private(set) var completed = 0
    @Published private(set) var found = 0
    @Published private(set) var skipped = 0
    @Published private(set) var statusText = "Idle"

    private var task: Task<Void, Never>?
    private static let maxConcurrent = 12

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(completed) / Double(total))
    }

    func start(client: SubsonicClient) {
        guard !isRunning else { return }
        isRunning = true
        completed = 0; found = 0; total = 0; skipped = 0
        statusText = "Scanning library…"
        task = Task { await run(client: client) }
    }

    func cancel() {
        task?.cancel()
    }

    private func run(client: SubsonicClient) async {
        let songs = await Self.allSongs(client: client)
        if Task.isCancelled { finish(cancelled: true); return }

        // only fetch songs that don't already have lyrics on device, so re-running
        // (or adding songs to the server) only downloads what's missing
        statusText = "Checking existing lyrics…"
        let pending = await LyricsService.shared.songsMissingLyrics(songs)
        if Task.isCancelled { finish(cancelled: true); return }
        skipped = songs.count - pending.count
        total = pending.count
        guard total > 0 else {
            isRunning = false
            task = nil
            statusText = songs.isEmpty
                ? "No songs found"
                : "All \(songs.count) songs already have lyrics"
            VoltaNotificationCenter.shared.post("Lyrics already up to date", tone: .success)
            return
        }
        statusText = "Downloading \(total) missing…"

        await withTaskGroup(of: Bool.self) { group in
            var iterator = pending.makeIterator()
            for _ in 0..<Self.maxConcurrent {
                guard let song = iterator.next() else { break }
                group.addTask { await Self.fetch(song, client: client) }
            }
            while let hadLyrics = await group.next() {
                completed += 1
                if hadLyrics { found += 1 }
                statusText = "Downloading missing… \(completed)/\(total)"
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                if let song = iterator.next() {
                    group.addTask { await Self.fetch(song, client: client) }
                }
            }
        }
        finish(cancelled: Task.isCancelled)
    }

    private func finish(cancelled: Bool) {
        isRunning = false
        task = nil
        let skippedNote = skipped > 0 ? " · \(skipped) already had lyrics" : ""
        statusText = cancelled
            ? "Stopped · added \(found)\(skippedNote)"
            : "Done · added \(found) of \(total)\(skippedNote)"
        VoltaNotificationCenter.shared.post(
            cancelled ? "Lyrics download stopped" : "Lyrics download complete",
            tone: cancelled ? .warning : .success
        )
    }

    // fetch (and persist) lyrics for one song; true when any were found
    private nonisolated static func fetch(_ song: Song, client: SubsonicClient) async -> Bool {
        let lines = await LyricsService.shared.lyrics(for: song, client: client)
        return !lines.isEmpty
    }

    // walks all albums and collects their unique songs
    private nonisolated static func allSongs(client: SubsonicClient) async -> [Song] {
        var albums: [Album] = []
        var offset = 0
        while true {
            let batch = (try? await client.allAlbums(size: 500, offset: offset)) ?? []
            albums.append(contentsOf: batch)
            if batch.count < 500 { break }
            offset += 500
            if offset > 50_000 || Task.isCancelled { break }
        }

        var songs: [Song] = []
        var seen = Set<String>()
        var index = 0
        let batchSize = 12
        while index < albums.count {
            if Task.isCancelled { break }
            let slice = Array(albums[index..<min(index + batchSize, albums.count)])
            let results = await withTaskGroup(of: [Song].self) { group in
                for album in slice {
                    group.addTask { (try? await client.album(id: album.id))?.song ?? album.song ?? [] }
                }
                var acc: [Song] = []
                for await s in group { acc.append(contentsOf: s) }
                return acc
            }
            for s in results where seen.insert(s.id).inserted { songs.append(s) }
            index += batchSize
        }
        return songs
    }
}
