import SwiftUI
import UIKit
import QuartzCore

struct AnimatedImageView: UIViewRepresentable {
    let image: UIImage

    final class Coordinator {
        var configuredImage: UIImage?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> CompositorAnimatedImageView {
        let v = CompositorAnimatedImageView()
        v.contentMode = .scaleAspectFill
        v.clipsToBounds = true
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        configure(v, context: context)
        return v
    }

    func updateUIView(_ uiView: CompositorAnimatedImageView, context: Context) {
        // Reconfigure only when the artwork changes; playback ticks re-render often.
        guard context.coordinator.configuredImage !== image else { return }
        configure(uiView, context: context)
    }

    private func configure(_ v: CompositorAnimatedImageView, context: Context) {
        context.coordinator.configuredImage = image
        if let frames = image.images, frames.count > 1 {
            v.setAnimation(frames: frames, delays: image.frameDelays, duration: image.duration)
            AppLogger.shared.log("Live artwork: presenting \(frames.count) frames via compositor keyframe animation", category: .other)
        } else {
            v.setAnimation(frames: [], delays: nil, duration: 0)
            v.image = image
            AppLogger.shared.log("Live artwork: animated image arrived with NO frames array (images=\(image.images?.count ?? -1)) — rendering still", category: .other, level: .warning)
        }
    }
}

// Let Core Animation advance artwork frames instead of driving them from the main thread.
final class CompositorAnimatedImageView: UIImageView {
    private static let animationKey = "liveArtworkFrames"

    private var frameContents: [CGImage] = []
    private var keyTimes: [NSNumber] = []
    private var duration: TimeInterval = 0
    private var activationObserver: NSObjectProtocol?
    private var loggedStart = false

    func setAnimation(frames: [UIImage], delays: [TimeInterval]?, duration: TimeInterval) {
        layer.removeAnimation(forKey: Self.animationKey)
        frameContents = frames.compactMap { $0.cgImage }
        guard frameContents.count > 1 else {
            keyTimes = []
            self.duration = 0
            return
        }
        // Keep a still image around for offscreen and backgrounded states.
        image = frames.first
        (keyTimes, self.duration) = Self.makeKeyTimes(count: frameContents.count, delays: delays, duration: duration)
        loggedStart = false
        installIfPossible()
    }

    // Use source frame delays when available; otherwise fall back to even spacing.
    private static func makeKeyTimes(count: Int, delays: [TimeInterval]?, duration: TimeInterval) -> ([NSNumber], TimeInterval) {
        if let delays, delays.count == count {
            let total = delays.reduce(0, +)
            if total > 0 {
                var times: [NSNumber] = []
                times.reserveCapacity(count)
                var acc: TimeInterval = 0
                for delay in delays {
                    times.append(NSNumber(value: acc / total))
                    acc += delay
                }
                return (times, total)
            }
        }
        let total = duration > 0 ? duration : Double(count) * 0.1
        let times = (0..<count).map { NSNumber(value: Double($0) / Double(count)) }
        return (times, total)
    }

    private func installIfPossible() {
        guard window != nil, frameContents.count > 1,
              layer.animation(forKey: Self.animationKey) == nil else { return }
        let anim = CAKeyframeAnimation(keyPath: "contents")
        anim.values = frameContents
        anim.keyTimes = keyTimes
        anim.calculationMode = .discrete
        anim.duration = duration
        anim.repeatCount = .greatestFiniteMagnitude
        anim.isRemovedOnCompletion = false
        layer.add(anim, forKey: Self.animationKey)
        if !loggedStart {
            loggedStart = true
            AppLogger.shared.log("Live artwork: compositor animation installed (\(frameContents.count) frames over \(String(format: "%.1f", duration))s at native rate)", category: .other)
        }
    }

    // UIKit drops layer animations after backgrounding, so reinstall when the view comes back.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            layer.removeAnimation(forKey: Self.animationKey)
        } else {
            observeActivationIfNeeded()
            installIfPossible()
        }
    }

    private func observeActivationIfNeeded() {
        guard activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.installIfPossible()
        }
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }
}
