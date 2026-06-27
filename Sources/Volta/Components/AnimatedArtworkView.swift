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
    private var lastTimestamp: CFTimeInterval = 0
    private var loggedFirstLoop = false

    func setAnimation(frames: [UIImage], duration: TimeInterval) {
        link?.invalidate()
        link = nil
        self.frames = frames
        // Native per-frame delay; floor allows rates up to 120fps.
        frameDelay = frames.count > 1 ? max(1.0 / 120.0, duration / Double(frames.count)) : 0.1
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
        lastTimestamp = 0
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        // Full-refresh link; the accumulator steps frames at the native rate so
        // changes land on the nearest refresh (smoother than a fixed low-fps clock).
        let maxFPS = Float(max(60, UIScreen.main.maximumFramesPerSecond))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: maxFPS, preferred: maxFPS)
        l.add(to: .main, forMode: .common)
        link = l
        AppLogger.shared.log("Live artwork: display link started (\(frames.count) frames; native \(String(format: "%.0f", 1.0 / frameDelay))fps stepped @ up to \(String(format: "%.0f", maxFPS))Hz)", category: .other)
    }

    @objc private func tick(_ l: CADisplayLink) {
        // Advance by real elapsed time so a dropped tick doesn't slow playback.
        let elapsed = lastTimestamp > 0 ? l.timestamp - lastTimestamp : (l.targetTimestamp - l.timestamp)
        lastTimestamp = l.timestamp
        accumulated += max(0, elapsed)
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
