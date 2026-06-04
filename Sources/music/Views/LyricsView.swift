import SwiftUI

struct LyricsViewWithState: View {
    @Environment(AppState.self) private var appState
    @State private var lines: [LyricLine] = []
    @State private var isLoading = false
    @State private var activeLine: Int = 0

    private var audio: AudioPlayer { appState.audioPlayer }
    private var isSynced: Bool { lines.first.map { $0.time >= 0 } ?? false }

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
        .task(id: audio.currentSong?.id) { await loadLyrics() }
        .onChange(of: audio.currentTime) { _, t in updateActiveLine(for: t) }
    }

    // MARK: - Focused view (synced lyrics)

    private var focusedLyricsView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<lines.count, id: \.self) { idx in
                        let d = abs(idx - activeLine)
                        let isActive = d == 0
                        Text(lines[idx].text.isEmpty ? " " : lines[idx].text)
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
            .onChange(of: activeLine) { _, l in
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
            Text("No lyrics available").font(.subheadline).foregroundStyle(.white.opacity(0.4))
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
                        Text(line.text.isEmpty ? " " : line.text)
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
            .onChange(of: activeLine) { _, l in
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    proxy.scrollTo(max(0, l - 1), anchor: .top)
                }
            }
        }
    }

    private func opacityFor(_ d: Int) -> Double {
        switch d { case 0: 1.0; case 1: 0.4; case 2: 0.2; default: 0.1 }
    }

    // MARK: - Data loading

    private func loadLyrics() async {
        guard let song = audio.currentSong, let client = appState.client else {
            lines = []; return
        }
        isLoading = true
        defer { isLoading = false }
        lines = await LyricsService.shared.lyrics(for: song, client: client)
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
