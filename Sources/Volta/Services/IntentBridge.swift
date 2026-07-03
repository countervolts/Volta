import Foundation

// App Intents bridge to the live client/player.
final class IntentBridge: @unchecked Sendable {
    static let shared = IntentBridge()
    private init() {}

    // Posted whenever the live client is connected or torn down, so scenes that
    // live outside the SwiftUI hierarchy (CarPlay) can refresh their content.
    static let clientDidChange = Notification.Name("VoltaIntentBridgeClientDidChange")

    private let lock = NSLock()
    private var _client: (any MusicService)?
    private var _audioPlayer: AudioPlayer?
    private let sessionRestoreTimeout: TimeInterval = 4

    var client: (any MusicService)? {
        lock.withLock { _client }
    }

    // The live player is @MainActor-isolated; only touch it from the main actor.
    var audioPlayer: AudioPlayer? {
        lock.withLock { _audioPlayer }
    }

    func readyClient() async -> (any MusicService)? {
        await ensureReady()
        return client
    }

    func ensureReady() async {
        guard client == nil else { return }

        let shouldWait = await MainActor.run {
            AppState.shared.restoreSession()
            return AppState.shared.phase != .login
        }
        guard shouldWait else { return }

        let deadline = Date().addingTimeInterval(sessionRestoreTimeout)
        while client == nil && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func setup(client: any MusicService, audioPlayer: AudioPlayer) {
        lock.withLock {
            _client = client
            _audioPlayer = audioPlayer
        }
        NotificationCenter.default.post(name: Self.clientDidChange, object: nil)
    }

    func teardown() {
        lock.withLock {
            _client = nil
            _audioPlayer = nil
        }
        NotificationCenter.default.post(name: Self.clientDidChange, object: nil)
    }

    // MainActor caller; dispatches and waits.
    func playQueue(_ songs: [Song], source: String) async {
        await ensureReady()
        await MainActor.run {
            _audioPlayer?.playQueue(songs, source: source)
        }
    }

    func playSong(_ song: Song) async {
        await ensureReady()
        await MainActor.run {
            _audioPlayer?.play(song: song)
        }
    }

    func pause() async {
        await ensureReady()
        await MainActor.run { _audioPlayer?.pause() }
    }

    func resume() async {
        await ensureReady()
        await MainActor.run {
            guard let p = _audioPlayer, !p.isPlaying else { return }
            p.togglePlayPause()
        }
    }

    func skip() async {
        await ensureReady()
        await MainActor.run { _audioPlayer?.skipNext() }
    }
}
