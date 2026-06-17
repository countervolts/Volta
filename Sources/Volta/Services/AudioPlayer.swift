import Foundation
import AVFoundation
import Accelerate
import MediaPlayer
import Observation
import UIKit

enum RepeatMode: Sendable { case off, one, all }
enum AutoplayMode: Sendable { case off, random, algorithm }

// User-tunable infinite-play fill style.
enum InfinitePlayStyle: String, CaseIterable, Identifiable, Sendable {
    case random      // any songs from the library
    case similar     // similar to what was playing before infinite play started
    case sameGenre   // stay in the current genre

    var id: String { rawValue }

    var label: String {
        switch self {
        case .random:    return "Random"
        case .similar:   return "Similar Songs"
        case .sameGenre: return "Same Genre"
        }
    }

    var icon: String {
        switch self {
        case .random:    return "shuffle"
        case .similar:   return "wand.and.stars"
        case .sameGenre: return "guitars"
        }
    }

    static var current: InfinitePlayStyle {
        InfinitePlayStyle(rawValue: UserDefaults.standard.string(forKey: "infinitePlayStyle") ?? "") ?? .random
    }
}
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
    let oldRate: Float
    let nextRate: Float
    // Beat grids used for downbeat-locked transitions.
    var beatAligned: Bool = false
    var beatsPerBar: Int = 4
    var outBeatPeriod: TimeInterval = 0     // outgoing-track beat period (s)
    var outBeatPhase: TimeInterval = 0      // outgoing-track grid offset (s)
    var inBeatPeriod: TimeInterval = 0      // incoming-track beat period (s)
    var inBeatPhase: TimeInterval = 0       // incoming-track grid offset (s)
    // Incoming-volume multiplier for hotter masters.
    var volumeMatch: Float = 1

    static func fallback(mode: PlaybackTransitionMode, current: Song, next: Song) -> PlaybackTransitionPlan {
        let sameAlbum = current.albumId != nil && current.albumId == next.albumId
        let sameArtist = current.artistId != nil && current.artistId == next.artistId
        let sameGenre = current.genre != nil && current.genre?.caseInsensitiveCompare(next.genre ?? "") == .orderedSame
        switch mode {
        case .off:
            return PlaybackTransitionPlan(mode: mode, duration: 0, startLead: 0, nextStart: 0, reason: "off", oldRate: 1, nextRate: 1)
        case .crossfade:
            let duration = PlaybackTransitionSettings.crossfadeDuration(sameAlbum: sameAlbum)
            return PlaybackTransitionPlan(mode: mode, duration: duration, startLead: duration, nextStart: 0, reason: "fixed", oldRate: 1, nextRate: 1)
        case .automix:
            let duration = PlaybackTransitionSettings.automixDuration(
                sameAlbum: sameAlbum,
                sameArtist: sameArtist,
                sameGenre: sameGenre
            )
            return PlaybackTransitionPlan(mode: mode, duration: duration, startLead: duration, nextStart: 0, reason: "metadata", oldRate: 1, nextRate: 1)
        }
    }
}

private enum PlaybackTransitionSettings {
    static var style: String {
        UserDefaults.standard.string(forKey: "automixStyle") ?? "balanced"
    }

    static var silenceTrimEnabled: Bool {
        if UserDefaults.standard.object(forKey: "automixSilenceTrim") == nil { return true }
        return UserDefaults.standard.bool(forKey: "automixSilenceTrim")
    }

    static var tempoMatchEnabled: Bool {
        if UserDefaults.standard.object(forKey: "automixTempoMatch") == nil { return true }
        return UserDefaults.standard.bool(forKey: "automixTempoMatch")
    }

    // Fire on the outgoing downbeat and drop the incoming on its downbeat.
    static var beatAlignEnabled: Bool {
        if UserDefaults.standard.object(forKey: "automixBeatAlign") == nil { return true }
        return UserDefaults.standard.bool(forKey: "automixBeatAlign")
    }

    // Scale blend length by Camelot compatibility.
    static var harmonicEnabled: Bool {
        if UserDefaults.standard.object(forKey: "automixHarmonic") == nil { return true }
        return UserDefaults.standard.bool(forKey: "automixHarmonic")
    }

    // Skip sparse intros and long decaying outros.
    static var sweetSpotEnabled: Bool {
        if UserDefaults.standard.object(forKey: "automixSweetSpot") == nil { return true }
        return UserDefaults.standard.bool(forKey: "automixSweetSpot")
    }

    // Loudness match when ReplayGain is not already doing it.
    static var loudnessMatchEnabled: Bool {
        if UserDefaults.standard.object(forKey: "automixLoudnessMatch") == nil { return true }
        return UserDefaults.standard.bool(forKey: "automixLoudnessMatch")
    }

    static var maxBlend: TimeInterval {
        let value = UserDefaults.standard.double(forKey: "automixMaxBlendSeconds")
        return min(18, max(4, value > 0 ? value : 10))
    }

    static func crossfadeDuration(sameAlbum: Bool) -> TimeInterval {
        let value = UserDefaults.standard.double(forKey: "crossfadeDurationSeconds")
        let duration = min(12, max(1, value > 0 ? value : 6))
        return sameAlbum ? min(duration, 4) : duration
    }

    static func automixDuration(sameAlbum: Bool, sameArtist: Bool, sameGenre: Bool) -> TimeInterval {
        if sameAlbum { return min(maxBlend, 4) }
        let base: TimeInterval
        switch style {
        case "tight":
            base = sameArtist || sameGenre ? 7 : 5
        case "wide":
            base = sameArtist || sameGenre ? 13 : 10
        default:
            base = sameArtist || sameGenre ? 10 : 8
        }
        return min(maxBlend, max(3, base))
    }
}

private struct AudioSilenceProfile: Sendable {
    var leadingSilence: TimeInterval
    var trailingSilence: TimeInterval

    static let zero = AudioSilenceProfile(leadingSilence: 0, trailingSilence: 0)
}

// Shared by live AutoMix and the Settings preview.
enum AutoMixTempo {
    // Gentle, pitch-preserved bend.
    static let maxRate: Double = 1.06          // +/-6%
    static let maxRatio: Double = 1.32         // engage only within ~32%

    // 75 and 150 BPM are often the same pulse counted differently.
    static func fold(_ bpm: Double, toward target: Double) -> Double {
        let candidates = [bpm / 2, bpm, bpm * 2].filter { $0 >= 60 && $0 <= 210 }
        return candidates.min {
            abs(log($0 / target)) < abs(log($1 / target))
        } ?? bpm
    }

    // Bend only the outgoing track, and hold one constant rate through the fade.
    static func outgoingRate(currentBPM rawCurrent: Double, nextBPM rawNext: Double)
        -> (rate: Float, currentBPM: Double, nextBPM: Double)? {
        let currentBPM = fold(rawCurrent, toward: rawNext)
        let nextBPM = fold(rawNext, toward: currentBPM)
        guard currentBPM >= 60, nextBPM >= 60, currentBPM <= 210, nextBPM <= 210 else { return nil }
        // play the outgoing track at the incoming track's tempo (nextBPM)
        let ratio = nextBPM / currentBPM
        guard ratio.isFinite, ratio > 0, abs(log(ratio)) <= log(maxRatio) else { return nil }
        let rate = min(maxRate, max(1 / maxRate, ratio))
        guard abs(rate - 1) >= 0.008 else { return nil }
        return (Float(rate), currentBPM, nextBPM)
    }
}

@MainActor
@Observable
final class AudioPlayer {
    private(set) var currentSong: Song?
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var currentArtwork: UIImage?
    private(set) var currentAnimatedArtwork: UIImage?
    private(set) var currentLiveArtwork: LiveArtworkAsset?

    private(set) var queue: [Song] = []
    private(set) var currentIndex: Int = 0
    private(set) var queueSourceTitle: String = ""
    private(set) var queueSourceAlbum: Album?
    private(set) var queueSourcePlaylist: Playlist?

    private(set) var isShuffle = false
    private(set) var repeatMode: RepeatMode = .off
    private(set) var autoplayMode: AutoplayMode = .off
    private(set) var transitionMode: PlaybackTransitionMode = .off
    var isCrossfade: Bool { transitionMode != .off }

    var isAutoplay: Bool {
        get { autoplayMode != .off }
        set {
            autoplayMode = newValue ? .random : .off
            UserDefaults.standard.set(newValue, forKey: "autoplayEnabled")
            ensureAutoplayPreloadedIfNeeded()
        }
    }

    private(set) var starredIDs: Set<String> = []

