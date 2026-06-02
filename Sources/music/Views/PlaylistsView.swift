import SwiftUI

struct PlaylistsView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = PlaylistsViewModel()
    @Binding var path: [Playlist]
    @Namespace private var heroNamespace

    private let columns = [GridItem(.flexible(), spacing: Theme.Layout.gridSpacing),
                           GridItem(.flexible(), spacing: Theme.Layout.gridSpacing)]

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.background.ignoresSafeArea()
                if vm.isLoading && !vm.hasLoaded {
                    ProgressView().controlSize(.large).tint(Theme.accent)
                } else if vm.filtered.isEmpty && vm.hasLoaded {
                    emptyState
                } else {
                    grid
                }
            }
            .navigationTitle("Playlists")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $vm.searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search playlists")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { vm.showCreateSheet = true } label: {
                        Image(systemName: Symbols.newPlaylist)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .accountToolbar()
            .navigationDestination(for: Playlist.self) { pl in
                PlaylistDetailView(playlist: pl)
                    .navigationTransition(.zoom(sourceID: pl.id, in: heroNamespace))
            }
            .environment(\.heroNamespace, heroNamespace)
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $vm.showCreateSheet) {
            createSheet
        }
        .task(id: appState.currentServer?.id) {
            if let client = appState.client { await vm.load(client: client) }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.Layout.gridSpacing) {
                ForEach(vm.filtered) { pl in
                    NavigationLink(value: pl) {
                        VStack(alignment: .leading, spacing: 6) {
                            ArtworkView(coverArtID: pl.coverArt, size: 400)
                                .aspectRatio(1, contentMode: .fit)
                                .heroSource(id: pl.id)
                            Text(pl.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.primaryText)
                                .lineLimit(1)
                            if let count = pl.songCount {
                                Text("\(count) songs")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            if let client = appState.client {
                                Task { await vm.deletePlaylist(pl, client: client) }
                            }
                        } label: {
                            Label("Delete Playlist", systemImage: Symbols.trash)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.vertical, 12)
            .padding(.bottom, 80)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: Symbols.playlists).font(.system(size: 40, weight: .ultraLight)).foregroundStyle(Theme.secondaryText)
            Text("No playlists yet").font(.headline).foregroundStyle(Theme.primaryText)
        }
    }

    private var createSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Playlist name", text: $vm.newPlaylistName)
                }
            }
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { vm.showCreateSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        if let client = appState.client {
                            Task { await vm.createPlaylist(client: client) }
                        }
                    }
                    .disabled(vm.newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty || vm.isCreating)
                }
            }
        }
        .presentationDetents([.height(200)])
    }
}
