import SwiftUI
import AVKit
import AVFoundation
import MediaPlayer
import UIKit

enum PlayerTab { case nowPlaying, queue, lyrics }

struct NowPlayingScreen: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool
    @State private var activeTab: PlayerTab = .nowPlaying
    @State private var dragOffset: CGFloat = 0
    @State private var pendingDragOffset: CGFloat = 0
    @State private var dragThrottler: VSyncThrottler?
    @State private var infoSheet: SongMenuSheet? = nil
    @State private var showLosslessInfo = false
    @State private var showAudioSignalPath = false
    @State private var showVisualizer = false
    // Shared scrub state for bar and time labels.
    @State private var scrubbing = false
    @State private var scrubTime: TimeInterval = 0
    @State private var isAdjustingVolume = false
    @State private var artistToShow: Artist?
    @State private var albumToShow: Album?
    @State private var isFetchingArtist = false
    @State private var isFetchingAlbum = false
    @State private var tasteStore = TasteStore.shared
    @AppStorage("showLosslessBadge") private var showLosslessBadge = true
    @AppStorage(DeveloperExperiments.preciseTimestampsKey) private var preciseTimestamps = false
    @AppStorage("artworkAnimation") private var artworkAnimation = true
    @AppStorage("dynamicBackground") private var dynamicBackground = true
    // present a normal (static) cover with the same edge-to-edge, gradient-fade
    // look animated covers get
    @AppStorage("stylizedPlayerCover") private var stylizedPlayerCover = false
    // observe accent so player controls retint live on change
    @AppStorage("accentColorName") private var accentColorName = "purple"

    // skip/prev nudge animation
    @State private var skipNudge: CGFloat = 0
    @State private var prevNudge: CGFloat = 0
    @State private var playerBackground = Color(white: 0.08)
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var audio: AudioPlayer { appState.audioPlayer }
    private var currentTaste: TasteState {
        audio.currentSong.map { tasteStore.state(for: $0.id) } ?? .neutral
    }

    var body: some View {
        ZStack {
            playerBackground.ignoresSafeArea()

            if sizeClass == .regular {
                iPadLayout
            } else {
                phoneLayout
            }
        }
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged { v in
                    pendingDragOffset = max(0, v.translation.height)
                    if let dragThrottler {
                        dragThrottler.schedule()
                    } else {
                        dragOffset = pendingDragOffset
                    }
                }
                .onEnded { v in
                    if v.translation.height > 120 || v.predictedEndTranslation.height > 300 {
                        AppLogger.shared.log(
                            "Player dismissed by drag; translation=\(Int(v.translation.height)); predicted=\(Int(v.predictedEndTranslation.height))",
                            category: .playback
                        )
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            isPresented = false
                        }
                    }
                    pendingDragOffset = 0
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { dragOffset = 0 }
                }
        )
        // Track the finger directly; only release gets the spring.
        .offset(y: dragOffset)
        .sheet(item: $infoSheet) { which in
            switch which {
            case .info:    SongInfoSheet(song: audio.currentSong)
            case .credits: SongCreditsSheet(song: audio.currentSong)
            }
        }
        .sheet(isPresented: $showAudioSignalPath) {
            AudioSignalPathSheet(song: audio.currentSong)
        }
        .fullScreenCover(isPresented: $showVisualizer) {
            AudioVisualizerScreen(audio: audio)
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
            .preferredColorScheme(Theme.colorScheme)
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
            .preferredColorScheme(Theme.colorScheme)
        }
        .onAppear {
            AppLogger.shared.log(
                "Full player appeared; songID=\(audio.currentSong?.id ?? "none"); liveArtwork=\(audio.currentLiveArtwork != nil)",
                category: .playback
            )
            dragThrottler = VSyncThrottler {
                dragOffset = pendingDragOffset
            }
            refreshPlayerBackground(animated: false)
        }
        .onDisappear {
            AppLogger.shared.log("Full player disappeared", category: .playback)
            dragThrottler?.invalidate()
            dragThrottler = nil
        }
        .onChange(of: audio.currentSong?.id) { _, _ in
            refreshPlayerBackground(animated: true)
        }
        .onChange(of: audio.currentArtwork == nil) { _, _ in
            refreshPlayerBackground(animated: true)
        }
        .onChange(of: dynamicBackground) { _, _ in
            refreshPlayerBackground(animated: true)
        }
        .preferredColorScheme(Theme.colorScheme)
    }

    @ViewBuilder
    private var phoneLayout: some View {
        if usesFullBleedCover {
            fullBleedLayout()
        } else {
            VStack(spacing: 0) {
                dragHandle
                tabContent
                Spacer(minLength: 0)
                transportControls
                Spacer(minLength: 0)
                bottomControls
            }
        }
    }

    // Full-bleed artwork header for live/stylized covers.
    private var usesFullBleedCover: Bool {
        guard activeTab == .nowPlaying else { return false }
        if audio.currentLiveArtwork != nil { return true }
        return stylizedPlayerCover && audio.currentArtwork != nil
    }

    private func fullBleedLayout() -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let topInset = geo.safeAreaInsets.top
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    fullBleedCoverContent
                        .frame(width: w, height: w + topInset)
                        .clipped()
                        .overlay(alignment: .bottom) {
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: playerBackground.opacity(0.55), location: 0.72),
                                    .init(color: playerBackground, location: 1)
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                            .frame(height: w * 0.30)
                        }
                        .id(audio.currentSong?.id)
                    // the whole header is offset up by topInset, so doubling the
                    // inset puts the handle just below the status bar
                    dragHandle.padding(.top, topInset * 2)
                }
                .frame(width: w, height: w + topInset)
                .offset(y: -topInset)
                .padding(.bottom, -topInset)

                trackInfo
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 20)

                scrubber
                    .padding(.horizontal, 24)
                    .padding(.bottom, 4)

                Spacer(minLength: 0)
                transportControls
                Spacer(minLength: 0)
                bottomControls
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }

    @ViewBuilder
    private var iPadLayout: some View {
        if activeTab != .nowPlaying {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    dragHandle
                    nowPlayingContent
                    Spacer(minLength: 0)
                    transportControls
                    Spacer(minLength: 0)
                    bottomControls
                }
                .frame(width: 420)

                Rectangle()
                    .fill(.white.opacity(0.10))
                    .frame(width: 0.5)

                if activeTab == .lyrics {
                    LyricsViewWithState()
                        .frame(maxWidth: .infinity)
                } else {
                    QueueView()
                        .frame(maxWidth: .infinity)
                }
            }
            .transition(.opacity)
        } else {
            VStack(spacing: 0) {
                dragHandle
                nowPlayingContent
                Spacer(minLength: 0)
                transportControls
                Spacer(minLength: 0)
                bottomControls
            }
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity, alignment: .center)
            .transition(.opacity)
        }
    }

    // MARK: - Share / sleep helpers

    private func shareCurrentSong() {
        guard let song = audio.currentSong else { return }
        Task {
            if let url = await SongLinkService.pageURL(for: song) {
                ShareSheet.present([url])
            }
        }
    }

    @ViewBuilder
    private var sleepTimerMenu: some View {
        Menu {
            if audio.sleepTimerActive {
                Button(role: .destructive) { audio.cancelSleepTimer() } label: {
                    Label(audio.sleepEndsAtTrackEnd ? "Cancel (end of track)" : "Cancel Timer",
                          systemImage: "xmark.circle")
                }
                Divider()
            }
            ForEach([5, 15, 30, 45, 60], id: \.self) { m in
                Button("\(m) minutes") { audio.startSleepTimer(minutes: m) }
            }
            Button("End of Track") { audio.startSleepTimerEndOfTrack() }
        } label: {
            Image(systemName: audio.sleepTimerActive ? "moon.fill" : "moon.zzz")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(audio.sleepTimerActive ? Theme.accent : .white.opacity(0.6))
                .frame(width: 44, height: 44)
        }
        .frame(maxWidth: .infinity)
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
                        if let s = audio.currentSong { tasteStore.toggleLove(s.id) }
                    } label: {
                        Label(currentTaste == .loved ? L(.action_unlove) : L(.action_love),
                              systemImage: currentTaste == .loved ? "heart.fill" : "heart")
                    }
                    Button {
                        if let s = audio.currentSong { tasteStore.toggleDislike(s.id) }
                    } label: {
                        Label(currentTaste == .disliked ? L(.action_remove_dislike) : L(.action_dislike),
                              systemImage: currentTaste == .disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    }
                    Divider()
                    Button {
                        if let s = audio.currentSong { audio.playNext(s) }
                    } label: {
                        Label(L(.action_play_next), systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                    Button {
                        if let s = audio.currentSong { audio.addToQueue(s) }
                    } label: {
                        Label(L(.action_play_last), systemImage: "text.line.last.and.arrowtriangle.forward")
                    }
                    Divider()
                    Button { infoSheet = .info } label: { Label(L(.action_info), systemImage: Symbols.info) }
                    Button { infoSheet = .credits } label: { Label(L(.action_view_credits), systemImage: "list.star") }
                    Button { shareCurrentSong() } label: { Label(L(.action_share), systemImage: Symbols.share) }
                    if audio.currentSong?.albumId != nil {
                        Button {
                            guard let albumId = audio.currentSong?.albumId else { return }
                            Task { albumToShow = try? await appState.client?.album(id: albumId) }
                        } label: { Label(L(.action_go_to_album), systemImage: "square.stack") }
                    }
                    if audio.currentSong?.artistId != nil {
                        Button {
                            guard let artistId = audio.currentSong?.artistId, !isFetchingArtist else { return }
                            isFetchingArtist = true
                            Task {
                                defer { isFetchingArtist = false }
                                artistToShow = try? await appState.client?.artist(id: artistId)
                            }
                        } label: { Label(L(.action_go_to_artist), systemImage: "person.fill") }
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
            if let live = audio.currentLiveArtwork {
                // Full-player live artwork.
                liveArtworkView(live)
            } else if let image = audio.currentArtwork {
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
        .scaleEffect((artworkAnimation && !PerformanceMode.reduceAnimations) ? (audio.isPlaying ? 1.0 : 0.88) : 1.0)
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: audio.isPlaying)
        .id(audio.currentSong?.id)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.92).combined(with: .opacity),
            removal: .scale(scale: 0.92).combined(with: .opacity)
        ))
    }

    @ViewBuilder
    private func liveArtworkView(_ live: LiveArtworkAsset) -> some View {
        AnimatedImageView(image: live.animatedImage)
    }

    // header artwork for the full-bleed layout: the animated cover if present,
    // otherwise the static cover (stylized-cover option) presented the same way
    @ViewBuilder
    private var fullBleedCoverContent: some View {
        if let live = audio.currentLiveArtwork {
            liveArtworkView(live)
        } else if let image = audio.currentArtwork {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
    }

    private var trackInfo: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                if audio.isMixing && audio.transitionMode == .automix {
                    HStack(spacing: 5) {
                        Image(systemName: "waveform.path")
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                        Text("Mixing")
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.accent.opacity(0.16)))
                    .transition(.opacity.combined(with: .scale))
                }
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
                        if let s = audio.currentSong { tasteStore.toggleLove(s.id) }
                    } label: {
                        Label(currentTaste == .loved ? L(.action_unlove) : L(.action_love),
                              systemImage: currentTaste == .loved ? "heart.fill" : "heart")
                    }
                    Button {
                        if let s = audio.currentSong { tasteStore.toggleDislike(s.id) }
                    } label: {
                        Label(currentTaste == .disliked ? L(.action_remove_dislike) : L(.action_dislike),
                              systemImage: currentTaste == .disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    }
                    Divider()
                    Button {
                        if let s = audio.currentSong { audio.playNext(s) }
                    } label: {
                        Label(L(.action_play_next), systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                    Button {
                        if let s = audio.currentSong { audio.addToQueue(s) }
                    } label: {
                        Label(L(.action_play_last), systemImage: "text.line.last.and.arrowtriangle.forward")
                    }
                    Divider()
                    Button { infoSheet = .info } label: { Label(L(.action_info), systemImage: Symbols.info) }
                    Button { infoSheet = .credits } label: { Label(L(.action_view_credits), systemImage: "list.star") }
                    Button { shareCurrentSong() } label: { Label(L(.action_share), systemImage: Symbols.share) }
                    Divider()
                    if audio.currentSong?.albumId != nil {
                        Button {
                            guard let albumId = audio.currentSong?.albumId, !isFetchingAlbum else { return }
                            isFetchingAlbum = true
                            Task {
                                defer { isFetchingAlbum = false }
                                albumToShow = try? await appState.client?.album(id: albumId)
                            }
                        } label: { Label(L(.action_go_to_album), systemImage: "square.stack") }
                    }
                    if audio.currentSong?.artistId != nil {
                        Button {
                            guard let artistId = audio.currentSong?.artistId, !isFetchingArtist else { return }
                            isFetchingArtist = true
                            Task {
                                defer { isFetchingArtist = false }
                                artistToShow = try? await appState.client?.artist(id: artistId)
                            }
                        } label: { Label(L(.action_go_to_artist), systemImage: "person.fill") }
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
        // One timeline and one player snapshot drive the fill and both labels.
        // Keeping the sample atomic prevents each view from landing on a different
        // player tick, especially when precise timestamps are enabled.
        TimelineView(
            .animation(
                minimumInterval: preciseTimestamps ? 1.0 / 60.0 : 0.2,
                paused: scrubbing || !audio.isPlaying
            )
        ) { _ in
            let snapshot = audio.playbackTimeSnapshot()
            let total = snapshot.duration
            let t = scrubbing ? min(scrubTime, total) : snapshot.elapsed
            VStack(spacing: 6) {
                ScrubBar(
                    duration: total,
                    currentTime: t,
                    scrubbing: $scrubbing,
                    scrubTime: $scrubTime,
                    onSeek: { audio.seek(to: $0) }
                )
                let losslessStatus = LosslessBadgeResolver.status(for: audio.currentSong)
                HStack {
                    Text(formatTime(t))
                        .monospacedDigit()
                    Spacer()
                    if let losslessStatus, showLosslessBadge {
                        Button { showLosslessInfo = true } label: {
                            Label(losslessStatus.title, systemImage: losslessStatus.systemImage)
                                .font(.caption2.bold())
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.white.opacity(0.15), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showLosslessInfo) {
                            LosslessInfoPopover(song: audio.currentSong) {
                                showLosslessInfo = false
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 180_000_000)
                                    showAudioSignalPath = true
                                }
                            }
                                .presentationCompactAdaptation(.popover)
                        }
                    }
                    Spacer()
                    Text("-\(formatTime(max(0, total - t)))")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    // MARK: - Playback controls

    // Shared transport row.
    private var transportControls: some View {
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
    }

    // volume slider + bottom action bar, pinned below the centred transport row
    private var bottomControls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: Symbols.volumeLow)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                SystemVolumeSlider(isInteracting: $isAdjustingVolume)
                    .frame(height: 20)
                    .scaleEffect(x: 1, y: isAdjustingVolume ? 1.7 : 1, anchor: .center)
                    .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isAdjustingVolume)
                Image(systemName: Symbols.volumeHigh)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            // Equal thirds: lyrics, AirPlay, queue.
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

                OutputRouteButton()
                    .frame(width: 44, height: 44)
                    .frame(maxWidth: .infinity)

                Button {
                    showVisualizer = true
                } label: {
                    Image(systemName: Symbols.visualizer)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

                sleepTimerMenu

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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.65).delay(0.1)) { skipNudge = 0 }
    }

    private func animatePrev() {
        withAnimation(.easeOut(duration: 0.1)) { prevNudge = -14 }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.65).delay(0.1)) { prevNudge = 0 }
    }

    private func refreshPlayerBackground(animated: Bool) {
        guard dynamicBackground, !PerformanceMode.disableDynamicBackground else {
            let fallback = Color(white: 0.08)
            if animated {
                withAnimation(.easeInOut(duration: 0.2)) { playerBackground = fallback }
            } else {
                playerBackground = fallback
            }
            return
        }
        guard let image = audio.currentArtwork else { return }
        let next = ColorExtractor.backgroundSwiftUI(from: image)
        if animated {
            withAnimation(.easeInOut(duration: 0.55)) { playerBackground = next }
        } else {
            playerBackground = next
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return preciseTimestamps ? "0:00.0000" : "0:00" }
        if preciseTimestamps {
            let minutes = Int(t) / 60
            let seconds = t - Double(minutes * 60)
            // %07.4f keeps a leading zero on the seconds so it reads 0:05.1234
            return String(format: "%d:%07.4f", minutes, seconds)
        }
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct AudioVisualizerScreen: View {
    let audio: AudioPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !audio.isPlaying)) { timeline in
                Canvas { context, size in
                    drawVoltaVisual(context: &context, size: size, date: timeline.date)
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)

                Spacer()

                VStack(spacing: 8) {
                    Text(audio.currentSong?.title ?? "Not Playing")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(audio.currentSong?.artist ?? " ")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)

                HStack(spacing: 36) {
                    Button { audio.skipPrevious() } label: {
                        Image(systemName: Symbols.previous)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                    }
                    .buttonStyle(.plain)

                    Button { audio.togglePlayPause() } label: {
                        Image(systemName: audio.isPlaying ? Symbols.pause : Symbols.play)
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 78, height: 78)
                            .background(.white, in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button { audio.skipNext() } label: {
                        Image(systemName: Symbols.next)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 44)
            }
        }
        .preferredColorScheme(Theme.colorScheme)
    }

    private func drawVoltaVisual(context: inout GraphicsContext, size: CGSize, date: Date) {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.43)
        let side = min(size.width, size.height)
        let baseRadius = side * 0.18
        let liveTime = audio.liveTime()
        let clock = date.timeIntervalSinceReferenceDate + liveTime
        let seed = Double(abs(audio.currentSong?.id.hashValue ?? 13) % 997) / 97.0
        let energy = audio.isPlaying ? 1.0 : 0.18

        let glowRect = CGRect(x: center.x - side * 0.46, y: center.y - side * 0.46, width: side * 0.92, height: side * 0.92)
        context.fill(
            Path(ellipseIn: glowRect),
            with: .radialGradient(
                Gradient(colors: [Theme.accent.opacity(0.34 * energy), .clear]),
                center: center,
                startRadius: 0,
                endRadius: side * 0.46
            )
        )

        for ring in 0..<5 {
            let progress = Double(ring) / 4.0
            let pulse = 0.5 + 0.5 * sin(clock * (1.2 + progress) + seed + progress * 4.0)
            let radius = baseRadius + CGFloat(ring) * side * 0.052 + CGFloat(pulse * energy) * 18
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            let path = Path(ellipseIn: rect)
            let dash = [CGFloat(5 + ring * 3), CGFloat(8 + ring * 2)]
            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [Theme.accent.opacity(0.85), .white.opacity(0.55), .cyan.opacity(0.55)]),
                    startPoint: CGPoint(x: rect.minX, y: rect.minY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
                ),
                style: StrokeStyle(lineWidth: CGFloat(1.4 + progress * 2.2), lineCap: .round, dash: dash, dashPhase: CGFloat(clock * (18 + progress * 20)))
            )
        }

        let spokeCount = 72
        for i in 0..<spokeCount {
            let p = Double(i) / Double(spokeCount)
            let phase = clock * (1.6 + p * 2.0) + p * .pi * 8 + seed
            let wave = abs(sin(phase) * 0.6 + sin(phase * 0.37 + seed) * 0.4)
            let angle = p * .pi * 2 + clock * 0.18
            let inner = baseRadius * 0.82 + CGFloat(wave * 16 * energy)
            let outer = inner + CGFloat(18 + wave * 72 * energy)
            let a = CGFloat(angle)
            let p1 = CGPoint(x: center.x + cos(a) * inner, y: center.y + sin(a) * inner)
            let p2 = CGPoint(x: center.x + cos(a) * outer, y: center.y + sin(a) * outer)
            var path = Path()
            path.move(to: p1)
            path.addLine(to: p2)
            context.stroke(path, with: .color(.white.opacity(0.18 + wave * 0.72)), lineWidth: CGFloat(1.0 + wave * 2.4))
        }

        for i in 0..<18 {
            let p = Double(i) / 18.0
            let angle = clock * (0.35 + p * 0.18) + p * .pi * 2 + seed
            let radius = baseRadius * 1.55 + CGFloat(sin(clock + p * 5) * 20)
            let dot = CGPoint(x: center.x + cos(CGFloat(angle)) * radius, y: center.y + sin(CGFloat(angle)) * radius)
            let size = CGFloat(3 + (sin(clock * 2 + p * 8) + 1) * 3 * energy)
            context.fill(
                Path(ellipseIn: CGRect(x: dot.x - size / 2, y: dot.y - size / 2, width: size, height: size)),
                with: .color(Theme.accent.opacity(0.35 + 0.55 * energy))
            )
        }
    }
}

