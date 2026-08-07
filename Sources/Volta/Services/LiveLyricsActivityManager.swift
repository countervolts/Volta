import Combine
import Foundation

#if os(iOS)
import UIKit
#endif

#if canImport(ActivityKit)
import ActivityKit
#endif

#if canImport(VoltaLiveActivitySupport)
import VoltaLiveActivitySupport
#endif

enum LiveLyricsPreferences {
    static let enabledKey = "liveLyricsActivityEnabled"
}

@MainActor
final class LiveLyricsActivityManager {
    static let shared = LiveLyricsActivityManager()

    private weak var appState: AppState?
    private var controller: Any?

    private init() {}

    func connect(appState: AppState) {
        guard self.appState !== appState else { return }
        self.appState = appState

#if os(iOS) && canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            controller = LiveLyricsActivityController(appState: appState)
        }
#endif
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: LiveLyricsPreferences.enabledKey)

#if os(iOS) && canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            (controller as? LiveLyricsActivityController)?.setEnabled(enabled)
        }
#endif
    }
}

#if os(iOS) && canImport(ActivityKit)
@available(iOS 16.1, *)
@MainActor
private final class LiveLyricsActivityController {
    private struct LyricGroup {
        let time: TimeInterval
        let text: String
    }

    private struct ResolvedLyric {
        let current: String
        let next: String
        let groupIndex: Int
        let nextBoundary: TimeInterval?
    }

