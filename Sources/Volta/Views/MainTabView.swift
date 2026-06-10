import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("accentColorName") private var accentColorName = "purple"
    @AppStorage("customAccentRed") private var customAccentRed = 0.55
    @AppStorage("customAccentGreen") private var customAccentGreen = 0.36
    @AppStorage("customAccentBlue") private var customAccentBlue = 0.96
    @AppStorage("developerPerformanceOverlay") private var developerPerformanceOverlay = false
    @State private var selectedTab = 0
    @State private var showNowPlaying = false

    @State private var homePath:      [HomeRoute]    = []
    @State private var libraryPath:   [LibraryRoute] = []
    @State private var playlistsPath: [Playlist]     = []
    @State private var searchPath:    [SearchRoute]  = []

    private var audio: AudioPlayer { appState.audioPlayer }
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
        ZStack {
            tabContent

            if showNowPlaying {
                NowPlayingScreen(isPresented: $showNowPlaying)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
        .animation(.easeInOut(duration: 0.2), value: accentRefreshKey)
        .preferredColorScheme(Theme.colorScheme)
        .onAppear {
            AppDiagnostics.logMainTabDecision()
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
                .tabViewBottomAccessory(isEnabled: audio.currentSong != nil) {
                    modernMiniPlayerAccessory
                }
        } else {
            modernTabView
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    legacyMiniPlayer
                }
        }
    }

    private var modernMiniPlayerAccessory: some View {
        MiniPlayerAccessory(onExpand: presentNowPlaying)
            .padding(.horizontal, 12)
            .padding(.bottom, 2)
    }

    @available(iOS 26.0, *)
    private var modernTabView: some View {
        TabView(selection: tabSelection) {
            Tab("Home", systemImage: Symbols.home, value: 0) {
                HomeView(path: $homePath)
            }
            Tab("Library", systemImage: Symbols.library, value: 1) {
                LibraryView(path: $libraryPath)
            }
            Tab("Playlists", systemImage: Symbols.playlists, value: 2) {
                PlaylistsView(path: $playlistsPath)
            }
            Tab("Stats", systemImage: Symbols.stats, value: 3) {
                StatsView()
            }
            Tab("Search", systemImage: Symbols.search, value: 4, role: .search) {
                SearchView(path: $searchPath)
            }
        }
        .tabBarMinimizeBehavior(audio.currentSong != nil ? .onScrollDown : .automatic)
        .tint(Theme.accent)
    }

    private var legacyTabs: some View {
        TabView(selection: tabSelection) {
            legacyTabPage {
                HomeView(path: $homePath)
            }
                .tabItem { Label("Home", systemImage: Symbols.home) }
                .tag(0)

            legacyTabPage {
                LibraryView(path: $libraryPath)
            }
                .tabItem { Label("Library", systemImage: Symbols.library) }
                .tag(1)

            legacyTabPage {
                PlaylistsView(path: $playlistsPath)
            }
                .tabItem { Label("Playlists", systemImage: Symbols.playlists) }
                .tag(2)

            legacyTabPage {
                StatsView()
            }
                .tabItem { Label("Stats", systemImage: Symbols.stats) }
                .tag(3)

            legacyTabPage {
                SearchView(path: $searchPath)
            }
                .tabItem { Label("Search", systemImage: Symbols.search) }
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
        if audio.currentSong != nil {
            MiniPlayerAccessory(onExpand: presentNowPlaying)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 10)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
        }
    }

    private func presentNowPlaying() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            showNowPlaying = true
        }
    }
}
