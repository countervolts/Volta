import SwiftUI
import UIKit

// Mini player used by both the tab accessory and fallback bar.
struct MiniPlayerAccessory: View {
    @EnvironmentObject private var appState: AppState
    var onExpand: () -> Void
    var onArtworkFrameChange: (CGRect) -> Void = { _ in }
    var onTransitionGeometryChange: (MiniPlayerTransitionGeometry) -> Void = { _ in }
    var placement: MiniPlayerAccessoryPlacement = .legacy
    var showsNextButton = true
    var landingTextScale: CGFloat = 1
    var landingTextOffset: CGFloat = 0

    private var audio: AudioPlayer { appState.audioPlayer }

    @State private var dragX: CGFloat = 0
    @State private var measuredElementFrames: [MiniPlayerElement: CGRect] = [:]

    var body: some View {
        if let song = audio.currentSong {
            HStack(spacing: 10) {
                Button(action: onExpand) {
                    HStack(spacing: 10) {
                        artwork
                            .id(song.id)

                        MiniPlayerMetadataChrome(
                            title: song.title,
                            artist: song.artist ?? ""
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .scaleEffect(landingTextScale, anchor: .leading)
                        .offset(y: landingTextOffset)
                        .reportMiniPlayerElement(.metadata)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button { audio.togglePlayPause() } label: {
                    MiniPlayerTransportIcon(
                        systemName: audio.isPlaying ? Symbols.pause : Symbols.play
                    )
                        .contentShape(Rectangle())
                        .reportMiniPlayerElement(.playPause)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(audio.isPlaying ? "Pause" : "Play")

                if showsNextButton {
                    Button { audio.skipNext() } label: {
                        MiniPlayerTransportIcon(systemName: Symbols.next)
                            .contentShape(Rectangle())
                            .reportMiniPlayerElement(.next)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Next")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onPreferenceChange(MiniPlayerElementFramesKey.self) { frames in
                measuredElementFrames = frames
                reportTransitionGeometry(frames)
            }
            .onChangeCompat(of: placement) { _, _ in
                reportTransitionGeometry(measuredElementFrames)
            }
            .offset(x: dragX)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: dragX)
            // Swipe changes tracks; high priority keeps it from also opening the player.
            .highPriorityGesture(
                DragGesture(minimumDistance: 24)
                    .onChanged { v in
                        guard abs(v.translation.width) > abs(v.translation.height) else { return }
                        dragX = v.translation.width / 2.2   // resistance
                    }
                    .onEnded { v in
                        let w = v.translation.width
                        if abs(w) > abs(v.translation.height) {
                            if w < -48 { audio.skipNext() }
                            else if w > 48 { audio.skipPrevious() }
                        }
                        dragX = 0
                    }
            )
        }
    }

    @ViewBuilder
    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.secondaryBackground)
            if let image = audio.currentArtwork {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: Symbols.albumPlaceholder)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .reportMiniPlayerElement(.artwork)
    }

    private func reportTransitionGeometry(_ frames: [MiniPlayerElement: CGRect]) {
        let geometry = MiniPlayerTransitionGeometry(
            artworkFrame: frames[.artwork] ?? .zero,
            metadataFrame: frames[.metadata] ?? .zero,
            playPauseFrame: frames[.playPause] ?? .zero,
            nextFrame: frames[.next] ?? .zero,
            placement: placement
        )
        guard geometry.isMeaningful else { return }
        onArtworkFrameChange(geometry.artworkFrame)
        onTransitionGeometryChange(geometry)
    }
}

struct MiniPlayerMetadataChrome: View {
    let title: String
    let artist: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            OverflowSlidingText(
                text: title,
                font: .subheadline.weight(.semibold),
                uiFont: .systemFont(
                    ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize,
                    weight: .semibold
                ),
                color: .primary
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(artist)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct MiniPlayerTransportIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 36, height: 36)
    }
}

enum MiniPlayerAccessoryPlacement: String, Hashable {
    case legacy
    case inline
    case expanded
    case undefined
}

struct MiniPlayerTransitionGeometry: Equatable {
    var artworkFrame: CGRect = .zero
    var metadataFrame: CGRect = .zero
    var playPauseFrame: CGRect = .zero
    var nextFrame: CGRect = .zero
    var placement: MiniPlayerAccessoryPlacement = .undefined

    var isMeaningful: Bool {
        [artworkFrame, metadataFrame, playPauseFrame, nextFrame].allSatisfy {
            $0.width > 1 && $0.height > 1
                && $0.minX.isFinite && $0.minY.isFinite
        }
    }
}

private enum MiniPlayerElement: Hashable {
    case artwork
    case metadata
    case playPause
    case next
}

private struct MiniPlayerElementFramesKey: PreferenceKey {
    static var defaultValue: [MiniPlayerElement: CGRect] = [:]

    static func reduce(
        value: inout [MiniPlayerElement: CGRect],
        nextValue: () -> [MiniPlayerElement: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private extension View {
    func reportMiniPlayerElement(_ element: MiniPlayerElement) -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: MiniPlayerElementFramesKey.self,
                    value: [element: geo.frame(in: .global)]
                )
            }
        }
    }
}
