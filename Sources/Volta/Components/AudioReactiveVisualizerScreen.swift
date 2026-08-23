import SwiftUI
import UIKit
import QuartzCore

private enum VisualizerPalette {
    static let background = Color(red: 0.006, green: 0.008, blue: 0.012)
    static let paper = Color.white
    static let red = Color(red: 1.0, green: 0.18, blue: 0.16)
    static let green = Color(red: 0.16, green: 0.92, blue: 0.39)
    static let blue = Color(red: 0.10, green: 0.46, blue: 1.0)

    static func rgbGradient(opacity: Double = 1) -> Gradient {
        Gradient(stops: [
            .init(color: red.opacity(opacity), location: 0),
            .init(color: green.opacity(opacity), location: 0.5),
            .init(color: blue.opacity(opacity), location: 1),
        ])
    }

    static func rgb(at position: CGFloat) -> Color {
        let t = min(1, max(0, position))
        if t <= 0.5 {
            let progress = Double(t * 2)
            return Color(
                red: 1.0 - progress * 0.84,
                green: 0.18 + progress * 0.74,
                blue: 0.16 + progress * 0.23
            )
        }

        let progress = Double((t - 0.5) * 2)
        return Color(
            red: 0.16 - progress * 0.06,
            green: 0.92 - progress * 0.46,
            blue: 0.39 + progress * 0.61
        )
    }
}

@MainActor
private final class VisualizerRenderClock: NSObject, ObservableObject {
    @Published private(set) var frameTime: CFTimeInterval = 0

    private var displayLink: CADisplayLink?

    func start(isPlaying: Bool, reduceMotion: Bool) {
        if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        update(isPlaying: isPlaying, reduceMotion: reduceMotion)
    }

    func update(isPlaying: Bool, reduceMotion: Bool) {
        guard let displayLink else { return }

        let nativeRate = max(30, UIScreen.main.maximumFramesPerSecond)
        let preferredRate = reduceMotion ? min(30, nativeRate) : nativeRate
        if #available(iOS 15.0, *) {
            let preferred = Float(preferredRate)
            let minimum = reduceMotion ? preferred : min(60, preferred)
            displayLink.preferredFrameRateRange = CAFrameRateRange(
                minimum: minimum,
                maximum: preferred,
                preferred: preferred
            )
        } else {
            displayLink.preferredFramesPerSecond = preferredRate
        }
        displayLink.isPaused = !isPlaying
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ displayLink: CADisplayLink) {
        frameTime = displayLink.targetTimestamp
    }
}

struct AudioReactiveVisualizerScreen: View {
    @ObservedObject var audio: AudioPlayer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var renderClock = VisualizerRenderClock()

