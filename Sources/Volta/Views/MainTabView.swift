import SwiftUI
import UIKit

private enum PlayerPresentationPhase {
    case mini
    case expanding
    case expanded
    case dragging
    case collapsing
    case cancelling
}

#if DEBUG
private extension PlayerPresentationPhase {
    var debugName: String {
        switch self {
        case .mini: return "mini"
        case .expanding: return "expanding"
        case .expanded: return "expanded"
        case .dragging: return "dragging"
        case .collapsing: return "collapsing"
        case .cancelling: return "cancelling"
        }
    }
}
#endif

private let playerDismissalDuration: Double = 0.54

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("accentColorName") private var accentColorName = "purple"
    @AppStorage("customAccentRed") private var customAccentRed = 0.55
    @AppStorage("customAccentGreen") private var customAccentGreen = 0.36
    @AppStorage("customAccentBlue") private var customAccentBlue = 0.96
    @AppStorage("developerPerformanceOverlay") private var developerPerformanceOverlay = false
    @AppStorage("stylizedPlayerCover") private var stylizedPlayerCover = false
    @AppStorage("artworkAnimation") private var artworkAnimation = true
    @State private var selectedTab = 0
    @State private var showNowPlaying = false
    @State private var playerOverlayMounted = false
    @State private var playerExpansionProgress: CGFloat = 0
    @State private var miniPlayerFrame: CGRect = .zero
    @State private var miniArtworkFrame: CGRect = .zero
    @State private var miniTransitionGeometry = MiniPlayerTransitionGeometry()
    @State private var miniPlayerPlacement: MiniPlayerAccessoryPlacement = .undefined
    @State private var miniPlayerFramesByPlacement: [MiniPlayerAccessoryPlacement: CGRect] = [:]
    @State private var miniGeometriesByPlacement: [MiniPlayerAccessoryPlacement: MiniPlayerTransitionGeometry] = [:]
    @State private var playerDismissDestinationFrame: CGRect = .zero
    @State private var playerDismissDestinationGeometry = MiniPlayerTransitionGeometry()
    @State private var expandedArtworkFrame: CGRect = .zero
    @State private var playerSnapshot: PlayerTransitionSnapshot?
    @State private var playerPresentationTask: Task<Void, Never>?
    @State private var miniPlayerLandingTask: Task<Void, Never>?
    @State private var isPlayerTransitioning = false
    @State private var isPlayerDismissGestureActive = false
    @State private var isCompletingPlayerDismiss = false
    @State private var isCancellingPlayerDismiss = false
    @State private var playerDismissStartProgress: CGFloat = 1
    @State private var playerDismissTravelOffset: CGFloat = 0
    @State private var playerDismissAnimationProgress: CGFloat = 0
    @State private var playerDismissReleaseOffset: CGFloat = 0
    @State private var playerDismissDestinationOffset: CGFloat = 0
    @State private var playerDismissInitialVelocity: CGFloat = 0
    @State private var playerPresentationPhase: PlayerPresentationPhase = .mini
    @State private var miniPlayerLandingTextScale: CGFloat = 1
    @State private var miniPlayerLandingTextOffset: CGFloat = 0
#if DEBUG
    @State private var expandedDismissDebugGeometry = PlayerDismissDebugGeometry()
    @State private var lastDismissDebugGeometry = PlayerDismissDebugGeometry()
    @State private var lastRenderedDismissGeometry = PlayerDismissRenderedGeometry()