// MARK: - Scrub bar

private struct ScrubBar: View {
    let duration: TimeInterval
    let currentTime: TimeInterval
    @Binding var scrubbing: Bool
    @Binding var scrubTime: TimeInterval
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        GeometryReader { geo in
            let trackHeight: CGFloat = scrubbing ? 9 : 5
            let progress = duration > 0 ? min(1, max(0, currentTime / duration)) : 0
            let fillWidth = max(0, min(geo.size.width, geo.size.width * CGFloat(progress)))
            Capsule().fill(.white.opacity(0.2))
                .frame(width: geo.size.width, height: trackHeight)
                .overlay(alignment: .leading) {
                    // scrubber stays white regardless of accent colour
                    Capsule().fill(.white)
                        .frame(width: fillWidth, height: trackHeight)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                // minimumDistance > 0 so parent vertical swipe doesn't activate scrubber
                DragGesture(minimumDistance: 4)
                    .onChanged { v in
                        scrubbing = true
                        scrubTime = max(0, min(duration, Double(v.location.x / geo.size.width) * duration))
                    }
                    .onEnded { _ in
                        onSeek(scrubTime)
                        scrubbing = false
                    }
            )
        }
        .frame(height: 24)
    }
}

// MARK: - System volume (MPVolumeView)

private struct SystemVolumeSlider: UIViewRepresentable {
    @Binding var isInteracting: Bool