    var body: some View {
        let renderTime = renderClock.frameTime
        ZStack {
            VisualizerPalette.background.ignoresSafeArea()

            let frame = AudioVisualizerFrame(
                snapshot: audio.visualizerSnapshot(),
                isPlaying: audio.isPlaying
            )
            Canvas(opaque: true, colorMode: .nonLinear) { context, size in
                Self.draw(
                    frame: frame,
                    renderTime: renderTime,
                    context: &context,
                    size: size
                )
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    closeButton
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)

                Spacer()

                trackDetails
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)

                transport
                    .padding(.bottom, 44)
            }
        }
        .preferredColorScheme(Theme.colorScheme)
        .onAppear {
            // The visualizer stays attached to the live audio tap on every
            // supported OS instead of falling back to a synthetic animation.
            audio.setVisualizerActive(true)
            renderClock.start(isPlaying: audio.isPlaying, reduceMotion: reduceMotion)
        }
        .onDisappear {
            renderClock.stop()
            audio.setVisualizerActive(false)
        }
        .onChangeCompat(of: audio.isPlaying) { isPlaying in
            renderClock.update(isPlaying: isPlaying, reduceMotion: reduceMotion)
        }
        .onChangeCompat(of: reduceMotion) { updatedReduceMotion in
            renderClock.update(isPlaying: audio.isPlaying, reduceMotion: updatedReduceMotion)
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(VisualizerPalette.paper)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close visualizer")
    }

    private var trackDetails: some View {
        VStack(spacing: 8) {
            OverflowSlidingText(
                text: audio.currentSong?.title ?? L(.player_not_playing),
                font: .title2.bold(),
                uiFont: .systemFont(
                    ofSize: UIFont.preferredFont(forTextStyle: .title2).pointSize,
                    weight: .bold
                ),
                color: VisualizerPalette.paper
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(audio.currentSong?.artist ?? " ")
                .font(.subheadline)
                .foregroundStyle(VisualizerPalette.paper.opacity(0.64))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var transport: some View {
        HStack(spacing: 36) {
            Button { audio.skipPrevious() } label: {
                Image(systemName: Symbols.previous)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(VisualizerPalette.paper)
                    .frame(width: 58, height: 58)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous track")

            Button { audio.togglePlayPause() } label: {
                Image(systemName: audio.isPlaying ? Symbols.pause : Symbols.play)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(VisualizerPalette.background)
                    .frame(width: 68, height: 62)
                    .background(VisualizerPalette.paper, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(audio.isPlaying ? "Pause" : "Play")

            Button { audio.skipNext() } label: {
                Image(systemName: Symbols.next)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(VisualizerPalette.paper)
                    .frame(width: 58, height: 58)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next track")
        }
    }

    private static func draw(
        frame: AudioVisualizerFrame,
        renderTime: CFTimeInterval,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(VisualizerPalette.background))
        drawClassic(frame: frame, renderTime: renderTime, context: &context, size: size)
    }

    private static func drawClassic(
        frame: AudioVisualizerFrame,
        renderTime: CFTimeInterval,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let centerY = size.height * 0.42
        let visualHeight = min(size.height * 0.34, size.width * 0.55)
        let energy = max(0.03, frame.rms)

        let bandCount = max(1, frame.bands.count)
        for index in 0..<bandCount {
            let amplitude = pow(frame.band(at: index), 0.72)
            let x = (CGFloat(index) + 0.5) / CGFloat(bandCount) * size.width
            let height = visualHeight * CGFloat(0.06 + amplitude * 0.94 + frame.beat * 0.04)
            var bar = Path()
            bar.move(to: CGPoint(x: x, y: centerY - height))
            bar.addLine(to: CGPoint(x: x, y: centerY + height))
            context.stroke(
                bar,
                with: .color(VisualizerPalette.rgb(at: x / max(1, size.width)).opacity(0.20 + amplitude * 0.70)),
                style: StrokeStyle(lineWidth: max(1.0, size.width / CGFloat(bandCount) * 0.44), lineCap: .round)
            )
        }

        let waveformCount = max(1, frame.waveform.count)
        var waveform = Path()
        for index in 0..<waveformCount {
            let x = CGFloat(index) / CGFloat(max(1, waveformCount - 1)) * size.width
            let y = centerY + CGFloat(frame.waveform(at: index)) * visualHeight
            if index == 0 {
                waveform.move(to: CGPoint(x: x, y: y))
            } else {
                waveform.addLine(to: CGPoint(x: x, y: y))
            }
        }
        context.stroke(
            waveform,
            with: .linearGradient(
                VisualizerPalette.rgbGradient(opacity: 0.92),
                startPoint: CGPoint(x: 0, y: centerY),
                endPoint: CGPoint(x: size.width, y: centerY)
            ),
            style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round)
        )

        let scanProgress = CGFloat(renderTime.truncatingRemainder(dividingBy: 1.8) / 1.8)
        let scanX = size.width * scanProgress
        var scan = Path()
        scan.move(to: CGPoint(x: scanX, y: centerY - visualHeight))
        scan.addLine(to: CGPoint(x: scanX, y: centerY + visualHeight))
        context.stroke(
            scan,
            with: .color(VisualizerPalette.rgb(at: scanProgress).opacity(0.10 + energy * 0.14)),
            style: StrokeStyle(lineWidth: 0.75)
        )
    }

}

private struct AudioVisualizerFrame: Sendable {
    let bands: [Double]
    let waveform: [Double]
    let rms: Double
    let beat: Double

    init(snapshot: AudioVisualizerSnapshot, isPlaying: Bool) {
        bands = isPlaying ? snapshot.bands : AudioVisualizerSnapshot.silent.bands
        waveform = isPlaying ? snapshot.waveform : AudioVisualizerSnapshot.silent.waveform
        rms = isPlaying ? min(1.0, snapshot.rms * 4.6) : 0
        beat = isPlaying ? min(1.0, snapshot.beat) : 0
    }

    func band(at index: Int) -> Double {
        guard !bands.isEmpty else { return 0 }
        return max(0, min(1, bands[index % bands.count]))
    }

    func waveform(at index: Int) -> Double {
        guard !waveform.isEmpty else { return 0 }
        return max(-1, min(1, waveform[index % waveform.count]))
    }
}
