import SwiftUI

// Mini player that lives inside the native `.tabViewBottomAccessory` slot.
// The system draws the Liquid Glass capsule + handles the collapse-with-tab-bar
// motion; we only supply the content and shrink it when the bar minimizes.
//
// placement == .inline  → accessory is riding INSIDE the minimized tab bar
//                         (tight: artwork + title + play/pause only)
// placement == .expanded/.none → full-width pill above the bar
//                         (artwork + title/artist + play/pause + next)
struct MiniPlayerAccessory: View {
    @Environment(AppState.self) private var appState
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    var onExpand: () -> Void

    private var audio: AudioPlayer { appState.audioPlayer }

    private var compact: Bool {
        if case .inline = placement { return true }
        return false
    }

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
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
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
    }
}
