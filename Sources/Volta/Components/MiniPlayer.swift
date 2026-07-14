import SwiftUI

// Mini player used by both the tab accessory and fallback bar.
struct MiniPlayerAccessory: View {
    @EnvironmentObject private var appState: AppState
    var onExpand: () -> Void
    var onArtworkFrameChange: (CGRect) -> Void = { _ in }

    private var audio: AudioPlayer { appState.audioPlayer }

    @State private var dragX: CGFloat = 0

    var body: some View {
        if let song = audio.currentSong {
            Button(action: onExpand) {
                HStack(spacing: 10) {
                    artwork

                    VStack(alignment: .leading, spacing: 1) {
                        Text(song.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(song.artist ?? "")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button { audio.togglePlayPause() } label: {
                        Image(systemName: audio.isPlaying ? Symbols.pause : Symbols.play)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .offset(x: dragX)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: dragX)
            }
            .buttonStyle(.plain)
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
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: MiniPlayerArtworkFrameKey.self,
                    value: geo.frame(in: .global)
                )
            }
        }
        .onPreferenceChange(MiniPlayerArtworkFrameKey.self) { frame in
            guard frame.width > 1, frame.height > 1 else { return }
            onArtworkFrameChange(frame)
        }
    }
}

private struct MiniPlayerArtworkFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
