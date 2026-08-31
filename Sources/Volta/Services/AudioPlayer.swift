import Foundation
import AVFoundation
import Accelerate
import MediaPlayer
import UIKit
import Combine

enum RepeatMode: Sendable { case off, one, all }
enum AutoplayMode: Sendable { case off, random, algorithm }

enum GaplessPlaybackMode: String, Sendable {
    case off
    case weak
    case on

    static func resolved(storedValue: String?) -> GaplessPlaybackMode {
        // Match the shipped player: gapless queue insertion is opt-in. Treat
        // missing or unknown values as off so an upgrade cannot silently move
        // an existing user onto a different AVQueuePlayer state machine.
        storedValue.flatMap(GaplessPlaybackMode.init(rawValue:)) ?? .off
    }

    static var current: GaplessPlaybackMode {
        resolved(storedValue: UserDefaults.standard.string(forKey: "gaplessPlayback"))
    }

    var preparesSuccessor: Bool { self != .off }
    var enqueuesSuccessor: Bool { self == .on }
}

struct PlaybackTimeSnapshot: Sendable {
    let elapsed: TimeInterval
    let duration: TimeInterval

    var remaining: TimeInterval { max(0, duration - elapsed) }
}

struct PreviousTrackPlan: Equatable, Sendable {
    let targetIndex: Int
    let shouldMaterializePlayback: Bool

    static func resolve(
        elapsed: TimeInterval,
        currentIndex: Int,
        queueCount: Int,
        isDeferredSession: Bool
    ) -> PreviousTrackPlan? {
        guard queueCount > 0, currentIndex >= 0, currentIndex < queueCount else { return nil }

        if elapsed <= 3, currentIndex > 0 {
            return PreviousTrackPlan(
                targetIndex: currentIndex - 1,
                shouldMaterializePlayback: true
            )
        }

        return PreviousTrackPlan(
            targetIndex: currentIndex,
            // A restored launch session intentionally has no AVPlayerItem. A
            // transport command must materialize one instead of seeking the
            // empty queue player and leaving playback in a phantom state.
            shouldMaterializePlayback: isDeferredSession
        )
    }
}

private struct SavedPlaybackSession: Codable, Sendable {
    let version: Int
    let serverID: String
    let savedAt: Date
    let song: Song
    let queue: [Song]
    let currentIndex: Int
    let elapsed: TimeInterval
    let duration: TimeInterval
    let wasPlaying: Bool
    let queueSourceTitle: String
    let queueSourceAlbum: Album?
    let queueSourcePlaylist: Playlist?
}

private enum SavedPlaybackSessionStore {
    static let key = "lastPlaybackSession"
    static let version = 1
    // Encoding a queue can be relatively expensive. Keep routine autosaves off
    // the main actor so they cannot interrupt rendering during playback.
    static let persistenceQueue = DispatchQueue(
        label: "com.ayo.music.playback-session",
        qos: .utility
    )
}

private enum PlaybackHistoryStore {
    static let keyPrefix = "playbackHistory"
    static let maxCount = 50
    static let persistenceQueue = DispatchQueue(
        label: "com.ayo.music.playback-history",
        qos: .utility
    )

    static func key(for serverID: String) -> String {
        "\(keyPrefix).\(serverID)"
    }
}

private enum PlaybackURLSource: String, Equatable {
    case download
    case playbackCache = "cache"
    case stream

    var isUserDownload: Bool { self == .download }
}

private typealias PlaybackURLInfo = (url: URL, source: PlaybackURLSource, usesTranscode: Bool)

private enum ItemAudioProcessingMode: Int {
    case none
    case transitionOnly
    case effectsAllowed
    case effectsBypassed
}

private final class ItemAudioPipeline {
    let track: AVAssetTrack
    let tap: MTAudioProcessingTap?
    let autoMixChannelID: UInt64
    let mode: ItemAudioProcessingMode

    init(
        track: AVAssetTrack,
        tap: MTAudioProcessingTap?,
        autoMixChannelID: UInt64,
        mode: ItemAudioProcessingMode
    ) {
        self.track = track
        self.tap = tap
        self.autoMixChannelID = autoMixChannelID
        self.mode = mode
    }
}

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

private enum PlaybackTransitionSettings {
    static var minimumEndLead: TimeInterval {
        let value = UserDefaults.standard.double(forKey: "automixMinimumEndLeadSeconds")
        return min(20, max(4, value > 0 ? value : 8))
    }

    static var maxBlend: TimeInterval {
        switch AutoMixStyle.current {
        case .tight: 7
        case .balanced: 11
        case .wide: 15
        }
    }

    static func crossfadeDuration(sameAlbum: Bool) -> TimeInterval {
        let value = UserDefaults.standard.double(forKey: "crossfadeDurationSeconds")
        let duration = min(12, max(1, value > 0 ? value : 6))
        return sameAlbum ? min(duration, 4) : duration
    }

}

@MainActor
final class AudioPlayer: ObservableObject {
    @Published private(set) var currentSong: Song?
    @Published private(set) var hasActivePlaybackSession = false
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var currentArtwork: UIImage?
    @Published private(set) var currentAnimatedArtwork: UIImage?
    @Published private(set) var currentLiveArtwork: LiveArtworkAsset?
    @Published private(set) var currentPlaybackUsesTranscode = false

    @Published private(set) var queue: [Song] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var queueSourceTitle: String = ""
    @Published private(set) var queueSourceAlbum: Album?
    @Published private(set) var queueSourcePlaylist: Playlist?
    @Published private(set) var playbackHistory: [Song] = []

    @Published private(set) var isShuffle = false
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var autoplayMode: AutoplayMode = .off
    @Published private(set) var transitionMode: PlaybackTransitionMode = .off
    var isCrossfade: Bool { transitionMode != .off }

    var isAutoplay: Bool {
        get { autoplayMode != .off }
        set {
            autoplayMode = newValue ? .random : .off
            UserDefaults.standard.set(newValue, forKey: "autoplayEnabled")
            ensureAutoplayPreloadedIfNeeded()
        }
    }

    @Published private(set) var starredIDs: Set<String> = []

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
    private var primaryCurrentItemObservation: NSKeyValueObservation?
    private var secondaryCurrentItemObservation: NSKeyValueObservation?
    private var loggedSongIDs: Set<String> = []
    private var targetVolume: Float = 1.0
    private var transitionPlanTask: Task<Void, Never>?
    private var transitionPlanKey: String?
    private var preparedTransitionPlan: AutoMixTransitionPlan?
    private var isTransitioning = false
    private let autoMixCoordinator = AutoMixCoordinator()
    private let autoMixPlanner = AutoMixPlanner()
    private weak var transitionOutgoingPlayer: AVQueuePlayer?
    private weak var transitionIncomingPlayer: AVQueuePlayer?
    private var transitionNextSong: Song?
    private var activeTransitionPlan: AutoMixTransitionPlan?
    private var transitionIncomingSource: PlaybackURLSource?
    private var transitionIncomingUsesTranscode = false
    private var transitionPromoted = false
    private var readinessRetryCount = 0
    // Drives the "Mixing" indicator.
    @Published private(set) var isMixing = false
    private var transitionSuppressedUntil = Date.distantPast
    // Muted pre-buffer on the inactive player.
    private var primedSongID: String?
    private var primingSongID: String?
    private var transitionPrimeTask: Task<Void, Never>?
    private var primedSongUsesTranscode = false
    private var primedPlaybackSource: PlaybackURLSource?
    private var primedReady = false

    private var gaplessNextItem: AVPlayerItem? = nil
    private var gaplessNextSongID: String? = nil
    private var gaplessNextSource: PlaybackURLSource? = nil
    private var gaplessNextUsesTranscode = false
    private var gaplessNextQueueIndex: Int? = nil
    private var gaplessPreloadTask: Task<Void, Never>?
    private var gaplessPreloadGeneration: UInt64 = 0
    private var gaplessNextStatusObservation: NSKeyValueObservation?
    private var gaplessRetrySongID: String?
    private var gaplessRetryCount = 0
    private var gaplessReadinessLoggedItemID: ObjectIdentifier?
    private var gaplessTransitionMeasurementTask: Task<Void, Never>?
    private var currentAudioProcessingTask: Task<Void, Never>?
    private var playbackPreparationTask: Task<Void, Never>?
    private let itemAudioProcessingModes = NSMapTable<AVPlayerItem, NSNumber>.weakToStrongObjects()
    private let itemAudioPipelines = NSMapTable<AVPlayerItem, ItemAudioPipeline>.weakToStrongObjects()
    private var currentPlayerItem: AVPlayerItem? = nil
    private var currentPlaybackSource: PlaybackURLSource?
    private var prematureTranscodeEndRetries: [String: Int] = [:]
    // A paused restored session keeps metadata only until playback resumes.
    private var deferredRestoredTime: TimeInterval? = nil
    // Lets deferred play requests detect newer track changes.
    private var playRequestID: UInt64 = 0
    private var autoplayAppendTask: Task<Void, Never>?
    // Per-song loads, cancelled on track change so rapid skips don't pile up.
    private var artworkLoadTask: Task<Void, Never>?
    private var durationLoadTask: Task<Void, Never>?
    private var startupDiagnosticsTask: Task<Void, Never>?
    private var warmStreamsTask: Task<Void, Never>?
    private let autoplayPreloadThreshold = 1
    private var currentServerID: String?
    private var playbackHistoryPersistenceGeneration: UInt64 = 0
    private var savedPlaybackSessionPersistenceGeneration: UInt64 = 0
    private var didAttemptSavedSessionRestore = false
    private var lastSessionAutosaveAt = Date.distantPast
    private let sessionAutosaveInterval: TimeInterval = 5
    private let maxSavedSessionQueueCount = 100
    private var currentSongStartedAt: Date?

    @Published private(set) var autoplayArtistName: String?
    @Published private(set) var autoplayArtistId: String?

    // Seed songs for Similar Songs infinite play.
    private var infinitePlaySeed: [Song] = []

    @Published private(set) var sleepTimerActive = false
    @Published private(set) var sleepEndsAtTrackEnd = false
    @Published private(set) var sleepRemaining: TimeInterval = 0
    private var sleepTimer: Timer?

    static var canUseAutoMix: Bool {
        true
    }

