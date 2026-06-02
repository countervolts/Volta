import SwiftUI

// Native iOS 26 Liquid Glass tab bar.
//
// Everything that used to be hand-rolled in BottomBar is now system-native:
//   • Tab(role: .search)            → tab bar morphs into a search field
//   • .tabBarMinimizeBehavior       → tab bar collapses on scroll down
//   • .tabViewBottomAccessory       → mini player rides above the bar and
//                                     collapses INTO it with the same motion
//                                     Apple Music uses.
//
// CRITICAL: the accessory modifier is ALWAYS applied; visibility is driven by
// the iOS 26.1 `isEnabled:` overload. Conditionally adding/removing the modifier
// produces two different view types → SwiftUI gives the whole TabView a new
// identity → it tears down + rebuilds (flash, dead swipe-back). A single stable
// type with a Bool flag avoids that entirely, and `isEnabled: false` collapses
// the glass capsule so nothing shows when no song is loaded.
struct MainTabView: View {
    @Environment(AppState.self) private var appState
    // observe accent so the tab bar + accessory tint refresh live on change
    @AppStorage("accentColorName") private var accentColorName = "purple"
    @State private var selectedTab = 0
    @State private var showNowPlaying = false

    // Paths hoisted here as belt-and-suspenders so navigation survives any
    // TabView re-evaluation.
    @State private var homePath:      [HomeRoute]    = []
    @State private var libraryPath:   [LibraryRoute] = []
    @State private var playlistsPath: [Playlist]     = []
    @State private var searchPath:    [SearchRoute]  = []

    private var audio: AudioPlayer { appState.audioPlayer }

    var body: some View {
        ZStack {
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

            if showNowPlaying {
                NowPlayingScreen(isPresented: $showNowPlaying)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.85), value: showNowPlaying)
        .preferredColorScheme(.dark)
    }
}
