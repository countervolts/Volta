import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("accentColorName") private var accentColorName = "purple"
    @AppStorage("customAccentRed") private var customAccentRed = 0.55
    @AppStorage("customAccentGreen") private var customAccentGreen = 0.36
    @AppStorage("customAccentBlue") private var customAccentBlue = 0.96
    @State private var selectedTab = 0
    @State private var showNowPlaying = false

    @State private var homePath:      [HomeRoute]    = []
    @State private var libraryPath:   [LibraryRoute] = []
    @State private var playlistsPath: [Playlist]     = []
    @State private var searchPath:    [SearchRoute]  = []

    private var audio: AudioPlayer { appState.audioPlayer }
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
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.85), value: showNowPlaying)
        .animation(.easeInOut(duration: 0.2), value: accentRefreshKey)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var tabContent: some View {
        if #available(iOS 26.1, *) {
            modernTabs
        } else {
            legacyTabs
        }
    }

    @available(iOS 26.1, *)
    private var modernTabs: some View {
        TabView(selection: $selectedTab) {
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
        .tabViewBottomAccessory(isEnabled: audio.currentSong != nil) {
            MiniPlayerAccessory(onExpand: { showNowPlaying = true })
        }
        .tint(Theme.accent)
    }

    private var legacyTabs: some View {
        TabView(selection: $selectedTab) {
            HomeView(path: $homePath)
                .tabItem { Label("Home", systemImage: Symbols.home) }
                .tag(0)

            LibraryView(path: $libraryPath)
                .tabItem { Label("Library", systemImage: Symbols.library) }
                .tag(1)

            PlaylistsView(path: $playlistsPath)
                .tabItem { Label("Playlists", systemImage: Symbols.playlists) }
                .tag(2)

            StatsView()
                .tabItem { Label("Stats", systemImage: Symbols.stats) }
                .tag(3)

            SearchView(path: $searchPath)
                .tabItem { Label("Search", systemImage: Symbols.search) }
                .tag(4)
        }
        .safeAreaInset(edge: .bottom) {
            legacyMiniPlayer
        }
        .tint(Theme.accent)
    }

    @ViewBuilder
    private var legacyMiniPlayer: some View {
        if audio.currentSong != nil {
            MiniPlayerAccessory(onExpand: { showNowPlaying = true })
                .padding(.vertical, 8)
                .glassCard(cornerRadius: 18)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
        }
    }
}