    private let primaryPlayer = AVQueuePlayer()
    private let secondaryPlayer = AVQueuePlayer()
    private var activePlayer: AVQueuePlayer
    private var player: AVQueuePlayer { activePlayer }
    private var inactivePlayer: AVQueuePlayer {
        activePlayer === primaryPlayer ? secondaryPlayer : primaryPlayer
    }
    private var client: (any MusicService)?
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
    // Drives the "Mixing" indicator.
    private(set) var isMixing = false
    private var transitionSuppressedUntil = Date.distantPast
    // Muted pre-buffer on the inactive player.
    private var primedSongID: String?
    // Scheduled downbeat transition that has not fired yet.
    private var transitionArmTask: Task<Void, Never>?
    private var transitionArmed = false
    // Bass-swap tap ids; 0 means inactive.
    private var primedBassID: UInt64 = 0
    private var currentBassID: UInt64 = 0

    private var gaplessNextItem: AVPlayerItem? = nil
    // Bumped on every playCurrent so a deferred (warm-then-play) request can detect
    // it was superseded by a newer skip/track change before it runs.
    private var playRequestID: UInt64 = 0
    private var autoplayAppendTask: Task<Void, Never>?
    private let autoplayPreloadThreshold = 1

    private(set) var autoplayArtistName: String?
    private(set) var autoplayArtistId: String?

    // Seed songs for Similar Songs infinite play.
    private var infinitePlaySeed: [Song] = []

    private(set) var sleepTimerActive = false
    private(set) var sleepEndsAtTrackEnd = false
    private(set) var sleepRemaining: TimeInterval = 0
    private var sleepTimer: Timer?

    static var canUseAutoMix: Bool {
        (UserDefaults.standard.string(forKey: "gaplessPlayback") ?? "on") != "off"
    }

