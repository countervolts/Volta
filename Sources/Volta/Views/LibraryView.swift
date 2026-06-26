import SwiftUI
import UIKit

struct LibraryView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = LibraryViewModel()
    @State private var hiddenAlbums = HiddenAlbumStore.shared
    @Binding var path: NavigationPath
    @Namespace private var heroNamespace
    @AppStorage("albumSortOrder") private var albumSortOrder = "alphabetical"

    @State private var selectionMode = false
    @State private var selectedSongIDs: Set<String> = []
    @State private var showBatchPlaylistSheet = false
    @State private var addToPlaylistSong: Song?
    @State private var batchToast: String? = nil

    private var selectedSongs: [Song] {
        vm.filteredSongs.filter { selectedSongIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.background.ignoresSafeArea()
                GeometryReader { geo in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            sourcePicker
                            filterPicker
                            Divider().background(Theme.secondaryText.opacity(0.15))
                            content
                        }
                        .frame(minHeight: geo.size.height + 160, alignment: .top)
                        .padding(.bottom, 80)
                    }
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .accountToolbar(path: $path)
            .searchable(text: $vm.searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: searchPrompt)
            .navigationDestination(for: LibraryRoute.self) { route in
                libraryDestination(route)
            }
            .environment(\.heroNamespace, heroNamespace)
            .overlay(alignment: .bottom) { selectionOverlay }
            .sheet(isPresented: $showBatchPlaylistSheet) {
                AddSongsToPlaylistSheet(songs: selectedSongs) { name, count in
                    finishBatch("Added \(count) to \(name)")
                }
            }
            .sheet(item: $addToPlaylistSong) { song in
                AddToPlaylistSheet(song: song) { name in
                    showToast("Added to \(name)")
                }
            }
            .onChange(of: vm.filter) { _, _ in exitSelection() }
            .onChange(of: vm.source) { _, _ in exitSelection() }
            .onChange(of: albumSortOrder) { _, value in
                vm.setSort(LibraryViewModel.sortOrder(from: value))
            }
            .onChange(of: hiddenAlbums.revision) { _, _ in
                exitSelection()
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(Theme.colorScheme)
        .task(id: appState.currentServer?.id) {
            if let client = appState.client { await vm.load(client: client) }
        }
    }

    private var searchPrompt: String {
        "Search Library"
    }

    @ViewBuilder
    private func libraryDestination(_ route: LibraryRoute) -> some View {
        switch route {
        case .album(let album):
            AlbumDetailView(album: album)
                .zoomNavigationTransition(sourceID: album.id, in: heroNamespace)
        case .artist(let artist):
            ArtistDetailView(artist: artist)
                .zoomNavigationTransition(sourceID: artist.id, in: heroNamespace)
        case .playlist(let pl):
            PlaylistDetailView(playlist: pl)
        case .genreAlbums(let genre):
            genreGrid(genre: genre)
        case .folder(let source):
            FolderBrowseScreen(source: source, title: folderTitle(source))
        case .downloadedFolder(let path):
            DownloadedFolderScreen(path: path, title: path.last ?? "Folders")
        }
    }

    private func folderTitle(_ source: FolderSource) -> String {
        if case .directory(_, let name) = source { return name }
        return "Folders"
    }

    private func genreGrid(genre: String) -> some View {
        let items = vm.albumsForGenre(genre).map(MediaItem.init(album:))
        return FullMediaGrid(title: genre, items: items) { item in
            if let album = item.albumRef { path.append(LibraryRoute.album(album)) }
        }
    }

    // MARK: - Source picker (Server vs Downloaded)

    private var sourcePicker: some View {
        Picker("Source", selection: Binding(
            get: { vm.source },
            set: { s in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { vm.setSource(s) }
            }
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
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(LibraryFilter.allCases) { f in
                        Button {
                            withAnimation(.easeOut(duration: 0.12)) {
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
                .padding(.leading, Theme.Layout.screenPadding)
                .padding(.vertical, 12)
            }
            if vm.filter == .albums || vm.filter == .songs {
                filterMenu
                    .padding(.trailing, Theme.Layout.screenPadding)
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Sort By", selection: Binding(get: { vm.sortOrder }, set: { vm.setSort($0) })) {
                ForEach(LibrarySortOrder.allCases) { Text($0.rawValue).tag($0) }
            }
            if !vm.availableGenres.isEmpty {
                Picker("Genre", selection: Binding(
                    get: { vm.genreFilter ?? "" },
                    set: { vm.setGenreFilter($0.isEmpty ? nil : $0) }
                )) {
                    Text("All Genres").tag("")
                    ForEach(vm.availableGenres, id: \.self) { Text($0).tag($0) }
                }
            }
            Toggle(isOn: Binding(get: { vm.neverPlayedOnly }, set: { vm.neverPlayedOnly = $0 })) {
                Label("Never Played", systemImage: "moon.zzz")
            }
            if vm.hasActiveFilters {
                Divider()
                Button(role: .destructive) { vm.clearFilters() } label: {
                    Label("Clear Filters", systemImage: "xmark.circle")
                }
            }
        } label: {
            Image(systemName: vm.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 20))
                .foregroundStyle(vm.hasActiveFilters ? Theme.accent : Theme.secondaryText)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vm.filter == .folders {
            foldersContent
        } else if vm.isLoading && !vm.hasLoaded {
            ProgressView().controlSize(.large).tint(Theme.accent)
                .frame(maxWidth: .infinity, minHeight: 360)
        } else if vm.source == .downloaded && vm.filteredSongs.isEmpty && vm.searchText.isEmpty {
            downloadedEmptyState
        } else {
            switch vm.filter {
            case .artists: artistsList
            case .albums: albumsGrid
            case .songs: songsList
            case .genres: genresList
            case .folders: EmptyView()   // handled above
            }
        }
    }

    // MARK: - Folders

    @ViewBuilder
    private var foldersContent: some View {
        if vm.source == .downloaded {
            // Mirror the server folder browser, but build the tree locally from
            // the file paths of downloaded songs so it works fully offline.
            DownloadedFolderView(prefix: [], filterText: vm.searchText)
        } else {
            VStack(spacing: 0) {
                // music-folder picker only when the server exposes more than one
                if vm.musicFolders.count > 1 {
                    Menu {
                        Button("All Folders") { vm.selectedFolderID = nil }
                        ForEach(vm.musicFolders) { folder in
                            Button(folder.name) { vm.selectedFolderID = folder.id }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                            Text(selectedFolderName)
                            Image(systemName: Symbols.chevronDown).font(.caption2)
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.primaryText)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .glassCapsule()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Layout.screenPadding)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                }
                FolderBrowseView(source: vm.rootFolderSource, filterText: vm.searchText)
                    .id(vm.selectedFolderID)
            }
        }
    }

    private var selectedFolderName: String {
        guard let id = vm.selectedFolderID,
              let folder = vm.musicFolders.first(where: { $0.id == id }) else { return "All Folders" }
        return folder.name
    }

    private var downloadedEmptyState: some View {
        // message reflects whichever section (artists/albums/songs/genres) is selected
        let (title, subtitle): (String, String) = {
            switch vm.filter {
            case .artists: return ("No downloaded artists", "Artists show up here once you download some of their songs.")
            case .albums:  return ("No downloaded albums", "Albums show up here once you download their tracks.")
            case .songs:   return ("No downloaded songs", "Download songs from an album or playlist to play them offline.")
            case .genres:  return ("No downloaded genres", "Genres appear here once you have downloaded songs.")
            case .folders: return ("No downloaded folders", "Folder browsing is available on the Server source.")
            }
        }()
        return VStack(spacing: 12) {
            Image(systemName: Symbols.downloaded)
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(Theme.secondaryText)
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private var albumsGrid: some View {
        let columns = [GridItem(.flexible(), spacing: Theme.Layout.gridSpacing),
                       GridItem(.flexible(), spacing: Theme.Layout.gridSpacing),
                       GridItem(.flexible(), spacing: Theme.Layout.gridSpacing)]
        return LazyVGrid(columns: columns, spacing: Theme.Layout.gridSpacing) {
            ForEach(vm.filteredAlbums) { album in
                NavigationLink(value: LibraryRoute.album(album)) {
                    MediaCard(item: MediaItem(album: album))
                }
                .buttonStyle(.plain)
                .albumContextMenu(album)
            }
        }
        .padding(.horizontal, Theme.Layout.screenPadding)
        .padding(.vertical, 12)
    }

    private var artistsList: some View {
        LazyVStack(spacing: 0) {
            ForEach(vm.filteredArtists) { artist in
                NavigationLink(value: LibraryRoute.artist(artist)) {
                    HStack(spacing: 14) {
                        ArtworkView(coverArtID: artist.coverArt, size: 100, cornerRadius: 28)
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                            .heroSource(id: artist.id)
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
        }
    }

    private var songsList: some View {
        LazyVStack(spacing: 0) {
            if !vm.filteredSongs.isEmpty {
                librarySongsActions
            }
            ForEach(Array(vm.filteredSongs.enumerated()), id: \.element.id) { index, song in
                songRow(song, visibleIndex: index)
                Divider().background(Theme.secondaryText.opacity(0.12))
                    .padding(.leading, selectionMode ? 96 : 68)
            }
        }
    }

    private var librarySongsActions: some View {
        HStack(spacing: 12) {
            Button {
                appState.audioPlayer.playQueue(vm.filteredSongs, startIndex: 0, source: "Library Songs")
            } label: {
                Label(L(.action_play), systemImage: Symbols.play)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button {
                appState.audioPlayer.playQueue(vm.filteredSongs.shuffled(), startIndex: 0, source: "Library Songs")
            } label: {
                Label(L(.action_shuffle), systemImage: Symbols.shuffle)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .glassCapsule(tinted: true)
                    .foregroundStyle(Theme.primaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Layout.screenPadding)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func songRow(_ song: Song, visibleIndex: Int) -> some View {
        let selected = selectedSongIDs.contains(song.id)
        if selectionMode {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? Theme.accent : Theme.secondaryText)
                    .transition(.scale.combined(with: .opacity))
                ArtworkView(coverArtID: song.coverArt, size: 80, cornerRadius: 6)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).font(.body).foregroundStyle(Theme.primaryText).lineLimit(1)
                    Text(song.artist ?? "").font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture { toggleSelection(song) }
            .onLongPressGesture(minimumDuration: 0.4) { enterSelection(with: song) }
        } else {
            TrackRow(
                song: song,
                index: visibleIndex + 1,
                isCurrentlyPlaying: appState.audioPlayer.currentSong?.id == song.id,
                onTap: {
                    appState.audioPlayer.playQueue(vm.filteredSongs, startIndex: visibleIndex, source: "Library Songs")
                },
                showArtist: true,
                leadingArtwork: true,
                onSwipePlayNext: {
                    appState.audioPlayer.playNext(song)
                }
            ) {
                SongMenu(
                    song: song,
                    onGoToAlbum: song.albumId == nil ? nil : { goToAlbum(song) },
                    onGoToArtist: song.artistId == nil ? nil : { goToArtist(song) },
                    onAddToPlaylist: { addToPlaylistSong = song },
                    onDelete: vm.source == .downloaded ? {
                        DownloadService.shared.removeDownload(for: song)
                    } : nil,
                    deleteLabel: L(.action_remove_download)
                )
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .onLongPressGesture(minimumDuration: 0.4) { enterSelection(with: song) }
        }
    }

    // MARK: - Multi-select

    @ViewBuilder
    private var selectionOverlay: some View {
        ZStack(alignment: .bottom) {
            if let msg = batchToast {
                Text(msg)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .shadow(radius: 8)
                    .padding(.bottom, selectionMode ? 168 : 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if selectionMode {
                selectionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selectionMode)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: batchToast)
    }

    private var selectionBar: some View {
        VStack(spacing: 14) {
            HStack {
                Button(L(.action_done)) { exitSelection() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text("\(selectedSongIDs.count) selected")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.primaryText)
                    .contentTransition(.numericText())
                Spacer()
                Button(allSelected ? "Deselect All" : "Select All") { toggleSelectAll() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            HStack(spacing: 0) {
                batchButton(L(.action_play_next), "text.line.first.and.arrowtriangle.forward") {
                    appState.audioPlayer.playNext(selectedSongs)
                    finishBatch("Playing \(selectedSongs.count) next")
                }
                batchButton("Queue", "text.append") {
                    appState.audioPlayer.addToQueue(selectedSongs)
                    finishBatch("Added \(selectedSongs.count) to queue")
                }
                batchButton("Playlist", Symbols.addToPlaylist) {
                    showBatchPlaylistSheet = true
                }
                if vm.source == .downloaded {
                    batchButton(L(.action_remove), Symbols.trash) {
                        let songs = selectedSongs
                        for s in songs { DownloadService.shared.removeDownload(for: s) }
                        exitSelection()
                    }
                } else {
                    batchButton(L(.action_download), Symbols.download) {
                        let songs = selectedSongs
                        for s in songs where DownloadService.shared.state(for: s) == .notDownloaded {
                            DownloadService.shared.download(song: s)
                        }
                        finishBatch("Downloading \(songs.count)")
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassCard(cornerRadius: 24)
        .padding(.horizontal, 14)
        .padding(.bottom, 96)
    }

    private func batchButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 19, weight: .medium))
                Text(title).font(.caption2.weight(.medium))
            }
            .foregroundStyle(selectedSongIDs.isEmpty ? Theme.secondaryText : Theme.primaryText)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(selectedSongIDs.isEmpty)
    }

    private var allSelected: Bool {
        !vm.filteredSongs.isEmpty && selectedSongIDs.count >= vm.filteredSongs.count
    }

    private func enterSelection(with song: Song) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            selectionMode = true
            selectedSongIDs.insert(song.id)
        }
    }

    private func toggleSelection(_ song: Song) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if selectedSongIDs.contains(song.id) { selectedSongIDs.remove(song.id) }
            else { selectedSongIDs.insert(song.id) }
        }
    }

    private func toggleSelectAll() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if allSelected { selectedSongIDs.removeAll() }
            else { selectedSongIDs = Set(vm.filteredSongs.map(\.id)) }
        }
    }

    private func exitSelection() {
        guard selectionMode else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            selectionMode = false
            selectedSongIDs.removeAll()
        }
    }

    private func finishBatch(_ message: String) {
        showToast(message)
        exitSelection()
    }

    private func showToast(_ message: String) {
        withAnimation { batchToast = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { batchToast = nil }
        }
    }

    private func goToAlbum(_ song: Song) {
        guard let id = song.albumId else { return }
        Task {
            if let album = try? await appState.client?.album(id: id) {
                path.append(LibraryRoute.album(album))
            }
        }
    }

    private func goToArtist(_ song: Song) {
        guard let id = song.artistId else { return }
        Task {
            if let artist = try? await appState.client?.artist(id: id) {
                path.append(LibraryRoute.artist(artist))
            }
        }
    }

    private var genresList: some View {
        let counts = vm.genreAlbumCounts()
        return LazyVStack(spacing: 0) {
            ForEach(vm.filteredGenres, id: \.self) { genre in
                let albumCount = counts[genre] ?? 0
                NavigationLink(value: LibraryRoute.genreAlbums(genre)) {
                    HStack {
                        Text(genre).font(.body).foregroundStyle(Theme.primaryText)
                        Spacer()
                        Text("\(albumCount) Album\(albumCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                        Image(systemName: Symbols.chevron).font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.horizontal, Theme.Layout.screenPadding)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().background(Theme.secondaryText.opacity(0.12)).padding(.leading, Theme.Layout.screenPadding)
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
    case folder(FolderSource)
    // Virtual folder tree built from downloaded songs' paths; `path` is the
    // chain of directory names from the root down to this folder.
    case downloadedFolder(path: [String])
}

// MARK: - Batch add-to-playlist sheet (multi-select)

struct AddSongsToPlaylistSheet: View {
    let songs: [Song]
    var onAdded: (String, Int) -> Void
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var playlists: [Playlist] = []
    @State private var isLoading = true
    @State private var working = false

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if playlists.isEmpty {
                    Text("No playlists yet")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(playlists) { pl in
                        Button { add(to: pl) } label: {
                            HStack(spacing: 12) {
                                ArtworkView(coverArtID: pl.coverArt, size: 100, cornerRadius: 6)
                                    .frame(width: 44, height: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pl.name).font(.body).foregroundStyle(.primary)
                                    if let n = pl.songCount {
                                        Text("\(n) songs").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if working { ProgressView().controlSize(.small) }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(working)
                    }
                }
            }
            .navigationTitle("Add \(songs.count) Song\(songs.count == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(working)
                }
            }
        }
        .task {
            if let client = appState.client {
                playlists = (try? await client.playlists()) ?? []
            }
            isLoading = false
        }
    }

    private func add(to pl: Playlist) {
        guard let client = appState.client else { return }
        working = true
        Task {
            // Add sequentially to preserve server order.
            for song in songs {
                try? await client.addToPlaylist(playlistID: pl.id, songID: song.id)
            }
            await PlaylistBackupStore.shared.backup(playlistID: pl.id, client: client)
            await MainActor.run {
                onAdded(pl.name, songs.count)
                dismiss()
            }
        }
    }
}
