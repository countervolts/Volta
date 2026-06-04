import SwiftUI
import UIKit

struct TrackRow<Trailing: View>: View {
    let song: Song
    let index: Int
    var isCurrentlyPlaying: Bool = false
    var onTap: () -> Void = {}
    var showDownloadState: Bool = true
    var showArtist: Bool = false
    // show the song's cover art on the left instead of the track number
    var leadingArtwork: Bool = false
    // swipe-right to play next (these rows aren't in a List, so we drive it
    // with a drag gesture instead of native swipeActions)
    var onSwipePlayNext: (() -> Void)? = nil
    @State private var dragX: CGFloat = 0
    @ViewBuilder var trailing: () -> Trailing

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

    // subtitle under the title: artist (for playlists) and/or featured artists
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

            Button(action: onTap) {
                HStack(spacing: 14) {
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

                    Spacer()

                    if showDownloadState {
                        DownloadStateIndicator(song: song)
                    }

                    trailing()
                }
                .contentShape(Rectangle())
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
            .buttonStyle(.plain)
            .offset(x: dragX)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: dragX)
        }
        .contentShape(Rectangle())
        .background {
            if onSwipePlayNext != nil {
                RowHorizontalSwipeBridge(
                    onChanged: { x in dragX = max(0, min(swipeMax, x)) },
                    onEnded: { x in
                        let finalX = max(0, min(swipeMax, x))
                        if finalX >= swipeTrigger {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onSwipePlayNext?()
                        }
                        dragX = 0
                    },
                    onCancelled: { dragX = 0 }
                )
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

    private func formatDuration(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct RowHorizontalSwipeBridge: UIViewRepresentable {
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void
    var onCancelled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded, onCancelled: onCancelled)
    }

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: HostView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onCancelled = onCancelled
        uiView.coordinator = context.coordinator
        uiView.installIfPossible()
    }

    static func dismantleUIView(_ uiView: HostView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class HostView: UIView {
        weak var coordinator: Coordinator?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            installIfPossible()
        }

        func installIfPossible() {
            coordinator?.attach(to: superview)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGFloat) -> Void
        var onEnded: (CGFloat) -> Void
        var onCancelled: () -> Void
        private weak var attachedView: UIView?
        private var pan: UIPanGestureRecognizer?

        init(onChanged: @escaping (CGFloat) -> Void,
             onEnded: @escaping (CGFloat) -> Void,
             onCancelled: @escaping () -> Void) {
            self.onChanged = onChanged
            self.onEnded = onEnded
            self.onCancelled = onCancelled
        }

        func attach(to view: UIView?) {
            guard let view, attachedView !== view else { return }
            detach()
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            view.addGestureRecognizer(recognizer)
            attachedView = view
            pan = recognizer
        }

        func detach() {
            if let pan, let attachedView {
                attachedView.removeGestureRecognizer(pan)
            }
            pan = nil
            attachedView = nil
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let x = max(0, recognizer.translation(in: recognizer.view).x)
            switch recognizer.state {
            case .began, .changed:
                onChanged(x)
            case .ended:
                onEnded(x)
            case .cancelled, .failed:
                onCancelled()
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return velocity.x > 80 && abs(velocity.x) > abs(velocity.y) * 1.35
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
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
