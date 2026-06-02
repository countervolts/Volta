import SwiftUI
import AVKit
import AVFoundation
import MediaPlayer

enum PlayerTab { case nowPlaying, queue, lyrics }

struct NowPlayingScreen: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool
    @State private var activeTab: PlayerTab = .nowPlaying
    @State private var dragOffset: CGFloat = 0
    @State private var showSongInfo = false
    @State private var artistToShow: Artist?
    @State private var albumToShow: Album?
    @State private var isFetchingArtist = false
    @State private var isFetchingAlbum = false
    @AppStorage("showLosslessBadge") private var showLosslessBadge = true
    @AppStorage("artworkAnimation") private var artworkAnimation = true
    // observe accent so player controls retint live on change
    @AppStorage("accentColorName") private var accentColorName = "purple"

    // skip/prev nudge animation
    @State private var skipNudge: CGFloat = 0
    @State private var prevNudge: CGFloat = 0

    private var audio: AudioPlayer { appState.audioPlayer }

    private var bg: Color {
        if let image = audio.currentArtwork {
            return ColorExtractor.backgroundSwiftUI(from: image)
        }
        return Color(white: 0.08)
    }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
                .animation(.easeInOut(duration: 0.6), value: audio.currentSong?.id)

            VStack(spacing: 0) {
                dragHandle
                tabContent
                Spacer(minLength: 0).frame(maxHeight: 40)
                controls
            }
        }
        .gesture(
            DragGesture()
                .onChanged { v in dragOffset = max(0, v.translation.height) }
                .onEnded { v in
                    if v.translation.height > 120 || v.predictedEndTranslation.height > 300 {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            isPresented = false
                        }
                    }
                    withAnimation { dragOffset = 0 }
                }
        )
        .offset(y: dragOffset)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.9), value: dragOffset)
        .sheet(isPresented: $showSongInfo) {
            SongInfoSheet(song: audio.currentSong)
        }
        .sheet(item: $albumToShow) { album in
            NavigationStack {
                AlbumDetailView(album: album)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { albumToShow = nil }
                                .foregroundStyle(Theme.accent)
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
        .sheet(item: $artistToShow) { artist in
            NavigationStack {
                ArtistDetailView(artist: artist)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { artistToShow = nil }
                                .foregroundStyle(Theme.accent)
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Drag handle

    private var dragHandle: some View {
        Capsule()
            .fill(.white.opacity(0.3))
            .frame(width: 36, height: 4)
            .padding(.top, 12)
            .padding(.bottom, 8)
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .nowPlaying:
            nowPlayingContent
        case .queue:
            altContent { QueueView().transition(.opacity) }
        case .lyrics:
            altContent { LyricsViewWithState().transition(.opacity) }
        }
    }

    // compact artwork+title+artist at top, content in middle, full scrubber at bottom
    private func altContent<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) {
            compactTrackHeader
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 8)

            content()
                .frame(maxHeight: .infinity)

            scrubber
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 4)
        }
    }

    private var compactTrackHeader: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { activeTab = .nowPlaying }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(white: 0.15))
                    if let image = audio.currentArtwork {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(audio.currentSong?.title ?? " ")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Button {
                    guard let song = audio.currentSong, let artistId = song.artistId else { return }
                    guard !isFetchingArtist else { return }
                    isFetchingArtist = true
                    Task {
                        defer { isFetchingArtist = false }
                        artistToShow = try? await appState.client?.artist(id: artistId)
                    }
                } label: {
                    Text(audio.currentSong?.artist ?? " ")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(isFetchingArtist ? 0.35 : 0.65))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(audio.currentSong?.artistId == nil)
            }
            Spacer()
            HStack(spacing: 4) {
                Button {
                    if let id = audio.currentSong?.id { audio.toggleStar(songID: id) }
                } label: {
                    Image(systemName: audio.currentSong.map { audio.isStarred($0.id) } == true
                          ? Symbols.star : Symbols.starEmpty)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(audio.currentSong.map { audio.isStarred($0.id) } == true
                                         ? .yellow : .white.opacity(0.6))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.3, dampingFraction: 0.6),
                           value: audio.currentSong.map { audio.isStarred($0.id) })

                Menu {
                    Button {
                        if let s = audio.currentSong { audio.playNext(s) }
                    } label: {
                        Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                    Button {
                        if let s = audio.currentSong { audio.addToQueue(s) }
                    } label: {
                        Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward")
                    }
                    Divider()
                    Button { showSongInfo = true } label: { Label("Info", systemImage: Symbols.info) }
                    Button { showSongInfo = true } label: { Label("View Credits", systemImage: "list.star") }
                    if audio.currentSong?.albumId != nil {
                        Button {
                            guard let albumId = audio.currentSong?.albumId else { return }
                            Task { albumToShow = try? await appState.client?.album(id: albumId) }
                        } label: { Label("Go to Album", systemImage: "square.stack") }
                    }
                    if audio.currentSong?.artistId != nil {
                        Button {
                            guard let artistId = audio.currentSong?.artistId, !isFetchingArtist else { return }
                            isFetchingArtist = true
                            Task {
                                defer { isFetchingArtist = false }
                                artistToShow = try? await appState.client?.artist(id: artistId)
                            }
                        } label: { Label("Go to Artist", systemImage: "person.fill") }
                    }
                } label: {
                    Image(systemName: Symbols.more)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Now playing content (artwork + track info + scrubber)

    private var nowPlayingContent: some View {
        VStack(spacing: 0) {
            artworkView
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 42)

            trackInfo
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

            scrubber
                .padding(.horizontal, 24)
                .padding(.bottom, 4)
        }
    }

    private var artworkView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(white: 0.12))
                .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
            if let image = audio.currentArtwork {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: Symbols.albumPlaceholder)
                    .font(.system(size: 60, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .aspectRatio(1, contentMode: .fit)
        .scaleEffect(artworkAnimation ? (audio.isPlaying ? 1.0 : 0.88) : 1.0)
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: audio.isPlaying)
        .id(audio.currentSong?.id)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.92).combined(with: .opacity),
            removal: .scale(scale: 0.92).combined(with: .opacity)
        ))
    }

    private var isLossless: Bool {
        guard let s = audio.currentSong?.suffix?.lowercased() else { return false }
        return ["flac", "wav", "aiff", "aif", "alac", "ape", "wv", "tta"].contains(s)
    }

    private var trackInfo: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(audio.currentSong?.title ?? " ")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Button {
                    guard let song = audio.currentSong, let artistId = song.artistId else { return }
                    guard !isFetchingArtist else { return }
                    isFetchingArtist = true
                    Task {
                        defer { isFetchingArtist = false }
                        artistToShow = try? await appState.client?.artist(id: artistId)
                    }
                } label: {
                    Text(audio.currentSong?.artist ?? " ")
                        .font(.body)
                        .foregroundStyle(.white.opacity(isFetchingArtist ? 0.35 : 0.65))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(audio.currentSong?.artistId == nil)
            }
            Spacer()
            HStack(spacing: 4) {
                Button {
                    if let id = audio.currentSong?.id { audio.toggleStar(songID: id) }
                } label: {
                    Image(systemName: audio.currentSong.map { audio.isStarred($0.id) } == true
                          ? Symbols.star : Symbols.starEmpty)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(audio.currentSong.map { audio.isStarred($0.id) } == true
                                         ? .yellow : .white.opacity(0.6))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.3, dampingFraction: 0.6),
                           value: audio.currentSong.map { audio.isStarred($0.id) })

                Menu {
                    Button {
                        if let s = audio.currentSong { audio.playNext(s) }
                    } label: {
                        Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                    Button {
                        if let s = audio.currentSong { audio.addToQueue(s) }
                    } label: {
                        Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward")
                    }
                    Divider()
                    Button { showSongInfo = true } label: { Label("Info", systemImage: Symbols.info) }
                    Button { showSongInfo = true } label: { Label("View Credits", systemImage: "list.star") }
                    Divider()
                    if audio.currentSong?.albumId != nil {
                        Button {
                            guard let albumId = audio.currentSong?.albumId, !isFetchingAlbum else { return }
                            isFetchingAlbum = true
                            Task {
                                defer { isFetchingAlbum = false }
                                albumToShow = try? await appState.client?.album(id: albumId)
                            }
                        } label: { Label("Go to Album", systemImage: "square.stack") }
                    }
                    if audio.currentSong?.artistId != nil {
                        Button {
                            guard let artistId = audio.currentSong?.artistId, !isFetchingArtist else { return }
                            isFetchingArtist = true
                            Task {
                                defer { isFetchingArtist = false }
                                artistToShow = try? await appState.client?.artist(id: artistId)
                            }
                        } label: { Label("Go to Artist", systemImage: "person.fill") }
                    }
                } label: {
                    Image(systemName: Symbols.more)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Scrubber

    private var scrubber: some View {
        VStack(spacing: 6) {
            ScrubBar(
                currentTime: audio.currentTime,
                duration: audio.duration,
                onSeek: { audio.seek(to: $0) }
            )
            HStack {
                Text(formatTime(audio.currentTime))
                    .monospacedDigit()
                Spacer()
                if isLossless && showLosslessBadge {
                    Label("Lossless", systemImage: "waveform")
                        .font(.caption2.bold())
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.15), in: Capsule())
                }
                Spacer()
                Text("-\(formatTime(max(0, audio.duration - audio.currentTime)))")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Playback controls

    private var controls: some View {
        VStack(spacing: 0) {
            // transport: prev | play/pause | next
            HStack(spacing: 0) {
                Spacer()

                Button {
                    animatePrev()
                    audio.skipPrevious()
                } label: {
                    Image(systemName: Symbols.previous)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 68, height: 68)
                        .offset(x: prevNudge)
                }
                .buttonStyle(.plain)

                Spacer()

                Button { audio.togglePlayPause() } label: {
                    Image(systemName: audio.isPlaying ? Symbols.pause : Symbols.play)
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 84, height: 84)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: audio.isPlaying)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    animateSkip()
                    audio.skipNext()
                } label: {
                    Image(systemName: Symbols.next)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 68, height: 68)
                        .offset(x: skipNudge)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.bottom, 8)

            // volume (native MPVolumeView — actually controls device volume)
            HStack(spacing: 10) {
                Image(systemName: Symbols.volumeLow)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                SystemVolumeSlider()
                    .frame(height: 20)
                Image(systemName: Symbols.volumeHigh)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            // bottom bar: lyrics | airplay | queue — equal thirds
            HStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeTab = activeTab == .lyrics ? .nowPlaying : .lyrics
                    }
                } label: {
                    Image(systemName: activeTab == .lyrics ? Symbols.lyrics : Symbols.lyricsInactive)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(activeTab == .lyrics ? Theme.accent : .white.opacity(0.6))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

                AirPlayButton()
                    .frame(width: 44, height: 44)
                    .frame(maxWidth: .infinity)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeTab = activeTab == .queue ? .nowPlaying : .queue
                    }
                } label: {
                    Image(systemName: Symbols.queue)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(activeTab == .queue ? Theme.accent : .white.opacity(0.6))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Skip animations

    private func animateSkip() {
        withAnimation(.easeOut(duration: 0.1)) { skipNudge = 14 }
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { skipNudge = 0 }
        }
    }

    private func animatePrev() {
        withAnimation(.easeOut(duration: 0.1)) { prevNudge = -14 }
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { prevNudge = 0 }
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Scrub bar (larger track for Apple Music feel)

private struct ScrubBar: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var isDragging = false
    @State private var dragValue: TimeInterval = 0

    private var displayTime: TimeInterval { isDragging ? dragValue : currentTime }
    private var progress: Double { duration > 0 ? displayTime / duration : 0 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2)).frame(height: 5)
                Capsule()
                    .fill(.white)
                    .frame(width: max(0, geo.size.width * CGFloat(progress)), height: 5)
                    .animation(.linear(duration: isDragging ? 0 : 0.5), value: progress)
                // thumb shown only while scrubbing — no height change prevents parent-drag interference
                if isDragging {
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .offset(x: max(0, geo.size.width * CGFloat(progress) - 7))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                // minimumDistance > 0 so parent vertical swipe doesn't activate scrubber
                DragGesture(minimumDistance: 4)
                    .onChanged { v in
                        isDragging = true
                        dragValue = max(0, min(duration, Double(v.location.x / geo.size.width) * duration))
                    }
                    .onEnded { v in
                        onSeek(dragValue)
                        isDragging = false
                    }
            )
        }
        .frame(height: 24)
    }
}

// MARK: - System volume (MPVolumeView — actually sets device volume)

private struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView()
        v.tintColor = .white
        let blank = UIImage()
        v.setVolumeThumbImage(blank, for: .normal)
        v.setVolumeThumbImage(blank, for: .highlighted)
        return v
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

// MARK: - AirPlay button

private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = UIColor.white.withAlphaComponent(0.6)
        v.activeTintColor = .white
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// MARK: - Song info sheet

struct SongInfoSheet: View {
    let song: Song?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let song {
                    row("Title", song.title)
                    row("Artist", song.artist)
                    row("Album", song.album)
                    row("Year", song.year.map(String.init))
                    row("Genre", song.genre)
                    row("Duration", song.duration.map { "\($0 / 60):\(String(format: "%02d", $0 % 60))" })
                    row("Bit Rate", song.bitRate.map { "\($0) kbps" })
                    row("Format", song.contentType)
                    row("File Type", song.suffix?.uppercased())
                    row("File Size", song.size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) })
                }
            }
            .navigationTitle("Song Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value { LabeledContent(label, value: value) }
    }
}
