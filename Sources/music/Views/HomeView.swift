import SwiftUI

enum HomeRoute: Hashable {
    case album(Album)
    case playlist(Playlist)
    case artist(Artist)
    case mix(MusicMix)
    case recentlyPlayedAll
    case newReleasesAll
}

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Binding var path: [HomeRoute]

    private var vm: HomeViewModel { appState.homeViewModel }
    @State private var showSettings = false
    @Namespace private var heroNamespace

    private let pad = Theme.Layout.screenPadding

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if vm.isLoading && !vm.hasLoaded {
                    loadingState
                } else if isEmpty {
                    emptyState
                } else {
                    sections
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ServerMenuButton(onOpenSettings: { showSettings = true })
                }
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .navigationDestination(for: HomeRoute.self) { route in
                destination(for: route)
            }
            .environment(\.heroNamespace, heroNamespace)
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .task(id: appState.currentServer?.id) {
            if !vm.hasLoaded { await vm.load(appState: appState) }
        }
    }

    @ViewBuilder
    private func destination(for route: HomeRoute) -> some View {
        switch route {
        case .album(let album):
            AlbumDetailView(album: album)
                .navigationTransition(.zoom(sourceID: album.id, in: heroNamespace))
        case .playlist(let pl):
            PlaylistDetailView(playlist: pl)
                .navigationTransition(.zoom(sourceID: pl.id, in: heroNamespace))
        case .artist(let artist):
            ArtistDetailView(artist: artist)
        case .mix(let mix):
            MixDetailView(mix: mix)
        case .recentlyPlayedAll:
            FullMediaGrid(title: "Recently Played", items: vm.recentlyPlayed) { item in
                navigate(to: item)
            }
        case .newReleasesAll:
            FullMediaGrid(title: "Recently Added", items: vm.newReleases.map(MediaItem.init(album:))) { item in
                navigate(to: item)
            }
        }
    }

    private func navigate(to item: MediaItem) {
        switch item.kind {
        case .album:
            if let album = item.albumRef { path.append(.album(album)) }
        case .playlist:
            if let pl = item.playlistRef { path.append(.playlist(pl)) }
        }
    }

    private var isEmpty: Bool {
        vm.hasLoaded &&
        vm.picks.isEmpty && vm.recentlyPlayed.isEmpty &&
        vm.moreLike.isEmpty && vm.discover.isEmpty &&
        vm.newReleases.isEmpty && vm.topArtists.isEmpty
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.sectionSpacing) {
            Text("Home")
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, pad)
                .padding(.top, 4)

            if !vm.picksFeed.isEmpty {
                section(title: "Picks for You") {
                    HorizontalPickRow(items: vm.picksFeed,
                        onSelectAlbum: { path.append(.album($0)) },
                        onSelectMix: { path.append(.mix($0)) })
                }
            }

            if !vm.recentlyPlayed.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeaderView("Recently Played") {
                        path.append(.recentlyPlayedAll)
                    }
                    .padding(.horizontal, pad)
                    HorizontalMediaRow(items: vm.recentlyPlayed) { item in
                        navigate(to: item)
                    }
                }
            }

            if !vm.topArtists.isEmpty {
                section(title: "Artists") {
                    ArtistScrollRow(artists: vm.topArtists) { artist in
                        path.append(.artist(artist))
                    }
                }
            }

            ForEach(vm.moreLike) { item in
                section(title: "More Like \(item.artistName)") {
                    HorizontalMediaRow(items: item.albums.map(MediaItem.init(album:))) { mediaItem in
                        if let album = mediaItem.albumRef { path.append(.album(album)) }
                    }
                }
            }

            if !vm.discover.isEmpty {
                section(title: "Discover") {
                    HorizontalMediaRow(items: vm.discover.map(MediaItem.init(album:))) { mediaItem in
                        if let album = mediaItem.albumRef { path.append(.album(album)) }
                    }
                }
            }

            if !vm.newReleases.isEmpty {
                section(title: "Recently Added", seeAll: { path.append(.newReleasesAll) }) {
                    HorizontalMediaRow(items: vm.newReleases.map(MediaItem.init(album:))) { mediaItem in
                        if let album = mediaItem.albumRef { path.append(.album(album)) }
                    }
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 120)
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        seeAll: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeaderView(title, onSeeAll: seeAll)
                .padding(.horizontal, pad)
            content()
        }
    }

    private var loadingState: some View {
        VStack {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)
                .padding(.top, 120)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Artist scroll row

    private struct ArtistScrollRow: View {
        let artists: [Artist]
        var onTap: (Artist) -> Void

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 18) {
                    ForEach(artists) { artist in
                        Button { onTap(artist) } label: {
                            VStack(spacing: 8) {
                                ArtworkView(coverArtID: artist.coverArt, size: 200, cornerRadius: 44)
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                                    .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 1))
                                Text(artist.name)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Theme.primaryText)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 80)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Layout.screenPadding)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: Symbols.warning)
                .font(.system(size: 34))
                .foregroundStyle(Theme.secondaryText)
            Text("Nothing here yet")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text("Your library looks empty or the server is unreachable.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .padding(.top, 120)
        .frame(maxWidth: .infinity)
    }
}