#endif

    @State private var homePath = NavigationPath()
    @State private var libraryPath = NavigationPath()
    @State private var playlistsPath = NavigationPath()
    @State private var searchPath = NavigationPath()
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var audio: AudioPlayer { appState.audioPlayer }
    private var shouldShowMiniPlayer: Bool {
        audio.hasActivePlaybackSession && audio.currentSong != nil
    }
    private var reducesPlayerMotion: Bool {
        accessibilityReduceMotion || PerformanceMode.reduceAnimations
    }
    private var playerPresentationDuration: Double {
        reducesPlayerMotion ? 0.16 : 0.52
    }
    private func playerPresentationAnimation(duration: Double) -> Animation {
        if reducesPlayerMotion {
            return .easeOut(duration: duration)
        }
        return .spring(
            response: max(0.30, duration),
            dampingFraction: 0.88,
            blendDuration: 0.08
        )
    }
    private func playerPresentationSettleDelay(for duration: Double) -> Double {
        reducesPlayerMotion ? duration + 0.02 : max(0.30, duration) + 0.10
    }
    private func playerDismissFlightDuration(for progress: CGFloat) -> Double {
        if reducesPlayerMotion { return 0.16 }
        return max(0.14, 0.42 * Double(min(max(progress, 0), 1)))
    }
    private func playerDismissFlightAnimation(duration: Double) -> Animation {
        reducesPlayerMotion ? .easeOut(duration: duration) : .easeInOut(duration: duration)
    }
    private var usesPhysicalPlayerDismissal: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
            && horizontalSizeClass != .regular
            && verticalSizeClass != .compact
            && !reducesPlayerMotion
    }
    private var isPhysicalPlayerDismissalActive: Bool {
        usesPhysicalPlayerDismissal
            && (playerPresentationPhase == .dragging
                || playerPresentationPhase == .collapsing
                || playerPresentationPhase == .cancelling)
    }
    private var showsRealMiniPlayer: Bool {
        playerPresentationPhase == .mini
    }
    private var tabSelection: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { value in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    selectedTab = value
                }
            }
        )
    }
    private var accentRefreshKey: String {
        "\(accentColorName)-\(customAccentRed)-\(customAccentGreen)-\(customAccentBlue)"
    }

    var body: some View {
        GeometryReader { rootGeo in
            ZStack {
                tabContent

                if playerOverlayMounted, let playerSnapshot {
                    PlayerDismissalMotionAnimator(
                        interactiveTravelOffset: playerDismissTravelOffset,
                        animationProgress: playerDismissAnimationProgress,
                        releaseOffset: playerDismissReleaseOffset,
                        destinationOffset: playerDismissDestinationOffset,
                        normalizedInitialVelocity: playerDismissInitialVelocity,
                        isCollapsing: playerPresentationPhase == .collapsing,
                        neutralizesInheritedAnimation: isPhysicalPlayerDismissalActive
                    ) { motion in
                        ZStack {
                            PlayerExpansionAnimator(
                                progress: playerExpansionProgress,
                                isTransitioning: isPlayerTransitioning || isPlayerDismissGestureActive
                            ) { progress in
                                PlayerExpansionOverlay(
                                    progress: progress,
                                    sourceFrame: miniPlayerFrame,
                                    sourceArtworkFrame: miniArtworkFrame,
                                    safeAreaInsets: rootGeo.safeAreaInsets,
                                    snapshot: playerSnapshot,
                                    reduceMotion: reducesPlayerMotion,
                                    isInteractiveDismissal: isPlayerDismissGestureActive,
                                    isCompletingDismissal: isCompletingPlayerDismiss,
                                    isCancellingDismissal: isCancellingPlayerDismiss,
                                    dismissalStartProgress: playerDismissStartProgress,
                                    dismissalTravel: playerDismissTravel
                                )
                                .opacity(isPhysicalPlayerDismissalActive ? 0 : 1)
                            }
                            .allowsHitTesting(false)
                            .zIndex(0)

                            PlayerExpansionAnimator(
                                progress: playerExpansionProgress,
                                isTransitioning: isPlayerTransitioning || isPlayerDismissGestureActive
                            ) { progress in
                                let reveal = playerContentOpacity(for: progress)
                                playerScreen(
                                    progress: progress,
                                    reveal: reveal,
                                    dismissTravelOffset: motion.travelOffset,
                                    dismissMorphProgress: motion.morphProgress,
                                    safeAreaInsets: rootGeo.safeAreaInsets
                                )
                            }
                            .allowsHitTesting(
                                isPlayerDismissGestureActive
                                    || (!isPlayerTransitioning && playerExpansionProgress >= 0.999)
                            )
                            .accessibilityHidden(isPlayerTransitioning)
                            .zIndex(1)

                            if isPhysicalPlayerDismissalActive {
                                PlayerDismissalOverlay(
                                    travelOffset: motion.travelOffset,
                                    morphProgress: motion.morphProgress,
                                    sourceFrame: playerDismissDestinationFrame,
                                    sourceArtworkFrame: miniArtworkFrame,
                                    expandedArtworkFrame: expandedArtworkFrame,
                                    miniGeometry: playerDismissDestinationGeometry,
                                    safeAreaInsets: rootGeo.safeAreaInsets,
                                    snapshot: playerSnapshot,
                                    isInteractive: isPlayerDismissGestureActive,
                                    isCompleting: isCompletingPlayerDismiss,
                                    onRenderedGeometryChange: recordRenderedDismissGeometry
                                )
                                .allowsHitTesting(false)
                                .zIndex(2)
                            }
                        }
                    }
                    .zIndex(9)
                }

                if developerPerformanceOverlay {
                    PerformanceOverlay()
                        .padding(.horizontal, 10)
                        .padding(.top, 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .allowsHitTesting(false)
                        .zIndex(20)
                }
            }
            .frame(width: rootGeo.size.width, height: rootGeo.size.height)
        }
        .animation(.easeInOut(duration: 0.2), value: accentRefreshKey)
        .preferredColorScheme(Theme.colorScheme)
        .onAppear {
            AppDiagnostics.logMainTabDecision()
            if appState.requestedWidgetStatsDestination != nil {
                tabSelection.wrappedValue = 3
            }
        }
        .onDisappear {
            playerPresentationTask?.cancel()
            playerPresentationTask = nil
            miniPlayerLandingTask?.cancel()
            miniPlayerLandingTask = nil
        }
        .onChangeCompat(of: appState.requestedWidgetStatsDestination) { _, destination in
            guard destination != nil else { return }
            tabSelection.wrappedValue = 3
        }
        .onChangeCompat(of: shouldShowMiniPlayer) { _, available in
            guard !available else { return }
            playerPresentationTask?.cancel()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                showNowPlaying = false
                playerOverlayMounted = false
                playerExpansionProgress = 0
                playerSnapshot = nil
                isPlayerTransitioning = false
                isPlayerDismissGestureActive = false
                isCompletingPlayerDismiss = false
                isCancellingPlayerDismiss = false
                playerDismissTravelOffset = 0
                playerDismissAnimationProgress = 0
                playerDismissDestinationFrame = .zero
                playerDismissDestinationGeometry = MiniPlayerTransitionGeometry()
                playerPresentationPhase = .mini
                miniPlayerLandingTextScale = 1
                miniPlayerLandingTextOffset = 0
            }
        }
    }

    @ViewBuilder
    private func playerScreen(
        progress: CGFloat,
        reveal: CGFloat,
        dismissTravelOffset: CGFloat,
        dismissMorphProgress: CGFloat,
        safeAreaInsets: EdgeInsets
    ) -> some View {
        let screen = NowPlayingScreen(
            isPresented: nowPlayingPresentationBinding,
            onDismissDragChanged: updatePlayerDismissDrag,
            onDismissDragCancelled: cancelPlayerDismissDrag,
            onDismissDragEnded: { offset, predictedOffset in
                dismissNowPlaying(from: offset, predictedOffset: predictedOffset)
            },
            onArtworkFrameChange: recordExpandedArtworkFrame,
            onDismissDebugGeometryChange: { geometry in
                recordPlayerDismissDebugGeometry(
                    geometry,
                    safeAreaTop: safeAreaInsets.top
                )
            },
            stableSafeAreaInsets: safeAreaInsets,
            hidesArtworkForDismissal: usesPhysicalPlayerDismissal
                && playerPresentationPhase == .collapsing
        )
        .opacity(reveal)
        .offset(
            y: isPhysicalPlayerDismissalActive
                ? dismissTravelOffset
                : playerContentVerticalOffset(for: progress)
        )

        screen.mask {
            if isPhysicalPlayerDismissalActive {
                PlayerDismissalClipMask(
                    travelOffset: dismissTravelOffset,
                    morphProgress: dismissMorphProgress,
                    destinationFrame: playerDismissDestinationFrame,
                    safeAreaInsets: safeAreaInsets,
                    isInteractive: isPlayerDismissGestureActive
                )
            } else if usesDirectDismissalPresentation {
                Rectangle().ignoresSafeArea()
            } else {
                PlayerExpansionClipMask(
                    progress: progress,
                    sourceFrame: miniPlayerFrame,
                    safeAreaInsets: safeAreaInsets,
                    reduceMotion: reducesPlayerMotion
                )
            }
        }
    }

    private var usesDirectDismissalPresentation: Bool {
        isPlayerDismissGestureActive || isCompletingPlayerDismiss || isCancellingPlayerDismiss
    }

    @ViewBuilder
    private var tabContent: some View {
        if #available(iOS 26.0, *) {
            modernTabs
        } else {
            legacyTabs
        }
    }

    @available(iOS 26.0, *)
    @ViewBuilder
    private var modernTabs: some View {
        if #available(iOS 26.1, *) {
            modernTabView
                .tabViewBottomAccessory(isEnabled: shouldShowMiniPlayer) {
                    modernMiniPlayerAccessory
                }
        } else {
            modernTabView
                .modifier(ModernMiniPlayerModifier(shouldShow: shouldShowMiniPlayer) {
                    modernMiniPlayerAccessory
                })
        }
    }

    @available(iOS 26.0, *)
    private var modernTabView: some View {
        TabView(selection: tabSelection) {
            Tab(L(.tab_home), systemImage: Symbols.home, value: 0) {
                HomeView(path: $homePath)
            }
            Tab(L(.tab_library), systemImage: Symbols.library, value: 1) {
                LibraryView(path: $libraryPath, isTabActive: selectedTab == 1)
            }
            Tab(L(.tab_playlists), systemImage: Symbols.playlists, value: 2) {
                PlaylistsView(path: $playlistsPath)
            }
            Tab(L(.tab_stats), systemImage: Symbols.stats, value: 3) {
                StatsView()
            }
            Tab(L(.tab_search), systemImage: Symbols.search, value: 4, role: .search) {
                SearchView(path: $searchPath)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Theme.accent)
    }

    @available(iOS 26.0, *)
    @ViewBuilder
    private var modernMiniPlayerAccessory: some View {
        ModernMiniPlayerAccessory(
            onExpand: presentNowPlaying,
            onArtworkFrameChange: recordMiniArtworkFrame,
            onTransitionGeometryChange: recordMiniTransitionGeometry,
            onSurfaceFrameChange: recordMiniPlayerFrame,
            onSwiftUIFrameChange: recordMiniPlayerSwiftUIFrame,
            landingTextScale: miniPlayerLandingTextScale,
            landingTextOffset: miniPlayerLandingTextOffset,
            isVisible: showsRealMiniPlayer
        )
    }

    private var legacyTabs: some View {
        TabView(selection: tabSelection) {
            legacyTabPage {
                HomeView(path: $homePath)
            }
                .tabItem { Label(L(.tab_home), systemImage: Symbols.home) }
                .tag(0)

            legacyTabPage {
                LibraryView(path: $libraryPath, isTabActive: selectedTab == 1)
            }
                .tabItem { Label(L(.tab_library), systemImage: Symbols.library) }
                .tag(1)

            legacyTabPage {
                PlaylistsView(path: $playlistsPath)
            }
                .tabItem { Label(L(.tab_playlists), systemImage: Symbols.playlists) }
                .tag(2)

            legacyTabPage {
                StatsView()
            }
                .tabItem { Label(L(.tab_stats), systemImage: Symbols.stats) }
                .tag(3)

            legacyTabPage {
                SearchView(path: $searchPath)
            }
                .tabItem { Label(L(.tab_search), systemImage: Symbols.search) }
                .tag(4)
        }
        .tint(Theme.accent)
    }

    private func legacyTabPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                legacyMiniPlayer
            }
    }

    @ViewBuilder
    private var legacyMiniPlayer: some View {
        if shouldShowMiniPlayer {
            MiniPlayerAccessory(
                onExpand: presentNowPlaying,
                onArtworkFrameChange: recordMiniArtworkFrame,
                onTransitionGeometryChange: recordMiniTransitionGeometry,
                placement: .legacy,
                landingTextScale: miniPlayerLandingTextScale,
                landingTextOffset: miniPlayerLandingTextOffset
            )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 10)
                .reportPlayerAccessoryFrame { frame in
                    recordMiniPlayerFrame(frame, placement: .legacy)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
                .opacity(showsRealMiniPlayer ? 1 : 0)
                .allowsHitTesting(showsRealMiniPlayer)
                .accessibilityHidden(!showsRealMiniPlayer)
        }
    }

    private func presentNowPlaying() {
        guard !playerOverlayMounted,
              let song = audio.currentSong else { return }
        AppLogger.shared.log(
            "Player expanded from mini player; songID=\(song.id)",
            category: .playback
        )

        playerPresentationTask?.cancel()
        miniPlayerLandingTask?.cancel()
        var resetLanding = Transaction()
        resetLanding.disablesAnimations = true
        withTransaction(resetLanding) {
            miniPlayerLandingTextScale = 1
            miniPlayerLandingTextOffset = 0
        }
        let snapshot = PlayerTransitionSnapshot(
            title: song.title,
            artist: song.artist ?? "",
            artwork: audio.currentLiveArtwork?.previewImage ?? audio.currentArtwork,
            isPlaying: audio.isPlaying,
            targetArtworkScale: transitionArtworkScale(usesFullBleedArtwork: usesFullBleedArtwork),
            usesFullBleedArtwork: usesFullBleedArtwork
        )

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            playerSnapshot = snapshot
            playerExpansionProgress = 0
            playerOverlayMounted = true
            showNowPlaying = true
            isPlayerTransitioning = true
            isPlayerDismissGestureActive = false
            isCompletingPlayerDismiss = false
            isCancellingPlayerDismiss = false
            playerDismissTravelOffset = 0
            playerDismissAnimationProgress = 0
            playerPresentationPhase = .expanding
        }

        playerPresentationTask = Task { @MainActor in
            // Give the transition layer one render pass at the mini-player
            // endpoint before beginning the spring.
            await Task.yield()
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(playerPresentationAnimation(duration: playerPresentationDuration)) {
                playerExpansionProgress = 1
            }
            try? await Task.sleep(
                nanoseconds: UInt64(
                    playerPresentationSettleDelay(for: playerPresentationDuration)
                        * 1_000_000_000
                )
            )
            guard !Task.isCancelled else { return }
            isPlayerTransitioning = false
            playerPresentationPhase = .expanded
            playerPresentationTask = nil
        }
    }

    private var nowPlayingPresentationBinding: Binding<Bool> {
        Binding(
            get: { showNowPlaying },
            set: { value in
                if value {
                    showNowPlaying = true
                } else {
                    dismissNowPlaying()
                }
            }
        )
    }

    private func dismissNowPlaying(
        from dragOffset: CGFloat? = nil,
        predictedOffset: CGFloat? = nil
    ) {
        guard playerOverlayMounted else {
            showNowPlaying = false
            return
        }

        playerPresentationTask?.cancel()
        if let currentSong = audio.currentSong {
            let refreshedSnapshot = PlayerTransitionSnapshot(
                title: currentSong.title,
                artist: currentSong.artist ?? "",
                artwork: audio.currentLiveArtwork?.previewImage ?? audio.currentArtwork,
                isPlaying: audio.isPlaying,
                targetArtworkScale: transitionArtworkScale(
                    usesFullBleedArtwork: usesFullBleedArtwork
                ),
                usesFullBleedArtwork: usesFullBleedArtwork
            )
            var snapshotTransaction = Transaction()
            snapshotTransaction.disablesAnimations = true
            withTransaction(snapshotTransaction) {
                playerSnapshot = refreshedSnapshot
            }
        }

        if usesPhysicalPlayerDismissal {
            let releaseOffset = max(0, dragOffset ?? 0)
            let capturedFrame = miniPlayerFrame
            let capturedGeometry = miniTransitionGeometry
            let destination = playerDismissTravel(to: capturedFrame)
            let projectedOffset = max(releaseOffset, predictedOffset ?? releaseOffset)
            let projectedVelocity = max(0, projectedOffset - releaseOffset) / 0.22
            let remainingTravel = max(destination - releaseOffset, 1)
            // Analytical spring consumes unit-distance velocity per second.
            // Keep a fast baseline after threshold drags, then add measured flick momentum.
            let normalizedVelocity = min(
                max(10 + projectedVelocity / remainingTravel, 10),
                14
            )

            var startTransaction = Transaction()
            startTransaction.disablesAnimations = true
            withTransaction(startTransaction) {
                showNowPlaying = true
                isPlayerTransitioning = true
                isPlayerDismissGestureActive = false
                isCompletingPlayerDismiss = true
                isCancellingPlayerDismiss = false
                playerExpansionProgress = 1
                playerDismissTravelOffset = releaseOffset
                playerDismissAnimationProgress = 0
                playerDismissReleaseOffset = releaseOffset
                playerDismissDestinationOffset = destination
                playerDismissInitialVelocity = normalizedVelocity
                playerDismissDestinationFrame = capturedFrame
                playerDismissDestinationGeometry = capturedGeometry
                playerPresentationPhase = .collapsing
            }
#if DEBUG
            logCollapseCapture(
                frame: capturedFrame,
                geometry: capturedGeometry,
                destinationOffset: destination
            )
#endif

            playerPresentationTask = Task { @MainActor in
                // Establish the collapsing hierarchy at the exact release
                // geometry for one render pass. Travel and morph then start
                // together from the same animatable clock.
                await Task.yield()
                try? await Task.sleep(nanoseconds: 16_000_000)
                guard !Task.isCancelled,
                      playerPresentationPhase == .collapsing else { return }
                withAnimation(.linear(duration: playerDismissalDuration)) {
                    playerDismissAnimationProgress = 1
                }
                try? await Task.sleep(
                    nanoseconds: UInt64(playerDismissalDuration * 1_000_000_000)
                )
                guard !Task.isCancelled else { return }

                // Clamp every transition value to the measured destination,
                // then keep that exact visual state mounted for a display
                // frame before changing ownership to the real mini player.
                var landing = Transaction()
                landing.disablesAnimations = true
                withTransaction(landing) {
                    playerDismissAnimationProgress = 1
                    playerDismissTravelOffset = destination
                }
                try? await Task.sleep(nanoseconds: 34_000_000)
                guard !Task.isCancelled else { return }

                var handoff = Transaction()
                handoff.disablesAnimations = true
                withTransaction(handoff) {
                    showNowPlaying = false
                    playerOverlayMounted = false
                    playerExpansionProgress = 0
                    playerDismissTravelOffset = 0
                    playerDismissAnimationProgress = 0
                    playerSnapshot = nil
                    isPlayerTransitioning = false
                    isPlayerDismissGestureActive = false
                    isCompletingPlayerDismiss = false
                    isCancellingPlayerDismiss = false
                    playerPresentationPhase = .mini
                }
#if DEBUG
                await Task.yield()
                logRealMiniPlayerAfterHandoff()
#endif
                playerPresentationTask = nil
            }
            return
        }

        let startProgress = dragOffset.map { interactivePlayerProgress(for: $0) }
            ?? playerExpansionProgress
        let duration = playerDismissFlightDuration(for: startProgress)

        var startTransaction = Transaction()
        startTransaction.disablesAnimations = true
        withTransaction(startTransaction) {
            showNowPlaying = false
            isPlayerTransitioning = true
            isPlayerDismissGestureActive = false
            isCompletingPlayerDismiss = true
            isCancellingPlayerDismiss = false
            playerDismissStartProgress = startProgress
            playerExpansionProgress = startProgress
            playerPresentationPhase = .collapsing
        }

        withAnimation(playerDismissFlightAnimation(duration: duration)) {
            playerExpansionProgress = 0
        }

        playerPresentationTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: UInt64((duration + 0.02) * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            var handoff = Transaction()
            handoff.disablesAnimations = true
            withTransaction(handoff) {
                playerOverlayMounted = false
                playerExpansionProgress = 0
                playerSnapshot = nil
                isPlayerTransitioning = false
                isPlayerDismissGestureActive = false
                isCompletingPlayerDismiss = false
                isCancellingPlayerDismiss = false
                playerPresentationPhase = .mini
            }
            playerPresentationTask = nil
            playMiniPlayerLandingBounce()
        }
    }

    private func updatePlayerDismissDrag(_ translation: CGFloat) {
        guard playerOverlayMounted, !isPlayerTransitioning else { return }
        let offset = max(0, translation)
        let startsPhysicalDrag = usesPhysicalPlayerDismissal
            && offset > 0
            && playerPresentationPhase != .dragging
        playerPresentationTask?.cancel()
        playerPresentationTask = nil

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isPlayerDismissGestureActive = offset > 0
            isCompletingPlayerDismiss = false
            isCancellingPlayerDismiss = false
            playerPresentationPhase = offset > 0 ? .dragging : .expanded
            if usesPhysicalPlayerDismissal {
                if startsPhysicalDrag {
                    playerDismissDestinationFrame = miniPlayerFrame
                    playerDismissDestinationGeometry = miniTransitionGeometry
                }
                playerExpansionProgress = 1
                playerDismissTravelOffset = offset
                playerDismissAnimationProgress = 0
            } else {
                playerExpansionProgress = interactivePlayerProgress(for: offset)
            }
        }
    }

    private func cancelPlayerDismissDrag() {
        guard playerOverlayMounted, isPlayerDismissGestureActive else { return }
        playerPresentationTask?.cancel()

        if usesPhysicalPlayerDismissal {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isPlayerDismissGestureActive = false
                isPlayerTransitioning = true
                isCompletingPlayerDismiss = false
                isCancellingPlayerDismiss = true
                playerDismissAnimationProgress = 0
                playerPresentationPhase = .cancelling
            }

            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                playerDismissTravelOffset = 0
            }

            playerPresentationTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 440_000_000)
                guard !Task.isCancelled else { return }
                var finish = Transaction()
                finish.disablesAnimations = true
                withTransaction(finish) {
                    playerDismissTravelOffset = 0
                    isPlayerTransitioning = false
                    isCancellingPlayerDismiss = false
                    playerPresentationPhase = .expanded
                }
                playerPresentationTask = nil
            }
            return
        }

        let duration = playerPresentationDuration * Double(1 - playerExpansionProgress)

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isPlayerDismissGestureActive = false
            isPlayerTransitioning = true
            isCompletingPlayerDismiss = false
            isCancellingPlayerDismiss = true
            playerDismissStartProgress = playerExpansionProgress
            playerPresentationPhase = .cancelling
        }

        withAnimation(playerPresentationAnimation(duration: duration)) {
            playerExpansionProgress = 1
        }

        playerPresentationTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: UInt64(
                    playerPresentationSettleDelay(for: duration) * 1_000_000_000
                )
            )
            guard !Task.isCancelled else { return }
            isPlayerTransitioning = false
            isCancellingPlayerDismiss = false
            playerPresentationPhase = .expanded
            playerPresentationTask = nil
        }
    }

    private var playerDismissTravel: CGFloat {
        playerDismissTravel(to: miniPlayerFrame)
    }

    private func playerDismissTravel(to frame: CGRect) -> CGFloat {
        if frame.isMeaningful { return max(1, frame.minY) }
        let windowHeight = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \UIWindow.isKeyWindow)?
            .bounds.height
        return max(1, (windowHeight ?? 800) * 0.82)
    }

    private func interactivePlayerProgress(for offset: CGFloat) -> CGFloat {
        min(max(1 - offset / playerDismissTravel, 0), 1)
    }

    private func playerContentVerticalOffset(for progress: CGFloat) -> CGFloat {
        guard isPlayerDismissGestureActive || isCompletingPlayerDismiss || isCancellingPlayerDismiss else {
            return 0
        }
        return playerDismissTravel * (1 - min(max(progress, 0), 1))
    }

    private func playerContentOpacity(for progress: CGFloat) -> CGFloat {
        if reducesPlayerMotion { return progress }
        if isPlayerDismissGestureActive { return 1 }

        let restingOpacity = playerFullContentOpacity(progress)
        if isCompletingPlayerDismiss {
            let handoffProgress = 1 - min(
                max(progress / max(playerDismissStartProgress, 0.001), 0),
                1
            )
            let handoff = smoothStep(handoffProgress, from: 0.08, to: 0.45)
            return 1 + (restingOpacity - 1) * handoff
        }
        if isCancellingPlayerDismiss {
            let travel = max(1 - playerDismissStartProgress, 0.001)
            let recoveryProgress = min(
                max((progress - playerDismissStartProgress) / travel, 0),
                1
            )
            return 1 + (restingOpacity - 1) * recoveryProgress
        }
        return restingOpacity
    }

    private func playMiniPlayerLandingBounce() {
        guard !reducesPlayerMotion else { return }

        miniPlayerLandingTask?.cancel()
        withAnimation(.easeIn(duration: 0.06)) {
            miniPlayerLandingTextScale = 0.94
            miniPlayerLandingTextOffset = 1
        }
        miniPlayerLandingTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.26, dampingFraction: 0.62)) {
                miniPlayerLandingTextScale = 1
                miniPlayerLandingTextOffset = 0
            }
            miniPlayerLandingTask = nil
        }
    }

    private func recordMiniPlayerFrame(
        _ frame: CGRect,
        placement: MiniPlayerAccessoryPlacement
    ) {
#if DEBUG
        logMiniGeometry("REAL_REPORTER", frame: frame, placement: placement)
#endif
        guard frame.isMeaningful else { return }
        miniPlayerFramesByPlacement[placement] = frame
        guard !isPlayerTransitioning,
              let geometry = miniGeometriesByPlacement[placement],
              geometry.isMeaningful else { return }
        activateMiniPlayerDestination(
            frame: frame,
            geometry: geometry,
            placement: placement
        )
    }

    private func recordMiniArtworkFrame(_ frame: CGRect) {
        guard !isPlayerTransitioning, frame.isMeaningful else { return }
        if !miniArtworkFrame.isApproximatelyEqual(to: frame) {
            miniArtworkFrame = frame
        }
    }

    private func recordMiniTransitionGeometry(_ geometry: MiniPlayerTransitionGeometry) {
        guard geometry.isMeaningful else { return }
#if DEBUG
        logMiniGeometry("REAL_CHILDREN", geometry: geometry)
#endif
        miniGeometriesByPlacement[geometry.placement] = geometry
        guard !isPlayerTransitioning,
              let frame = miniPlayerFramesByPlacement[geometry.placement],
              frame.isMeaningful else { return }
        activateMiniPlayerDestination(
            frame: frame,
            geometry: geometry,
            placement: geometry.placement
        )
    }

    private func activateMiniPlayerDestination(
        frame: CGRect,
        geometry: MiniPlayerTransitionGeometry,
        placement: MiniPlayerAccessoryPlacement
    ) {
        // A transient nil environment must not replace a known concrete
        // system placement with geometry from an undefined layout pass.
        if placement == .undefined, miniPlayerPlacement != .undefined { return }
        let surfaceChanged = !miniPlayerFrame.isApproximatelyEqual(to: frame)
        let childrenChanged = !miniTransitionGeometry.artworkFrame.isApproximatelyEqual(
            to: geometry.artworkFrame
        ) || !miniTransitionGeometry.metadataFrame.isApproximatelyEqual(
            to: geometry.metadataFrame
        ) || !miniTransitionGeometry.playPauseFrame.isApproximatelyEqual(
            to: geometry.playPauseFrame
        ) || !miniTransitionGeometry.nextFrame.isApproximatelyEqual(
            to: geometry.nextFrame
        )
        guard surfaceChanged || childrenChanged || miniPlayerPlacement != placement else { return }
        miniPlayerFrame = frame
        miniArtworkFrame = geometry.artworkFrame
        miniTransitionGeometry = geometry
        miniPlayerPlacement = placement
#if DEBUG
        logMiniGeometry("STORED_DESTINATION", frame: frame, geometry: geometry)
#endif
    }

    private func recordMiniPlayerSwiftUIFrame(_ frame: CGRect) {
#if DEBUG
        logMiniGeometry(
            "SWIFTUI_ACCESSORY_CONTENT",
            frame: frame,
            placement: miniPlayerPlacement
        )
#endif
    }

    private func recordExpandedArtworkFrame(_ frame: CGRect) {
        guard playerOverlayMounted,
              !isPlayerTransitioning,
              !isPlayerDismissGestureActive,
              frame.isMeaningful else { return }
        if !expandedArtworkFrame.isApproximatelyEqual(to: frame) {
            expandedArtworkFrame = frame
        }
    }

    private func recordPlayerDismissDebugGeometry(
        _ geometry: PlayerDismissDebugGeometry,
        safeAreaTop: CGFloat
    ) {
#if DEBUG
        guard geometry.isMeaningful,
              geometry != lastDismissDebugGeometry else { return }
        lastDismissDebugGeometry = geometry

        if playerPresentationPhase == .expanded {
            expandedDismissDebugGeometry = geometry
        }

        let baseline = expandedDismissDebugGeometry
        let surfaceDelta = geometry.surfaceFrame.minY - baseline.surfaceFrame.minY
        let grabberDelta = geometry.grabberFrame.minY - baseline.grabberFrame.minY
        let artworkDelta = geometry.artworkFrame.minY - baseline.artworkFrame.minY
        print(
            "PLAYER_DRAG_GEOMETRY phase=\(playerPresentationPhase.debugName) "
                + "gestureTranslationY=\(debugScalar(playerDismissTravelOffset)) "
                + "surfaceMinY=\(debugScalar(geometry.surfaceFrame.minY)) "
                + "surfaceFrame=\(debugRect(geometry.surfaceFrame)) "
                + "grabberGlobalFrame=\(debugRect(geometry.grabberFrame)) "
                + "artworkGlobalFrame=\(debugRect(geometry.artworkFrame)) "
                + "safeAreaInsets.top=\(debugScalar(safeAreaTop)) "
                + "deltas(surface/grabber/artwork)=\(debugScalar(surfaceDelta))/"
                + "\(debugScalar(grabberDelta))/\(debugScalar(artworkDelta))"
        )

        if playerPresentationPhase == .dragging {
            let surfaceError = abs(surfaceDelta - playerDismissTravelOffset)
            let grabberError = abs(grabberDelta - surfaceDelta)
            let artworkError = abs(artworkDelta - surfaceDelta)
            if surfaceError > 1.5 || grabberError > 1.5 || artworkError > 1.5 {
                print(
                    "PLAYER_DRAG_INVARIANT_FAIL surfaceError=\(debugScalar(surfaceError)) "
                        + "grabberError=\(debugScalar(grabberError)) "
                        + "artworkError=\(debugScalar(artworkError))"
                )
            }
        }
#endif
    }

    private func recordRenderedDismissGeometry(_ geometry: PlayerDismissRenderedGeometry) {
#if DEBUG
        guard geometry.morphProgress >= 0.999,
              geometry != lastRenderedDismissGeometry else { return }
        lastRenderedDismissGeometry = geometry
        print(
            "TRANSITION_AT_P1 surface=\(debugRect(geometry.surfaceFrame)) "
                + "artwork=\(debugRect(geometry.artworkFrame)) "
                + "metadata=\(debugRect(geometry.metadataFrame)) "
                + "playPause=\(debugRect(geometry.playPauseFrame)) "
                + "next=\(debugRect(geometry.nextFrame))"
        )
#endif
    }

