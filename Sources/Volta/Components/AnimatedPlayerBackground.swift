import SwiftUI
import UIKit

/// The full-player artwork wash used by the web player.
///
/// The scene intentionally uses the same proportions and timing as the web
/// implementation: one oversized cover plus three smaller covers, with the
/// latter two orbiting inside their own rotating squares. Keeping the scene
/// on a 15 Hz timeline is important here; the large blur is ambient motion,
/// not a control that needs a 60 Hz render loop.
struct AnimatedPlayerBackground: View {
    let artwork: UIImage?
    let artworkID: String?
    let fallbackColor: Color

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var startedAt = Date()
    @State private var displayedArtwork: UIImage?
    @State private var displayedArtworkID: String?
    @State private var outgoingArtwork: UIImage?
    @State private var artworkOpacity: Double
    @State private var transitionID = 0

    private static let renderInterval = 1.0 / 15.0
    private static let artworkFadeDuration = 1.7
    private static let reducedMotionScale = 0.2
    private static let blurRadius: CGFloat = 104

    init(artwork: UIImage?, artworkID: String?, fallbackColor: Color) {
        self.artwork = artwork
        self.artworkID = artworkID
        self.fallbackColor = fallbackColor
        _displayedArtwork = State(initialValue: artwork)
        _displayedArtworkID = State(initialValue: artwork == nil ? nil : artworkID)
        _artworkOpacity = State(initialValue: artwork == nil ? 0 : 1)
    }

    private var reducesMotion: Bool {
        accessibilityReduceMotion || PerformanceMode.reduceAnimations
    }

