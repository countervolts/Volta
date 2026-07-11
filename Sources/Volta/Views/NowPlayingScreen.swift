import SwiftUI
import AVKit
import AVFoundation
import MediaPlayer
import UIKit
import UniformTypeIdentifiers

enum PlayerTab { case nowPlaying, queue, lyrics }

struct NowPlayingScreen: View {
    @EnvironmentObject private var appState: AppState
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
    // Gates the scrubber's animation schedule until the open transition finishes,
    // so the time labels don't get caught up in the present animation and bounce.
    @State private var playerSettled = false
    @State private var isAdjustingVolume = false
    @State private var artistToShow: Artist?
    @State private var albumToShow: Album?
    @State private var showArtistAlbumPicker = false
    @State private var isFetchingArtist = false
    @State private var isFetchingAlbum = false
    @StateObject private var tasteStore = TasteStore.shared
    @State private var showQueueHistory = false
    @State private var didPositionQueueScroll = false
    @State private var queueScrollRequest = 0
    @State private var queueAnchorOffset: CGFloat = 0
    @State private var draggingQueueIndex: Int?
    @State private var draggingQueueSongID: String?
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
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var audio: AudioPlayer { appState.audioPlayer }
    private let queueContentAnchor = "queue-content-anchor"
    private var currentTaste: TasteState {
        audio.currentSong.map { tasteStore.state(for: $0.id) } ?? .neutral
    }
    private var isPhoneLandscape: Bool {
        UIDevice.current.userInterfaceIdiom == .phone && verticalSizeClass == .compact
    }