#if DEBUG
    private func logCollapseCapture(
        frame: CGRect,
        geometry: MiniPlayerTransitionGeometry,
        destinationOffset: CGFloat
    ) {
        print(
            "COLLAPSE_CAPTURE surface=\(debugRect(frame)) "
                + "placement=\(geometry.placement.rawValue) "
                + "destinationOffset=\(debugScalar(destinationOffset)) "
                + "artwork=\(debugRect(geometry.artworkFrame)) "
                + "metadata=\(debugRect(geometry.metadataFrame)) "
                + "playPause=\(debugRect(geometry.playPauseFrame)) "
                + "next=\(debugRect(geometry.nextFrame))"
        )
    }

    private func logRealMiniPlayerAfterHandoff() {
        print(
            "REAL_AFTER_HANDOFF surface=\(debugRect(miniPlayerFrame)) "
                + "placement=\(miniPlayerPlacement.rawValue) "
                + "artwork=\(debugRect(miniTransitionGeometry.artworkFrame)) "
                + "metadata=\(debugRect(miniTransitionGeometry.metadataFrame)) "
                + "playPause=\(debugRect(miniTransitionGeometry.playPauseFrame)) "
                + "next=\(debugRect(miniTransitionGeometry.nextFrame))"
        )
    }

    private func logMiniGeometry(
        _ label: String,
        frame: CGRect,
        placement: MiniPlayerAccessoryPlacement
    ) {
        print(
            "\(label) surface=\(debugRect(frame)) placement=\(placement.rawValue)"
        )
    }

    private func logMiniGeometry(
        _ label: String,
        geometry: MiniPlayerTransitionGeometry
    ) {
        print(
            "\(label) placement=\(geometry.placement.rawValue) "
                + "artwork=\(debugRect(geometry.artworkFrame)) "
                + "metadata=\(debugRect(geometry.metadataFrame)) "
                + "playPause=\(debugRect(geometry.playPauseFrame)) "
                + "next=\(debugRect(geometry.nextFrame))"
        )
    }

    private func logMiniGeometry(
        _ label: String,
        frame: CGRect,
        geometry: MiniPlayerTransitionGeometry
    ) {
        print(
            "\(label) surface=\(debugRect(frame)) "
                + "placement=\(geometry.placement.rawValue) "
                + "artwork=\(debugRect(geometry.artworkFrame)) "
                + "metadata=\(debugRect(geometry.metadataFrame)) "
                + "playPause=\(debugRect(geometry.playPauseFrame)) "
                + "next=\(debugRect(geometry.nextFrame))"
        )
    }

    private func debugRect(_ rect: CGRect) -> String {
        "x=\(debugScalar(rect.minX)),y=\(debugScalar(rect.minY)),"
            + "w=\(debugScalar(rect.width)),h=\(debugScalar(rect.height))"
    }

    private func debugScalar(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }
