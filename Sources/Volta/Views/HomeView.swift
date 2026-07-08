import SwiftUI

enum HomeRoute: Hashable {
    case album(Album)
    case playlist(Playlist)
    case artist(Artist)
    case mix(MusicMix)
    case mediaGrid(title: String, items: [MediaItem])
}

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Binding var path: NavigationPath

    private var vm: HomeViewModel { appState.homeViewModel }
    @State private var toastMessage: String?
    @State private var savingMixIDs = Set<String>()
    @State private var networkMonitor = NetworkMonitor.shared
    @Namespace private var heroNamespace

    private let pad = Theme.Layout.screenPadding

    private struct HomeSectionSnapshot {
        var picksFeed: [PickFeedItem] = []
        var recentlyPlayed: [MediaItem] = []
        var topArtists: [Artist] = []
        var moreLike: [HomeViewModel.MoreLikeSection] = []
        var discover: [Album] = []
        var newReleases: [Album] = []
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                homeBody
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: HomeRoute.self) { route in
                destination(for: route)
            }
            .settingsDestinations()
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
        case .mediaGrid(let title, let items):
            FullMediaGrid(title: title, items: items) { item in
                navigate(to: item)
            }
        }
    }

    private func navigate(to item: MediaItem) {
        switch item.kind {
        case .album:
            if let album = item.albumRef { path.append(HomeRoute.album(album)) }
        case .playlist:
            if let pl = item.playlistRef { path.append(HomeRoute.playlist(pl)) }
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

    private func albumKey(for song: Song) -> String {
        song.albumId ?? "offline-album-\(song.album ?? song.id)"
    }

    private func artistKey(for song: Song) -> String {
        song.offlineArtistKey
    }

    private func stableSeed(_ text: String) -> UInt64 {
        text.unicodeScalars.reduce(UInt64(0xCBF29CE484222325)) { seed, scalar in
            (seed ^ UInt64(scalar.value)) &* 0x100000001B3
        }
    }

    private func downloadedAlbums(from songs: [Song]) -> [Album] {
        var grouped: [String: [Song]] = [:]
        for song in songs {
            let fallbackID = "offline-album-\(song.album ?? song.id)"
            grouped[song.albumId ?? fallbackID, default: []].append(song)
        }

        return grouped.map { id, albumSongs in
            let sortedSongs = albumSongs.sorted {
                let disc0 = $0.discNumber ?? 1
                let disc1 = $1.discNumber ?? 1
                if disc0 != disc1 { return disc0 < disc1 }
                return ($0.track ?? 0) < ($1.track ?? 0)
            }
            let first = sortedSongs[0]
            return Album(
                id: id,
                name: first.album ?? "Unknown Album",
                artist: first.primaryArtistName,
                artistId: first.primaryArtistID,
                coverArt: first.coverArt,
                songCount: sortedSongs.count,
                duration: sortedSongs.reduce(0) { $0 + ($1.duration ?? 0) },
                playCount: nil,
                created: nil,
                year: first.year,
                genre: first.genre,
                starred: nil,
                comment: nil,
                recordLabel: nil,
                song: sortedSongs
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func downloadedArtists(from songs: [Song]) -> [Artist] {
        var grouped: [String: [Song]] = [:]
        for song in songs {
            grouped[artistKey(for: song), default: []].append(song)
        }
        return grouped.map { id, artistSongs in
            let first = artistSongs[0]
            let albumIDs = Set(artistSongs.compactMap(\.albumId))
            return Artist(
                id: id,
                name: first.primaryArtistName,
                coverArt: first.coverArt,
                albumCount: max(1, albumIDs.count),
                artistImageUrl: nil,
                starred: nil,
                album: nil
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func offlineHome(_ songs: [Song]) -> some View {
        homeSections(offlineSections(from: songs))
    }

    private var sections: some View {
        homeSections(onlineSections)
    }

    private var onlineSections: HomeSectionSnapshot {
        HomeSectionSnapshot(
            picksFeed: vm.picksFeed,
            recentlyPlayed: vm.recentlyPlayed,
            topArtists: vm.topArtists,
            moreLike: vm.moreLike,
            discover: vm.discover,
            newReleases: vm.newReleases
        )
    }

    private func offlineSections(from songs: [Song]) -> HomeSectionSnapshot {
        let albums = downloadedAlbums(from: songs)
        let artists = downloadedArtists(from: songs)
        let recentSongs = DownloadService.shared.downloadedSongsByRecentPlay()
        let recentAlbums = albumsInSongOrder(recentSongs, fallback: albums)
        let recentlyPlayed = Array(recentAlbums.prefix(40)).map(MediaItem.init(album:))

        var discoverRNG = SeededRNG(seed: SeededRNG.daySeed() &+ 0xD154)
        let discover = Array(albums.shuffled(using: &discoverRNG).prefix(9))

        let newReleases = Array(albums.sorted {
            let lhsYear = $0.year ?? Int.min
            let rhsYear = $1.year ?? Int.min
            if lhsYear != rhsYear { return lhsYear > rhsYear }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }.prefix(40))

        return HomeSectionSnapshot(
            picksFeed: offlinePicks(songs: songs, albums: albums),
            recentlyPlayed: recentlyPlayed,
            topArtists: Array(artists.prefix(20)),
            moreLike: offlineMoreLikeSections(songs: songs, albums: albums),
            discover: discover,
            newReleases: newReleases
        )
    }

    private func albumsInSongOrder(_ songs: [Song], fallback albums: [Album]) -> [Album] {
        let albumsByID = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })
        var seen = Set<String>()
        var result: [Album] = []
        for song in songs {
            let key = albumKey(for: song)
            guard seen.insert(key).inserted, let album = albumsByID[key] else { continue }
            result.append(album)
        }
        return result.isEmpty ? albums : result
    }

    private func offlinePicks(songs: [Song], albums: [Album]) -> [PickFeedItem] {
        var rng = SeededRNG(seed: SeededRNG.daySeed() &+ 0xA11)
        var pickAlbums = albums
        pickAlbums.shuffle(using: &rng)
        var items = downloadedMixes(from: songs).map(PickFeedItem.mix)
            + pickAlbums.prefix(9).map(PickFeedItem.album)
        items.shuffle(using: &rng)
        return items
    }

    private func downloadedMixes(from songs: [Song]) -> [MusicMix] {
        var seen = Set<String>()
        let uniqueSongs = songs.filter { seen.insert($0.id).inserted }
        guard uniqueSongs.count >= 3 else { return [] }

        var rng = SeededRNG(seed: SeededRNG.daySeed() &+ 0x5150)
        func mixSongs(_ source: [Song], salt: UInt64) -> [Song] {
            var localRNG = SeededRNG(seed: SeededRNG.daySeed() &+ salt)
            return Array(source.shuffled(using: &localRNG).prefix(min(50, source.count)))
        }

        var mixes: [MusicMix] = [
            MusicMix(
                id: "offline-downloaded-\(SeededRNG.daySeed())",
                title: "Downloaded Mix",
                subtitle: "Available offline",
                coverArt: uniqueSongs.first(where: { $0.coverArt != nil })?.coverArt,
                songs: mixSongs(uniqueSongs, salt: 0xD0A)
            )
        ]

        let genreGroups = Dictionary(grouping: uniqueSongs) { $0.genre ?? "" }
            .filter { !$0.key.isEmpty && $0.value.count >= 3 }
            .sorted { $0.value.count > $1.value.count }
        for (genre, group) in genreGroups.prefix(2) {
            let picked = mixSongs(group, salt: stableSeed(genre))
            mixes.append(MusicMix(
                id: "genre-\(genre)",
                title: "\(genre) Mix",
                subtitle: "Daily \(genre.lowercased()) mix",
                coverArt: picked.first(where: { $0.coverArt != nil })?.coverArt,
                songs: picked
            ))
        }

        let artistGroups = Dictionary(grouping: uniqueSongs) { artistKey(for: $0) }
            .filter { $0.value.count >= 3 }
            .sorted { $0.value.count > $1.value.count }
        if let (_, group) = artistGroups.first {
            let artist = group.first?.primaryArtistName ?? ArtistNameResolver.unknownArtist
            let picked = mixSongs(group, salt: 0xA27157)
            mixes.append(MusicMix(
                id: "artist-\(artist)",
                title: "\(artist) Mix",
                subtitle: "Based on \(artist)",
                coverArt: picked.first(where: { $0.coverArt != nil })?.coverArt,
                songs: picked
            ))
        }

        mixes.shuffle(using: &rng)
        return Array(mixes.prefix(4))
    }

    private func offlineMoreLikeSections(songs: [Song], albums: [Album]) -> [HomeViewModel.MoreLikeSection] {
        let artistSongGroups = Dictionary(grouping: songs) { artistKey(for: $0) }
            .sorted { $0.value.count > $1.value.count }
        return artistSongGroups.prefix(2).compactMap { id, artistSongs in
            guard let first = artistSongs.first else { return nil }
            let artistName = first.primaryArtistName
            let artistAlbums = albums.filter { album in
                if let artistID = album.artistId {
                    return artistID == id
                }
                return album.artist == artistName
            }
            guard !artistAlbums.isEmpty else { return nil }
            return HomeViewModel.MoreLikeSection(id: id, artistName: artistName, albums: artistAlbums)
        }
    }

    private func homeSections(_ data: HomeSectionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Theme.Layout.sectionSpacing) {
            homeHeader

            if !data.picksFeed.isEmpty {
                section(title: L(.home_picks_for_you)) {
                    HorizontalPickRow(items: data.picksFeed,
                        onSelectAlbum: { path.append(HomeRoute.album($0)) },
                        onSelectMix: { path.append(HomeRoute.mix($0)) },
                        onSaveMix: { saveMixAsPlaylist($0) },
                        isSavingMix: { savingMixIDs.contains($0.id) })
                }
            }

            if !data.recentlyPlayed.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeaderView(L(.home_recently_played)) {
                        path.append(HomeRoute.mediaGrid(title: L(.home_recently_played), items: data.recentlyPlayed))
                    }
                    .padding(.horizontal, pad)
                    HorizontalMediaRow(items: data.recentlyPlayed) { item in
                        navigate(to: item)
                    }
                }
            }

            if !data.topArtists.isEmpty {
                section(title: L(.home_artists)) {
                    ArtistScrollRow(artists: data.topArtists) { artist in
                        path.append(HomeRoute.artist(artist))
                    }
                }
            }

            ForEach(data.moreLike) { item in
                section(title: L(.home_more_like, item.artistName)) {
                    HorizontalMediaRow(items: item.albums.map(MediaItem.init(album:))) { mediaItem in
                        if let album = mediaItem.albumRef { path.append(HomeRoute.album(album)) }
                    }
                }
            }

            if !data.discover.isEmpty {
                section(title: L(.home_discover)) {
                    HorizontalMediaRow(items: data.discover.map(MediaItem.init(album:))) { mediaItem in
                        if let album = mediaItem.albumRef { path.append(HomeRoute.album(album)) }
                    }
                }
            }

            if !data.newReleases.isEmpty {
                let items = data.newReleases.map(MediaItem.init(album:))
                section(title: L(.home_recently_added), seeAll: { path.append(HomeRoute.mediaGrid(title: L(.home_recently_added), items: items)) }) {
                    HorizontalMediaRow(items: items) { mediaItem in
                        if let album = mediaItem.albumRef { path.append(HomeRoute.album(album)) }
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
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(L(.tab_home))
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)

                if isServerUnavailable {
                    Text("(\(L(.home_offline).lowercased()))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText.opacity(0.6))
                }
            }

            Spacer()

            ServerMenuButton(onOpenSettings: { path.append(SettingsRoute.root) })
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