    init() {
        activePlayer = primaryPlayer
        // Start route-aware EQ profile handling with the playback stack, not
        // only after the Equalizer settings screen has been opened.
        _ = EqualizerProfileStore.shared
        // Disable AVQueuePlayer's boundary wait; blend warmup has its own gate.
        primaryPlayer.automaticallyWaitsToMinimizeStalling = false
        secondaryPlayer.automaticallyWaitsToMinimizeStalling = false
        primaryPlayer.actionAtItemEnd = .advance
        secondaryPlayer.actionAtItemEnd = .advance
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
        addCurrentItemObservers()
        addEndObserver()
        addInterruptionObserver()
        addRouteChangeObserver()
        addStallObserver()
        NotificationCenter.default.addObserver(forName: .equalizerToggled, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, let item = self.player.currentItem else { return }
                let desiredMode = self.desiredAudioProcessingMode
                let currentMode = self.audioProcessingMode(for: item)
                guard desiredMode != currentMode else { return }
                self.applyEqualizer(to: item)
                self.invalidatePreloadedNext()
                self.scheduleGaplessPreload()
                self.clearPriming()
                self.resetPreparedTransitionPlan()
                self.prepareTransitionPlanIfNeeded()
            }
        }
    }

    private func makePlayerItem(
        playback urlInfo: PlaybackURLInfo,
        requiresTimePitchProcessing: Bool = false
    ) -> AVPlayerItem {
        // Precise duration probing is useful and cheap for local files, but can
        // delay a remote item's initial buffering while AVFoundation inspects it.
        let options: [String: Any]? = urlInfo.source == .stream
            ? nil
            : [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        let asset = AVURLAsset(url: urlInfo.url, options: options)
        let item = AVPlayerItem(asset: asset)
        if urlInfo.source == .stream {
            item.preferredForwardBufferDuration = urlInfo.usesTranscode ? 24 : 12
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        }
        if requiresTimePitchProcessing {
            item.audioTimePitchAlgorithm = .spectral
        }
        return item
    }

    private var desiredAudioProcessingMode: ItemAudioProcessingMode {
        let visualizerActive = AudioVisualizerEngine.shared.isActive
        let transitionActive = transitionMode != .off && !PerformanceMode.simpleTransitions
        if PerformanceMode.bypassAudioEffects {
            if visualizerActive { return .effectsBypassed }
            return transitionActive ? .transitionOnly : .none
        }
        if EqualizerEngine.shared.isAnyEffectActive { return .effectsAllowed }
        if visualizerActive { return .effectsBypassed }
        return transitionActive ? .transitionOnly : .none
    }

    private var audioProcessingRequired: Bool {
        desiredAudioProcessingMode != .none
    }

    private func audioProcessingMode(for item: AVPlayerItem) -> ItemAudioProcessingMode {
        guard let raw = itemAudioProcessingModes.object(forKey: item)?.intValue else { return .none }
        return ItemAudioProcessingMode(rawValue: raw) ?? .none
    }

    private func setAudioProcessingMode(_ mode: ItemAudioProcessingMode, for item: AVPlayerItem) {
        if mode == .none {
            itemAudioProcessingModes.removeObject(forKey: item)
            releaseAudioPipeline(for: item)
        } else {
            itemAudioProcessingModes.setObject(NSNumber(value: mode.rawValue), forKey: item)
        }
    }

    private func releaseAudioPipeline(for item: AVPlayerItem) {
        if let pipeline = itemAudioPipelines.object(forKey: item), pipeline.autoMixChannelID != 0 {
            AutoMixTransitionDSP.shared.release(channelID: pipeline.autoMixChannelID)
        }
        itemAudioPipelines.removeObject(forKey: item)
        itemAudioProcessingModes.removeObject(forKey: item)
    }

    private func sourceNeedsNetworkBuffer(source: PlaybackURLSource, usesTranscode: Bool) -> Bool {
        source == .stream && usesTranscode
    }

    private func startPlayer(_ target: AVQueuePlayer, source: PlaybackURLSource, usesTranscode: Bool) {
        let shouldWaitForNetworkBuffer = sourceNeedsNetworkBuffer(source: source, usesTranscode: usesTranscode)
        target.automaticallyWaitsToMinimizeStalling = shouldWaitForNetworkBuffer
        if shouldWaitForNetworkBuffer {
            target.play()
        } else {
            target.playImmediately(atRate: 1)
        }
    }

    private func activateAudioSessionForPlayback() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            // A long background pause can leave this app's session inactive.
            // Reapplying category before activation makes a user-initiated
            // resume deterministic instead of relying on a stale player state.
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            return true
        } catch {
            AppLogger.shared.log(
                "Playback resume could not activate audio session: \(error.localizedDescription)",
                category: .playback,
                level: .warning
            )
            return false
        }
    }

    // Loading an audio track is asynchronous. Callers preparing an upcoming
    // item await this before queue insertion so audioMix is never swapped at
    // the handoff boundary.
    private func prepareAudioProcessing(
        for item: AVPlayerItem,
        forceAutoMixDSP: Bool = false
    ) async -> Bool {
        let desiredMode = desiredAudioProcessingMode
        let resolvedMode: ItemAudioProcessingMode = forceAutoMixDSP && desiredMode == .transitionOnly
            ? .effectsBypassed
            : desiredMode
        guard resolvedMode != .none else {
            item.audioMix = nil
            setAudioProcessingMode(.none, for: item)
            return true
        }
        guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first,
              !Task.isCancelled else {
            return false
        }
        // Settings may change while the asset load suspends. Build against the
        // latest topology so a newly enabled EQ is not inserted unprocessed.
        let latestDesiredMode = desiredAudioProcessingMode
        let latestMode: ItemAudioProcessingMode = forceAutoMixDSP && latestDesiredMode == .transitionOnly
            ? .effectsBypassed
            : latestDesiredMode
        guard latestMode != .none else {
            item.audioMix = nil
            setAudioProcessingMode(.none, for: item)
            return true
        }
        releaseAudioPipeline(for: item)
        let needsTap = latestMode == .effectsAllowed || latestMode == .effectsBypassed
        let autoMixChannelID = needsTap
            && transitionMode == .automix
            && !PerformanceMode.simpleTransitions
            ? AutoMixTransitionDSP.shared.reserveChannel()
            : 0
        let tap: MTAudioProcessingTap?
        if needsTap {
            tap = EqualizerEngine.shared.makeTap(
                bypassEffects: latestMode == .effectsBypassed,
                autoMixChannelID: autoMixChannelID
            )
            guard tap != nil else {
                AutoMixTransitionDSP.shared.release(channelID: autoMixChannelID)
                return false
            }
        } else {
            tap = nil
        }
        let params = AVMutableAudioMixInputParameters(track: track)
        params.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        item.audioMix = mix
        itemAudioPipelines.setObject(
            ItemAudioPipeline(
                track: track,
                tap: tap,
                autoMixChannelID: autoMixChannelID,
                mode: latestMode
            ),
            forKey: item
        )
        setAudioProcessingMode(latestMode, for: item)
        return true
    }

    private func applyEqualizer(to item: AVPlayerItem) {
        currentAudioProcessingTask?.cancel()
        guard audioProcessingRequired else {
            item.audioMix = nil
            setAudioProcessingMode(.none, for: item)
            currentAudioProcessingTask = nil
            return
        }
        currentAudioProcessingTask = Task { @MainActor [weak self, weak item] in
            guard let self, let item else { return }
            _ = await self.prepareAudioProcessing(for: item)
        }
    }

    private func installTransitionEnvelope(
        on item: AVPlayerItem,
        plan: AutoMixTransitionPlan,
        outgoing: Bool
    ) -> Bool {
        guard let pipeline = itemAudioPipelines.object(forKey: item) else { return false }
        let parameters = AVMutableAudioMixInputParameters(track: pipeline.track)
        parameters.audioTapProcessor = pipeline.tap
        if outgoing {
            AutoMixTimedEnvelope.applyOutgoing(plan, to: parameters)
        } else {
            AutoMixTimedEnvelope.applyIncoming(plan, to: parameters)
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        item.audioMix = mix
        return true
    }

    private func resetTransitionEnvelope(on item: AVPlayerItem, at mediaTime: TimeInterval) {
        guard let pipeline = itemAudioPipelines.object(forKey: item) else { return }
        AutoMixTransitionDSP.shared.reset(channelID: pipeline.autoMixChannelID)
        let parameters = AVMutableAudioMixInputParameters(track: pipeline.track)
        parameters.audioTapProcessor = pipeline.tap
        AutoMixTimedEnvelope.setUnity(to: parameters, at: mediaTime)
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        item.audioMix = mix
    }

    private func configureTransitionFilters(
        outgoingItem: AVPlayerItem,
        incomingItem: AVPlayerItem,
        plan: AutoMixTransitionPlan
    ) {
        if let pipeline = itemAudioPipelines.object(forKey: outgoingItem) {
            AutoMixTransitionDSP.shared.configure(
                channelID: pipeline.autoMixChannelID,
                descriptor: AutoMixTransitionFilterDescriptor(
                    mediaStart: plan.outgoingCue,
                    mediaDuration: plan.duration,
                    highPassStartHz: plan.filters.outgoingHighPassStartHz,
                    highPassEndHz: plan.filters.outgoingHighPassEndHz,
                    lowPassStartHz: plan.filters.outgoingLowPassStartHz,
                    lowPassEndHz: plan.filters.outgoingLowPassEndHz
                )
            )
        }
        if let pipeline = itemAudioPipelines.object(forKey: incomingItem) {
            AutoMixTransitionDSP.shared.configure(
                channelID: pipeline.autoMixChannelID,
                descriptor: AutoMixTransitionFilterDescriptor(
                    mediaStart: plan.incomingCue,
                    mediaDuration: plan.incomingMediaDuration,
                    highPassStartHz: plan.filters.incomingHighPassStartHz,
                    highPassEndHz: plan.filters.incomingHighPassEndHz,
                    lowPassStartHz: plan.filters.incomingLowPassStartHz,
                    lowPassEndHz: plan.filters.incomingLowPassEndHz
                )
            )
        }
    }

    func updateClient(_ client: (any MusicService)?, serverID: String? = nil) {
        let previousServerID = currentServerID
        if previousServerID != serverID || client == nil {
            PlaybackCacheService.shared.cancelPrefetches()
            Task { await AutoMixAnalysisService.shared.cancelAll() }
        }
        self.client = client
        currentServerID = serverID
        TrackPairingStore.shared.selectServer(serverID)
        if previousServerID != serverID {
            loadPlaybackHistory(for: serverID)
        }
        DownloadService.shared.updateClient(client, serverID: serverID)
        AppLogger.shared.log(
            "Playback client updated; connected=\(client != nil)",
            category: .playback
        )
    }

    // MARK: - Playback entry points

    func playQueue(_ songs: [Song], startIndex: Int = 0, source: String = "", album: Album? = nil, playlist: Playlist? = nil) {
        guard songs.indices.contains(startIndex) else {
            AppLogger.shared.log(
                "Queue rejected; count=\(songs.count); requestedIndex=\(startIndex)",
                category: .playback,
                level: .warning
            )
            return
        }
        AppLogger.shared.log(
            "Queue started; count=\(songs.count); index=\(startIndex); source='\(source)'",
            category: .playback
        )
        cancelTransitionPlayback()
        invalidatePreloadedNext()
        autoplayArtistName = nil
        autoplayArtistId = nil
        infinitePlaySeed = []
        let pairedQueue = queueWithTrackPairings(songs, startIndex: startIndex)
        queue = pairedQueue.songs
        queueSourceTitle = source
        queueSourceAlbum = album
        queueSourcePlaylist = playlist
        currentIndex = pairedQueue.startIndex
        if isShuffle { shuffleUpcoming() }
        playCurrent()
    }

    func play(song: Song) {
        playQueue([song], startIndex: 0, source: song.album ?? "")
    }

    func playFromHistory(_ song: Song) {
        suppressTransitionsBriefly()
        cancelTransitionPlayback()

        if currentSong?.id == song.id, queue.indices.contains(currentIndex) {
            playCurrent()
            return
        }

        guard !queue.isEmpty else {
            play(song: song)
            return
        }

        invalidatePreloadedNext()
        resetPreparedTransitionPlan()
        let insertionIndex = min(currentIndex + 1, queue.count)
        queue.insert(song, at: insertionIndex)
        currentIndex = insertionIndex
        playCurrent()
    }

    func clearPlaybackHistory() {
        playbackHistoryPersistenceGeneration &+= 1
        playbackHistory = []
        guard let currentServerID else { return }
        UserDefaults.standard.removeObject(forKey: PlaybackHistoryStore.key(for: currentServerID))
    }

    func playArtist(_ songs: [Song], artist: Artist) {
        guard !songs.isEmpty else { return }
        playQueue(songs, startIndex: 0, source: artist.name)
        autoplayArtistName = artist.name
        autoplayArtistId = artist.id
        if autoplayMode == .off { autoplayMode = .algorithm }
    }

    func skipNext() {
        AppLogger.shared.log("Skip next; index=\(currentIndex); target=\(currentIndex + 1)", category: .playback)
        guard !queue.isEmpty, queue.indices.contains(currentIndex) else { return }
        suppressTransitionsBriefly()
        cancelTransitionPlayback()
        switch repeatMode {
        case .one:
            seek(to: 0)
            resume()
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
        AppLogger.shared.log("Skip previous; index=\(currentIndex); elapsed=\(String(format: "%.3f", currentTime))s", category: .playback)
        let isDeferredSession = currentPlayerItem == nil && deferredRestoredTime != nil
        guard let plan = PreviousTrackPlan.resolve(
            elapsed: playbackTimeSnapshot().elapsed,
            currentIndex: currentIndex,
            queueCount: queue.count,
            isDeferredSession: isDeferredSession
        ) else { return }
        suppressTransitionsBriefly()
        cancelTransitionPlayback()

        if plan.targetIndex != currentIndex || plan.shouldMaterializePlayback {
            currentIndex = plan.targetIndex
            playCurrent()
        } else {
            seek(to: 0)
            if isPlaying { resume() }
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
            pause()
        } else {
            resume()
        }
    }

    func pause() {
        pauseAllPlayers()
        cancelTransitionPlayback(keepPaused: true)
        isPlaying = false
        AppLogger.shared.log(
            "Playback paused by command; songID=\(currentSong?.id ?? "none"); elapsed=\(String(format: "%.3f", liveTime()))s",
            category: .playback
        )
        updateNowPlaying()
        persistLastPlaybackSession()
    }

    func clearActivePlaybackForRecovery() {
        AppLogger.shared.logAlways(
            "Developer recovery requested; songID=\(currentSong?.id ?? "none"); queueCount=\(queue.count); hasItem=\(currentPlayerItem != nil); deferred=\(deferredRestoredTime != nil)",
            category: .playback,
            level: .warning
        )
        stopAndClear()
    }

    // Full stop for logout.
    func stopAndClear() {
        AppLogger.shared.log(
            "Playback stopped and queue cleared; songID=\(currentSong?.id ?? "none"); queueCount=\(queue.count)",
            category: .playback
        )
        // Invalidate unstructured metadata warmups before clearing state so a
        // late response cannot resurrect the track that was just removed.
        playRequestID &+= 1
        autoplayAppendTask?.cancel(); autoplayAppendTask = nil
        PlaybackCacheService.shared.cancelPrefetches()
        pauseAllPlayers()
        cancelTransitionPlayback(keepPaused: true)
        resetPreparedTransitionPlan()
        cancelSleepTimer(resumeGaplessPreload: false)
        artworkLoadTask?.cancel(); artworkLoadTask = nil
        durationLoadTask?.cancel(); durationLoadTask = nil
        startupDiagnosticsTask?.cancel(); startupDiagnosticsTask = nil
        warmStreamsTask?.cancel(); warmStreamsTask = nil
        gaplessPreloadTask?.cancel(); gaplessPreloadTask = nil
        gaplessPreloadGeneration &+= 1
        gaplessNextStatusObservation?.invalidate(); gaplessNextStatusObservation = nil
        gaplessTransitionMeasurementTask?.cancel(); gaplessTransitionMeasurementTask = nil
        currentAudioProcessingTask?.cancel(); currentAudioProcessingTask = nil
        playbackPreparationTask?.cancel(); playbackPreparationTask = nil
        for item in primaryPlayer.items() + secondaryPlayer.items() {
            releaseAudioPipeline(for: item)
        }
        primaryPlayer.removeAllItems()
        secondaryPlayer.removeAllItems()
        activePlayer = primaryPlayer
        targetVolume = 1
        primaryPlayer.volume = 1
        secondaryPlayer.volume = 0
        primaryPlayer.rate = 1
        secondaryPlayer.rate = 1
        primaryPlayer.automaticallyWaitsToMinimizeStalling = false
        secondaryPlayer.automaticallyWaitsToMinimizeStalling = false
        itemAudioProcessingModes.removeAllObjects()
        itemAudioPipelines.removeAllObjects()
        Task { await AutoMixAnalysisService.shared.cancelAll() }
        currentPlayerItem = nil
        currentPlaybackSource = nil
        currentPlaybackUsesTranscode = false
        prematureTranscodeEndRetries.removeAll()
        deferredRestoredTime = nil
        gaplessNextItem = nil
        gaplessNextSongID = nil
        gaplessNextSource = nil
        gaplessNextUsesTranscode = false
        gaplessNextQueueIndex = nil
        gaplessReadinessLoggedItemID = nil
        gaplessRetrySongID = nil
        gaplessRetryCount = 0
        isPlaying = false
        hasActivePlaybackSession = false
        currentSong = nil
        currentSongStartedAt = nil
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
        infinitePlaySeed = []
        loggedSongIDs.removeAll()
        transitionSuppressedUntil = .distantPast
        lastSessionAutosaveAt = .distantPast
        clearSavedPlaybackSession()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func seek(to time: TimeInterval) {
        let before = liveTime()
        let total = playbackTimeSnapshot().duration
        let clamped = total > 0 ? min(max(0, time), total) : max(0, time)
        cancelTransitionPlayback(keepPaused: !isPlaying)
        if deferredRestoredTime != nil, currentPlayerItem == nil {
            deferredRestoredTime = clamped
            currentTime = clamped
            updateNowPlayingTime()
            persistLastPlaybackSession()
            return
        }
        let target = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
        AppLogger.shared.log(
            "Playback seek; from=\(String(format: "%.4f", before))s; to=\(String(format: "%.4f", clamped))s; duration=\(String(format: "%.4f", total))s",
            category: .playback
        )
        updateNowPlayingTime()
        persistLastPlaybackSession()
        if transitionMode != .off {
            refreshAutoMixAnalysisWindow()
            prepareTransitionPlanIfNeeded()
        }
    }

    func liveTime() -> TimeInterval {
        playbackTimeSnapshot().elapsed
    }

    func liveDuration() -> TimeInterval {
        playbackTimeSnapshot().duration
    }

    func setVisualizerActive(_ active: Bool) {
        AudioVisualizerEngine.shared.setActive(active)
        if let item = player.currentItem {
            applyEqualizer(to: item)
        }
        invalidatePreloadedNext()
        scheduleGaplessPreload()
        clearPriming()
        resetPreparedTransitionPlan()
        prepareTransitionPlanIfNeeded()
    }

    func visualizerSnapshot() -> AudioVisualizerSnapshot {
        AudioVisualizerEngine.shared.snapshot()
    }

    private func notifyNowPlaying(for song: Song) {
        let startedAt = currentSongStartedAt ?? Date()
        ThirdPartyScrobbler.shared.notifyNowPlaying(song: song, startedAt: startedAt)
        guard let client, client.capabilities.contains(.serverScrobbling) else { return }
        Task {
            do {
                try await client.scrobble(id: song.id, at: nil, submission: false)
            } catch {
                AppLogger.shared.log(
                    "Server now-playing scrobble failed: '\(song.title)' - \(error.localizedDescription)",
                    category: .playback,
                    level: .warning
                )
            }
        }
    }

    private func submitServerScrobble(for song: Song, startedAt: Date) {
        guard let client, client.capabilities.contains(.serverScrobbling) else { return }
        Task {
            do {
                try await client.scrobble(id: song.id, at: startedAt, submission: true)
                AppLogger.shared.log("Server scrobble submitted: '\(song.title)'", category: .playback)
            } catch {
                AppLogger.shared.log(
                    "Server scrobble failed: '\(song.title)' - \(error.localizedDescription)",
                    category: .playback,
                    level: .warning
                )
            }
        }
    }

    func refreshPlaybackCache() {
        warmUpcomingStreams()
    }

    // Read the AVPlayer clock and item duration once, normalize them together,
    // and hand UI consumers one coherent sample.
    func playbackTimeSnapshot() -> PlaybackTimeSnapshot {
        let itemDuration = player.currentItem?.duration.seconds ?? .nan
        let metadataDuration = resolvedPlaybackDuration(avDuration: itemDuration)

        let playerTime = player.currentTime().seconds
        let sampledTime = deferredRestoredTime
            ?? (currentPlayerItem != nil && playerTime.isFinite ? playerTime : currentTime)
        let rawElapsed = max(0, sampledTime)

        // Duration cannot fall behind live playback.
        var total = max(0, metadataDuration)
        total = max(total, rawElapsed)

        let elapsed = total > 0 ? min(rawElapsed, total) : rawElapsed
        return PlaybackTimeSnapshot(elapsed: elapsed, duration: total)
    }

    private func resolvedPlaybackDuration(avDuration: TimeInterval) -> TimeInterval {
        let serverDuration = Double(currentSong?.duration ?? 0)
        let storedDuration = duration > 0 ? duration : serverDuration
        guard avDuration.isFinite, avDuration > 0 else {
            return max(0, storedDuration)
        }
        // Some servers report a rounded or stale duration while the streamed
        // item continues beyond it. Never let that shorter estimate put the
        // scrubber at 0:00 before AVFoundation has actually reached its end.
        return max(storedDuration, avDuration)
    }

    func persistLastPlaybackSession(synchronize: Bool = false) {
        guard let serverID = currentServerID,
              let song = currentSong else { return }

        var sessionQueue = queue
        var sessionIndex = currentIndex
        if sessionQueue.isEmpty {
            sessionQueue = [song]
            sessionIndex = 0
        } else if !sessionQueue.indices.contains(sessionIndex)
                    || sessionQueue[sessionIndex].id != song.id {
            if let matchingIndex = sessionQueue.firstIndex(where: { $0.id == song.id }) {
                sessionIndex = matchingIndex
            } else {
                let insertionIndex = min(max(0, sessionIndex), sessionQueue.count)
                sessionQueue.insert(song, at: insertionIndex)
                sessionIndex = insertionIndex
            }
        }
        if sessionQueue.count > maxSavedSessionQueueCount {
            let halfWindow = maxSavedSessionQueueCount / 2
            let lowerBound = max(0, min(sessionIndex - halfWindow, sessionQueue.count - maxSavedSessionQueueCount))
            let upperBound = min(sessionQueue.count, lowerBound + maxSavedSessionQueueCount)
            sessionQueue = Array(sessionQueue[lowerBound..<upperBound])
            sessionIndex -= lowerBound
        }

        let snapshot = playbackTimeSnapshot()
        let metadataDuration = Double(song.duration ?? 0)
        let total = max(snapshot.duration, metadataDuration)
        let elapsed = total > 0
            ? min(max(0, snapshot.elapsed), total)
            : max(0, snapshot.elapsed)
        let session = SavedPlaybackSession(
            version: SavedPlaybackSessionStore.version,
            serverID: serverID,
            savedAt: Date(),
            song: song,
            queue: sessionQueue,
            currentIndex: sessionIndex,
            elapsed: elapsed,
            duration: total,
            wasPlaying: isPlaying,
            queueSourceTitle: queueSourceTitle,
            queueSourceAlbum: nil,
            queueSourcePlaylist: nil
        )

        savedPlaybackSessionPersistenceGeneration &+= 1
        let generation = savedPlaybackSessionPersistenceGeneration
        let encode = { @Sendable () throws -> Data in
            try JSONEncoder().encode(session)
        }

        let reportFailure: @Sendable (String) -> Void = { message in
            _ = Task { @MainActor in
                AppLogger.shared.log(
                    "Saved playback session failed: \(message)",
                    category: .playback,
                    level: .warning
                )
            }
        }

        lastSessionAutosaveAt = Date()
        if synchronize {
            do {
                let data = try encode()
                UserDefaults.standard.set(data, forKey: SavedPlaybackSessionStore.key)
                UserDefaults.standard.synchronize()
            } catch {
                reportFailure(error.localizedDescription)
            }
        } else {
            SavedPlaybackSessionStore.persistenceQueue.async { [weak self] in
                do {
                    let data = try encode()
                    Task { @MainActor [weak self] in
                        guard let self,
                              self.savedPlaybackSessionPersistenceGeneration == generation,
                              self.currentServerID == serverID,
                              self.currentSong?.id == song.id else { return }
                        UserDefaults.standard.set(data, forKey: SavedPlaybackSessionStore.key)
                    }
                } catch {
                    reportFailure(error.localizedDescription)
                }
            }
        }
    }

    func restoreLastPlaybackSessionIfNeeded() async {
        guard !didAttemptSavedSessionRestore else { return }
        didAttemptSavedSessionRestore = true
        guard currentSong == nil, !hasActivePlaybackSession else { return }
        playRequestID &+= 1
        let restoreRequestID = playRequestID
        guard let serverID = currentServerID,
              let session = loadSavedPlaybackSession(),
              session.serverID == serverID else { return }

        var restoredQueue = session.queue.isEmpty ? [session.song] : session.queue
        var restoredIndex = session.currentIndex
        if !restoredQueue.indices.contains(restoredIndex)
            || restoredQueue[restoredIndex].id != session.song.id {
            if let matchingIndex = restoredQueue.firstIndex(where: { $0.id == session.song.id }) {
                restoredIndex = matchingIndex
            } else {
                restoredQueue = [session.song]
                restoredIndex = 0
            }
        }

        let song = restoredQueue[restoredIndex]
        if DownloadService.shared.localURL(for: song) == nil,
           client?.streamMetadataReady(for: song) == false {
            await client?.prepareForPlayback(song: song)
        }

        guard restoreRequestID == playRequestID,
              currentSong == nil,
              !hasActivePlaybackSession else { return }
        guard playbackURL(for: song) != nil else {
            AppLogger.shared.log(
                "Saved playback session restore skipped: no stream URL for '\(song.title)'",
                category: .playback,
                level: .warning
            )
            return
        }

        cancelTransitionPlayback(keepPaused: true)
        resetPreparedTransitionPlan()
        artworkLoadTask?.cancel(); artworkLoadTask = nil
        durationLoadTask?.cancel(); durationLoadTask = nil
        warmStreamsTask?.cancel(); warmStreamsTask = nil
        primaryPlayer.pause()
        secondaryPlayer.pause()
        for item in primaryPlayer.items() + secondaryPlayer.items() {
            releaseAudioPipeline(for: item)
        }
        primaryPlayer.removeAllItems()
        secondaryPlayer.removeAllItems()
        activePlayer = primaryPlayer

        queue = restoredQueue
        currentIndex = restoredIndex
        queueSourceTitle = session.queueSourceTitle
        queueSourceAlbum = session.queueSourceAlbum
        queueSourcePlaylist = session.queueSourcePlaylist
        currentArtwork = nil
        currentAnimatedArtwork = nil
        currentLiveArtwork = nil
        hasActivePlaybackSession = true
        currentSong = song
        isPlaying = false
        let total = max(session.duration, Double(song.duration ?? 0))
        let elapsed = total > 0 ? min(max(0, session.elapsed), total) : max(0, session.elapsed)
        currentSongStartedAt = Date(timeIntervalSinceNow: -elapsed)
        currentTime = elapsed
        duration = total
        deferredRestoredTime = elapsed
        currentPlayerItem = nil
        currentPlaybackUsesTranscode = false
        loggedSongIDs.remove(song.id)
        if song.starred != nil { starredIDs.insert(song.id) }

        updateNowPlaying()
        artworkLoadTask = Task { [weak self] in await self?.loadArtwork(for: song) }
        AppLogger.shared.log(
            "Saved playback session restored without player allocation; title='\(song.title)'; elapsed=\(String(format: "%.3f", elapsed))s; savedAt=\(session.savedAt)",
            category: .playback
        )
    }

    private func resumeDeferredSessionIfNeeded() -> Bool {
        guard currentPlayerItem == nil,
              let elapsed = deferredRestoredTime,
              let song = currentSong else { return false }
        guard let urlInfo = playbackURL(for: song) else {
            AppLogger.shared.log(
                "Restored playback resume failed: no stream URL for '\(song.title)'",
                category: .playback,
                level: .warning
            )
            return false
        }

        let item = makePlayerItem(playback: urlInfo)
        startupDiagnosticsTask?.cancel()
        playbackPreparationTask?.cancel()
        playRequestID &+= 1
        let requestToken = playRequestID
        isPlaying = true
        currentSongStartedAt = Date(timeIntervalSinceNow: -max(0, elapsed))
        updateNowPlaying()
        persistLastPlaybackSession()

        // Keep the not-yet-inserted item alive until preparation finishes.
        // A weak capture here drops the only owner as soon as this method
        // returns, so the task exits without ever materializing playback.
        playbackPreparationTask = Task { @MainActor [weak self, item] in
            guard let self else { return }
            defer {
                if requestToken == self.playRequestID {
                    self.playbackPreparationTask = nil
                }
            }
            let processingReady = await self.prepareAudioProcessing(for: item)
            guard !Task.isCancelled,
                  requestToken == self.playRequestID,
                  self.currentPlayerItem == nil,
                  self.currentSong?.id == song.id,
                  let resumedElapsed = self.deferredRestoredTime else { return }
            if !processingReady {
                item.audioMix = nil
                self.setAudioProcessingMode(.none, for: item)
                AppLogger.shared.log(
                    "Audio processing unavailable while restoring '\(song.title)'; playing unprocessed",
                    category: .playback,
                    level: .warning
                )
            }
            self.materializeDeferredPlayback(
                song: song,
                item: item,
                urlInfo: urlInfo,
                elapsed: resumedElapsed
            )
        }
        return true
    }

    private func materializeDeferredPlayback(
        song: Song,
        item: AVPlayerItem,
        urlInfo: PlaybackURLInfo,
        elapsed: TimeInterval
    ) {
        for existing in player.items() { releaseAudioPipeline(for: existing) }
        player.removeAllItems()
        player.insert(item, after: nil)
        currentPlayerItem = item
        currentPlaybackSource = urlInfo.source
        currentPlaybackUsesTranscode = urlInfo.usesTranscode
        applyReplayGain(for: song)
        try? AVAudioSession.sharedInstance().setActive(true)

        let beginPlayback = { [weak self, weak item] in
            guard let self, let item,
                  self.currentPlayerItem === item,
                  self.currentSong?.id == song.id else { return }
            self.deferredRestoredTime = nil
            self.currentTime = elapsed
            if self.isPlaying {
                self.startPlayer(self.player, source: urlInfo.source, usesTranscode: urlInfo.usesTranscode)
            }
        }
        if elapsed > 0 {
            let target = CMTime(seconds: elapsed, preferredTimescale: 600)
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                guard finished else { return }
                Task { @MainActor in beginPlayback() }
            }
        } else {
            beginPlayback()
        }

        notifyNowPlaying(for: song)
        updateNowPlaying()
        persistLastPlaybackSession()
        durationLoadTask?.cancel()
        durationLoadTask = Task { [weak self] in await self?.loadDuration(from: item) }
        monitorStartup(for: item, song: song, source: urlInfo.source)
        scheduleGaplessPreload()
        ensureAutoplayPreloadedIfNeeded()
        warmUpcomingStreams()
        if Date() >= transitionSuppressedUntil {
            prepareTransitionPlanIfNeeded()
        }
        AppLogger.shared.log(
            "Restored playback materialized; title='\(song.title)'; elapsed=\(String(format: "%.3f", elapsed))s",
            category: .playback
        )
    }

    private func autosaveLastPlaybackSessionIfNeeded() {
        guard currentSong != nil else { return }
        let now = Date()
        guard now.timeIntervalSince(lastSessionAutosaveAt) >= sessionAutosaveInterval else { return }
        persistLastPlaybackSession()
    }

    private func loadSavedPlaybackSession() -> SavedPlaybackSession? {
        guard let data = UserDefaults.standard.data(forKey: SavedPlaybackSessionStore.key) else { return nil }
        do {
            let session = try JSONDecoder().decode(SavedPlaybackSession.self, from: data)
            guard session.version == SavedPlaybackSessionStore.version else { return nil }
            return session
        } catch {
            AppLogger.shared.log(
                "Saved playback session unreadable: \(error.localizedDescription)",
                category: .playback,
                level: .warning
            )
            clearSavedPlaybackSession()
            return nil
        }
    }

    private func clearSavedPlaybackSession() {
        // Any older encode already queued on the persistence worker must not be
        // allowed to recreate the session after a recovery clear or logout.
        savedPlaybackSessionPersistenceGeneration &+= 1
        UserDefaults.standard.removeObject(forKey: SavedPlaybackSessionStore.key)
        UserDefaults.standard.synchronize()
    }

    // MARK: - Queue manipulation

    func moveQueueItem(from source: IndexSet, to dest: Int) {
        cancelTransitionPlayback(keepPaused: !isPlaying)
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
        resetPreparedTransitionPlan()
        scheduleGaplessPreload()
        prepareTransitionPlanIfNeeded()
        warmUpcomingStreams()
    }

    func playNext(_ song: Song) {
        // single-song entry point fired from menus/swipes/album loops; the toast
        // centre dedupes a burst of identical posts (album "Play Next") into one.
        VoltaNotificationCenter.shared.post(L(.notif_playing_next), tone: .queue)
        guard !queue.isEmpty else {
            queue = queueWithTrackPairings([song]).songs
            currentIndex = 0
            queueSourceTitle = "Play Next"
            AppLogger.shared.log("Queued next while idle: '\(song.title)'", category: .playback)
            return
        }
        cancelTransitionPlayback(keepPaused: !isPlaying)
        invalidatePreloadedNext()
        insertSongsNext(queueWithTrackPairings([song]).songs)
        resetPreparedTransitionPlan()
        scheduleGaplessPreload()
        prepareTransitionPlanIfNeeded()
        warmUpcomingStreams()
    }

    func addToQueue(_ song: Song) {
        guard !queue.isEmpty else { play(song: song); return }
        queue.append(contentsOf: queueWithTrackPairings([song]).songs)
        VoltaNotificationCenter.shared.post(L(.notif_added_to_queue), tone: .queue)
        scheduleGaplessPreload()
        warmUpcomingStreams()
    }

    func playNext(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        guard !queue.isEmpty else {
            queue = queueWithTrackPairings(songs).songs
            currentIndex = 0
            queueSourceTitle = "Selection"
            AppLogger.shared.log("Queued \(songs.count) next while idle", category: .playback)
            return
        }
        cancelTransitionPlayback(keepPaused: !isPlaying)
        invalidatePreloadedNext()
        insertSongsNext(queueWithTrackPairings(songs).songs)
        resetPreparedTransitionPlan()
        scheduleGaplessPreload()
        prepareTransitionPlanIfNeeded()
        warmUpcomingStreams()
    }

    func addToQueue(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        guard !queue.isEmpty else { playQueue(songs, startIndex: 0, source: "Selection"); return }
        queue.append(contentsOf: queueWithTrackPairings(songs).songs)
        scheduleGaplessPreload()
        warmUpcomingStreams()
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

    private func queueWithTrackPairings(_ songs: [Song], startIndex: Int = 0) -> (songs: [Song], startIndex: Int) {
        guard !songs.isEmpty else { return (songs, startIndex) }
        var expanded: [Song] = []
        var adjustedStartIndex = min(max(0, startIndex), songs.count - 1)

        for (index, song) in songs.enumerated() {
            if index == startIndex { adjustedStartIndex = expanded.count }
            expanded.append(song)
            let originalNext = songs.indices.contains(index + 1) ? songs[index + 1] : nil
            appendTrackPairingChain(after: song, to: &expanded, originalNext: originalNext)
        }

        return (expanded, adjustedStartIndex)
    }

    private func appendTrackPairingChain(after song: Song, to expanded: inout [Song], originalNext: Song?) {
        var seen: Set<String> = [song.id]
        var cursor = song

        while let paired = TrackPairingStore.shared.pairedSong(after: cursor) {
            if originalNext?.id == paired.id { return }
            guard !seen.contains(paired.id) else { return }
            expanded.append(paired)
            seen.insert(paired.id)
            cursor = paired
        }
    }

    private func pairedShuffleGroups(_ songs: [Song]) -> [[Song]] {
        guard !songs.isEmpty else { return [] }
        var groups: [[Song]] = []
        var index = 0

        while index < songs.count {
            var group = [songs[index]]
            var cursor = songs[index]
            index += 1

            while index < songs.count,
                  let paired = TrackPairingStore.shared.pairedSong(after: cursor),
                  songs[index].id == paired.id {
                group.append(songs[index])
                cursor = songs[index]
                index += 1
            }

            groups.append(group)
        }

        return groups
    }

    func removeQueueItem(at index: Int) {
        guard index >= 0, index < queue.count else { return }
        cancelTransitionPlayback(keepPaused: !isPlaying)
        if index == currentIndex + 1 { resetPreparedTransitionPlan() }
        queue.remove(at: index)
        if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex {
            if currentIndex >= queue.count { currentIndex = max(0, queue.count - 1) }
            if !queue.isEmpty { playCurrent() }
        }
        scheduleGaplessPreload()
        prepareTransitionPlanIfNeeded()
        warmUpcomingStreams()
    }

    // MARK: - Modes

    func toggleShuffle() {
        isShuffle.toggle()
        guard isShuffle else { return }
        cancelTransitionPlayback(keepPaused: !isPlaying)
        shuffleUpcoming()
        // Rebuild the preloaded next item and transition for the new order.
        invalidatePreloadedNext()
        resetPreparedTransitionPlan()
        scheduleGaplessPreload()
        if Date() >= transitionSuppressedUntil { prepareTransitionPlanIfNeeded() }
        warmUpcomingStreams()
    }

    // Shuffle only the songs after the current one; played + current stay put.
    private func shuffleUpcoming() {
        let start = currentIndex + 1
        guard start < queue.count else { return }
        var anchorEnd = start
        var cursor = queue[currentIndex]
        while anchorEnd < queue.count,
              let paired = TrackPairingStore.shared.pairedSong(after: cursor),
              queue[anchorEnd].id == paired.id {
            cursor = queue[anchorEnd]
            anchorEnd += 1
        }

        let anchoredPairing = Array(queue[start..<anchorEnd])
        var groups = pairedShuffleGroups(Array(queue[anchorEnd...]))
        groups.shuffle()
        queue.replaceSubrange(start..., with: anchoredPairing + groups.flatMap { $0 })
    }

    func cycleRepeat() {
        cancelTransitionPlayback(keepPaused: !isPlaying)
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        resetPreparedTransitionPlan()
        scheduleGaplessPreload()
        prepareTransitionPlanIfNeeded()
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
        if nextMode != transitionMode {
            cancelTransitionPlayback(keepPaused: !isPlaying)
        }
        transitionMode = nextMode
        UserDefaults.standard.set(nextMode.rawValue, forKey: "playbackTransitionMode")
        UserDefaults.standard.set(nextMode != .off, forKey: "crossfadeEnabled")
        resetPreparedTransitionPlan()
        if let item = player.currentItem { applyEqualizer(to: item) }
        if nextMode == .off {
            cancelTransitionPlayback()
            scheduleGaplessPreload()
            Task { await AutoMixAnalysisService.shared.cancelAll() }
        } else {
            invalidatePreloadedNext()
            clearPriming()
            refreshAutoMixAnalysisWindow()
            prepareTransitionPlanIfNeeded()
        }
    }

    func refreshGaplessPlaybackMode() {
        invalidatePreloadedNext()
        scheduleGaplessPreload()
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
        AppLogger.shared.log("Sleep timer set for \(minutes) minutes", category: .playback)
    }

    func startSleepTimerEndOfTrack() {
        cancelSleepTimer()
        sleepEndsAtTrackEnd = true
        sleepTimerActive = true
        // With actionAtItemEnd=.advance, removing the prepared item is what
        // guarantees the next track cannot begin before the end callback pauses.
        invalidatePreloadedNext()
        AppLogger.shared.log("Sleep timer set for end of track", category: .playback)
    }

    func cancelSleepTimer(resumeGaplessPreload: Bool = true) {
        let wasEndingAtTrackEnd = sleepEndsAtTrackEnd
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerActive = false
        sleepEndsAtTrackEnd = false
        sleepRemaining = 0
        if wasEndingAtTrackEnd, resumeGaplessPreload {
            scheduleGaplessPreload()
        }
    }

    private func fireSleep() {
        AppLogger.shared.log("Sleep timer fired; pausing playback", category: .playback)
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

        guard !Task.isCancelled, !fresh.isEmpty else { return }
        queue.append(contentsOf: queueWithTrackPairings(Array(fresh.prefix(30))).songs)
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

        switch AutoMixStyle.current {
        case .tight:
            let lead = Array(sameArtist.prefix(4)) + Array(sameGenre.prefix(12))
            let tail = Array(sameArtist.dropFirst(4)) + Array(sameGenre.dropFirst(12)) + rest
            return lead + tail.shuffled()
        case .wide:
            let lead = Array(sameGenre.prefix(4)) + Array(rest.prefix(6))
            let tail = sameArtist + Array(sameGenre.dropFirst(4)) + Array(rest.dropFirst(6))
            return lead.shuffled() + tail.shuffled()
        case .balanced:
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

    private func recordCurrentSongInHistory(unless nextSongID: String? = nil) {
        guard let song = currentSong,
              song.id != nextSongID else { return }

        playbackHistory.removeAll { $0.id == song.id }
        playbackHistory.insert(song, at: 0)
        if playbackHistory.count > PlaybackHistoryStore.maxCount {
            playbackHistory.removeLast(playbackHistory.count - PlaybackHistoryStore.maxCount)
        }
        persistPlaybackHistory()
    }

    private func loadPlaybackHistory(for serverID: String?) {
        playbackHistoryPersistenceGeneration &+= 1
        guard let serverID else {
            playbackHistory = []
            return
        }
        guard let data = UserDefaults.standard.data(forKey: PlaybackHistoryStore.key(for: serverID)) else {
            playbackHistory = []
            return
        }

        do {
            let songs = try JSONDecoder().decode([Song].self, from: data)
            var seen = Set<String>()
            playbackHistory = Array(songs.filter { seen.insert($0.id).inserted }.prefix(PlaybackHistoryStore.maxCount))
        } catch {
            AppLogger.shared.log(
                "Playback history unreadable: \(error.localizedDescription)",
                category: .playback,
                level: .warning
            )
            playbackHistory = []
            UserDefaults.standard.removeObject(forKey: PlaybackHistoryStore.key(for: serverID))
        }
    }

    private func persistPlaybackHistory() {
        guard let currentServerID else { return }
        playbackHistoryPersistenceGeneration &+= 1
        let generation = playbackHistoryPersistenceGeneration
        let songs = Array(playbackHistory.prefix(PlaybackHistoryStore.maxCount))
        let key = PlaybackHistoryStore.key(for: currentServerID)
        PlaybackHistoryStore.persistenceQueue.async { [weak self] in
            do {
                let data = try JSONEncoder().encode(songs)
                Task { @MainActor [weak self] in
                    guard let self,
                          self.playbackHistoryPersistenceGeneration == generation,
                          self.currentServerID == currentServerID else { return }
                    UserDefaults.standard.set(data, forKey: key)
                }
            } catch {
                let message = error.localizedDescription
                Task { @MainActor in
                    AppLogger.shared.log(
                        "Playback history save failed: \(message)",
                        category: .playback,
                        level: .warning
                    )
                }
            }
        }
    }

    private func playCurrent() {
        guard !queue.isEmpty, currentIndex < queue.count else { return }
        // Invalidate a launch-restored placeholder as soon as a concrete track
        // request wins. Otherwise controls pressed while stream metadata warms
        // can accidentally try to resume the old, item-less session.
        playbackPreparationTask?.cancel()
        playbackPreparationTask = nil
        deferredRestoredTime = nil
        enforceTrackPairingChainAfterCurrent()
        let song = queue[currentIndex]
        playRequestID &+= 1
        let token = playRequestID

        // Plex needs the file part key cached before streamURL can serve the
        // original; warm it (only when streaming and not already ready) so we
        // never silently fall back to a transcode. The common case stays fully
        // synchronous, so playback latency is unchanged.
        if let client,
           DownloadService.shared.localURL(for: song) == nil,
           !client.streamMetadataReady(for: song) {
            Task { @MainActor [weak self] in
                await client.prepareForPlayback(song: song)
                guard let self, token == self.playRequestID else { return }
                self.startPlaying(song: song)
                self.warmUpcomingStreams()
            }
            return
        }

        startPlaying(song: song)
        warmUpcomingStreams()
    }

    private func enforceTrackPairingChainAfterCurrent() {
        guard queue.indices.contains(currentIndex) else { return }
        var insertionIndex = currentIndex + 1
        var cursor = queue[currentIndex]
        var seen: Set<String> = [cursor.id]
        var changed = false

        while let paired = TrackPairingStore.shared.pairedSong(after: cursor) {
            guard !seen.contains(paired.id) else { break }
            seen.insert(paired.id)

            if queue.indices.contains(insertionIndex), queue[insertionIndex].id == paired.id {
                cursor = queue[insertionIndex]
                insertionIndex += 1
                continue
            }

            if insertionIndex < queue.count,
               let existingIndex = queue[insertionIndex...].firstIndex(where: { $0.id == paired.id }) {
                let existing = queue.remove(at: existingIndex)
                queue.insert(existing, at: insertionIndex)
            } else {
                queue.insert(paired, at: insertionIndex)
            }

            changed = true
            cursor = paired
            insertionIndex += 1
        }

        if changed {
            invalidatePreloadedNext()
            resetPreparedTransitionPlan()
            AppLogger.shared.log("Track pairing enforced after current song; index=\(currentIndex)", category: .playback)
        }
    }

    // Best-effort metadata warmup for upcoming original streams.
    private func warmUpcomingStreams() {
        guard let client else { return }
        let gaplessMode = GaplessPlaybackMode.current
        let reservedNextIndex = automaticNextQueueIndex().flatMap { index -> Int? in
            guard gaplessMode.preparesSuccessor,
                  queue.indices.contains(index),
                  canUseGaplessForCurrentTransition(nextIndex: index) else { return nil }
            return index
        }
        let reservedNextSongID = reservedNextIndex.map { queue[$0].id }
        var cacheCandidates = Array(
            queue.dropFirst(currentIndex + 1)
                .filter { !gaplessMode.enqueuesSuccessor || $0.id != reservedNextSongID }
                .prefix(5)
        )
        if cacheCandidates.isEmpty,
           let nextIndex = automaticNextQueueIndex(),
           queue.indices.contains(nextIndex),
           !gaplessMode.enqueuesSuccessor || nextIndex != reservedNextIndex {
            cacheCandidates = [queue[nextIndex]]
        }
        PlaybackCacheService.shared.prefetch(cacheCandidates, client: client)

        let upper = min(currentIndex + 3, queue.count)
        guard currentIndex + 1 < upper else { return }
        let songs = Array(queue[(currentIndex + 1)..<upper]
            .filter {
                $0.id != reservedNextSongID
                    && DownloadService.shared.localURL(for: $0) == nil
                    && !client.streamMetadataReady(for: $0)
            })
        guard !songs.isEmpty else { return }
        // Cancel the prior warmup so a skip burst doesn't flood the server.
        warmStreamsTask?.cancel()
        warmStreamsTask = Task { @MainActor in
            for song in songs {
                if Task.isCancelled { return }
                await client.prepareForPlayback(song: song)
            }
        }
    }

    // The single source of truth for an automatic, natural-end transition.
    // Manual skips intentionally retain their existing repeat semantics.
    private func automaticNextQueueIndex() -> Int? {
        guard !queue.isEmpty,
              queue.indices.contains(currentIndex),
              repeatMode != .one else { return nil }
        let nextIndex = currentIndex + 1
        if queue.indices.contains(nextIndex) {
            return nextIndex
        }
        return repeatMode == .all ? 0 : nil
    }

    private func invalidatePreloadedNext() {
        gaplessPreloadGeneration &+= 1
        gaplessPreloadTask?.cancel()
        gaplessPreloadTask = nil
        gaplessNextStatusObservation?.invalidate()
        gaplessNextStatusObservation = nil
        if let gaplessNextItem {
            if gaplessNextItem !== currentPlayerItem,
               gaplessNextItem !== player.currentItem,
               player.items().contains(where: { $0 === gaplessNextItem }) {
                player.remove(gaplessNextItem)
            }
            if gaplessNextItem !== currentPlayerItem,
               gaplessNextItem !== player.currentItem {
                releaseAudioPipeline(for: gaplessNextItem)
            }
        }
        gaplessNextItem = nil
        gaplessNextSongID = nil
        gaplessNextSource = nil
        gaplessNextUsesTranscode = false
        gaplessNextQueueIndex = nil
        gaplessReadinessLoggedItemID = nil
    }

    private func startPlaying(song: Song) {
        cancelTransitionPlayback()
        resetPreparedTransitionPlan()
        playbackPreparationTask?.cancel()
        playbackPreparationTask = nil
        deferredRestoredTime = nil
        inactivePlayer.pause()
        for item in inactivePlayer.items() { releaseAudioPipeline(for: item) }
        inactivePlayer.removeAllItems()
        guard let urlInfo = playbackURL(for: song) else {
            AppLogger.shared.log("Playback failed: no stream URL for '\(song.title)'", category: .playback, level: .error)
            return
        }
        let reusableWeakItem: AVPlayerItem? = {
            guard GaplessPlaybackMode.current == .weak,
                  gaplessNextSongID == song.id,
                  gaplessNextQueueIndex == currentIndex,
                  let item = gaplessNextItem,
                  let assetURL = (item.asset as? AVURLAsset)?.url,
                  assetURL == urlInfo.url else { return nil }
            return item
        }()
        invalidatePreloadedNext()
        let item = reusableWeakItem ?? makePlayerItem(playback: urlInfo)
        let requestToken = playRequestID
        let desiredMode = desiredAudioProcessingMode
        if desiredMode != audioProcessingMode(for: item) {
            // The item is not player-owned yet, so the preparation task must
            // hold it strongly until beginPlayback inserts it.
            playbackPreparationTask = Task { @MainActor [weak self, item] in
                guard let self else { return }
                defer {
                    if requestToken == self.playRequestID {
                        self.playbackPreparationTask = nil
                    }
                }
                let processingReady = await self.prepareAudioProcessing(for: item)
                guard !Task.isCancelled,
                      requestToken == self.playRequestID,
                      self.queue.indices.contains(self.currentIndex),
                      self.queue[self.currentIndex].id == song.id else { return }
                if !processingReady {
                    // Playback must remain available even if a tap cannot be
                    // constructed for an unusual asset.
                    item.audioMix = nil
                    self.setAudioProcessingMode(.none, for: item)
                    AppLogger.shared.log(
                        "Audio processing unavailable; playing unprocessed audio for '\(song.title)'",
                        category: .playback,
                        level: .warning
                    )
                }
                self.beginPlayback(song: song, item: item, urlInfo: urlInfo)
            }
            return
        }
        beginPlayback(song: song, item: item, urlInfo: urlInfo)
    }

    private func beginPlayback(song: Song, item: AVPlayerItem, urlInfo: PlaybackURLInfo) {
        startupDiagnosticsTask?.cancel()
        recordCurrentSongInHistory(unless: song.id)
        if urlInfo.source.isUserDownload { DownloadService.shared.markPlayed(song.id) }
        prematureTranscodeEndRetries.removeValue(forKey: song.id)
        AppLogger.shared.log(
            "Track starting; title='\(song.title)'; artist='\(song.artist ?? "?")'; source=\(urlInfo.source.rawValue); index=\(currentIndex); queueCount=\(queue.count); stream=\(Self.streamingPreferenceSummary(for: song))",
            category: .playback
        )

        player.pause()
        for existing in player.items() { releaseAudioPipeline(for: existing) }
        player.removeAllItems()
        player.insert(item, after: nil)
        currentPlayerItem = item
        currentPlaybackSource = urlInfo.source
        currentPlaybackUsesTranscode = urlInfo.usesTranscode
        try? AVAudioSession.sharedInstance().setActive(true)
        startPlayer(player, source: urlInfo.source, usesTranscode: urlInfo.usesTranscode)
        applyReplayGain(for: song)
        currentArtwork = nil
        currentAnimatedArtwork = nil
        currentLiveArtwork = nil
        hasActivePlaybackSession = true
        currentSong = song
        currentSongStartedAt = Date()
        isPlaying = true
        currentTime = 0
        duration = Double(song.duration ?? 0)
        loggedSongIDs.remove(song.id)

        if song.starred != nil {
            starredIDs.insert(song.id)
        }

        updateNowPlaying()
        notifyNowPlaying(for: song)
        persistLastPlaybackSession()
        artworkLoadTask?.cancel()
        artworkLoadTask = Task { [weak self] in await self?.loadArtwork(for: song) }
        durationLoadTask?.cancel()
        durationLoadTask = Task { [weak self] in await self?.loadDuration(from: item) }
        monitorStartup(for: item, song: song, source: urlInfo.source)
        scheduleGaplessPreload()
        ensureAutoplayPreloadedIfNeeded()
        if Date() >= transitionSuppressedUntil {
            prepareTransitionPlanIfNeeded()
        }
    }

    private func scheduleGaplessPreload() {
        let mode = GaplessPlaybackMode.current
        guard mode.preparesSuccessor,
              !sleepEndsAtTrackEnd,
              let currentItem = player.currentItem,
              currentItem === currentPlayerItem,
              let nextIndex = automaticNextQueueIndex(),
              canUseGaplessForCurrentTransition(nextIndex: nextIndex) else {
            invalidatePreloadedNext()
            return
        }
        let nextSong = queue[nextIndex]
        if gaplessRetrySongID != nextSong.id {
            gaplessRetrySongID = nextSong.id
            gaplessRetryCount = 0
        }
        guard gaplessRetryCount < 2 else { return }

        // Keep an already-buffering item, even if its cache download completes
        // later. Replacing it near the boundary would throw away useful data.
        if gaplessNextSongID == nextSong.id,
           let gaplessNextItem,
           (mode == .weak || player.items().contains(where: { $0 === gaplessNextItem })) {
            gaplessNextQueueIndex = nextIndex
            return
        }
        if gaplessNextSongID == nextSong.id, gaplessPreloadTask != nil {
            gaplessNextQueueIndex = nextIndex
            return
        }

        invalidatePreloadedNext()
        gaplessNextSongID = nextSong.id
        gaplessNextQueueIndex = nextIndex
        let generation = gaplessPreloadGeneration

        // Resolve server-specific metadata (notably Plex's original-file part
        // key) before choosing the URL. Resolving first prevents an accidental
        // fallback transcode from changing the decoder format at the boundary.
        gaplessPreloadTask = Task { @MainActor [weak self, weak currentItem] in
            guard let self, let currentItem else { return }
            if DownloadService.shared.localURL(for: nextSong) == nil,
               let client = self.client,
               !client.streamMetadataReady(for: nextSong) {
                await client.prepareForPlayback(song: nextSong)
            }
            guard !Task.isCancelled,
                  generation == self.gaplessPreloadGeneration,
                  self.gaplessNextSongID == nextSong.id,
                  self.gaplessNextQueueIndex == nextIndex,
                  self.player.currentItem === currentItem,
                  self.currentPlayerItem === currentItem,
                  GaplessPlaybackMode.current == mode else { return }

            guard let urlInfo = self.playbackURL(for: nextSong) else {
                AppLogger.shared.log(
                    "Gapless pre-buffer skipped: no stream URL for '\(nextSong.title)'",
                    category: .playback,
                    level: .warning
                )
                self.invalidatePreloadedNext()
                return
            }
            let nextItem = self.makePlayerItem(playback: urlInfo)
            self.gaplessNextSource = urlInfo.source
            self.gaplessNextUsesTranscode = urlInfo.usesTranscode

            if self.audioProcessingRequired {
                let processingReady = await self.prepareAudioProcessing(for: nextItem)
                guard !Task.isCancelled else { return }
                if !processingReady {
                    nextItem.audioMix = nil
                    self.setAudioProcessingMode(.none, for: nextItem)
                    AppLogger.shared.log(
                        "Gapless successor will play without audio processing; title='\(nextSong.title)'",
                        category: .playback,
                        level: .warning
                    )
                }
            }
            guard !Task.isCancelled, generation == self.gaplessPreloadGeneration else { return }
            self.insertPreparedGaplessItem(
                nextItem,
                after: currentItem,
                song: nextSong,
                index: nextIndex,
                source: urlInfo.source,
                mode: mode,
                generation: generation
            )
        }
    }

    private func canUseGaplessForCurrentTransition(nextIndex: Int) -> Bool {
        if transitionMode == .off { return true }
        guard transitionMode == .automix,
              queue.indices.contains(currentIndex),
              queue.indices.contains(nextIndex) else { return false }
        return shouldPreserveIntendedHandoff(
            current: queue[currentIndex],
            next: queue[nextIndex]
        )
    }

    private func isTrackPairing(current: Song, next: Song) -> Bool {
        guard TrackPairingStore.bypassAutoMixEnabled,
              let paired = TrackPairingStore.shared.pairedSong(after: current) else { return false }
        return paired.id == next.id
    }

    private func shouldPreserveIntendedHandoff(current: Song, next: Song) -> Bool {
        guard transitionMode == .automix else { return false }
        if isTrackPairing(current: current, next: next) { return true }
        return autoMixContext(for: current).isSequentialAlbumTrack(before: autoMixContext(for: next))
    }

    private func insertPreparedGaplessItem(
        _ nextItem: AVPlayerItem,
        after currentItem: AVPlayerItem,
        song: Song,
        index: Int,
        source: PlaybackURLSource,
        mode: GaplessPlaybackMode,
        generation: UInt64
    ) {
        gaplessPreloadTask = nil
        guard mode.preparesSuccessor,
              GaplessPlaybackMode.current == mode,
              generation == gaplessPreloadGeneration,
              !sleepEndsAtTrackEnd,
              player.currentItem === currentItem,
              currentPlayerItem === currentItem,
              automaticNextQueueIndex() == index,
              canUseGaplessForCurrentTransition(nextIndex: index),
              queue.indices.contains(index),
              queue[index].id == song.id,
              gaplessNextSongID == song.id,
              gaplessNextQueueIndex == index else { return }
        if mode.enqueuesSuccessor, !player.canInsert(nextItem, after: currentItem) {
            AppLogger.shared.log(
                "Gapless pre-buffer skipped: AVQueuePlayer rejected next item for '\(song.title)'",
                category: .playback,
                level: .warning
            )
            invalidatePreloadedNext()
            return
        }
        gaplessNextItem = nextItem
        gaplessNextStatusObservation?.invalidate()
        gaplessNextStatusObservation = nextItem.observe(\.status, options: [.new]) { [weak self, weak nextItem] _, _ in
            Task { @MainActor in
                guard let self, let nextItem,
                      nextItem.status == .failed,
                      self.gaplessNextItem === nextItem,
                      self.gaplessNextSongID == song.id else { return }
                self.gaplessRetryCount += 1
                AppLogger.shared.log(
                    "Gapless successor failed before handoff; title='\(song.title)'; error=\(nextItem.error?.localizedDescription ?? "unknown")",
                    category: .playback,
                    level: .warning
                )
                self.invalidatePreloadedNext()
                self.scheduleGaplessPreload()
            }
        }
        if mode.enqueuesSuccessor {
            // Precise transitions must not add an automatic boundary wait.
            player.automaticallyWaitsToMinimizeStalling = false
            player.insert(nextItem, after: currentItem)
        }
        AppLogger.shared.log(
            "Gapless successor prepared; mode=\(mode.rawValue); enqueued=\(mode.enqueuesSuccessor); title='\(song.title)'; index=\(index); source=\(source.rawValue); effects=\(nextItem.audioMix == nil ? "off" : "prepared"); preferredBuffer=\(String(format: "%.0f", nextItem.preferredForwardBufferDuration))s",
            category: .playback
        )
    }

    private func completeQueuedGaplessHandoff(
        finishedItem: AVPlayerItem,
        outgoingEndedAt: TimeInterval
    ) -> Bool {
        guard GaplessPlaybackMode.current.enqueuesSuccessor,
              let nextIndex = automaticNextQueueIndex(),
              canUseGaplessForCurrentTransition(nextIndex: nextIndex),
              let queuedItem = gaplessNextItem,
              gaplessNextQueueIndex == nextIndex else { return false }

        let song = queue[nextIndex]
        guard gaplessNextSongID == song.id else {
            AppLogger.shared.log(
                "Gapless handoff rejected: queued song id mismatch; expected=\(song.id); queued=\(gaplessNextSongID ?? "nil")",
                category: .playback,
                level: .warning
            )
            invalidatePreloadedNext()
            return false
        }

        let advancedAutomatically = player.currentItem === queuedItem
        var requiredFallback = false
        if !advancedAutomatically,
           player.currentItem === finishedItem,
           player.items().contains(where: { $0 === queuedItem }) {
            AppLogger.shared.log(
                "Gapless automatic advance failed; using AVQueuePlayer fallback for '\(song.title)'",
                category: .playback,
                level: .warning
            )
            requiredFallback = true
            player.advanceToNextItem()
        }

        guard let activeItem = player.currentItem, activeItem === queuedItem else {
            AppLogger.shared.log(
                "Gapless handoff fell back: queued item was not active for '\(song.title)'",
                category: .playback,
                level: .warning
            )
            invalidatePreloadedNext()
            return false
        }

        AppLogger.shared.log(
            "Gapless handoff: AVQueuePlayer \(requiredFallback ? "required fallback" : "advanced automatically"); title='\(song.title)'",
            category: .playback
        )
        recordCurrentSongInHistory(unless: song.id)
        let activeSource = gaplessNextSource ?? .stream
        let activeUsesTranscode = gaplessNextUsesTranscode
        startupDiagnosticsTask?.cancel()
        currentIndex = nextIndex
        currentPlayerItem = queuedItem
        currentPlaybackSource = activeSource
        currentPlaybackUsesTranscode = activeUsesTranscode
        prematureTranscodeEndRetries.removeValue(forKey: song.id)
        gaplessNextStatusObservation?.invalidate()
        gaplessNextStatusObservation = nil
        gaplessNextItem = nil
        gaplessNextSongID = nil
        gaplessNextSource = nil
        gaplessNextUsesTranscode = false
        gaplessNextQueueIndex = nil
        gaplessReadinessLoggedItemID = nil
        gaplessRetrySongID = nil
        gaplessRetryCount = 0
        if DownloadService.shared.localURL(for: song) != nil {
            DownloadService.shared.markPlayed(song.id)
        }
        applyReplayGain(for: song)
        currentArtwork = nil
        currentAnimatedArtwork = nil
        currentLiveArtwork = nil
        hasActivePlaybackSession = true
        currentSong = song
        let incomingTime = queuedItem.currentTime().seconds
        let startedOffset = incomingTime.isFinite ? max(0, incomingTime) : 0
        currentSongStartedAt = Date(timeIntervalSinceNow: -startedOffset)
        currentTime = startedOffset
        duration = Double(song.duration ?? 0)
        loggedSongIDs.remove(song.id)
        if song.starred != nil { starredIDs.insert(song.id) }

        AppLogger.shared.log(
            "Gapless handoff active; title='\(song.title)'; index=\(currentIndex)",
            category: .playback
        )
        updateNowPlaying()
        notifyNowPlaying(for: song)
        persistLastPlaybackSession()
        artworkLoadTask?.cancel()
        artworkLoadTask = Task { [weak self] in await self?.loadArtwork(for: song) }
        durationLoadTask?.cancel()
        durationLoadTask = Task { [weak self] in await self?.loadDuration(from: queuedItem) }
        monitorStartup(for: queuedItem, song: song, source: activeSource)
        ensureAutoplayPreloadedIfNeeded()
        warmUpcomingStreams()
        if isPlaying, player.rate == 0 {
            try? AVAudioSession.sharedInstance().setActive(true)
            startPlayer(player, source: activeSource, usesTranscode: activeUsesTranscode)
        }
        measureGaplessStartDelay(for: queuedItem, outgoingEndedAt: outgoingEndedAt)
        scheduleGaplessPreload()
        refreshAutoMixAnalysisWindow()
        prepareTransitionPlanIfNeeded()
        return true
    }

    private func prepareTransitionPlanIfNeeded() {
        guard !PerformanceMode.simpleTransitions else {
            resetPreparedTransitionPlan()
            return
        }
        if transitionMode == .automix, !Self.canUseAutoMix {
            setTransitionMode(.crossfade)
            return
        }
        guard transitionMode != .off,
              !isTransitioning,
              currentIndex + 1 < queue.count,
              let current = currentSong else {
            resetPreparedTransitionPlan()
            return
        }
        let next = queue[currentIndex + 1]
        refreshAutoMixAnalysisWindow()
        if shouldPreserveIntendedHandoff(current: current, next: next) {
            resetPreparedTransitionPlan()
            scheduleGaplessPreload()
            return
        }

        let key = "\(transitionMode.rawValue):\(AutoMixStyle.current.rawValue):\(current.id)->\(next.id)"
        guard transitionPlanKey != key else { return }
        if primedSongID != nil && primedSongID != next.id { clearPriming() }
        resetPreparedTransitionPlan()
        transitionPlanKey = key

        let outgoing = autoMixContext(for: current)
        let incoming = autoMixContext(for: next)
        if transitionMode == .crossfade {
            let plan = autoMixPlanner.fixedCrossfade(
                outgoing: outgoing,
                incoming: incoming,
                currentTime: liveTime(),
                duration: PlaybackTransitionSettings.crossfadeDuration(
                    sameAlbum: current.albumId != nil && current.albumId == next.albumId
                )
            )
            preparedTransitionPlan = plan
            schedulePreparedTransition(plan, nextSong: next, key: key)
            return
        }

        let outgoingRequest = autoMixAnalysisRequest(for: current)
        let incomingRequest = autoMixAnalysisRequest(for: next)
        transitionPlanTask = Task { @MainActor [weak self] in
            guard let self else { return }
            async let outgoingAnalysis = AutoMixAnalysisService.shared.analysis(for: outgoingRequest)
            async let incomingAnalysis = AutoMixAnalysisService.shared.analysis(for: incomingRequest)
            let plan = self.autoMixPlanner.plan(
                outgoing: outgoing,
                incoming: incoming,
                outgoingAnalysis: await outgoingAnalysis,
                incomingAnalysis: await incomingAnalysis,
                constraints: self.autoMixConstraints(current: current, next: next)
            )
            guard !Task.isCancelled,
                  self.transitionPlanKey == key,
                  self.currentSong?.id == current.id,
                  self.currentIndex + 1 < self.queue.count,
                  self.queue[self.currentIndex + 1].id == next.id else { return }
            self.transitionPlanTask = nil
            self.preparedTransitionPlan = plan
            if plan.type == .intendedGapless {
                self.resetPreparedTransitionPlan()
                self.scheduleGaplessPreload()
            } else {
                self.schedulePreparedTransition(plan, nextSong: next, key: key)
            }
        }
    }

    private func schedulePreparedTransition(
        _ plan: AutoMixTransitionPlan,
        nextSong: Song,
        key: String
    ) {
        guard !isTransitioning,
              plan.usesDualPlayers,
              activePlayer.currentItem === currentPlayerItem else { return }
        let now = liveTime()
        guard plan.outgoingCue > now - 0.15 else {
            let duration = liveDuration()
            guard let fallback = plan.readinessFallback(
                outgoingNow: now + 0.1,
                outgoingDuration: duration
            ) else { return }
            preparedTransitionPlan = fallback
            schedulePreparedTransition(fallback, nextSong: nextSong, key: key)
            return
        }
        let primeTime = max(now, plan.outgoingCue - max(8, min(16, plan.duration + 5)))
        autoMixCoordinator.armOutgoing(
            player: activePlayer,
            primeTime: primeTime,
            transitionTime: plan.outgoingCue,
            onPrime: { [weak self] in
                guard let self, self.transitionPlanKey == key else { return }
                self.primeNext(nextSong, plan: plan)
            },
            onTransition: { [weak self] in
                guard let self, self.transitionPlanKey == key else { return }
                self.attemptPlannedTransition(plan, nextSong: nextSong)
            }
        )
    }

    private func resetPreparedTransitionPlan() {
        transitionPlanTask?.cancel()
        transitionPlanTask = nil
        transitionPlanKey = nil
        preparedTransitionPlan = nil
        readinessRetryCount = 0
        if !isTransitioning { autoMixCoordinator.cancel() }
    }

    private func suppressTransitionsBriefly() {
        transitionSuppressedUntil = Date().addingTimeInterval(2)
        resetPreparedTransitionPlan()
    }

    private func autoMixContext(for song: Song) -> AutoMixTrackContext {
        AutoMixTrackContext(
            id: song.id,
            title: song.title,
            albumID: song.albumId,
            artistID: song.artistId,
            genre: song.genre,
            trackNumber: song.track,
            discNumber: song.discNumber,
            duration: Double(song.duration ?? 0),
            hasReplayGain: song.replayGain != nil
        )
    }

    private func autoMixConstraints(current: Song, next: Song) -> AutoMixPlaybackConstraints {
        let replayGainMode = UserDefaults.standard.string(forKey: "replayGainMode") ?? "off"
        return AutoMixPlaybackConstraints(
            currentTime: liveTime(),
            outgoingDuration: max(liveDuration(), Double(current.duration ?? 0)),
            incomingReady: primedReady,
            trackPairing: isTrackPairing(current: current, next: next),
            replayGainModeEnabled: replayGainMode != "off",
            style: AutoMixStyle.current,
            maximumOverlap: PlaybackTransitionSettings.maxBlend,
            minimumEndLead: PlaybackTransitionSettings.minimumEndLead
        )
    }

    private func autoMixAnalysisRequest(for song: Song) -> AutoMixAnalysisRequest {
        let source: AutoMixAudioSource
        if let local = DownloadService.shared.localURL(for: song) {
            source = .file(url: local, source: .download, complete: true)
        } else if let client,
                  let cached = PlaybackCacheService.shared.analysisURL(for: song, client: client) {
            source = .file(url: cached, source: .playbackCache, complete: true)
        } else if let client,
                  let remote = client.originalStreamURL(id: song.id) ?? client.streamURL(for: song) {
            let requestedSeconds: TimeInterval = 120
            let bytesPerSecond: Double?
            if let bitRate = song.bitRate, bitRate > 0 {
                bytesPerSecond = Double(bitRate) * 125
            } else if let size = song.size,
                      let duration = song.duration,
                      size > 0, duration > 0 {
                bytesPerSecond = Double(size) / Double(duration)
            } else {
                bytesPerSecond = nil
            }
            let targetBytes = bytesPerSecond.map { Int(($0 * requestedSeconds).rounded(.up)) }
                ?? 6 * 1_048_576
            source = .remote(
                url: remote,
                headers: client.mediaRequestHeaders(),
                fileExtension: song.suffix ?? "audio",
                requestedSeconds: requestedSeconds,
                maximumBytes: min(12 * 1_048_576, max(2 * 1_048_576, targetBytes))
            )
        } else {
            source = .unavailable
        }
        return AutoMixAnalysisRequest(
            trackID: song.id,
            duration: Double(song.duration ?? 0),
            fileSize: song.size,
            bitrateKbps: song.bitRate,
            metadataBPM: song.bpm.flatMap { $0 > 0 ? Double($0) : nil },
            source: source
        )
    }

    private func refreshAutoMixAnalysisWindow() {
        guard transitionMode == .automix else {
            Task { await AutoMixAnalysisService.shared.cancelAll() }
            return
        }
        let lower = max(0, currentIndex)
        let upper = min(queue.count, lower + 3)
        guard lower < upper else { return }
        let requests = queue[lower..<upper].map(autoMixAnalysisRequest(for:))
        Task { await AutoMixAnalysisService.shared.setUpcoming(requests) }
    }

    func estimatedBPM(for song: Song) async -> Double? {
        await autoMixAnalysis(for: song).estimatedBPM
    }

    func autoMixAnalysis(for song: Song) async -> AutoMixTrackAnalysis {
        await AutoMixAnalysisService.shared.analysis(for: autoMixAnalysisRequest(for: song))
    }

    func autoMixPlan(current: Song, next: Song) async -> AutoMixTransitionPlan {
        async let outgoing = AutoMixAnalysisService.shared.analysis(for: autoMixAnalysisRequest(for: current))
        async let incoming = AutoMixAnalysisService.shared.analysis(for: autoMixAnalysisRequest(for: next))
        return autoMixPlanner.plan(
            outgoing: autoMixContext(for: current),
            incoming: autoMixContext(for: next),
            outgoingAnalysis: await outgoing,
            incomingAnalysis: await incoming,
            constraints: AutoMixPlaybackConstraints(
                currentTime: 0,
                outgoingDuration: Double(current.duration ?? 0),
                incomingReady: true,
                trackPairing: isTrackPairing(current: current, next: next),
                replayGainModeEnabled: (UserDefaults.standard.string(forKey: "replayGainMode") ?? "off") != "off",
                style: AutoMixStyle.current,
                maximumOverlap: PlaybackTransitionSettings.maxBlend,
                minimumEndLead: PlaybackTransitionSettings.minimumEndLead
            )
        )
    }

    func autoMixPreviewURL(for song: Song) -> URL? { playbackURL(for: song)?.url }

    private func primeNext(_ song: Song, plan: AutoMixTransitionPlan) {
        guard primedSongID != song.id,
              primingSongID != song.id,
              !isTransitioning,
              let urlInfo = playbackURL(for: song) else { return }
        let target = inactivePlayer
        let item = makePlayerItem(
            playback: urlInfo,
            requiresTimePitchProcessing: abs(plan.incomingRate - 1) >= 0.001
        )
        primingSongID = song.id
        primedReady = false
        transitionPrimeTask?.cancel()
        transitionPrimeTask = Task { @MainActor [weak self, weak target, item] in
            guard let self, let target else { return }
            let filtersRequired = plan.filters != .bypass
            if filtersRequired, let outgoingItem = self.currentPlayerItem {
                let outgoingReady = await self.prepareAudioProcessing(
                    for: outgoingItem,
                    forceAutoMixDSP: true
                )
                guard outgoingReady else { return }
            }
            let processingReady = await self.prepareAudioProcessing(
                for: item,
                forceAutoMixDSP: filtersRequired
            )
            guard !Task.isCancelled, processingReady else {
                if self.primingSongID == song.id { self.primingSongID = nil }
                self.transitionPrimeTask = nil
                AppLogger.shared.log(
                    "AutoMix priming failed: processing pipeline unavailable; songID=\(song.id)",
                    category: .playback,
                    level: .warning
                )
                return
            }
            self.installPrimedItem(
                item,
                on: target,
                song: song,
                plan: plan,
                source: urlInfo.source,
                usesTranscode: urlInfo.usesTranscode
            )
        }
    }

    private func installPrimedItem(
        _ item: AVPlayerItem,
        on target: AVQueuePlayer,
        song: Song,
        plan: AutoMixTransitionPlan,
        source: PlaybackURLSource,
        usesTranscode: Bool
    ) {
        transitionPrimeTask = nil
        guard !isTransitioning,
              transitionMode != .off,
              inactivePlayer === target,
              currentIndex + 1 < queue.count,
              queue[currentIndex + 1].id == song.id,
              primingSongID == song.id else {
            if primingSongID == song.id { primingSongID = nil }
            releaseAudioPipeline(for: item)
            return
        }
        primingSongID = nil
        primedSongID = song.id
        primedSongUsesTranscode = usesTranscode
        primedPlaybackSource = source
        primedReady = false
        target.pause()
        for existing in target.items() { releaseAudioPipeline(for: existing) }
        target.removeAllItems()
        target.insert(item, after: nil)
        target.volume = 0
        target.automaticallyWaitsToMinimizeStalling = sourceNeedsNetworkBuffer(
            source: source,
            usesTranscode: usesTranscode
        )
        let seekTime = CMTime(seconds: plan.incomingCue, preferredTimescale: 600)
        let tolerance = CMTime(seconds: 0.012, preferredTimescale: 600)
        target.seek(to: seekTime, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self, weak target, weak item] finished in
            guard finished else { return }
            Task { @MainActor [weak self, weak target, weak item] in
                guard let self, let target, let item else { return }
                self.transitionPrimeTask?.cancel()
                self.transitionPrimeTask = Task { @MainActor [weak self, weak target, weak item] in
                    guard let self, let target, let item else { return }
                    for _ in 0..<80 {
                        guard !Task.isCancelled,
                              self.primedSongID == song.id,
                              target.currentItem === item else { return }
                        if item.status == .readyToPlay {
                            self.primedReady = true
                            break
                        }
                        if item.status == .failed { break }
                        try? await Task.sleep(nanoseconds: 50_000_000)
                    }
                    self.transitionPrimeTask = nil
                    AppLogger.shared.log(
                        "AutoMix primed: songID=\(song.id); source=\(source.rawValue); ready=\(self.primedReady); buffered=\(Self.bufferedRangeSummary(item))",
                        category: .playback,
                        level: self.primedReady ? .info : .warning
                    )
                }
            }
        }
    }

    private func clearPriming() {
        transitionPrimeTask?.cancel()
        transitionPrimeTask = nil
        primingSongID = nil
        primedSongID = nil
        primedSongUsesTranscode = false
        primedPlaybackSource = nil
        primedReady = false
        guard !isTransitioning else { return }
        let target = inactivePlayer
        target.pause()
        for item in target.items() { releaseAudioPipeline(for: item) }
        target.removeAllItems()
        target.volume = 0
        target.rate = 1
    }

    private func attemptPlannedTransition(_ plan: AutoMixTransitionPlan, nextSong: Song) {
        guard !isTransitioning,
              currentIndex + 1 < queue.count,
              queue[currentIndex + 1].id == nextSong.id else { return }
        if primedSongID != nextSong.id { primeNext(nextSong, plan: plan) }

        guard primedSongID == nextSong.id,
              primedItemIsReady(for: plan) else {
            let remaining = liveDuration() - liveTime()
            if remaining > 1.4, readinessRetryCount < 8 {
                readinessRetryCount += 1
                let retryAt = liveTime() + 0.35
                autoMixCoordinator.armOutgoing(
                    player: activePlayer,
                    primeTime: liveTime(),
                    transitionTime: retryAt,
                    onPrime: {},
                    onTransition: { [weak self] in
                        self?.attemptPlannedTransition(plan, nextSong: nextSong)
                    }
                )
            } else {
                AutoMixDiagnostics.logFallback(
                    planned: plan.type,
                    actual: nil,
                    reason: "incomingNotReady"
                )
                clearPriming()
                resetPreparedTransitionPlan()
            }
            return
        }

        let actualPlan: AutoMixTransitionPlan
        if readinessRetryCount > 0,
           let fallback = plan.readinessFallback(
                outgoingNow: liveTime(),
                outgoingDuration: liveDuration()
           ) {
            actualPlan = fallback
            AutoMixDiagnostics.logFallback(
                planned: plan.type,
                actual: fallback.type,
                reason: "incomingReadyLate"
            )
        } else {
            actualPlan = plan
        }
        startPlannedTransition(actualPlan, nextSong: nextSong)
    }

    private func primedItemIsReady(for plan: AutoMixTransitionPlan) -> Bool {
        guard primedReady,
              let item = inactivePlayer.currentItem,
              item.status == .readyToPlay else { return false }
        guard primedPlaybackSource == .stream else { return true }
        let cue = plan.incomingCue
        let bufferedEnd = item.loadedTimeRanges
            .map(\.timeRangeValue.end.seconds)
            .filter(\.isFinite)
            .max() ?? 0
        let required = min(12, plan.incomingMediaDuration + 1)
        return bufferedEnd - cue >= required && item.isPlaybackLikelyToKeepUp
    }

    private func startPlannedTransition(_ plan: AutoMixTransitionPlan, nextSong: Song) {
        guard !isTransitioning,
              currentIndex + 1 < queue.count,
              queue[currentIndex + 1].id == nextSong.id,
              let nextItem = inactivePlayer.currentItem,
              let outgoingItem = activePlayer.currentItem,
              primedSongID == nextSong.id,
              primedItemIsReady(for: plan) else { return }

        let oldPlayer = activePlayer
        let newPlayer = inactivePlayer
        guard installTransitionEnvelope(on: outgoingItem, plan: plan, outgoing: true),
              installTransitionEnvelope(on: nextItem, plan: plan, outgoing: false) else {
            AutoMixDiagnostics.logFallback(
                planned: plan.type,
                actual: nil,
                reason: "audioPipelineUnavailable"
            )
            clearPriming()
            return
        }
        configureTransitionFilters(
            outgoingItem: outgoingItem,
            incomingItem: nextItem,
            plan: plan
        )

        transitionOutgoingPlayer = oldPlayer
        transitionIncomingPlayer = newPlayer
        transitionNextSong = nextSong
        activeTransitionPlan = plan
        transitionIncomingSource = primedPlaybackSource
        transitionIncomingUsesTranscode = primedSongUsesTranscode
        transitionPromoted = false
        isTransitioning = true
        isMixing = true
        primedSongID = nil
        primedPlaybackSource = nil
        primedSongUsesTranscode = false
        primedReady = false
        transitionPlanTask?.cancel()
        transitionPlanTask = nil
        preparedTransitionPlan = nil

        oldPlayer.volume = targetVolume
        newPlayer.volume = replayGainVolume(for: nextSong)
        newPlayer.playImmediately(atRate: plan.incomingRate)
        autoMixCoordinator.armHandoff(
            incomingPlayer: newPlayer,
            incomingCue: plan.incomingCue,
            incomingMediaDuration: plan.incomingMediaDuration,
            onPromote: { [weak self] in self?.promoteActiveTransition() },
            onComplete: { [weak self] in self?.completeActiveTransition() }
        )
        AppLogger.shared.log(
            "AutoMix transition started: songID=\(nextSong.id); type=\(plan.type.rawValue); duration=\(String(format: "%.3f", plan.duration)); incomingRate=\(String(format: "%.4f", plan.incomingRate))",
            category: .playback
        )
    }

    private func promoteActiveTransition() {
        guard isTransitioning,
              !transitionPromoted,
              let newPlayer = transitionIncomingPlayer,
              let nextItem = newPlayer.currentItem,
              let nextSong = transitionNextSong,
              currentIndex + 1 < queue.count,
              queue[currentIndex + 1].id == nextSong.id else { return }
        transitionPromoted = true
        recordCurrentSongInHistory(unless: nextSong.id)
        if transitionIncomingSource?.isUserDownload == true {
            DownloadService.shared.markPlayed(nextSong.id)
        }
        activePlayer = newPlayer
        currentPlayerItem = nextItem
        currentIndex += 1
        currentPlaybackSource = transitionIncomingSource
        currentPlaybackUsesTranscode = transitionIncomingUsesTranscode
        targetVolume = replayGainVolume(for: nextSong)
        currentArtwork = nil
        currentAnimatedArtwork = nil
        currentLiveArtwork = nil
        hasActivePlaybackSession = true
        currentSong = nextSong
        let incomingTime = nextItem.currentTime().seconds
        let offset = incomingTime.isFinite ? max(0, incomingTime) : 0
        currentSongStartedAt = Date(timeIntervalSinceNow: -offset)
        currentTime = offset
        duration = Double(nextSong.duration ?? 0)
        loggedSongIDs.remove(nextSong.id)
        if nextSong.starred != nil { starredIDs.insert(nextSong.id) }
        transitionPlanKey = nil

        updateNowPlaying()
        notifyNowPlaying(for: nextSong)
        persistLastPlaybackSession()
        artworkLoadTask?.cancel()
        artworkLoadTask = Task { [weak self] in await self?.loadArtwork(for: nextSong) }
        durationLoadTask?.cancel()
        durationLoadTask = Task { [weak self] in await self?.loadDuration(from: nextItem) }
        if let source = transitionIncomingSource {
            monitorStartup(for: nextItem, song: nextSong, source: source)
        }
        ensureAutoplayPreloadedIfNeeded()
        warmUpcomingStreams()
    }

    private func completeActiveTransition() {
        guard isTransitioning,
              let oldPlayer = transitionOutgoingPlayer,
              let newPlayer = transitionIncomingPlayer,
              let plan = activeTransitionPlan else { return }
        if !transitionPromoted { promoteActiveTransition() }
        guard activePlayer === newPlayer else {
            cancelTransitionPlayback()
            return
        }

        if let oldItem = oldPlayer.currentItem {
            resetTransitionEnvelope(on: oldItem, at: oldItem.currentTime().seconds)
            releaseAudioPipeline(for: oldItem)
        }
        oldPlayer.pause()
        oldPlayer.removeAllItems()
        oldPlayer.rate = 1
        oldPlayer.volume = 0
        if let newItem = newPlayer.currentItem {
            resetTransitionEnvelope(on: newItem, at: newItem.currentTime().seconds)
        }
        newPlayer.volume = targetVolume
        isMixing = false

        if abs(plan.incomingRate - 1) >= 0.001, plan.restoreRateDuration > 0 {
            let restorationStart = newPlayer.currentTime().seconds
            autoMixCoordinator.restoreRate(
                player: newPlayer,
                from: plan.incomingRate,
                startingAt: restorationStart,
                duration: plan.restoreRateDuration
            ) { [weak self] in
                self?.finishTransitionCleanup()
            }
        } else {
            newPlayer.rate = 1
            finishTransitionCleanup()
        }
    }

    private func finishTransitionCleanup() {
        guard isTransitioning else { return }
        transitionIncomingPlayer?.rate = isPlaying ? 1 : 0
        autoMixCoordinator.cancel()
        isTransitioning = false
        isMixing = false
        transitionOutgoingPlayer = nil
        transitionIncomingPlayer = nil
        transitionNextSong = nil
        activeTransitionPlan = nil
        transitionIncomingSource = nil
        transitionIncomingUsesTranscode = false
        transitionPromoted = false
        readinessRetryCount = 0
        if let item = player.currentItem { applyEqualizer(to: item) }
        scheduleGaplessPreload()
        refreshAutoMixAnalysisWindow()
        prepareTransitionPlanIfNeeded()
    }

    private func playbackURL(for song: Song) -> PlaybackURLInfo? {
        if let localURL = DownloadService.shared.localURL(for: song) {
            return (localURL, .download, false)
        }
        if let client {
            let streamURL = client.streamURL(for: song)
            let usesTranscode = streamURL.map(Self.streamURLUsesTranscode) ?? false
            if let cachedURL = PlaybackCacheService.shared.cachedURL(for: song, client: client) {
                return (cachedURL, .playbackCache, usesTranscode)
            }
            guard let streamURL else { return nil }
            return (streamURL, .stream, usesTranscode)
        }
        return nil
    }

    private static func streamURLUsesTranscode(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        if path.contains("/transcode/") || path.contains("/universal") || path.contains("/gettranscodestream") {
            return true
        }

        guard let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return false
        }

        for item in queryItems {
            let name = item.name.lowercased()
            let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            switch name {
            case "format":
                if let value, value != "raw" { return true }
            case "maxbitrate", "bitrate", "maxstreamingbitrate", "audiocodec", "transcodingcontainer", "transcodingprotocol", "transcodeparams":
                return true
            case "static":
                if value == "false" { return true }
            default:
                continue
            }
        }

        return false
    }

    private func cancelTransitionPlayback(keepPaused: Bool = false) {
        autoMixCoordinator.cancel()
        transitionPlanTask?.cancel()
        transitionPlanTask = nil
        transitionPlanKey = nil
        preparedTransitionPlan = nil
        transitionPrimeTask?.cancel()
        transitionPrimeTask = nil
        primingSongID = nil
        primedSongID = nil
        primedReady = false
        primedPlaybackSource = nil
        primedSongUsesTranscode = false
        let authoritativePlayer = activePlayer
        let discardedPlayer = authoritativePlayer === primaryPlayer ? secondaryPlayer : primaryPlayer
        if let item = authoritativePlayer.currentItem {
            resetTransitionEnvelope(on: item, at: item.currentTime().seconds)
        }
        for item in discardedPlayer.items() { releaseAudioPipeline(for: item) }
        let shouldKeepPaused = keepPaused || !isPlaying
        primaryPlayer.rate = shouldKeepPaused ? 0 : 1
        secondaryPlayer.rate = shouldKeepPaused ? 0 : 1
        discardedPlayer.pause()
        discardedPlayer.removeAllItems()
        discardedPlayer.volume = 0
        authoritativePlayer.volume = targetVolume
        isTransitioning = false
        isMixing = false
        transitionOutgoingPlayer = nil
        transitionIncomingPlayer = nil
        transitionNextSong = nil
        activeTransitionPlan = nil
        transitionIncomingSource = nil
        transitionIncomingUsesTranscode = false
        transitionPromoted = false
        readinessRetryCount = 0
        if let item = authoritativePlayer.currentItem, transitionMode != .off {
            applyEqualizer(to: item)
        }
        if shouldKeepPaused { pauseAllPlayers() }
    }

    private func pauseAllPlayers() {
        primaryPlayer.pause()
        secondaryPlayer.pause()
    }

    private func loadArtwork(for song: Song) async {
        let started = ProcessInfo.processInfo.systemUptime
        async let staticImage = loadStaticArtwork(for: song)
        async let liveResult = resolveVisualLiveArtwork(for: song)

        let image = await staticImage
        guard !Task.isCancelled, currentSong?.id == song.id else { return }
        currentArtwork = image
        AppLogger.shared.log(
            "Static artwork \(image == nil ? "unavailable" : "ready"); songID=\(song.id); elapsedMs=\(Int((ProcessInfo.processInfo.systemUptime - started) * 1000))",
            category: .playback,
            level: image == nil ? .warning : .info
        )
        if let image {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }

        // Skip the costly live-artwork decode if the track already changed.
        guard !Task.isCancelled else { return }
        let (live, liveURL) = await liveResult
        guard !Task.isCancelled, currentSong?.id == song.id else { return }
        currentLiveArtwork = live
        currentAnimatedArtwork = live?.animatedImage
        applyNowPlayingAnimatedArtwork(live)
        AppLogger.shared.log(
            "Live artwork \(live == nil ? "unavailable" : "ready for display"); songID=\(song.id); elapsedMs=\(Int((ProcessInfo.processInfo.systemUptime - started) * 1000))",
            category: .playback,
            level: live == nil && LiveArtworkSettings.shouldShowAnimatedArtwork ? .warning : .info
        )

        // Do not make the visible animation wait for lock-screen video encoding.
        guard !Task.isCancelled,
              live != nil, let liveURL, LiveArtworkSettings.prepareVideoAsset else { return }
        guard let videoAspect = await waitForSupportedLockScreenArtworkAspect() else {
            AppLogger.shared.log(
                "Lock-screen artwork preparation skipped: no supported animated-artwork key",
                category: .playback,
                level: .warning
            )
            return
        }
        let videoReady = await ArtworkLoader.shared.liveArtwork(
            for: liveURL,
            includeVideo: true,
            videoAspect: videoAspect
        )
        guard !Task.isCancelled, currentSong?.id == song.id else { return }
        if let videoReady {
            currentLiveArtwork = videoReady
            currentAnimatedArtwork = videoReady.animatedImage
            applyNowPlayingAnimatedArtwork(videoReady)
        }
        AppLogger.shared.log(
            "Lock-screen artwork preparation finished; songID=\(song.id); videoReady=\(videoReady?.videoURL != nil); elapsedMs=\(Int((ProcessInfo.processInfo.systemUptime - started) * 1000))",
            category: .playback
        )
        if videoReady?.videoURL != nil {
            scheduleAnimatedArtworkReattach(for: song)
        }
    }

    private func loadStaticArtwork(for song: Song) async -> UIImage? {
        // Match the library artwork path. In Offline Mode `client` is nil, so
        // a URL-only lookup left Now Playing empty even when a downloaded
        // album's pinned (or embedded) cover was available locally.
        let coverArtID = song.coverArt?.nonBlank ?? song.albumId?.nonBlank
        if let url = client?.coverArtURL(id: coverArtID, size: 600),
           let image = await ArtworkLoader.shared.image(for: url, maxPixelSize: 600) {
            return image
        }
        if let image = await ArtworkLoader.shared.image(
            forCoverArtID: coverArtID,
            serverID: currentServerID,
            maxPixelSize: 600
        ) {
            return image
        }
        if let source = DownloadService.shared.localArtworkSource(
            forCoverArtID: coverArtID,
            serverID: currentServerID
        ) {
            return await ArtworkLoader.shared.image(
                fromEmbeddedArtworkAt: source.url,
                coverArtID: coverArtID,
                serverID: source.serverID,
                groupID: source.groupID,
                owner: source.owner,
                maxPixelSize: 600
            )
        }
        return nil
    }

    private func resolveVisualLiveArtwork(for song: Song) async -> (LiveArtworkAsset?, URL?) {
        guard LiveArtworkSettings.shouldShowAnimatedArtwork else {
            AppLogger.shared.log("Live artwork skipped by current settings; songID=\(song.id)", category: .playback)
            return (nil, nil)
        }

        if let result = await firstLiveArtwork(for: client?.liveArtworkURLs(id: song.coverArt) ?? []) {
            return result
        }
        // Emby songs commonly inherit their album's Primary image. Try the
        // resolved cover-art item first so a song without its own image does
        // not produce a full set of 404 probes before the album cover. Keep
        // the raw song item as a fallback for servers with track-specific art.
        if client?.backendKind == .emby,
           song.coverArt != song.id,
           let result = await firstLiveArtwork(for: client?.liveArtworkURLs(id: song.id) ?? []) {
            return result
        }
        guard let albumID = song.albumId else { return (nil, nil) }

        let albumCoverArt: String?
        if queueSourceAlbum?.id == albumID {
            albumCoverArt = queueSourceAlbum?.coverArt
        } else if let client {
            albumCoverArt = (try? await client.album(id: albumID))?.coverArt
        } else {
            albumCoverArt = nil
        }
        guard albumCoverArt != song.coverArt else { return (nil, nil) }
        return await firstLiveArtwork(for: client?.liveArtworkURLs(id: albumCoverArt) ?? []) ?? (nil, nil)
    }

    private func firstLiveArtwork(for urls: [URL]) async -> (LiveArtworkAsset?, URL?)? {
        for url in urls {
            guard !Task.isCancelled else { return nil }
            if let live = await ArtworkLoader.shared.liveArtwork(for: url, includeVideo: false) {
                return (live, url)
            }
        }
        return nil
    }

    private func supportedLockScreenArtworkAspect() -> LockScreenArtworkAspect? {
        guard #available(iOS 26.0, *) else { return nil }
        let supported = MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys
        if supported.contains(MPNowPlayingInfoProperty3x4AnimatedArtwork) { return .portrait }
        if supported.contains(MPNowPlayingInfoProperty1x1AnimatedArtwork) { return .square }
        // Developer raw mode intentionally bypasses platform capability checks.
        return LiveArtworkSettings.rawAnimatedArtworkEnabled ? .portrait : nil
    }

    private func waitForSupportedLockScreenArtworkAspect() async -> LockScreenArtworkAspect? {
        if let aspect = supportedLockScreenArtworkAspect() { return aspect }
        // The collection can be empty briefly after a cold launch. Keep visible
        // artwork responsive while waiting to prepare the system-only video.
        for delayNanoseconds in [250_000_000, 500_000_000, 1_000_000_000, 2_000_000_000] as [UInt64] {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return nil }
            if let aspect = supportedLockScreenArtworkAspect() { return aspect }
        }
        return nil
    }

    // Animated-artwork keys can appear a beat after song start; retry attachment.
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
        let started = ProcessInfo.processInfo.systemUptime
        for attempt in 0..<30 {
            if Task.isCancelled || item !== currentPlayerItem { return }
            let d = item.duration
            if d.isNumeric, d.seconds > 0 {
                guard item === currentPlayerItem else { return }
                let serverDuration = Double(currentSong?.duration ?? 0)
                let effectiveDuration = max(serverDuration, d.seconds)
                duration = effectiveDuration
                if d.seconds > serverDuration + 0.5 {
                    AppLogger.shared.log(
                        "Playback duration extended beyond server metadata; av=\(String(format: "%.4f", d.seconds))s; server=\(String(format: "%.4f", serverDuration))s; source=\(currentPlaybackSource?.rawValue ?? "unknown"); attempts=\(attempt + 1); elapsedMs=\(Int((ProcessInfo.processInfo.systemUptime - started) * 1000))",
                        category: .playback,
                        level: .warning
                    )
                } else {
                    AppLogger.shared.log(
                        "Playback duration ready; duration=\(String(format: "%.4f", effectiveDuration))s; source=\(currentPlaybackSource?.rawValue ?? "unknown"); attempts=\(attempt + 1); elapsedMs=\(Int((ProcessInfo.processInfo.systemUptime - started) * 1000))",
                        category: .playback
                    )
                }
                updateNowPlayingTime()
                if transitionMode != .off, !isTransitioning {
                    resetPreparedTransitionPlan()
                    prepareTransitionPlanIfNeeded()
                }
                return
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        AppLogger.shared.log(
            "Playback duration was not ready after 6 seconds; songID=\(currentSong?.id ?? "none"); itemStatus=\(item.status.rawValue); itemError=\(item.error?.localizedDescription ?? "none"); isCurrent=\(item === player.currentItem); playerStatus=\(player.timeControlStatus.rawValue); waiting=\(String(describing: player.reasonForWaitingToPlay)); rate=\(String(format: "%.2f", player.rate))",
            category: .playback,
            level: .warning
        )
    }

    private func monitorStartup(for item: AVPlayerItem, song: Song, source: PlaybackURLSource) {
        startupDiagnosticsTask?.cancel()
        guard source == .stream else { return }
        let started = ProcessInfo.processInfo.systemUptime
        startupDiagnosticsTask = Task { @MainActor [weak self, weak item] in
            for delay in [3.0, 10.0, 30.0] {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled,
                      let self,
                      let item,
                      self.currentPlayerItem === item,
                      self.currentSong?.id == song.id else { return }

                let playerTime = self.player.currentTime().seconds
                let hasProgress = playerTime.isFinite && playerTime > 0.25
                let playing = self.player.timeControlStatus == .playing && self.player.rate > 0
                if hasProgress && playing { return }

                let elapsedMs = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
                AppLogger.shared.log(
                    "Stream startup waiting; title='\(song.title)'; elapsedMs=\(elapsedMs); itemStatus=\(item.status.rawValue); itemError=\(item.error?.localizedDescription ?? "none"); playerStatus=\(self.player.timeControlStatus.rawValue); waiting=\(String(describing: self.player.reasonForWaitingToPlay)); rate=\(String(format: "%.2f", self.player.rate)); time=\(String(format: "%.3f", max(0, playerTime.isFinite ? playerTime : 0))); buffered=\(Self.bufferedRangeSummary(item))",
                    category: .playback,
                    level: delay >= 10 ? .warning : .info
                )
            }
        }
    }

    private static func bufferedRangeSummary(_ item: AVPlayerItem) -> String {
        let ranges = item.loadedTimeRanges.map(\.timeRangeValue)
        guard let range = ranges.max(by: { lhs, rhs in
            (lhs.start.seconds + lhs.duration.seconds) < (rhs.start.seconds + rhs.duration.seconds)
        }) else { return "none" }
        let start = range.start.seconds
        let end = range.start.seconds + range.duration.seconds
        guard start.isFinite, end.isFinite else { return "unknown" }
        return "\(String(format: "%.2f", start))-\(String(format: "%.2f", end))"
    }

    private static func streamingPreferenceSummary(for song: Song) -> String {
        let decision = StreamingPreferences.streamDecision(for: song)
        let format = decision.format ?? (decision.wantsTranscode ? "automatic" : "raw")
        let source = decision.sourceKind?.rawValue ?? "unknown"
        let rule = decision.ruleTarget?.rawValue ?? "none"
        return "bitrateKbps=\(decision.bitrateKbps); requestedBitrateKbps=\(decision.requestedBitrateKbps); format=\(format); sourceType=\(source); rule=\(rule)"
    }

    private func logGaplessReadinessIfNeeded(force: Bool = false) {
        guard let item = gaplessNextItem,
              let songID = gaplessNextSongID else { return }
        let itemID = ObjectIdentifier(item)
        guard gaplessReadinessLoggedItemID != itemID else { return }
        if !force {
            let remaining = liveDuration() - liveTime()
            guard remaining.isFinite, remaining > 0, remaining <= 2 else { return }
        }

        gaplessReadinessLoggedItemID = itemID
        let bufferedEnd = item.loadedTimeRanges
            .compactMap { $0.timeRangeValue.end.seconds }
            .filter(\.isFinite)
            .max() ?? 0
        let itemTime = item.currentTime().seconds
        let bufferedAhead = max(0, bufferedEnd - (itemTime.isFinite ? itemTime : 0))
        AppLogger.shared.log(
            "Gapless readiness; songID=\(songID); source=\(gaplessNextSource?.rawValue ?? "unknown"); status=\(item.status.rawValue); likelyToKeepUp=\(item.isPlaybackLikelyToKeepUp); bufferFull=\(item.isPlaybackBufferFull); bufferEmpty=\(item.isPlaybackBufferEmpty); bufferedAhead=\(String(format: "%.2f", bufferedAhead))s",
            category: .playback
        )
    }

    private func measureGaplessStartDelay(for item: AVPlayerItem, outgoingEndedAt: TimeInterval) {
        gaplessTransitionMeasurementTask?.cancel()
        gaplessTransitionMeasurementTask = Task { @MainActor [weak self, weak item] in
            guard let self, let item else { return }
            for _ in 0..<80 {
                guard !Task.isCancelled, self.currentPlayerItem === item else { return }
                let itemTime = item.currentTime().seconds
                if (itemTime.isFinite && itemTime > 0) || self.player.timeControlStatus == .playing {
                    let delayMS = max(0, ProcessInfo.processInfo.systemUptime - outgoingEndedAt) * 1_000
                    AppLogger.shared.log(
                        "Gapless incoming audio observed; delayMs=\(String(format: "%.1f", delayMS)); itemTime=\(String(format: "%.3f", itemTime.isFinite ? itemTime : 0))s",
                        category: .playback
                    )
                    self.gaplessTransitionMeasurementTask = nil
                    return
                }
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
            guard !Task.isCancelled, self.currentPlayerItem === item else { return }
            AppLogger.shared.log(
                "Gapless incoming audio was not observed within 2s; status=\(item.status.rawValue); waiting=\(String(describing: self.player.reasonForWaitingToPlay))",
                category: .playback,
                level: .warning
            )
            self.gaplessTransitionMeasurementTask = nil
        }
    }

    private func addTimeObservers() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        primaryTimeObserverToken = primaryPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.activePlayer === self.primaryPlayer else { return }
                self.currentTime = self.player.currentTime().seconds
                self.checkLogPlay()
                self.logGaplessReadinessIfNeeded()
                self.autosaveLastPlaybackSessionIfNeeded()
            }
        }
        secondaryTimeObserverToken = secondaryPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.activePlayer === self.secondaryPlayer else { return }
                self.currentTime = self.player.currentTime().seconds
                self.checkLogPlay()
                self.logGaplessReadinessIfNeeded()
                self.autosaveLastPlaybackSessionIfNeeded()
            }
        }
    }

    private func addCurrentItemObservers() {
        primaryCurrentItemObservation = primaryPlayer.observe(\.currentItem, options: [.new]) { [weak self] observed, change in
            guard let nextItem = change.newValue ?? nil else { return }
            Task { @MainActor [weak self, weak observed, weak nextItem] in
                guard let self, let observed, let nextItem else { return }
                self.handleCurrentItemChange(player: observed, item: nextItem)
            }
        }
        secondaryCurrentItemObservation = secondaryPlayer.observe(\.currentItem, options: [.new]) { [weak self] observed, change in
            guard let nextItem = change.newValue ?? nil else { return }
            Task { @MainActor [weak self, weak observed, weak nextItem] in
                guard let self, let observed, let nextItem else { return }
                self.handleCurrentItemChange(player: observed, item: nextItem)
            }
        }
    }

    private func handleCurrentItemChange(player observedPlayer: AVQueuePlayer, item: AVPlayerItem) {
        guard observedPlayer === activePlayer,
              item === gaplessNextItem,
              item !== currentPlayerItem,
              let outgoingItem = currentPlayerItem else { return }
        _ = completeQueuedGaplessHandoff(
            finishedItem: outgoingItem,
            outgoingEndedAt: ProcessInfo.processInfo.systemUptime
        )
    }

    private func checkLogPlay() {
        guard let song = currentSong,
              duration > 0,
              !loggedSongIDs.contains(song.id) else { return }
        let threshold = DeveloperExperiments.instantScrobbling
            ? 1.0
            : min(duration * 0.5, Double(song.duration ?? Int(duration)) * 0.5)
        if currentTime >= threshold {
            loggedSongIDs.insert(song.id)
            let event = PlayEvent(song: song)
            StatsStore.shared.record(event)
            let startedAt = currentSongStartedAt ?? Date(timeIntervalSinceNow: -max(0, currentTime))
            let listenedDuration = Int(max(0, currentTime).rounded())
            let trackDuration = Int(max(duration, Double(song.duration ?? 0)).rounded())
            ThirdPartyScrobbler.shared.submitScrobble(
                song: song,
                event: event,
                startedAt: startedAt,
                listenedDuration: listenedDuration,
                trackDuration: trackDuration
            )
            submitServerScrobble(for: song, startedAt: startedAt)
            AppLogger.shared.log("Play event recorded: '\(song.title)' at \(Int(currentTime))s / \(Int(duration))s", category: .playback)
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
                guard finishedItem === self.currentPlayerItem else {
                    return
                }
                let outgoingEndedAt = ProcessInfo.processInfo.systemUptime
                self.logGaplessReadinessIfNeeded(force: true)
                if self.retryPrematureTranscodeEndIfNeeded(finishedItem: finishedItem) {
                    return
                }
                if self.sleepEndsAtTrackEnd {
                    self.player.pause()
                    self.isPlaying = false
                    self.cancelSleepTimer(resumeGaplessPreload: false)
                    self.updateNowPlaying()
                    return
                }
                if self.completeQueuedGaplessHandoff(
                    finishedItem: finishedItem,
                    outgoingEndedAt: outgoingEndedAt
                ) {
                    return
                }
                guard self.currentPlayerItem === finishedItem else { return }
                if self.repeatMode == .one {
                    self.playCurrent()
                    return
                }
                self.skipNext()
            }
        }
    }

    private func retryPrematureTranscodeEndIfNeeded(finishedItem: AVPlayerItem) -> Bool {
        guard currentPlaybackSource == .stream,
              currentPlaybackUsesTranscode,
              isPlaying,
              let song = currentSong else { return false }

        let elapsed = finishedItem.currentTime().seconds
        let expectedDuration = max(duration, Double(song.duration ?? 0))
        guard elapsed.isFinite,
              expectedDuration.isFinite,
              expectedDuration > 0,
              elapsed > 0.25,
              expectedDuration - elapsed > 12 else { return false }

        let retryCount = prematureTranscodeEndRetries[song.id, default: 0]
        guard retryCount < 1 else {
            AppLogger.shared.log(
                "Transcoded stream ended early after retry; title='\(song.title)'; elapsed=\(String(format: "%.3f", elapsed))s; expected=\(String(format: "%.3f", expectedDuration))s; buffered=\(Self.bufferedRangeSummary(finishedItem))",
                category: .playback,
                level: .warning
            )
            return false
        }

        prematureTranscodeEndRetries[song.id] = retryCount + 1
        AppLogger.shared.log(
            "Transcoded stream ended early; title='\(song.title)'; elapsed=\(String(format: "%.3f", elapsed))s; expected=\(String(format: "%.3f", expectedDuration))s; retrying",
            category: .playback,
            level: .warning
        )
        restartCurrentStream(song: song, at: elapsed)
        return true
    }

    private func restartCurrentStream(song: Song, at elapsed: TimeInterval) {
        invalidatePreloadedNext()
        guard let urlInfo = playbackURL(for: song) else {
            AppLogger.shared.log(
                "Transcoded stream retry failed: no stream URL for '\(song.title)'",
                category: .playback,
                level: .error
            )
            isPlaying = false
            updateNowPlaying()
            return
        }

        let item = makePlayerItem(playback: urlInfo)
        startupDiagnosticsTask?.cancel()
        playbackPreparationTask?.cancel()
        playRequestID &+= 1
        let requestToken = playRequestID
        let expectedItem = currentPlayerItem
        playbackPreparationTask = Task { @MainActor [weak self, item, weak expectedItem] in
            guard let self else { return }
            defer {
                if requestToken == self.playRequestID {
                    self.playbackPreparationTask = nil
                }
            }
            let processingReady = await self.prepareAudioProcessing(for: item)
            guard !Task.isCancelled,
                  requestToken == self.playRequestID,
                  self.currentPlayerItem === expectedItem,
                  self.currentSong?.id == song.id else { return }
            if !processingReady {
                item.audioMix = nil
                self.setAudioProcessingMode(.none, for: item)
                AppLogger.shared.log(
                    "Audio processing unavailable during stream retry for '\(song.title)'; playing unprocessed",
                    category: .playback,
                    level: .warning
                )
            }
            self.materializeRestartedStream(
                song: song,
                item: item,
                urlInfo: urlInfo,
                elapsed: elapsed
            )
        }
    }

    private func materializeRestartedStream(
        song: Song,
        item: AVPlayerItem,
        urlInfo: PlaybackURLInfo,
        elapsed: TimeInterval
    ) {
        player.pause()
        for existing in player.items() { releaseAudioPipeline(for: existing) }
        player.removeAllItems()
        player.insert(item, after: nil)
        currentPlayerItem = item
        currentPlaybackSource = urlInfo.source
        currentPlaybackUsesTranscode = urlInfo.usesTranscode
        currentTime = elapsed
        try? AVAudioSession.sharedInstance().setActive(true)

        let resume = { [weak self, weak item] in
            guard let self, let item,
                  self.currentPlayerItem === item,
                  self.currentSong?.id == song.id else { return }
            if self.isPlaying {
                self.startPlayer(self.player, source: urlInfo.source, usesTranscode: urlInfo.usesTranscode)
            }
        }

        let target = CMTime(seconds: elapsed, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
            guard finished else { return }
            Task { @MainActor in resume() }
        }
        updateNowPlaying()
        persistLastPlaybackSession()
        durationLoadTask?.cancel()
        durationLoadTask = Task { [weak self] in await self?.loadDuration(from: item) }
        monitorStartup(for: item, song: song, source: urlInfo.source)
        scheduleGaplessPreload()
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
                    self.pauseAllPlayers()
                    self.isPlaying = false
                    self.cancelTransitionPlayback(keepPaused: true)
                    self.updateNowPlaying()
                case .ended:
                    let resumePref = UserDefaults.standard.object(forKey: "resumeAfterInterruption") as? Bool ?? true
                    let shouldResume: Bool
                    if let rawOptions = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                        shouldResume = resumePref && AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
                    } else {
                        shouldResume = false
                    }
                    if shouldResume { self.resume() }
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
                    self.pauseAllPlayers()
                    self.isPlaying = false
                    self.cancelTransitionPlayback(keepPaused: true)
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
                guard self.isPlaying, let stalledItem = note.object as? AVPlayerItem else { return }
                if self.isTransitioning,
                   stalledItem === self.transitionIncomingPlayer?.currentItem {
                    AutoMixDiagnostics.logFallback(
                        planned: self.activeTransitionPlan?.type ?? .adaptiveCrossfade,
                        actual: nil,
                        reason: "incomingStalled"
                    )
                    self.cancelTransitionPlayback()
                }
                guard stalledItem === self.player.currentItem else { return }
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
        guard let song = currentSong else { return }

        // Restored sessions carry queue/position metadata but deliberately do
        // not allocate an AVPlayerItem at launch. Remote play must take the
        // same materialization path as the in-app play button.
        if currentPlayerItem == nil {
            if deferredRestoredTime != nil {
                if playbackPreparationTask == nil {
                    _ = resumeDeferredSessionIfNeeded()
                }
            } else if playbackPreparationTask == nil,
                      queue.indices.contains(currentIndex) {
                playCurrent()
            }
            return
        }

        guard !isPlaying,
              activateAudioSessionForPlayback() else { return }
        let resumeTime = playbackTimeSnapshot().elapsed
        if currentPlayerItem?.status == .failed {
            AppLogger.shared.log(
                "Playback resume rebuilding failed item; title='\(song.title)'; elapsed=\(String(format: "%.3f", resumeTime))s",
                category: .playback,
                level: .warning
            )
            isPlaying = true
            updateNowPlaying()
            restartCurrentStream(song: song, at: resumeTime)
            return
        }
        if let currentPlaybackSource {
            startPlayer(player, source: currentPlaybackSource, usesTranscode: currentPlaybackUsesTranscode)
        } else {
            player.play()
        }
        isPlaying = true
        if currentSongStartedAt == nil {
            currentSongStartedAt = Date(timeIntervalSinceNow: -max(0, currentTime))
        }
        if let song = currentSong { notifyNowPlaying(for: song) }
        updateNowPlaying()
        persistLastPlaybackSession()
        refreshAutoMixAnalysisWindow()
        prepareTransitionPlanIfNeeded()
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
        let candidateKeys = [
            MPNowPlayingInfoProperty3x4AnimatedArtwork,
            MPNowPlayingInfoProperty1x1AnimatedArtwork
        ]
        for k in candidateKeys { info.removeValue(forKey: k) }
        let supportedKeys = MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys
        guard let live, let videoURL = live.videoURL, let videoAspect = live.videoAspect else {
            AppLogger.shared.log("Lock-screen animated artwork: not attached (live=\(live != nil), video=\(live?.videoURL != nil), aspect=\(String(describing: live?.videoAspect)), supportedKeys=\(supportedKeys))", category: .playback)
            return
        }
        let key = videoAspect == .portrait
            ? MPNowPlayingInfoProperty3x4AnimatedArtwork
            : MPNowPlayingInfoProperty1x1AnimatedArtwork
        guard supportedKeys.contains(key) || LiveArtworkSettings.rawAnimatedArtworkEnabled else {
            AppLogger.shared.log("Lock-screen animated artwork: prepared \(videoAspect.rawValue), but OS does not support its key (supportedKeys=\(supportedKeys))", category: .playback, level: .warning)
            return
        }
        let preview = live.previewImage
        AppLogger.shared.log(
            "Lock-screen animated artwork attached; key=\(key); preview=\(Int(preview.size.width))x\(Int(preview.size.height)); file=\(videoURL.lastPathComponent)",
            category: .playback
        )
        // If the system never requests the video, it is gating animation, not format.
        let animated = MPMediaItemAnimatedArtwork(
            artworkID: live.artworkID,
            previewImageRequestHandler: { _, completion in
                AppLogger.shared.log("Lock-screen animated artwork preview requested by system", category: .playback)
                completion(preview)
            },
            videoAssetFileURLRequestHandler: { _, completion in
                AppLogger.shared.log("Lock-screen animated artwork video requested by system; file=\(videoURL.lastPathComponent)", category: .playback)
                completion(videoURL)
            }
        )
        info[key] = animated
    }

    private func updateNowPlayingTime() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        let effectiveDuration = resolvedPlaybackDuration(avDuration: player.currentItem?.duration.seconds ?? .nan)
        if effectiveDuration > 0 { info[MPMediaItemPropertyPlaybackDuration] = effectiveDuration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