#endif

    private var usesFullBleedArtwork: Bool {
        audio.currentLiveArtwork != nil
            || (stylizedPlayerCover && audio.currentArtwork != nil)
    }

    private func transitionArtworkScale(usesFullBleedArtwork: Bool) -> CGFloat {
        guard !usesFullBleedArtwork,
              artworkAnimation,
              !PerformanceMode.reduceAnimations,
              !audio.isPlaying else { return 1 }
        return 0.88
    }

    private func playerFullContentOpacity(_ progress: CGFloat) -> CGFloat {
        smoothStep(progress, from: 0.56, to: 0.94)
    }

    private func smoothStep(_ value: CGFloat, from lower: CGFloat, to upper: CGFloat) -> CGFloat {
        guard upper > lower else { return value >= upper ? 1 : 0 }
        let t = min(max((value - lower) / (upper - lower), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

private struct PlayerTransitionSnapshot {
    let title: String
    let artist: String
    let artwork: UIImage?
    let isPlaying: Bool
    let targetArtworkScale: CGFloat
    let usesFullBleedArtwork: Bool
}

/// SwiftUI only samples ordinary closure arguments at the start and end of an
/// animation. Making the scalar itself animatable gives the transition its
/// actual in-flight value on every display frame.
private struct PlayerExpansionAnimator<Content: View>: View, Animatable {
    var progress: CGFloat
    let isTransitioning: Bool
    let content: (CGFloat) -> Content

    init(
        progress: CGFloat,
        isTransitioning: Bool,
        @ViewBuilder content: @escaping (CGFloat) -> Content
    ) {
        self.progress = progress
        self.isTransitioning = isTransitioning
        self.content = content
    }

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        content(progress)
            .transaction { transaction in
                // Derived geometry already follows the interpolated scalar.
                // Carrying the parent's animation into every derived frame
                // recursively eases those values and produces visible lag.
                if isTransitioning {
                    transaction.animation = nil
                }
            }
    }
}

private struct PlayerDismissalMotion {
    let travelOffset: CGFloat
    let morphProgress: CGFloat
}

/// One display-linked animation clock feeds two independent response systems:
/// an underdamped travel spring and a monotonic overdamped morph. Geometry gets
/// native SwiftUI interpolation at the display refresh rate without nested
/// animation transactions cancelling each other.
private struct PlayerDismissalMotionAnimator<Content: View>: View, Animatable {
    var interactiveTravelOffset: CGFloat
    var animationProgress: CGFloat
    let releaseOffset: CGFloat
    let destinationOffset: CGFloat
    let normalizedInitialVelocity: CGFloat
    let isCollapsing: Bool
    let neutralizesInheritedAnimation: Bool
    let content: (PlayerDismissalMotion) -> Content

    init(
        interactiveTravelOffset: CGFloat,
        animationProgress: CGFloat,
        releaseOffset: CGFloat,
        destinationOffset: CGFloat,
        normalizedInitialVelocity: CGFloat,
        isCollapsing: Bool,
        neutralizesInheritedAnimation: Bool,
        @ViewBuilder content: @escaping (PlayerDismissalMotion) -> Content
    ) {
        self.interactiveTravelOffset = interactiveTravelOffset
        self.animationProgress = animationProgress
        self.releaseOffset = releaseOffset
        self.destinationOffset = destinationOffset
        self.normalizedInitialVelocity = normalizedInitialVelocity
        self.isCollapsing = isCollapsing
        self.neutralizesInheritedAnimation = neutralizesInheritedAnimation
        self.content = content
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(interactiveTravelOffset, animationProgress) }
        set {
            interactiveTravelOffset = newValue.first
            animationProgress = newValue.second
        }
    }

    var body: some View {
        content(currentMotion)
            .transaction { transaction in
                if neutralizesInheritedAnimation {
                    transaction.animation = nil
                }
            }
    }

    private var currentMotion: PlayerDismissalMotion {
        guard isCollapsing else {
            return PlayerDismissalMotion(
                travelOffset: interactiveTravelOffset,
                morphProgress: 0
            )
        }

        let clock = min(max(Double(animationProgress), 0), 1)
        guard clock > 0 else {
            return PlayerDismissalMotion(
                travelOffset: releaseOffset,
                morphProgress: 0
            )
        }
        guard clock < 1 else {
            return PlayerDismissalMotion(
                travelOffset: destinationOffset,
                morphProgress: 1
            )
        }

        let elapsed = clock * playerDismissalDuration
        return PlayerDismissalMotion(
            travelOffset: travelOffset(at: elapsed),
            morphProgress: morphProgress(at: elapsed)
        )
    }

    private func travelOffset(at elapsed: Double) -> CGFloat {
        let initialVelocity = normalizedInitialVelocity * max(destinationOffset - releaseOffset, 1)
        if #available(iOS 17.0, *) {
            let spring = Spring(mass: 1, stiffness: 220, damping: 24)
            return spring.value(
                fromValue: releaseOffset,
                toValue: destinationOffset,
                initialVelocity: initialVelocity,
                time: elapsed
            )
        }

        // Same second-order response for the iOS 16 fallback.
        let start = Double(releaseOffset)
        let destination = Double(destinationOffset)
        let decayRate = 12.0
        let dampedFrequency = sqrt(220.0 - decayRate * decayRate)
        let fallbackInitialVelocity = Double(initialVelocity)
        let displacement = start - destination
        let sineCoefficient = (fallbackInitialVelocity + decayRate * displacement) / dampedFrequency
        let response = exp(-decayRate * elapsed) * (
            displacement * cos(dampedFrequency * elapsed)
                + sineCoefficient * sin(dampedFrequency * elapsed)
        )
        return CGFloat(destination + response)
    }

    private func morphProgress(at elapsed: Double) -> CGFloat {
        // Overdamped second-order response: fast source departure, no overshoot,
        // about 95% complete near 270 ms, then a subtle settling tail.
        let slowRate = 10.5
        let fastRate = 130.0
        let remaining = (
            fastRate * exp(-slowRate * elapsed)
                - slowRate * exp(-fastRate * elapsed)
        ) / (fastRate - slowRate)
        return CGFloat(min(max(1 - remaining, 0), 1))
    }
}