    final class SliderOnlyVolumeView: MPVolumeView {
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let slider = subviews.compactMap({ $0 as? UISlider }).first else { return }
            for subview in subviews where subview !== slider {
                subview.isHidden = true
                subview.frame = .zero
            }
            slider.isHidden = false
            slider.frame = bounds
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(isInteracting: $isInteracting) }

    func makeUIView(context: Context) -> SliderOnlyVolumeView {
        let v = SliderOnlyVolumeView()
        v.tintColor = .white
        let blank = UIImage()
        v.setVolumeThumbImage(blank, for: .normal)
        v.setVolumeThumbImage(blank, for: .highlighted)
        context.coordinator.volumeView = v
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.require(toFail: pan)
        v.addGestureRecognizer(pan)
        v.addGestureRecognizer(tap)
        return v
    }
    func updateUIView(_ uiView: SliderOnlyVolumeView, context: Context) {}

    final class Coordinator: NSObject {
        weak var volumeView: MPVolumeView?
        private var isInteracting: Binding<Bool>
        private var panStartVolume: Float = 0
        private var panActive = false

        init(isInteracting: Binding<Bool>) {
            self.isInteracting = isInteracting
        }

        private var slider: UISlider? {
            volumeView?.subviews.compactMap { $0 as? UISlider }.first
        }

