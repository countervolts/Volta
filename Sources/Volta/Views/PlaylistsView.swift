import SwiftUI
import UIKit

private enum PlaylistCreateKind: String, CaseIterable, Identifiable {
    case custom = "Custom"
    case smart = "Smart"
    case folder = "Folder"
    var id: String { rawValue }
    @MainActor var label: String {
        switch self {
        case .custom: return L(.create_kind_custom)
        case .smart:  return L(.create_kind_smart)
        case .folder: return L(.media_folder)
        }
    }
}

private struct SmartPlaylistEvaluationKey: Hashable {
    let playlists: [SmartPlaylist]
    let sourceRevision: Int
    let tasteRevision: Int
    let downloadedRevision: Int
}

/// Restores the parent list's navigation bar after an immersive playlist
/// detail view has hidden it. This is scoped to the playlists stack so the
/// parent grid returns with its normal large-title layout after a pop.
private struct PlaylistNavigationBarRestorer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.restore()
    }

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            restore()
        }

        func restore() {
            // SwiftUI can update the background representable while the pushed
            // detail is still on screen. Do not re-show the parent bar until
            // this list's controller is actually visible again.
            guard viewIfLoaded?.window != nil else { return }
            navigationController?.setNavigationBarHidden(false, animated: false)
        }
    }
}

