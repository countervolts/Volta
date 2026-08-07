import SwiftUI
#if canImport(Translation)
import Translation
#endif

struct LyricsViewWithState: View {
    @EnvironmentObject private var appState: AppState
    // The portrait player keeps this view mounted for its hero transition. Keep
    // its data warm, while allowing its display-rate renderer to sleep offstage.
    var isPlaybackRenderingActive = true
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
        .onReceive(audio.$currentTime) { time in
            guard isPlaybackRenderingActive else { return }
            updateActiveLine(for: time)
        }
        .onChangeCompat(of: isPlaybackRenderingActive) { _, isActive in
            guard isActive else { return }
            updateActiveLine(for: audio.playbackTimeSnapshot().elapsed)
        }
    }

    private var lyricsContentKey: String {
        let songID = audio.currentSong?.id ?? "none"
        if isLoading { return "\(songID)-loading" }
        if lines.isEmpty { return "\(songID)-empty" }
        return "\(songID)-\(isSynced ? "synced" : "plain")-\(lines.count)"
    }

    // MARK: - Focused view (synced lyrics)

    private var focusedLyricsView: some View {
        TimelineView(
            .animation(
                minimumInterval: FrameRateGovernor.minimumInterval,
                paused: !isPlaybackRenderingActive || !audio.isPlaying
            )
        ) { _ in
            let displayTime = audio.playbackTimeSnapshot().elapsed
            let displayActiveLine = activeLineID(for: displayTime) ?? activeLine
            focusedLyricsScroll(activeLine: displayActiveLine, currentTime: displayTime)
        }
    }

    private func focusedLyricsScroll(activeLine displayActiveLine: Int, currentTime: TimeInterval) -> some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<lines.count, id: \.self) { idx in
                            let line = lines[idx]
                            let isActive = isLineActive(line, displayActiveLine: displayActiveLine)
                            let d = isActive ? 0 : abs(line.id - displayActiveLine)
                            lyricText(
                                for: line,
                                isActive: isActive,
                                font: isActive
                                    ? .system(size: 28, weight: .bold)
                                    : .system(size: 18, weight: .semibold),
                                opacity: opacityFor(d),
                                currentTime: currentTime,
                                lineEndTime: lineEndTime(after: idx)
                            )
                                .multilineTextAlignment(textAlignment(for: line))
                                .frame(maxWidth: .infinity, alignment: frameAlignment(for: line))
                                .padding(.bottom, isActive ? 22 : 12)
                                .contentShape(Rectangle())
                                // tap a synced line to seek playback to that timestamp
                                .onTapGesture {
                                    let t = line.time
                                    guard t >= 0 else { return }
                                    audio.seek(to: t)
                                    activeLine = line.id
                                }
                                .id(line.id)
                        }
                        Color.clear.frame(height: bottomScrollClearance(for: geo.size.height))
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }
                .onChangeCompat(of: displayActiveLine) { _, l in
                    if activeLine != l { activeLine = l }
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                        proxy.scrollTo(max(0, l - 1), anchor: .top)
                    }
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
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(lines) { line in
                            let isActive = isLineActive(line, displayActiveLine: activeLine)
                            let d = abs(line.id - activeLine)
                            let opacity = isSynced ? opacityFor(d) : 1.0
                            lyricText(
                                for: line,
                                isActive: isActive,
                                font: isActive ? .system(size: 28, weight: .bold) : .system(size: 18, weight: .semibold),
                                opacity: opacity
                            )
                                .multilineTextAlignment(textAlignment(for: line))
                                .frame(maxWidth: .infinity, alignment: frameAlignment(for: line))
                                .padding(.horizontal, 24)
                                .padding(.bottom, isActive ? 22 : 12)
                                .id(line.id)
                                .animation(.easeInOut(duration: 0.35), value: isActive)
                        }
                        Color.clear.frame(height: bottomScrollClearance(for: geo.size.height))
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
    }

    private func bottomScrollClearance(for viewportHeight: CGFloat) -> CGFloat {
        max(180, viewportHeight * 0.65)
    }

    private func opacityFor(_ d: Int) -> Double {
        switch d { case 0: 1.0; case 1: 0.74; case 2: 0.56; default: 0.4 }
    }

    private func displayText(for line: LyricLine) -> String {
        let text = isShowingTranslation ? (translatedTexts[line.id] ?? line.text) : line.text
        return text.isEmpty ? " " : text
    }

    @ViewBuilder
    private func lyricText(
        for line: LyricLine,
        isActive: Bool,
        font: Font,
        opacity: Double,
        currentTime: TimeInterval? = nil,
        lineEndTime: TimeInterval? = nil
    ) -> some View {
        if isSynced,
           isActive,
           !isShowingTranslation,
           let cues = line.cues,
           !cues.isEmpty {
            KaraokeLyricText(
                line: line,
                cues: cues,
                currentTime: currentTime ?? audio.playbackTimeSnapshot().elapsed,
                lineEndTime: lineEndTime,
                isTrailing: line.vocalLane == .other
            )
                .font(font)
        } else {
            Text(displayText(for: line))
                .font(font)
                .foregroundStyle(lyricColor(isActive: isActive, opacity: opacity))
        }
    }

    private func lyricColor(isActive: Bool, opacity: Double) -> Color {
        guard isSynced else { return .white.opacity(opacity) }
        if isActive { return .white }
        return .gray.opacity(opacity)
    }

    private func frameAlignment(for line: LyricLine) -> Alignment {
        line.vocalLane == .other ? .trailing : .leading
    }

    private func textAlignment(for line: LyricLine) -> TextAlignment {
        line.vocalLane == .other ? .trailing : .leading
    }

    private func lineEndTime(after index: Int) -> TimeInterval? {
        guard lines.indices.contains(index), lines[index].time >= 0 else { return nil }
        let current = lines[index].time
        return lines[(index + 1)...].first { $0.time > current + 0.001 }?.time
    }

    private func activeLineID(for time: TimeInterval) -> Int? {
        guard isSynced else { return nil }
        if let idx = lines.lastIndex(where: { $0.time <= time }) {
            let activeTime = lines[idx].time
            return lines.first(where: { abs($0.time - activeTime) <= 0.001 })?.id ?? lines[idx].id
        }
        return lines.first?.id
    }

    private func isLineActive(_ line: LyricLine, displayActiveLine: Int) -> Bool {
        guard isSynced else { return line.id == displayActiveLine }
        guard let activeTime = lines.first(where: { $0.id == displayActiveLine })?.time else {
            return line.id == displayActiveLine
        }
        return abs(line.time - activeTime) <= 0.001
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
                    .foregroundStyle(isShowingTranslation ? .white : .white.opacity(0.78))
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
        if let id = activeLineID(for: time), id != activeLine {
            activeLine = id
        }
    }
}

