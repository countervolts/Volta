import SwiftUI

struct SearchView: View {
    @State private var searchText = ""
    @State private var isSearchActive = false

    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = SearchViewModel()
    @StateObject private var hiddenAlbums = HiddenAlbumStore.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @Binding var path: NavigationPath
    @Namespace private var heroNamespace

    private var isOffline: Bool { networkMonitor.connection == .none }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.background.ignoresSafeArea()

                Group {
                    if vm.query.isEmpty && isSearchActive && !vm.recentSearches.isEmpty {
                        recentSearchesView
                    } else if vm.query.isEmpty {
                        browseLanding
                    } else if vm.isSearching {
                        ProgressView()
                            .controlSize(.large)
                            .tint(Theme.accent)
                    } else if vm.hasSearched && vm.artists.isEmpty && vm.albums.isEmpty && vm.songs.isEmpty && vm.genres.isEmpty && vm.lyricHits.isEmpty {
                        noResults
                    } else {
                        results
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SearchActiveReader(isActive: $isSearchActive))
            }
            .navigationTitle(L(.tab_search))
            .accountToolbar(path: $path)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: L(.search_prompt))
            .onSubmit(of: .search) {
                vm.saveSearch(searchText)
            }
            .navigationDestination(for: SearchRoute.self) { route in
                searchDestination(route)
            }
            .environment(\.heroNamespace, heroNamespace)
        }
        .tint(Theme.accent)
        .preferredColorScheme(Theme.colorScheme)
        .onAppear {
            vm.setOffline(isOffline)
            if let client = appState.client { vm.bind(client: client) }
        }
        .onChangeCompat(of: searchText) { _, new in
            vm.query = new
        }
        .onChangeCompat(of: networkMonitor.connection) { _, _ in
            vm.setOffline(isOffline)
        }
        .onChangeCompat(of: hiddenAlbums.revision) { _, _ in
            vm.refreshForVisibilityChange()
        }
    }

    // MARK: - Destinations

    @ViewBuilder
    private func searchDestination(_ route: SearchRoute) -> some View {
        switch route {
        case .album(let album):
            AlbumDetailView(album: album)
                .zoomNavigationTransition(sourceID: album.id, in: heroNamespace)
        case .playlist(let pl):
            PlaylistDetailView(playlist: pl)
        case .artist(let artist):
            ArtistDetailView(artist: artist)
        case .genre(let genreName):
            GenreHomeView(
                genreName: genreName,
                onAlbum: { path.append(SearchRoute.album($0)) },
                onArtist: { path.append(SearchRoute.artist($0)) },
                onMix: { path.append(SearchRoute.mix($0)) }
            )
        case .mix(let mix):
            MixDetailView(mix: mix)
        }
    }

    // MARK: - Empty / no-results states

    private var browseLanding: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if !vm.installedGenres.isEmpty {
                    browseSection(title: L(.search_browse_genres)) {
                        let columns = [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ]
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(vm.installedGenres) { genre in
                                Button {
                                    path.append(SearchRoute.genre(genre.name))
                                } label: {
                                    genreBrowseCard(genre)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                } else if vm.isLoadingBrowseGenres {
                    ProgressView()
                        .controlSize(.large)
                        .tint(Theme.accent)
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: Symbols.search)
                            .font(.system(size: 44, weight: .ultraLight))
                            .foregroundStyle(Theme.secondaryText)
                        Text(L(.search_placeholder))
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                }

                Color.clear.frame(height: 80)
            }
            .padding(.top, 16)
        }
    }

    private func browseSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(Theme.primaryText)
                .padding(.horizontal, 20)
            content()
        }
    }

    private func genreBrowseCard(_ genre: GenreSearchResult) -> some View {
        let style = genreStyle(for: genre.name)
        return HStack(spacing: 12) {
            Image(systemName: style.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(genre.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(L(.media_album_count, genre.albumCount))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(minHeight: 76)
        .background(style.color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func genreStyle(for name: String) -> (symbol: String, color: Color) {
        let lower = name.lowercased()
        if lower.contains("rock") { return ("bolt.fill", .red.opacity(0.82)) }
        if lower.contains("pop") { return ("sparkles", .pink.opacity(0.82)) }
        if lower.contains("hip") || lower.contains("rap") { return ("mic.fill", .orange.opacity(0.82)) }
        if lower.contains("jazz") { return ("saxophone", .blue.opacity(0.82)) }
        if lower.contains("elect") || lower.contains("dance") { return ("waveform.path.ecg", .cyan.opacity(0.82)) }
        if lower.contains("classical") { return ("pianokeys", .indigo.opacity(0.82)) }
        if lower.contains("metal") { return ("flame.fill", .gray.opacity(0.86)) }
        if lower.contains("country") || lower.contains("folk") { return ("guitars", .green.opacity(0.80)) }
        if lower.contains("r&b") || lower.contains("soul") { return ("heart.fill", .purple.opacity(0.80)) }
        return (Symbols.genres, Theme.accent.opacity(0.80))
    }

    private var recentSearchesView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(L(.search_recent))
                        .font(.title3.bold())
                        .foregroundStyle(Theme.primaryText)
                    Spacer()
                    Button(L(.action_clear)) { vm.clearRecentSearches() }
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                ForEach(vm.recentSearches) { item in
                    recentSearchRow(item)
                    Divider().background(Theme.secondaryText.opacity(0.12)).padding(.leading, 52)
                }
                Color.clear.frame(height: 80)
            }
        }
    }

    private var noResults: some View {
        VStack(spacing: 10) {
            Image(systemName: Symbols.warning)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.secondaryText)
            Text(L(.search_no_results, vm.query))
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: - Results

    private var results: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if !vm.artists.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L(.home_artists))
                            .font(.title3.bold())
                            .foregroundStyle(Theme.primaryText)
                            .padding(.horizontal, 20)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 16) {
                                ForEach(vm.artists) { artist in
                                    artistCell(artist)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }

                if !vm.albums.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L(.media_albums))
                            .font(.title3.bold())
                            .foregroundStyle(Theme.primaryText)
                            .padding(.horizontal, 20)
                        let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(vm.albums) { album in
                                Button {
                                    vm.saveSelectedAlbum(album, typedQuery: searchText)
                                    path.append(SearchRoute.album(album))
                                } label: {
                                    MediaCard(item: MediaItem(album: album))
                                        .heroSource(id: album.id)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }

                if !vm.songs.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(L(.media_songs))
                            .font(.title3.bold())
                            .foregroundStyle(Theme.primaryText)
                            .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                        ForEach(Array(vm.songs.enumerated()), id: \.element.id) { i, song in
                            searchSongRow(song)
                            Divider().background(Theme.secondaryText.opacity(0.2)).padding(.leading, 72)
                        }
                    }
                }

                if !vm.lyricHits.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(L(.search_from_lyrics))
                            .font(.title3.bold())
                            .foregroundStyle(Theme.primaryText)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                        ForEach(vm.lyricHits) { hit in
                            lyricHitRow(hit)
                            Divider().background(Theme.secondaryText.opacity(0.2)).padding(.leading, 72)
                        }
                    }
                }

                if !vm.genres.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(L(.media_genres))
                            .font(.title3.bold())
                            .foregroundStyle(Theme.primaryText)
                            .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                        ForEach(vm.genres) { genre in
                            Button {
                                path.append(SearchRoute.genre(genre.name))
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: Symbols.genres)
                                        .font(.system(size: 18))
                                        .foregroundStyle(Theme.accent)
                                        .frame(width: 44, height: 44)
                                        .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(genre.name)
                                            .font(.body)
                                            .foregroundStyle(Theme.primaryText)
                                        Text("\(genre.albumCount) albums")
                                            .font(.caption)
                                            .foregroundStyle(Theme.secondaryText)
                                    }
                                    Spacer()
                                    Image(systemName: Symbols.chevron)
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().background(Theme.secondaryText.opacity(0.2)).padding(.leading, 72)
                        }
                    }
                }

                Color.clear.frame(height: 80)
            }
            .padding(.top, 16)
        }
    }

    private func recentSearchRow(_ item: SearchHistoryItem) -> some View {
        HStack(spacing: 12) {
            recentSearchArtwork(item)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text(item.subtitle ?? item.kind.label)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            Button { vm.removeRecentSearch(item) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            openRecentSearch(item)
        }
    }

    @ViewBuilder
    private func recentSearchArtwork(_ item: SearchHistoryItem) -> some View {
        switch item.kind {
        case .artist:
            ArtworkView(coverArtID: item.coverArt, size: 160, cornerRadius: 22)
                .frame(width: 44, height: 44)
                .clipShape(Circle())
        case .album, .song, .lyric:
            ArtworkView(coverArtID: item.coverArt, size: 160, cornerRadius: 6)
                .frame(width: 44, height: 44)
        case .genre, .query:
            Image(systemName: recentSearchSymbol(for: item.kind))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(item.kind == .genre ? Theme.accent : Theme.secondaryText)
                .frame(width: 44, height: 44)
                .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func recentSearchSymbol(for kind: SearchHistoryKind) -> String {
        switch kind {
        case .artist: return "music.mic"
        case .album: return "square.stack"
        case .song: return Symbols.songs
        case .lyric: return "quote.bubble"
        case .genre: return Symbols.genres
        case .query: return Symbols.search
        }
    }

    private func artistCell(_ artist: Artist) -> some View {
        Button {
            vm.saveSelectedArtist(artist, typedQuery: searchText)
            path.append(SearchRoute.artist(artist))
        } label: {
            VStack(spacing: 8) {
                ArtworkView(coverArtID: artist.coverArt, size: 200, cornerRadius: 50)
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
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

    private func lyricHitRow(_ hit: LyricSearchHit) -> some View {
        let song = vm.lyricSong(for: hit)
        return Button {
            playLyricHit(hit, song: song)
        } label: {
            HStack(spacing: 12) {
                ArtworkView(coverArtID: song?.coverArt, size: 80, cornerRadius: 6)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.title).font(.body).foregroundStyle(Theme.primaryText).lineLimit(1)
                    if let artist = song?.artist ?? hit.artist {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                    Text("“\(hit.snippet)”")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let song, song.albumId != nil {
                Button {
                    goToAlbum(song)
                } label: {
                    Label(L(.action_go_to_album), systemImage: "square.stack")
                }
            }
            if let song, song.artistId != nil {
                Button {
                    goToArtist(song)
                } label: {
                    Label(L(.action_go_to_artist), systemImage: "music.mic")
                }
            }
        }
    }

    private func playLyricHit(_ hit: LyricSearchHit, song resolvedSong: Song?) {
        if let resolvedSong {
            appState.audioPlayer.play(song: resolvedSong)
            return
        }
        guard let client = appState.client else { return }
        Task {
            if let song = try? await client.song(id: hit.id) {
                appState.audioPlayer.play(song: song)
            } else {
                VoltaNotificationCenter.shared.post(L(.notif_couldnt_load, hit.title), tone: .error)
            }
        }
    }

    private func goToAlbum(_ song: Song) {
        guard let id = song.albumId, let client = appState.client else { return }
        guard !hiddenAlbums.isSongHidden(song) else { return }
        Task {
            if let album = try? await client.album(id: id) {
                await MainActor.run {
                    guard !hiddenAlbums.isHidden(album) else { return }
                    vm.saveSelectedAlbum(album, typedQuery: searchText)
                    path.append(SearchRoute.album(album))
                }
            } else {
                VoltaNotificationCenter.shared.post(L(.notif_couldnt_load_album), tone: .error)
            }
        }
    }

    private func goToArtist(_ song: Song) {
        guard let id = song.artistId, let client = appState.client else { return }
        guard !hiddenAlbums.isSongHidden(song) else { return }
        Task {
            if let artist = try? await client.artist(id: id) {
                await MainActor.run {
                    hiddenAlbums.register(artists: [artist])
                    guard !hiddenAlbums.isArtistHidden(artist) else { return }
                    vm.saveSelectedArtist(artist, typedQuery: searchText)
                    path.append(SearchRoute.artist(artist))
                }
            } else {
                VoltaNotificationCenter.shared.post(L(.notif_couldnt_load_artist), tone: .error)
            }
        }
    }

    private func searchSongRow(_ song: Song) -> some View {
        Button {
            appState.audioPlayer.play(song: song)
        } label: {
            HStack(spacing: 12) {
                ArtworkView(coverArtID: song.coverArt, size: 80, cornerRadius: 6)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).font(.body).foregroundStyle(Theme.primaryText).lineLimit(1)
                    Text(song.artist ?? "").font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openRecentSearch(_ item: SearchHistoryItem) {
        switch item.kind {
        case .artist:
            openRecentArtist(item)
        case .album:
            openRecentAlbum(item)
        case .song, .lyric, .genre, .query:
            searchText = item.query
            vm.query = item.query
        }
    }

    private func openRecentArtist(_ item: SearchHistoryItem) {
        guard let id = targetID(for: item, prefix: "artist-"), let client = appState.client else {
            searchText = item.query
            vm.query = item.query
            return
        }

        Task {
            if let artist = try? await client.artist(id: id) {
                await MainActor.run {
                    hiddenAlbums.register(artists: [artist])
                    guard !hiddenAlbums.isArtistHidden(artist) else { return }
                    path.append(SearchRoute.artist(artist))
                }
            } else {
                await MainActor.run {
                    searchText = item.query
                    vm.query = item.query
                }
            }
        }
    }

    private func openRecentAlbum(_ item: SearchHistoryItem) {
        guard let id = targetID(for: item, prefix: "album-"), let client = appState.client else {
            searchText = item.query
            vm.query = item.query
            return
        }

        Task {
            if let album = try? await client.album(id: id) {
                await MainActor.run {
                    guard !hiddenAlbums.isHidden(album) else { return }
                    path.append(SearchRoute.album(album))
                }
            } else {
                await MainActor.run {
                    searchText = item.query
                    vm.query = item.query
                }
            }
        }
    }

    private func targetID(for item: SearchHistoryItem, prefix: String) -> String? {
        if let targetID = item.targetID { return targetID }
        guard item.id.hasPrefix(prefix) else { return nil }
        return String(item.id.dropFirst(prefix.count))
    }
}

private struct SearchActiveReader: View {
    @Environment(\.isSearching) private var isSearching
    @Binding var isActive: Bool

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { isActive = isSearching }
            .onChangeCompat(of: isSearching) { _, newValue in
                isActive = newValue
            }
    }
}

enum SearchRoute: Hashable {
    case album(Album)
    case playlist(Playlist)
    case artist(Artist)
    case genre(String)
    case mix(MusicMix)
}

private struct GenreHomeData: Sendable {
    var albumsNewestFirst: [Album] = []
    var discoverAlbums: [Album] = []
    var discoverItems: [MediaItem] = []
    var albumItems: [MediaItem] = []
    var artists: [Artist] = []

    var albumCount: Int { albumsNewestFirst.count }
    var pickAlbums: [Album] { Array(discoverAlbums.prefix(5)) }
}

private struct GenreHomeView: View {
    let genreName: String
    var onAlbum: (Album) -> Void
    var onArtist: (Artist) -> Void
    var onMix: (MusicMix) -> Void

    @EnvironmentObject private var appState: AppState
    @State private var genreData = GenreHomeData()
    @State private var isLoadingGenre = false
    @State private var genreMix: MusicMix?
    @State private var isLoadingMix = false
    @State private var savingMixIDs = Set<String>()
    @State private var toastMessage: String?
    @StateObject private var hiddenAlbums = HiddenAlbumStore.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared

    private var isOffline: Bool { networkMonitor.connection == .none }

    private var pickFeed: [PickFeedItem] {
        var items = genreData.pickAlbums.map(PickFeedItem.album)
        if let genreMix { items.insert(.mix(genreMix), at: 0) }
        return items
    }

    private var genreSeed: UInt64 {
        UInt64(String(Crypto.md5Hex(genreName).prefix(16)), radix: 16) ?? 0
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Layout.sectionSpacing) {
                    header

                    if !pickFeed.isEmpty {
                        section(title: "\(genreName) \(L(.home_picks_for_you))") {
                            HorizontalPickRow(
                                items: pickFeed,
                                onSelectAlbum: onAlbum,
                                onSelectMix: onMix,
                                onSaveMix: { saveMixAsPlaylist($0) },
                                isSavingMix: { savingMixIDs.contains($0.id) }
                            )
                        }
                    } else if isLoadingGenre || isLoadingMix {
                        loadingSection(title: "\(genreName) \(L(.home_picks_for_you))")
                    }

                    if !genreData.discoverItems.isEmpty {
                        section(title: L(.home_discover)) {
                            HorizontalMediaRow(items: genreData.discoverItems) { item in
                                if let album = item.albumRef { onAlbum(album) }
                            }
                        }
                    }

                    if !genreData.albumItems.isEmpty {
                        section(title: L(.media_albums)) {
                            HorizontalMediaRow(items: genreData.albumItems) { item in
                                if let album = item.albumRef { onAlbum(album) }
                            }
                        }
                    }

                    if !genreData.artists.isEmpty {
                        section(title: L(.home_artists)) {
                            SearchArtistScrollRow(artists: genreData.artists, onTap: onArtist)
                        }
                    }

                    Color.clear.frame(height: 90)
                }
                .padding(.top, 4)
            }
            if let toastMessage {
                VStack {
                    Spacer()
                    PlaybackActionToast(message: toastMessage)
                        .padding(.bottom, 78)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toastMessage)
        .navigationTitle(genreName)
        .navigationBarTitleDisplayMode(.large)
        .preferredColorScheme(Theme.colorScheme)
        .task(id: "\(genreName)-\(hiddenAlbums.revision)") {
            if DeveloperExperiments.constrainedConcurrency(default: 2) == 1 {
                await loadGenreData()
                await loadGenreMix()
            } else {
                async let data: Void = loadGenreData()
                async let mix: Void = loadGenreMix()
                _ = await (data, mix)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(genreData.albumCount) album\(genreData.albumCount == 1 ? "" : "s") in your library")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, Theme.Layout.screenPadding)
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeaderView(title)
                .padding(.horizontal, Theme.Layout.screenPadding)
            content()
        }
    }

    private func loadingSection(title: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeaderView(title)
                .padding(.horizontal, Theme.Layout.screenPadding)
            ProgressView()
                .tint(Theme.accent)
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    private func loadGenreData() async {
        isLoadingGenre = true
        defer { isLoadingGenre = false }

        var albums: [Album] = []
        if !isOffline, let client = appState.client {
            albums = await Self.fetchGenreAlbums(genreName: genreName, client: client)
        }
        // Fall back to downloaded songs when offline or the server is unreachable.
        if albums.isEmpty {
            let songs = OfflineLibrary.songs(
                inGenre: genreName,
                from: HiddenAlbumStore.shared.visibleSongs(DownloadService.shared.downloadedSongs())
            )
            albums = OfflineLibrary.albums(from: songs)
        }
        hiddenAlbums.register(albums: albums)
        let data = await Self.makeGenreHomeData(albums: albums, seed: genreSeed)
        guard !Task.isCancelled else { return }
        genreData = data
    }

    private func loadGenreMix() async {
        isLoadingMix = true
        defer { isLoadingMix = false }

        var songs: [Song] = []
        if !isOffline, let client = appState.client {
            songs = HiddenAlbumStore.shared.visibleSongs((try? await client.songsByGenre(genreName, count: 100)) ?? [])
        }
        // Fall back to downloaded songs when offline or the server is unreachable.
        if songs.isEmpty {
            songs = OfflineLibrary.songs(
                inGenre: genreName,
                from: HiddenAlbumStore.shared.visibleSongs(DownloadService.shared.downloadedSongs())
            )
        }
        var seen = Set<String>()
        let unique = songs.filter { seen.insert($0.id).inserted }
        guard !unique.isEmpty else {
            genreMix = nil
            return
        }

        var rng = SeededRNG(seed: genreSeed &+ SeededRNG.daySeed() &+ 0xC0FFEE)
        let shuffled = unique.shuffled(using: &rng)
        let count = min(shuffled.count, max(20, min(50, shuffled.count)))
        let selected = Array(shuffled.prefix(count))
        genreMix = MusicMix(
            id: "genre-\(Crypto.md5Hex(genreName))-\(SeededRNG.daySeed())",
            title: "\(genreName) Mix",
            subtitle: L(.search_genre_mix_subtitle, genreName.lowercased()),
            coverArt: selected.first(where: { $0.coverArt != nil })?.coverArt,
            songs: selected
        )
    }

    private nonisolated static func fetchGenreAlbums(genreName: String, client: any MusicService) async -> [Album] {
        var matches: [Album] = []
        var offset = 0
        let size = 500
        while true {
            let batch = (try? await client.allAlbums(size: size, offset: offset)) ?? []
            let filtered = await DeveloperExperiments.runSync(priority: .userInitiated) {
                batch.filter {
                    ($0.genre ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        .caseInsensitiveCompare(genreName) == .orderedSame
                }
            }
            matches += filtered
            if batch.count < size { break }
            offset += size
            if offset > 20_000 { break }
        }
        return HiddenAlbumStore.visibleAlbums(matches)
    }

    private nonisolated static func makeGenreHomeData(
        albums: [Album],
        seed: UInt64
    ) async -> GenreHomeData {
        await DeveloperExperiments.runSync(priority: .userInitiated) {
            let newestFirst = albums.sorted {
                let lhs = ($0.year ?? Int.min, $0.createdDate ?? .distantPast, $0.name)
                let rhs = ($1.year ?? Int.min, $1.createdDate ?? .distantPast, $1.name)
                return lhs > rhs
            }

            var rng = SeededRNG(seed: seed &+ SeededRNG.daySeed())
            let discoverAlbums = newestFirst.shuffled(using: &rng)
            let discoverItems = Array(discoverAlbums.prefix(18)).map(MediaItem.init(album:))
            let albumItems = newestFirst.map(MediaItem.init(album:))
            let artists = Self.artists(from: albums)

            return GenreHomeData(
                albumsNewestFirst: newestFirst,
                discoverAlbums: discoverAlbums,
                discoverItems: discoverItems,
                albumItems: albumItems,
                artists: artists
            )
        }
    }

    private nonisolated static func artists(from albums: [Album]) -> [Artist] {
        var counts: [String: Int] = [:]
        var byID: [String: Artist] = [:]
        for album in albums {
            guard let id = album.artistId, let name = album.artist else { continue }
            counts[id, default: 0] += 1
            if byID[id] == nil {
                byID[id] = Artist(
                    id: id,
                    name: name,
                    coverArt: album.coverArt,
                    albumCount: nil,
                    artistImageUrl: nil,
                    starred: nil,
                    album: nil
                )
            }
        }
        return byID.values
            .map { artist in
                Artist(
                    id: artist.id,
                    name: artist.name,
                    coverArt: artist.coverArt,
                    albumCount: counts[artist.id],
                    artistImageUrl: artist.artistImageUrl,
                    starred: artist.starred,
                    album: nil
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
                AppLogger.shared.log("Failed saving search genre mix '\(mix.title)' as playlist: \(error.localizedDescription)", category: .other, level: .error)
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

private struct SearchArtistScrollRow: View {
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
