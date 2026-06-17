import Foundation

// App Intents bridge to the live client/player.
final class IntentBridge: @unchecked Sendable {
    static let shared = IntentBridge()
    private init() {}

    private let lock = NSLock()
    private var _client: (any MusicService)?
    private var _audioPlayer: AudioPlayer?

    var client: (any MusicService)? {
        lock.withLock { _client }
    }

    func setup(client: any MusicService, audioPlayer: AudioPlayer) {
        lock.withLock {
            _client = client
            _audioPlayer = audioPlayer
        }
    }

    func teardown() {
        lock.withLock {
            _client = nil
            _audioPlayer = nil
        }
    }

    // MainActor caller; dispatches and waits.
    func playQueue(_ songs: [Song], source: String) async {
        await MainActor.run {
            _audioPlayer?.playQueue(songs, source: source)
        }
    }

    func playSong(_ song: Song) async {
        await MainActor.run {
            _audioPlayer?.play(song: song)
        }
    }

    func pause() async {
        await MainActor.run { _audioPlayer?.pause() }
    }

    func resume() async {
        await MainActor.run {
            guard let p = _audioPlayer, !p.isPlaying else { return }
            p.togglePlayPause()
        }
    }

    func skip() async {
        await MainActor.run { _audioPlayer?.skipNext() }
    }
}
