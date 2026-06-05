import SwiftUI

private enum PlaylistCreateKind: String, CaseIterable, Identifiable {
    case custom = "Custom"
    case smart = "Smart"
    var id: String { rawValue }
}

struct PlaylistsView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = PlaylistsViewModel()
    @State private var smartStore = SmartPlaylistStore.shared
    @State private var pendingDelete: Playlist?
    @State private var pendingSmartDelete: SmartPlaylist?
    @Binding var path: [Playlist]
    @Namespace private var heroNamespace

    @State private var createKind: PlaylistCreateKind = .custom
    @State private var smartDraft = SmartPlaylist(name: "")
    @State private var minYearText = ""
    @State private var maxYearText = ""
    @State private var minPlayText = ""
    @State private var maxPlayText = ""
    @State private var showSmartArtistPicker = false
    @State private var showSmartAlbumPicker = false

    private let columns = [GridItem(.flexible(), spacing: Theme.Layout.gridSpacing),
                           GridItem(.flexible(), spacing: Theme.Layout.gridSpacing)]

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.background.ignoresSafeArea()
                if vm.isLoading && !vm.hasLoaded {
                    ProgressView().controlSize(.large).tint(Theme.accent)
                } else if vm.filtered.isEmpty && filteredSmartPlaylists.isEmpty && vm.hasLoaded {
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
                    .zoomNavigationTransition(sourceID: pl.id, in: heroNamespace)
            }
            .environment(\.heroNamespace, heroNamespace)
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $vm.showCreateSheet) {
            createSheet
        }
            .confirmationDialog(
                "Delete Playlist?",
            isPresented: Binding(get: { pendingDelete != nil },
                                 set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { pl in
            Button("Delete “\(pl.name)”", role: .destructive) {
                if let client = appState.client {
                    Task { await vm.deletePlaylist(pl, client: client) }
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { pl in
            Text("“\(pl.name)” will be permanently deleted. This can’t be undone.")
        }
        .confirmationDialog(
            "Delete Smart Playlist?",
            isPresented: Binding(get: { pendingSmartDelete != nil },
                                 set: { if !$0 { pendingSmartDelete = nil } }),
            presenting: pendingSmartDelete
        ) { smart in
            Button("Delete “\(smart.name)”", role: .destructive) {
                smartStore.delete(smart)
                pendingSmartDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingSmartDelete = nil }
        } message: { smart in
            Text("“\(smart.name)” will be removed from this device.")
        }
        .task(id: appState.currentServer?.id) {
            if let client = appState.client { await vm.load(client: client) }
        }
    }

    private var filteredSmartPlaylists: [SmartPlaylist] {
        let list = smartStore.playlists
        let filtered = vm.searchText.isEmpty ? list : list.filter {
            $0.name.localizedCaseInsensitiveContains(vm.searchText)
            || $0.ruleSummary.localizedCaseInsensitiveContains(vm.searchText)
        }
        return filtered.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.pinned != rhs.element.pinned { return lhs.element.pinned }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.Layout.gridSpacing) {
                ForEach(vm.filtered) { pl in
                    NavigationLink(value: pl) { serverPlaylistCard(pl) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { vm.togglePin(pl) }
                        } label: {
                            Label(vm.isPinned(pl) ? "Unpin" : "Pin to Top",
                                  systemImage: vm.isPinned(pl) ? "pin.slash" : "pin")
                        }
                        Button(role: .destructive) {
                            pendingDelete = pl
                        } label: {
                            Label("Delete Playlist", systemImage: Symbols.trash)
                        }
                    }
                }
                ForEach(filteredSmartPlaylists) { smart in
                    NavigationLink {
                        SmartPlaylistDetailView(playlist: smart, sourceSongs: vm.smartSourceSongs)
                    } label: {
                        smartPlaylistCard(smart)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            smartStore.togglePin(smart)
                        } label: {
                            Label(smart.pinned ? "Unpin" : "Pin to Top",
                                  systemImage: smart.pinned ? "pin.slash" : "pin")
                        }
                        Button(role: .destructive) {
                            pendingSmartDelete = smart
                        } label: {
                            Label("Delete Smart Playlist", systemImage: Symbols.trash)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.vertical, 12)
            .padding(.bottom, 80)
        }
    }

    private func serverPlaylistCard(_ pl: Playlist) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PlaylistCover(playlist: pl, size: 400)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .heroSource(id: pl.id)
                .overlay(alignment: .topTrailing) {
                    if vm.isPinned(pl) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.45), in: Circle())
                            .padding(8)
                    }
                }
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

    private func smartPlaylistCard(_ smart: SmartPlaylist) -> some View {
        let songs = smart.resolve(from: vm.smartSourceSongs)
        return VStack(alignment: .leading, spacing: 6) {
            SmartPlaylistCover(songs: songs)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    if smart.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.45), in: Circle())
                            .padding(8)
                    }
                }
            Text(smart.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
            Text("\(songs.count) songs · \(smart.ruleSummary)")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
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
                    Picker("Type", selection: $createKind) {
                        ForEach(PlaylistCreateKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if createKind == .custom {
                    Section {
                        TextField("Playlist name", text: $vm.newPlaylistName)
                    }
                } else {
                    smartPlaylistForm
                }
            }
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { closeCreateSheet() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        if createKind == .custom {
                            if let client = appState.client {
                                Task { await vm.createPlaylist(client: client) }
                            }
                        } else {
                            createSmartPlaylist()
                        }
                    }
                    .disabled(createDisabled)
                }
            }
        }
        .presentationDetents(createKind == .custom ? [.height(260)] : [.large])
        .onAppear { resetCreateDrafts() }
        .sheet(isPresented: $showSmartArtistPicker) {
            SmartMultiSelectSheet(title: "Artists", options: vm.smartArtists, selection: $smartDraft.selectedArtists)
        }
        .sheet(isPresented: $showSmartAlbumPicker) {
            SmartMultiSelectSheet(title: "Albums", options: vm.smartAlbums, selection: $smartDraft.selectedAlbums)
        }
    }

    private var createDisabled: Bool {
        switch createKind {
        case .custom:
            return vm.newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty || vm.isCreating
        case .smart:
            return smartDraft.name.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var smartPlaylistForm: some View {
        Group {
            Section("Name") {
                TextField("Smart playlist name", text: $smartDraft.name)
                TextField("Description", text: Binding(
                    get: { smartDraft.subtitle ?? "" },
                    set: { smartDraft.subtitle = $0.isEmpty ? nil : $0 }
                ))
            }

            Section("Rules") {
                Picker("Match", selection: $smartDraft.matchMode) {
                    ForEach(SmartMatchMode.allCases) { Text($0.rawValue).tag($0) }
                }
                TextField("Title, artist, album, genre contains", text: $smartDraft.searchText)
                TextField("Artist contains", text: $smartDraft.artist)
                TextField("Album contains", text: $smartDraft.album)
                Button { showSmartArtistPicker = true } label: {
                    smartSelectionRow("Artists", values: smartDraft.selectedArtists)
                }
                Button { showSmartAlbumPicker = true } label: {
                    smartSelectionRow("Albums", values: smartDraft.selectedAlbums)
                }
                Picker("Genre", selection: $smartDraft.genre) {
                    Text("Any Genre").tag("")
                    ForEach(vm.smartGenres, id: \.self) { Text($0).tag($0) }
                }
            }

            Section("Filters") {
                TextField("Minimum year", text: $minYearText)
                    .keyboardType(.numberPad)
                TextField("Maximum year", text: $maxYearText)
                    .keyboardType(.numberPad)
                TextField("Minimum plays", text: $minPlayText)
                    .keyboardType(.numberPad)
                TextField("Maximum plays", text: $maxPlayText)
                    .keyboardType(.numberPad)
                Toggle("Never Played Only", isOn: $smartDraft.neverPlayedOnly)
                Toggle("Lossless Only", isOn: $smartDraft.onlyLossless)
                Toggle("Downloaded Only", isOn: $smartDraft.onlyDownloaded)
                Picker("Taste", selection: $smartDraft.taste) {
                    ForEach(SmartTasteFilter.allCases) { Text($0.rawValue).tag($0) }
                }
            }

            Section("Mix Options") {
                Picker("Sort", selection: $smartDraft.sort) {
                    ForEach(SmartSortMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Stepper("Limit: \(smartDraft.limit) songs", value: $smartDraft.limit, in: 5...200, step: 5)
                Text("\(smartPreviewCount) matching songs right now")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var smartPreviewCount: Int {
        smartDraftWithNumbers().resolve(from: vm.smartSourceSongs).count
    }

    private func smartSelectionRow(_ title: String, values: [String]) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(values.isEmpty ? "Any" : "\(values.count) selected")
                .foregroundStyle(.secondary)
            Image(systemName: Symbols.chevron)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func smartDraftWithNumbers() -> SmartPlaylist {
        var draft = smartDraft
        draft.minYear = Int(minYearText.trimmingCharacters(in: .whitespaces))
        draft.maxYear = Int(maxYearText.trimmingCharacters(in: .whitespaces))
        draft.minPlayCount = Int(minPlayText.trimmingCharacters(in: .whitespaces))
        draft.maxPlayCount = Int(maxPlayText.trimmingCharacters(in: .whitespaces))
        return draft
    }

    private func createSmartPlaylist() {
        var draft = smartDraftWithNumbers()
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        smartStore.upsert(draft)
        closeCreateSheet()
    }

    private func closeCreateSheet() {
        vm.showCreateSheet = false
        resetCreateDrafts()
    }

    private func resetCreateDrafts() {
        createKind = .custom
        smartDraft = SmartPlaylist(name: "")
        minYearText = ""
        maxYearText = ""
        minPlayText = ""
        maxPlayText = ""
    }
}

private struct SmartPlaylistCover: View {
    let songs: [Song]

    var body: some View {
        let coverSongs = Array(songs.filter { $0.coverArt != nil }.prefix(4))
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let tileSide = (side - 1) / 2

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.Layout.cardCorner, style: .continuous)
                    .fill(Theme.secondaryBackground)
                    .frame(width: side, height: side)

                if coverSongs.isEmpty {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: side, height: side)
                } else if coverSongs.count == 1 {
                    ArtworkView(coverArtID: coverSongs[0].coverArt, size: 400, cornerRadius: 0)
                        .frame(width: side, height: side)
                } else {
                    ForEach(Array(coverSongs.enumerated()), id: \.element.id) { index, song in
                        ArtworkView(coverArtID: song.coverArt, size: 240, cornerRadius: 0)
                            .frame(width: tileSide, height: tileSide)
                            .clipped()
                            .offset(
                                x: CGFloat(index % 2) * (tileSide + 1),
                                y: CGFloat(index / 2) * (tileSide + 1)
                            )
                    }
                    if coverSongs.count == 3 {
                        Rectangle()
                            .fill(Theme.secondaryBackground)
                            .frame(width: tileSide, height: tileSide)
                            .offset(x: tileSide + 1, y: tileSide + 1)
                    }
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardCorner, style: .continuous))
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct SmartMultiSelectSheet: View {
    let title: String
    let options: [String]
    @Binding var selection: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredOptions: [String] {
        searchText.isEmpty ? options : options.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private var selectedSet: Set<String> { Set(selection) }

    var body: some View {
        NavigationStack {
            List {
                if !selection.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            selection.removeAll()
                        } label: {
                            Label("Clear Selection", systemImage: "xmark.circle")
                        }
                    }
                }

                Section {
                    ForEach(filteredOptions, id: \.self) { option in
                        Button { toggle(option) } label: {
                            HStack {
                                Text(option)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedSet.contains(option) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search \(title.lowercased())")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func toggle(_ option: String) {
        if selection.contains(option) {
            selection.removeAll { $0 == option }
        } else {
            selection.append(option)
            selection.sort()
        }
    }
}

private struct SmartPlaylistDetailView: View {
    let playlist: SmartPlaylist
    let sourceSongs: [Song]

    @Environment(AppState.self) private var appState
    @State private var activeSheet: PlaylistSheet? = nil
    @State private var toastMessage: String?
    @AppStorage("showTrackArtwork") private var showTrackArtwork = true

    private var songs: [Song] { playlist.resolve(from: sourceSongs) }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    coverSection
                    infoSection
                    actionRow
                    trackList
                    footer
                    Color.clear.frame(height: 120)
                }
            }
            .scrollIndicators(.hidden)

            if let msg = toastMessage {
                VStack {
                    Spacer()
                    PlaybackActionToast(message: msg)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 78)
                }
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        .background(SwipeBackEnabler())
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addToPlaylist(let song):
                AddToPlaylistSheet(song: song, onAdded: { name in showToast("Added to \(name)") })
            case .album(let album):
                NavigationStack {
                    AlbumDetailView(album: album)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { activeSheet = nil }.foregroundStyle(Theme.accent)
                            }
                        }
                }
                .preferredColorScheme(.dark)
            case .artist(let artist):
                NavigationStack {
                    ArtistDetailView(artist: artist)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { activeSheet = nil }.foregroundStyle(Theme.accent)
                            }
                        }
                }
                .preferredColorScheme(.dark)
            case .edit:
                EmptyView()
            }
        }
    }

    private var coverSection: some View {
        GeometryReader { geo in
            SmartPlaylistCover(songs: songs)
                .frame(width: geo.size.width, height: geo.size.width)
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, Theme.background], startPoint: .center, endPoint: .bottom)
                        .frame(height: 160)
                }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(playlist.name)
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text(playlist.subtitle?.isEmpty == false ? playlist.subtitle! : playlist.ruleSummary)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var actionRow: some View {
        HStack(spacing: 14) {
            Button {
                let shuffled = songs.shuffled()
                if !shuffled.isEmpty {
                    appState.audioPlayer.playQueue(shuffled, startIndex: 0, source: playlist.name)
                }
            } label: {
                Image(systemName: Symbols.shuffle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .glassCircle()
            }
            .buttonStyle(.plain)

            Button {
                if !songs.isEmpty {
                    appState.audioPlayer.playQueue(songs, startIndex: 0, source: playlist.name)
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: Symbols.play).font(.system(size: 14, weight: .bold))
                    Text("Play").font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)

            DownloadAlbumButton(songs: songs)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }

    private var trackList: some View {
        VStack(spacing: 0) {
            Divider()
                .frame(height: 0.75)
                .overlay(.white.opacity(0.15))
                .padding(.bottom, 4)
            ForEach(Array(songs.enumerated()), id: \.element.id) { i, song in
                TrackRow(
                    song: song,
                    index: i + 1,
                    isCurrentlyPlaying: appState.audioPlayer.currentSong?.id == song.id,
                    onTap: {
                        appState.audioPlayer.playQueue(songs, startIndex: i, source: playlist.name)
                    },
                    showArtist: true,
                    leadingArtwork: showTrackArtwork,
                    onSwipePlayNext: {
                        appState.audioPlayer.playNext(song)
                        showToast("Playing Next")
                    }
                ) {
                    SongMenu(
                        song: song,
                        onGoToAlbum: song.albumId == nil ? nil : { goToAlbum(song) },
                        onGoToArtist: song.artistId == nil ? nil : { goToArtist(song) },
                        onAddToPlaylist: { activeSheet = .addToPlaylist(song) }
                    )
                }
                Divider().overlay(.white.opacity(0.14))
            }
        }
        .padding(.horizontal, 20)
        .simultaneousGesture(verticalPlaybackSwipe)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(songs.count) songs")
            Text("\(playlist.matchMode.rawValue) · \(playlist.sort.rawValue)")
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.4))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }

    private func goToAlbum(_ song: Song) {
        guard let id = song.albumId else { return }
        Task {
            if let album = try? await appState.client?.album(id: id) { activeSheet = .album(album) }
        }
    }

    private func goToArtist(_ song: Song) {
        guard let id = song.artistId else { return }
        Task {
            if let artist = try? await appState.client?.artist(id: id) { activeSheet = .artist(artist) }
        }
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { toastMessage = nil }
        }
    }

    private var verticalPlaybackSwipe: some Gesture {
        DragGesture(minimumDistance: 80)
            .onEnded { value in
                guard abs(value.translation.height) > 180,
                      abs(value.translation.width) < 55 else { return }
                moveWithinSmartPlaylist(delta: value.translation.height < 0 ? 1 : -1)
            }
    }

    private func moveWithinSmartPlaylist(delta: Int) {
        let list = songs
        guard let current = appState.audioPlayer.currentSong,
              let currentIndex = list.firstIndex(where: { $0.id == current.id }) else { return }
        let nextIndex = max(0, min(list.count - 1, currentIndex + delta))
        guard nextIndex != currentIndex else { return }
        appState.audioPlayer.playQueue(list, startIndex: nextIndex, source: playlist.name)
    }
}
