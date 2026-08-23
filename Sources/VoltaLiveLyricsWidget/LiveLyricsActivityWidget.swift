import ActivityKit
import SwiftUI
#if canImport(VoltaLiveActivitySupport)
import VoltaLiveActivitySupport
#endif
import WidgetKit

@main
@available(iOS 16.1, *)
struct VoltaLiveLyricsWidgetBundle: WidgetBundle {
    var body: some Widget {
        VoltaLiveLyricsWidget()
        VoltaLibraryWidget()
        VoltaListeningWidget()
    }
}

@available(iOS 16.1, *)
private struct VoltaLiveLyricsWidget: Widget {
    var body: some WidgetConfiguration {
        if #available(iOS 18.0, *) {
            // CarPlay otherwise merges the one-line compact leading/trailing regions.
            return activityConfiguration
                .supplementalActivityFamilies([.small])
        } else {
            return activityConfiguration
        }
    }

    private var activityConfiguration: ActivityConfiguration<LiveLyricsActivityAttributes> {
        ActivityConfiguration(for: LiveLyricsActivityAttributes.self) { context in
            LiveLyricsActivityView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.92))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            LiveLyricsDynamicIsland.make(state: context.state)
        }
    }
}

@available(iOS 16.1, *)
private struct LiveLyricsActivityView: View {
    let state: LiveLyricsActivityAttributes.ContentState

    @ViewBuilder
    var body: some View {
        if #available(iOS 18.0, *) {
            LiveLyricsActivityFamilyView(state: state)
        } else {
            LiveLyricsLockScreenView(state: state)
        }
    }
}

@available(iOS 18.0, *)
private struct LiveLyricsActivityFamilyView: View {
    @Environment(\.activityFamily) private var activityFamily

    let state: LiveLyricsActivityAttributes.ContentState

    @ViewBuilder
    var body: some View {
        if activityFamily == .small {
            LiveLyricsSmallActivityView(state: state)
        } else {
            LiveLyricsLockScreenView(state: state)
        }
    }
}

@available(iOS 18.0, *)
private struct LiveLyricsSmallActivityView: View {
    let state: LiveLyricsActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(state.currentLine)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.72)
                .fixedSize(horizontal: false, vertical: true)

            if !state.nextLine.isEmpty {
                Text(state.nextLine)
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

@available(iOS 16.1, *)
private struct LiveLyricsLockScreenView: View {
    let state: LiveLyricsActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .foregroundStyle(.purple)
                Text("VOLTA LYRICS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                Spacer(minLength: 8)
                if !state.isPlaying {
                    Image(systemName: "pause.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Paused")
                }
            }

            Text(state.currentLine)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)

            if !state.nextLine.isEmpty {
                Text(state.nextLine)
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(spacing: 4) {
                Text(state.songTitle)
                    .fontWeight(.semibold)
                Text("·")
                Text(state.artist)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

@available(iOS 16.1, *)
private enum LiveLyricsDynamicIsland {
    static func make(
        state: LiveLyricsActivityAttributes.ContentState
    ) -> DynamicIsland {
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                Image(systemName: "music.note")
                    .foregroundStyle(.purple)
            }
            DynamicIslandExpandedRegion(.trailing) {
                Image(systemName: state.isPlaying ? "waveform" : "pause.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(state.isPlaying ? "Playing" : "Paused")
            }
            DynamicIslandExpandedRegion(.center) {
                Text(state.songTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            DynamicIslandExpandedRegion(.bottom) {
                VStack(spacing: 3) {
                    Text(state.currentLine)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    if !state.nextLine.isEmpty {
                        Text(state.nextLine)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 8)
            }
        } compactLeading: {
            Image(systemName: "music.note")
                .foregroundStyle(.purple)
        } compactTrailing: {
            Text(state.currentLine)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        } minimal: {
            Image(systemName: "music.note")
                .foregroundStyle(.purple)
        }
        .keylineTint(.purple)
    }
}
