import Foundation
import AVFoundation
import MediaPlayer
import Observation
import UIKit

enum RepeatMode: Sendable { case off, one, all }
enum AutoplayMode: Sendable { case off, random, algorithm }
enum PlaybackTransitionMode: String, CaseIterable, Identifiable, Sendable {
    case off
    case crossfade
    case automix

    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: "Crossfade"
        case .crossfade: "Crossfade"
        case .automix: "AutoMix"
        }
    }
    var settingsLabel: String {
        switch self {
        case .off: "Off"
        case .crossfade: "Crossfade"
        case .automix: "AutoMix"
        }
    }
    var icon: String {
        switch self {
        case .off, .crossfade: "arrow.left.arrow.right"
        case .automix: "waveform.path"
        }
    }
}

private struct PlaybackTransitionPlan: Sendable {
    let mode: PlaybackTransitionMode
    let duration: TimeInterval
    let startLead: TimeInterval
    let nextStart: TimeInterval
    let reason: String

    static func fallback(mode: PlaybackTransitionMode, current: Song, next: Song) -> PlaybackTransitionPlan {
        let sameAlbum = current.albumId != nil && current.albumId == next.albumId
        let sameArtist = current.artistId != nil && current.artistId == next.artistId
        let sameGenre = current.genre != nil && current.genre?.caseInsensitiveCompare(next.genre ?? "") == .orderedSame
        switch mode {
        case .off:
            return PlaybackTransitionPlan(mode: mode, duration: 0, startLead: 0, nextStart: 0, reason: "off")
        case .crossfade:
            let duration = sameAlbum ? 3.0 : 6.0
            return PlaybackTransitionPlan(mode: mode, duration: duration, startLead: duration, nextStart: 0, reason: "fixed")
        case .automix:
            let duration: TimeInterval
            if sameAlbum {
                duration = 4.0
            } else if sameArtist || sameGenre {
                duration = 11.0
            } else {
                duration = 8.0
            }
            return PlaybackTransitionPlan(mode: mode, duration: duration, startLead: duration, nextStart: 0, reason: "metadata")
        }
    }
}

private struct AudioSilenceProfile: Sendable {
    var leadingSilence: TimeInterval
    var trailingSilence: TimeInterval

    static let zero = AudioSilenceProfile(leadingSilence: 0, trailingSilence: 0)
}

@MainActor
@Observable
final class AudioPlayer {
    // current track state
    private(set) var currentSong: Song?
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var currentArtwork: UIImage?
    // animated ("live") cover art when the artwork is a multi-frame image; nil
    // otherwise. Only the full player consumes this — the lock screen and miniplayer
    // keep using the still currentArtwork.
    private(set) var currentAnimatedArtwork: UIImage?
    private var currentLiveArtwork: LiveArtworkAsset?

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
    private(set) var transitionMode: PlaybackTransitionMode = .off
    var isCrossfade: Bool { transitionMode != .off }

    // legacy shim used by SettingsView toggle
    var isAutoplay: Bool {
        get { autoplayMode != .off }
        set {
            autoplayMode = newValue ? .random : .off
            ensureAutoplayPreloadedIfNeeded()
        }
    }

    // starred IDs tracked locally (toggled optimistically)
    private(set) var starredIDs: Set<String> = []

    private let primaryPlayer = AVQueuePlayer()
    private let secondaryPlayer = AVQueuePlayer()
    private var activePlayer: AVQueuePlayer
    private var player: AVQueuePlayer { activePlayer }
    private var inactivePlayer: AVQueuePlayer {
        activePlayer === primaryPlayer ? secondaryPlayer : primaryPlayer
    }
    private var client: SubsonicClient?
    private var primaryTimeObserverToken: Any?
    private var secondaryTimeObserverToken: Any?
    private var shuffledOrder: [Int] = []
    private var loggedSongIDs: Set<String> = []
    private var targetVolume: Float = 1.0
    private var transitionTask: Task<Void, Never>?
    private var transitionPlanTask: Task<Void, Never>?
    private var transitionPlanKey: String?
    private var preparedTransitionPlan: PlaybackTransitionPlan?
    private var isTransitioning = false

    private var gaplessNextItem: AVPlayerItem? = nil   // pre-buffered for weak mode
    private var autoplayAppendTask: Task<Void, Never>?
    private let autoplayPreloadThreshold = 1