        // Only the real slider track should catch taps.
        private func onTrack(_ point: CGPoint, _ slider: UISlider) -> Bool {
            point.x >= 0 && point.x <= slider.bounds.width
        }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let slider, slider.bounds.width > 0 else { return }
            let p = g.location(in: slider)
            guard onTrack(p, slider) else { return }   // tap off the track does nothing
            let frac = Float(max(0, min(1, p.x / slider.bounds.width)))
            isInteracting.wrappedValue = true
            slider.setValue(frac, animated: false)
            slider.sendActions(for: .valueChanged)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                self?.isInteracting.wrappedValue = false
            }
        }

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard let slider, slider.bounds.width > 0 else { return }
            switch g.state {
            case .began:
                panActive = onTrack(g.location(in: slider), slider)
                panStartVolume = slider.value
                isInteracting.wrappedValue = panActive
            case .changed:
                guard panActive else { return }
                let delta = Float(g.translation(in: slider).x / slider.bounds.width)
                let frac = max(0, min(1, panStartVolume + delta))
                slider.setValue(frac, animated: false)
                slider.sendActions(for: .valueChanged)
            default:
                panActive = false
                isInteracting.wrappedValue = false
                panStartVolume = slider.value
            }
        }
    }
}

// MARK: - Animated (live) artwork

