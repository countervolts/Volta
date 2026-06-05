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
    @State private var toastMessage: String?
    @State private var savingMixIDs = Set<String>()
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
                .zoomNavigationTransition(sourceID: album.id, in: heroNamespace)
        case .playlist(let pl):
            PlaylistDetailView(playlist: pl)
                .zoomNavigationTransition(sourceID: pl.id, in: heroNamespace)
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
                        onSelectMix: { path.append(.mix($0)) },
                        onSaveMix: { saveMixAsPlaylist($0) },
                        isSavingMix: { savingMixIDs.contains($0.id) })
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
        .overlay(alignment: .bottom) {
            if let toastMessage {
                PlaybackActionToast(message: toastMessage)
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toastMessage)
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

    private func saveMixAsPlaylist(_ mix: MusicMix) {
        guard !savingMixIDs.contains(mix.id), let client = appState.client else { return }
        savingMixIDs.insert(mix.id)
        showToast("Saving \(mix.title)")

        Task {
            do {
                let name = try await uniquePlaylistName(for: mix.title, client: client)
                guard let playlist = try await client.createPlaylist(name: name) else {
                    throw MixSaveError.createFailed
                }
                for song in mix.songs {
                    try await client.addToPlaylist(playlistID: playlist.id, songID: song.id)
                }
                AppLogger.shared.log("Saved mix '\(mix.title)' as playlist '\(name)' (\(mix.songs.count) songs)", category: .other)
                await MainActor.run {
                    savingMixIDs.remove(mix.id)
                    showToast("Saved to \(name)")
                }
            } catch {
                AppLogger.shared.log("Failed saving mix '\(mix.title)' as playlist: \(error.localizedDescription)", category: .other, level: .error)
                await MainActor.run {
                    savingMixIDs.remove(mix.id)
                    showToast("Couldn't save mix")
                }
            }
        }
    }

    private func uniquePlaylistName(for title: String, client: SubsonicClient) async throws -> String {
        let base = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Saved Mix" : title
        let existing = Set((try await client.playlists()).map { $0.name.lowercased() })
        guard existing.contains(base.lowercased()) else { return base }
        for index in 2...99 {
            let candidate = "\(base) \(index)"
            if !existing.contains(candidate.lowercased()) {
                return candidate
            }
        }
        return "\(base) \(Date().formatted(date: .numeric, time: .shortened))"
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation { toastMessage = nil }
            }
        }
    }
}

private enum MixSaveError: LocalizedError {
    case createFailed

    var errorDescription: String? {
        "The server did not return a playlist."
    }
}
