import SwiftUI
#if canImport(Translation)
import Translation
#endif

struct LyricsViewWithState: View {
    @EnvironmentObject private var appState: AppState
    @State private var lines: [LyricLine] = []
    @State private var isLoading = false
    @State private var activeLine: Int = 0
    @State private var translatedTexts: [Int: String] = [:]
    @State private var isShowingTranslation = false
    @State private var isTranslationRequestPending = false
    @State private var isTranslating = false
    @State private var translationRequestID = 0

    private static let translationRequestTimeoutNanoseconds: UInt64 = 5_000_000_000

    private var audio: AudioPlayer { appState.audioPlayer }
    private var isSynced: Bool { lines.first.map { $0.time >= 0 } ?? false }
    private var isTranslationBusy: Bool { isTranslationRequestPending || isTranslating }

    var body: some View {
        Group {
            if isLoading {
                VStack { Spacer(); ProgressView().tint(.white); Spacer() }
            } else if lines.isEmpty {
                emptyState
            } else if isSynced {
                focusedLyricsView
            } else {
                lyricsScroll
            }
        }
        .id(lyricsContentKey)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .opacity.combined(with: .move(edge: .top))
        ))
        .animation(.easeInOut(duration: 0.28), value: lyricsContentKey)
        .overlay(alignment: .topTrailing) { translationButton }
        .background(translationTaskView)
        .task(id: audio.currentSong?.id) { await loadLyrics() }
        .onChangeCompat(of: audio.currentTime) { _, t in updateActiveLine(for: t) }
    }

    private var lyricsContentKey: String {
        let songID = audio.currentSong?.id ?? "none"
        if isLoading { return "\(songID)-loading" }
        if lines.isEmpty { return "\(songID)-empty" }
        return "\(songID)-\(isSynced ? "synced" : "plain")-\(lines.count)"
    }

    // MARK: - Focused view (synced lyrics)

    private var focusedLyricsView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<lines.count, id: \.self) { idx in
                        let d = abs(idx - activeLine)
                        let isActive = d == 0
                        Text(displayText(for: lines[idx]))
                            .font(isActive
                                  ? .system(size: 32, weight: .bold)
                                  : .system(size: 22, weight: .semibold))
                            .foregroundStyle(.white.opacity(opacityFor(d)))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, isActive ? 28 : 20)
                            .contentShape(Rectangle())
                            // tap a synced line to seek playback to that timestamp
                            .onTapGesture {
                                let t = lines[idx].time
                                guard t >= 0 else { return }
                                audio.seek(to: t)
                                activeLine = lines[idx].id
                            }
                            .id(idx)
                    }
                    Color.clear.frame(height: 80)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
            .onChangeCompat(of: activeLine) { _, l in
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                    proxy.scrollTo(max(0, l - 1), anchor: .top)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: Symbols.lyricsInactive)
                .font(.system(size: 40, weight: .ultraLight)).foregroundStyle(.white.opacity(0.3))
            Text(L(.lyrics_none)).font(.subheadline).foregroundStyle(.white.opacity(0.4))
            Spacer()
        }
    }

    private var lyricsScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(lines) { line in
                        let isActive = line.id == activeLine
                        let d = abs(line.id - activeLine)
                        let opacity = isSynced ? opacityFor(d) : 1.0
                        Text(displayText(for: line))
                            .font(isActive ? .system(size: 32, weight: .bold) : .system(size: 22, weight: .semibold))
                            .foregroundStyle(.white.opacity(opacity))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.bottom, isActive ? 28 : 20)
                            .id(line.id)
                            .animation(.easeInOut(duration: 0.35), value: isActive)
                    }
                    Color.clear.frame(height: 80)
                }
                .padding(.top, 16)
            }
            .onChangeCompat(of: activeLine) { _, l in
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    proxy.scrollTo(max(0, l - 1), anchor: .top)
                }
            }
        }
    }

    private func opacityFor(_ d: Int) -> Double {
        switch d { case 0: 1.0; case 1: 0.4; case 2: 0.2; default: 0.1 }
    }

    private func displayText(for line: LyricLine) -> String {
        let text = isShowingTranslation ? (translatedTexts[line.id] ?? line.text) : line.text
        return text.isEmpty ? " " : text
    }

    @ViewBuilder
    private var translationButton: some View {
#if canImport(Translation)
        if #available(iOS 18.0, *), !lines.isEmpty {
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {}

                Button { toggleTranslation() } label: {
                    ZStack {
                        if isTranslationBusy {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "translate")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .foregroundStyle(isShowingTranslation ? Theme.accent : .white.opacity(0.78))
                    .frame(width: 36, height: 36)
                    .glassCircle()
                    .frame(width: 52, height: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(width: 60, height: 52)
            .padding(.trailing, 4)
        }
#endif
    }

    @ViewBuilder
    private var translationTaskView: some View {
#if canImport(Translation)
        if #available(iOS 18.0, *) {
            LyricsTranslationTask(
                requestID: translationRequestID,
                lines: lines,
                isShowing: isShowingTranslation,
                setTranslating: {
                    if $0 { isTranslationRequestPending = false }
                    isTranslating = $0
                },
                finish: {
                    translatedTexts = $0
                    isTranslationRequestPending = false
                }
            )
        }
#else
        EmptyView()
#endif
    }

#if canImport(Translation)
    @available(iOS 18.0, *)
    private func toggleTranslation() {
        guard !isTranslationBusy else { return }

        if isShowingTranslation {
            isShowingTranslation = false
            return
        }

        isTranslationRequestPending = true
        isShowingTranslation = true
        translationRequestID += 1
        let requestID = translationRequestID
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.translationRequestTimeoutNanoseconds)
            if isTranslationRequestPending, translationRequestID == requestID {
                isTranslationRequestPending = false
            }
        }
    }
#endif

    // MARK: - Data loading

    private func loadLyrics() async {
        guard let song = audio.currentSong, let client = appState.client else {
            lines = []; return
        }
        isLoading = true
        defer { isLoading = false }
        lines = await LyricsService.shared.lyrics(for: song, client: client)
        translatedTexts = [:]
        isShowingTranslation = false
        isTranslationRequestPending = false
        isTranslating = false
        translationRequestID = 0
        activeLine = 0
        updateActiveLine(for: audio.currentTime)
    }

    private func updateActiveLine(for time: TimeInterval) {
        guard isSynced else { return }
        if let idx = lines.lastIndex(where: { $0.time <= time }) {
            let id = lines[idx].id
            if id != activeLine { activeLine = id }
        }
    }
}

#if canImport(Translation)
@available(iOS 18.0, *)
private struct LyricsTranslationTask: View {
    let requestID: Int
    let lines: [LyricLine]
    let isShowing: Bool
    let setTranslating: @MainActor (Bool) -> Void
    let finish: @MainActor ([Int: String]) -> Void

    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear(perform: refresh)
            .onChangeCompat(of: requestID) { _, _ in refresh() }
            .translationTask(configuration) { session in
                await translate(using: session)
            }
    }

    private func refresh() {
        guard isShowing, requestID > 0 else { return }
        if configuration == nil {
            configuration = TranslationSession.Configuration(source: nil, target: Locale.current.language)
        } else {
            configuration?.invalidate()
        }
    }

    private func translate(using session: TranslationSession) async {
        guard isShowing else { return }
        setTranslating(true)
        defer { setTranslating(false) }

        var translated: [Int: String] = [:]
        for line in lines where !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let response = try? await session.translate(line.text) {
                translated[line.id] = response.targetText
            }
        }
        finish(translated)
    }
}
#endif