// Plays the locally cached live-artwork mp4 on a muted, looping AVPlayerLayer.
// Hardware-decoded, so frame count/size don't matter (unlike UIImageView frame
// animation). The still frame sits behind the layer to cover the brief moment
// before the first video frame is ready.
private struct LiveArtworkVideoView: UIViewRepresentable {
    let url: URL
    let stillFrame: UIImage

    final class Coordinator {
        var url: URL?
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
        var foregroundObserver: NSObjectProtocol?

        deinit {
            if let foregroundObserver {
                NotificationCenter.default.removeObserver(foregroundObserver)
            }
            player?.pause()
        }
    }

    final class PlayerLayerView: UIView {
        final class VideoLayerView: UIView {
            override static var layerClass: AnyClass { AVPlayerLayer.self }
            var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        }

        let stillView = UIImageView()
        let videoView = VideoLayerView()
        var playerLayer: AVPlayerLayer { videoView.playerLayer }

        override init(frame: CGRect) {
            super.init(frame: frame)
            stillView.contentMode = .scaleAspectFill
            stillView.clipsToBounds = true
            videoView.clipsToBounds = true
            videoView.isOpaque = false
            videoView.backgroundColor = .clear
            stillView.backgroundColor = .clear
            addSubview(stillView)
            addSubview(videoView)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            stillView.frame = bounds
            videoView.frame = bounds
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerLayerView {
        let v = PlayerLayerView()
        v.clipsToBounds = true
        v.playerLayer.videoGravity = .resizeAspectFill
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        configure(v, context: context)
        return v
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        guard context.coordinator.url != url else { return }
        configure(uiView, context: context)
    }

    private func configure(_ v: PlayerLayerView, context: Context) {
        let co = context.coordinator
        co.player?.pause()
        if let old = co.foregroundObserver {
            NotificationCenter.default.removeObserver(old)
        }

        v.stillView.image = stillFrame

        let player = AVQueuePlayer()
        // silent video-only asset; never let it touch audio playback or sleep
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        co.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        co.player = player
        co.url = url
        v.playerLayer.player = player
        player.play()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak player, weak co] in
            guard let player else { return }
            let item = player.currentItem
            let error = item?.error?.localizedDescription ?? co?.looper?.error?.localizedDescription ?? "none"
            AppLogger.shared.log("Live artwork: video layer after 1.5s — itemStatus=\(item?.status.rawValue ?? -1) rate=\(player.rate) error=\(error)", category: .other)
        }

