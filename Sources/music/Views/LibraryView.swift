import SwiftUI

struct LibraryView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = LibraryViewModel()
    @Binding var path: [LibraryRoute]
    @Namespace private var heroNamespace

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    sourcePicker
                    filterPicker
                    Divider().background(Theme.secondaryText.opacity(0.15))
                    content
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .accountToolbar()
            .searchable(text: $vm.searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: searchPrompt)
            .navigationDestination(for: LibraryRoute.self) { route in
                libraryDestination(route)
            }
            .environment(\.heroNamespace, heroNamespace)
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .task(id: appState.currentServer?.id) {
            if let client = appState.client { await vm.load(client: client) }
        }
    }

    private var searchPrompt: String {
        "Search \(vm.filter.rawValue.lowercased())"
    }

    @ViewBuilder
    private func libraryDestination(_ route: LibraryRoute) -> some View {
        switch route {
        case .album(let album):
            AlbumDetailView(album: album)
                .navigationTransition(.zoom(sourceID: album.id, in: heroNamespace))
        case .artist(let artist):
            ArtistDetailView(artist: artist)
        case .playlist(let pl):
            PlaylistDetailView(playlist: pl)
        case .genreAlbums(let genre):
            genreGrid(genre: genre)
        }
    }

    private func genreGrid(genre: String) -> some View {
        let items = vm.albumsForGenre(genre).map(MediaItem.init(album:))
        return FullMediaGrid(title: genre, items: items) { item in
            if let album = item.albumRef { path.append(.album(album)) }
        }
    }

    // MARK: - Source picker (Server vs Downloaded)

    private var sourcePicker: some View {
        Picker("Source", selection: Binding(
            get: { vm.source },
            set: { s in withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { vm.setSource(s) } }
        )) {
            ForEach(LibrarySource.allCases) { s in
                Text(s.rawValue).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Theme.Layout.screenPadding)
        .padding(.top, 8)
    }

    // MARK: - Filter picker

    private var filterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(LibraryFilter.allCases) { f in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            vm.setFilter(f)
                        }
                    } label: {
                        Text(f.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(vm.filter == f ? Theme.background : Theme.primaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(vm.filter == f ? Theme.accent : Theme.secondaryBackground,
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && !vm.hasLoaded {
            Spacer()
            ProgressView().controlSize(.large).tint(Theme.accent)
            Spacer()
        } else if vm.source == .downloaded && vm.filteredSongs.isEmpty && vm.searchText.isEmpty {
            downloadedEmptyState
        } else {
            switch vm.filter {
            case .artists: artistsList
            case .albums: albumsGrid
            case .songs: songsList
            case .genres: genresList
            }
        }
    }

    private var downloadedEmptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: Symbols.downloaded)
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(Theme.secondaryText)
            Text("No downloads yet")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text("Download songs from an album to browse them offline.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var albumsGrid: some View {
        let columns = [GridItem(.flexible(), spacing: Theme.Layout.gridSpacing),
                       GridItem(.flexible(), spacing: Theme.Layout.gridSpacing),
                       GridItem(.flexible(), spacing: Theme.Layout.gridSpacing)]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.Layout.gridSpacing) {
                ForEach(vm.filteredAlbums) { album in
                    NavigationLink(value: LibraryRoute.album(album)) {
                        MediaCard(item: MediaItem(album: album))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.vertical, 12)
            .padding(.bottom, 80)
        }
    }

    private var artistsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(vm.filteredArtists) { artist in
                    Button {
                        path.append(.artist(artist))
                    } label: {
                        HStack(spacing: 14) {
                            ArtworkView(coverArtID: artist.coverArt, size: 100, cornerRadius: 28)
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(artist.name).font(.body.weight(.medium)).foregroundStyle(Theme.primaryText)
                                if let count = artist.albumCount {
                                    Text("\(count) albums").font(.caption).foregroundStyle(Theme.secondaryText)
                                }
                            }
                            Spacer()
                            Image(systemName: Symbols.chevron).font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                        .padding(.horizontal, Theme.Layout.screenPadding)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().background(Theme.secondaryText.opacity(0.12)).padding(.leading, 70)
                }
                Color.clear.frame(height: 80)
            }
        }
    }

    private var songsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(vm.filteredSongs.enumerated()), id: \.element.id) { i, song in
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
                            if let dur = song.duration {
                                Text(formatDuration(dur)).font(.caption.monospacedDigit()).foregroundStyle(Theme.secondaryText)
                            }
                        }
                        .padding(.horizontal, Theme.Layout.screenPadding)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().background(Theme.secondaryText.opacity(0.12)).padding(.leading, 68)
                }
                Color.clear.frame(height: 80)
            }
        }
    }

    private var genresList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(vm.filteredGenres, id: \.self) { genre in
                    NavigationLink(value: LibraryRoute.genreAlbums(genre)) {
                        HStack {
                            Text(genre).font(.body).foregroundStyle(Theme.primaryText)
                            Spacer()
                            Text("\(vm.albumsForGenre(genre).count)").font(.caption).foregroundStyle(Theme.secondaryText)
                            Image(systemName: Symbols.chevron).font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                        .padding(.horizontal, Theme.Layout.screenPadding)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().background(Theme.secondaryText.opacity(0.12)).padding(.leading, Theme.Layout.screenPadding)
                }
                Color.clear.frame(height: 80)
            }
        }
    }

    private func formatDuration(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }
}

enum LibraryRoute: Hashable {
    case album(Album)
    case artist(Artist)
    case playlist(Playlist)
    case genreAlbums(String)
}
