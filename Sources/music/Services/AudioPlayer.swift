import Foundation
import AVFoundation
import MediaPlayer
import Observation
import UIKit

enum RepeatMode: Sendable { case off, one, all }
enum AutoplayMode: Sendable { case off, random, algorithm }

@MainActor
@Observable
final class AudioPlayer {
    // current track state
    private(set) var currentSong: Song?
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var currentArtwork: UIImage?

    // queue
    private(set) var queue: [Song] = []
    private(set) var currentIndex: Int = 0
    private(set) var queueSourceTitle: String = ""
    private(set) var queueSourceAlbum: Album?
    private(set) var queueSourcePlaylist: Playlist?

    // modes
    private(set) var isShuffle = false
    private(set) var repeatMode: RepeatMode = .off
    private(set) var autoplayMode: AutoplayMode = .off
    private(set) var isCrossfade = false

    // legacy shim used by SettingsView toggle
    var isAutoplay: Bool {
        get { autoplayMode != .off }
        set { autoplayMode = newValue ? .random : .off }
    }

    // starred IDs tracked locally (toggled optimistically)
    private(set) var starredIDs: Set<String> = []

    private let player = AVQueuePlayer()
    private var client: SubsonicClient?
    private var timeObserverToken: Any?
    private var shuffledOrder: [Int] = []
    private var loggedSongIDs: Set<String> = []

    private var gaplessNextItem: AVPlayerItem? = nil   // pre-buffered for weak mode

    init() {
        configureAudioSession()
        configureRemoteCommands()
        addTimeObserver()
        addEndObserver()
    }

    func updateClient(_ client: SubsonicClient?) {
        self.client = client
        DownloadService.shared.updateClient(client)
    }

    // MARK: - Playback entry points

    func playQueue(_ songs: [Song], startIndex: Int = 0, source: String = "", album: Album? = nil, playlist: Playlist? = nil) {
        gaplessNextItem = nil
        queue = songs
        queueSourceTitle = source
        queueSourceAlbum = album
        queueSourcePlaylist = playlist
        shuffledOrder = Array(songs.indices)
        if isShuffle { shuffledOrder.shuffle() }
        currentIndex = startIndex
        playCurrent()
    }

    func play(song: Song) {
        playQueue([song], startIndex: 0, source: song.album ?? "")
    }

    func skipNext() {
        AppLogger.shared.log("⏭ Skip next (idx \(currentIndex) → \(currentIndex + 1))", category: .playback)
        switch repeatMode {
        case .one:
            seek(to: 0)
            player.play()
        case .all:
            currentIndex = (currentIndex + 1) % queue.count
            playCurrent()
        case .off:
            if currentIndex < queue.count - 1 {
                currentIndex += 1
                playCurrent()
            } else if autoplayMode != .off {
                Task { await appendAutoplaySongs() }
            } else {
                player.pause()
                isPlaying = false
                currentTime = 0
                seek(to: 0)
            }
        }
    }

    func skipPrevious() {
        AppLogger.shared.log("⏮ Skip previous (idx \(currentIndex))", category: .playback)
        if currentTime > 3 {
            seek(to: 0)
            if isPlaying { player.play() }
        } else if currentIndex > 0 {
            currentIndex -= 1
            playCurrent()
        } else {
            seek(to: 0)
        }
    }

    func skipTo(index: Int) {
        guard index >= 0, index < queue.count else { return }
        currentIndex = index
        playCurrent()
    }