    private weak var appState: AppState?
    private let audio: AudioPlayer
    private var cancellables: Set<AnyCancellable> = []
    private var songTask: Task<Void, Never>?
    private var publishTask: Task<Void, Never>?
    private var lyricGroups: [LyricGroup] = []
    private var lyricsSongID: String?
    private var activity: Activity<LiveLyricsActivityAttributes>?
    private var desiredState: LiveLyricsActivityAttributes.ContentState?
    private var failedStartSongID: String?
    private var wasDismissedForCurrentSession = false

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: LiveLyricsPreferences.enabledKey)
    }

    init(appState: AppState) {
        self.appState = appState
        audio = appState.audioPlayer
        observePlayback()
        handleSongChange(audio.currentSong)
    }

    deinit {
        songTask?.cancel()
        publishTask?.cancel()
    }

    func setEnabled(_ enabled: Bool) {
        failedStartSongID = nil
        desiredState = nil
        wasDismissedForCurrentSession = false

        if enabled {
            loadLyricsForCurrentSong()
        } else {
            lyricGroups = []
            lyricsSongID = nil
            songTask?.cancel()
            publishTask?.cancel()
            Task { @MainActor [weak self] in
                await self?.endAllActivities()
            }
        }
    }

    private func observePlayback() {
        audio.$currentSong
            .sink { [weak self] song in
                Task { @MainActor [weak self] in
                    self?.handleSongChange(song)
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            audio.$currentTime,
            audio.$isPlaying,
            audio.$hasActivePlaybackSession
        )
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshActivity()
                }
            }
            .store(in: &cancellables)

        appState?.$client
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.isEnabled,
                          let songID = self.audio.currentSong?.id,
                          self.lyricsSongID != songID else { return }
                    self.loadLyricsForCurrentSong()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.failedStartSongID = nil
                    self?.desiredState = nil
                    self?.refreshActivity()
                }
            }
            .store(in: &cancellables)
    }

    private func handleSongChange(_ song: Song?) {
        lyricGroups = []
        lyricsSongID = nil
        desiredState = nil
        failedStartSongID = nil
        songTask?.cancel()
        publishTask?.cancel()

        guard song != nil, isEnabled else {
            if song == nil {
                wasDismissedForCurrentSession = false
            }
            Task { @MainActor [weak self] in
                await self?.endAllActivities()
            }
            return
        }

        if let song {
            updateExistingActivityStatus("Loading lyrics…", for: song)
        }
        loadLyricsForCurrentSong()
    }

    private func loadLyricsForCurrentSong() {
        songTask?.cancel()
        guard isEnabled,
              let song = audio.currentSong else {
            if audio.currentSong == nil {
                Task { @MainActor [weak self] in
                    await self?.endAllActivities()
                }
            }
            return
        }

        songTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard !Task.isCancelled,
                  let client = self.appState?.client else { return }

            let lines = await LyricsService.shared.lyrics(for: song, client: client)
            guard !Task.isCancelled,
                  self.isEnabled,
                  self.audio.currentSong?.id == song.id else { return }

            self.lyricGroups = Self.makeGroups(from: lines)
            self.lyricsSongID = song.id
            self.desiredState = nil

            guard !self.lyricGroups.isEmpty else {
                AppLogger.shared.log(
                    "Live Lyrics skipped; song='\(song.title)' has no time-synced lyrics",
                    category: .lyrics
                )
                self.updateExistingActivityStatus("No synced lyrics", for: song)
                return
            }

            AppLogger.shared.log(
                "Live Lyrics ready; song='\(song.title)'; timedGroups=\(self.lyricGroups.count)",
                category: .lyrics
            )
            self.refreshActivity()
        }
    }

    private func refreshActivity() {
        guard isEnabled,
              audio.hasActivePlaybackSession,
              let song = audio.currentSong,
              lyricsSongID == song.id,
              !lyricGroups.isEmpty else { return }

        let elapsed = audio.playbackTimeSnapshot().elapsed
        guard let lyric = resolveLyric(at: elapsed) else { return }

        let state = LiveLyricsActivityAttributes.ContentState(
            songTitle: Self.limited(song.title, to: 100),
            artist: Self.limited(Self.nonempty(song.artist) ?? "Unknown Artist", to: 100),
            currentLine: Self.limited(lyric.current, to: 300),
            nextLine: Self.limited(lyric.next, to: 180),
            isPlaying: audio.isPlaying,
            lineIndex: lyric.groupIndex
        )

        guard desiredState != state else { return }
        desiredState = state

        let staleDate: Date?
        if audio.isPlaying,
           let boundary = lyric.nextBoundary,
           boundary > elapsed {
            staleDate = Date().addingTimeInterval(boundary - elapsed + 3)
        } else {
            staleDate = nil
        }

        publishTask?.cancel()
        publishTask = Task { @MainActor [weak self] in
            await self?.publish(state, staleDate: staleDate, songID: song.id)
        }
    }

    private func publish(
        _ state: LiveLyricsActivityAttributes.ContentState,
        staleDate: Date?,
        songID: String
    ) async {
        guard isEnabled,
              !wasDismissedForCurrentSession,
              audio.currentSong?.id == songID else { return }

        if activity == nil {
            activity = Activity<LiveLyricsActivityAttributes>.activities.first
        }

        if let activity {
            let activityState = activity.activityState
            if activityState == .active {
                await update(activity, state: state, staleDate: staleDate)
                return
            }
            if #available(iOS 16.2, *), activityState == .stale {
                await update(activity, state: state, staleDate: staleDate)
                return
            }
            if #available(iOS 26.0, *), activityState == .pending {
                return
            }
            if activityState == .dismissed {
                failedStartSongID = songID
                wasDismissedForCurrentSession = true
                self.activity = nil
                return
            }
        }

        activity = nil
        guard failedStartSongID != songID else { return }
        guard UIApplication.shared.applicationState == .active else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            failedStartSongID = songID
            AppLogger.shared.log(
                "Live Lyrics unavailable because Live Activities are disabled by the system",
                category: .lyrics,
                level: .warning
            )
            return
        }

        do {
            let attributes = LiveLyricsActivityAttributes()
            if #available(iOS 16.2, *) {
                let content = ActivityContent(state: state, staleDate: staleDate)
                activity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
            } else {
                activity = try Activity.request(
                    attributes: attributes,
                    contentState: state,
                    pushType: nil
                )
            }
            failedStartSongID = nil
            AppLogger.shared.log("Live Lyrics activity started", category: .lyrics)
        } catch {
            failedStartSongID = songID
            AppLogger.shared.log(
                "Live Lyrics activity could not start: \(error.localizedDescription)",
                category: .lyrics,
                level: .warning
            )
        }
    }

    private func update(
        _ activity: Activity<LiveLyricsActivityAttributes>,
        state: LiveLyricsActivityAttributes.ContentState,
        staleDate: Date?
    ) async {
        if #available(iOS 16.2, *) {
            await activity.update(ActivityContent(state: state, staleDate: staleDate))
        } else {
            await activity.update(using: state)
        }
    }

    private func endAllActivities() async {
        let finalState = desiredState
        desiredState = nil
        failedStartSongID = nil
        activity = nil

        for existing in Activity<LiveLyricsActivityAttributes>.activities {
            if #available(iOS 16.2, *) {
                let content = finalState.map { ActivityContent(state: $0, staleDate: nil) }
                await existing.end(content, dismissalPolicy: .immediate)
            } else {
                await existing.end(using: finalState, dismissalPolicy: .immediate)
            }
        }
    }

    private func updateExistingActivityStatus(_ message: String, for song: Song) {
        if activity == nil {
            activity = Activity<LiveLyricsActivityAttributes>.activities.first
        }
        guard let existing = activity else { return }

        let activityState = existing.activityState
        if activityState == .dismissed {
            wasDismissedForCurrentSession = true
            activity = nil
            return
        }
        let canUpdate: Bool
        if activityState == .active {
            canUpdate = true
        } else if #available(iOS 16.2, *), activityState == .stale {
            canUpdate = true
        } else {
            canUpdate = false
        }
        guard canUpdate else { return }

        let state = LiveLyricsActivityAttributes.ContentState(
            songTitle: Self.limited(song.title, to: 100),
            artist: Self.limited(Self.nonempty(song.artist) ?? "Unknown Artist", to: 100),
            currentLine: message,
            nextLine: "",
            isPlaying: audio.isPlaying,
            lineIndex: -1
        )
        desiredState = state
        publishTask?.cancel()
        publishTask = Task { @MainActor [weak self] in
            await self?.update(existing, state: state, staleDate: nil)
        }
    }

    private func resolveLyric(at elapsed: TimeInterval) -> ResolvedLyric? {
        guard !lyricGroups.isEmpty else { return nil }
        let currentIndex = lyricGroups.lastIndex(where: { $0.time <= elapsed + 0.001 }) ?? 0
        let current = lyricGroups[currentIndex]
        let nextIndex = lyricGroups.index(after: currentIndex)
        let next = lyricGroups.indices.contains(nextIndex) ? lyricGroups[nextIndex] : nil
        return ResolvedLyric(
            current: current.text,
            next: next?.text ?? "",
            groupIndex: currentIndex,
            nextBoundary: next?.time
        )
    }

    private static func makeGroups(from lines: [LyricLine]) -> [LyricGroup] {
        let timed = lines.enumerated()
            .filter { $0.element.time >= 0 && nonempty($0.element.text) != nil }
            .sorted { lhs, rhs in
                if abs(lhs.element.time - rhs.element.time) <= 0.001 {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.time < rhs.element.time
            }

        var groups: [(time: TimeInterval, lines: [String])] = []
        for item in timed {
            let line = item.element
            guard let text = nonempty(line.text) else { continue }
            if let last = groups.indices.last,
               abs(groups[last].time - line.time) <= 0.001 {
                groups[last].lines.append(text)
            } else {
                groups.append((line.time, [text]))
            }
        }

        return groups.map { group in
            LyricGroup(time: group.time, text: group.lines.joined(separator: "\n"))
        }
    }

    private static func nonempty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func limited(_ value: String, to maximum: Int) -> String {
        guard value.count > maximum else { return value }
        return String(value.prefix(maximum - 1)) + "…"
    }
}
#endif