    var body: some View {
        ZStack {
            playerBackground.ignoresSafeArea()

            if isPhoneLandscape {
                phoneLandscapeLayout
            } else if sizeClass == .regular {
                iPadLayout
            } else {
                phoneLayout
            }
        }
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged { v in
                    if shouldSuppressPlayerDismissDrag(v) {
                        pendingDragOffset = 0
                        dragOffset = 0
                        return
                    }
                    pendingDragOffset = max(0, v.translation.height)
                    if let dragThrottler {
                        dragThrottler.schedule()
                    } else {
                        dragOffset = pendingDragOffset
                    }
                }
                .onEnded { v in
                    if shouldSuppressPlayerDismissDrag(v) {
                        pendingDragOffset = 0
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { dragOffset = 0 }
                        return
                    }
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
        .confirmationDialog(
            audio.currentSong?.artist ?? "",
            isPresented: $showArtistAlbumPicker,
            titleVisibility: .visible
        ) {
            if audio.currentSong?.artistId != nil {
                Button {
                    openCurrentArtist()
                } label: {
                    Label(L(.action_go_to_artist), systemImage: "person.fill")
                }
            }
            if audio.currentSong?.albumId != nil {
                Button {
                    openCurrentAlbum()
                } label: {
                    Label(L(.action_go_to_album), systemImage: "square.stack")
                }
            }
            Button(L(.action_cancel), role: .cancel) {}
        } message: {
            if let album = audio.currentSong?.album {
                Text(album)
            }
        }
        .sheet(item: $albumToShow) { album in
            NavigationStack {
                AlbumDetailView(album: album)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(L(.action_done)) { albumToShow = nil }
                                .foregroundStyle(Theme.accent)
                        }
                    }
            }
            // Re-host toasts above the sheet; the root host sits below this layer.
            .overlay { VoltaNotificationHost() }
            .preferredColorScheme(Theme.colorScheme)
        }
        .sheet(item: $artistToShow) { artist in
            NavigationStack {
                ArtistDetailView(artist: artist)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(L(.action_done)) { artistToShow = nil }
                                .foregroundStyle(Theme.accent)
                        }
                    }
            }
            .overlay { VoltaNotificationHost() }
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
            // Hold the scrubber's high-frequency schedule until the open
            // transition (0.4s) has settled, then let the time labels animate live.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                playerSettled = true
            }
        }
        .onDisappear {
            AppLogger.shared.log("Full player disappeared", category: .playback)
            dragThrottler?.invalidate()
            dragThrottler = nil
        }
        .onChangeCompat(of: audio.currentSong?.id) { _, _ in
            refreshPlayerBackground(animated: true)
        }
        .onChangeCompat(of: audio.currentArtwork == nil) { _, _ in
            refreshPlayerBackground(animated: true)
        }
        .onChangeCompat(of: dynamicBackground) { _, _ in
            refreshPlayerBackground(animated: true)
        }
        .onChangeCompat(of: activeTab) { _, tab in
            if tab != .queue {
                showQueueHistory = false
                didPositionQueueScroll = false
                queueAnchorOffset = 0
            }
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

    private var phoneLandscapeLayout: some View {
        GeometryReader { geo in
            let safe = geo.safeAreaInsets
            let verticalInset = [
                CGFloat(28),
                geo.size.height * 0.09,
                safe.top + 14,
                safe.bottom + 14
            ].max() ?? 28
            let leadingInset = max(safe.leading + 22, geo.size.width * 0.06)
            let trailingInset = max(safe.trailing + 22, geo.size.width * 0.045)
            let columnSpacing = max(28, geo.size.width * 0.045)
            let minimumPanelWidth = min(360, max(250, geo.size.width * 0.36))
            let maxArtworkFromHeight = max(190, geo.size.height - verticalInset * 2)
            let maxArtworkFromWidth = max(
                190,
                geo.size.width - leadingInset - trailingInset - columnSpacing - minimumPanelWidth
            )
            let artworkSide = min(maxArtworkFromHeight, geo.size.width * 0.43, maxArtworkFromWidth)

            HStack(alignment: .center, spacing: columnSpacing) {
                landscapeArtworkView
                    .frame(width: artworkSide, height: artworkSide)

                landscapeRightPanel
                    .frame(maxWidth: .infinity)
                    .frame(height: artworkSide)
            }
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
            .padding(.vertical, verticalInset)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            .overlay(alignment: .top) {
                dragHandle
                    .padding(.top, max(0, safe.top - 2))
            }
        }
    }

    private var landscapeArtworkView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.12))
                .shadow(color: .black.opacity(0.34), radius: 26, y: 18)
            if let live = audio.currentLiveArtwork {
                liveArtworkView(live)
            } else if let image = audio.currentArtwork {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: Symbols.albumPlaceholder)
                    .font(.system(size: 64, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.28))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .id(audio.currentSong?.id)
    }

    private var landscapeRightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            landscapeTrackHeader

            landscapePanelContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            landscapeBottomNavigation
        }
    }

    @ViewBuilder
    private var landscapePanelContent: some View {
        switch activeTab {
        case .nowPlaying:
            landscapeNowPlayingPanel
        case .queue:
            landscapeQueuePanel
        case .lyrics:
            LandscapeLyricsPreview()
        }
    }

    private var landscapeTrackHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(audio.currentSong?.title ?? " ")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Button { presentArtistAlbumPicker() } label: {
                    Text(audio.currentSong?.artist ?? " ")
                        .font(.system(size: 23, weight: .regular))
                        .foregroundStyle(.white.opacity((isFetchingArtist || isFetchingAlbum) ? 0.35 : 0.58))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .buttonStyle(.plain)
                .disabled(audio.currentSong?.artistId == nil && audio.currentSong?.albumId == nil)
            }

            Spacer(minLength: 12)

            HStack(spacing: 12) {
                landscapeStarButton
                landscapeMoreMenu
            }
        }
        .padding(.top, 14)
    }

    private var landscapeStarButton: some View {
        Button {
            if let id = audio.currentSong?.id { audio.toggleStar(songID: id) }
        } label: {
            Image(systemName: audio.currentSong.map { audio.isStarred($0.id) } == true
                  ? Symbols.star : Symbols.starEmpty)
                .font(.system(size: 25, weight: .regular))
                .foregroundStyle(audio.currentSong.map { audio.isStarred($0.id) } == true
                                 ? .yellow : .white)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.12), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.6),
                   value: audio.currentSong.map { audio.isStarred($0.id) })
    }

    private var landscapeMoreMenu: some View {
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
                Button { openCurrentAlbum() } label: {
                    Label(L(.action_go_to_album), systemImage: "square.stack")
                }
            }
            if audio.currentSong?.artistId != nil {
                Button { openCurrentArtist() } label: {
                    Label(L(.action_go_to_artist), systemImage: "person.fill")
                }
            }
        } label: {
            Image(systemName: Symbols.more)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.12), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var landscapeNowPlayingPanel: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)

            landscapeScrubber

            Spacer(minLength: 18)

            landscapeTransportControls

            Spacer(minLength: 20)

            landscapeVolumeControl

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var landscapeScrubber: some View {
        TimelineView(
            .animation(
                minimumInterval: preciseTimestamps ? 1.0 / 60.0 : 0.2,
                paused: !playerSettled || scrubbing || !audio.isPlaying
            )
        ) { _ in
            let snapshot = audio.playbackTimeSnapshot()
            let total = snapshot.duration
            let t = scrubbing ? min(scrubTime, total) : snapshot.elapsed
            VStack(spacing: 7) {
                ScrubBar(
                    duration: total,
                    currentTime: t,
                    scrubbing: $scrubbing,
                    scrubTime: $scrubTime,
                    onSeek: { audio.seek(to: $0) }
                )
                landscapeTimeLabels(elapsed: t, total: total)
            }
        }
        .transaction { $0.animation = nil }
    }

    private func landscapeTimeLabels(elapsed t: TimeInterval, total: TimeInterval) -> some View {
        HStack {
            timeText(formatTime(t))
            Spacer()
            timeText("-\(formatTime(max(0, total - t)))")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white.opacity(0.42))
        .frame(height: 18)
    }

    private var landscapeTransportControls: some View {
        HStack(spacing: 0) {
            Spacer()

            Button {
                animatePrev()
                audio.skipPrevious()
            } label: {
                Image(systemName: Symbols.previous)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 78, height: 62)
                    .offset(x: prevNudge)
            }
            .buttonStyle(.plain)

            Spacer()

            Button { audio.togglePlayPause() } label: {
                Image(systemName: audio.isPlaying ? Symbols.pause : Symbols.play)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 92, height: 74)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: audio.isPlaying)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                animateSkip()
                audio.skipNext()
            } label: {
                Image(systemName: Symbols.next)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 78, height: 62)
                    .offset(x: skipNudge)
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private var landscapeVolumeControl: some View {
        HStack(spacing: 14) {
            Image(systemName: Symbols.volumeLow)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.54))
            SystemVolumeSlider(isInteracting: $isAdjustingVolume)
                .frame(height: RuntimeCompatibility.isIOS16 ? 28 : 22)
                .scaleEffect(x: 1, y: isAdjustingVolume ? 1.55 : 1, anchor: .center)
                .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isAdjustingVolume)
            Image(systemName: Symbols.volumeHigh)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.54))
        }
    }

    private var landscapeQueuePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            landscapeModeToggles
                .padding(.top, 34)
                .padding(.bottom, 22)

            Text(L(.queue_continue_playing))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
            if !audio.queueSourceTitle.isEmpty {
                Text(audio.queueSourceTitle)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
            }

            landscapeQueueList
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var landscapeModeToggles: some View {
        let autoplayIcon: String = switch audio.autoplayMode {
        case .off, .random: "infinity"
        case .algorithm: "wand.and.stars"
        }
        return HStack(spacing: 16) {
            landscapeModeButton(icon: Symbols.shuffle, active: audio.isShuffle) {
                audio.toggleShuffle()
            }
            landscapeModeButton(
                icon: audio.repeatMode == .one ? Symbols.repeatOne : Symbols.repeatAll,
                active: audio.repeatMode != .off
            ) {
                audio.cycleRepeat()
            }
            landscapeModeButton(icon: autoplayIcon, active: audio.autoplayMode != .off) {
                audio.cycleAutoplay()
            }
            landscapeModeButton(icon: audio.transitionMode.icon, active: audio.transitionMode != .off) {
                audio.cycleTransitionMode()
            }
        }
    }

    private func landscapeModeButton(icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(active ? Color(white: 0.18) : .white.opacity(0.76))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    Capsule(style: .continuous)
                        .fill(active ? .white.opacity(0.68) : .white.opacity(0.11))
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.74), value: active)
    }

    private var landscapeUpcomingSongs: [Song] {
        let next = audio.currentIndex + 1
        guard next < audio.queue.count else { return [] }
        return Array(audio.queue[next...])
    }

    @ViewBuilder
    private var landscapeQueueList: some View {
        let upcoming = landscapeUpcomingSongs
        if upcoming.isEmpty {
            Text("Nothing queued")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.42))
                .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(Array(upcoming.enumerated()), id: \.offset) { item in
                        let globalIndex = audio.currentIndex + 1 + item.offset
                        landscapeQueueRow(song: item.element, globalIndex: globalIndex)
                    }
                }
                .padding(.bottom, 30)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.72),
                        .init(color: .black.opacity(0.05), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private func landscapeQueueRow(song: Song, globalIndex: Int) -> some View {
        Button {
            audio.skipTo(index: globalIndex)
        } label: {
            HStack(spacing: 14) {
                ArtworkView(coverArtID: song.coverArt, size: 96, cornerRadius: 6)
                    .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(song.artist ?? "")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                Image(systemName: Symbols.dragHandle)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.25))
                    .frame(width: 36, height: 44)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private var landscapeBottomNavigation: some View {
        HStack(spacing: 0) {
            landscapeTabButton(
                tab: .lyrics,
                icon: activeTab == .lyrics ? Symbols.lyrics : Symbols.lyricsInactive
            )
            .frame(maxWidth: .infinity)

            OutputRouteButton()
                .frame(width: 48, height: 48)
                .scaleEffect(1.16)
                .frame(maxWidth: .infinity)

            landscapeTabButton(tab: .queue, icon: Symbols.queue)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 54)
        .overlay(alignment: .topTrailing) {
            if activeTab != .queue && audio.isShuffle {
                landscapeShuffleBadge
                    .offset(x: 8, y: -19)
            }
        }
    }

    private func landscapeTabButton(tab: PlayerTab, icon: String) -> some View {
        let active = activeTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                activeTab = active ? .nowPlaying : tab
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(active ? Color(white: 0.20) : .white.opacity(0.58))
                .frame(width: 46, height: 46)
                .background(active ? .white.opacity(0.68) : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var landscapeShuffleBadge: some View {
        Button {
            audio.toggleShuffle()
        } label: {
            Image(systemName: Symbols.shuffle)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.13), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
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

    private func presentArtistAlbumPicker() {
        guard audio.currentSong?.artistId != nil || audio.currentSong?.albumId != nil else { return }
        showArtistAlbumPicker = true
    }

    private func openCurrentArtist() {
        guard let artistId = audio.currentSong?.artistId, !isFetchingArtist else { return }
        isFetchingArtist = true
        Task {
            defer { isFetchingArtist = false }
            artistToShow = try? await appState.client?.artist(id: artistId)
        }
    }

    private func openCurrentAlbum() {
        guard let albumId = audio.currentSong?.albumId, !isFetchingAlbum else { return }
        isFetchingAlbum = true
        Task {
            defer { isFetchingAlbum = false }
            albumToShow = try? await appState.client?.album(id: albumId)
        }
    }

    @ViewBuilder
    private var sleepTimerMenu: some View {
        Menu {
            if audio.sleepTimerActive {
                Button(role: .destructive) { audio.cancelSleepTimer() } label: {
                    Label(audio.sleepEndsAtTrackEnd ? L(.sleep_cancel_end_of_track) : L(.sleep_cancel_timer),
                          systemImage: "xmark.circle")
                }
                Divider()
            }
            ForEach([5, 15, 30, 45, 60], id: \.self) { m in
                Button(L(.sleep_minutes, m)) { audio.startSleepTimer(minutes: m) }
            }
            Button(L(.sleep_end_of_track)) { audio.startSleepTimerEndOfTrack() }
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
            queuePagerContent
        case .lyrics:
            altContent { LyricsViewWithState().transition(.opacity) }
        }
    }

    private var queuePagerContent: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                GeometryReader { scrollGeo in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            queueHistoryHeader
                                .padding(.horizontal, 24)
                                .padding(.top, 52)
                                .padding(.bottom, 18)

                            queueHistoryRows
                                .padding(.bottom, 34)

                            Color.clear
                                .frame(height: 1)
                                .id(queueContentAnchor)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: QueueAnchorOffsetKey.self,
                                            value: geo.frame(in: .named("queueScroll")).minY
                                        )
                                    }
                                )

                            VStack(alignment: .leading, spacing: 0) {
                                compactTrackHeader
                                    .padding(.horizontal, 20)
                                    .padding(.top, 4)
                                    .padding(.bottom, 20)

                                queueModeToggles
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 26)

                                queueContinueHeader
                                    .padding(.horizontal, 24)
                                    .padding(.bottom, 18)

                                queueUpcomingRows
                                    .padding(.horizontal, 24)
                            }
                            .frame(maxWidth: .infinity, minHeight: scrollGeo.size.height, alignment: .top)
                        }
                        .padding(.bottom, 28)
                    }
                    .coordinateSpace(name: "queueScroll")
                    .scrollIndicators(.visible)
                    .task(id: activeTab) {
                        guard activeTab == .queue, !didPositionQueueScroll else { return }
                        didPositionQueueScroll = true
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        proxy.scrollTo(queueContentAnchor, anchor: .top)
                    }
                    .onChangeCompat(of: queueScrollRequest) { _, _ in
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                            proxy.scrollTo(queueContentAnchor, anchor: .top)
                        }
                    }
                    .onPreferenceChange(QueueAnchorOffsetKey.self) { offset in
                        queueAnchorOffset = offset
                        let visible = offset > 24
                        if visible != showQueueHistory {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showQueueHistory = visible
                        }
                    }
                }

                scrubber
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
        }
    }

    private var queueHistoryHeader: some View {
        HStack {
            Text("History")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Spacer()
            Button {
                audio.clearPlaybackHistory()
            } label: {
                Text(L(.action_clear))
                    .font(.body.weight(.medium))
                    .foregroundStyle(audio.playbackHistory.isEmpty ? .white.opacity(0.28) : .white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .disabled(audio.playbackHistory.isEmpty)
        }
    }

    @ViewBuilder
    private var queueHistoryRows: some View {
        let history = audio.playbackHistory.filter { $0.id != audio.currentSong?.id }
        if history.isEmpty {
            Text("No history yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.42))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                .padding(.horizontal, 24)
                .padding(.top, 8)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(history, id: \.id) { song in
                    queueHistoryRow(song)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func queueHistoryRow(_ song: Song) -> some View {
        Button {
            audio.playFromHistory(song)
            queueScrollRequest += 1
        } label: {
            HStack(spacing: 12) {
                ArtworkView(coverArtID: song.coverArt, size: 80, cornerRadius: 6)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.body)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(song.artist ?? "")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private var queueModeToggles: some View {
        let autoplayIcon: String = switch audio.autoplayMode {
        case .off, .random: "infinity"
        case .algorithm: "wand.and.stars"
        }
        return HStack(spacing: 16) {
            queueModeButton(icon: Symbols.shuffle, active: audio.isShuffle) {
                audio.toggleShuffle()
            }
            queueModeButton(
                icon: audio.repeatMode == .one ? Symbols.repeatOne : Symbols.repeatAll,
                active: audio.repeatMode != .off
            ) {
                audio.cycleRepeat()
            }
            queueModeButton(icon: autoplayIcon, active: audio.autoplayMode != .off) {
                audio.cycleAutoplay()
            }
            queueModeButton(icon: audio.transitionMode.icon, active: audio.transitionMode != .off) {
                audio.cycleTransitionMode()
            }
        }
    }

    private func queueModeButton(icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(active ? Color(white: 0.18) : .white.opacity(0.76))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    Capsule(style: .continuous)
                        .fill(active ? .white.opacity(0.68) : .white.opacity(0.11))
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.74), value: active)
    }

    private var queueContinueHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L(.queue_continue_playing))
                .font(.headline)
                .foregroundStyle(.white)
            if !audio.queueSourceTitle.isEmpty {
                Text(audio.queueSourceTitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var queueUpcomingSongs: [Song] {
        let next = audio.currentIndex + 1
        guard next < audio.queue.count else { return [] }
        return Array(audio.queue[next...])
    }

    @ViewBuilder
    private var queueUpcomingRows: some View {
        let upcoming = queueUpcomingSongs
        if upcoming.isEmpty {
            Text("Nothing queued")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.42))
                .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(upcoming.enumerated()), id: \.element.id) { item in
                    let globalIndex = audio.currentIndex + 1 + item.offset
                    queueUpcomingRow(song: item.element, globalIndex: globalIndex)
                }
            }
        }
    }

    private func queueUpcomingRow(song: Song, globalIndex: Int) -> some View {
        HStack(spacing: 12) {
            ArtworkView(coverArtID: song.coverArt, size: 80, cornerRadius: 6)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(song.artist ?? "")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Image(systemName: Symbols.dragHandle)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.25))
                .frame(width: 36, height: 44)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 8)
        .opacity(draggingQueueSongID == song.id ? 0.45 : 1)
        .onTapGesture {
            audio.skipTo(index: globalIndex)
        }
        .onDrag {
            draggingQueueIndex = globalIndex
            draggingQueueSongID = song.id
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return NSItemProvider(object: song.id as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: QueueReorderDropDelegate(
                destinationIndex: globalIndex,
                draggingIndex: $draggingQueueIndex,
                draggingSongID: $draggingQueueSongID,
                move: moveQueuedSong
            )
        )
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: draggingQueueSongID)
    }

    private func moveQueuedSong(from source: Int, to destination: Int) {
        guard source != destination,
              source > audio.currentIndex,
              destination > audio.currentIndex,
              source < audio.queue.count,
              destination < audio.queue.count else { return }
        let insertionIndex = source < destination ? destination + 1 : destination
        audio.moveQueueItem(from: IndexSet(integer: source), to: min(insertionIndex, audio.queue.count))
    }

    private func shouldSuppressPlayerDismissDrag(_ value: DragGesture.Value) -> Bool {
        guard !isPhoneLandscape,
              sizeClass != .regular,
              activeTab == .queue else { return false }
        if showQueueHistory, value.translation.height > 0, queueAnchorOffset > 260 {
            return false
        }
        return true
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
                        Button { openCurrentAlbum() } label: {
                            Label(L(.action_go_to_album), systemImage: "square.stack")
                        }
                    }
                    if audio.currentSong?.artistId != nil {
                        Button { openCurrentArtist() } label: {
                            Label(L(.action_go_to_artist), systemImage: "person.fill")
                        }
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
                            .symbolVariableColorRepeatingCompat()
                        Text(L(.player_mixing))
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
                Button { presentArtistAlbumPicker() } label: {
                    Text(audio.currentSong?.artist ?? " ")
                        .font(.body)
                        .foregroundStyle(.white.opacity((isFetchingArtist || isFetchingAlbum) ? 0.35 : 0.65))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(audio.currentSong?.artistId == nil && audio.currentSong?.albumId == nil)
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
                        Button { openCurrentAlbum() } label: {
                            Label(L(.action_go_to_album), systemImage: "square.stack")
                        }
                    }
                    if audio.currentSong?.artistId != nil {
                        Button { openCurrentArtist() } label: {
                            Label(L(.action_go_to_artist), systemImage: "person.fill")
                        }
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
        TimelineView(
            .animation(
                minimumInterval: preciseTimestamps ? 1.0 / 60.0 : 0.2,
                paused: !playerSettled || scrubbing || !audio.isPlaying
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
                timeLabels(elapsed: t, total: total)
            }
        }
        .transaction { $0.animation = nil }
    }

    // Text has .contentTransition(.identity) + .transaction { animation = nil } so the
    // animation-schedule doesn't wobble it. Driven by the shared snapshot above.
    private func timeLabels(elapsed t: TimeInterval, total: TimeInterval) -> some View {
        let losslessStatus = LosslessBadgeResolver.status(for: audio.currentSong)
        return HStack {
            timeText(formatTime(t))
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
                        .popoverPresentationCompactAdaptationCompat()
                }
            }
            Spacer()
            timeText("-\(formatTime(max(0, total - t)))")
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.5))
        // Fixed line height so the badge can't shift the time labels.
        .frame(height: 22)
    }

    private func timeText(_ value: String) -> some View {
        Text(value)
            .monospacedDigit()
            .contentTransition(.identity)
            .transaction { $0.animation = nil }
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
                    .frame(height: RuntimeCompatibility.isIOS16 ? 28 : 20)
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
                    if activeTab == .queue, showQueueHistory {
                        queueScrollRequest += 1
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeTab = activeTab == .queue ? .nowPlaying : .queue
                        }
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

private struct QueueAnchorOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct QueueReorderDropDelegate: DropDelegate {
    let destinationIndex: Int
    @Binding var draggingIndex: Int?
    @Binding var draggingSongID: String?
    let move: (Int, Int) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let sourceIndex = draggingIndex,
              sourceIndex != destinationIndex else { return }
        move(sourceIndex, destinationIndex)
        draggingIndex = destinationIndex
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingIndex = nil
        draggingSongID = nil
        return true
    }

    func dropExited(info: DropInfo) {
        guard !info.hasItemsConforming(to: [UTType.text]) else { return }
        draggingIndex = nil
        draggingSongID = nil
    }
}

