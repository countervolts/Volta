import SwiftUI

struct TrackRow<Trailing: View>: View {
    let song: Song
    let index: Int
    var isCurrentlyPlaying: Bool = false
    var onTap: () -> Void = {}
    var showDownloadState: Bool = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    if isCurrentlyPlaying {
                        Image(systemName: "waveform")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .symbolEffect(.variableColor.iterative.reversing, isActive: true)
                    } else {
                        Text("\(index)")
                            .font(.system(size: 14, weight: .regular).monospacedDigit())
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.body)
                        .foregroundStyle(isCurrentlyPlaying ? Theme.accent : Theme.primaryText)
                    if let extra = song.contributes, !extra.isEmpty {
                        Text(extra)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if showDownloadState {
                    DownloadStateIndicator(song: song)
                }

                trailing()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private func formatDuration(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

extension TrackRow where Trailing == EmptyView {
    init(
        song: Song,
        index: Int,
        isCurrentlyPlaying: Bool = false,
        onTap: @escaping () -> Void = {},
        showDownloadState: Bool = true
    ) {
        self.init(
            song: song,
            index: index,
            isCurrentlyPlaying: isCurrentlyPlaying,
            onTap: onTap,
            showDownloadState: showDownloadState
        ) { EmptyView() }
    }
}

// MARK: - Download state indicator

private struct DownloadStateIndicator: View {
    let song: Song

    var body: some View {
        let state = DownloadService.shared.state(for: song)
        switch state {
        case .notDownloaded:
            EmptyView()
        case .downloading(let progress):
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.2), lineWidth: 1.5)
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
            .animation(.linear(duration: 0.2), value: progress)
        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.green.opacity(0.7))
        }
    }
}