    func togglePlayPause() {
        guard currentSong != nil else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
        AppLogger.shared.log(isPlaying ? "▶ Resume" : "⏸ Pause", category: .playback)
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func seek(to time: TimeInterval) {
        let target = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
        updateNowPlayingTime()
    }

    // MARK: - Queue manipulation

    func moveQueueItem(from source: IndexSet, to dest: Int) {
        queue.move(fromOffsets: source, toOffset: dest)
        // keep currentIndex pointing at the same song after reorder
        if let moved = source.first {
            if moved == currentIndex {
                currentIndex = dest > moved ? dest - 1 : dest
            } else if moved < currentIndex, dest > currentIndex {
                currentIndex -= 1
            } else if moved > currentIndex, dest <= currentIndex {
                currentIndex += 1
            }
        }
    }

    func playNext(_ song: Song) {
        guard !queue.isEmpty else { play(song: song); return }
        queue.insert(song, at: currentIndex + 1)
    }

    func addToQueue(_ song: Song) {
        guard !queue.isEmpty else { play(song: song); return }
        queue.append(song)
    }

    func removeQueueItem(at index: Int) {
        guard index >= 0, index < queue.count else { return }
        queue.remove(at: index)
        if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex {
            if currentIndex >= queue.count { currentIndex = max(0, queue.count - 1) }
            if !queue.isEmpty { playCurrent() }
        }
    }

    // MARK: - Modes

    func toggleShuffle() {
        isShuffle.toggle()
        if isShuffle {
            shuffledOrder = Array(queue.indices)
            shuffledOrder.shuffle()
        }
    }

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    func cycleAutoplay() {
        switch autoplayMode {
        case .off:       autoplayMode = .random
        case .random:    autoplayMode = .algorithm
        case .algorithm: autoplayMode = .off
        }
    }
    func toggleAutoplay() { isAutoplay.toggle() }
    func toggleCrossfade() { isCrossfade.toggle() }

    // MARK: - Starred

    func toggleStar(songID: String) {
        if starredIDs.contains(songID) {
            starredIDs.remove(songID)
            Task { try? await client?.unstar(id: songID) }
        } else {
            starredIDs.insert(songID)
            Task { try? await client?.star(id: songID) }
        }
    }

    func isStarred(_ songID: String) -> Bool { starredIDs.contains(songID) }

    // MARK: - Autoplay

    private func appendAutoplaySongs() async {
        guard let client else { return }
        var songs: [Song] = []
        if autoplayMode == .algorithm, let current = currentSong {
            // algorithm mode: songs from similar artists / same genre
            if let artistId = current.artistId,
               let info = try? await client.artistInfo(id: artistId),
               let similar = info.similarArtist?.prefix(3), !similar.isEmpty {
                let picked = Array(similar).randomElement()
                if let s = picked, let topSongs = try? await client.topSongs(artistName: s.name, count: 10) {
                    songs = topSongs
                }
            }
            // fallback to random if algorithm couldn't find songs
            if songs.isEmpty {
                songs = (try? await client.randomSongs(size: 20)) ?? []
            }
        } else {
            songs = (try? await client.randomSongs(size: 20)) ?? []
        }
        guard !songs.isEmpty else { return }
        // deduplicate against existing queue
        let existingIDs = Set(queue.map(\.id))
        let fresh = songs.filter { !existingIDs.contains($0.id) }
        guard !fresh.isEmpty else { return }
        queue.append(contentsOf: fresh)
        currentIndex += 1
        playCurrent()
    }

    // MARK: - Private

    private func playCurrent() {
        guard !queue.isEmpty, currentIndex < queue.count else { return }
        let song = queue[currentIndex]
        startPlaying(song: song)
    }

    private func startPlaying(song: Song) {
        let localURL = DownloadService.shared.localURL(for: song)
        let streamURL = localURL ?? client?.streamURL(id: song.id)
        guard let url = streamURL else {
            AppLogger.shared.log("✗ No stream URL for '\(song.title)'", category: .playback, level: .error)
            return
        }
        let src = localURL != nil ? "local" : "stream"
        AppLogger.shared.log("▶ '\(song.title)' by \(song.artist ?? "?") [\(src)]", category: .playback)

        let gapless = UserDefaults.standard.string(forKey: "gaplessPlayback") ?? "off"

        // Check if we pre-buffered this exact song (weak mode)
        let item: AVPlayerItem
        if gapless != "off",
           let preloaded = gaplessNextItem,
           let preloadedURL = (preloaded.asset as? AVURLAsset)?.url,
           preloadedURL == url {
            item = preloaded
            gaplessNextItem = nil
        } else {
            item = AVPlayerItem(url: url)
        }

        // For gapless "on": use AVQueuePlayer's insert so transition is seamless
        if gapless == "on" {
            player.removeAllItems()
            player.insert(item, after: nil)
        } else {
            player.replaceCurrentItem(with: item)
        }
        player.play()
        currentSong = song
        isPlaying = true
        currentTime = 0
        duration = 0
        currentArtwork = nil
        loggedSongIDs.remove(song.id)   // allow re-logging if replayed

        // starred state from server's starred field
        if song.starred != nil {
            starredIDs.insert(song.id)
        }

        updateNowPlaying()
        Task { await loadArtwork(for: song) }
        Task { await loadDuration(from: item) }
        scheduleGaplessPreload()
    }

    private func scheduleGaplessPreload() {
        let gapless = UserDefaults.standard.string(forKey: "gaplessPlayback") ?? "off"
        guard gapless != "off" else { gaplessNextItem = nil; return }
        let nextIndex = currentIndex + 1
        guard nextIndex < queue.count else { gaplessNextItem = nil; return }
        let nextSong = queue[nextIndex]
        let localURL = DownloadService.shared.localURL(for: nextSong)
        guard let url = localURL ?? client?.streamURL(id: nextSong.id) else { return }
        let nextItem = AVPlayerItem(url: url)
        gaplessNextItem = nextItem
        // For "on" mode: actually insert into AVQueuePlayer queue for seamless transition
        if gapless == "on" {
            player.insert(nextItem, after: player.currentItem)
        }
        AppLogger.shared.log("⏭ Gapless pre-buffer: '\(nextSong.title)' [mode=\(gapless)]", category: .playback)
    }

    private func loadArtwork(for song: Song) async {
        let url = client?.coverArtURL(id: song.coverArt, size: 600)
        let image = await ArtworkLoader.shared.image(for: url)
        guard currentSong?.id == song.id else { return }
        currentArtwork = image
        if let image {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    private func loadDuration(from item: AVPlayerItem) async {
        // poll until duration becomes available
        for _ in 0..<30 {
            let d = item.duration
            if d.isNumeric, d.seconds > 0 {
                duration = d.seconds
                updateNowPlayingTime()
                return
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    private func addTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.currentTime = time.seconds
                self.checkLogPlay()
            }
        }
    }

    private func checkLogPlay() {
        guard let song = currentSong,
              duration > 0,
              !loggedSongIDs.contains(song.id) else { return }
        // log when half listened or completed
        let threshold = min(duration * 0.5, Double(song.duration ?? Int(duration)) * 0.5)
        if currentTime >= threshold {
            loggedSongIDs.insert(song.id)
            let event = PlayEvent(song: song)
            StatsStore.shared.record(event)
            AppLogger.shared.log("✓ Logged play: '\(song.title)' at \(Int(currentTime))s / \(Int(duration))s", category: .playback)
        }
    }

    private func addEndObserver() {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let gapless = UserDefaults.standard.string(forKey: "gaplessPlayback") ?? "off"
                // For "on" mode, AVQueuePlayer already advanced to the pre-queued item.
                // Update our index + state without replacing the current item.
                if gapless == "on",
                   self.repeatMode == .off,
                   self.currentIndex + 1 < self.queue.count {
                    self.currentIndex += 1
                    let song = self.queue[self.currentIndex]
                    self.currentSong = song
                    self.currentTime = 0
                    self.duration = 0
                    self.currentArtwork = nil
                    self.loggedSongIDs.remove(song.id)
                    if song.starred != nil { self.starredIDs.insert(song.id) }
                    self.updateNowPlaying()
                    Task { await self.loadArtwork(for: song) }
                    if let item = self.player.currentItem {
                        Task { await self.loadDuration(from: item) }
                    }
                    self.scheduleGaplessPreload()
                } else {
                    self.skipNext()
                }
            }
        }
    }

    // MARK: - Audio session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    // MARK: - Remote commands

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }; return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }; return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }; return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipNext() }; return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipPrevious() }; return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let e = event as? MPChangePlaybackPositionCommandEvent {
                Task { @MainActor in self?.seek(to: e.positionTime) }
            }
            return .success
        }
    }

    private func resume() {
        guard currentSong != nil, !isPlaying else { return }
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    // MARK: - Now Playing

    private func updateNowPlaying() {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist ?? "",
            MPMediaItemPropertyAlbumTitle: song.album ?? "",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
        ]
        if let dur = song.duration { info[MPMediaItemPropertyPlaybackDuration] = Double(dur) }
        if let artwork = currentArtwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingTime() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