private struct LandscapeLyricsPreview: View {
    @EnvironmentObject private var appState: AppState
    @State private var lines: [LyricLine] = []
    @State private var isLoading = false
    @State private var activeIndex = 0

    private var audio: AudioPlayer { appState.audioPlayer }
    private var isSynced: Bool { lines.first.map { $0.time >= 0 } ?? false }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lines.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: Symbols.lyricsInactive)
                        .font(.system(size: 36, weight: .ultraLight))
                    Text(L(.lyrics_none))
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.35))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                lyricStack
            }
        }
        .task(id: audio.currentSong?.id) {
            await loadLyrics()
        }
        .onChangeCompat(of: audio.currentTime) { _, time in
            updateActiveLine(for: time)
        }
    }

    private var lyricStack: some View {
        VStack(alignment: .leading, spacing: 34) {
            if let currentLine {
                Text(displayText(for: currentLine))
                    .font(.system(size: 37, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.68)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let nextLine {
                Text(displayText(for: nextLine))
                    .font(.system(size: 31, weight: .bold))
                    .foregroundStyle(.white.opacity(0.13))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .multilineTextAlignment(.leading)
                    .blur(radius: 3.2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.bottom, 12)
        .animation(.spring(response: 0.52, dampingFraction: 0.84), value: activeIndex)
    }

    private var currentLine: LyricLine? {
        guard lines.indices.contains(activeIndex) else { return lines.first }
        return lines[activeIndex]
    }

    private var nextLine: LyricLine? {
        let next = activeIndex + 1
        guard lines.indices.contains(next) else { return nil }
        return lines[next]
    }

    private func displayText(for line: LyricLine) -> String {
        line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? " " : line.text
    }

    private func loadLyrics() async {
        guard let song = audio.currentSong, let client = appState.client else {
            lines = []
            activeIndex = 0
            return
        }

        isLoading = true
        defer { isLoading = false }
        lines = await LyricsService.shared.lyrics(for: song, client: client)
        activeIndex = 0
        updateActiveLine(for: audio.currentTime)
    }

    private func updateActiveLine(for time: TimeInterval) {
        guard isSynced else { return }
        if let index = lines.lastIndex(where: { $0.time <= time }), index != activeIndex {
            activeIndex = index
        }
    }
}

private struct AudioVisualizerScreen: View {
    let audio: AudioPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if RuntimeCompatibility.usesPassiveVisualizer {
                PassiveAudioVisualizerView(isPlaying: audio.isPlaying)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !audio.isPlaying)) { timeline in
                    Canvas { context, size in
                        drawVoltaVisual(context: &context, size: size, date: timeline.date)
                    }
                }
                .ignoresSafeArea()
            }

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
                    Text(audio.currentSong?.title ?? L(.player_not_playing))
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
        .onAppear {
            if !RuntimeCompatibility.usesPassiveVisualizer {
                audio.setVisualizerActive(true)
            }
        }
        .onDisappear {
            if !RuntimeCompatibility.usesPassiveVisualizer {
                audio.setVisualizerActive(false)
            }
        }
    }

    private func drawVoltaVisual(context: inout GraphicsContext, size: CGSize, date: Date) {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.43)
        let side = min(size.width, size.height)
        let baseRadius = side * 0.17
        let liveTime = audio.liveTime()
        let clock = date.timeIntervalSinceReferenceDate + liveTime
        let snapshot = audio.visualizerSnapshot()
        let bands = snapshot.bands.isEmpty ? AudioVisualizerSnapshot.silent.bands : snapshot.bands
        let rms = audio.isPlaying ? min(1.0, snapshot.rms * 4.0) : 0
        let peak = audio.isPlaying ? min(1.0, snapshot.peak * 1.7) : 0
        let beat = audio.isPlaying ? min(1.0, snapshot.beat) : 0
        let energy = max(0.08, rms)
        let rotation = clock * (0.035 + energy * 0.035)

        let glowRect = CGRect(x: center.x - side * 0.46, y: center.y - side * 0.46, width: side * 0.92, height: side * 0.92)
        context.fill(
            Path(ellipseIn: glowRect),
            with: .radialGradient(
                Gradient(colors: [
                    .white.opacity(0.07 + 0.08 * peak),
                    Theme.accent.opacity(0.28 + 0.20 * beat),
                    .cyan.opacity(0.06 + 0.10 * rms),
                    .clear
                ]),
                center: center,
                startRadius: 0,
                endRadius: side * 0.46
            )
        )

        let coreRadius = baseRadius * CGFloat(0.72 + rms * 0.16 + beat * 0.12)
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - coreRadius, y: center.y - coreRadius, width: coreRadius * 2, height: coreRadius * 2)),
            with: .radialGradient(
                Gradient(colors: [
                    .white.opacity(0.92),
                    Theme.accent.opacity(0.88),
                    .cyan.opacity(0.46),
                    .clear
                ]),
                center: center,
                startRadius: 0,
                endRadius: coreRadius
            )
        )

        for ring in 0..<3 {
            let progress = CGFloat(ring) / 2
            let radius = baseRadius * (1.08 + progress * 0.42) + CGFloat(beat) * 10
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            var path = Path()
            path.addEllipse(in: rect)
            context.stroke(
                path,
                with: .color(.white.opacity(0.14 + Double(progress) * 0.09 + rms * 0.18)),
                style: StrokeStyle(lineWidth: 0.8 + progress * 1.4, lineCap: .round, dash: [8 + progress * 8, 14 + progress * 10], dashPhase: CGFloat(clock * (10 + Double(ring) * 7)))
            )
        }

        let count = bands.count
        for i in 0..<count {
            let raw = max(0, min(1, bands[i]))
            let neighbor = (bands[max(0, i - 1)] + raw + bands[min(count - 1, i + 1)]) / 3
            let shaped = pow(neighbor, 0.72)
            let fraction = Double(i) / Double(count)
            let angle = -Double.pi / 2 + fraction * Double.pi * 2 + rotation
            let lineWidth = max(1.4, side * 0.0036)
            let inner = baseRadius * CGFloat(1.22 + peak * 0.05)
            let outer = inner + side * CGFloat(0.055 + shaped * 0.28 + beat * 0.025)
            let cap = side * CGFloat(0.009 + shaped * 0.016)
            let a = CGFloat(angle)
            let p1 = CGPoint(x: center.x + cos(a) * inner, y: center.y + sin(a) * inner)
            let p2 = CGPoint(x: center.x + cos(a) * outer, y: center.y + sin(a) * outer)
            var path = Path()
            path.move(to: p1)
            path.addLine(to: p2)
            let hue = fraction
            let color = Color(
                hue: 0.56 + hue * 0.19,
                saturation: 0.50 + shaped * 0.34,
                brightness: 0.78 + shaped * 0.22
            )
            context.stroke(
                path,
                with: .color(color.opacity(0.38 + shaped * 0.58)),
                style: StrokeStyle(lineWidth: lineWidth + CGFloat(shaped) * 2.8, lineCap: .round)
            )
            if shaped > 0.18 {
                let dot = CGPoint(x: center.x + cos(a) * (outer + cap * 0.25), y: center.y + sin(a) * (outer + cap * 0.25))
                context.fill(
                    Path(ellipseIn: CGRect(x: dot.x - cap / 2, y: dot.y - cap / 2, width: cap, height: cap)),
                    with: .color(.white.opacity(0.12 + shaped * 0.48))
                )
            }
        }

        var waveform = Path()
        let waveformRadius = baseRadius * 2.16 + CGFloat(beat) * 8
        for i in 0...count {
            let band = bands[i % count]
            let fraction = Double(i) / Double(count)
            let angle = -Double.pi / 2 + fraction * Double.pi * 2 - rotation * 0.72
            let radius = waveformRadius + CGFloat(pow(band, 0.7)) * side * 0.075
            let point = CGPoint(x: center.x + cos(CGFloat(angle)) * radius, y: center.y + sin(CGFloat(angle)) * radius)
            if i == 0 { waveform.move(to: point) } else { waveform.addLine(to: point) }
        }
        context.stroke(
            waveform,
            with: .linearGradient(
                Gradient(colors: [.white.opacity(0.32 + rms * 0.28), Theme.accent.opacity(0.52), .cyan.opacity(0.36)]),
                startPoint: CGPoint(x: center.x - waveformRadius, y: center.y - waveformRadius),
                endPoint: CGPoint(x: center.x + waveformRadius, y: center.y + waveformRadius)
            ),
            style: StrokeStyle(lineWidth: 1.1 + CGFloat(rms) * 2.2, lineCap: .round, lineJoin: .round)
        )

        for i in stride(from: 0, to: count, by: 4) {
            let amplitude = bands[i]
            guard amplitude > 0.10 else { continue }
            let fraction = Double(i) / Double(count)
            let angle = -Double.pi / 2 + fraction * Double.pi * 2 + rotation * 1.6
            let radius = baseRadius * CGFloat(2.54 + amplitude * 0.42 + beat * 0.08)
            let dotSize = side * CGFloat(0.004 + amplitude * 0.012)
            let dot = CGPoint(x: center.x + cos(CGFloat(angle)) * radius, y: center.y + sin(CGFloat(angle)) * radius)
            context.fill(
                Path(ellipseIn: CGRect(x: dot.x - dotSize / 2, y: dot.y - dotSize / 2, width: dotSize, height: dotSize)),
                with: .color(Theme.accent.opacity(0.22 + amplitude * 0.50))
            )
        }
    }
}