private struct PlayerDismissalClipMask: View {
    let travelOffset: CGFloat
    let morphProgress: CGFloat
    let destinationFrame: CGRect
    let safeAreaInsets: EdgeInsets
    let isInteractive: Bool

    var body: some View {
        GeometryReader { geo in
            let destination = localDestinationFrame(in: geo)
            let expanded = expandedFrame(in: geo.size)
            let morph = min(max(morphProgress, 0), 1)
            let surface = CGRect(
                x: interpolate(expanded.minX, destination.minX, morph),
                y: expanded.minY + travelOffset,
                width: interpolate(expanded.width, destination.width, morph),
                height: interpolate(expanded.height, destination.height, morph)
            )
            let dragRadius = min(26, max(0, travelOffset * 0.18))
            let destinationRadius = min(destination.height / 2, 28)
            let radius = interpolate(
                isInteractive ? dragRadius : min(dragRadius, 22),
                destinationRadius,
                morph
            )

            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .frame(width: surface.width, height: surface.height)
                .position(x: surface.midX, y: surface.midY)
        }
    }

    private func expandedFrame(in size: CGSize) -> CGRect {
        CGRect(
            x: -safeAreaInsets.leading,
            y: -safeAreaInsets.top,
            width: size.width + safeAreaInsets.leading + safeAreaInsets.trailing,
            height: size.height + safeAreaInsets.top + safeAreaInsets.bottom
        )
    }

    private func localDestinationFrame(in geo: GeometryProxy) -> CGRect {
        let fallback = CGRect(
            x: 12,
            y: max(0, geo.size.height - max(126, safeAreaInsets.bottom + 106)),
            width: max(1, geo.size.width - 24),
            height: 56
        )
        guard destinationFrame.isMeaningful else { return fallback }
        let global = geo.frame(in: .global)
        return destinationFrame.offsetBy(dx: -global.minX, dy: -global.minY)
    }

    private func interpolate(_ start: CGFloat, _ end: CGFloat, _ progress: CGFloat) -> CGFloat {
        start + (end - start) * progress
    }
}

/// Dismissal-only chrome. The full player remains a rigid, clipped surface;
/// this layer supplies the material, one shared artwork image, and destination
/// mini-player controls while width and height morph independently from travel.
private struct PlayerDismissalOverlay: View {
    let travelOffset: CGFloat
    let morphProgress: CGFloat
    let sourceFrame: CGRect
    let sourceArtworkFrame: CGRect
    let expandedArtworkFrame: CGRect
    let miniGeometry: MiniPlayerTransitionGeometry
    let safeAreaInsets: EdgeInsets
    let snapshot: PlayerTransitionSnapshot
    let isInteractive: Bool
    let isCompleting: Bool
    let onRenderedGeometryChange: (PlayerDismissRenderedGeometry) -> Void

