import SwiftUI
import UIKit

/// Original Library experience. Kept intact for people who choose Legacy in
/// Library settings.
struct LegacyLibraryView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = LibraryViewModel()
    @StateObject private var hiddenAlbums = HiddenAlbumStore.shared
    @StateObject private var savedSortStore = SavedLibrarySortStore.shared
    @StateObject private var downloads = DownloadService.shared
    @Binding var path: NavigationPath
    @Namespace private var heroNamespace
    @AppStorage("albumSortOrder") private var albumSortOrder = "alphabetical"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
#if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
#endif

    @State private var selectionMode = false
    @State private var selectedSongIDs: Set<String> = []
    @State private var showBatchPlaylistSheet = false
    @State private var addToPlaylistSong: Song?
    @State private var batchToast: String? = nil
    @State private var customSortEditor: SavedLibrarySortEditorContext?

    private var selectedSongs: [Song] {
        vm.filteredSongs.filter { selectedSongIDs.contains($0.id) }
    }

    private var albumGridColumnCount: Int {
#if os(iOS)
        verticalSizeClass == .compact ? 5 : 3
#else
        3
#endif
    }

    private var albumGridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: Theme.Layout.gridSpacing),
            count: albumGridColumnCount
        )
    }

    private var interactionAnimation: Animation {
        reduceMotion || PerformanceMode.reduceAnimations
            ? .linear(duration: 0.01)
            : .spring(response: 0.32, dampingFraction: 0.84)
    }

    private var libraryContentKey: String {
        "\(vm.source.rawValue)|\(vm.filter.rawValue)|\(vm.isLoading && !vm.hasLoaded)"
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.background.ignoresSafeArea()
                GeometryReader { geo in
                    ScrollViewReader { scrollProxy in
                        ZStack(alignment: .trailing) {
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    sourcePicker
                                    filterPicker
                                    Divider().background(Theme.secondaryText.opacity(0.15))
                                    content
                                        .id(libraryContentKey)
                                        .transition(.opacity)
                                        .animation(interactionAnimation, value: libraryContentKey)
                                }
                                .frame(minHeight: geo.size.height + 160, alignment: .top)
                                .padding(.bottom, 80)
                            }
                            alphabetJumpOverlay(scrollProxy: scrollProxy)
                        }
                    }
                }
            }
            .navigationTitle(L(.tab_library))
            .navigationBarTitleDisplayMode(.large)
            .toolbar(.visible, for: .navigationBar)
            .accountToolbar(path: $path)
            .searchable(text: $vm.searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: searchPrompt)
            .navigationDestination(for: LibraryRoute.self) { route in
                libraryDestination(route)
            }
            .environment(\.heroNamespace, heroNamespace)
            .overlay(alignment: .bottom) { selectionOverlay }
            .sheet(isPresented: $showBatchPlaylistSheet) {
                AddSongsToPlaylistSheet(songs: selectedSongs) { name, count in
                    finishBatch(L(.toast_added_count_to, count, name))
                }
            }
            .sheet(item: $addToPlaylistSong) { song in
                AddToPlaylistSheet(song: song) { name in
                    showToast(L(.toast_added_to, name))
                }
            }
            .sheet(item: $customSortEditor) { context in
                NavigationStack {
                    SavedLibrarySortEditorView(
                        target: context.target,
                        sort: context.sort,
                        previewCountProvider: { vm.customSortPreviewCount(for: $0) }
                    ) { sort in
                        savedSortStore.upsert(sort)
                        vm.applyCustomSort(sort)
                    }
                }
            }
            .onChangeCompat(of: vm.filter) { _, _ in exitSelection() }
            .onChangeCompat(of: vm.source) { _, _ in exitSelection() }
            .onChangeCompat(of: albumSortOrder) { _, value in
                vm.setSort(LibraryViewModel.sortOrder(from: value))
            }
            .onChangeCompat(of: hiddenAlbums.revision) { _, _ in
                exitSelection()
            }
            .onChangeCompat(of: downloads.downloadedRevision) { _, _ in
                exitSelection()
            }
            .onReceive(savedSortStore.$sorts) { sorts in
                vm.reconcileActiveCustomSort(with: sorts)
            }
            .background(NavigationBarRestorer())
        }
        .tint(Theme.accent)
        .preferredColorScheme(Theme.colorScheme)
        .task(id: "\(appState.currentServer?.id ?? "none")|\(appState.isOfflineMode)") {
            if appState.isOfflineMode || appState.client == nil {
                vm.setSource(.downloaded)
            } else if let client = appState.client {
                await vm.load(client: client)
            }
        }
    }

    private var searchPrompt: String {
        L(.library_search_prompt)
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
            DownloadedFolderScreen(path: path, title: path.last ?? L(.library_folders))
        }
    }

    private func folderTitle(_ source: FolderSource) -> String {
        if case .directory(_, let name) = source { return name }
        return L(.library_folders)
    }

    private func genreGrid(genre: String) -> some View {
        let items = vm.albumsForGenre(genre).map(MediaItem.init(album:))
        return FullMediaGrid(title: genre, items: items) { item in
            if let album = item.albumRef { path.append(LibraryRoute.album(album)) }
        }
    }

    // MARK: - Source picker (Server vs Downloaded)

    private var sourcePicker: some View {
        Picker(L(.library_source), selection: Binding(
            get: { vm.source },
            set: { s in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { vm.setSource(s) }
            }
        )) {
            ForEach(LibrarySource.allCases) { s in
                Text(s.label).tag(s)
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
                            withAnimation(interactionAnimation) {
                                vm.setFilter(f)
                            }
                        } label: {
                            Text(f.label)
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
            if let activeCustomSort = vm.activeCustomSort {
                Label(activeCustomSort.name, systemImage: "checkmark.circle.fill")
                Divider()
            }

            Picker(L(.library_sort_by), selection: Binding(get: { vm.sortOrder }, set: { vm.setSort($0) })) {
                ForEach(LibrarySortOrder.allCases) { Text($0.label).tag($0) }
            }

            if let target = vm.customSortTarget {
                let targetSorts = savedSortStore.sorts(for: target)
                Divider()
                if !targetSorts.isEmpty {
                    Menu {
                        ForEach(targetSorts) { sort in
                            Button {
                                vm.applyCustomSort(sort)
                            } label: {
                                Label(
                                    sort.name,
                                    systemImage: vm.activeCustomSort?.id == sort.id ? "checkmark.circle.fill" : "arrow.up.arrow.down"
                                )
                            }
                        }
                    } label: {
                        Label(L(.library_views_saved), systemImage: "slider.horizontal.3")
                    }
                }

                Button {
                    customSortEditor = SavedLibrarySortEditorContext(target: target, sort: vm.activeCustomSort)
                } label: {
                    Label(
                        vm.activeCustomSort == nil ? L(.library_view_filter_settings) : L(.library_view_edit_filter_settings),
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                }

                Button {
                    path.append(SettingsRoute.savedLibrarySorts)
                } label: {
                    Label(L(.library_views_manage), systemImage: "list.bullet.rectangle")
                }
            }

            if !vm.availableGenres.isEmpty {
                Divider()
                Picker(L(.media_genre), selection: Binding(
                    get: { vm.genreFilter ?? "" },
                    set: { vm.setGenreFilter($0.isEmpty ? nil : $0) }
                )) {
                    Text(L(.library_all_genres)).tag("")
                    ForEach(vm.availableGenres, id: \.self) { Text($0).tag($0) }
                }
            }
            Toggle(isOn: Binding(get: { vm.neverPlayedOnly }, set: { vm.neverPlayedOnly = $0 })) {
                Label(L(.library_never_played), systemImage: "moon.zzz")
            }
            if vm.hasActiveFilters {
                Divider()
                Button(role: .destructive) { vm.clearFilters() } label: {
                    Label(L(.library_clear_filters), systemImage: "xmark.circle")
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
        } else if vm.source == .server,
                  let failure = vm.loadFailure(for: vm.filter),
                  vm.currentFilterIsEmpty,
                  vm.searchText.isEmpty {
            serverLoadErrorState(failure)
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
                        Button(L(.library_all_folders)) { vm.selectedFolderID = nil }
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
              let folder = vm.musicFolders.first(where: { $0.id == id }) else { return L(.library_all_folders) }
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

    private func serverLoadErrorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.secondaryText)
            Text("\(vm.filter.rawValue) could not be loaded")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(4)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    @ViewBuilder
    private var albumsGrid: some View {
        let trailingPadding = alphabetContentTrailingPadding
        let groupedSections = albumGroupSections
        if !groupedSections.isEmpty {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(groupedSections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        libraryGroupHeader(section.label, horizontalPadding: false)
                        ForEach(albumGridRows(for: section.items, prefix: section.id)) { row in
                            HStack(alignment: .top, spacing: Theme.Layout.gridSpacing) {
                                ForEach(row.items) { album in
                                    albumGridItem(album)
                                        .frame(maxWidth: .infinity, alignment: .topLeading)
                                }
                                ForEach(row.items.count..<albumGridColumnCount, id: \.self) { _ in
                                    Color.clear
                                        .frame(maxWidth: .infinity)
                                        .accessibilityHidden(true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(row.id)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.vertical, 12)
        } else if usesAlbumAlphabetSections {
            LazyVStack(spacing: Theme.Layout.gridSpacing) {
                ForEach(albumGridRows) { row in
                    HStack(alignment: .top, spacing: Theme.Layout.gridSpacing) {
                        ForEach(row.items) { album in
                            albumGridItem(album)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        ForEach(row.items.count..<albumGridColumnCount, id: \.self) { _ in
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(row.id)
                }
            }
            .padding(.leading, Theme.Layout.screenPadding)
            .padding(.trailing, trailingPadding)
            .padding(.vertical, 12)
        } else {
            LazyVGrid(columns: albumGridColumns, spacing: Theme.Layout.gridSpacing) {
                ForEach(vm.filteredAlbums) { album in
                    albumGridItem(album)
                }
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.vertical, 12)
        }
    }

    private func albumGridItem(_ album: Album) -> some View {
        NavigationLink(value: LibraryRoute.album(album)) {
            MediaCard(item: MediaItem(album: album))
        }
        .buttonStyle(.plain)
        .albumContextMenu(album)
    }

    private var artistsList: some View {
        let trailingPadding = alphabetContentTrailingPadding
        return LazyVStack(spacing: 0) {
            ForEach(vm.filteredArtists) { artist in
                NavigationLink(value: LibraryRoute.artist(artist)) {
                    HStack(spacing: 14) {
                        ArtworkView(coverArtID: artist.coverArt, artistID: artist.id, size: 100, cornerRadius: 28)
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
                    .padding(.leading, Theme.Layout.screenPadding)
                    .padding(.trailing, trailingPadding)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .id(alphabetAnchorID(kind: "artist", rawID: artist.id))
                Divider().background(Theme.secondaryText.opacity(0.12)).padding(.leading, 70)
            }
        }
    }

    private var songsList: some View {
        let groupedSections = songGroupSections
        if !groupedSections.isEmpty {
            return AnyView(
                LazyVStack(spacing: 0) {
                    if !vm.filteredSongs.isEmpty {
                        librarySongsActions
                    }
                    ForEach(groupedSections) { section in
                        libraryGroupHeader(section.label)
                        ForEach(section.items) { entry in
                            songListEntry(entry, trailingPadding: Theme.Layout.screenPadding)
                        }
                    }
                }
            )
        }

        let sections = usesSongAlphabetSections ? songAlphabetSections : []
        let entries = sections.isEmpty ? songListEntries : songListEntries(from: sections)
        let trailingPadding = showsAlphabetJumpBar(jumpItems(from: sections)) ? 48 : Theme.Layout.screenPadding
        return AnyView(
            LazyVStack(spacing: 0) {
                if !vm.filteredSongs.isEmpty {
                    librarySongsActions
                }
                ForEach(entries) { entry in
                    songListEntry(entry, trailingPadding: trailingPadding)
                }
            }
        )
    }

    private func libraryGroupHeader(_ title: String, horizontalPadding: Bool = true) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, horizontalPadding ? Theme.Layout.screenPadding : 0)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func songListEntry(_ entry: SongListEntry, trailingPadding: CGFloat) -> some View {
        VStack(spacing: 0) {
            songRow(entry.song, visibleIndex: entry.visibleIndex, trailingPadding: trailingPadding)
            Divider().background(Theme.secondaryText.opacity(0.12))
                .padding(.leading, selectionMode ? 96 : 68)
        }
        .id(entry.id)
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
    private func songRow(_ song: Song, visibleIndex: Int, trailingPadding: CGFloat? = nil) -> some View {
        let resolvedTrailingPadding = trailingPadding ?? alphabetContentTrailingPadding
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
            .padding(.leading, Theme.Layout.screenPadding)
            .padding(.trailing, resolvedTrailingPadding)
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
            .padding(.leading, Theme.Layout.screenPadding)
            .padding(.trailing, resolvedTrailingPadding)
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
                Button(allSelected ? L(.library_deselect_all) : L(.library_select_all)) { toggleSelectAll() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            HStack(spacing: 0) {
                batchButton(L(.action_play_next), "text.line.first.and.arrowtriangle.forward") {
                    appState.audioPlayer.playNext(selectedSongs)
                    finishBatch(L(.toast_playing_n_next, selectedSongs.count))
                }
                batchButton(L(.action_queue), "text.append") {
                    appState.audioPlayer.addToQueue(selectedSongs)
                    finishBatch(L(.toast_added_n_to_queue, selectedSongs.count))
                }
                batchButton(L(.media_playlist), Symbols.addToPlaylist) {
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
                        finishBatch(L(.toast_downloading_n, songs.count))
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
        withAnimation(interactionAnimation) {
            selectionMode = true
            selectedSongIDs.insert(song.id)
        }
    }

    private func toggleSelection(_ song: Song) {
        withAnimation(interactionAnimation) {
            if selectedSongIDs.contains(song.id) { selectedSongIDs.remove(song.id) }
            else { selectedSongIDs.insert(song.id) }
        }
    }

    private func toggleSelectAll() {
        withAnimation(interactionAnimation) {
            if allSelected { selectedSongIDs.removeAll() }
            else { selectedSongIDs = Set(vm.filteredSongs.map(\.id)) }
        }
    }

    private func exitSelection() {
        guard selectionMode else { return }
        withAnimation(interactionAnimation) {
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

    @ViewBuilder
    private func alphabetJumpOverlay(scrollProxy: ScrollViewProxy) -> some View {
        let items = alphabetJumpItems
        if showsAlphabetJumpBar(items) {
            AlphabetJumpBar(items: items) { item in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeOut(duration: 0.18)) {
                    scrollProxy.scrollTo(item.targetID, anchor: .top)
                }
            }
            .padding(.trailing, 4)
            .transition(.opacity)
        }
    }

    private var alphabetContentTrailingPadding: CGFloat {
        showsAlphabetJumpBar(alphabetJumpItems) ? 48 : Theme.Layout.screenPadding
    }

    private var alphabetJumpItems: [AlphabetJumpItem] {
        switch vm.filter {
        case .artists:
            return alphabetJumpItems(
                vm.filteredArtists.map { ($0.name, alphabetAnchorID(kind: "artist", rawID: $0.id)) }
            )
        case .albums:
            guard usesAlbumAlphabetSections else { return [] }
            return alphabetJumpItems(
                vm.filteredAlbums.map { album in
                    let key = alphabetSectionKey(for: album.name)
                    return (album.name, alphabetAnchorID(kind: "album", rawID: "section-\(key)"))
                }
            )
        case .songs:
            guard usesSongAlphabetSections else { return [] }
            return songAlphabetSections.map { AlphabetJumpItem(label: $0.label, targetID: $0.targetID) }
        case .genres, .folders:
            return []
        }
    }

    private var usesAlbumAlphabetSections: Bool {
        if let activeCustomSort = vm.activeCustomSort {
            return activeCustomSort.usesAlbumAlphabetSections
        }
        return vm.sortOrder == .name || vm.sortOrder == .album
    }

    private var usesSongAlphabetSections: Bool {
        if let activeCustomSort = vm.activeCustomSort {
            return activeCustomSort.usesSongAlphabetSections
        }
        return vm.sortOrder == .name
    }

    private var albumAlphabetSections: [AlphabetSection<Album>] {
        alphabetSections(
            kind: "album",
            items: vm.filteredAlbums,
            title: { $0.name }
        )
    }

    private var albumGridRows: [AlbumGridRow] {
        var rows: [AlbumGridRow] = []
        var anchoredLetters: Set<String> = []

        for section in albumAlphabetSections {
            for offset in stride(from: 0, to: section.items.count, by: albumGridColumnCount) {
                let end = min(offset + albumGridColumnCount, section.items.count)
                let items = Array(section.items[offset..<end])
                guard let firstAlbumID = items.first?.id else { continue }
                let anchorID: String?
                if offset == 0, anchoredLetters.insert(section.label).inserted {
                    anchorID = section.targetID
                } else {
                    anchorID = nil
                }
                rows.append(
                    AlbumGridRow(
                        id: anchorID ?? "library-album-row-\(firstAlbumID)",
                        items: items
                    )
                )
            }
        }

        return rows
    }

    private var albumGroupSections: [LibraryGroupSection<Album>] {
        guard let activeCustomSort = vm.activeCustomSort,
              activeCustomSort.groupMode != .none else { return [] }
        return groupedSections(
            kind: "album",
            items: vm.filteredAlbums,
            label: { activeCustomSort.groupLabel(for: $0) }
        )
    }

    private func albumGridRows(for albums: [Album], prefix: String) -> [AlbumGridRow] {
        var rows: [AlbumGridRow] = []
        for offset in stride(from: 0, to: albums.count, by: albumGridColumnCount) {
            let end = min(offset + albumGridColumnCount, albums.count)
            let items = Array(albums[offset..<end])
            guard let firstAlbumID = items.first?.id else { continue }
            rows.append(AlbumGridRow(id: "\(prefix)-row-\(firstAlbumID)", items: items))
        }
        return rows
    }

    private var songListEntries: [SongListEntry] {
        vm.filteredSongs.enumerated().map { SongListEntry(visibleIndex: $0.offset, song: $0.element) }
    }

    private var songGroupSections: [LibraryGroupSection<SongListEntry>] {
        guard let activeCustomSort = vm.activeCustomSort,
              activeCustomSort.groupMode != .none else { return [] }
        return groupedSections(
            kind: "song",
            items: songListEntries,
            label: { activeCustomSort.groupLabel(for: $0.song) }
        )
    }

    private var songAlphabetSections: [AlphabetSection<SongListEntry>] {
        alphabetSections(
            kind: "song",
            items: songListEntries,
            title: { $0.song.title }
        )
    }

    private func songListEntries(from sections: [AlphabetSection<SongListEntry>]) -> [SongListEntry] {
        sections.flatMap { section in
            section.items.enumerated().map { offset, entry in
                SongListEntry(
                    visibleIndex: entry.visibleIndex,
                    song: entry.song,
                    anchorID: offset == 0 ? section.targetID : nil
                )
            }
        }
    }

    private func showsAlphabetJumpBar(_ items: [AlphabetJumpItem]) -> Bool {
        !selectionMode && items.count >= 3
    }

    private func jumpItems<Item>(from sections: [AlphabetSection<Item>]) -> [AlphabetJumpItem] {
        sections.map { AlphabetJumpItem(label: $0.label, targetID: $0.targetID) }
    }

    private func groupedSections<Item>(
        kind: String,
        items: [Item],
        label: (Item) -> String
    ) -> [LibraryGroupSection<Item>] {
        var sections: [LibraryGroupSection<Item>] = []
        var sectionIndexes: [String: Int] = [:]

        for item in items {
            let groupLabel = label(item)
            if let index = sectionIndexes[groupLabel] {
                sections[index].items.append(item)
            } else {
                let id = "library-\(kind)-group-\(sections.count)"
                sectionIndexes[groupLabel] = sections.count
                sections.append(LibraryGroupSection(id: id, label: groupLabel, items: [item]))
            }
        }

        return sections
    }

    private func alphabetSections<Item>(
        kind: String,
        items: [Item],
        title: (Item) -> String
    ) -> [AlphabetSection<Item>] {
        var sections: [AlphabetSection<Item>] = []

        for item in items {
            let key = alphabetSectionKey(for: title(item))
            if sections.last?.label == key {
                sections[sections.count - 1].items.append(item)
            } else {
                sections.append(
                    AlphabetSection(
                        label: key,
                        targetID: alphabetAnchorID(kind: kind, rawID: "section-\(key)"),
                        items: [item]
                    )
                )
            }
        }

        return sections
    }

    private func alphabetJumpItems(_ namesAndIDs: [(String, String)]) -> [AlphabetJumpItem] {
        var seen: Set<String> = []
        var items: [AlphabetJumpItem] = []

        for entry in namesAndIDs {
            let key = alphabetSectionKey(for: entry.0)
            guard seen.insert(key).inserted else { continue }
            items.append(AlphabetJumpItem(label: key, targetID: entry.1))
        }

        return items.sorted { alphabetSortRank($0.label) < alphabetSortRank($1.label) }
    }

    private func alphabetAnchorID(kind: String, rawID: String) -> String {
        "library-\(kind)-\(rawID)"
    }

    private func alphabetSectionKey(for text: String) -> String {
        let normalized = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard let first = normalized.first else { return "#" }
        let uppercased = String(first).uppercased()
        return ("A"..."Z").contains(uppercased) ? uppercased : "#"
    }

    private func alphabetSortRank(_ key: String) -> Int {
        guard key != "#", let scalar = key.unicodeScalars.first else { return 26 }
        return Int(scalar.value - UnicodeScalar("A").value)
    }

    private func formatDuration(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct AlphabetJumpItem: Identifiable {
    let label: String
    let targetID: String

    var id: String { label }
}

private struct AlphabetSection<Item>: Identifiable {
    let label: String
    let targetID: String
    var items: [Item]

    var id: String { targetID }
}

private struct AlbumGridRow: Identifiable {
    let id: String
    let items: [Album]
}

private struct LibraryGroupSection<Item>: Identifiable {
    let id: String
    let label: String
    var items: [Item]
}

private struct SongListEntry: Identifiable {
    let visibleIndex: Int
    let song: Song
    var anchorID: String? = nil

    var id: String { anchorID ?? song.id }
}

struct AlphabetJumpBar: View {
    let items: [AlphabetJumpItem]
    var onSelect: (AlphabetJumpItem) -> Void

    @State private var activeID: String?

    private let rowHeight: CGFloat = 14
    private let verticalPadding: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ForEach(items) { item in
                    Text(item.label)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(activeID == item.id ? Theme.background : Theme.accent.opacity(0.95))
                        .frame(width: 20, height: rowHeight)
                        .background(activeID == item.id ? Theme.accent : Color.clear, in: Circle())
                        .contentShape(Rectangle())
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("Jump to \(item.label)")
                        .accessibilityAction {
                            select(item)
                            clearActive(afterSelecting: item.id)
                        }
                }
            }
            .padding(.vertical, verticalPadding)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        selectItem(at: value.location.y, height: geometry.size.height)
                    }
                    .onEnded { _ in
                        activeID = nil
                    }
            )
        }
        .frame(width: 24, height: CGFloat(items.count) * rowHeight + verticalPadding * 2)
    }

    private func select(_ item: AlphabetJumpItem) {
        activeID = item.id
        onSelect(item)
    }

    private func clearActive(afterSelecting id: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if activeID == id {
                activeID = nil
            }
        }
    }

    private func selectItem(at y: CGFloat, height: CGFloat) {
        let contentTop = verticalPadding
        let contentHeight = max(rowHeight, height - verticalPadding * 2)
        let clampedY = min(max(y - contentTop, 0), contentHeight - 0.1)
        let index = Int(clampedY / rowHeight)
        guard items.indices.contains(index) else { return }

        let item = items[index]
        guard activeID != item.id else { return }
        select(item)
    }
}

struct NavigationBarRestorer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.restore()
    }

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            restore()
        }

        func restore() {
            navigationController?.setNavigationBarHidden(false, animated: false)
        }
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
    @EnvironmentObject private var appState: AppState
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
                    Text(L(.playlists_none_yet))
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
                                        Text(L(.home_song_count, n)).font(.caption).foregroundStyle(.secondary)
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
            .navigationTitle(L(.library_add_n_songs, songs.count))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L(.action_cancel)) { dismiss() }.disabled(working)
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