        // AVPlayer pauses video when the app backgrounds and won't resume itself
        co.foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak player] _ in
            player?.play()
        }
    }
}

// AnimatedImageView / FrameSteppingImageView live in Components/AnimatedArtworkView.swift

// MARK: - AirPlay button

// Keep the route picker for taps; draw our own glyph over it.
private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .clear
        v.activeTintColor = .clear
        v.prioritizesVideoDevices = false
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// route picker that shows the active output device (AirPods / headphones / car /
// speaker). The AirPlay picker sits behind a non-interactive dynamic icon.
private struct OutputRouteButton: View {
    @StateObject private var route = OutputRouteMonitor.shared

    var body: some View {
        ZStack {
            AirPlayButton()
            Image(systemName: route.iconName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(route.isExternal ? Theme.accent : .white.opacity(0.6))
                .allowsHitTesting(false)
                .id(route.iconName)
                .transition(.scale.combined(with: .opacity))
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: route.iconName)
    }
}

// MARK: - Song info sheet

struct SongInfoSheet: View {
    let song: Song?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let song {
                    row(L(.media_title), song.title)
                    row(L(.media_artist), song.artist)
                    row(L(.media_album), song.album)
                    row(L(.media_year), song.year.map(String.init))
                    row(L(.media_genre), song.genre)
                    row(L(.media_duration), song.duration.map { "\($0 / 60):\(String(format: "%02d", $0 % 60))" })
                    row(L(.media_bit_rate), song.bitRate.map { "\($0) kbps" })
                    row(L(.media_sample_rate), song.samplingRate.map { String(format: "%.1f kHz", Double($0) / 1000) })
                    row(L(.media_bit_depth), song.bitDepth.map { "\($0)-bit" })
                    row(L(.media_format), song.contentType)
                    row(L(.media_file_type), song.suffix?.uppercased())
                    row(L(.media_file_size), song.size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) })
                    row(L(.media_play_count), song.playCount.map(String.init))
                    row(L(.media_path), song.path)
                }
            }
            .navigationTitle(L(.song_info_title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L(.action_done)) { dismiss() } } }
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value { LabeledContent(label, value: value) }
    }
}