    // when set, autoplay keeps pulling more songs from this artist (artist-profile play button)
    private(set) var autoplayArtistName: String?
    private(set) var autoplayArtistId: String?

    // sleep timer
    private(set) var sleepTimerActive = false
    private(set) var sleepEndsAtTrackEnd = false
    private(set) var sleepRemaining: TimeInterval = 0
    private var sleepTimer: Timer?

    static var canUseAutoMix: Bool {
        (UserDefaults.standard.string(forKey: "gaplessPlayback") ?? "on") != "off"
    }

    init() {
        activePlayer = primaryPlayer
        if let raw = UserDefaults.standard.string(forKey: "playbackTransitionMode"),
           let mode = PlaybackTransitionMode(rawValue: raw) {
            transitionMode = mode
        } else if UserDefaults.standard.bool(forKey: "crossfadeEnabled") {
            transitionMode = .crossfade
        }
        if transitionMode == .automix, !Self.canUseAutoMix {
            transitionMode = .crossfade
            UserDefaults.standard.set(PlaybackTransitionMode.crossfade.rawValue, forKey: "playbackTransitionMode")
        }
        configureAudioSession()
        configureRemoteCommands()
        addTimeObservers()
        addEndObserver()
        // re-apply (or remove) the EQ tap on the current item when toggled
        NotificationCenter.default.addObserver(forName: .equalizerToggled, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, let item = self.player.currentItem else { return }
                self.applyEqualizer(to: item)
            }
        }
    }

    // attaches the equalizer tap to an item's audio track (no-op + clears the mix
    // when the EQ is disabled, so default playback is never routed through a tap).
    private func applyEqualizer(to item: AVPlayerItem) {
        guard EqualizerEngine.shared.isEnabled else { item.audioMix = nil; return }
        Task { @MainActor [weak self] in
            guard self != nil else { return }
            guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first,
                  let tap = EqualizerEngine.shared.makeTap() else { return }
            let params = AVMutableAudioMixInputParameters(track: track)
            params.audioTapProcessor = tap
            let mix = AVMutableAudioMix()
            mix.inputParameters = [params]
            item.audioMix = mix
        }
    }

    func updateClient(_ client: SubsonicClient?) {
        self.client = client
        DownloadService.shared.updateClient(client)
    }

    // MARK: - Playback entry points

    func playQueue(_ songs: [Song], startIndex: Int = 0, source: String = "", album: Album? = nil, playlist: Playlist? = nil) {
        cancelTransitionPlayback()
        gaplessNextItem = nil
        // any normal play action clears artist-scoped autoplay
        autoplayArtistName = nil
        autoplayArtistId = nil
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

    // play an artist's music and keep autoplay scoped to that artist
    func playArtist(_ songs: [Song], artist: Artist) {
        guard !songs.isEmpty else { return }
        playQueue(songs, startIndex: 0, source: artist.name)
        autoplayArtistName = artist.name
        autoplayArtistId = artist.id
        if autoplayMode == .off { autoplayMode = .algorithm }   // so it keeps playing them
    }

    func skipNext() {
        AppLogger.shared.log("⏭ Skip next (idx \(currentIndex) → \(currentIndex + 1))", category: .playback)
        cancelTransitionPlayback()
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
                Task { await appendAutoplaySongs(advanceAfterAppend: true) }
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
        cancelTransitionPlayback()
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
        cancelTransitionPlayback()
        currentIndex = index
        playCurrent()
    }

    func togglePlayPause() {
        guard currentSong != nil else { return }
        if isPlaying {
            pauseAllPlayers()
            cancelTransitionPlayback()
        } else {
            player.play()
        }
        isPlaying.toggle()
        AppLogger.shared.log(isPlaying ? "▶ Resume" : "⏸ Pause", category: .playback)
        updateNowPlaying()
    }

    func pause() {
        pauseAllPlayers()
        cancelTransitionPlayback()
        isPlaying = false
        updateNowPlaying()
    }

    func seek(to time: TimeInterval) {
        cancelTransitionPlayback()
        let target = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
        updateNowPlayingTime()
    }

    // live playback position straight from the player. the scrubber samples this
    // every frame so its fill tracks the real position and can't drift/detach
    // between the (coarser) periodic observer ticks.
    func liveTime() -> TimeInterval {
        let t = player.currentTime().seconds
        return t.isFinite ? t : currentTime
    }

    // duration of the item actually playing right now. read live so the remaining
    // time can't show 0:00 while audio keeps playing (stale metadata duration) and
    // stays in lockstep with liveTime — both sampled from the same source.
    func liveDuration() -> TimeInterval {
        let d = player.currentItem?.duration.seconds ?? duration
        return (d.isFinite && d > 0) ? d : duration
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
        guard !queue.isEmpty else {
            queue = [song]
            currentIndex = 0
            return
        }
        invalidatePreloadedNext()
        queue.insert(song, at: currentIndex + 1)
        resetPreparedTransitionPlan()
        scheduleGaplessPreload()
        prepareTransitionPlanIfNeeded()
    }

    func addToQueue(_ song: Song) {
        guard !queue.isEmpty else { play(song: song); return }
        queue.append(song)
    }

    // batch variants for multi-select — order is preserved.
    func playNext(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        guard !queue.isEmpty else {
            queue = songs
            currentIndex = 0
            queueSourceTitle = "Selection"
            return
        }
        invalidatePreloadedNext()
        queue.insert(contentsOf: songs, at: currentIndex + 1)
        resetPreparedTransitionPlan()
        scheduleGaplessPreload()
        prepareTransitionPlanIfNeeded()
    }

    func addToQueue(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        guard !queue.isEmpty else { playQueue(songs, startIndex: 0, source: "Selection"); return }
        queue.append(contentsOf: songs)
    }

    func removeQueueItem(at index: Int) {
        guard index >= 0, index < queue.count else { return }
        if index == currentIndex + 1 { resetPreparedTransitionPlan() }
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
        ensureAutoplayPreloadedIfNeeded()
    }
    func toggleAutoplay() { isAutoplay.toggle() }
    func cycleTransitionMode() {
        switch transitionMode {
        case .off:       setTransitionMode(.crossfade)
        case .crossfade: setTransitionMode(Self.canUseAutoMix ? .automix : .off)
        case .automix:   setTransitionMode(.off)
        }
    }
    func setTransitionMode(_ mode: PlaybackTransitionMode) {
        let nextMode = (mode == .automix && !Self.canUseAutoMix) ? .crossfade : mode
        transitionMode = nextMode
        UserDefaults.standard.set(nextMode.rawValue, forKey: "playbackTransitionMode")
        UserDefaults.standard.set(nextMode != .off, forKey: "crossfadeEnabled")
        resetPreparedTransitionPlan()
        if nextMode == .off {
            cancelTransitionPlayback()
        } else {
            prepareTransitionPlanIfNeeded()
        }
    }
    func toggleCrossfade() { cycleTransitionMode() }

    // MARK: - Sleep timer

    func startSleepTimer(minutes: Int) {
        cancelSleepTimer()
        sleepEndsAtTrackEnd = false
        sleepRemaining = TimeInterval(minutes * 60)
        sleepTimerActive = true
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.sleepTimerActive, !self.sleepEndsAtTrackEnd else { return }
                self.sleepRemaining -= 1
                if self.sleepRemaining <= 0 { self.fireSleep() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        sleepTimer = timer
        AppLogger.shared.log("😴 Sleep timer set for \(minutes) min", category: .playback)
    }

    func startSleepTimerEndOfTrack() {
        cancelSleepTimer()
        sleepEndsAtTrackEnd = true
        sleepTimerActive = true
        AppLogger.shared.log("😴 Sleep timer set: end of track", category: .playback)
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerActive = false
        sleepEndsAtTrackEnd = false
        sleepRemaining = 0
    }

    private func fireSleep() {
        AppLogger.shared.log("😴 Sleep timer fired — pausing", category: .playback)
        pause()
        cancelSleepTimer()
    }

    // MARK: - ReplayGain / volume normalization

    private func replayGainVolume(for song: Song) -> Float {
        let mode = UserDefaults.standard.string(forKey: "replayGainMode") ?? "off"
        guard mode != "off", let rg = song.replayGain else { return 1.0 }
        // gain is in dB relative to the ReplayGain reference level → linear multiplier
        let gainDB: Double? = mode == "album" ? (rg.albumGain ?? rg.trackGain) : (rg.trackGain ?? rg.albumGain)
        guard let g = gainDB else { return 1.0 }
        var linear = pow(10.0, g / 20.0)
        // peak protection: never push the signal above full scale (clipping)
        if let peak = (mode == "album" ? rg.albumPeak : rg.trackPeak), peak > 0 {
            linear = min(linear, 1.0 / peak)
        }
        // AVPlayer volume is capped at 1.0 so upward normalization is limited to attenuation
        return Float(min(1.0, max(0.0, linear)))
    }

    private func applyReplayGain(for song: Song) {
        targetVolume = replayGainVolume(for: song)
        player.volume = targetVolume
    }

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

    private func appendAutoplaySongs(advanceAfterAppend: Bool) async {
        if currentIndex < queue.count - 1 {
            if advanceAfterAppend {
                currentIndex += 1
                playCurrent()
            }
            return
        }
        if let task = autoplayAppendTask {
            await task.value
        } else {
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.fetchAutoplaySongs()
            }
            autoplayAppendTask = task
            await task.value
            autoplayAppendTask = nil
        }

        guard advanceAfterAppend else { return }
        if currentIndex < queue.count - 1 {
            currentIndex += 1
            playCurrent()
        } else {
            player.pause()
            isPlaying = false
            currentTime = 0
            seek(to: 0)
        }
    }

    private func ensureAutoplayPreloadedIfNeeded() {
        guard autoplayMode != .off,
              autoplayAppendTask == nil,
              !queue.isEmpty else { return }
        let remaining = max(0, queue.count - currentIndex - 1)
        guard remaining <= autoplayPreloadThreshold else { return }
        autoplayAppendTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.fetchAutoplaySongs()
            self.autoplayAppendTask = nil
        }
    }

    private func fetchAutoplaySongs() async {
        guard autoplayMode != .off, let client else { return }
        let existingIDs = Set(queue.map(\.id))
        func freshFrom(_ list: [Song]) -> [Song] { list.filter { !existingIDs.contains($0.id) } }

        var fresh: [Song] = []

        // 1) artist-scoped autoplay: keep pulling the same artist's top songs
        if let name = autoplayArtistName {
            fresh = freshFrom((try? await client.topSongs(artistName: name, count: 50)) ?? [])
        }
        // 2) algorithm mode: blended, taste-aware selection
        if fresh.isEmpty, autoplayMode == .algorithm {
            fresh = await algorithmicAutoplay(client: client, existingIDs: existingIDs)
        }
        // 3) fallback: random library songs
        if fresh.isEmpty {
            var pool = (try? await client.randomSongs(size: 30)) ?? []
            if transitionMode == .automix, let g = currentSong?.genre, !g.isEmpty {
                pool += (try? await client.songsByGenre(g, count: 10)) ?? []
            }
            fresh = automixSmoothAutoplay(freshFrom(pool), current: currentSong)
        }

        guard !fresh.isEmpty else { return }
        queue.append(contentsOf: Array(fresh.prefix(30)))
        scheduleGaplessPreload()
    }

    // algorithm mode draws from several signals and blends them:
    //   • continuity — similar artists to what's playing + more of this genre
    //   • taste      — the user's most-played artists from LOCAL play history
    //   • server     — each artist's top (most-streamed) songs
    // results are deduped, biased toward the current genre, but kept shuffled.
    private func algorithmicAutoplay(client: SubsonicClient, existingIDs: Set<String>) async -> [Song] {
        let currentGenre = currentSong?.genre?.lowercased()
        var pool: [Song] = []

        // similar artists to the one playing (discovery, same neighbourhood)
        if let artistId = currentSong?.artistId,
           let info = try? await client.artistInfo(id: artistId) {
            let names = (info.similarArtist ?? []).prefix(3).map(\.name)
            pool += await topSongs(forArtists: names, client: client, each: 8)
        }

        // the user's most-played artists from local stats (their actual taste)
        pool += await topSongs(forArtists: topLocalArtists(limit: 3), client: client, each: 8)

        // keep the current vibe going with more of the same genre
        if let g = currentSong?.genre, !g.isEmpty {
            pool += (try? await client.songsByGenre(g, count: 25)) ?? []
        }

        // dedupe + drop anything already queued
        var seen = Set<String>()
        let unique = pool.filter { seen.insert($0.id).inserted && !existingIDs.contains($0.id) }

        if transitionMode == .automix {
            return automixSmoothAutoplay(unique, current: currentSong)
        }

        // partition by genre match so the current vibe leads, each part shuffled
        let matching = unique.filter { $0.genre?.lowercased() == currentGenre }.shuffled()
        let rest     = unique.filter { $0.genre?.lowercased() != currentGenre }.shuffled()
        return matching + rest
    }

    private func automixSmoothAutoplay(_ songs: [Song], current: Song?) -> [Song] {
        guard transitionMode == .automix, let current, !songs.isEmpty else { return songs }
        let currentGenre = current.genre?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sameArtist = songs.filter {
            current.artistId != nil && $0.artistId == current.artistId
        }.shuffled()
        let sameGenre = songs.filter {
            guard !sameArtist.contains($0), let currentGenre, !currentGenre.isEmpty else { return false }
            return $0.genre?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == currentGenre
        }.shuffled()
        let rest = songs.filter { song in
            !sameArtist.contains(song) && !sameGenre.contains(song)
        }.shuffled()

        let lead = Array(sameArtist.prefix(2)) + Array(sameGenre.prefix(8))
        let tail = Array(sameArtist.dropFirst(2)) + Array(sameGenre.dropFirst(8)) + rest
        return lead + tail.shuffled()
    }

    // the user's most-played artists from the local stats store (streamed count).
    private func topLocalArtists(limit: Int) -> [String] {
        var counts: [String: Int] = [:]
        for e in StatsStore.shared.allEvents() { counts[e.artist, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.prefix(limit).map(\.key)
    }

    // fetches each artist's top songs in parallel and flattens the result.
    private func topSongs(forArtists names: [String], client: SubsonicClient, each: Int) async -> [Song] {
        guard !names.isEmpty else { return [] }
        return await withTaskGroup(of: [Song].self) { group in
            for n in names {
                group.addTask { (try? await client.topSongs(artistName: n, count: each)) ?? [] }
            }
            var all: [Song] = []
            for await s in group { all += s }
            return all
        }
    }

    // MARK: - Private

    private func playCurrent() {
        guard !queue.isEmpty, currentIndex < queue.count else { return }
        let song = queue[currentIndex]
        startPlaying(song: song)
    }

    private func invalidatePreloadedNext() {
        if let gaplessNextItem {
            player.remove(gaplessNextItem)
        }
        gaplessNextItem = nil
    }

    private func startPlaying(song: Song) {
        cancelTransitionPlayback()
        resetPreparedTransitionPlan()
        inactivePlayer.pause()
        inactivePlayer.removeAllItems()
        let localURL = DownloadService.shared.localURL(for: song)
        let streamURL = localURL ?? client?.streamURL(id: song.id)
        guard let url = streamURL else {
            AppLogger.shared.log("✗ No stream URL for '\(song.title)'", category: .playback, level: .error)
            return
        }
        let src = localURL != nil ? "local" : "stream"
        if localURL != nil { DownloadService.shared.markPlayed(song.id) }
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

        applyEqualizer(to: item)

        // For gapless "on": use AVQueuePlayer's insert so transition is seamless
        if gapless == "on" {
            player.removeAllItems()
            player.insert(item, after: nil)
        } else {
            player.replaceCurrentItem(with: item)
        }
        player.play()
        applyReplayGain(for: song)
        currentSong = song
        isPlaying = true
        currentTime = 0
        duration = 0
        currentArtwork = nil
        currentAnimatedArtwork = nil
        currentLiveArtwork = nil
        loggedSongIDs.remove(song.id)   // allow re-logging if replayed

        // starred state from server's starred field
        if song.starred != nil {
            starredIDs.insert(song.id)
        }

        updateNowPlaying()
        Task { await loadArtwork(for: song) }
        Task { await loadDuration(from: item) }
        scheduleGaplessPreload()
        ensureAutoplayPreloadedIfNeeded()
        prepareTransitionPlanIfNeeded()
    }

    private func scheduleGaplessPreload() {
        guard transitionMode == .off else { gaplessNextItem = nil; return }
        let gapless = UserDefaults.standard.string(forKey: "gaplessPlayback") ?? "off"
        guard gapless != "off" else { gaplessNextItem = nil; return }
        let nextIndex = currentIndex + 1
        guard nextIndex < queue.count else { gaplessNextItem = nil; return }
        let nextSong = queue[nextIndex]
        let localURL = DownloadService.shared.localURL(for: nextSong)
        guard let url = localURL ?? client?.streamURL(id: nextSong.id) else { return }
        let nextItem = AVPlayerItem(url: url)
        applyEqualizer(to: nextItem)
        gaplessNextItem = nextItem
        // For "on" mode: actually insert into AVQueuePlayer queue for seamless transition
        if gapless == "on" {
            player.insert(nextItem, after: player.currentItem)
        }
        AppLogger.shared.log("⏭ Gapless pre-buffer: '\(nextSong.title)' [mode=\(gapless)]", category: .playback)
    }

    private func prepareTransitionPlanIfNeeded() {
        if transitionMode == .automix, !Self.canUseAutoMix {
            setTransitionMode(.crossfade)
            return
        }
        guard transitionMode != .off,
              currentIndex + 1 < queue.count,
              let current = currentSong else {
            resetPreparedTransitionPlan()
            return
        }
        let next = queue[currentIndex + 1]
        let key = "\(transitionMode.rawValue):\(current.id)->\(next.id)"
        guard transitionPlanKey != key else { return }

        resetPreparedTransitionPlan()
        transitionPlanKey = key
        let fallback = PlaybackTransitionPlan.fallback(mode: transitionMode, current: current, next: next)
        preparedTransitionPlan = fallback

        guard transitionMode == .automix else { return }
        transitionPlanTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let plan = await self.makeAutoMixPlan(current: current, next: next, fallback: fallback)
            guard !Task.isCancelled, self.transitionPlanKey == key else { return }
            self.preparedTransitionPlan = plan
            AppLogger.shared.log(
                "🌀 AutoMix plan: \(current.title) → \(next.title), \(String(format: "%.1f", plan.duration))s, lead \(String(format: "%.1f", plan.startLead))s, seek \(String(format: "%.1f", plan.nextStart))s [\(plan.reason)]",
                category: .playback
            )
        }
    }

    private func resetPreparedTransitionPlan() {
        transitionPlanTask?.cancel()
        transitionPlanTask = nil
        transitionPlanKey = nil
        preparedTransitionPlan = nil
    }

    private func makeAutoMixPlan(
        current: Song,
        next: Song,
        fallback: PlaybackTransitionPlan
    ) async -> PlaybackTransitionPlan {
        var currentProfile = AudioSilenceProfile.zero
        var nextProfile = AudioSilenceProfile.zero

        if let currentURL = DownloadService.shared.localURL(for: current) {
            currentProfile = await AutoMixAudioAnalyzer.shared.profile(for: currentURL)
        }
        if let nextURL = DownloadService.shared.localURL(for: next) {
            nextProfile = await AutoMixAudioAnalyzer.shared.profile(for: nextURL)
        }

        let trailing = min(10, max(0, currentProfile.trailingSilence))
        let leading = min(8, max(0, nextProfile.leadingSilence))
        let sameAlbum = current.albumId != nil && current.albumId == next.albumId
        let trimmedLeading = leading > 0.35 ? max(0, leading - 0.08) : 0
        let duration = sameAlbum ? min(fallback.duration, 4.0) : fallback.duration
        let startLead = max(1.5, duration + (trailing > 0.35 ? trailing - 0.1 : 0))

        guard trailing > 0.35 || leading > 0.35 else { return fallback }
        return PlaybackTransitionPlan(
            mode: .automix,
            duration: duration,
            startLead: startLead,
            nextStart: trimmedLeading,
            reason: "silence trim"
        )
    }

    private func checkScheduledTransition() {
        guard transitionMode != .off,
              isPlaying,
              !isTransitioning,
              transitionTask == nil,
              !sleepEndsAtTrackEnd,
              repeatMode != .one,
              currentIndex + 1 < queue.count,
              let current = currentSong else { return }

        let next = queue[currentIndex + 1]
        prepareTransitionPlanIfNeeded()
        let plan = preparedTransitionPlan ?? PlaybackTransitionPlan.fallback(
            mode: transitionMode,
            current: current,
            next: next
        )
        let remaining = liveDuration() - liveTime()
        guard remaining.isFinite,
              remaining > 0.25,
              remaining <= plan.startLead else { return }
        startPlannedTransition(plan, nextSong: next)
    }

    private func startPlannedTransition(_ plan: PlaybackTransitionPlan, nextSong: Song) {
        guard !isTransitioning,
              currentIndex + 1 < queue.count,
              let urlInfo = playbackURL(for: nextSong) else { return }

        let oldPlayer = activePlayer
        let newPlayer = inactivePlayer
        let nextItem = AVPlayerItem(url: urlInfo.url)
        applyEqualizer(to: nextItem)

        newPlayer.pause()
        newPlayer.removeAllItems()
        newPlayer.insert(nextItem, after: nil)
        newPlayer.volume = 0
        if plan.nextStart > 0 {
            let seekTime = CMTime(seconds: plan.nextStart, preferredTimescale: 600)
            newPlayer.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        if urlInfo.isLocal { DownloadService.shared.markPlayed(nextSong.id) }
        let oldStartVolume = oldPlayer.volume
        let newTargetVolume = replayGainVolume(for: nextSong)

        activePlayer = newPlayer
        targetVolume = newTargetVolume
        currentIndex += 1
        currentSong = nextSong
        isPlaying = true
        currentTime = plan.nextStart
        duration = 0
        currentArtwork = nil
        currentAnimatedArtwork = nil
        currentLiveArtwork = nil
        loggedSongIDs.remove(nextSong.id)
        if nextSong.starred != nil { starredIDs.insert(nextSong.id) }
        resetPreparedTransitionPlan()

        newPlayer.play()
        updateNowPlaying()
        Task { await loadArtwork(for: nextSong) }
        Task { await loadDuration(from: nextItem) }
        ensureAutoplayPreloadedIfNeeded()
        prepareTransitionPlanIfNeeded()

        isTransitioning = true
        let fadeDuration = max(0.75, plan.duration)
        AppLogger.shared.log("🌀 \(plan.mode.settingsLabel): '\(nextSong.title)' over \(String(format: "%.1f", fadeDuration))s", category: .playback)
        transitionTask = Task { @MainActor [weak self, weak oldPlayer, weak newPlayer] in
            guard let self, let oldPlayer, let newPlayer else { return }
            let steps = max(12, Int(fadeDuration * 30))
            for step in 0...steps {
                if Task.isCancelled { return }
                let x = Double(step) / Double(steps)
                let curve = x * x * (3 - 2 * x)
                oldPlayer.volume = oldStartVolume * Float(1 - curve)
                newPlayer.volume = newTargetVolume * Float(curve)
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
            guard self.player === newPlayer else { return }
            oldPlayer.pause()
            oldPlayer.removeAllItems()
            oldPlayer.volume = 0
            newPlayer.volume = newTargetVolume
            self.isTransitioning = false
            self.transitionTask = nil
            self.scheduleGaplessPreload()
            self.prepareTransitionPlanIfNeeded()
        }
    }

    private func playbackURL(for song: Song) -> (url: URL, isLocal: Bool)? {
        if let localURL = DownloadService.shared.localURL(for: song) {
            return (localURL, true)
        }
        guard let streamURL = client?.streamURL(id: song.id) else { return nil }
        return (streamURL, false)
    }

    private func cancelTransitionPlayback() {
        transitionTask?.cancel()
        transitionTask = nil
        isTransitioning = false
        inactivePlayer.pause()
        inactivePlayer.removeAllItems()
        inactivePlayer.volume = 0
        player.volume = targetVolume
    }

    private func pauseAllPlayers() {
        primaryPlayer.pause()
        secondaryPlayer.pause()
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

        // probe for live (animated) artwork from the ORIGINAL cover (no size param,
        // so a resizing server doesn't flatten the animation). full player only.
        let liveEnabled = UserDefaults.standard.object(forKey: "liveArtwork") as? Bool ?? true
        guard liveEnabled, song.coverArt != nil else { return }
        let originalURL = client?.coverArtURL(id: song.coverArt)
        let live = await ArtworkLoader.shared.liveArtwork(for: originalURL)
        guard currentSong?.id == song.id else { return }
        currentLiveArtwork = live
        currentAnimatedArtwork = live?.animatedImage
        applyNowPlayingAnimatedArtwork(live)
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

    private func addTimeObservers() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        primaryTimeObserverToken = primaryPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                guard self.activePlayer === self.primaryPlayer else { return }
                self.currentTime = time.seconds
                self.checkLogPlay()
                self.checkScheduledTransition()
            }
        }
        secondaryTimeObserverToken = secondaryPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                guard self.activePlayer === self.secondaryPlayer else { return }
                self.currentTime = time.seconds
                self.checkLogPlay()
                self.checkScheduledTransition()
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
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let finishedItem = note.object as? AVPlayerItem else { return }
                if self.isTransitioning, finishedItem !== self.player.currentItem { return }
                // sleep timer set to "end of track": stop here instead of advancing
                if self.sleepEndsAtTrackEnd {
                    self.player.pause()
                    self.isPlaying = false
                    self.cancelSleepTimer()
                    self.updateNowPlaying()
                    return
                }
                let gapless = UserDefaults.standard.string(forKey: "gaplessPlayback") ?? "off"
                // For "on" mode, AVQueuePlayer already advanced to the pre-queued item.
                // Update our index + state without replacing the current item.
                if gapless == "on",
                   self.repeatMode == .off,
                   self.currentIndex + 1 < self.queue.count {
                    self.currentIndex += 1
                    let song = self.queue[self.currentIndex]
                    self.applyReplayGain(for: song)
                    self.currentSong = song
                    self.currentTime = 0
                    self.duration = 0
                    self.currentArtwork = nil
                    self.currentAnimatedArtwork = nil
                    self.currentLiveArtwork = nil
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
        addAnimatedArtwork(to: &info, live: currentLiveArtwork)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func applyNowPlayingAnimatedArtwork(_ live: LiveArtworkAsset?) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        addAnimatedArtwork(to: &info, live: live)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func addAnimatedArtwork(to info: inout [String: Any], live: LiveArtworkAsset?) {
        info.removeValue(forKey: MPNowPlayingInfoProperty1x1AnimatedArtwork)
        guard let live, let videoURL = live.videoURL else { return }
        let key = MPNowPlayingInfoProperty1x1AnimatedArtwork
        guard MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys.contains(key) else { return }
        let preview = live.previewImage
        let animated = MPMediaItemAnimatedArtwork(artworkID: live.artworkID) { _ in
            preview
        } videoAssetFileURLRequestHandler: { _ in
            videoURL
        }
        info[key] = animated
    }

    private func updateNowPlayingTime() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

private actor AutoMixAudioAnalyzer {
    static let shared = AutoMixAudioAnalyzer()

    private var cache: [URL: AudioSilenceProfile] = [:]
    private let silenceThreshold: Float = 0.003

    func profile(for url: URL) async -> AudioSilenceProfile {
        guard url.isFileURL else { return .zero }
        if let cached = cache[url] { return cached }
        let profile = await analyze(url: url)
        cache[url] = profile
        return profile
    }

    private func analyze(url: URL) async -> AudioSilenceProfile {
        let asset = AVURLAsset(url: url)
        guard let loadedDuration = try? await asset.load(.duration),
              let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return .zero }
        let duration = loadedDuration.seconds
        guard duration.isFinite,
              duration > 0 else { return .zero }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return .zero }
        reader.add(output)
        guard reader.startReading() else { return .zero }

        var firstAudible: TimeInterval?
        var lastAudible: TimeInterval?

        while !Task.isCancelled, let sampleBuffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            var length = 0
            var rawPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(
                block,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &rawPointer
            )
            guard status == kCMBlockBufferNoErr,
                  let rawPointer,
                  length >= MemoryLayout<Float>.size else { continue }

            let sampleCount = length / MemoryLayout<Float>.size
            let stride = max(1, sampleCount / 4096)
            let maxAmplitude = rawPointer.withMemoryRebound(to: Float.self, capacity: sampleCount) { samples in
                var maxValue: Float = 0
                var index = 0
                while index < sampleCount {
                    maxValue = max(maxValue, abs(samples[index]))
                    index += stride
                }
                return maxValue
            }
            guard maxAmplitude >= silenceThreshold else { continue }

            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            let sampleDuration = CMSampleBufferGetDuration(sampleBuffer).seconds
            let start = pts.isFinite ? pts : 0
            let end = sampleDuration.isFinite ? start + sampleDuration : start
            if firstAudible == nil { firstAudible = start }
            lastAudible = max(lastAudible ?? end, end)
        }

        guard let firstAudible, let lastAudible else { return .zero }
        let leading = min(12, max(0, firstAudible))
        let trailing = min(12, max(0, duration - lastAudible))
        return AudioSilenceProfile(leadingSilence: leading, trailingSilence: trailing)
    }
}
