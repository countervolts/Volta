import Foundation
import Combine

enum CompanionLyricsPhase: String, Sendable {
    case queued
    case downloading
    case saved
    case unavailable
}

struct CompanionLyricsTransfer: Identifiable, Sendable, Equatable {
    let id: String
    let song: Song
    var phase: CompanionLyricsPhase
    let source: LyricsDownloadSource
}

private struct QueuedCompanionLyrics {
    let song: Song
    let client: any MusicService
    let source: LyricsDownloadSource
}

// Downloads lyrics for the whole library with bounded concurrency (~12 in flight)
// and publishes progress for a settings UI. Songs that already have lyrics on
// device resolve from disk and don't hit the network.
@MainActor
final class LyricsBulkDownloader: ObservableObject {
    static let shared = LyricsBulkDownloader()
    static let downloadWithSongsKey = "downloadLyricsWithSongs"

    @Published private(set) var isRunning = false
    @Published private(set) var total = 0
    @Published private(set) var completed = 0
    @Published private(set) var found = 0
    @Published private(set) var skipped = 0
    @Published private(set) var statusText = "Idle"
    @Published private(set) var companionTransfers: [CompanionLyricsTransfer] = []
    @Published private(set) var revision = 0

    private var task: Task<Void, Never>?
    private var companionQueue: [QueuedCompanionLyrics] = []
    private var companionTasks: [String: Task<Void, Never>] = [:]
    private var companionItems: [String: CompanionLyricsTransfer] = [:]
    private var companionOrder: [String] = []
    private static let maxConcurrent = 12
    private static let maxCompanionConcurrent = 4

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(completed) / Double(total))
    }

    func start(client: any MusicService, source: LyricsDownloadSource) {
        guard !isRunning else { return }
        // Demo servers are stream-only; don't bulk-pull their lyrics to disk.
        if DemoServers.isDemo(client.config.baseURL) {
            VoltaNotificationCenter.shared.post(L(.notif_demo_no_downloads), tone: .info)
            return
        }
        isRunning = true
        completed = 0; found = 0; total = 0; skipped = 0
        statusText = "Scanning library for \(source.displayName)…"
        task = Task { await run(client: client, source: source) }
    }

    func cancel() {
        task?.cancel()
    }

    func enqueueCompanionLyrics(
        for song: Song,
        client: any MusicService,
        source: LyricsDownloadSource
    ) {
        guard !DemoServers.isDemo(client.config.baseURL),
              companionItems[song.id] == nil else { return }
        companionItems[song.id] = CompanionLyricsTransfer(
            id: song.id,
            song: song,
            phase: .queued,
            source: source
        )
        companionOrder.append(song.id)
        companionQueue.append(QueuedCompanionLyrics(song: song, client: client, source: source))
        publishCompanionTransfers()
        pumpCompanionLyrics()
    }

    func cancelCompanionLyrics(for songID: String) {
        companionQueue.removeAll { $0.song.id == songID }
        companionTasks.removeValue(forKey: songID)?.cancel()
        companionItems.removeValue(forKey: songID)
        companionOrder.removeAll { $0 == songID }
        publishCompanionTransfers()
        pumpCompanionLyrics()
    }

    private func pumpCompanionLyrics() {
        while companionTasks.count < Self.maxCompanionConcurrent, !companionQueue.isEmpty {
            let request = companionQueue.removeFirst()
            let songID = request.song.id
            guard var transfer = companionItems[songID] else { continue }
            transfer.phase = .downloading
            companionItems[songID] = transfer
            publishCompanionTransfers()

            companionTasks[songID] = Task { @MainActor [weak self] in
                let alreadySaved = await LyricsService.shared.hasLocalLyrics(for: songID)
                let saved: Bool
                if alreadySaved {
                    saved = true
                } else {
                    let lines = await LyricsService.shared.lyrics(
                        for: request.song,
                        client: request.client,
                        forceSave: true,
                        downloadSource: request.source
                    )
                    saved = !lines.isEmpty
                }
                guard !Task.isCancelled else { return }
                self?.finishCompanionLyrics(songID: songID, saved: saved)
            }
        }
    }

    private func finishCompanionLyrics(songID: String, saved: Bool) {
        companionTasks.removeValue(forKey: songID)
        guard var transfer = companionItems[songID] else {
            pumpCompanionLyrics()
            return
        }
        transfer.phase = saved ? .saved : .unavailable
        companionItems[songID] = transfer
        revision &+= 1
        publishCompanionTransfers()
        pumpCompanionLyrics()

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self,
                  let phase = self.companionItems[songID]?.phase,
                  phase == .saved || phase == .unavailable else { return }
            self.companionItems.removeValue(forKey: songID)
            self.companionOrder.removeAll { $0 == songID }
            self.publishCompanionTransfers()
        }
    }

    private func publishCompanionTransfers() {
        companionTransfers = companionOrder.compactMap { companionItems[$0] }
    }

    private func run(client: any MusicService, source: LyricsDownloadSource) async {
        let songs = await Self.allSongs(client: client)
        if Task.isCancelled { finish(cancelled: true); return }

        // only fetch songs that don't already have lyrics on device, so re-running
        // (or adding songs to the server) only downloads what's missing
        statusText = "Checking existing \(source.displayName) lyrics…"
        let pending = await LyricsService.shared.songsMissingLyrics(songs, source: source)
        if Task.isCancelled { finish(cancelled: true); return }
        skipped = songs.count - pending.count
        total = pending.count
        guard total > 0 else {
            isRunning = false
            task = nil
            statusText = songs.isEmpty
                ? "No songs found"
                : "All \(songs.count) songs already have lyrics"
            VoltaNotificationCenter.shared.post(L(.notif_lyrics_up_to_date), tone: .success)
            return
        }
        statusText = "Downloading \(total) from \(source.displayName)…"

        await withTaskGroup(of: Bool.self) { group in
            var iterator = pending.makeIterator()
            let maxConcurrent = DeveloperExperiments.constrainedConcurrency(default: Self.maxConcurrent)
            for _ in 0..<maxConcurrent {
                guard let song = iterator.next() else { break }
                group.addTask { await Self.fetch(song, client: client, source: source) }
            }
            while let hadLyrics = await group.next() {
                completed += 1
                if hadLyrics { found += 1 }
                statusText = "Downloading from \(source.displayName)… \(completed)/\(total)"
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                if let song = iterator.next() {
                    group.addTask { await Self.fetch(song, client: client, source: source) }
                }
            }
        }
        finish(cancelled: Task.isCancelled)
    }

    private func finish(cancelled: Bool) {
        isRunning = false
        task = nil
        revision &+= 1
        let skippedNote = skipped > 0 ? " · \(skipped) already had lyrics" : ""
        statusText = cancelled
            ? "Stopped · added \(found)\(skippedNote)"
            : "Done · added \(found) of \(total)\(skippedNote)"
        VoltaNotificationCenter.shared.post(
            cancelled ? L(.notif_lyrics_download_stopped) : L(.notif_lyrics_download_complete),
            tone: cancelled ? .warning : .success
        )
    }

    // fetch (and persist) lyrics for one song; true when any were found
    private nonisolated static func fetch(
        _ song: Song,
        client: any MusicService,
        source: LyricsDownloadSource
    ) async -> Bool {
        // The explicit Download All action persists even if the automatic
        // "Save Lyrics Locally" toggle is off.
        let lines = await LyricsService.shared.lyrics(
            for: song,
            client: client,
            forceSave: true,
            downloadSource: source
        )
        return !lines.isEmpty
    }

    // walks all albums and collects their unique songs
    private nonisolated static func allSongs(client: any MusicService) async -> [Song] {
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
            let batches = await DeveloperExperiments.runConcurrently(slice, defaultMaxConcurrent: batchSize) { album in
                (try? await client.album(id: album.id))?.song ?? album.song ?? []
            }
            let results = batches.flatMap { $0 }
            for s in results where seen.insert(s.id).inserted { songs.append(s) }
            index += batchSize
        }
        return songs
    }
}