private struct KaraokeLyricText: View {
    let line: LyricLine
    let cues: [LyricCue]
    let currentTime: TimeInterval
    let lineEndTime: TimeInterval?
    let isTrailing: Bool

    var body: some View {
        let text = line.text.isEmpty ? " " : line.text
        KaraokeLineLayout(isTrailing: isTrailing) {
            ForEach(segments) { segment in
                KaraokeLyricSegmentView(segment: segment)
                    .fixedSize(horizontal: true, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private var segments: [KaraokeLyricSegment] {
        let textByteCount = line.text.utf8.count
        guard textByteCount > 0 else {
            return [KaraokeLyricSegment(id: 0, text: " ", progress: 1)]
        }

        let ordered = cues
            .filter { $0.byteStart >= 0 && $0.byteEnd >= $0.byteStart && $0.byteEnd < textByteCount }
            .sorted { $0.byteStart == $1.byteStart ? $0.start < $1.start : $0.byteStart < $1.byteStart }
        guard !ordered.isEmpty else {
            return [KaraokeLyricSegment(
                id: 0,
                text: line.text,
                progress: currentTime >= line.time ? 1 : 0
            )]
        }

        var output: [KaraokeLyricSegment] = []
        var cursor = line.text.startIndex

        for index in ordered.indices {
            let cue = ordered[index]
            guard let range = stringRange(in: line.text, byteStart: cue.byteStart, byteEnd: cue.byteEnd),
                  range.lowerBound >= cursor else {
                continue
            }

            if cursor < range.lowerBound {
                output.append(KaraokeLyricSegment(
                    id: output.count,
                    text: String(line.text[cursor..<range.lowerBound]),
                    progress: currentTime >= cue.start ? 1 : 0
                ))
            }

            output.append(KaraokeLyricSegment(
                id: output.count,
                text: String(line.text[range]),
                progress: cueProgress(at: index, in: ordered)
            ))
            cursor = range.upperBound
        }

        if cursor < line.text.endIndex {
            let endProgress = ordered.last.map { currentTime >= cueEnd(for: $0, fallback: $0.start + 0.45) ? 1.0 : 0.0 } ?? 0
            output.append(KaraokeLyricSegment(
                id: output.count,
                text: String(line.text[cursor..<line.text.endIndex]),
                progress: endProgress
            ))
        }

        return output.isEmpty
            ? [KaraokeLyricSegment(
                id: 0,
                text: line.text,
                progress: currentTime >= line.time ? 1 : 0
            )]
            : output
    }

    private func cueProgress(at index: Int, in cues: [LyricCue]) -> CGFloat {
        let cue = cues[index]
        if currentTime < cue.start { return 0 }
        let end = cueEnd(at: index, in: cues)
        if currentTime >= end { return 1 }
        let duration = max(0.08, end - cue.start)
        let rawProgress = (currentTime - cue.start) / duration
        return CGFloat(smoothstep(clamp(rawProgress)))
    }

    private func cueEnd(at index: Int, in cues: [LyricCue]) -> TimeInterval {
        let cue = cues[index]
        let fallback = cue.start + 0.45
        if let end = cue.end, end > cue.start { return end }
        let nextIndex = index + 1
        if cues.indices.contains(nextIndex), cues[nextIndex].start > cue.start {
            return cues[nextIndex].start
        }
        if let lineEndTime, lineEndTime > cue.start {
            return min(lineEndTime, cue.start + 0.6)
        }
        return fallback
    }

    private func cueEnd(for cue: LyricCue, fallback: TimeInterval) -> TimeInterval {
        if let end = cue.end, end > cue.start { return end }
        return fallback
    }

    private func stringRange(in text: String, byteStart: Int, byteEnd: Int) -> Range<String.Index>? {
        guard byteStart >= 0, byteEnd >= byteStart, byteEnd < text.utf8.count else { return nil }
        let lowerUTF8 = text.utf8.index(text.utf8.startIndex, offsetBy: byteStart)
        let upperUTF8 = text.utf8.index(text.utf8.startIndex, offsetBy: byteEnd + 1)
        guard let lower = String.Index(lowerUTF8, within: text),
              let upper = String.Index(upperUTF8, within: text) else {
            return nil
        }
        return lower..<upper
    }

    private func smoothstep(_ value: Double) -> Double {
        value * value * (3 - (2 * value))
    }

    private func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

private struct KaraokeLyricSegment: Identifiable {
    let id: Int
    let text: String
    let progress: CGFloat
}

private struct KaraokeLyricSegmentView: View {
    let segment: KaraokeLyricSegment

    var body: some View {
        ZStack(alignment: .leading) {
            Text(segment.text)
                .foregroundStyle(.gray.opacity(0.78))
            Text(segment.text)
                .foregroundStyle(.white)
                .mask {
                    GeometryReader { proxy in
                        HStack(spacing: 0) {
                            Rectangle()
                                .frame(width: proxy.size.width * segment.progress)
                            Spacer(minLength: 0)
                        }
                    }
                }
        }
    }
}

private struct KaraokeLineLayout: Layout {
    let isTrailing: Bool

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? subviews.reduce(CGFloat.zero) {
            $0 + $1.sizeThatFits(.unspecified).width
        }
        let lines = lineMetrics(for: subviews, maxWidth: max(1, maxWidth))
        return CGSize(
            width: proposal.width ?? lines.map(\.width).max() ?? 0,
            height: lines.reduce(CGFloat.zero) { $0 + $1.height }
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let lines = lineMetrics(for: subviews, maxWidth: max(1, bounds.width))
        var y = bounds.minY
        for line in lines {
            var x = isTrailing ? bounds.maxX - line.width : bounds.minX
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + ((line.height - size.height) / 2)),
                    proposal: ProposedViewSize(size)
                )
                x += size.width
            }
            y += line.height
        }
    }

    private func lineMetrics(for subviews: Subviews, maxWidth: CGFloat) -> [KaraokeLineMetric] {
        var lines: [KaraokeLineMetric] = []
        var current = KaraokeLineMetric(indices: [], width: 0, height: 0)

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let shouldWrap = !current.indices.isEmpty && current.width + size.width > maxWidth
            if shouldWrap {
                lines.append(current)
                current = KaraokeLineMetric(indices: [], width: 0, height: 0)
            }
            current.indices.append(index)
            current.width += size.width
            current.height = max(current.height, size.height)
        }

        if !current.indices.isEmpty {
            lines.append(current)
        }
        return lines
    }
}

private struct KaraokeLineMetric {
    var indices: [Int]
    var width: CGFloat
    var height: CGFloat
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
