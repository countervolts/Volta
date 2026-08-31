import Foundation
import AVFoundation

@MainActor
final class AutoMixCoordinator {
    private struct Observer {
        let id: UUID
        weak var player: AVPlayer?
        let token: Any
    }

    private var observers: [Observer] = []
    private var generation: UInt64 = 0

    func armOutgoing(
        player: AVPlayer,
        primeTime: TimeInterval,
        transitionTime: TimeInterval,
        onPrime: @escaping @MainActor () -> Void,
        onTransition: @escaping @MainActor () -> Void
    ) {
        cancel()
        generation &+= 1
        let tokenGeneration = generation
        let now = player.currentTime().seconds

        if primeTime <= now + 0.04 {
            onPrime()
        } else {
            addBoundary(player: player, time: primeTime) { [weak self] in
                guard self?.generation == tokenGeneration else { return }
                onPrime()
            }
        }
        let safeTransitionTime = transitionTime <= now + 0.04 ? now + 0.12 : transitionTime
        addBoundary(player: player, time: safeTransitionTime) { [weak self] in
            guard self?.generation == tokenGeneration else { return }
            onTransition()
        }
    }

    func armHandoff(
        incomingPlayer: AVPlayer,
        incomingCue: TimeInterval,
        incomingMediaDuration: TimeInterval,
        onPromote: @escaping @MainActor () -> Void,
        onComplete: @escaping @MainActor () -> Void
    ) {
        let tokenGeneration = generation
        addBoundary(
            player: incomingPlayer,
            time: incomingCue + incomingMediaDuration * 0.52
        ) { [weak self] in
            guard self?.generation == tokenGeneration else { return }
            onPromote()
        }
        addBoundary(
            player: incomingPlayer,
            time: incomingCue + incomingMediaDuration
        ) { [weak self] in
            guard self?.generation == tokenGeneration else { return }
            onComplete()
        }
    }

    func restoreRate(
        player: AVPlayer,
        from initialRate: Float,
        startingAt mediaStart: TimeInterval,
        duration: TimeInterval,
        completion: @escaping @MainActor () -> Void
    ) {
        guard abs(initialRate - 1) >= 0.001, duration > 0 else {
            player.rate = 1
            completion()
            return
        }
        let tokenGeneration = generation
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        let observerID = UUID()
        let observerToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak player] time in
            Task { @MainActor in
                guard let self, let player,
                      self.generation == tokenGeneration else { return }
                let progress = min(1, max(0, (time.seconds - mediaStart) / duration))
                let eased = progress * progress * (3 - 2 * progress)
                player.rate = initialRate + (1 - initialRate) * Float(eased)
                if progress >= 1 {
                    player.rate = 1
                    self.removeObserver(id: observerID)
                    completion()
                }
            }
        }
        observers.append(Observer(id: observerID, player: player, token: observerToken))
    }

    func cancel() {
        generation &+= 1
        for observer in observers {
            observer.player?.removeTimeObserver(observer.token)
        }
        observers.removeAll()
    }

    private func addBoundary(
        player: AVPlayer,
        time: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) {
        let token = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: CMTime(seconds: max(0, time), preferredTimescale: 600))],
            queue: .main
        ) {
            Task { @MainActor in action() }
        }
        observers.append(Observer(id: UUID(), player: player, token: token))
    }

    private func removeObserver(id: UUID) {
        guard let index = observers.firstIndex(where: { $0.id == id }) else { return }
        let observer = observers.remove(at: index)
        observer.player?.removeTimeObserver(observer.token)
    }
}