    var body: some View {
        GeometryReader { geo in
            let morph = clamped(morphProgress)
            let globalFrame = geo.frame(in: .global)
            let expanded = expandedSurface(in: geo.size)
            let destination = localFrame(
                sourceFrame,
                relativeTo: globalFrame,
                fallback: fallbackDestination(in: geo.size)
            )
            let surface = CGRect(
                x: interpolate(expanded.minX, destination.minX, morph),
                y: expanded.minY + travelOffset,
                width: interpolate(expanded.width, destination.width, morph),
                height: interpolate(expanded.height, destination.height, morph)
            )
            let dragRadius = min(26, max(0, travelOffset * 0.18))
            let destinationRadius = min(destination.height / 2, 28)
            let radius = interpolate(
                isInteractive ? dragRadius : min(dragRadius, 22),
                destinationRadius,
                morph
            )
            let sourceArtwork = localFrame(
                expandedArtworkFrame,
                relativeTo: globalFrame,
                fallback: fallbackExpandedArtwork(in: expanded)
            )
            let destinationArtwork = localFrame(
                miniGeometry.artworkFrame.isMeaningful
                    ? miniGeometry.artworkFrame
                    : sourceArtworkFrame,
                relativeTo: globalFrame,
                fallback: CGRect(
                    x: destination.minX + 12,
                    y: destination.minY + 8,
                    width: 32,
                    height: 32
                )
            )
            let artwork = artworkFrame(
                source: sourceArtwork,
                destination: destinationArtwork,
                travelOffset: travelOffset,
                morph: morph
            )
            let metadata = travellingElementFrame(
                miniGeometry.metadataFrame,
                surface: surface,
                destinationSurface: destination,
                globalFrame: globalFrame
            )
            let playPause = travellingElementFrame(
                miniGeometry.playPauseFrame,
                surface: surface,
                destinationSurface: destination,
                globalFrame: globalFrame
            )
            let next = travellingElementFrame(
                miniGeometry.nextFrame,
                surface: surface,
                destinationSurface: destination,
                globalFrame: globalFrame
            )
            let renderedGeometry = PlayerDismissRenderedGeometry(
                surfaceFrame: globalized(surface, relativeTo: globalFrame),
                artworkFrame: globalized(artwork, relativeTo: globalFrame),
                metadataFrame: globalized(metadata, relativeTo: globalFrame),
                playPauseFrame: globalized(playPause, relativeTo: globalFrame),
                nextFrame: globalized(next, relativeTo: globalFrame),
                morphProgress: morph
            )
            let materialOpacity = smoothStep(morph, from: 0.38, to: 0.98)
            let chromeOpacity = isCompleting
                ? smoothStep(morph, from: 0, to: 0.12)
                : 0

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.black.opacity(0.001))
                    .frame(width: surface.width, height: surface.height)
                    .position(x: surface.midX, y: surface.midY)
                    .shadow(
                        color: .black.opacity(interpolate(0.18, 0.34, morph)),
                        radius: interpolate(12, 18, morph),
                        y: interpolate(7, 10, morph)
                    )

                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Color.black.opacity(interpolate(0.10, 0.30, morph))
                }
                .frame(width: surface.width, height: surface.height)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .position(x: surface.midX, y: surface.midY)
                .opacity(materialOpacity)

                transitionChrome(
                    metadata: metadata,
                    playPause: playPause,
                    next: next,
                    canvasSize: geo.size
                )
                .opacity(chromeOpacity)
                .mask {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .frame(width: surface.width, height: surface.height)
                        .position(x: surface.midX, y: surface.midY)
                }

