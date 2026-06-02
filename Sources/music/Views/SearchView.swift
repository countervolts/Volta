import SwiftUI

struct SearchView: View {
    @State private var searchText = ""

    @Environment(AppState.self) private var appState
    @State private var vm = SearchViewModel()
    @Binding var path: [SearchRoute]
    @Namespace private var heroNamespace

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.background.ignoresSafeArea()

                Group {
                    if vm.query.isEmpty {
                        if vm.recentSearches.isEmpty { emptyPrompt } else { recentSearchesView }
                    } else if vm.isSearching {
                        ProgressView()
                            .controlSize(.large)
                            .tint(Theme.accent)
                    } else if vm.hasSearched && vm.artists.isEmpty && vm.albums.isEmpty && vm.songs.isEmpty {
                        noResults
                    } else {
                        results
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Search")
            .accountToolbar()
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Albums, Artists, Songs")
            .navigationDestination(for: SearchRoute.self) { route in
                searchDestination(route)
            }
            .environment(\.heroNamespace, heroNamespace)
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .onAppear {
            if let client = appState.client { vm.bind(client: client) }
        }
        .onChange(of: searchText) { _, new in
            vm.query = new
        }
    }

    // MARK: - Destinations

    @ViewBuilder
    private func searchDestination(_ route: SearchRoute) -> some View {
        switch route {
        case .album(let album):
            AlbumDetailView(album: album)
                .navigationTransition(.zoom(sourceID: album.id, in: heroNamespace))
        case .playlist(let pl):
            PlaylistDetailView(playlist: pl)
        case .artist(let artist):
            ArtistDetailView(artist: artist)
        }
    }

    // MARK: - Empty / no-results states

    private var emptyPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: Symbols.search)
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(Theme.secondaryText)
            Text("Search your library")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var recentSearchesView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Recent")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.primaryText)
                    Spacer()
                    Button("Clear") { vm.clearRecentSearches() }
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                ForEach(vm.recentSearches, id: \.self) { term in
                    HStack(spacing: 12) {
                        Image(systemName: "clock")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.secondaryText)
                        Text(term)
                            .font(.body)
                            .foregroundStyle(Theme.primaryText)
                        Spacer()
                        Button { vm.removeRecentSearch(term) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.secondaryText)
                                .padding(6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        searchText = term
                        vm.query = term
                    }
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
            Text("No results for \"\(vm.query)\"")
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
                        Text("Artists")
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
                        Text("Albums")
                            .font(.title3.bold())
                            .foregroundStyle(Theme.primaryText)
                            .padding(.horizontal, 20)
                        let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(vm.albums) { album in
                                NavigationLink(value: SearchRoute.album(album)) {
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
                        Text("Songs")
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

                Color.clear.frame(height: 80)
            }
            .padding(.top, 16)
        }
    }

    private func artistCell(_ artist: Artist) -> some View {
        Button { path.append(SearchRoute.artist(artist)) } label: {
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
}

enum SearchRoute: Hashable {
    case album(Album)
    case playlist(Playlist)
    case artist(Artist)
}