    init() {
        activePlayer = primaryPlayer
        autoplayMode = UserDefaults.standard.bool(forKey: "autoplayEnabled") ? .random : .off
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
        addInterruptionObserver()
        addRouteChangeObserver()
        addStallObserver()
        NotificationCenter.default.addObserver(forName: .equalizerToggled, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, let item = self.player.currentItem else { return }
                self.applyEqualizer(to: item)
            }
        }
    }

    // Pick the time-stretch algorithm once; switching later audibly re-primes.
    private func makePlayerItem(url: URL) -> AVPlayerItem {
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .timeDomain
        return item
    }

    private func applyEqualizer(to item: AVPlayerItem) {
        guard EqualizerEngine.shared.isAnyEffectActive, !PerformanceMode.bypassAudioEffects else {
            item.audioMix = nil; return
        }
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

    // One audioMix tap per item, so bass-swap yields to EQ/effects.
    private var bassSwapAvailable: Bool {
        transitionMode == .automix
            && AutoMixBassSwap.shared.isEnabled
            && !EqualizerEngine.shared.isAnyEffectActive
            && !PerformanceMode.bypassAudioEffects
    }

    // Attach incoming-track bass-swap and return its tap id.
    private func attachBassSwap(to item: AVPlayerItem) -> UInt64 {
        guard bassSwapAvailable else { return 0 }
        let id = AutoMixBassSwap.shared.reserveID()
        Task { @MainActor [weak self] in
            guard self != nil else { return }
            guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first,
                  let tap = AutoMixBassSwap.shared.makeTap(id: id) else { return }
            let params = AVMutableAudioMixInputParameters(track: track)
            params.audioTapProcessor = tap
            let mix = AVMutableAudioMix()
            mix.inputParameters = [params]
            item.audioMix = mix
        }
        return id
    }

    // Incoming bass opens as the new track takes over.
    private func bassSwapCutoff(at x: Double) -> Double {
        let openBy = 0.6
        let k = max(0, 1 - x / openBy)
        return AutoMixBassSwap.bypassHz + (AutoMixBassSwap.maxCutoffHz - AutoMixBassSwap.bypassHz) * (k * k)
    }

    // Align grids at the bend point, not at T0, then clamp to half a beat.
    private func beatLockSeekShift(plan: PlaybackTransitionPlan) -> TimeInterval {
        guard plan.beatAligned, plan.outBeatPeriod > 0.2, plan.inBeatPeriod > 0.2,
              abs(plan.oldRate - 1) >= 0.01 else { return 0 }
        let pi = plan.inBeatPeriod, po = plan.outBeatPeriod
        let bendAt = 0.15 * max(0.75, plan.duration)
        let outFrac = bendAt.truncatingRemainder(dividingBy: po) / po
        let inFrac = bendAt.truncatingRemainder(dividingBy: pi) / pi
        var shift = (outFrac - inFrac) * pi
        shift = shift.truncatingRemainder(dividingBy: pi)
        if shift > pi / 2 { shift -= pi }
        if shift <= -pi / 2 { shift += pi }
        return shift
    }

    func updateClient(_ client: (any MusicService)?) {
        self.client = client
        DownloadService.shared.updateClient(client)
    }

    // MARK: - Playback entry points

    func playQueue(_ songs: [Song], startIndex: Int = 0, source: String = "", album: Album? = nil, playlist: Playlist? = nil) {
        cancelTransitionPlayback()
        gaplessNextItem = nil
        autoplayArtistName = nil
        autoplayArtistId = nil
        infinitePlaySeed = []
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

    func playArtist(_ songs: [Song], artist: Artist) {
        guard !songs.isEmpty else { return }
        playQueue(songs, startIndex: 0, source: artist.name)
        autoplayArtistName = artist.name
        autoplayArtistId = artist.id
        if autoplayMode == .off { autoplayMode = .algorithm }
    }

    func skipNext() {
        AppLogger.shared.log("⏭ Skip next (idx \(currentIndex) > \(currentIndex + 1))", category: .playback)
        suppressTransitionsBriefly()
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
        suppressTransitionsBriefly()
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
        suppressTransitionsBriefly()
        cancelTransitionPlayback()
        currentIndex = index
        playCurrent()
    }

    func togglePlayPause() {
        guard currentSong != nil else { return }
        if isPlaying {
            pauseAllPlayers()
            cancelTransitionPlayback(keepPaused: true)
        } else {
            player.play()
        }
        isPlaying.toggle()
        AppLogger.shared.log(isPlaying ? "▶ Resume" : "⏸ Pause", category: .playback)
        updateNowPlaying()
    }

    func pause() {
        pauseAllPlayers()
        cancelTransitionPlayback(keepPaused: true)
        isPlaying = false
        updateNowPlaying()
    }

    // Full stop for logout.
    func stopAndClear() {
        pauseAllPlayers()
        cancelTransitionPlayback(keepPaused: true)
        primaryPlayer.replaceCurrentItem(with: nil)
        secondaryPlayer.replaceCurrentItem(with: nil)
        isPlaying = false
        currentSong = nil
        currentArtwork = nil
        currentAnimatedArtwork = nil
        currentLiveArtwork = nil
        currentTime = 0
        duration = 0
        queue = []
        currentIndex = 0
        queueSourceTitle = ""
        queueSourceAlbum = nil
        queueSourcePlaylist = nil
        autoplayArtistName = nil
        autoplayArtistId = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func seek(to time: TimeInterval) {
        cancelTransitionPlayback(keepPaused: !isPlaying)
        let target = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
        updateNowPlayingTime()
    }

    func liveTime() -> TimeInterval {
        let t = player.currentTime().seconds
        return t.isFinite ? t : currentTime
    }

    func liveDuration() -> TimeInterval {
        let d = player.currentItem?.duration.seconds ?? duration
        return (d.isFinite && d > 0) ? d : duration
    }

    // MARK: - Queue manipulation

    func moveQueueItem(from source: IndexSet, to dest: Int) {
        queue.move(fromOffsets: source, toOffset: dest)
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
        // single-song entry point fired from menus/swipes/album loops; the toast
        // centre dedupes a burst of identical posts (album "Play Next") into one.
        VoltaNotificationCenter.shared.post(L(.notif_playing_next), tone: .queue)
        guard !queue.isEmpty else {
            queue = [song]
            currentIndex = 0
            queueSourceTitle = "Play Next"
            AppLogger.shared.log("Queued next while idle: '\(song.title)'", category: .playback)
            return
        }
        invalidatePreloadedNext()
        insertSongsNext([song])
        resetPreparedTransitionPlan()
        scheduleGaplessPreload()
        prepareTransitionPlanIfNeeded()
    }

    func addToQueue(_ song: Song) {
        guard !queue.isEmpty else { play(song: song); return }
        queue.append(song)
        VoltaNotificationCenter.shared.post(L(.notif_added_to_queue), tone: .queue)
    }

    func playNext(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        guard !queue.isEmpty else {
            queue = songs
            currentIndex = 0
            queueSourceTitle = "Selection"
            AppLogger.shared.log("Queued \(songs.count) next while idle", category: .playback)
            return
        }
        invalidatePreloadedNext()
        insertSongsNext(songs)
        resetPreparedTransitionPlan()
        scheduleGaplessPreload()
        prepareTransitionPlanIfNeeded()
    }

    func addToQueue(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        guard !queue.isEmpty else { playQueue(songs, startIndex: 0, source: "Selection"); return }
        queue.append(contentsOf: songs)
    }

    private func insertSongsNext(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        let currentID = currentSong?.id
        let idsToMove = Set(songs.map(\.id))
        var insertionIndex = min(currentIndex + 1, queue.count)
        var filteredQueue: [Song] = []

        for (idx, queued) in queue.enumerated() {
            let shouldMove = idsToMove.contains(queued.id) && queued.id != currentID
            if shouldMove {
                if idx < insertionIndex { insertionIndex -= 1 }
            } else {
                filteredQueue.append(queued)
            }
        }

        queue = filteredQueue
        insertionIndex = min(max(currentIndex + 1, insertionIndex), queue.count)
        queue.insert(contentsOf: songs, at: insertionIndex)
        AppLogger.shared.log("Queued \(songs.count) next at index \(insertionIndex)", category: .playback)
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
        UserDefaults.standard.set(autoplayMode != .off, forKey: "autoplayEnabled")
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
        // gain is in dB relative to the ReplayGain reference level > linear multiplier
        let gainDB: Double? = mode == "album" ? (rg.albumGain ?? rg.trackGain) : (rg.trackGain ?? rg.albumGain)
        guard let g = gainDB else { return 1.0 }
        var linear = pow(10.0, g / 20.0)
        if let peak = (mode == "album" ? rg.albumPeak : rg.trackPeak), peak > 0 {
            linear = min(linear, 1.0 / peak)
        }
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
            VoltaNotificationCenter.shared.post(L(.notif_removed_from_favorites), tone: .info)
            Task { try? await client?.unstar(id: songID) }
        } else {
            starredIDs.insert(songID)
            VoltaNotificationCenter.shared.post(L(.notif_added_to_favorites), tone: .success)
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
        // First dry queue becomes the Similar Songs seed.
        if infinitePlaySeed.isEmpty { infinitePlaySeed = queue }
        let existingIDs = Set(queue.map(\.id))
        func freshFrom(_ list: [Song]) -> [Song] {
            HiddenAlbumStore.shared.visibleSongs(list).filter { !existingIDs.contains($0.id) }
        }

        var fresh: [Song] = []

        if let name = autoplayArtistName {
            fresh = freshFrom((try? await client.topSongs(artistName: name, count: 50)) ?? [])
        }
        if fresh.isEmpty, autoplayMode == .algorithm {
            fresh = await algorithmicAutoplay(client: client, existingIDs: existingIDs)
        }
        if fresh.isEmpty, autoplayMode == .random {
            fresh = await styledRandomAutoplay(client: client, existingIDs: existingIDs)
        }
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

    private func algorithmicAutoplay(client: any MusicService, existingIDs: Set<String>) async -> [Song] {
        let currentGenre = currentSong?.genre?.lowercased()
        var pool: [Song] = []

        if let artistId = currentSong?.artistId,
           let info = try? await client.artistInfo(id: artistId) {
            let names = (info.similarArtist ?? []).prefix(3).map(\.name)
            pool += await topSongs(forArtists: names, client: client, each: 8)
        }

        pool += await topSongs(forArtists: topLocalArtists(limit: 3), client: client, each: 8)

        if let g = currentSong?.genre, !g.isEmpty {
            pool += (try? await client.songsByGenre(g, count: 25)) ?? []
        }

        var seen = Set<String>()
        let unique = HiddenAlbumStore.shared.visibleSongs(pool).filter {
            seen.insert($0.id).inserted && !existingIDs.contains($0.id)
        }

        if transitionMode == .automix {
            return automixSmoothAutoplay(unique, current: currentSong)
        }

        let matching = unique.filter { $0.genre?.lowercased() == currentGenre }.shuffled()
        let rest     = unique.filter { $0.genre?.lowercased() != currentGenre }.shuffled()
        return matching + rest
    }

    // Toggle-based autoplay (.random mode) fill, shaped by the user's
    // InfinitePlayStyle. Returns [] to fall through to the plain random fill.
    private func styledRandomAutoplay(client: any MusicService, existingIDs: Set<String>) async -> [Song] {
        func dedupe(_ list: [Song]) -> [Song] {
            var seen = Set<String>()
            return HiddenAlbumStore.shared.visibleSongs(list).filter {
                seen.insert($0.id).inserted && !existingIDs.contains($0.id)
            }
        }

        let seed = infinitePlaySeed.isEmpty ? [currentSong].compactMap { $0 } : infinitePlaySeed

        switch InfinitePlayStyle.current {
        case .random:
            return []   // plain random fallback handles it

        case .similar:
            var pool: [Song] = []
            let artistNames = Array(Set(seed.compactMap { $0.artist?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty })).prefix(4)
            pool += await topSongs(forArtists: Array(artistNames), client: client, each: 8)
            let genres = Array(Set(seed.compactMap { $0.genre?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty })).prefix(2)
            for g in genres {
                pool += (try? await client.songsByGenre(g, count: 15)) ?? []
            }
            let unique = dedupe(pool)
            return transitionMode == .automix ? automixSmoothAutoplay(unique, current: currentSong) : unique.shuffled()

        case .sameGenre:
            let genre = (currentSong?.genre ?? seed.first?.genre)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let genre, !genre.isEmpty else { return [] }
            let unique = dedupe((try? await client.songsByGenre(genre, count: 40)) ?? [])
            return transitionMode == .automix ? automixSmoothAutoplay(unique, current: currentSong) : unique.shuffled()
        }
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

        switch PlaybackTransitionSettings.style {
        case "tight":
            let lead = Array(sameArtist.prefix(4)) + Array(sameGenre.prefix(12))
            let tail = Array(sameArtist.dropFirst(4)) + Array(sameGenre.dropFirst(12)) + rest
            return lead + tail.shuffled()
        case "wide":
            let lead = Array(sameGenre.prefix(4)) + Array(rest.prefix(6))
            let tail = sameArtist + Array(sameGenre.dropFirst(4)) + Array(rest.dropFirst(6))
            return lead.shuffled() + tail.shuffled()
        default:
            let lead = Array(sameArtist.prefix(2)) + Array(sameGenre.prefix(8))
            let tail = Array(sameArtist.dropFirst(2)) + Array(sameGenre.dropFirst(8)) + rest
            return lead + tail.shuffled()
        }
    }

    private func topLocalArtists(limit: Int) -> [String] {
        var counts: [String: Int] = [:]
        for e in StatsStore.shared.allEvents() { counts[e.artist, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.prefix(limit).map(\.key)
    }

    private func topSongs(forArtists names: [String], client: any MusicService, each: Int) async -> [Song] {
        guard !names.isEmpty else { return [] }
        let batches = await DeveloperExperiments.runConcurrently(names, defaultMaxConcurrent: names.count) { name in
            (try? await client.topSongs(artistName: name, count: each)) ?? []
        }
        return HiddenAlbumStore.shared.visibleSongs(batches.flatMap { $0 })
    }

    // MARK: - Private

    private func playCurrent() {
        guard !queue.isEmpty, currentIndex < queue.count else { return }
        let song = queue[currentIndex]
        playRequestID &+= 1
        let token = playRequestID

        // Plex needs the file part key cached before streamURL can serve the
        // original; warm it (only when streaming and not already ready) so we
        // never silently fall back to a transcode. The common case stays fully
        // synchronous, so playback latency is unchanged.
        if let client,
           DownloadService.shared.localURL(for: song) == nil,
           !client.streamMetadataReady(id: song.id) {
            Task { @MainActor [weak self] in
                await client.prepareForPlayback(id: song.id)
                guard let self, token == self.playRequestID else { return }
                self.startPlaying(song: song)
                self.warmUpcomingStreams()
            }
            return
        }

        startPlaying(song: song)
        warmUpcomingStreams()
    }

    // Pre-fetch stream metadata for the next couple of tracks so gapless/transition
    // preloads also serve the original file rather than a transcode (Plex caches
    // the file part key here). Best-effort and fire-and-forget.
    private func warmUpcomingStreams() {
        guard let client else { return }
        let upper = min(currentIndex + 3, queue.count)
        guard currentIndex + 1 < upper else { return }
        let ids = queue[(currentIndex + 1)..<upper]
            .filter { DownloadService.shared.localURL(for: $0) == nil && !client.streamMetadataReady(id: $0.id) }
            .map(\.id)
        guard !ids.isEmpty else { return }
        Task { @MainActor in
            for id in ids { await client.prepareForPlayback(id: id) }
        }
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

        let item: AVPlayerItem
        if gapless != "off",
           let preloaded = gaplessNextItem,
           let preloadedURL = (preloaded.asset as? AVURLAsset)?.url,
           preloadedURL == url {
            item = preloaded
            gaplessNextItem = nil
        } else {
            item = makePlayerItem(url: url)
        }

        applyEqualizer(to: item)

        if gapless == "on" {
            player.removeAllItems()
            player.insert(item, after: nil)
        } else {
            player.replaceCurrentItem(with: item)
        }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        applyReplayGain(for: song)
        currentSong = song
        isPlaying = true
        currentTime = 0
        duration = 0
        currentArtwork = nil
        currentAnimatedArtwork = nil
        currentLiveArtwork = nil
        loggedSongIDs.remove(song.id)

        if song.starred != nil {
            starredIDs.insert(song.id)
        }

        updateNowPlaying()
        Task { await loadArtwork(for: song) }
        Task { await loadDuration(from: item) }
        scheduleGaplessPreload()
        ensureAutoplayPreloadedIfNeeded()
        if Date() >= transitionSuppressedUntil {
            prepareTransitionPlanIfNeeded()
        }
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
        let nextItem = makePlayerItem(url: url)
        applyEqualizer(to: nextItem)
        gaplessNextItem = nextItem
        if gapless == "on" {
            player.insert(nextItem, after: player.currentItem)
        }
        AppLogger.shared.log("⏭ Gapless pre-buffer: '\(nextSong.title)' [mode=\(gapless)]", category: .playback)
    }

    private func prepareTransitionPlanIfNeeded() {
        // Performance Mode "Simple Transitions" forces plain track changes (no
        // crossfade/AutoMix dual-player work) without touching the user's setting
        guard !PerformanceMode.simpleTransitions else {
            resetPreparedTransitionPlan()
            return
        }
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

        if primedSongID != nil, primedSongID != next.id { clearPriming() }
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
                "🌀 AutoMix plan: \(current.title) > \(next.title), \(String(format: "%.1f", plan.duration))s, lead \(String(format: "%.1f", plan.startLead))s, seek \(String(format: "%.1f", plan.nextStart))s [\(plan.reason)]",
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

    private func suppressTransitionsBriefly() {
        transitionSuppressedUntil = Date().addingTimeInterval(2.0)
        resetPreparedTransitionPlan()
    }

    private func makeAutoMixPlan(
        current: Song,
        next: Song,
        fallback: PlaybackTransitionPlan
    ) async -> PlaybackTransitionPlan {
        let sameAlbum = current.albumId != nil && current.albumId == next.albumId

        // One cached analysis per track.
        let a = await AutoMixAudioAnalyzer.shared.analysis(
            songID: current.id,
            localURL: DownloadService.shared.localURL(for: current),
            remoteURL: client?.originalStreamURL(id: current.id),
            fileExtension: current.suffix,
            taggedBPM: current.bpm.flatMap { $0 > 0 ? Double($0) : nil }
        )
        let b = await AutoMixAudioAnalyzer.shared.analysis(
            songID: next.id,
            localURL: DownloadService.shared.localURL(for: next),
            remoteURL: client?.originalStreamURL(id: next.id),
            fileExtension: next.suffix,
            taggedBPM: next.bpm.flatMap { $0 > 0 ? Double($0) : nil }
        )

        var reasons: [String] = []
        var duration = min(PlaybackTransitionSettings.maxBlend, sameAlbum ? min(fallback.duration, 4.0) : fallback.duration)
        var nextStart: TimeInterval = 0
        var startLead = max(1.5, duration)

        // 1) Trim dead air on either side of the handoff.
        let trailing = min(10, max(0, a.trailingSilence))
        let trailingPad = PlaybackTransitionSettings.silenceTrimEnabled && trailing > 0.35 ? trailing - 0.1 : 0
        if PlaybackTransitionSettings.silenceTrimEnabled {
            let leading = min(8, max(0, b.leadingSilence))
            if leading > 0.35 { nextStart = max(0, leading - 0.08); reasons.append("silence trim") }
            else if trailing > 0.35 { reasons.append("silence trim") }
        }

        // 1b) Sequential album tracks get a near-gapless handoff.
        let sequentialAlbum = sameAlbum
            && current.track != nil && next.track != nil
            && next.track == (current.track ?? 0) + 1
            && (current.discNumber ?? 1) == (next.discNumber ?? 1)
        if sequentialAlbum {
            reasons.append("album handoff")
            let handoff = min(duration, 1.2)
            return PlaybackTransitionPlan(
                mode: .automix,
                duration: handoff,
                startLead: max(0.9, handoff + trailingPad),
                nextStart: nextStart,
                reason: reasons.joined(separator: ", "),
                oldRate: 1,
                nextRate: 1
            )
        }

        // 1c) Cold endings cut tight.
        if a.endsCold {
            duration = min(duration, 3.2)
            reasons.append("cold end")
        }
        // Two arrhythmic tracks get a longer wash.
        else if a.grid == nil, b.grid == nil {
            duration = min(PlaybackTransitionSettings.maxBlend, max(duration, 10))
            reasons.append("long fade")
        }

        // 2) Harmonic match changes overlap length, not beat matching.
        if PlaybackTransitionSettings.harmonicEnabled, let ka = a.key, let kb = b.key, !sameAlbum {
            let compat = MusicalKey.compatibility(ka, kb)
            if compat >= 0.8 { reasons.append("key \(ka.camelot)→\(kb.camelot)") }
            else if compat >= 0.45 { duration = max(3, duration * 0.9); reasons.append("key \(ka.camelot)→\(kb.camelot)") }
            else { duration = max(2.5, duration * 0.7); reasons.append("key \(ka.camelot)/\(kb.camelot) tight") }
        }

        // 3) Beat match when a small outgoing-track bend can lock the grids.
        var oldRate: Float = 1
        var beatAligned = false
        var outPeriod: TimeInterval = 0, outPhase: TimeInterval = 0
        var inPeriod: TimeInterval = 0, inPhase: TimeInterval = 0
        if PlaybackTransitionSettings.tempoMatchEnabled, !sameAlbum,
           let ga = a.grid, let gb = b.grid,
           let r = AutoMixTempo.outgoingRate(currentBPM: ga.bpm, nextBPM: gb.bpm) {
            oldRate = r.rate
            reasons.append("BPM \(Int(r.currentBPM.rounded()))→\(Int(r.nextBPM.rounded()))")
            if PlaybackTransitionSettings.beatAlignEnabled {
                beatAligned = true
                outPeriod = ga.period; outPhase = ga.phase
                inPeriod = gb.period; inPhase = gb.phase
                // Start the incoming on a strong downbeat, past sparse intro if needed.
                var entryFloor = max(nextStart, gb.firstStrongBeat)
                if PlaybackTransitionSettings.sweetSpotEnabled, b.mixInPoint > entryFloor + 1.0 {
                    entryFloor = b.mixInPoint
                    reasons.append(String(format: "intro +%.0fs", b.mixInPoint))
                }
                var entry = gb.downbeat(atOrAfter: entryFloor)
                // Prefer a nearby 4-bar phrase boundary.
                let bar = gb.period * 4
                let phrase = bar * 4
                let anchor = gb.downbeat(atOrAfter: gb.firstStrongBeat)
                if phrase > 0, entry > anchor + 0.01 {
                    let k = ((entry - anchor) / phrase).rounded(.up)
                    let phraseEntry = anchor + k * phrase
                    if phraseEntry - entry <= bar * 2 + 0.01 { entry = phraseEntry }
                }
                nextStart = entry
                // Bar-counted blend length.
                if bar > 0.5 {
                    let bars = max(1, (duration / bar).rounded())
                    duration = min(PlaybackTransitionSettings.maxBlend, max(2, bars * bar))
                }
                reasons.append("beat-locked")
            }
        }

        // 4) Vocal guard: avoid stacking two vocal lines.
        if a.duration > 0,
           let vocalTail = a.vocalTailEnd, vocalTail > a.duration - 3,
           let vocalIn = b.vocalIntroStart, vocalIn < nextStart + duration + 1 {
            duration = min(duration, 4)
            reasons.append("vocal guard")
        }

        // 5) Open point: blend length, silence pad, and optional outro skip.
        startLead = min(PlaybackTransitionSettings.maxBlend + 8, max(1.5, duration + trailingPad))
        if PlaybackTransitionSettings.sweetSpotEnabled, a.mixOutPoint > 0, a.duration > 0 {
            var mixOut = a.mixOutPoint
            if let vocalTail = a.vocalTailEnd, vocalTail > mixOut, vocalTail < a.duration - 2 {
                mixOut = min(a.duration - 2, vocalTail + 0.3)
            }
            let lead = a.duration - mixOut
            if lead > startLead + 1.5 {
                startLead = min(45, lead)
                reasons.append(String(format: "outro −%.0fs", lead - duration))
            }
        }
        if beatAligned, outPeriod > 0 {
            startLead = min(startLead + outPeriod * 4, max(startLead, PlaybackTransitionSettings.maxBlend + 8))
        }

        // 6) Loudness match when ReplayGain is not already handling it.
        var volumeMatch: Float = 1
        if PlaybackTransitionSettings.loudnessMatchEnabled, a.rms > 0, b.rms > 0 {
            let rgMode = UserDefaults.standard.string(forKey: "replayGainMode") ?? "off"
            let rgHandled = rgMode != "off" && next.replayGain != nil
            let ratio = a.rms / b.rms
            if !rgHandled, ratio < 0.95 {
                volumeMatch = max(0.7, ratio)
                reasons.append("level match")
            }
        }

        if reasons.isEmpty { reasons.append("metadata") }
        return PlaybackTransitionPlan(
            mode: .automix,
            duration: duration,
            startLead: startLead,
            nextStart: nextStart,
            reason: reasons.joined(separator: ", "),
            oldRate: oldRate,
            nextRate: 1,
            beatAligned: beatAligned,
            beatsPerBar: 4,
            outBeatPeriod: outPeriod,
            outBeatPhase: outPhase,
            inBeatPeriod: inPeriod,
            inBeatPhase: inPhase,
            volumeMatch: volumeMatch
        )
    }

    // BPM for a song, preferring OpenSubsonic/file metadata, then on-device audio
    // analysis of a downloaded copy, and finally a best-effort analysis of a short
    // prefix fetched from the server so streamed (un-downloaded) tracks still
    // tempo-match. Results (including failures) are cached per song id.
    private func tempoBPM(for song: Song) async -> Double? {
        if let tagged = song.bpm, tagged > 0 { return Double(tagged) }
        let local = DownloadService.shared.localURL(for: song)
        let remote = client?.originalStreamURL(id: song.id)
        return await AutoMixAudioAnalyzer.shared.bpm(
            songID: song.id,
            localURL: local,
            remoteURL: remote,
            fileExtension: song.suffix
        )
    }

    // Public BPM lookup used by the AutoMix preview UI in Settings.
    func estimatedBPM(for song: Song) async -> Double? {
        await tempoBPM(for: song)
    }

    // Full analysis for the Settings preview.
    func autoMixAnalysis(for song: Song) async -> AutoMixTrackAnalysis {
        await AutoMixAudioAnalyzer.shared.analysis(
            songID: song.id,
            localURL: DownloadService.shared.localURL(for: song),
            remoteURL: client?.originalStreamURL(id: song.id),
            fileExtension: song.suffix,
            taggedBPM: song.bpm.flatMap { $0 > 0 ? Double($0) : nil }
        )
    }

    private func checkScheduledTransition() {
        guard transitionMode != .off,
              isPlaying,
              !isTransitioning,
              !transitionArmed,
              transitionTask == nil,
              Date() >= transitionSuppressedUntil,
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
        guard remaining.isFinite, remaining > 0.25 else { return }
        // Pre-buffer the next track before the blend opens.
        let primeLead: TimeInterval = 6
        if remaining <= plan.startLead + primeLead {
            primeNext(next, plan: plan)
        }
        guard remaining <= plan.startLead else { return }
        armTransition(plan, nextSong: next, remaining: remaining)
    }

    // For beat-locked plans, wait for the outgoing downbeat before starting.
    private func armTransition(_ plan: PlaybackTransitionPlan, nextSong: Song, remaining: TimeInterval) {
        guard !transitionArmed, !isTransitioning else { return }
        guard plan.beatAligned, plan.outBeatPeriod > 0.2 else {
            startPlannedTransition(plan, nextSong: nextSong)
            return
        }
        let grid = AutoMixBeatGrid(bpm: 60.0 / plan.outBeatPeriod, phase: plan.outBeatPhase, firstStrongBeat: 0)
        let now = liveTime()
        // Need enough outgoing tail left after the wait.
        let minOverlap = min(2.5, max(1.2, plan.duration * 0.25))
        var target = grid.downbeat(atOrAfter: now + 0.05, beatsPerBar: plan.beatsPerBar)
        if target - now > remaining - minOverlap {
            target = grid.beat(atOrAfter: now + 0.05)   // settle for the next beat
        }
        let delay = target - now
        guard delay > 0.06, delay < remaining - 0.5 else {
            startPlannedTransition(plan, nextSong: nextSong)
            return
        }
        transitionArmed = true
        transitionArmTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.transitionArmed = false
            self.transitionArmTask = nil
            guard !self.isTransitioning, self.isPlaying, self.transitionMode != .off,
                  self.currentIndex + 1 < self.queue.count,
                  self.queue[self.currentIndex + 1].id == nextSong.id else { return }
            self.startPlannedTransition(plan, nextSong: nextSong)
        }
    }

    // Muted pre-buffer on the inactive player.
    private func primeNext(_ song: Song, plan: PlaybackTransitionPlan) {
        guard primedSongID != song.id,
              !isTransitioning,
              let urlInfo = playbackURL(for: song) else { return }
        let p = inactivePlayer
        let item = makePlayerItem(url: urlInfo.url)
        applyEqualizer(to: item)
        primedBassID = attachBassSwap(to: item)
        p.pause()
        p.removeAllItems()
        p.insert(item, after: nil)
        p.volume = 0
        if plan.nextStart > 0 {
            let tol = CMTime(seconds: 0.05, preferredTimescale: 600)
            p.seek(to: CMTime(seconds: plan.nextStart, preferredTimescale: 600), toleranceBefore: tol, toleranceAfter: tol)
        }
        p.play()   // muted warmup
        primedSongID = song.id
        AppLogger.shared.log("🔥 Prime next: '\(song.title)'", category: .playback)
    }

    private func clearPriming() {
        guard primedSongID != nil else { return }
        primedSongID = nil
        if primedBassID != 0 { AutoMixBassSwap.shared.deactivate(primedBassID); primedBassID = 0 }
        if !isTransitioning {
            inactivePlayer.pause()
            inactivePlayer.removeAllItems()
            inactivePlayer.volume = 0
        }
    }

    private func startPlannedTransition(_ plan: PlaybackTransitionPlan, nextSong: Song) {
        guard !isTransitioning,
              currentIndex + 1 < queue.count,
              let urlInfo = playbackURL(for: nextSong) else { return }

        let oldPlayer = activePlayer
        let newPlayer = inactivePlayer
        // Non-unity rate means tempo bend; do not switch pitch algorithms mid-play.
        let tempoActive = abs(plan.oldRate - 1) >= 0.01 || abs(plan.nextRate - 1) >= 0.01

        // Reuse a primed player when possible; otherwise build the item now.
        let nextItem: AVPlayerItem
        var incomingStart = plan.nextStart
        // Pre-compensate the tiny drift before the tempo bend engages.
        let lockShift = beatLockSeekShift(plan: plan)
        let inGrid: AutoMixBeatGrid? = (plan.beatAligned && plan.inBeatPeriod > 0.2)
            ? AutoMixBeatGrid(bpm: 60.0 / plan.inBeatPeriod, phase: plan.inBeatPhase, firstStrongBeat: 0)
            : nil
        if primedSongID == nextSong.id, let primed = newPlayer.currentItem {
            nextItem = primed
            newPlayer.volume = 0
            currentBassID = primedBassID
            primedBassID = 0
            // Nudge the muted primed track onto its next downbeat.
            if let inGrid {
                let pIn = newPlayer.currentTime().seconds
                if pIn.isFinite {
                    let db = max(0, inGrid.downbeat(atOrAfter: pIn + 0.02, beatsPerBar: plan.beatsPerBar) + lockShift)
                    let tol = CMTime(seconds: 0.012, preferredTimescale: 600)
                    newPlayer.seek(to: CMTime(seconds: db, preferredTimescale: 600), toleranceBefore: tol, toleranceAfter: tol)
                    incomingStart = db
                }
            }
        } else {
            nextItem = makePlayerItem(url: urlInfo.url)
            applyEqualizer(to: nextItem)
            currentBassID = attachBassSwap(to: nextItem)
            newPlayer.pause()
            newPlayer.removeAllItems()
            newPlayer.insert(nextItem, after: nil)
            newPlayer.volume = 0
            if inGrid != nil { incomingStart = max(0, incomingStart + lockShift) }
            if incomingStart > 0 {
                // Small tolerance keeps this seek fast.
                let seekTime = CMTime(seconds: incomingStart, preferredTimescale: 600)
                let tol = CMTime(seconds: 0.05, preferredTimescale: 600)
                newPlayer.seek(to: seekTime, toleranceBefore: tol, toleranceAfter: tol)
            }
            newPlayer.play()
        }
        primedSongID = nil
        AutoMixBassSwap.shared.activate(currentBassID)

        if urlInfo.isLocal { DownloadService.shared.markPlayed(nextSong.id) }
        let oldStartVolume = oldPlayer.volume
        // plan.volumeMatch ducks a hotter incoming master to the outgoing's level
        // (Sound Check-style); 1.0 whenever ReplayGain already normalizes it.
        let newTargetVolume = replayGainVolume(for: nextSong) * plan.volumeMatch

        activePlayer = newPlayer
        targetVolume = newTargetVolume
        currentIndex += 1
        currentSong = nextSong
        isPlaying = true
        currentTime = incomingStart
        duration = 0
        currentArtwork = nil
        currentAnimatedArtwork = nil
        currentLiveArtwork = nil
        loggedSongIDs.remove(nextSong.id)
        if nextSong.starred != nil { starredIDs.insert(nextSong.id) }
        resetPreparedTransitionPlan()

        // Incoming stays at true tempo.
        newPlayer.play()
        updateNowPlaying()
        Task { await loadArtwork(for: nextSong) }
        Task { await loadDuration(from: nextItem) }
        ensureAutoplayPreloadedIfNeeded()
        prepareTransitionPlanIfNeeded()

        isTransitioning = true
        isMixing = true
        let fadeDuration = max(0.75, plan.duration)
        AppLogger.shared.log("🌀 \(plan.mode.settingsLabel): '\(nextSong.title)' over \(String(format: "%.1f", fadeDuration))s [\(plan.reason)]", category: .playback)
        transitionTask = Task { @MainActor [weak self, weak oldPlayer, weak newPlayer] in
            guard let self, let oldPlayer, let newPlayer else { return }

            // Keep the outgoing audible while the incoming starts rolling.
            let warmDeadline = Date().addingTimeInterval(3.0)
            while Date() < warmDeadline {
                if Task.isCancelled { return }
                oldPlayer.volume = oldStartVolume
                newPlayer.volume = 0
                let item = newPlayer.currentItem
                let ready = item?.status == .readyToPlay
                    && (item?.isPlaybackLikelyToKeepUp ?? false)
                    && newPlayer.timeControlStatus == .playing
                if ready { break }
                let oldDur = oldPlayer.currentItem?.duration.seconds ?? 0
                let oldNow = oldPlayer.currentTime().seconds
                if oldDur.isFinite, oldNow.isFinite, oldDur - oldNow <= 0.4 { break }
                try? await Task.sleep(nanoseconds: 30_000_000)
            }

            let steps = max(12, Int(fadeDuration * 30))
            var bentOutgoing = false
            for step in 0...steps {
                if Task.isCancelled { return }
                let x = Double(step) / Double(steps)
                // Equal-power curve; AutoMix differs by shape and analysis extras.
                let phase = plan.mode == .crossfade ? x : x * x * (3 - 2 * x)
                let theta = phase * (Double.pi / 2)
                oldPlayer.volume = oldStartVolume * Float(cos(theta))
                newPlayer.volume = newTargetVolume * Float(sin(theta))
                // Bend the outgoing once after it is already ducking.
                if tempoActive, !bentOutgoing, x >= 0.15 {
                    bentOutgoing = true
                    oldPlayer.rate = plan.oldRate
                }
                // Open incoming bass as it takes over.
                if self.currentBassID != 0 {
                    AutoMixBassSwap.shared.setCutoff(self.bassSwapCutoff(at: x), id: self.currentBassID)
                }
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
            guard self.player === newPlayer else { return }
            oldPlayer.pause()
            oldPlayer.removeAllItems()
            oldPlayer.rate = 1
            oldPlayer.volume = 0
            newPlayer.rate = 1
            newPlayer.volume = newTargetVolume
            if self.currentBassID != 0 {
                AutoMixBassSwap.shared.deactivate(self.currentBassID)
                self.currentBassID = 0
            }
            self.isTransitioning = false
            self.isMixing = false
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

    private func cancelTransitionPlayback(keepPaused: Bool = false) {
        transitionArmTask?.cancel()
        transitionArmTask = nil
        transitionArmed = false
        transitionTask?.cancel()
        transitionTask = nil
        isTransitioning = false
        isMixing = false
        if currentBassID != 0 { AutoMixBassSwap.shared.deactivate(currentBassID); currentBassID = 0 }
        if primedBassID != 0 { AutoMixBassSwap.shared.deactivate(primedBassID); primedBassID = 0 }
        primedSongID = nil
        let shouldKeepPaused = keepPaused || !isPlaying
        primaryPlayer.rate = shouldKeepPaused ? 0 : 1
        secondaryPlayer.rate = shouldKeepPaused ? 0 : 1
        inactivePlayer.pause()
        inactivePlayer.removeAllItems()
        inactivePlayer.volume = 0
        player.volume = targetVolume
        if shouldKeepPaused { pauseAllPlayers() }
    }

    private func pauseAllPlayers() {
        primaryPlayer.pause()
        secondaryPlayer.pause()
    }

    private func loadArtwork(for song: Song) async {
        let url = client?.coverArtURL(id: song.coverArt, size: 600)
        let image = await ArtworkLoader.shared.image(for: url, maxPixelSize: 600)
        guard currentSong?.id == song.id else { return }
        currentArtwork = image
        if let image {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }

        let liveEnabled = LiveArtworkSettings.shouldShowAnimatedArtwork
        guard liveEnabled else { return }

        var live = await ArtworkLoader.shared.liveArtwork(for: client?.coverArtURL(id: song.coverArt))
        if live == nil, let albumID = song.albumId {
            let albumCoverArt: String?
            if queueSourceAlbum?.id == albumID {
                albumCoverArt = queueSourceAlbum?.coverArt
            } else if let client {
                albumCoverArt = (try? await client.album(id: albumID))?.coverArt
            } else {
                albumCoverArt = nil
            }
            if albumCoverArt != song.coverArt {
                live = await ArtworkLoader.shared.liveArtwork(for: client?.coverArtURL(id: albumCoverArt))
            }
        }
        guard currentSong?.id == song.id else { return }
        currentLiveArtwork = live
        currentAnimatedArtwork = live?.animatedImage
        applyNowPlayingAnimatedArtwork(live)
        if live?.videoURL != nil {
            scheduleAnimatedArtworkReattach(for: song)
        }
    }

    // The OS's supportedAnimatedArtworkKeys set reads empty right at song start and
    // populates a beat later; re-attach the (already built) animated artwork once it
    // turns on so the lock screen actually picks it up.
    private func scheduleAnimatedArtworkReattach(for song: Song) {
        guard #available(iOS 26.0, *) else { return }
        Task { @MainActor [weak self] in
            for delaySeconds in [0.4, 1.0, 2.0, 4.0] {
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                guard let self, self.currentSong?.id == song.id else { return }
                let supported = MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys
                guard supported.contains(MPNowPlayingInfoProperty3x4AnimatedArtwork)
                    || supported.contains(MPNowPlayingInfoProperty1x1AnimatedArtwork) else { continue }
                self.applyNowPlayingAnimatedArtwork(self.currentLiveArtwork)
                return
            }
        }
    }

    private func loadDuration(from item: AVPlayerItem) async {
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
                if self.sleepEndsAtTrackEnd {
                    self.player.pause()
                    self.isPlaying = false
                    self.cancelSleepTimer()
                    self.updateNowPlaying()
                    return
                }
                let gapless = UserDefaults.standard.string(forKey: "gaplessPlayback") ?? "off"
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

    private func addInterruptionObserver() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let info = note.userInfo,
                      let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
                switch type {
                case .began:
                    self.isPlaying = false
                    self.updateNowPlaying()
                case .ended:
                    let resumePref = UserDefaults.standard.object(forKey: "resumeAfterInterruption") as? Bool ?? true
                    let shouldResume: Bool
                    if let rawOptions = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                        shouldResume = resumePref && AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
                    } else {
                        shouldResume = false
                    }
                    if shouldResume, self.player.rate == 0, self.currentSong != nil {
                        try? AVAudioSession.sharedInstance().setActive(true)
                        self.player.play()
                        self.isPlaying = true
                        self.updateNowPlaying()
                    }
                @unknown default:
                    break
                }
            }
        }
    }

    private func addRouteChangeObserver() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let rawReason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else { return }
                if reason == .oldDeviceUnavailable {
                    // System automatically pauses audio when headphones are unplugged; sync state.
                    self.isPlaying = false
                    self.updateNowPlaying()
                }
            }
        }
    }

    private func addStallObserver() {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.isPlaying, let stalledItem = note.object as? AVPlayerItem,
                      stalledItem === self.player.currentItem else { return }
                // Re-activate the session and nudge the player out of a stall so
                // background streaming (e.g. after a brief network drop) recovers.
                try? AVAudioSession.sharedInstance().setActive(true)
                self.player.play()
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
        guard #available(iOS 26.0, *) else { return }
        addSupportedAnimatedArtwork(to: &info, live: live)
    }

    @available(iOS 26.0, *)
    private func addSupportedAnimatedArtwork(to info: inout [String: Any], live: LiveArtworkAsset?) {
        // iOS 26/27 expose the PORTRAIT 3x4 lock-screen slot (square 1x1 isn't
        // offered); prefer it, fall back to 1x1 only if that's all the OS lists.
        let candidateKeys = [
            MPNowPlayingInfoProperty3x4AnimatedArtwork,
            MPNowPlayingInfoProperty1x1AnimatedArtwork
        ]
        for k in candidateKeys { info.removeValue(forKey: k) }
        let supportedKeys = MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys
        let key = candidateKeys.first { supportedKeys.contains($0) }
            ?? (LiveArtworkSettings.rawAnimatedArtworkEnabled ? MPNowPlayingInfoProperty3x4AnimatedArtwork : nil)
        guard let live, let videoURL = live.videoURL else {
            AppLogger.shared.log("Lock-screen animated artwork: not attached (live=\(live != nil), video=\(live?.videoURL != nil), supportedKeys=\(supportedKeys))", category: .playback)
            return
        }
        guard let key else {
            AppLogger.shared.log("Lock-screen animated artwork: OS reports no usable key — animated now-playing won't show (supportedKeys=\(supportedKeys))", category: .playback, level: .warning)
            return
        }
        AppLogger.shared.log("Lock-screen animated artwork: attached ✓ key=\(key) (\(videoURL.lastPathComponent))", category: .playback)
        let preview = live.previewImage
        // If the system never requests the video, it is gating animation, not format.
        let animated = MPMediaItemAnimatedArtwork(
            artworkID: live.artworkID,
            previewImageRequestHandler: { _, completion in
                AppLogger.shared.log("Lock-screen animated artwork: system REQUESTED preview image ✓", category: .playback)
                completion(preview)
            },
            videoAssetFileURLRequestHandler: { _, completion in
                AppLogger.shared.log("Lock-screen animated artwork: system REQUESTED video asset ✓ (\(videoURL.lastPathComponent))", category: .playback)
                completion(videoURL)
            }
        )
        info[key] = animated
    }

    private func updateNowPlayingTime() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

// On-device analyser behind AutoMix. Results are cached per song id.
private actor AutoMixAudioAnalyzer {
    static let shared = AutoMixAudioAnalyzer()

    private var analysisByID: [String: AutoMixTrackAnalysis] = [:]
    private let silenceThreshold: Float = 0.003
    // beat grid only trusts the first couple of minutes (phase smears over longer
    // spans); the structure pass (mix-in/out, RMS) wants the whole track
    private let gridCapSeconds: TimeInterval = 120
    private let envelopeCapSeconds: TimeInterval = 1200
    private let chromaCapSeconds: TimeInterval = 90

    private static var harmonicEnabled: Bool {
        if UserDefaults.standard.object(forKey: "automixHarmonic") == nil { return true }
        return UserDefaults.standard.bool(forKey: "automixHarmonic")
    }

    private static var sweetSpotEnabled: Bool {
        if UserDefaults.standard.object(forKey: "automixSweetSpot") == nil { return true }
        return UserDefaults.standard.bool(forKey: "automixSweetSpot")
    }

    // MARK: Public

    // Full per-track analysis, cached per song id. `taggedBPM` is the server/library
    // tempo when known; it's trusted for the grid's tempo while phase still comes
    // from the audio.
    func analysis(songID: String, localURL: URL?, remoteURL: URL?, fileExtension: String?, taggedBPM: Double?) async -> AutoMixTrackAnalysis {
        if let cached = analysisByID[songID] { return cached }

        var fileURL: URL?
        var isPrefix = false
        var tempToDelete: URL?
        if let localURL, localURL.isFileURL {
            fileURL = localURL
        } else if let remoteURL, let temp = await downloadPrefix(remoteURL, fileExtension: fileExtension) {
            fileURL = temp; isPrefix = true; tempToDelete = temp
        }
        guard let fileURL else {
            analysisByID[songID] = .zero
            return .zero
        }
        defer { if let tempToDelete { try? FileManager.default.removeItem(at: tempToDelete) } }

        let env = await decodeEnergyEnvelope(url: fileURL, isPrefix: isPrefix)
        var result = AutoMixTrackAnalysis()
        result.leadingSilence = env.silence.leadingSilence
        result.trailingSilence = env.silence.trailingSilence
        var effectiveTag = taggedBPM
        if effectiveTag == nil { effectiveTag = await readBPMMetadata(url: fileURL) }
        let gridEnergy = env.energy.last.map { $0.time > gridCapSeconds } == true
            ? Array(env.energy.prefix(while: { $0.time <= gridCapSeconds }))
            : env.energy
        result.grid = AutoMixDSP.beatGrid(energy: gridEnergy, taggedBPM: effectiveTag)

        // Structure: loudness + sweet-spot mix points. A streamed prefix has no
        // tail, so only the entry point (and a loudness estimate) applies there.
        if !env.energy.isEmpty {
            result.rms = env.energy.reduce(Float(0)) { $0 + $1.value } / Float(env.energy.count)
            let analysedSpan = isPrefix ? (env.energy.last?.time ?? 0) : env.duration
            result.mixInPoint = AutoMixDSP.mixInPoint(energy: env.energy, duration: analysedSpan)
            if !isPrefix {
                result.duration = env.duration
                result.mixOutPoint = AutoMixDSP.mixOutPoint(energy: env.energy, duration: env.duration)
                result.endsCold = AutoMixDSP.endsCold(
                    energy: env.energy,
                    duration: env.duration,
                    trailingSilence: env.silence.trailingSilence
                )
            }
        }
        // One FFT pass over the head of the file feeds both the key estimate and
        // the vocal-presence heuristic; a second, short pass scans the tail for the
        // last sung moment (local full files only — a prefix has no tail).
        if Self.harmonicEnabled || Self.sweetSpotEnabled {
            let head = await decodeSpectral(
                url: fileURL,
                capSeconds: chromaCapSeconds,
                includeChroma: Self.harmonicEnabled
            )
            if let chroma = head.chroma {
                result.key = AutoMixDSP.estimateKey(chroma: chroma)
            }
            if Self.sweetSpotEnabled {
                result.vocalIntroStart = AutoMixDSP.firstVocalActivity(frames: head.frames)
                if !isPrefix, result.duration > 50 {
                    let tail = await decodeSpectral(
                        url: fileURL,
                        startingAt: max(0, result.duration - 40),
                        capSeconds: 45,
                        includeChroma: false
                    )
                    result.vocalTailEnd = AutoMixDSP.lastVocalActivity(frames: tail.frames)
                }
            }
        }

        analysisByID[songID] = result
        return result
    }

    // BPM for a song id (used by the Settings preview). Reuses the cached analysis.
    func bpm(songID: String, localURL: URL?, remoteURL: URL?, fileExtension: String?) async -> Double? {
        let a = await analysis(songID: songID, localURL: localURL, remoteURL: remoteURL, fileExtension: fileExtension, taggedBPM: nil)
        return a.grid?.bpm
    }

    // MARK: Decode

    // Download the first few MB of a remote track to a temp file. A truncated
    // stream is still readable from the start, which is all the analyser needs.
    private func downloadPrefix(_ url: URL, fileExtension: String?) async -> URL? {
        let prefixBytes = 3 * 1024 * 1024  // ~3 MB: enough audio for tempo + key
        var request = URLRequest(url: url)
        request.setValue("bytes=0-\(prefixBytes - 1)", forHTTPHeaderField: "Range")
        request.timeoutInterval = 20

        let data: Data
        do {
            let (payload, _) = try await URLSession.shared.data(for: request)
            data = payload
        } catch {
            return nil
        }
        guard data.count > 64 * 1024 else { return nil }

        let ext = (fileExtension?.isEmpty == false) ? fileExtension! : "mp3"
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("automix-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        do {
            try data.write(to: temp, options: .atomic)
        } catch {
            return nil
        }
        return temp
    }

    // Energy envelope plus leading/trailing silence from one decode pass.
    private func decodeEnergyEnvelope(url: URL, isPrefix: Bool) async -> (energy: [AutoMixEnergyPoint], silence: AudioSilenceProfile, duration: TimeInterval) {
        let asset = AVURLAsset(url: url)
        let durationSeconds = (try? await asset.load(.duration))?.seconds ?? 0
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { return ([], .zero, 0) }
        let threshold = silenceThreshold
        let cap = envelopeCapSeconds
        return await DeveloperExperiments.runBlocking(qos: .userInitiated) {
            Self.decodeEnergyEnvelopeSync(
                asset: asset,
                track: track,
                isPrefix: isPrefix,
                durationSeconds: durationSeconds,
                silenceThreshold: threshold,
                envelopeCapSeconds: cap
            )
        }
    }

    private nonisolated static func decodeEnergyEnvelopeSync(
        asset: AVURLAsset,
        track: AVAssetTrack,
        isPrefix: Bool,
        durationSeconds: TimeInterval,
        silenceThreshold: Float,
        envelopeCapSeconds: TimeInterval
    ) -> (energy: [AutoMixEnergyPoint], silence: AudioSilenceProfile, duration: TimeInterval) {
        guard let reader = try? AVAssetReader(asset: asset) else { return ([], .zero, 0) }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return ([], .zero, 0) }
        reader.add(output)
        guard reader.startReading() else { return ([], .zero, 0) }

        var energy: [AutoMixEnergyPoint] = []
        var firstAudible: TimeInterval?
        var lastAudible: TimeInterval?

        while !Task.isCancelled, let sampleBuffer = output.copyNextSampleBuffer() {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            var length = 0
            var rawPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(
                block, atOffset: 0, lengthAtOffsetOut: nil,
                totalLengthOut: &length, dataPointerOut: &rawPointer
            )
            guard status == kCMBlockBufferNoErr,
                  let rawPointer,
                  length >= MemoryLayout<Float>.size else { continue }

            let sampleCount = length / MemoryLayout<Float>.size
            let stride = max(1, sampleCount / 4096)
            let measured = rawPointer.withMemoryRebound(to: Float.self, capacity: sampleCount) { samples -> (mean: Float, peak: Float) in
                var sum: Float = 0, peak: Float = 0, count = 0, index = 0
                while index < sampleCount {
                    let v = abs(samples[index])
                    sum += min(1, v)
                    peak = max(peak, v)
                    count += 1
                    index += stride
                }
                return (count > 0 ? sum / Float(count) : 0, peak)
            }

            guard pts.isFinite else { continue }
            let sampleDuration = CMSampleBufferGetDuration(sampleBuffer).seconds
            if pts <= envelopeCapSeconds {
                let midpoint = pts + (sampleDuration.isFinite ? sampleDuration / 2 : 0)
                energy.append(AutoMixEnergyPoint(time: midpoint, value: measured.mean))
            }
            if measured.peak >= silenceThreshold {
                let end = sampleDuration.isFinite ? pts + sampleDuration : pts
                if firstAudible == nil { firstAudible = pts }
                lastAudible = max(lastAudible ?? end, end)
            }
        }

        let silence: AudioSilenceProfile
        if let firstAudible, let lastAudible {
            let leading = min(12, max(0, firstAudible))
            let trailing = isPrefix ? 0 : min(12, max(0, durationSeconds - lastAudible))
            silence = AudioSilenceProfile(leadingSilence: leading, trailingSilence: trailing)
        } else {
            silence = .zero
        }
        return (energy, silence, durationSeconds.isFinite ? max(0, durationSeconds) : 0)
    }

    // Downsampled FFT for chroma and vocal-band frames.
    private func decodeSpectral(
        url: URL,
        startingAt: TimeInterval? = nil,
        capSeconds: TimeInterval,
        includeChroma: Bool
    ) async -> (chroma: [Double]?, frames: [AutoMixSpectralFrame]) {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { return (nil, []) }
        return await DeveloperExperiments.runBlocking(qos: .userInitiated) {
            Self.decodeSpectralSync(
                asset: asset,
                track: track,
                startingAt: startingAt,
                capSeconds: capSeconds,
                includeChroma: includeChroma
            )
        }
    }

    private nonisolated static func decodeSpectralSync(
        asset: AVURLAsset,
        track: AVAssetTrack,
        startingAt: TimeInterval?,
        capSeconds: TimeInterval,
        includeChroma: Bool
    ) -> (chroma: [Double]?, frames: [AutoMixSpectralFrame]) {
        guard let reader = try? AVAssetReader(asset: asset) else { return (nil, []) }
        if let startingAt, startingAt > 0 {
            reader.timeRange = CMTimeRange(
                start: CMTime(seconds: startingAt, preferredTimescale: 600),
                duration: .positiveInfinity
            )
        }

        let sampleRate = 22_050.0
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: sampleRate
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return (nil, []) }
        reader.add(output)
        guard reader.startReading() else { return (nil, []) }

        let n = 8192
        let half = n / 2
        let log2n = vDSP_Length(13)
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return (nil, []) }
        defer { vDSP_destroy_fftsetup(setup) }

        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))

        // Pitch-class bins, restricted to the range useful for key finding.
        var binPitch = [Int](repeating: -1, count: half)
        var isMid = [Bool](repeating: false, count: half)
        var isAudible = [Bool](repeating: false, count: half)
        for k in 1..<half {
            let f = Double(k) * sampleRate / Double(n)
            isMid[k] = f >= 280 && f <= 3800
            isAudible[k] = f >= 65 && f <= 8000
            guard f >= 65, f <= 2100 else { continue }
            let midi = 69 + 12 * log2(f / 440)
            binPitch[k] = ((Int(midi.rounded()) % 12) + 12) % 12
        }

        var chroma = [Double](repeating: 0, count: 12)
        var frameChroma = [Double](repeating: 0, count: 12)
        var realp = [Float](repeating: 0, count: half)
        var imagp = [Float](repeating: 0, count: half)
        var mags = [Float](repeating: 0, count: half)
        var windowed = [Float](repeating: 0, count: n)
        var ring = [Float]()
        ring.reserveCapacity(n * 2)
        let hop = n / 2
        let maxSamples = Int(capSeconds * sampleRate)
        var consumed = 0
        var frames: [AutoMixSpectralFrame] = []
        let baseTime = startingAt ?? 0
        var frameIndex = 0

        func processFrame() {
            ring.withUnsafeBufferPointer { rb in
                vDSP_vmul(rb.baseAddress!, 1, window, 1, &windowed, 1, vDSP_Length(n))
            }
            realp.withUnsafeMutableBufferPointer { rp in
                imagp.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    windowed.withUnsafeBufferPointer { wb in
                        wb.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { typed in
                            vDSP_ctoz(typed, 2, &split, 1, vDSP_Length(half))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(half))
                }
            }
            // Vocal-band share for the heuristic.
            var midSum: Float = 0, totalSum: Float = 0
            for k in 1..<half where isAudible[k] {
                totalSum += mags[k]
                if isMid[k] { midSum += mags[k] }
            }
            let time = baseTime + (Double(frameIndex) * Double(hop) + Double(n) / 2) / sampleRate
            frames.append(AutoMixSpectralFrame(
                time: time,
                energy: totalSum,
                midRatio: totalSum > 0 ? midSum / totalSum : 0
            ))
            frameIndex += 1

            guard includeChroma else { return }
            // Normalize per-frame chroma so loud sections do not dominate.
            for i in 0..<12 { frameChroma[i] = 0 }
            for k in 1..<half where binPitch[k] >= 0 {
                frameChroma[binPitch[k]] += log1p(Double(mags[k]))
            }
            let frameSum = frameChroma.reduce(0, +)
            if frameSum > 0 {
                for i in 0..<12 { chroma[i] += frameChroma[i] / frameSum }
            }
        }

        while !Task.isCancelled, consumed < maxSamples, let sampleBuffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            var length = 0
            var rawPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(
                block, atOffset: 0, lengthAtOffsetOut: nil,
                totalLengthOut: &length, dataPointerOut: &rawPointer
            )
            guard status == kCMBlockBufferNoErr,
                  let rawPointer,
                  length >= MemoryLayout<Float>.size else { continue }
            let count = length / MemoryLayout<Float>.size
            rawPointer.withMemoryRebound(to: Float.self, capacity: count) { samples in
                ring.append(contentsOf: UnsafeBufferPointer(start: samples, count: count))
            }
            consumed += count
            while ring.count >= n {
                processFrame()
                ring.removeFirst(hop)
            }
        }

        return (includeChroma && chroma.reduce(0, +) > 0 ? chroma : nil, frames)
    }

    // Embedded BPM tag (ID3 TBPM / iTunes tmpo) for local files, as a fallback when
    // the library/server didn't carry a tempo.
    private func readBPMMetadata(url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        let metadata = (try? await asset.load(.metadata)) ?? []
        for item in metadata {
            let keyText = [
                item.identifier?.rawValue,
                item.commonKey?.rawValue,
                item.keySpace?.rawValue,
                item.key.map { "\($0)" }
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
            guard keyText.contains("bpm")
                    || keyText.contains("beatsper")
                    || keyText.contains("tbpm")
                    || keyText.contains("tmpo") else { continue }

            if let number = try? await item.load(.numberValue), number.doubleValue > 0 {
                return number.doubleValue
            }
            if let text = try? await item.load(.stringValue) {
                let cleaned = text.replacingOccurrences(of: ",", with: ".")
                if let value = Double(cleaned.filter { $0.isNumber || $0 == "." }), value > 0 {
                    return value
                }
            }
        }
        return nil
    }
}
