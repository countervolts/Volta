import SwiftUI
import UIKit

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
    @State private var playerSnapshot: PlayerTransitionSnapshot?
    @State private var playerPresentationTask: Task<Void, Never>?
    @State private var isPlayerTransitioning = false
    @State private var isPlayerDismissGestureActive = false

    @State private var homePath = NavigationPath()
    @State private var libraryPath = NavigationPath()
    @State private var playlistsPath = NavigationPath()
    @State private var searchPath = NavigationPath()
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var audio: AudioPlayer { appState.audioPlayer }
    private var shouldShowMiniPlayer: Bool {
        audio.hasActivePlaybackSession && audio.currentSong != nil
    }
    private var reducesPlayerMotion: Bool {
        accessibilityReduceMotion || PerformanceMode.reduceAnimations
    }
    private var playerPresentationDuration: Double {
        reducesPlayerMotion ? 0.16 : 0.45
    }
    private func playerPresentationAnimation(duration: Double) -> Animation {
        .smooth(duration: duration)
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
                    PlayerExpansionAnimator(
                        progress: playerExpansionProgress,
                        isTransitioning: isPlayerTransitioning || isPlayerDismissGestureActive
                    ) { progress in
                        let reveal = min(max((progress - 0.55) / 0.35, 0), 1)
                        NowPlayingScreen(
                            isPresented: nowPlayingPresentationBinding,
                            onDismissDragChanged: updatePlayerDismissDrag,
                            onDismissDragCancelled: cancelPlayerDismissDrag,
                            onDismissDragEnded: { dismissNowPlaying(from: $0) }
                        )
                        .opacity(reveal)
                        .mask {
                            PlayerExpansionClipMask(
                                progress: progress,
                                sourceFrame: miniPlayerFrame,
                                safeAreaInsets: rootGeo.safeAreaInsets
                            )
                        }
                    }
                    .allowsHitTesting(
                        isPlayerDismissGestureActive
                            || (!isPlayerTransitioning && playerExpansionProgress >= 0.999)
                    )
                    .accessibilityHidden(isPlayerTransitioning)
                    .zIndex(9)

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
                            reduceMotion: reducesPlayerMotion
                        )
                    }
                    .allowsHitTesting(false)
                    .zIndex(10)
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
        }
        .onDisappear {
            playerPresentationTask?.cancel()
            playerPresentationTask = nil
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
            }
        }
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
                LibraryView(path: $libraryPath)
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

    @ViewBuilder
    private var modernMiniPlayerAccessory: some View {
        MiniPlayerAccessory(
            onExpand: presentNowPlaying,
            onArtworkFrameChange: recordMiniArtworkFrame
        )
            .padding(.horizontal, 12)
            .padding(.bottom, 2)
            .reportPlayerAccessoryFrame(recordMiniPlayerFrame)
            .allowsHitTesting(!playerOverlayMounted)
            .accessibilityHidden(playerOverlayMounted)
    }

    private var legacyTabs: some View {
        TabView(selection: tabSelection) {
            legacyTabPage {
                HomeView(path: $homePath)
            }
                .tabItem { Label(L(.tab_home), systemImage: Symbols.home) }
                .tag(0)

            legacyTabPage {
                LibraryView(path: $libraryPath)
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
                onArtworkFrameChange: recordMiniArtworkFrame
            )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 10)
                .reportPlayerAccessoryFrame(recordMiniPlayerFrame)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
                .allowsHitTesting(!playerOverlayMounted)
                .accessibilityHidden(playerOverlayMounted)
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
        let snapshot = PlayerTransitionSnapshot(
            artwork: audio.currentLiveArtwork?.previewImage ?? audio.currentArtwork,
            nativeMiniPlayer: captureNativeMiniPlayer(in: miniPlayerFrame),
            targetArtworkScale: transitionArtworkScale(usesFullBleedArtwork: usesFullBleedArtwork),
            usesLiveArtwork: audio.currentLiveArtwork != nil,
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
        }

        playerPresentationTask = Task { @MainActor in
            // Give the p=0 proxy one render pass while the real accessory is
            // still present, then hand visual ownership to the proxy atomically.
            await Task.yield()
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(playerPresentationAnimation(duration: playerPresentationDuration)) {
                playerExpansionProgress = 1
            }
            try? await Task.sleep(
                nanoseconds: UInt64((playerPresentationDuration + 0.06) * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            isPlayerTransitioning = false
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

    private func dismissNowPlaying(from dragOffset: CGFloat? = nil) {
        guard playerOverlayMounted else {
            showNowPlaying = false
            return
        }

        playerPresentationTask?.cancel()
        let startProgress = dragOffset.map { interactivePlayerProgress(for: $0) }
            ?? playerExpansionProgress
        let duration = playerPresentationDuration * Double(startProgress)

        var startTransaction = Transaction()
        startTransaction.disablesAnimations = true
        withTransaction(startTransaction) {
            showNowPlaying = false
            isPlayerTransitioning = true
            isPlayerDismissGestureActive = false
            playerExpansionProgress = startProgress
        }

        if audio.currentSong != nil {
            let refreshedSnapshot = PlayerTransitionSnapshot(
                artwork: audio.currentLiveArtwork?.previewImage ?? audio.currentArtwork,
                nativeMiniPlayer: playerSnapshot?.nativeMiniPlayer,
                targetArtworkScale: transitionArtworkScale(
                    usesFullBleedArtwork: usesFullBleedArtwork
                ),
                usesLiveArtwork: audio.currentLiveArtwork != nil,
                usesFullBleedArtwork: usesFullBleedArtwork
            )
            var snapshotTransaction = Transaction()
            snapshotTransaction.disablesAnimations = true
            withTransaction(snapshotTransaction) {
                playerSnapshot = refreshedSnapshot
            }
        }

        withAnimation(playerPresentationAnimation(duration: duration)) {
            playerExpansionProgress = 0
        }

        playerPresentationTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: UInt64((duration + 0.04) * 1_000_000_000)
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
            }
            playerPresentationTask = nil
        }
    }

    private func updatePlayerDismissDrag(_ translation: CGFloat) {
        guard playerOverlayMounted, !isPlayerTransitioning else { return }
        let offset = max(0, translation)
        playerPresentationTask?.cancel()
        playerPresentationTask = nil

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isPlayerDismissGestureActive = offset > 0
            playerExpansionProgress = interactivePlayerProgress(for: offset)
        }
    }

    private func cancelPlayerDismissDrag() {
        guard playerOverlayMounted, isPlayerDismissGestureActive else { return }
        playerPresentationTask?.cancel()
        let duration = playerPresentationDuration * Double(1 - playerExpansionProgress)

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isPlayerDismissGestureActive = false
            isPlayerTransitioning = true
        }

        withAnimation(playerPresentationAnimation(duration: duration)) {
            playerExpansionProgress = 1
        }

        playerPresentationTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: UInt64((duration + 0.02) * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            isPlayerTransitioning = false
            playerPresentationTask = nil
        }
    }

    private var playerDismissTravel: CGFloat {
        if miniPlayerFrame.isMeaningful {
            return max(1, miniPlayerFrame.midY)
        }
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

    private func recordMiniPlayerFrame(_ frame: CGRect) {
        guard !isPlayerTransitioning, frame.isMeaningful else { return }
        if !miniPlayerFrame.isApproximatelyEqual(to: frame) {
            miniPlayerFrame = frame
        }
    }

    private func recordMiniArtworkFrame(_ frame: CGRect) {
        guard !isPlayerTransitioning, frame.isMeaningful else { return }
        if !miniArtworkFrame.isApproximatelyEqual(to: frame) {
            miniArtworkFrame = frame
        }
    }

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

    /// Captures the composited system accessory, including Liquid Glass. A
    /// hand-built SwiftUI proxy cannot reproduce the native material exactly.
    private func captureNativeMiniPlayer(in frame: CGRect) -> UIImage? {
        guard frame.isMeaningful else { return nil }
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        guard let window = scenes
            .flatMap(\.windows)
            .first(where: \UIWindow.isKeyWindow)
                ?? scenes.flatMap(\.windows).first(where: { !$0.isHidden }) else {
            return nil
        }

        let crop = frame.standardized.intersection(window.bounds)
        guard crop.isMeaningful else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        format.opaque = false
        var didDraw = false
        let image = UIGraphicsImageRenderer(size: crop.size, format: format).image { context in
            context.cgContext.translateBy(x: -crop.minX, y: -crop.minY)
            didDraw = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        return didDraw ? image : nil
    }
}

private struct PlayerTransitionSnapshot {
    let artwork: UIImage?
    let nativeMiniPlayer: UIImage?
    let targetArtworkScale: CGFloat
    let usesLiveArtwork: Bool
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

/// Prevents the mounted full-player view from bleeding outside the card while
/// its transition proxy expands or contracts above the tab content.
private struct PlayerExpansionClipMask: View {
    let progress: CGFloat
    let sourceFrame: CGRect
    let safeAreaInsets: EdgeInsets

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
            let card = CGRect(
                x: source.minX + (destination.minX - source.minX) * p,
                y: source.minY + (destination.minY - source.minY) * p,
                width: source.width + (destination.width - source.width) * p,
                height: source.height + (destination.height - source.height) * p
            )
            let radius = min(source.height / 2, 30) * (1 - p)

            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .frame(width: card.width, height: card.height)
                .position(x: card.midX, y: card.midY)
        }
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

    init(
        progress: CGFloat,
        sourceFrame: CGRect,
        sourceArtworkFrame: CGRect,
        safeAreaInsets: EdgeInsets,
        snapshot: PlayerTransitionSnapshot,
        reduceMotion: Bool
    ) {
        self.progress = progress
        self.sourceFrame = sourceFrame
        self.sourceArtworkFrame = sourceArtworkFrame
        self.safeAreaInsets = safeAreaInsets
        self.snapshot = snapshot
        self.reduceMotion = reduceMotion
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
            let cardRadius = interpolate(
                min(source.height / 2, 30),
                0,
                p
            )
            let heroFrame = artworkFrame(
                source: sourceArtwork,
                size: geo.size,
                progress: p
            )
            let heroOpacity = linearRamp(p, from: 0.08, to: 0.24)
                * (1 - linearRamp(p, from: 0.93, to: 1))
            let surfaceFade = snapshot.usesLiveArtwork
                ? linearRamp(p, from: 0.32, to: 0.62)
                : linearRamp(p, from: 0.78, to: 1)
            let surfaceOpacity = reduceMotion
                ? linearRamp(p, from: 0.04, to: 0.60) * (1 - surfaceFade)
                : linearRamp(p, from: 0.03, to: 0.18) * (1 - surfaceFade)
            let nativeMiniOpacity = reduceMotion
                ? 1 - linearRamp(p, from: 0, to: 0.42)
                : 1 - linearRamp(p, from: 0.08, to: 0.30)
            let dimFade = snapshot.usesLiveArtwork
                ? linearRamp(p, from: 0.38, to: 0.68)
                : linearRamp(p, from: 0.84, to: 1)

            ZStack {
                Color.black
                    .opacity(
                        0.38
                            * linearRamp(p, from: 0.06, to: 0.62)
                            * (1 - dimFade)
                    )
                    .ignoresSafeArea()

                transitionSurface(frame: card, radius: cardRadius, progress: p)
                    .opacity(surfaceOpacity)

                nativeMiniPlayerSnapshot(frame: source)
                    .opacity(nativeMiniOpacity)

                heroArtwork(frame: heroFrame, progress: p)
                    .opacity(reduceMotion ? 0 : heroOpacity)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func transitionSurface(
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
        .frame(width: frame.width, height: frame.height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.white.opacity(interpolate(0.12, 0.035, progress)), lineWidth: 0.6)
        }
        .shadow(
            color: .black.opacity(interpolate(0.24, 0.48, progress)),
            radius: interpolate(12, 30, progress),
            y: interpolate(7, 14, progress)
        )
        .position(x: frame.midX, y: frame.midY)
    }

    @ViewBuilder
    private func nativeMiniPlayerSnapshot(frame: CGRect) -> some View {
        if let image = snapshot.nativeMiniPlayer {
            Image(uiImage: image)
                .resizable()
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .allowsHitTesting(false)
        }
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

    private func cardFrame(source: CGRect, size: CGSize, progress: CGFloat) -> CGRect {
        if reduceMotion {
            return CGRect(origin: .zero, size: size)
        }

        let destination = CGRect(origin: .zero, size: size)
        return interpolate(source, destination, progress)
    }

    private func artworkFrame(source: CGRect, size: CGSize, progress: CGFloat) -> CGRect {
        let target: CGRect
        if snapshot.usesFullBleedArtwork {
            target = CGRect(
                x: 0,
                y: -safeAreaInsets.top,
                width: size.width,
                height: size.width + safeAreaInsets.top
            )
        } else {
            let side = max(0, size.width - 48)
            let scaledSide = side * snapshot.targetArtworkScale
            let inset = (side - scaledSide) / 2
            target = CGRect(
                x: 24 + inset,
                y: 32 + inset,
                width: scaledSide,
                height: scaledSide
            )
        }
        let artworkProgress = reduceMotion
            ? linearRamp(progress, from: 0.10, to: 0.92)
            : progress
        return interpolate(source, target, artworkProgress)
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
