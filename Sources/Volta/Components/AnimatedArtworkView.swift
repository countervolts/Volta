import SwiftUI
import UIKit

struct AnimatedImageView: UIViewRepresentable {
    let image: UIImage

    final class Coordinator {
        var configuredImage: UIImage?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> FrameSteppingImageView {
        let v = FrameSteppingImageView()
        v.contentMode = .scaleAspectFill
        v.clipsToBounds = true
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        configure(v, context: context)
        return v
    }

    func updateUIView(_ uiView: FrameSteppingImageView, context: Context) {
        // Reconfigure only when the artwork changes; playback ticks re-render often.
        guard context.coordinator.configuredImage !== image else { return }
        configure(uiView, context: context)
    }

    private func configure(_ v: FrameSteppingImageView, context: Context) {
        context.coordinator.configuredImage = image
        if let frames = image.images, frames.count > 1 {
            v.setAnimation(frames: frames, duration: image.duration)
            AppLogger.shared.log("Live artwork: stepping \(frames.count) frames over \(String(format: "%.1f", image.duration))s via display link", category: .other)
        } else {
            v.setAnimation(frames: [], duration: 0)
            v.image = image
            AppLogger.shared.log("Live artwork: animated image arrived with NO frames array (images=\(image.images?.count ?? -1)) — rendering still", category: .other, level: .warning)
        }
    }
}

final class FrameSteppingImageView: UIImageView {
    private var frames: [UIImage] = []
    private var frameDelay: TimeInterval = 0.1
    private var link: CADisplayLink?
    private var index = 0
    private var accumulated: CFTimeInterval = 0
    private var loggedFirstLoop = false

    func setAnimation(frames: [UIImage], duration: TimeInterval) {
        link?.invalidate()
        link = nil
        self.frames = frames
        frameDelay = frames.count > 1 ? max(0.02, duration / Double(frames.count)) : 0.1
        index = 0
        accumulated = 0
        if let first = frames.first { image = first }
        startIfNeeded()
    }

    // Window membership owns the display link lifetime.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            link?.invalidate()
            link = nil
        } else {
            startIfNeeded()
        }
    }

    private func startIfNeeded() {
        guard window != nil, frames.count > 1, link == nil else {
            if frames.count > 1, link == nil {
                AppLogger.shared.log("Live artwork: display link NOT started — view has no window yet (\(frames.count) frames staged)", category: .other)
            }
            return
        }
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        // Artwork frames are low-fps; the accumulator keeps time when ticks are sparse.
        let rawMode = LiveArtworkSettings.rawAnimatedArtworkEnabled
        let lowPower = LiveArtworkSettings.lowPowerPlayback
        let maxFPS: Float = rawMode
            ? Float(max(30, UIScreen.main.maximumFramesPerSecond))
            : (lowPower ? 15 : 30)
        let minFPS: Float = rawMode ? min(30.0, maxFPS) : (lowPower ? 8 : 10)
        l.preferredFrameRateRange = CAFrameRateRange(minimum: minFPS, maximum: maxFPS, preferred: maxFPS)
        l.add(to: .main, forMode: .common)
        link = l
        AppLogger.shared.log("Live artwork: display link started (\(frames.count) frames @ \(String(format: "%.0f", 1.0 / frameDelay))fps\(rawMode ? ", raw" : (lowPower ? ", low power" : "")))", category: .other)
    }

    @objc private func tick(_ l: CADisplayLink) {
        accumulated += max(0, l.targetTimestamp - l.timestamp)
        guard accumulated >= frameDelay, !frames.isEmpty else { return }
        let steps = Int(accumulated / frameDelay)
        accumulated -= Double(steps) * frameDelay
        let previous = index
        index = (index + steps) % frames.count
        image = frames[index]
        if index < previous, !loggedFirstLoop {
            loggedFirstLoop = true
            AppLogger.shared.log("Live artwork: completed first animation loop (frames are advancing)", category: .other)
        }
    }
}