                heroArtwork(frame: artwork, morph: morph)
                    .opacity(isCompleting ? 1 : 0)

                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(interpolate(0, 0.10, morph)), lineWidth: 0.5)
                    .frame(width: surface.width, height: surface.height)
                    .position(x: surface.midX, y: surface.midY)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .preference(
                key: PlayerDismissRenderedGeometryKey.self,
                value: renderedGeometry
            )
        }
        .onPreferenceChange(PlayerDismissRenderedGeometryKey.self) {
            onRenderedGeometryChange($0)
        }
    }

    private func transitionChrome(
        metadata: CGRect,
        playPause: CGRect,
        next: CGRect,
        canvasSize: CGSize
    ) -> some View {
        return ZStack(alignment: .topLeading) {
            MiniPlayerMetadataChrome(
                title: snapshot.title,
                artist: snapshot.artist
            )
            .frame(width: metadata.width, height: metadata.height, alignment: .leading)
            .position(x: metadata.midX, y: metadata.midY)

            MiniPlayerTransportIcon(
                systemName: snapshot.isPlaying ? Symbols.pause : Symbols.play
            )
                .frame(width: playPause.width, height: playPause.height)
                .position(x: playPause.midX, y: playPause.midY)

            MiniPlayerTransportIcon(systemName: Symbols.next)
                .frame(width: next.width, height: next.height)
                .position(x: next.midX, y: next.midY)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .allowsHitTesting(false)
    }

    private func heroArtwork(frame: CGRect, morph: CGFloat) -> some View {
        Group {
            if let artwork = snapshot.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color(white: 0.12)
                    Image(systemName: Symbols.albumPlaceholder)
                        .font(.system(size: interpolate(15, 60, 1 - morph), weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        .frame(width: frame.width, height: frame.height)
        .clipShape(
            RoundedRectangle(
                cornerRadius: interpolate(snapshot.usesFullBleedArtwork ? 0 : 18, 6, morph),
                style: .continuous
            )
        )
        .shadow(
            color: .black.opacity(0.34 * (1 - smoothStep(morph, from: 0.62, to: 1))),
            radius: interpolate(22, 0, morph),
            y: interpolate(11, 0, morph)
        )
        .position(x: frame.midX, y: frame.midY)
        .allowsHitTesting(false)
    }

    private func artworkFrame(
        source: CGRect,
        destination: CGRect,
        travelOffset: CGFloat,
        morph: CGFloat
    ) -> CGRect {
        let translatedSource = source.offsetBy(dx: 0, dy: travelOffset)
        return interpolate(translatedSource, destination, morph)
    }

    private func travellingElementFrame(
        _ globalElementFrame: CGRect,
        surface: CGRect,
        destinationSurface: CGRect,
        globalFrame: CGRect
    ) -> CGRect {
        let fallback = CGRect(
            x: destinationSurface.maxX - 92,
            y: destinationSurface.minY + 10,
            width: 36,
            height: 36
        )
        let destination = localFrame(
            globalElementFrame,
            relativeTo: globalFrame,
            fallback: fallback
        )
        return destination.offsetBy(
            dx: 0,
            dy: surface.minY - destinationSurface.minY
        )
    }

    private func expandedSurface(in size: CGSize) -> CGRect {
        CGRect(
            x: -safeAreaInsets.leading,
            y: -safeAreaInsets.top,
            width: size.width + safeAreaInsets.leading + safeAreaInsets.trailing,
            height: size.height + safeAreaInsets.top + safeAreaInsets.bottom
        )
    }

    private func fallbackDestination(in size: CGSize) -> CGRect {
        CGRect(
            x: 12,
            y: max(0, size.height - max(126, safeAreaInsets.bottom + 106)),
            width: max(1, size.width - 24),
            height: 56
        )
    }

    private func fallbackExpandedArtwork(in surface: CGRect) -> CGRect {
        if snapshot.usesFullBleedArtwork {
            return CGRect(
                x: surface.minX,
                y: surface.minY,
                width: surface.width,
                height: surface.width
            )
        }
        let availableSide = max(0, surface.width - 48)
        let side = availableSide * snapshot.targetArtworkScale
        return CGRect(
            x: surface.midX - side / 2,
            y: surface.minY + 32 + (availableSide - side) / 2,
            width: side,
            height: side
        )
    }

    private func localFrame(
        _ global: CGRect,
        relativeTo globalContainer: CGRect,
        fallback: CGRect
    ) -> CGRect {
        guard global.isMeaningful else { return fallback }
        return global.offsetBy(dx: -globalContainer.minX, dy: -globalContainer.minY)
    }

    private func globalized(_ local: CGRect, relativeTo globalContainer: CGRect) -> CGRect {
        local.offsetBy(dx: globalContainer.minX, dy: globalContainer.minY)
    }

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    private func smoothStep(_ value: CGFloat, from lower: CGFloat, to upper: CGFloat) -> CGFloat {
        guard upper > lower else { return value >= upper ? 1 : 0 }
        let t = clamped((value - lower) / (upper - lower))
        return t * t * (3 - 2 * t)
    }

    private func interpolate(_ start: CGFloat, _ end: CGFloat, _ progress: CGFloat) -> CGFloat {
        start + (end - start) * progress
    }

    private func interpolate(_ start: CGRect, _ end: CGRect, _ progress: CGFloat) -> CGRect {
        CGRect(
            x: interpolate(start.minX, end.minX, progress),
            y: interpolate(start.minY, end.minY, progress),
            width: interpolate(start.width, end.width, progress),
            height: interpolate(start.height, end.height, progress)
        )
    }
}

private struct PlayerDismissRenderedGeometry: Equatable {
    var surfaceFrame: CGRect = .zero
    var artworkFrame: CGRect = .zero
    var metadataFrame: CGRect = .zero
    var playPauseFrame: CGRect = .zero
    var nextFrame: CGRect = .zero
    var morphProgress: CGFloat = 0
}

private struct PlayerDismissRenderedGeometryKey: PreferenceKey {
    static var defaultValue = PlayerDismissRenderedGeometry()

    static func reduce(
        value: inout PlayerDismissRenderedGeometry,
        nextValue: () -> PlayerDismissRenderedGeometry
    ) {
        value = nextValue()
    }
}

/// Prevents the mounted full-player view from bleeding outside the card while
/// its transition proxy expands or contracts above the tab content.
private struct PlayerExpansionClipMask: View {
    let progress: CGFloat
    let sourceFrame: CGRect
    let safeAreaInsets: EdgeInsets
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { geo in
            let p = min(max(progress, 0), 1)
            let globalFrame = geo.frame(in: .global)
            let fallback = CGRect(
                x: 12,
                y: max(0, geo.size.height - max(126, safeAreaInsets.bottom + 106)),
                width: max(1, geo.size.width - 24),
                height: 56
            )
            let source = sourceFrame.isMeaningful
                ? sourceFrame.offsetBy(dx: -globalFrame.minX, dy: -globalFrame.minY)
                : fallback
            let destination = CGRect(
                x: -safeAreaInsets.leading,
                y: -safeAreaInsets.top,
                width: geo.size.width + safeAreaInsets.leading + safeAreaInsets.trailing,
                height: geo.size.height + safeAreaInsets.top + safeAreaInsets.bottom
            )
            if reduceMotion {
                Rectangle()
                    .frame(width: destination.width, height: destination.height)
                    .position(x: destination.midX, y: destination.midY)
            } else {
                let card = interpolate(source, destination, p)
                let radius = min(source.height / 2, 30) * pow(1 - p, 0.58)

                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .frame(width: card.width, height: card.height)
                    .position(x: card.midX, y: card.midY)
            }
        }
    }

    private func interpolate(_ start: CGRect, _ end: CGRect, _ progress: CGFloat) -> CGRect {
        CGRect(
            x: start.minX + (end.minX - start.minX) * progress,
            y: start.minY + (end.minY - start.minY) * progress,
            width: start.width + (end.width - start.width) * progress,
            height: start.height + (end.height - start.height) * progress
        )
    }
}

/// A single persistent card owns the complete mini-to-player handoff. The
/// source accessory disappears only after this p=0 proxy has rendered, and the
/// real player artwork fades in only once the proxy reaches its final frame.
private struct PlayerExpansionOverlay: View {
    let progress: CGFloat
    let sourceFrame: CGRect
    let sourceArtworkFrame: CGRect
    let safeAreaInsets: EdgeInsets
    let snapshot: PlayerTransitionSnapshot
    let reduceMotion: Bool
    let isInteractiveDismissal: Bool
    let isCompletingDismissal: Bool
    let isCancellingDismissal: Bool
    let dismissalStartProgress: CGFloat
    let dismissalTravel: CGFloat

    init(
        progress: CGFloat,
        sourceFrame: CGRect,
        sourceArtworkFrame: CGRect,
        safeAreaInsets: EdgeInsets,
        snapshot: PlayerTransitionSnapshot,
        reduceMotion: Bool,
        isInteractiveDismissal: Bool,
        isCompletingDismissal: Bool,
        isCancellingDismissal: Bool,
        dismissalStartProgress: CGFloat,
        dismissalTravel: CGFloat
    ) {
        self.progress = progress
        self.sourceFrame = sourceFrame
        self.sourceArtworkFrame = sourceArtworkFrame
        self.safeAreaInsets = safeAreaInsets
        self.snapshot = snapshot
        self.reduceMotion = reduceMotion
        self.isInteractiveDismissal = isInteractiveDismissal
        self.isCompletingDismissal = isCompletingDismissal
        self.isCancellingDismissal = isCancellingDismissal
        self.dismissalStartProgress = dismissalStartProgress
        self.dismissalTravel = dismissalTravel
    }

    var body: some View {
        GeometryReader { geo in
            let p = clamped(progress)
            let overlayGlobalFrame = geo.frame(in: .global)
            let source = localSourceFrame(
                in: geo.size,
                overlayGlobalFrame: overlayGlobalFrame
            )
            let sourceArtwork = localSourceArtworkFrame(
                in: source,
                overlayGlobalFrame: overlayGlobalFrame
            )
            let card = cardFrame(source: source, size: geo.size, progress: p)
            let cardRadius = min(source.height / 2, 30) * pow(1 - p, 0.58)
            let normalHeroFrame = artworkFrame(
                source: sourceArtwork,
                size: geo.size,
                progress: p
            )
            let heroFrame = isCompletingDismissal
                ? releaseArtworkFrame(
                    source: sourceArtwork,
                    size: geo.size,
                    progress: p
                )
                : normalHeroFrame
            let heroOpacity: CGFloat = {
                if reduceMotion || isInteractiveDismissal || isCancellingDismissal { return 0 }
                if isCompletingDismissal { return 1 }
                return smoothStep(p, from: 0.035, to: 0.16)
                    * (1 - smoothStep(p, from: 0.90, to: 0.985))
            }()
            let hidesDismissalProxy = isInteractiveDismissal
                || isCompletingDismissal
                || isCancellingDismissal
            let surfaceOpacity = hidesDismissalProxy
                ? 0
                : smoothStep(p, from: 0.015, to: 0.16)
                    * (1 - smoothStep(p, from: 0.92, to: 0.995))
            let compactHeaderOpacity = hidesDismissalProxy
                ? 0
                : smoothStep(p, from: 0.06, to: 0.20)
                    * (1 - smoothStep(p, from: 0.76, to: 0.94))
            let dimOpacity = hidesDismissalProxy
                ? 0
                : 0.14
                    * smoothStep(p, from: 0.18, to: 0.72)
                    * (1 - smoothStep(p, from: 0.94, to: 1))

            ZStack {
                Color.black
                    .opacity(dimOpacity)
                    .ignoresSafeArea()

                transitionSurface(
                    canvasSize: geo.size,
                    frame: card,
                    radius: cardRadius,
                    progress: p
                )
                    .opacity(surfaceOpacity)

                heroArtwork(frame: heroFrame, progress: p)
                    .opacity(heroOpacity)

                compactHeader(
                    frame: card,
                    sourceArtwork: sourceArtwork,
                    canvasSize: geo.size
                )
                .opacity(compactHeaderOpacity)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .opacity(reduceMotion ? 0 : 1)
        }
    }

    private func transitionSurface(
        canvasSize: CGSize,
        frame: CGRect,
        radius: CGFloat,
        progress: CGFloat
    ) -> some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)

            if let artwork = snapshot.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.12)
                    // Keep the blur kernel stable while the card changes size;
                    // recalculating it every display frame is very expensive.
                    .blur(radius: 38, opaque: true)
                    .opacity(interpolate(0.20, 0.11, progress))
            }

            Color.black.opacity(interpolate(0.18, 0.62, progress))
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .mask {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
        }
        .shadow(
            color: .black.opacity(interpolate(0.22, 0.42, progress)),
            radius: interpolate(14, 28, progress),
            y: interpolate(8, 14, progress)
        )
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.white.opacity(interpolate(0.12, 0.035, progress)), lineWidth: 0.6)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    private func heroArtwork(frame: CGRect, progress: CGFloat) -> some View {
        Group {
            if let artwork = snapshot.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color(white: 0.12)
                    Image(systemName: Symbols.albumPlaceholder)
                        .font(.system(size: interpolate(15, 58, progress), weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.32))
                }
            }
        }
        .frame(width: frame.width, height: frame.height)
        .clipShape(
            RoundedRectangle(
                cornerRadius: interpolate(
                    8,
                    snapshot.usesFullBleedArtwork ? 0 : 18,
                    linearRamp(progress, from: 0.08, to: 0.86)
                ),
                style: .continuous
            )
        )
        .shadow(
            color: .black.opacity(0.38 * linearRamp(progress, from: 0.10, to: 0.72)),
            radius: interpolate(0, 24, linearRamp(progress, from: 0.10, to: 0.78)),
            y: interpolate(0, 12, linearRamp(progress, from: 0.10, to: 0.78))
        )
        .position(x: frame.midX, y: frame.midY)
        .allowsHitTesting(false)
    }

    private func compactHeader(
        frame: CGRect,
        sourceArtwork: CGRect,
        canvasSize: CGSize
    ) -> some View {
        let horizontalPadding = max(12, frame.width * 0.045)
        let artworkClearance = max(0, sourceArtwork.maxX - frame.minX + 10)
        let leading = frame.minX + max(horizontalPadding, artworkClearance)
        let trailing = frame.maxX - horizontalPadding
        let controlsWidth: CGFloat = 80
        let availableTextWidth = max(0, trailing - leading - controlsWidth - 10)
        let centerY = frame.minY + min(30, max(24, frame.height / 2))

        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(snapshot.artist)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(width: availableTextWidth, alignment: .leading)
            .position(x: leading + availableTextWidth / 2, y: centerY)

            HStack(spacing: 4) {
                Image(systemName: snapshot.isPlaying ? Symbols.pause : Symbols.play)
                    .frame(width: 36, height: 36)
                Image(systemName: Symbols.next)
                    .frame(width: 36, height: 36)
            }
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .position(x: trailing - controlsWidth / 2, y: centerY)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipped()
        .allowsHitTesting(false)
    }

    private func cardFrame(source: CGRect, size: CGSize, progress: CGFloat) -> CGRect {
        let destination = CGRect(
            x: -safeAreaInsets.leading,
            y: -safeAreaInsets.top,
            width: size.width + safeAreaInsets.leading + safeAreaInsets.trailing,
            height: size.height + safeAreaInsets.top + safeAreaInsets.bottom
        )
        if reduceMotion { return destination }
        return interpolate(source, destination, progress)
    }

    private func artworkFrame(source: CGRect, size: CGSize, progress: CGFloat) -> CGRect {
        let target = expandedArtworkFrame(in: size)
        let artworkProgress = reduceMotion
            ? linearRamp(progress, from: 0.10, to: 0.92)
            : progress
        return interpolate(source, target, artworkProgress)
    }

    private func releaseArtworkFrame(source: CGRect, size: CGSize, progress: CGFloat) -> CGRect {
        let releaseProgress = min(
            max(progress / max(dismissalStartProgress, 0.001), 0),
            1
        )
        let releaseStart = expandedArtworkFrame(in: size).offsetBy(
            dx: 0,
            dy: dismissalTravel * (1 - dismissalStartProgress)
        )
        return interpolate(source, releaseStart, releaseProgress)
    }

    private func expandedArtworkFrame(in size: CGSize) -> CGRect {
        if snapshot.usesFullBleedArtwork {
            return CGRect(
                x: 0,
                y: -safeAreaInsets.top,
                width: size.width,
                height: size.width + safeAreaInsets.top
            )
        }
        let side = max(0, size.width - 48)
        let scaledSide = side * snapshot.targetArtworkScale
        let inset = (side - scaledSide) / 2
        return CGRect(
            x: 24 + inset,
            y: 32 + inset,
            width: scaledSide,
            height: scaledSide
        )
    }

    private func localSourceFrame(in size: CGSize, overlayGlobalFrame: CGRect) -> CGRect {
        let fallback = CGRect(
            x: 12,
            y: max(0, size.height - max(126, safeAreaInsets.bottom + 106)),
            width: max(1, size.width - 24),
            height: 56
        )
        guard sourceFrame.isMeaningful else { return fallback }
        return sourceFrame.offsetBy(dx: -overlayGlobalFrame.minX, dy: -overlayGlobalFrame.minY)
    }

    private func localSourceArtworkFrame(
        in source: CGRect,
        overlayGlobalFrame: CGRect
    ) -> CGRect {
        let fallback = CGRect(x: source.minX + 12, y: source.minY + 8, width: 32, height: 32)
        guard sourceArtworkFrame.isMeaningful else { return fallback }
        return sourceArtworkFrame.offsetBy(
            dx: -overlayGlobalFrame.minX,
            dy: -overlayGlobalFrame.minY
        )
    }

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    private func linearRamp(_ value: CGFloat, from lower: CGFloat, to upper: CGFloat) -> CGFloat {
        guard upper > lower else { return value >= upper ? 1 : 0 }
        return clamped((value - lower) / (upper - lower))
    }

    private func smoothStep(_ value: CGFloat, from lower: CGFloat, to upper: CGFloat) -> CGFloat {
        let t = linearRamp(value, from: lower, to: upper)
        return t * t * (3 - 2 * t)
    }

    private func interpolate(_ start: CGFloat, _ end: CGFloat, _ progress: CGFloat) -> CGFloat {
        start + (end - start) * progress
    }

    private func interpolate(_ start: CGRect, _ end: CGRect, _ progress: CGFloat) -> CGRect {
        CGRect(
            x: interpolate(start.minX, end.minX, progress),
            y: interpolate(start.minY, end.minY, progress),
            width: interpolate(start.width, end.width, progress),
            height: interpolate(start.height, end.height, progress)
        )
    }
}

