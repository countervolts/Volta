import SwiftUI
import UIKit

struct TrackRow<Trailing: View>: View {
    let song: Song
    let index: Int
    var isCurrentlyPlaying: Bool = false
    var onTap: () -> Void = {}
    var showDownloadState: Bool = true
    var showArtist: Bool = false
    // cover art in the track-number slot
    var leadingArtwork: Bool = false
    // custom swipe, since these rows are not List rows
    var onSwipePlayNext: (() -> Void)? = nil
    @State private var dragX: CGFloat = 0
    @State private var swipeAxis: SwipeAxis?
    @State private var suppressTap = false
    @ViewBuilder var trailing: () -> Trailing

    private enum SwipeAxis {
        case horizontal
        case ignored
    }

    private let swipeAxisLockDistance: CGFloat = 22
    private let swipeHorizontalDominance: CGFloat = 1.65
    private let swipeTrigger: CGFloat = 128
    private let swipeMax: CGFloat = 220
    private var swipeProgress: CGFloat { min(1, dragX / swipeTrigger) }
    private var revealWidth: CGFloat {
        guard dragX > 0 else { return 0 }
        return max(0, dragX - 10)
    }
    private var revealIconOpacity: Double {
        Double(min(1, max(0, (dragX - 36) / 42)))
    }

    // artist/features line under the title
    private var subtitle: String? {
        let extra = song.contributes.flatMap { $0.isEmpty ? nil : $0 }
        if showArtist {
            let base = (song.artist?.isEmpty == false) ? song.artist : nil
            switch (base, extra) {
            case let (b?, e?): return "\(b) · \(e)"
            case let (b?, nil): return b
            case let (nil, e?): return e
            default: return nil
            }
        }
        return extra
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if onSwipePlayNext != nil {
                swipeReveal
            }

            rowContent
            .offset(x: dragX)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: dragX)
        }
        .contentShape(Rectangle())
        .highPriorityGesture(horizontalSwipeGesture)
    }

    private var rowContent: some View {
        HStack(spacing: 14) {
            Button(action: performTap) {
                HStack(spacing: 14) {
                    leadingContent
                    titleContent
                    Spacer(minLength: 8)
                    if showDownloadState {
                        DownloadStateIndicator(song: song)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, dragX > 0 ? 14 : 0)
        .background {
            if dragX > 0 {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 5)
            } else {
                Theme.background.opacity(0.001)
            }
        }
    }

    @ViewBuilder
    private var leadingContent: some View {
        if leadingArtwork {
            ZStack {
                ArtworkView(coverArtID: song.coverArt, size: 80, cornerRadius: 6)
                    .frame(width: 40, height: 40)
                if isCurrentlyPlaying {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.black.opacity(0.45))
                        .frame(width: 40, height: 40)
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .symbolEffect(.variableColor.iterative.reversing, isActive: true)
                }
            }
        } else {
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
        }
    }

    private var titleContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(song.title)
                .font(.body)
                .foregroundStyle(isCurrentlyPlaying ? Theme.accent : Theme.primaryText)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    private var swipeReveal: some View {
        let armed = dragX >= swipeTrigger
        return ZStack {
            RoundedRectangle(cornerRadius: revealWidth > 150 ? 30 : 34, style: .continuous)
                .fill(armed ? Theme.accent : Theme.accent.opacity(0.92))
            Image(systemName: "text.line.first.and.arrowtriangle.forward")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .opacity(revealIconOpacity)
                .symbolEffect(.bounce, value: armed)
        }
        .frame(width: revealWidth, height: 64)
        .scaleEffect(0.96 + (0.04 * swipeProgress), anchor: .leading)
        .opacity(Double(min(1, dragX / 36)))
        .padding(.leading, 0)
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.82), value: armed)
        .allowsHitTesting(false)
    }

    private var horizontalSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 22, coordinateSpace: .local)
            .onChanged { value in
                guard onSwipePlayNext != nil else { return }
                updateSwipe(translation: value.translation)
            }
            .onEnded { value in
                guard onSwipePlayNext != nil else {
                    resetSwipe()
                    return
                }
                finishSwipe(translation: value.translation)
            }
    }

    private func updateSwipe(translation: CGSize) {
        if swipeAxis == nil {
            let absX = abs(translation.width)
            let absY = abs(translation.height)
            guard max(absX, absY) >= swipeAxisLockDistance else { return }

            if translation.width > 0, absX > absY * swipeHorizontalDominance {
                swipeAxis = .horizontal
            } else if absY > absX || translation.width < 0 {
                swipeAxis = .ignored
            } else {
                return
            }
        }

        guard swipeAxis == .horizontal else {
            dragX = 0
            return
        }
        dragX = max(0, min(swipeMax, translation.width))
    }

    private func finishSwipe(translation: CGSize) {
        let finalX = max(0, min(swipeMax, translation.width))
        if swipeAxis == .horizontal {
            suppressNextTap()
            if finalX >= swipeTrigger {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onSwipePlayNext?()
            }
        }
        resetSwipe()
    }

    private func performTap() {
        guard !suppressTap else { return }
        onTap()
    }

    private func suppressNextTap() {
        suppressTap = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            suppressTap = false
        }
    }

    private func resetSwipe() {
        swipeAxis = nil
        dragX = 0
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
        showDownloadState: Bool = true,
        showArtist: Bool = false
    ) {
        self.init(
            song: song,
            index: index,
            isCurrentlyPlaying: isCurrentlyPlaying,
            onTap: onTap,
            showDownloadState: showDownloadState,
            showArtist: showArtist
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