    private var motionScale: Double {
        reducesMotion ? Self.reducedMotionScale : 1
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.renderInterval)) { context in
            GeometryReader { geometry in
                let size = geometry.size
                let elapsed = max(0, context.date.timeIntervalSince(startedAt)) * motionScale

                ZStack {
                    fallbackColor

                    if displayedArtwork != nil || outgoingArtwork != nil {
                        artworkMesh(
                            in: size,
                            elapsed: elapsed,
                            artwork: displayedArtwork,
                            outgoingArtwork: outgoingArtwork,
                            opacity: artworkOpacity
                        )
                        .drawingGroup(opaque: false)
                        .blur(radius: Self.blurRadius, opaque: false)
                        // The web shader applies one strong grade after the
                        // blur. These native filters preserve that visual
                        // relationship on iOS while keeping the target at iOS 16.
                        .saturation(2.75)
                        .contrast(1.9)
                        .brightness(-0.3)
                    }

                    // Keep the artwork and lyrics brighter than the ambient
                    // wash, matching the web player's final veil and lift.
                    Color.black.opacity(0.5)
                    Color.white.opacity(0.05)
                }
                .frame(width: size.width, height: size.height)
                .clipped()
            }
        }
        .task(id: transitionID) {
            guard transitionID > 0 else { return }
            try? await Task.sleep(nanoseconds: 1_850_000_000)
            guard !Task.isCancelled else { return }
            outgoingArtwork = nil
        }
        .onAppear {
            updateArtwork(animated: false)
        }
        .onChange(of: artworkID) { _ in
            updateArtwork(animated: true)
        }
    }

    @ViewBuilder
    private func artworkMesh(
        in size: CGSize,
        elapsed: TimeInterval,
        artwork: UIImage?,
        outgoingArtwork: UIImage?,
        opacity: Double
    ) -> some View {
        let width = size.width
        let height = size.height

        ZStack {
            // Web: .fullscreen-cover { inset: -35% }
            artworkLayer(
                size: CGSize(width: width * 1.7, height: height * 1.7),
                center: CGPoint(x: width / 2, y: height / 2),
                angle: 0,
                anchor: .center,
                artwork: artwork,
                outgoingArtwork: outgoingArtwork,
                opacity: opacity
            )

            // Web: 125% square, centred in the viewport.
            artworkLayer(
                size: CGSize(width: width * 1.25, height: width * 1.25),
                center: CGPoint(x: width * 0.5, y: height * 0.5),
                angle: degrees(elapsed, period: 69.813, direction: 1),
                anchor: .center,
                artwork: artwork,
                outgoingArtwork: outgoingArtwork,
                opacity: opacity
            )

            // Web: 80% square, offset toward the upper-left.
            artworkLayer(
                size: CGSize(width: width * 0.8, height: width * 0.8),
                center: CGPoint(x: width * 0.4, y: height * 0.4),
                angle: degrees(elapsed, period: 26.18, direction: -1),
                anchor: .center,
                artwork: artwork,
                outgoingArtwork: outgoingArtwork,
                opacity: opacity
            )

            // Web: a rotating orbit square containing the 50% sprite.
            orbitLayer(
                width: width,
                height: height,
                angle: degrees(elapsed, period: 46.542, direction: -1),
                anchor: .center
            ) {
                artworkLayer(
                    size: CGSize(width: width * 0.5, height: width * 0.5),
                    center: CGPoint(x: width * 0.75, y: width * 0.5),
                    angle: degrees(elapsed, period: 34.907, direction: 1),
                    anchor: .center,
                    artwork: artwork,
                    outgoingArtwork: outgoingArtwork,
                    opacity: opacity
                )
            }

            // Web: a second orbit square containing the 25% sprite, with its
            // slightly offset transform origin preserved.
            orbitLayer(
                width: width,
                height: height,
                angle: degrees(elapsed, period: 69.813, direction: 1),
                anchor: UnitPoint(x: 0.55, y: 0.55)
            ) {
                artworkLayer(
                    size: CGSize(width: width * 0.25, height: width * 0.25),
                    center: CGPoint(x: width * 0.8, y: width * 0.55),
                    angle: degrees(elapsed, period: 52.36, direction: -1),
                    anchor: .center,
                    artwork: artwork,
                    outgoingArtwork: outgoingArtwork,
                    opacity: opacity
                )
            }
        }
    }

    @ViewBuilder
    private func orbitLayer<Content: View>(
        width: CGFloat,
        height: CGFloat,
        angle: Double,
        anchor: UnitPoint,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(width: width, height: width, alignment: .topLeading)
            .position(x: width / 2, y: height / 2)
            .rotationEffect(.degrees(angle), anchor: anchor)
    }

    @ViewBuilder
    private func artworkLayer(
        size: CGSize,
        center: CGPoint,
        angle: Double,
        anchor: UnitPoint,
        artwork: UIImage?,
        outgoingArtwork: UIImage?,
        opacity: Double
    ) -> some View {
        ZStack {
            if let outgoingArtwork {
                artworkImage(outgoingArtwork)
            }
            if let artwork {
                artworkImage(artwork)
                    .opacity(opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .position(center)
        .rotationEffect(.degrees(angle), anchor: anchor)
    }

    @ViewBuilder
    private func artworkImage(_ image: UIImage) -> some View {
        if image.images?.count ?? 0 > 1 {
            AnimatedImageView(image: image)
        } else {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
    }

    private func degrees(_ elapsed: TimeInterval, period: TimeInterval, direction: Double) -> Double {
        guard period > 0 else { return 0 }
        return (elapsed / period).truncatingRemainder(dividingBy: 1) * 360 * direction
    }

    private func updateArtwork(animated: Bool) {
        guard let artwork else {
            displayedArtwork = nil
            displayedArtworkID = nil
            outgoingArtwork = nil
            artworkOpacity = 0
            return
        }

        guard artworkID != displayedArtworkID || displayedArtwork == nil else { return }

        if animated, let displayedArtwork {
            outgoingArtwork = displayedArtwork
            artworkOpacity = 0
        } else {
            outgoingArtwork = nil
            artworkOpacity = 1
        }

        displayedArtwork = artwork
        displayedArtworkID = artworkID

        if animated {
            transitionID &+= 1
            withAnimation(.linear(duration: Self.artworkFadeDuration)) {
                artworkOpacity = 1
            }
        }
    }
}