private struct PassiveAudioVisualizerView: View {
    let isPlaying: Bool
    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let centerY = geo.size.height * 0.43
            let baseRadius = side * 0.17

            ZStack {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .stroke(
                            Theme.accent.opacity(0.16 - Double(index) * 0.02),
                            lineWidth: max(1, side * 0.004)
                        )
                        .frame(width: baseRadius * CGFloat(2.2 + Double(index) * 0.58),
                               height: baseRadius * CGFloat(2.2 + Double(index) * 0.58))
                        .scaleEffect(isPlaying && pulse ? 1.12 + CGFloat(index) * 0.04 : 0.94)
                        .opacity(isPlaying ? 1 : 0.45)
                        .animation(
                            .easeInOut(duration: 1.4 + Double(index) * 0.22)
                                .repeatForever(autoreverses: true),
                            value: pulse
                        )
                }

                ForEach(0..<32, id: \.self) { index in
                    let fraction = Double(index) / 32.0
                    let height = side * CGFloat(0.08 + (index % 5 == 0 ? 0.08 : 0.035))
                    Capsule()
                        .fill(Color(hue: 0.56 + fraction * 0.18, saturation: 0.72, brightness: 0.96).opacity(0.62))
                        .frame(width: max(2, side * 0.005), height: height)
                        .offset(y: -baseRadius * 1.58)
                        .rotationEffect(.degrees(fraction * 360))
                        .scaleEffect(y: isPlaying && pulse ? 1.24 : 0.72, anchor: .center)
                        .animation(
                            .easeInOut(duration: 0.9 + Double(index % 7) * 0.08)
                                .repeatForever(autoreverses: true),
                            value: pulse
                        )
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.95), Theme.accent.opacity(0.78), .cyan.opacity(0.25), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: baseRadius
                        )
                    )
                    .frame(width: baseRadius * 1.5, height: baseRadius * 1.5)
                    .scaleEffect(isPlaying && pulse ? 1.08 : 0.96)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .position(x: geo.size.width / 2, y: centerY)
            .onAppear { pulse = true }
            .onChangeCompat(of: isPlaying) { _, playing in
                guard playing else { return }
                pulse = false
                DispatchQueue.main.async { pulse = true }
            }
        }
        .ignoresSafeArea()
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
        var usesNativeSliderInteraction = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            showsVolumeSlider = true
            backgroundColor = .clear
            clipsToBounds = false
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            showsVolumeSlider = true
            backgroundColor = .clear
            clipsToBounds = false
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let slider = RuntimeCompatibility.isIOS16
                ? Self.firstVolumeSlider(in: self)
                : subviews.compactMap { $0 as? UISlider }.first
            guard let slider else { return }

            if RuntimeCompatibility.isIOS16 {
                for subview in subviews where subview !== slider && !slider.isDescendant(of: subview) {
                    subview.isHidden = true
                    subview.frame = .zero
                }
                slider.superview?.isHidden = false
                slider.superview?.alpha = 1
                slider.isHidden = false
                slider.alpha = 1
                slider.isEnabled = true
                slider.isUserInteractionEnabled = usesNativeSliderInteraction
                if slider.superview === self {
                    slider.frame = bounds
                } else {
                    slider.superview?.frame = bounds
                    slider.frame = slider.superview?.bounds ?? bounds
                }
            } else {
                for subview in subviews where subview !== slider {
                    subview.isHidden = true
                    subview.frame = .zero
                }
                slider.isHidden = false
                slider.alpha = 1
                slider.isEnabled = true
                // MPVolumeView's slider jumps to a tapped track location. Route touch
                // changes through our pan gesture so press/release does not change volume.
                slider.isUserInteractionEnabled = false
                slider.frame = bounds
            }
        }

        fileprivate static func firstVolumeSlider(in view: UIView) -> UISlider? {
            if let slider = view as? UISlider {
                return slider
            }
            for subview in view.subviews {
                if let slider = firstVolumeSlider(in: subview) {
                    return slider
                }
            }
            return nil
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(isInteracting: $isInteracting) }

    func makeUIView(context: Context) -> SliderOnlyVolumeView {
        let v = SliderOnlyVolumeView()
        v.usesNativeSliderInteraction = RuntimeCompatibility.isIOS16
        v.showsVolumeSlider = true
        v.tintColor = .white
        v.setMinimumVolumeSliderImage(Self.trackImage(color: UIColor.white.withAlphaComponent(0.92)), for: .normal)
        v.setMaximumVolumeSliderImage(Self.trackImage(color: UIColor.white.withAlphaComponent(0.24)), for: .normal)
        v.setVolumeThumbImage(Self.thumbImage(highlighted: false), for: .normal)
        v.setVolumeThumbImage(Self.thumbImage(highlighted: true), for: .highlighted)
        context.coordinator.volumeView = v
        DispatchQueue.main.async {
            v.setNeedsLayout()
            v.layoutIfNeeded()
        }
        if !RuntimeCompatibility.isIOS16 {
            let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
            pan.cancelsTouchesInView = true
            v.addGestureRecognizer(pan)
        }
        return v
    }
    func updateUIView(_ uiView: SliderOnlyVolumeView, context: Context) {
        uiView.usesNativeSliderInteraction = RuntimeCompatibility.isIOS16
        uiView.showsVolumeSlider = true
        uiView.setNeedsLayout()
    }

    private static func trackImage(color: UIColor) -> UIImage {
        let size = CGSize(width: 4, height: 4)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            color.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 2).fill()
        }
        return image.resizableImage(withCapInsets: UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2))
    }

    private static func thumbImage(highlighted: Bool) -> UIImage {
        let diameter: CGFloat = highlighted ? 16 : 14
        let size = CGSize(width: diameter, height: diameter)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            UIColor.white.withAlphaComponent(highlighted ? 1 : 0.96).setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
        }
    }

    final class Coordinator: NSObject {
        weak var volumeView: MPVolumeView?
        private var isInteracting: Binding<Bool>
        private var panStartVolume: Float = 0
        private var panActive = false

        init(isInteracting: Binding<Bool>) {
            self.isInteracting = isInteracting
        }

        private var slider: UISlider? {
            guard let volumeView else { return nil }
            if RuntimeCompatibility.isIOS16 {
                return SliderOnlyVolumeView.firstVolumeSlider(in: volumeView)
            }
            return volumeView.subviews.compactMap { $0 as? UISlider }.first
        }

        // Only gestures that start on the real slider track should affect volume.
        private func onTrack(_ point: CGPoint, _ slider: UISlider) -> Bool {
            point.x >= 0 && point.x <= slider.bounds.width
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
                Text(status?.status ?? L(.signal_lossless_audio)).font(.headline)
            }
            .padding(.bottom, 2)

            if let status {
                detailRow(L(.signal_output), status.output)
                detailRow(L(.signal_why), status.reason)
            }
            if let format { detailRow(L(.media_format), format) }
            if let rate = song?.bitRate { detailRow(L(.detail_bitrate), "\(rate) kbps") }
            if let sr = song?.samplingRate {
                detailRow(L(.detail_sample_rate), String(format: "%.1f kHz", Double(sr) / 1000))
            }
            if let bd = song?.bitDepth { detailRow(L(.detail_bit_depth), L(.detail_bit_value, bd)) }

            Divider().padding(.vertical, 2)

            Button(action: onOpenSignalPath) {
                Label(L(.signal_path_title), systemImage: "point.3.connected.trianglepath.dotted")
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
                Section(L(.signal_source_file)) {
                    row(L(.smart_sort_title), song?.title)
                    row(L(.media_format), fileFormat)
                    row(L(.detail_bitrate), song?.bitRate.map { "\($0) kbps" })
                    row(L(.detail_sample_rate), song?.samplingRate.map(formatSampleRate))
                    row(L(.detail_bit_depth), song?.bitDepth.map { L(.detail_bit_value, $0) })
                    row(L(.quality_lossless), song?.isLossless == true ? L(.action_yes) : L(.action_no))
                }

                Section(L(.signal_server_stream)) {
                    row(L(.signal_transcoding), transcodingFormat == "raw" ? L(.signal_original) : transcodingFormat.uppercased())
                    row(L(.signal_wifi_quality), bitrateLabel(streamingBitrate))
                    row(L(.signal_cellular_quality), streamingBitrateCell == 0 ? L(.signal_same_as_wifi) : bitrateLabel(streamingBitrateCell))
                }

                Section(L(.signal_app_processing)) {
                    row(L(.signal_volume_norm), replayGainLabel)
                    row(L(.media_equalizer), EqualizerEngine.shared.isEnabled ? L(.action_on) : L(.action_off))
                }

                Section(L(.signal_output)) {
                    row(L(.signal_output), outputName)
                    row(L(.signal_port_type), outputPortTypes)
                    row(L(.signal_output_sample_rate), session.sampleRate > 0 ? formatSampleRate(Int(session.sampleRate.rounded())) : nil)
                    row(L(.signal_output_channels), session.outputNumberOfChannels > 0 ? "\(session.outputNumberOfChannels)" : nil)
                }

                Section(L(.signal_result)) {
                    row(L(.signal_badge), status?.status ?? L(.signal_not_lossless))
                    row(L(.signal_why), status?.reason)
                }
            }
            .navigationTitle(L(.signal_path_title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L(.action_done)) { dismiss() }
                }
            }
        }
        .preferredColorScheme(Theme.colorScheme)
    }

    private var fileFormat: String? {
        song?.suffix?.uppercased() ?? song?.contentType
    }

    @MainActor
    private var replayGainLabel: String {
        switch replayGainMode {
        case "off": L(.action_off)
        case "album": L(.media_album)
        default: replayGainMode.capitalized
        }
    }

    @MainActor
    private var outputName: String {
        let names = session.currentRoute.outputs.map(\.portName).filter { !$0.isEmpty }
        return names.isEmpty ? L(.signal_system_output) : names.joined(separator: ", ")
    }

    private var outputPortTypes: String? {
        let types = session.currentRoute.outputs.map { $0.portType.rawValue }.filter { !$0.isEmpty }
        return types.isEmpty ? nil : types.joined(separator: ", ")
    }

    @MainActor
    private func bitrateLabel(_ value: Int) -> String {
        value == 0 ? L(.signal_original) : "\(value) kbps"
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