private struct PlayerAccessoryFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private extension View {
    func reportPlayerAccessoryFrame(_ action: @escaping (CGRect) -> Void) -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: PlayerAccessoryFrameKey.self,
                    value: geo.frame(in: .global)
                )
            }
        }
        .onPreferenceChange(PlayerAccessoryFrameKey.self) { frame in
            guard frame.isMeaningful else { return }
            action(frame)
        }
    }

    @ViewBuilder
    func debugReportPlayerAccessoryFrame(_ action: @escaping (CGRect) -> Void) -> some View {
#if DEBUG
        reportPlayerAccessoryFrame(action)
#else
        self
#endif
    }
}

private extension CGRect {
    var isMeaningful: Bool {
        minX.isFinite && minY.isFinite && width.isFinite && height.isFinite
            && width > 1 && height > 1
    }

    func isApproximatelyEqual(to other: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}

@available(iOS 26.0, *)
private struct ModernMiniPlayerAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var systemPlacement

    let onExpand: () -> Void
    let onArtworkFrameChange: (CGRect) -> Void
    let onTransitionGeometryChange: (MiniPlayerTransitionGeometry) -> Void
    let onSurfaceFrameChange: (CGRect, MiniPlayerAccessoryPlacement) -> Void
    let onSwiftUIFrameChange: (CGRect) -> Void
    let landingTextScale: CGFloat
    let landingTextOffset: CGFloat
    let isVisible: Bool

    private var placement: MiniPlayerAccessoryPlacement {
        switch systemPlacement {
        case .inline: return .inline
        case .expanded: return .expanded
        case nil: return .undefined
        @unknown default: return .undefined
        }
    }

    var body: some View {
        MiniPlayerAccessory(
            onExpand: onExpand,
            onArtworkFrameChange: onArtworkFrameChange,
            onTransitionGeometryChange: onTransitionGeometryChange,
            placement: placement,
            // The inline accessory is the compact player shown after the tab
            // bar minimizes on scroll. Keep the forward control in the larger
            // expanded mini player only.
            showsNextButton: placement != .inline,
            landingTextScale: landingTextScale,
            landingTextOffset: landingTextOffset
        )
        // Retained only as a DEBUG comparison. This is SwiftUI content,
        // not the system-owned rounded accessory surface.
        .debugReportPlayerAccessoryFrame(onSwiftUIFrameChange)
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
        .background {
            NativeTabAccessorySurfaceReporter(placement: placement) { frame, placement in
                onSurfaceFrameChange(frame, placement)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
    }
}

@available(iOS 26.0, *)
private struct NativeTabAccessorySurfaceReporter: UIViewRepresentable {
    let placement: MiniPlayerAccessoryPlacement
    let action: (CGRect, MiniPlayerAccessoryPlacement) -> Void

    func makeUIView(context: Context) -> NativeTabAccessorySurfaceProbeView {
        let view = NativeTabAccessorySurfaceProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: NativeTabAccessorySurfaceProbeView, context: Context) {
        uiView.placement = placement
        uiView.action = action
        uiView.scheduleReport()
    }
}

@available(iOS 26.0, *)
private final class NativeTabAccessorySurfaceProbeView: UIView {
    var placement: MiniPlayerAccessoryPlacement = .undefined
    var action: ((CGRect, MiniPlayerAccessoryPlacement) -> Void)?
    private var lastFrame: CGRect = .zero
    private var lastPlacement: MiniPlayerAccessoryPlacement = .undefined
    private var reportScheduled = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        scheduleReport()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scheduleReport()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        scheduleReport()
    }

    func scheduleReport() {
        guard !reportScheduled else { return }
        reportScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reportScheduled = false
            self.reportSurfaceFrame()
        }
    }

    private func reportSurfaceFrame() {
        guard let window,
              let tabBarController = containingTabBarController(),
              let surface = tabBarController.bottomAccessory?.contentView else { return }
        let hostFrame = surface.convert(surface.bounds, to: window)
        let visibleSurfaceBounds = surface.safeAreaLayoutGuide.layoutFrame
        let frame = surface.convert(visibleSurfaceBounds, to: window)
#if DEBUG
        if !lastFrame.isApproximatelyEqual(to: frame) || lastPlacement != placement {
            let insets = surface.safeAreaInsets
            print(
                "TAB_ACCESSORY_NATIVE host=\(hostFrame.debugDescription) "
                    + "visibleSurface=\(frame.debugDescription) "
                    + "safeInsets=top:\(insets.top),left:\(insets.left),"
                    + "bottom:\(insets.bottom),right:\(insets.right) "
                    + "placement=\(placement.rawValue)"
            )
        }
#endif
        guard frame.isMeaningful,
              !lastFrame.isApproximatelyEqual(to: frame)
                || lastPlacement != placement else { return }
        lastFrame = frame
        lastPlacement = placement
        action?(frame, placement)
    }

    private func containingTabBarController() -> UITabBarController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let tabBarController = current as? UITabBarController {
                return tabBarController
            }
            responder = current.next
        }
        guard let root = window?.rootViewController else { return nil }
        return findTabBarController(in: root)
    }

    private func findTabBarController(in controller: UIViewController) -> UITabBarController? {
        if let tabBarController = controller as? UITabBarController,
           isDescendant(of: tabBarController.view) {
            return tabBarController
        }
        if let presented = controller.presentedViewController,
           let match = findTabBarController(in: presented) {
            return match
        }
        for child in controller.children {
            if let match = findTabBarController(in: child) {
                return match
            }
        }
        return nil
    }
}

@available(iOS 26.0, *)
private struct ModernMiniPlayerModifier<Accessory: View>: ViewModifier {
    let shouldShow: Bool
    @ViewBuilder var accessory: () -> Accessory

    @ViewBuilder
    func body(content: Content) -> some View {
        if shouldShow {
            content.tabViewBottomAccessory {
                accessory()
            }
        } else {
            content
        }
    }
}