// MARK: - Lossless badge popover (format / bitrate / sample rate)

private struct LosslessInfoPopover: View {
    let song: Song?
    var onOpenSignalPath: () -> Void
    private var status: LosslessBadgeStatus? { LosslessBadgeResolver.status(for: song) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: status?.systemImage ?? "waveform")
                Text(status?.status ?? "Lossless Audio").font(.headline)
            }
            .padding(.bottom, 2)

            if let status {
                detailRow("Output", status.output)
                detailRow("Route", status.reason)
            }
            if let format { detailRow("Format", format) }
            if let rate = song?.bitRate { detailRow("Bitrate", "\(rate) kbps") }
            if let sr = song?.samplingRate {
                detailRow("Sample Rate", String(format: "%.1f kHz", Double(sr) / 1000))
            }
            if let bd = song?.bitDepth { detailRow("Bit Depth", "\(bd)-bit") }

            Divider().padding(.vertical, 2)

            Button(action: onOpenSignalPath) {
                Label("Audio Signal Path", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .padding(16)
        .frame(minWidth: 220)
    }

    private var format: String? {
        song?.suffix?.uppercased() ?? song?.contentType
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 24)
            Text(value).fontWeight(.medium)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
    }
}

// MARK: - Audio signal path

private struct AudioSignalPathSheet: View {
    let song: Song?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("streamingBitrate") private var streamingBitrate = 0
    @AppStorage("streamingBitrateCell") private var streamingBitrateCell = 0
    @AppStorage("transcodingFormat") private var transcodingFormat = "raw"
    @AppStorage("replayGainMode") private var replayGainMode = "off"

