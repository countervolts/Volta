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
    @State private var networkMonitor = NetworkMonitor.shared
    @Namespace private var heroNamespace

    private let pad = Theme.Layout.screenPadding

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                homeBody
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .navigationDestination(for: HomeRoute.self) { route in
                destination(for: route)
            }
            .environment(\.heroNamespace, heroNamespace)
        }
        .tint(Theme.accent)
        .preferredColorScheme(Theme.colorScheme)
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
                .zoomNavigationTransition(sourceID: mix.id, in: heroNamespace)
        case .recentlyPlayedAll:
            FullMediaGrid(title: L(.home_recently_played), items: vm.recentlyPlayed) { item in
                navigate(to: item)
            }
        case .newReleasesAll:
            FullMediaGrid(title: L(.home_recently_added), items: vm.newReleases.map(MediaItem.init(album:))) { item in
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

    private var isServerUnavailable: Bool {
        networkMonitor.connection == .none || vm.serverUnavailable
    }

    @ViewBuilder
    private var homeBody: some View {
        if isServerUnavailable {
            let downloads = downloadedSongs
            if downloads.isEmpty {
                serverUnavailableState
            } else {
                offlineHome(downloads)
            }
        } else if vm.isLoading && !vm.hasLoaded {
            loadingState
        } else if isEmpty {
            emptyState
        } else {
            sections
        }
    }

    // MARK: - Offline home (built from downloaded music)

    private var downloadedSongs: [Song] {
        DownloadService.shared.downloadedSongs()
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func downloadedAlbums(from songs: [Song]) -> [Album] {
        var byID: [String: Album] = [:]
        for song in songs {
            guard let aid = song.albumId, byID[aid] == nil else { continue }
            byID[aid] = Album(
                id: aid, name: song.album ?? "Unknown Album", artist: song.artist,
                artistId: song.artistId, coverArt: song.coverArt, songCount: nil,
                duration: nil, playCount: nil, created: nil, year: song.year,
                genre: song.genre, starred: nil, comment: nil, recordLabel: nil, song: nil
            )
        }
        return byID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func offlineHome(_ songs: [Song]) -> some View {
        let albums = downloadedAlbums(from: songs)
        return VStack(alignment: .leading, spacing: Theme.Layout.sectionSpacing) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L(.home_offline))
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Text(L(.home_downloaded_music))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                ServerMenuButton(onOpenSettings: { showSettings = true })
            }
            .padding(.horizontal, pad)
            .padding(.top, 2)

            HStack(spacing: 12) {
                Button {
                    appState.audioPlayer.playQueue(songs, startIndex: 0, source: "Downloads")
                } label: {
                    Label(L(.action_play), systemImage: Symbols.play)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.accent, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    appState.audioPlayer.playQueue(songs.shuffled(), startIndex: 0, source: "Downloads")
                } label: {
                    Label(L(.action_shuffle), systemImage: Symbols.shuffle)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.secondaryBackground, in: Capsule())
                        .foregroundStyle(Theme.primaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, pad)

            if !albums.isEmpty {
                section(title: L(.home_downloaded_albums)) {
                    HorizontalMediaRow(items: albums.map(MediaItem.init(album:))) { item in
                        if let album = item.albumRef { path.append(.album(album)) }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                SectionHeaderView(L(.home_downloaded_songs))
                    .padding(.horizontal, pad)
                LazyVStack(spacing: 0) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        TrackRow(
                            song: song,
                            index: index + 1,
                            isCurrentlyPlaying: appState.audioPlayer.currentSong?.id == song.id,
                            onTap: { appState.audioPlayer.playQueue(songs, startIndex: index, source: "Downloads") },
                            showArtist: true,
                            leadingArtwork: true,
                            onSwipePlayNext: { appState.audioPlayer.playNext(song) }
                        ) {
                            SongMenu(
                                song: song,
                                onDelete: { DownloadService.shared.removeDownload(for: song) },
                                deleteLabel: L(.action_remove_download)
                            )
                        }
                        .padding(.horizontal, pad)
                    }
                }
            }
        }
        .padding(.top, -10)
        .padding(.bottom, 120)
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.sectionSpacing) {
            homeHeader

            if !vm.picksFeed.isEmpty {
                section(title: L(.home_picks_for_you)) {
                    HorizontalPickRow(items: vm.picksFeed,
                        onSelectAlbum: { path.append(.album($0)) },
                        onSelectMix: { path.append(.mix($0)) },
                        onSaveMix: { saveMixAsPlaylist($0) },
                        isSavingMix: { savingMixIDs.contains($0.id) })
                }
            }

            if !vm.recentlyPlayed.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeaderView(L(.home_recently_played)) {
                        path.append(.recentlyPlayedAll)
                    }
                    .padding(.horizontal, pad)
                    HorizontalMediaRow(items: vm.recentlyPlayed) { item in
                        navigate(to: item)
                    }
                }
            }

            if !vm.topArtists.isEmpty {
                section(title: L(.home_artists)) {
                    ArtistScrollRow(artists: vm.topArtists) { artist in
                        path.append(.artist(artist))
                    }
                }
            }

            ForEach(vm.moreLike) { item in
                section(title: L(.home_more_like, item.artistName)) {
                    HorizontalMediaRow(items: item.albums.map(MediaItem.init(album:))) { mediaItem in
                        if let album = mediaItem.albumRef { path.append(.album(album)) }
                    }
                }
            }

            if !vm.discover.isEmpty {
                section(title: L(.home_discover)) {
                    HorizontalMediaRow(items: vm.discover.map(MediaItem.init(album:))) { mediaItem in
                        if let album = mediaItem.albumRef { path.append(.album(album)) }
                    }
                }
            }

            if !vm.newReleases.isEmpty {
                section(title: L(.home_recently_added), seeAll: { path.append(.newReleasesAll) }) {
                    HorizontalMediaRow(items: vm.newReleases.map(MediaItem.init(album:))) { mediaItem in
                        if let album = mediaItem.albumRef { path.append(.album(album)) }
                    }
                }
            }
        }
        .padding(.top, -10)
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

    private var homeHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(L(.tab_home))
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)

            Spacer()

            ServerMenuButton(onOpenSettings: { showSettings = true })
        }
        .padding(.horizontal, pad)
        .padding(.top, 2)
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
            Text(L(.home_nothing_here))
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text(L(.home_empty_message))
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .padding(.top, 120)
        .frame(maxWidth: .infinity)
    }

    private var serverUnavailableState: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 38, weight: .ultraLight))
                .foregroundStyle(Theme.secondaryText)
            Text(L(.home_server_unreachable))
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text(L(.home_server_unreachable_message))
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button {
                Task { await vm.load(appState: appState, force: true) }
            } label: {
                Label(L(.action_retry_connection), systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 40)
        .padding(.top, 120)
        .frame(maxWidth: .infinity)
    }

    private func saveMixAsPlaylist(_ mix: MusicMix) {
        guard !savingMixIDs.contains(mix.id), let client = appState.client else { return }
        savingMixIDs.insert(mix.id)
        let title = mix.localizedTitle
        showToast(L(.home_saving_mix, title))

        Task {
            do {
                let name = try await PlaylistWriter.saveMixAsPlaylist(mix, client: client, title: title)
                await MainActor.run {
                    savingMixIDs.remove(mix.id)
                    showToast(L(.home_saved_to, name))
                }
            } catch {
                AppLogger.shared.log("Failed saving mix '\(mix.title)' as playlist: \(error.localizedDescription)", category: .other, level: .error)
                await MainActor.run {
                    savingMixIDs.remove(mix.id)
                    showToast(L(.home_save_mix_failed))
                }
            }
        }
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