struct PlaylistsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = PlaylistsViewModel()
    @StateObject private var smartStore = SmartPlaylistStore.shared
    @StateObject private var folderStore = PlaylistFolderStore.shared
    @StateObject private var downloadService = DownloadService.shared
    @StateObject private var tasteStore = TasteStore.shared
    @StateObject private var dynamicResults = SmartPlaylistResults()
    @StateObject private var previewResults = SmartPlaylistResults()
    @State private var pendingDelete: Playlist?
    @State private var pendingSmartDelete: SmartPlaylist?
    @State private var pendingFolderDelete: PlaylistFolder?
    @Binding var path: NavigationPath
    @Namespace private var heroNamespace

    @State private var createKind: PlaylistCreateKind = .custom
    @State private var customPlaylistIsDynamic = false
    @State private var smartDraft = SmartPlaylist(name: "")
    @State private var minYearText = ""
    @State private var maxYearText = ""
    @State private var minPlayText = ""
    @State private var maxPlayText = ""
    @State private var duplicateCreateMessage: String?

    private let columns = [GridItem(.flexible(), spacing: Theme.Layout.gridSpacing),
                           GridItem(.flexible(), spacing: Theme.Layout.gridSpacing)]

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.background.ignoresSafeArea()
                if vm.isLoading && !vm.hasLoaded {
                    ProgressView().controlSize(.large).tint(Theme.accent)
                } else if rootPlaylists.isEmpty && rootSmartPlaylists.isEmpty && visibleFolders.isEmpty && vm.hasLoaded {
                    emptyState
                } else {
                    grid
                }
            }
            .navigationTitle(L(.tab_playlists))
            .navigationBarTitleDisplayMode(.large)
            // Playlist detail uses an immersive, hidden navigation bar. Reassert
            // this stack's visible bar so an interactive pop cannot leave the
            // grid drawing through the large "Playlists" title.
            .toolbar(.visible, for: .navigationBar)
            .searchable(text: $vm.searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: L(.playlists_search_prompt))
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
            .accountToolbar(path: $path)
            .navigationDestination(for: Playlist.self) { pl in
                PlaylistDetailView(playlist: pl)
                    .zoomNavigationTransition(sourceID: pl.id, in: heroNamespace)
            }
            .environment(\.heroNamespace, heroNamespace)
            .background(PlaylistNavigationBarRestorer())
        }
        .tint(Theme.accent)
        .preferredColorScheme(Theme.colorScheme)
        .sheet(isPresented: $vm.showCreateSheet) {
            createSheet
        }
            .confirmationDialog(
                L(.playlist_delete_q),
            isPresented: Binding(get: { pendingDelete != nil },
                                 set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { pl in
            Button(L(.playlist_delete_named, pl.name), role: .destructive) {
                if let client = appState.client {
                    Task { await vm.deletePlaylist(pl, client: client) }
                }
                pendingDelete = nil
            }
            Button(L(.action_cancel), role: .cancel) { pendingDelete = nil }
        } message: { pl in
            Text(L(.playlist_delete_msg, pl.name))
        }
        .confirmationDialog(
            L(.smart_delete_q),
            isPresented: Binding(get: { pendingSmartDelete != nil },
                                 set: { if !$0 { pendingSmartDelete = nil } }),
            presenting: pendingSmartDelete
        ) { smart in
            Button(L(.playlist_delete_named, smart.name), role: .destructive) {
                smartStore.delete(smart)
                pendingSmartDelete = nil
            }
            Button(L(.action_cancel), role: .cancel) { pendingSmartDelete = nil }
        } message: { smart in
            Text(L(.smart_delete_msg, smart.name))
        }
        .confirmationDialog(
            L(.folder_delete_q),
            isPresented: Binding(get: { pendingFolderDelete != nil },
                                 set: { if !$0 { pendingFolderDelete = nil } }),
            presenting: pendingFolderDelete
        ) { folder in
            Button(L(.playlist_delete_named, folder.name), role: .destructive) {
                folderStore.delete(folder)
                pendingFolderDelete = nil
            }
            Button(L(.action_cancel), role: .cancel) { pendingFolderDelete = nil }
        } message: { folder in
            Text(L(.folder_delete_msg, folder.name))
        }
        .task(id: appState.currentServer?.id) {
            if let client = appState.client { await vm.load(client: client) }
        }
        .task(id: dynamicEvaluationKey) {
            await refreshDynamicPlaylists()
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

    private var visibleFolders: [PlaylistFolder] {
        let folders = folderStore.folders.sorted { $0.createdAt < $1.createdAt }
        guard !vm.searchText.isEmpty else { return folders }
        return folders.filter { $0.name.localizedCaseInsensitiveContains(vm.searchText) }
    }

    private var rootPlaylists: [Playlist] {
        vm.filtered.filter { vm.searchText.isEmpty ? !folderStore.containsPlaylist(id: $0.id) : true }
    }

    private var rootSmartPlaylists: [SmartPlaylist] {
        filteredSmartPlaylists.filter { vm.searchText.isEmpty ? !folderStore.containsSmartPlaylist(id: $0.id) : true }
    }

    private var smartPlaylistSourceSongs: [Song] {
        vm.smartSourceSongs
    }

    private var dynamicEvaluationKey: SmartPlaylistEvaluationKey {
        SmartPlaylistEvaluationKey(
            playlists: smartStore.playlists,
            sourceRevision: vm.smartSourceRevision,
            tasteRevision: tasteStore.revision,
            downloadedRevision: downloadService.downloadedRevision
        )
    }

    private func refreshDynamicPlaylists() async {
        await dynamicResults.refresh(
            playlists: smartStore.playlists,
            librarySongs: vm.smartSourceSongs,
            downloadedSongs: downloadService.downloadedSongs(),
            context: SmartPlaylistEvaluationContext(
                lovedIDs: tasteStore.lovedIDs,
                dislikedIDs: tasteStore.dislikedIDs,
                downloadedIDs: Set(downloadService.downloadedSongs().map(\.id))
            )
        )
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.Layout.gridSpacing) {
                ForEach(visibleFolders) { folder in
                    NavigationLink {
                        PlaylistFolderDetailView(
                            folderID: folder.id,
                            serverPlaylists: vm.playlists,
                            smartSourceSongs: smartPlaylistSourceSongs,
                            sourceRevision: vm.smartSourceRevision,
                            smartArtists: vm.smartArtists,
                            smartAlbums: vm.smartAlbums,
                            smartGenres: vm.smartGenres
                        )
                    } label: {
                        playlistFolderCard(folder)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            pendingFolderDelete = folder
                        } label: {
                            Label(L(.action_delete), systemImage: Symbols.trash)
                        }
                    }
                }

                ForEach(rootPlaylists) { pl in
                    NavigationLink(value: pl) { serverPlaylistCard(pl) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        folderActions(for: pl)
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { vm.togglePin(pl) }
                        } label: {
                            Label(vm.isPinned(pl) ? L(.playlist_unpin) : L(.playlist_pin),
                                  systemImage: vm.isPinned(pl) ? "pin.slash" : "pin")
                        }
                        Button(role: .destructive) {
                            pendingDelete = pl
                        } label: {
                            Label(L(.action_delete), systemImage: Symbols.trash)
                        }
                    }
                }
                ForEach(rootSmartPlaylists) { smart in
                    NavigationLink {
                        SmartPlaylistDetailView(
                            playlist: smart,
                            sourceSongs: smartPlaylistSourceSongs,
                            sourceRevision: vm.smartSourceRevision,
                            artists: vm.smartArtists,
                            albums: vm.smartAlbums,
                            genres: vm.smartGenres
                        )
                    } label: {
                        smartPlaylistCard(smart)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        folderActions(for: smart)
                        Button {
                            smartStore.togglePin(smart)
                        } label: {
                            Label(smart.pinned ? L(.playlist_unpin) : L(.playlist_pin),
                                  systemImage: smart.pinned ? "pin.slash" : "pin")
                        }
                        Button(role: .destructive) {
                            pendingSmartDelete = smart
                        } label: {
                            Label(L(.action_delete), systemImage: Symbols.trash)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.vertical, 12)
            .padding(.bottom, 80)
        }
    }

    private func playlistFolderCard(_ folder: PlaylistFolder) -> some View {
        let count = folder.playlistIDs.count + folder.smartPlaylistIDs.count
        return VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Layout.cardCorner, style: .continuous)
                    .fill(Theme.secondaryBackground)
                Image(systemName: "folder.fill")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(count)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.42), in: Capsule())
                            .padding(10)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.cardCorner, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )

            Text(folder.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
            Text(L(.playlists_count, count))
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func folderActions(for playlist: Playlist) -> some View {
        if !folderStore.folders.isEmpty {
            Menu(L(.folder_add_to), systemImage: "folder.badge.plus") {
                ForEach(folderStore.folders) { folder in
                    Button(folder.name) {
                        folderStore.addPlaylist(id: playlist.id, to: folder)
                    }
                }
            }
        }
        if folderStore.containsPlaylist(id: playlist.id) {
            Button {
                folderStore.removePlaylist(id: playlist.id)
            } label: {
                Label(L(.folder_remove_from), systemImage: "folder.badge.minus")
            }
        }
    }

    @ViewBuilder
    private func folderActions(for smart: SmartPlaylist) -> some View {
        if !folderStore.folders.isEmpty {
            Menu(L(.folder_add_to), systemImage: "folder.badge.plus") {
                ForEach(folderStore.folders) { folder in
                    Button(folder.name) {
                        folderStore.addSmartPlaylist(id: smart.id, to: folder)
                    }
                }
            }
        }
        if folderStore.containsSmartPlaylist(id: smart.id) {
            Button {
                folderStore.removeSmartPlaylist(id: smart.id)
            } label: {
                Label(L(.folder_remove_from), systemImage: "folder.badge.minus")
            }
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
                Text(L(.home_song_count, count))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .contentShape(Rectangle())
    }

    private func smartPlaylistCard(_ smart: SmartPlaylist) -> some View {
        let songs = dynamicResults.songs(for: smart.id)
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
            Text(L(.smart_songs_rule, songs.count, smart.ruleSummary))
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: Symbols.playlists).font(.system(size: 40, weight: .ultraLight)).foregroundStyle(Theme.secondaryText)
            Text(L(.playlists_none_yet)).font(.headline).foregroundStyle(Theme.primaryText)
        }
    }

    private var createSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L(.create_type), selection: $createKind) {
                        ForEach(PlaylistCreateKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if createKind == .custom {
                    Section {
                        TextField(L(.create_playlist_name_ph), text: $vm.newPlaylistName)
                        if customPlaylistIsDynamic {
                            TextField(L(.smart_desc), text: Binding(
                                get: { smartDraft.subtitle ?? "" },
                                set: { smartDraft.subtitle = $0.isEmpty ? nil : $0 }
                            ))
                        }
                    }
                    Section("Playlist Options") {
                        Toggle("Dynamic Playlist", isOn: $customPlaylistIsDynamic)
                        if customPlaylistIsDynamic {
                            Text("Keep this custom playlist updated when your library, downloads, or taste changes.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if customPlaylistIsDynamic {
                        dynamicCustomPlaylistForm
                    }
                } else if createKind == .folder {
                    Section {
                        TextField(L(.create_folder_name_ph), text: $vm.newPlaylistName)
                    }
                } else {
                    smartPlaylistForm
                }
            }
            .navigationTitle(L(.create_new_playlist_title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L(.action_cancel)) { closeCreateSheet() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L(.action_create)) {
                        createCurrentDraft()
                    }
                    .disabled(createDisabled)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            resetCreateDrafts()
        }
        .task(id: smartPreviewEvaluationKey) {
            guard createKind == .smart || (createKind == .custom && customPlaylistIsDynamic) else { return }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let draft = playlistRuleDraftForCurrentKind()
            let downloaded = downloadService.downloadedSongs()
            await previewResults.refresh(
                playlists: [draft],
                librarySongs: vm.smartSourceSongs,
                downloadedSongs: downloaded,
                context: SmartPlaylistEvaluationContext(
                    lovedIDs: tasteStore.lovedIDs,
                    dislikedIDs: tasteStore.dislikedIDs,
                    downloadedIDs: Set(downloaded.map(\.id))
                )
            )
        }
        .alert(L(.name_exists_title), isPresented: Binding(
            get: { duplicateCreateMessage != nil },
            set: { if !$0 { duplicateCreateMessage = nil } }
        )) {
            Button(L(.action_ok), role: .cancel) { duplicateCreateMessage = nil }
        } message: {
            Text(duplicateCreateMessage ?? "")
        }
    }

    private var createDisabled: Bool {
        switch createKind {
        case .custom:
            return vm.newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty
                || (!customPlaylistIsDynamic && vm.isCreating)
        case .folder:
            return vm.newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty
        case .smart:
            return smartDraft.name.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var smartPlaylistForm: some View {
        SmartPlaylistEditorSections(
            draft: $smartDraft,
            minYearText: $minYearText,
            maxYearText: $maxYearText,
            minPlayText: $minPlayText,
            maxPlayText: $maxPlayText,
            artists: vm.smartArtists,
            albums: vm.smartAlbums,
            genres: vm.smartGenres,
            previewCount: smartPreviewCount,
            includesIdentitySection: true
        )
    }

    private var dynamicCustomPlaylistForm: some View {
        SmartPlaylistEditorSections(
            draft: $smartDraft,
            minYearText: $minYearText,
            maxYearText: $maxYearText,
            minPlayText: $minPlayText,
            maxPlayText: $maxPlayText,
            artists: vm.smartArtists,
            albums: vm.smartAlbums,
            genres: vm.smartGenres,
            previewCount: smartPreviewCount,
            includesIdentitySection: false
        )
    }

    private var smartPreviewCount: Int {
        previewResults.songs(for: smartDraft.id).count
    }

    private var smartPreviewEvaluationKey: SmartPlaylistEvaluationKey {
        SmartPlaylistEvaluationKey(
            playlists: createKind == .smart || (createKind == .custom && customPlaylistIsDynamic)
                ? [playlistRuleDraftForCurrentKind()]
                : [],
            sourceRevision: vm.smartSourceRevision,
            tasteRevision: tasteStore.revision,
            downloadedRevision: downloadService.downloadedRevision
        )
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

    private func createCustomDynamicPlaylist() {
        var draft = smartDraftWithNumbers()
        draft.name = vm.newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        smartStore.upsert(draft)
        closeCreateSheet()
    }

    private func playlistRuleDraftForCurrentKind() -> SmartPlaylist {
        var draft = smartDraftWithNumbers()
        if createKind == .custom {
            draft.name = vm.newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return draft
    }

    private func createCurrentDraft() {
        if let message = duplicateMessageForCurrentDraft() {
            duplicateCreateMessage = message
            return
        }
        if createKind == .custom {
            if customPlaylistIsDynamic {
                createCustomDynamicPlaylist()
            } else if let client = appState.client {
                Task { await vm.createPlaylist(client: client) }
            }
        } else if createKind == .folder {
            folderStore.create(name: vm.newPlaylistName)
            closeCreateSheet()
        } else {
            createSmartPlaylist()
        }
    }

    private func duplicateMessageForCurrentDraft() -> String? {
        switch createKind {
        case .custom:
            let name = normalizedCreateName(vm.newPlaylistName)
            if customPlaylistIsDynamic {
                guard smartStore.playlists.contains(where: { normalizedCreateName($0.name) == name }) else { return nil }
                return L(.dup_smart, vm.newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                guard vm.playlists.contains(where: { normalizedCreateName($0.name) == name }) else { return nil }
                return L(.dup_playlist, vm.newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        case .smart:
            let name = normalizedCreateName(smartDraft.name)
            guard smartStore.playlists.contains(where: { normalizedCreateName($0.name) == name }) else { return nil }
            return L(.dup_smart, smartDraft.name.trimmingCharacters(in: .whitespacesAndNewlines))
        case .folder:
            let name = normalizedCreateName(vm.newPlaylistName)
            guard folderStore.folders.contains(where: { normalizedCreateName($0.name) == name }) else { return nil }
            return L(.dup_folder, vm.newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func normalizedCreateName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func closeCreateSheet() {
        vm.showCreateSheet = false
        resetCreateDrafts()
    }

    private func resetCreateDrafts() {
        createKind = .custom
        customPlaylistIsDynamic = false
        vm.newPlaylistName = ""
        smartDraft = SmartPlaylist(name: "")
        minYearText = ""
        maxYearText = ""
        minPlayText = ""
        maxPlayText = ""
    }
}

private struct PlaylistFolderDetailView: View {
    let folderID: String
    let serverPlaylists: [Playlist]
    let smartSourceSongs: [Song]
    let sourceRevision: Int
    let smartArtists: [String]
    let smartAlbums: [String]
    let smartGenres: [String]

    @StateObject private var folderStore = PlaylistFolderStore.shared
    @StateObject private var smartStore = SmartPlaylistStore.shared
    @StateObject private var downloadService = DownloadService.shared
    @StateObject private var tasteStore = TasteStore.shared
    @StateObject private var dynamicResults = SmartPlaylistResults()

    private let columns = [GridItem(.flexible(), spacing: Theme.Layout.gridSpacing),
                           GridItem(.flexible(), spacing: Theme.Layout.gridSpacing)]

    private var folder: PlaylistFolder? {
        folderStore.folder(id: folderID)
    }

    private var containedPlaylists: [Playlist] {
        guard let folder else { return [] }
        return folder.playlistIDs.compactMap { id in
            serverPlaylists.first { $0.id == id }
        }
    }

    private var containedSmartPlaylists: [SmartPlaylist] {
        guard let folder else { return [] }
        return folder.smartPlaylistIDs.compactMap { id in
            smartStore.playlists.first { $0.id == id }
        }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if containedPlaylists.isEmpty && containedSmartPlaylists.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 40, weight: .ultraLight))
                        .foregroundStyle(Theme.secondaryText)
                    Text(L(.folder_empty))
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Theme.Layout.gridSpacing) {
                        ForEach(containedPlaylists) { playlist in
                            NavigationLink {
                                PlaylistDetailView(playlist: playlist)
                            } label: {
                                folderPlaylistCard(playlist)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    folderStore.removePlaylist(id: playlist.id)
                                } label: {
                                    Label(L(.folder_remove_from), systemImage: "folder.badge.minus")
                                }
                            }
                        }

                        ForEach(containedSmartPlaylists) { smart in
                            NavigationLink {
                                SmartPlaylistDetailView(
                                    playlist: smart,
                                    sourceSongs: smartSourceSongs,
                                    sourceRevision: sourceRevision,
                                    artists: smartArtists,
                                    albums: smartAlbums,
                                    genres: smartGenres
                                )
                            } label: {
                                folderSmartCard(smart)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    folderStore.removeSmartPlaylist(id: smart.id)
                                } label: {
                                    Label(L(.folder_remove_from), systemImage: "folder.badge.minus")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Layout.screenPadding)
                    .padding(.vertical, 12)
                    .padding(.bottom, 90)
                }
            }
        }
        .navigationTitle(folder?.name ?? L(.media_folder))
        .navigationBarTitleDisplayMode(.large)
        .preferredColorScheme(Theme.colorScheme)
        .task(id: evaluationKey) {
            let downloaded = downloadService.downloadedSongs()
            await dynamicResults.refresh(
                playlists: containedSmartPlaylists,
                librarySongs: smartSourceSongs,
                downloadedSongs: downloaded,
                context: SmartPlaylistEvaluationContext(
                    lovedIDs: tasteStore.lovedIDs,
                    dislikedIDs: tasteStore.dislikedIDs,
                    downloadedIDs: Set(downloaded.map(\.id))
                )
            )
        }
    }

    private func folderPlaylistCard(_ playlist: Playlist) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PlaylistCover(playlist: playlist, size: 400)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
            Text(playlist.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
            if let count = playlist.songCount {
                Text(L(.home_song_count, count))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .contentShape(Rectangle())
    }

    private func folderSmartCard(_ smart: SmartPlaylist) -> some View {
        let songs = dynamicResults.songs(for: smart.id)
        return VStack(alignment: .leading, spacing: 6) {
            SmartPlaylistCover(songs: songs)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
            Text(smart.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
            Text(L(.home_song_count, songs.count))
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .contentShape(Rectangle())
    }

    private var evaluationKey: SmartPlaylistEvaluationKey {
        SmartPlaylistEvaluationKey(
            playlists: containedSmartPlaylists,
            sourceRevision: sourceRevision,
            tasteRevision: tasteStore.revision,
            downloadedRevision: downloadService.downloadedRevision
        )
    }
}

private struct SmartPlaylistCover: View {
    let songs: [Song]

    var body: some View {
        let coverSongs = Array(songs.lazy.filter { $0.coverArt != nil }.prefix(4))
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
                            Label(L(.action_clear_selection), systemImage: "xmark.circle")
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
            .searchable(text: $searchText, prompt: L(.search_x, title.lowercased()))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L(.action_done)) { dismiss() }
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

/// The rule fields shared by smart-playlist creation and editing. Keeping the
/// numeric values as text here lets both callers preserve an unset value as
/// `nil` until they save the draft.
private struct SmartPlaylistEditorSections: View {
    @Binding var draft: SmartPlaylist
    @Binding var minYearText: String
    @Binding var maxYearText: String
    @Binding var minPlayText: String
    @Binding var maxPlayText: String

    let artists: [String]
    let albums: [String]
    let genres: [String]
    let previewCount: Int
    let includesIdentitySection: Bool

    @State private var showArtistPicker = false
    @State private var showAlbumPicker = false

    var body: some View {
        Group {
            if includesIdentitySection {
                Section(L(.sort_name)) {
                    TextField(L(.smart_name_ph), text: $draft.name)
                    TextField(L(.smart_desc), text: subtitle)
                }
            }

            Section(L(.smart_section_rules)) {
                Picker(L(.smart_match), selection: $draft.matchMode) {
                    ForEach(SmartMatchMode.allCases) { Text($0.label).tag($0) }
                }
                TextField(L(.smart_search_ph), text: $draft.searchText)
                TextField(L(.smart_artist_ph), text: $draft.artist)
                TextField(L(.smart_album_ph), text: $draft.album)
                Button { showArtistPicker = true } label: {
                    selectionRow(L(.home_artists), values: draft.selectedArtists)
                }
                Button { showAlbumPicker = true } label: {
                    selectionRow(L(.media_albums), values: draft.selectedAlbums)
                }
                Picker(L(.media_genre), selection: $draft.genre) {
                    Text(L(.smart_any_genre)).tag("")
                    ForEach(genres, id: \.self) { Text($0).tag($0) }
                }
            }

            Section(L(.smart_section_filters)) {
                TextField(L(.smart_min_year_ph), text: $minYearText)
                    .keyboardType(.numberPad)
                TextField(L(.smart_max_year_ph), text: $maxYearText)
                    .keyboardType(.numberPad)
                TextField(L(.smart_min_plays_ph), text: $minPlayText)
                    .keyboardType(.numberPad)
                TextField(L(.smart_max_plays_ph), text: $maxPlayText)
                    .keyboardType(.numberPad)
                Toggle(L(.smart_never_played_only), isOn: $draft.neverPlayedOnly)
                Toggle(L(.smart_lossless_only), isOn: $draft.onlyLossless)
                    .onChangeCompat(of: draft.onlyLossless) { _, enabled in
                        if !enabled { draft.onlyHiResLossless = false }
                    }
                Toggle(L(.smart_hires_only), isOn: $draft.onlyHiResLossless)
                    .onChangeCompat(of: draft.onlyHiResLossless) { _, enabled in
                        if enabled { draft.onlyLossless = true }
                    }
                .disabled(!draft.onlyLossless)
                Toggle(L(.smart_downloaded_only), isOn: $draft.onlyDownloaded)
                Picker(L(.smart_taste), selection: $draft.taste) {
                    ForEach(SmartTasteFilter.allCases) { Text($0.label).tag($0) }
                }
            }

            Section(L(.smart_section_mix)) {
                Picker(L(.smart_sort), selection: $draft.sort) {
                    ForEach(SmartSortMode.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Limit Number of Songs", isOn: limitEnabled)
                if draft.limit > 0 {
                    Stepper(L(.smart_limit, draft.limit), value: $draft.limit, in: 5...50_000, step: 5)
                }
                Text(L(.smart_matching_now, previewCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showArtistPicker) {
            SmartMultiSelectSheet(
                title: L(.home_artists),
                options: artists,
                selection: $draft.selectedArtists
            )
        }
        .sheet(isPresented: $showAlbumPicker) {
            SmartMultiSelectSheet(
                title: L(.media_albums),
                options: albums,
                selection: $draft.selectedAlbums
            )
        }
    }

    private var subtitle: Binding<String> {
        Binding(
            get: { draft.subtitle ?? "" },
            set: { draft.subtitle = $0.isEmpty ? nil : $0 }
        )
    }

    private var limitEnabled: Binding<Bool> {
        Binding(
            get: { draft.limit > 0 },
            set: { draft.limit = $0 ? max(50, draft.limit) : 0 }
        )
    }

    private func selectionRow(_ title: String, values: [String]) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(values.isEmpty ? L(.smart_any) : L(.smart_n_selected, values.count))
                .foregroundStyle(.secondary)
            Image(systemName: Symbols.chevron)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SmartPlaylistEditorSheet: View {
    let sourceSongs: [Song]
    let sourceRevision: Int
    let artists: [String]
    let albums: [String]
    let genres: [String]
    let existingPlaylists: [SmartPlaylist]
    let onSave: (SmartPlaylist) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var downloadService = DownloadService.shared
    @StateObject private var tasteStore = TasteStore.shared
    @StateObject private var previewResults = SmartPlaylistResults()
    @State private var draft: SmartPlaylist
    @State private var minYearText: String
    @State private var maxYearText: String
    @State private var minPlayText: String
    @State private var maxPlayText: String
    @State private var duplicateNameMessage: String?

    init(
        playlist: SmartPlaylist,
        sourceSongs: [Song],
        sourceRevision: Int,
        artists: [String],
        albums: [String],
        genres: [String],
        existingPlaylists: [SmartPlaylist],
        onSave: @escaping (SmartPlaylist) -> Void
    ) {
        var initialDraft = playlist
        // Older saved drafts did not have an editor enforcing these invariants.
        // Normalize only the editable representation, keeping all user rules.
        if initialDraft.onlyHiResLossless {
            initialDraft.onlyLossless = true
        }
        if initialDraft.limit > 0 {
            initialDraft.limit = min(50_000, max(5, initialDraft.limit))
        }

        self.sourceSongs = sourceSongs
        self.sourceRevision = sourceRevision
        self.artists = artists
        self.albums = albums
        self.genres = genres
        self.existingPlaylists = existingPlaylists
        self.onSave = onSave
        _draft = State(initialValue: initialDraft)
        _minYearText = State(initialValue: Self.numberText(initialDraft.minYear))
        _maxYearText = State(initialValue: Self.numberText(initialDraft.maxYear))
        _minPlayText = State(initialValue: Self.numberText(initialDraft.minPlayCount))
        _maxPlayText = State(initialValue: Self.numberText(initialDraft.maxPlayCount))
    }

    var body: some View {
        NavigationStack {
            Form {
                SmartPlaylistEditorSections(
                    draft: $draft,
                    minYearText: $minYearText,
                    maxYearText: $maxYearText,
                    minPlayText: $minPlayText,
                    maxPlayText: $maxPlayText,
                    artists: artists,
                    albums: albums,
                    genres: genres,
                    previewCount: previewCount,
                    includesIdentitySection: true
                )
            }
            .navigationTitle(L(.playlist_edit_title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L(.action_cancel)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L(.action_save)) { save() }
                        .disabled(normalizedName.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task(id: previewEvaluationKey) {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let value = normalizedDraft
            let downloaded = downloadService.downloadedSongs()
            await previewResults.refresh(
                playlists: [value],
                librarySongs: sourceSongs,
                downloadedSongs: downloaded,
                context: SmartPlaylistEvaluationContext(
                    lovedIDs: tasteStore.lovedIDs,
                    dislikedIDs: tasteStore.dislikedIDs,
                    downloadedIDs: Set(downloaded.map(\.id))
                )
            )
        }
        .alert(L(.name_exists_title), isPresented: Binding(
            get: { duplicateNameMessage != nil },
            set: { if !$0 { duplicateNameMessage = nil } }
        )) {
            Button(L(.action_ok), role: .cancel) { duplicateNameMessage = nil }
        } message: {
            Text(duplicateNameMessage ?? "")
        }
    }

    private var previewCount: Int {
        previewResults.songs(for: draft.id).count
    }

    private var previewEvaluationKey: SmartPlaylistEvaluationKey {
        SmartPlaylistEvaluationKey(
            playlists: [normalizedDraft],
            sourceRevision: sourceRevision,
            tasteRevision: tasteStore.revision,
            downloadedRevision: downloadService.downloadedRevision
        )
    }

    private var normalizedName: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedDraft: SmartPlaylist {
        var value = draft
        value.name = normalizedName
        let trimmedSubtitle = (value.subtitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        value.subtitle = trimmedSubtitle.isEmpty ? nil : trimmedSubtitle
        value.minYear = Int(minYearText.trimmingCharacters(in: .whitespaces))
        value.maxYear = Int(maxYearText.trimmingCharacters(in: .whitespaces))
        value.minPlayCount = Int(minPlayText.trimmingCharacters(in: .whitespaces))
        value.maxPlayCount = Int(maxPlayText.trimmingCharacters(in: .whitespaces))
        return value
    }

    private func save() {
        let value = normalizedDraft
        guard !value.name.isEmpty else { return }
        if existingPlaylists.contains(where: {
            $0.id != value.id && normalized($0.name) == normalized(value.name)
        }) {
            duplicateNameMessage = L(.dup_smart, value.name)
            return
        }
        onSave(value)
        dismiss()
    }

    private func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func numberText(_ number: Int?) -> String {
        number.map { String($0) } ?? ""
    }
}

private struct SmartPlaylistDetailView: View {
    let playlist: SmartPlaylist
    let sourceSongs: [Song]
    let sourceRevision: Int
    let artists: [String]
    let albums: [String]
    let genres: [String]

    @EnvironmentObject private var appState: AppState
    @StateObject private var smartStore = SmartPlaylistStore.shared
    @StateObject private var downloadService = DownloadService.shared
    @StateObject private var tasteStore = TasteStore.shared
    @StateObject private var dynamicResults = SmartPlaylistResults()
    @State private var activeSheet: PlaylistSheet? = nil
    @State private var editingPlaylist: SmartPlaylist?
    @State private var toastMessage: String?
    @AppStorage("showTrackArtwork") private var showTrackArtwork = true

    // The navigation value is a snapshot. Resolve it through the store so this
    // screen refreshes immediately after an offline edit is saved.
    private var currentPlaylist: SmartPlaylist {
        smartStore.playlists.first(where: { $0.id == playlist.id }) ?? playlist
    }

    private var songs: [Song] {
        dynamicResults.songs(for: currentPlaylist.id)
    }

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
        .preferredColorScheme(Theme.colorScheme)
        .background(SwipeBackEnabler())
        .task(id: evaluationKey) {
            let downloaded = downloadService.downloadedSongs()
            await dynamicResults.refresh(
                playlists: [currentPlaylist],
                librarySongs: sourceSongs,
                downloadedSongs: downloaded,
                context: SmartPlaylistEvaluationContext(
                    lovedIDs: tasteStore.lovedIDs,
                    dislikedIDs: tasteStore.dislikedIDs,
                    downloadedIDs: Set(downloaded.map(\.id))
                )
            )
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addToPlaylist(let song):
                AddToPlaylistSheet(song: song, onAdded: { name in showToast(L(.toast_added_to, name)) })
            case .album(let album):
                NavigationStack {
                    AlbumDetailView(album: album)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(L(.action_done)) { activeSheet = nil }.foregroundStyle(Theme.accent)
                            }
                        }
                }
                .preferredColorScheme(Theme.colorScheme)
            case .artist(let artist):
                NavigationStack {
                    ArtistDetailView(artist: artist)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(L(.action_done)) { activeSheet = nil }.foregroundStyle(Theme.accent)
                            }
                        }
                }
                .preferredColorScheme(Theme.colorScheme)
            case .edit:
                EmptyView()
            case .reorder:
                EmptyView()
            }
        }
        .sheet(item: $editingPlaylist) { playlist in
            SmartPlaylistEditorSheet(
                playlist: playlist,
                sourceSongs: sourceSongs,
                sourceRevision: sourceRevision,
                artists: artists,
                albums: albums,
                genres: genres,
                existingPlaylists: smartStore.playlists
            ) { updated in
                smartStore.upsert(updated)
            }
        }
    }

    private var evaluationKey: SmartPlaylistEvaluationKey {
        SmartPlaylistEvaluationKey(
            playlists: [currentPlaylist],
            sourceRevision: sourceRevision,
            tasteRevision: tasteStore.revision,
            downloadedRevision: downloadService.downloadedRevision
        )
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
            HStack(spacing: 10) {
                Text(currentPlaylist.name)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Button { editingPlaylist = currentPlaylist } label: {
                    Image(systemName: Symbols.edit)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .glassCircle()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L(.playlist_edit_title))
            }
            Text(currentPlaylist.subtitle?.isEmpty == false ? currentPlaylist.subtitle! : currentPlaylist.ruleSummary)
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
                    appState.audioPlayer.playQueue(shuffled, startIndex: 0, source: currentPlaylist.name)
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
                    appState.audioPlayer.playQueue(songs, startIndex: 0, source: currentPlaylist.name)
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: Symbols.play).font(.system(size: 14, weight: .bold))
                    Text(L(.action_play)).font(.subheadline.weight(.semibold))
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
        LazyVStack(spacing: 0) {
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
                        appState.audioPlayer.playQueue(songs, startIndex: i, source: currentPlaylist.name)
                    },
                    showArtist: true,
                    leadingArtwork: showTrackArtwork,
                    onSwipePlayNext: {
                        appState.audioPlayer.playNext(song)
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
        .overlay(alignment: .leading) { playbackSwipeGutter }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L(.home_song_count, songs.count))
            Text("\(currentPlaylist.matchMode.label) · \(currentPlaylist.sort.label)")
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

    private var playbackSwipeGutter: some View {
        Color.clear
            .frame(width: 56)
            .contentShape(Rectangle())
            .gesture(verticalPlaybackSwipe)
    }

    private func moveWithinSmartPlaylist(delta: Int) {
        let list = songs
        guard let current = appState.audioPlayer.currentSong,
              let currentIndex = list.firstIndex(where: { $0.id == current.id }) else { return }
        let nextIndex = max(0, min(list.count - 1, currentIndex + delta))
        guard nextIndex != currentIndex else { return }
        appState.audioPlayer.playQueue(list, startIndex: nextIndex, source: currentPlaylist.name)
    }
}