    private var status: LosslessBadgeStatus? { LosslessBadgeResolver.status(for: song) }
    private var session: AVAudioSession { AVAudioSession.sharedInstance() }

    var body: some View {
        NavigationStack {
            List {
                Section("Source File") {
                    row("Title", song?.title)
                    row("Format", fileFormat)
                    row("Bitrate", song?.bitRate.map { "\($0) kbps" })
                    row("Sample Rate", song?.samplingRate.map(formatSampleRate))
                    row("Bit Depth", song?.bitDepth.map { "\($0)-bit" })
                    row("Lossless", song?.isLossless == true ? "Yes" : "No")
                }

                Section("Server Stream") {
                    row("Transcoding", transcodingFormat == "raw" ? "Original" : transcodingFormat.uppercased())
                    row("Wi-Fi Quality", bitrateLabel(streamingBitrate))
                    row("Cellular Quality", streamingBitrateCell == 0 ? "Same as Wi-Fi" : bitrateLabel(streamingBitrateCell))
                }

                Section("App Processing") {
                    row("Volume Normalization", replayGainMode.capitalized)
                    row("Equalizer", EqualizerEngine.shared.isEnabled ? "On" : "Off")
                }

                Section("Output Route") {
                    row("Route", outputName)
                    row("Port Type", outputPortTypes)
                    row("Output Sample Rate", session.sampleRate > 0 ? formatSampleRate(Int(session.sampleRate.rounded())) : nil)
                    row("Output Channels", session.outputNumberOfChannels > 0 ? "\(session.outputNumberOfChannels)" : nil)
                }

                Section("Result") {
                    row("Badge", status?.status ?? "Not lossless")
                    row("Why", status?.reason)
                }
            }
            .navigationTitle("Audio Signal Path")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(Theme.colorScheme)
    }

    private var fileFormat: String? {
        song?.suffix?.uppercased() ?? song?.contentType
    }

    private var outputName: String {
        let names = session.currentRoute.outputs.map(\.portName).filter { !$0.isEmpty }
        return names.isEmpty ? "System Output" : names.joined(separator: ", ")
    }

    private var outputPortTypes: String {
        let types = session.currentRoute.outputs.map { $0.portType.rawValue }.filter { !$0.isEmpty }
        return types.isEmpty ? "Unknown" : types.joined(separator: ", ")
    }

    private func bitrateLabel(_ value: Int) -> String {
        value == 0 ? "Original" : "\(value) kbps"
    }

    private func formatSampleRate(_ value: Int) -> String {
        String(format: "%.1f kHz", Double(value) / 1000)
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(label, value: value)
        }
    }
}
