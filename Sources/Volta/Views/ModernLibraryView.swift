import SwiftUI
import UIKit

enum LibraryDesign: String, CaseIterable, Identifiable, Hashable {
    case modern
    case legacy

    static let storageKey = "libraryDesign"
    var id: String { rawValue }

    @MainActor
    var settingsLabel: String {
        switch self {
        case .modern: return "Modern"
        case .legacy: return "Legacy"
        }
    }
}

/// Only sections Volta can display. Deliberately excludes Music Videos, TV &
/// Movies, Playlists, Compilations, Composers, and Genres.
enum ModernLibrarySection: String, CaseIterable, Identifiable, Hashable {
    case artists
    case albums
    case songs
    case downloaded
    case madeForYou
    case folders

    static let storageKey = "modernLibrarySections"
    static let downloadedStorageKey = "modernDownloadedLibrarySections"
    static let defaults: [ModernLibrarySection] = [.artists, .albums, .songs]
    static let downloadedDefaults: [ModernLibrarySection] = [.artists, .albums, .songs, .folders]

    var id: String { rawValue }

    @MainActor
    var title: String {
        switch self {
        case .artists: return L(.home_artists)
        case .albums: return L(.media_albums)
        case .songs: return L(.media_songs)
        case .downloaded: return "Downloaded"
        case .madeForYou: return "Made for You"
        case .folders: return L(.library_folders)
        }
    }

    var icon: String {
        switch self {
        case .artists: return "music.mic"
        case .albums: return "square.stack"
        case .songs: return "music.note"
        case .downloaded: return Symbols.downloaded
        case .madeForYou: return "person.crop.rectangle"
        case .folders: return "folder"
        }
    }

    static func decode(
        _ stored: String,
        defaults fallback: [ModernLibrarySection] = ModernLibrarySection.defaults
    ) -> [ModernLibrarySection] {
        if stored == "none" { return [] }
        let values = stored
            .split(separator: ",")
            .compactMap { ModernLibrarySection(rawValue: String($0)) }
            .filter { $0 != .downloaded }
        return values.isEmpty ? fallback : values
    }

    static func encode(_ sections: [ModernLibrarySection]) -> String {
        sections.isEmpty ? "none" : sections.map(\.rawValue).joined(separator: ",")
    }
}

enum ModernLibraryDestination: Hashable {
    case collection(ModernLibraryCollection, LibrarySource)
}

enum ModernLibraryCollection: String, Hashable {
    case artists
    case albums
    case songs
    case downloads

    @MainActor
    var title: String {
        switch self {
        case .artists: return L(.home_artists)
        case .albums: return L(.media_albums)
        case .songs: return L(.media_songs)
        case .downloads: return "Downloaded"
        }
    }
}

/// Routes one public Library tab to either preserved legacy UI or redesigned UI.
struct LibraryView: View {
    @AppStorage(LibraryDesign.storageKey) private var designRaw = ""
    @Binding var path: NavigationPath
    /// TabView retains inactive tab roots. Pass the selection through so the
    /// modern library can release its artwork-heavy hierarchy while hidden.
    var isTabActive = true
    @State private var showDesignPicker = false

    private var design: LibraryDesign? { LibraryDesign(rawValue: designRaw) }

    var body: some View {
        Group {
            switch design {
            case .legacy:
                LegacyLibraryView(path: $path)
            case .modern, .none:
                ModernLibraryView(path: $path, isTabActive: isTabActive)
            }
        }
        .onAppear {
            showDesignPicker = design == nil
        }
        .fullScreenCover(isPresented: $showDesignPicker) {
            LibraryDesignPicker { design in
                designRaw = design.rawValue
                showDesignPicker = false
            }
            .interactiveDismissDisabled()
        }
    }
}

private struct LibraryDesignPicker: View {
    let choose: (LibraryDesign) -> Void
    @State private var previewDesign: LibraryDesign?
    @State private var previewPath = NavigationPath()

    var body: some View {
        if let previewDesign {
            preview(for: previewDesign)
        } else {
            designChoices
        }
    }

    private var designChoices: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Spacer(minLength: 24)
                    Text("Choose Your Library")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.primaryText)
                    Text("You can change this later in Settings.")
                        .foregroundStyle(Theme.secondaryText)

                    designCard(
                        .modern,
                        subtitle: "Apple Music-inspired pins, sections, and recent additions."
                    )
                    designCard(
                        .legacy,
                        subtitle: "Current Library filters, source picker, and saved views."
                    )
                }
                .padding(.horizontal, Theme.Layout.screenPadding)
                .padding(.bottom, 36)
            }
        }
        .preferredColorScheme(Theme.colorScheme)
    }

    private func designCard(
        _ design: LibraryDesign,
        subtitle: String
    ) -> some View {
        Button {
            previewPath = NavigationPath()
            previewDesign = design
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                LibraryDesignThumbnail(design: design)
                    .frame(height: 128)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(design.settingsLabel)
                        .font(.title3.bold())
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Theme.primaryText)
            .padding(14)
            .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func preview(for design: LibraryDesign) -> some View {
        ZStack {
            switch design {
            case .modern:
                ModernLibraryView(path: $previewPath, isTabActive: true)
            case .legacy:
                LegacyLibraryView(path: $previewPath)
            }

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(.orange, lineWidth: 4)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack {
                Text("PREVIEW")
                    .font(.caption.bold())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.orange, in: Capsule())
                    .padding(.top, 8)
                Spacer()
            }
            .allowsHitTesting(false)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 8) {
                ForEach(LibraryDesign.allCases) { option in
                    Button(option.settingsLabel) {
                        previewPath = NavigationPath()
                        previewDesign = option
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(option == design ? .black : .orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(option == design ? .orange : Color.clear, in: Capsule())
                }
                Spacer()
                Button("Use \(design.settingsLabel)") {
                    choose(design)
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.orange, in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.88))
        }
    }
}

private struct LibraryDesignThumbnail: View {
    let design: LibraryDesign

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Library")
                .font(.title3.bold())
            if design == .modern {
                HStack(spacing: 7) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Theme.accent.opacity(0.6))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
                ForEach(["Artists", "Albums"], id: \.self) { title in
                    HStack {
                        Image(systemName: "music.note").foregroundStyle(Theme.accent)
                        Text(title)
                        Spacer()
                        Image(systemName: Symbols.chevron)
                    }
                    .font(.caption)
                }
            } else {
                HStack(spacing: 6) {
                    Text("Server")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.accent, in: Capsule())
                    Text("Downloaded")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.secondaryBackground, in: Capsule())
                }
                .font(.caption2.weight(.semibold))
                HStack(spacing: 5) {
                    ForEach(["Artists", "Albums", "Songs"], id: \.self) { title in
                        Text(title)
                            .padding(5)
                            .background(Theme.secondaryBackground, in: Capsule())
                    }
                }
                .font(.caption2)
                RoundedRectangle(cornerRadius: 6).fill(Theme.secondaryBackground).frame(height: 20)
            }
        }
        .foregroundStyle(Theme.primaryText)
        .padding(12)
        .background(.black)
    }
}

struct ModernLibraryView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = LibraryViewModel()
    @StateObject private var downloadService = DownloadService.shared
    @AppStorage(ModernLibrarySection.storageKey) private var sectionsRaw = ""
    @AppStorage(ModernLibrarySection.downloadedStorageKey) private var downloadedSectionsRaw = ""
    @StateObject private var pinnedLibrary = PinnedLibraryStore.shared
    @Binding var path: NavigationPath
    /// Unlike navigation pushes, TabView preserves inactive tab contents.
    /// Keeping the recent-artwork shelf mounted left placeholder shimmers and
    /// image work alive after visiting Library, reducing player animation FPS.
    let isTabActive: Bool
    @Namespace private var heroNamespace
    @State private var showSectionEditor = false
    @State private var playlists: [Playlist] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
#if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
#endif

    private var recentColumns: [GridItem] {
        let count: Int
#if os(iOS)
        count = verticalSizeClass == .compact ? 4 : 2
#else
        count = 2
#endif
        return Array(repeating: GridItem(.flexible(), spacing: Theme.Layout.gridSpacing), count: count)
    }

    private var enabledSections: [ModernLibrarySection] {
        if isShowingDownloads {
            return ModernLibrarySection.decode(
                downloadedSectionsRaw,
                defaults: ModernLibrarySection.downloadedDefaults
            )
        }
        return ModernLibrarySection.decode(sectionsRaw)
    }

    private var pinnedAlbums: [Album] {
        vm.filteredAlbums.filter { pinnedLibrary.isPinned($0) }
    }

    private var pinnedPlaylists: [Playlist] {
        playlists.filter { pinnedLibrary.isPinned($0) }
    }

    private var pinnedItems: [ModernLibraryPinnedItem] {
        pinnedAlbums.map(ModernLibraryPinnedItem.album)
            + pinnedPlaylists.map(ModernLibraryPinnedItem.playlist)
    }
    private var isDownloadOnly: Bool {
        appState.isOfflineMode || appState.client == nil
    }

    private var isShowingDownloads: Bool {
        isDownloadOnly || vm.source == .downloaded
    }

    private var contentTransitionAnimation: Animation {
        reduceMotion || PerformanceMode.reduceAnimations
            ? .linear(duration: 0.01)
            : .easeInOut(duration: 0.22)
    }

    private var libraryContentKey: String {
        vm.isLoading && !vm.hasLoaded
            ? "loading"
            : "content-\(isShowingDownloads)"
    }

    private var recentItems: [ModernLibraryRecentItem] {
        if isShowingDownloads {
            return recentDownloadedAlbums(
                from: downloadService.downloadedSongsByDownloadDate(),
                matching: vm.filteredAlbums
            )
                .map { .album($0, .distantPast) }
        }
        let albums = vm.filteredAlbums.compactMap { album -> ModernLibraryRecentItem? in
            guard let date = album.createdDate else { return nil }
            return .album(album, date)
        }
        let playlistItems = playlists.compactMap { playlist -> ModernLibraryRecentItem? in
            guard let date = PlaylistOfflineCache.shared.recentDate(
                for: playlist,
                serverID: appState.currentServer?.id
            ) else { return nil }
            return .playlist(playlist, date)
        }
        return Array((albums + playlistItems).sorted { $0.date > $1.date }.prefix(30))
    }

    var body: some View {
        Group {
            if isTabActive {
                NavigationStack(path: $path) {
                    ZStack {
                        Theme.background.ignoresSafeArea()
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                Group {
                                    if vm.isLoading && !vm.hasLoaded {
                                        ProgressView()
                                            .controlSize(.large)
                                            .tint(Theme.accent)
                                            .frame(maxWidth: .infinity, minHeight: 260)
                                    } else {
                                        libraryBody
                                    }
                                }
                                .id(libraryContentKey)
                                .transition(.opacity)
                                .animation(contentTransitionAnimation, value: libraryContentKey)
                            }
                            .padding(.bottom, 96)
                        }
                        .scrollIndicators(.hidden)
                    }
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(for: LibraryRoute.self) { route in
                        destination(for: route)
                    }
                    .navigationDestination(for: ModernLibraryDestination.self) { destination in
                        switch destination {
                        case .collection(let collection, let source):
                            ModernLibraryCollectionView(
                                collection: collection,
                                source: source,
                                path: $path,
                                sectionsRaw: $downloadedSectionsRaw
                            )
                        }
                    }
                    .sheet(isPresented: $showSectionEditor) {
                        ModernLibrarySectionEditor(
                            sectionsRaw: isShowingDownloads ? $downloadedSectionsRaw : $sectionsRaw,
                            defaults: isShowingDownloads ? ModernLibrarySection.downloadedDefaults : ModernLibrarySection.defaults,
                            excludesDownloaded: isShowingDownloads
                        )
                    }
                    .environment(\.heroNamespace, heroNamespace)
                    .settingsDestinations()
                }
                .tint(Theme.accent)
                .preferredColorScheme(Theme.colorScheme)
                .task(id: "\(appState.currentServer?.id ?? "none")|\(appState.isOfflineMode)") {
                    await loadLibrary()
                }
            } else {
                // Do not leave a retained ScrollView full of image placeholders
                // (and their repeat-forever shimmers) competing with the player.
                Color.clear
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var libraryBody: some View {
        HStack(spacing: 10) {
            Text(L(.tab_library))
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 8)
            libraryOptionsButton
            ServerMenuButton(onOpenSettings: { path.append(SettingsRoute.root) })
        }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.top, 14)
            .padding(.bottom, 22)

        if !pinnedItems.isEmpty {
            Text("Pinned")
                .font(.title2.bold())
                .foregroundStyle(Theme.primaryText)
                .padding(.horizontal, Theme.Layout.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(pinnedItems) { item in
                        pinnedCard(item)
                    }
                }
                .padding(.horizontal, Theme.Layout.screenPadding)
            }
            .frame(height: 190)
            .padding(.bottom, 14)
        }

        VStack(spacing: 0) {
            ForEach(enabledSections) { section in
                sectionRow(section)
                if section != enabledSections.last {
                    Divider()
                        .background(Theme.secondaryText.opacity(0.16))
                        .padding(.leading, 56)
                }
            }
        }
        .padding(.horizontal, Theme.Layout.screenPadding)

        if !recentItems.isEmpty {
            Text(isShowingDownloads ? "Recently Downloaded" : L(.home_recently_added))
                .font(.title2.bold())
                .foregroundStyle(Theme.primaryText)
                .padding(.horizontal, Theme.Layout.screenPadding)
                .padding(.top, 30)
                .padding(.bottom, 14)

            LazyVGrid(columns: recentColumns, spacing: 20) {
                ForEach(recentItems) { item in
                    recentCard(item)
                }
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
        }
    }

    private var libraryOptionsButton: some View {
        Menu {
            Button {
                showSectionEditor = true
            } label: {
                Label("Edit Sections", systemImage: "checklist")
            }
            if !isDownloadOnly {
                Divider()
                Picker("Library Source", selection: Binding(
                    get: { vm.source },
                    set: { vm.setSource($0) }
                )) {
                    ForEach(LibrarySource.allCases) { source in
                        Text(source.label).tag(source)
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 22))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 38, height: 38)
                .glassCircle()
        }
        .menuStyle(.button)
        .accessibilityLabel("Library options")
    }

    @ViewBuilder
    private func sectionRow(_ section: ModernLibrarySection) -> some View {
        switch section {
        case .madeForYou:
            if !appState.homeViewModel.mixes.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(section.title)
                        .font(.title3.bold())
                        .foregroundStyle(Theme.primaryText)
                        .padding(.top, 18)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(appState.homeViewModel.mixes) { mix in
                                NavigationLink {
                                    MixDetailView(mix: mix)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ArtworkView(coverArtID: mix.coverArt, size: 300)
                                            .frame(width: 132, height: 132)
                                        Text(mix.localizedTitle)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(Theme.primaryText)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 132, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.bottom, 18)
                }
            }
        case .folders:
            Button {
                if vm.source == .downloaded {
                    path.append(LibraryRoute.downloadedFolder(path: []))
                } else {
                    path.append(LibraryRoute.folder(vm.rootFolderSource))
                }
            } label: {
                sectionRowLabel(section)
            }
            .buttonStyle(.plain)
        default:
            Button {
                path.append(ModernLibraryDestination.collection(collection(for: section), source(for: section)))
            } label: {
                sectionRowLabel(section)
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionRowLabel(_ section: ModernLibrarySection) -> some View {
        HStack(spacing: 16) {
            Image(systemName: section.icon)
                .font(.title3.weight(.medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            Text(section.title)
                .font(.title3)
                .foregroundStyle(Theme.primaryText)
            Spacer()
            Image(systemName: Symbols.chevron)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 18)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func recentCard(_ item: ModernLibraryRecentItem) -> some View {
        switch item {
        case .album(let album, _):
            NavigationLink {
                AlbumDetailView(album: album)
                    .zoomNavigationTransition(
                        sourceID: recentAlbumHeroID(album),
                        in: heroNamespace
                    )
            } label: {
                MediaCard(album: album, heroSourceID: recentAlbumHeroID(album))
            }
            .buttonStyle(.plain)
            .albumContextMenu(album)
        case .playlist(let playlist, _):
            NavigationLink {
                PlaylistDetailView(playlist: playlist)
                    .zoomNavigationTransition(
                        sourceID: recentPlaylistHeroID(playlist),
                        in: heroNamespace
                    )
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    PlaylistCover(playlist: playlist)
                        .aspectRatio(1, contentMode: .fit)
                        .heroSource(id: recentPlaylistHeroID(playlist))
                    Text(playlist.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Text(L(.media_playlist))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .buttonStyle(.plain)
            .playlistContextMenu(playlist)
        }
    }

    @ViewBuilder
    private func pinnedCard(_ item: ModernLibraryPinnedItem) -> some View {
        switch item {
        case .album(let album):
            NavigationLink {
                AlbumDetailView(album: album)
                    .zoomNavigationTransition(
                        sourceID: pinnedAlbumHeroID(album),
                        in: heroNamespace
                    )
            } label: {
                MediaCard(
                    album: album,
                    width: 132,
                    heroSourceID: pinnedAlbumHeroID(album)
                )
            }
            .buttonStyle(.plain)
            .albumContextMenu(album)
        case .playlist(let playlist):
            NavigationLink {
                PlaylistDetailView(playlist: playlist)
                    .zoomNavigationTransition(
                        sourceID: pinnedPlaylistHeroID(playlist),
                        in: heroNamespace
                    )
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    PlaylistCover(playlist: playlist)
                        .frame(width: 132, height: 132)
                        .aspectRatio(1, contentMode: .fit)
                        .heroSource(id: pinnedPlaylistHeroID(playlist))
                    Text(playlist.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Text("Playlist")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                .frame(width: 132, alignment: .leading)
            }
            .buttonStyle(.plain)
            .playlistContextMenu(playlist)
        }
    }

    private func collection(for section: ModernLibrarySection) -> ModernLibraryCollection {
        switch section {
        case .artists: return .artists
        case .albums: return .albums
        case .songs: return .songs
        case .downloaded: return .downloads
        case .madeForYou, .folders: return .albums
        }
    }

    private func recentPlaylistHeroID(_ playlist: Playlist) -> String {
        "library-recent-playlist-\(playlist.id)"
    }

    private func pinnedPlaylistHeroID(_ playlist: Playlist) -> String {
        "library-pinned-playlist-\(playlist.id)"
    }

    private func recentAlbumHeroID(_ album: Album) -> String {
        "library-recent-album-\(album.id)"
    }

    private func pinnedAlbumHeroID(_ album: Album) -> String {
        "library-pinned-album-\(album.id)"
    }

    private func source(for section: ModernLibrarySection) -> LibrarySource {
        section == .downloaded ? .downloaded : vm.source
    }

    @ViewBuilder
    private func destination(for route: LibraryRoute) -> some View {
        switch route {
        case .album(let album):
            AlbumDetailView(album: album)
                .zoomNavigationTransition(sourceID: album.id, in: heroNamespace)
        case .artist(let artist):
            ArtistDetailView(artist: artist)
        case .playlist(let playlist):
            PlaylistDetailView(playlist: playlist)
                .zoomNavigationTransition(sourceID: playlist.id, in: heroNamespace)
        case .genreAlbums(let genre):
            FullMediaGrid(title: genre, items: vm.albumsForGenre(genre).map(MediaItem.init(album:))) { item in
                if let album = item.albumRef { path.append(LibraryRoute.album(album)) }
            }
        case .folder(let source):
            FolderBrowseScreen(source: source, title: folderTitle(source))
        case .downloadedFolder(let folderPath):
            DownloadedFolderScreen(path: folderPath, title: folderPath.last ?? L(.library_folders))
        }
    }

    private func folderTitle(_ source: FolderSource) -> String {
        if case .directory(_, let name) = source { return name }
        return L(.library_folders)
    }

    private func loadLibrary() async {
        if appState.isOfflineMode || appState.client == nil {
            vm.setSource(.downloaded)
            playlists = PlaylistOfflineCache.shared.playlists(for: appState.currentServer?.id)
        } else if let client = appState.client {
            await vm.load(client: client)
            if let loaded = try? await client.playlists() {
                PlaylistOfflineCache.shared.cacheList(loaded, serverID: appState.currentServer?.id)
                playlists = loaded
                Task {
                    await PlaylistOfflineCache.shared.cacheAll(
                        loaded,
                        client: client,
                        serverID: appState.currentServer?.id
                    )
                }
            } else {
                playlists = PlaylistOfflineCache.shared.playlists(for: appState.currentServer?.id)
            }
        }
        if !appState.homeViewModel.hasLoaded {
            await appState.homeViewModel.load(appState: appState)
        }
    }
}

private enum ModernLibraryRecentItem: Identifiable {
    case album(Album, Date)
    case playlist(Playlist, Date)

    var id: String {
        switch self {
        case .album(let album, _): return "album-\(album.id)"
        case .playlist(let playlist, _): return "playlist-\(playlist.id)"
        }
    }

    var date: Date {
        switch self {
        case .album(_, let date), .playlist(_, let date): return date
        }
    }
}

private enum ModernLibraryPinnedItem: Identifiable {
    case album(Album)
    case playlist(Playlist)

    var id: String {
        switch self {
        case .album(let album): return "album-\(album.id)"
        case .playlist(let playlist): return "playlist-\(playlist.id)"
        }
    }
}

private struct ModernLibrarySectionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var sectionsRaw: String
    @State private var orderedSections: [ModernLibrarySection]
    @State private var enabledSections: Set<ModernLibrarySection>
    private let defaults: [ModernLibrarySection]
    private let excludesDownloaded: Bool

    init(
        sectionsRaw: Binding<String>,
        defaults: [ModernLibrarySection] = ModernLibrarySection.defaults,
        excludesDownloaded: Bool = false
    ) {
        let enabled = ModernLibrarySection.decode(sectionsRaw.wrappedValue, defaults: defaults)
        _sectionsRaw = sectionsRaw
        _enabledSections = State(initialValue: Set(enabled))
        _orderedSections = State(
            initialValue: (enabled + ModernLibrarySection.allCases.filter { !enabled.contains($0) })
                .filter { $0 != .downloaded }
        )
        self.defaults = defaults
        self.excludesDownloaded = excludesDownloaded
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(orderedSections) { section in
                        sectionToggle(section)
                    }
                    .onMove(perform: move)
                } footer: {
                    Text("Choose sections shown in Library. Drag to change their order.")
                }
                .listRowBackground(Theme.secondaryBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Sections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L(.action_done)) { dismiss() }
                }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(Theme.colorScheme)
        .onDisappear {
            sectionsRaw = ModernLibrarySection.encode(orderedSections.filter { enabledSections.contains($0) })
        }
    }

    private func sectionToggle(_ section: ModernLibrarySection) -> some View {
        Button {
            toggle(section)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isEnabled(section) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isEnabled(section) ? Theme.accent : Theme.secondaryText)
                Image(systemName: section.icon)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 24)
                Text(section.title)
                    .foregroundStyle(Theme.primaryText)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func isEnabled(_ section: ModernLibrarySection) -> Bool {
        enabledSections.contains(section)
    }

    private func toggle(_ section: ModernLibrarySection) {
        if enabledSections.contains(section) {
            enabledSections.remove(section)
        } else {
            enabledSections.insert(section)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        orderedSections.move(fromOffsets: source, toOffset: destination)
    }
}

private struct ModernLibraryCollectionView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = LibraryViewModel()
    @StateObject private var downloadService = DownloadService.shared
    let collection: ModernLibraryCollection
    let source: LibrarySource
    @Binding var path: NavigationPath
    @Binding var sectionsRaw: String
    @State private var showSectionEditor = false
#if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
#endif

    private var columns: [GridItem] {
        let count: Int
#if os(iOS)
        count = verticalSizeClass == .compact ? 4 : 2
#else
        count = 2
#endif
        return Array(repeating: GridItem(.flexible(), spacing: Theme.Layout.gridSpacing), count: count)
    }

    private var downloadedSections: [ModernLibrarySection] {
        ModernLibrarySection.decode(
            sectionsRaw,
            defaults: ModernLibrarySection.downloadedDefaults
        )
        .filter { $0 != .downloaded }
    }

    private var recentlyDownloadedAlbums: [Album] {
        recentDownloadedAlbums(
            from: downloadService.downloadedSongsByDownloadDate(),
            matching: vm.filteredAlbums
        )
    }

    private var alphabetItems: [AlphabetJumpItem] {
        switch collection {
        case .artists:
            return artistSections.compactMap {
                guard let first = $0.items.first else { return nil }
                return AlphabetJumpItem(label: $0.label, targetID: anchor(kind: "artist", id: first.id))
            }
        case .albums:
            return albumSections.map {
                AlphabetJumpItem(
                    label: $0.label,
                    targetID: anchor(kind: "album", id: "section-\($0.label)")
                )
            }
        case .songs:
            return songSections.compactMap {
                guard let first = $0.items.first else { return nil }
                return AlphabetJumpItem(label: $0.label, targetID: anchor(kind: "song", id: first.song.id))
            }
        case .downloads:
            return []
        }
    }

    private var artistSections: [ModernAlphabetSection<Artist>] {
        alphabetSections(vm.filteredArtists, title: \.name)
    }

    private var albumSections: [ModernAlphabetSection<Album>] {
        alphabetSections(displayedAlbums, title: \.name)
    }

    private var songEntries: [ModernLibrarySongEntry] {
        displayedSongs.enumerated().map {
            ModernLibrarySongEntry(song: $0.element, queueIndex: $0.offset)
        }
    }

    private var songSections: [ModernAlphabetSection<ModernLibrarySongEntry>] {
        alphabetSections(songEntries, title: { $0.song.title })
    }

    private var displayedAlbums: [Album] {
        vm.filteredAlbums.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var displayedSongs: [Song] {
        vm.filteredSongs.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollViewReader { scrollProxy in
                ZStack(alignment: .trailing) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if collection == .downloads {
                                downloadedHome
                            } else {
                                collectionBody
                            }
                        }
                        .padding(.bottom, 96)
                        .padding(.trailing, alphabetItems.count >= 3 ? 34 : 0)
                    }
                    .scrollIndicators(.hidden)

                    if alphabetItems.count >= 3 {
                        AlphabetJumpBar(items: alphabetItems) { item in
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            scrollProxy.scrollTo(item.targetID, anchor: .top)
                        }
                        .padding(.trailing, 4)
                    }
                }
            }
        }
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.automatic, for: .navigationBar)
        .modernLibrarySearchable(
            collection != .downloads,
            text: $vm.searchText,
            prompt: "Search \(collection.title)"
        )
        .toolbar {
            if collection == .downloads {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSectionEditor = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Edit downloaded sections")
                }
            }
        }
        .sheet(isPresented: $showSectionEditor) {
            ModernLibrarySectionEditor(
                sectionsRaw: $sectionsRaw,
                defaults: ModernLibrarySection.downloadedDefaults,
                excludesDownloaded: true
            )
        }
        .preferredColorScheme(Theme.colorScheme)
        .background(ModernLibraryNavigationBarRestorer())
        .task(id: "\(appState.currentServer?.id ?? "none")|\(source.rawValue)") {
            vm.setSource(source)
            if source == .server, let client = appState.client {
                await vm.load(client: client)
            }
        }
    }

    @ViewBuilder
    private var collectionBody: some View {
        if vm.isLoading && !vm.hasLoaded && source == .server {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)
                .frame(maxWidth: .infinity, minHeight: 280)
        } else {
            switch collection {
            case .artists:
                artistList
            case .albums:
                albumGrid
            case .songs:
                songList
            case .downloads:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var downloadedHome: some View {
        ForEach(downloadedSections) { section in
            switch section {
            case .folders:
                Button {
                    path.append(LibraryRoute.downloadedFolder(path: []))
                } label: {
                    downloadedSectionLabel(section)
                }
                .buttonStyle(.plain)
            case .madeForYou:
                if !appState.homeViewModel.mixes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(section.title)
                            .font(.title3.bold())
                            .foregroundStyle(Theme.primaryText)
                            .padding(.horizontal, Theme.Layout.screenPadding)
                            .padding(.top, 18)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(appState.homeViewModel.mixes) { mix in
                                    NavigationLink {
                                        MixDetailView(mix: mix)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            ArtworkView(coverArtID: mix.coverArt, size: 260)
                                                .frame(width: 120, height: 120)
                                            Text(mix.localizedTitle)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(Theme.primaryText)
                                                .lineLimit(1)
                                        }
                                        .frame(width: 120, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, Theme.Layout.screenPadding)
                        }
                        .padding(.bottom, 18)
                    }
                }
            case .artists, .albums, .songs:
                Button {
                    path.append(ModernLibraryDestination.collection(collection(for: section), .downloaded))
                } label: {
                    downloadedSectionLabel(section)
                }
                .buttonStyle(.plain)
            case .downloaded:
                EmptyView()
            }
            if section != downloadedSections.last {
                Divider()
                    .background(Theme.secondaryText.opacity(0.16))
                    .padding(.leading, 56)
                    .padding(.horizontal, Theme.Layout.screenPadding)
            }
        }
    }

    private func downloadedSectionLabel(_ section: ModernLibrarySection) -> some View {
        HStack(spacing: 16) {
            Image(systemName: section.icon)
                .font(.title3.weight(.medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            Text(section.title)
                .font(.title3)
                .foregroundStyle(Theme.primaryText)
            Spacer()
            Image(systemName: Symbols.chevron)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, Theme.Layout.screenPadding)
        .padding(.vertical, 18)
        .contentShape(Rectangle())
    }

    private func collection(for section: ModernLibrarySection) -> ModernLibraryCollection {
        switch section {
        case .artists: return .artists
        case .albums: return .albums
        case .songs: return .songs
        case .downloaded, .madeForYou, .folders: return .albums
        }
    }

    private var artistList: some View {
        LazyVStack(spacing: 0) {
            ForEach(artistSections) { section in
                ForEach(section.items) { artist in
                    NavigationLink(value: LibraryRoute.artist(artist)) {
                        HStack(spacing: 14) {
                            ArtworkView(coverArtID: artist.coverArt, size: 120, cornerRadius: 28)
                                .frame(width: 56, height: 56)
                            Text(artist.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Theme.primaryText)
                            Spacer()
                            Image(systemName: Symbols.chevron)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .padding(.horizontal, Theme.Layout.screenPadding)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .id(anchor(kind: "artist", id: artist.id))
                    Divider().background(Theme.secondaryText.opacity(0.16)).padding(.leading, 84)
                }
            }
        }
        .padding(.top, 12)
    }

    private var albumGrid: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(albumSections) { section in
                Color.clear
                    .frame(height: 1)
                    .id(anchor(kind: "album", id: "section-\(section.label)"))
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(section.items) { album in
                        NavigationLink(value: LibraryRoute.album(album)) {
                            MediaCard(album: album)
                        }
                        .buttonStyle(.plain)
                        .albumContextMenu(album)
                        .id(anchor(kind: "album", id: album.id))
                }
            }
        }

    }
        .padding(Theme.Layout.screenPadding)
    }

    private var songList: some View {
        LazyVStack(spacing: 0) {
            ForEach(songSections) { section in
                ForEach(section.items) { entry in
                    let song = entry.song
                    TrackRow(
                        song: song,
                        index: entry.queueIndex + 1,
                        isCurrentlyPlaying: appState.audioPlayer.currentSong?.id == song.id,
                        onTap: {
                            appState.audioPlayer.playQueue(
                                displayedSongs,
                                startIndex: entry.queueIndex,
                                source: collection.title
                            )
                        },
                        showArtist: true,
                        leadingArtwork: true,
                        onSwipePlayNext: { appState.audioPlayer.playNext(song) }
                    ) {
                        SongMenu(song: song)
                    }
                    .padding(.horizontal, Theme.Layout.screenPadding)
                    .id(anchor(kind: "song", id: song.id))
                    Divider().background(Theme.secondaryText.opacity(0.16)).padding(.leading, 76)
                }
            }
        }
        .padding(.top, 8)
    }

    private func alphabetSections<Item>(
        _ items: [Item],
        title: (Item) -> String
    ) -> [ModernAlphabetSection<Item>] {
        var buckets: [String: [Item]] = [:]
        for item in items {
            let label = alphabetLabel(for: title(item))
            buckets[label, default: []].append(item)
        }
        return buckets.keys
            .sorted { alphabetRank($0) < alphabetRank($1) }
            .map { ModernAlphabetSection(label: $0, items: buckets[$0] ?? []) }
    }

    private func anchor(kind: String, id: String) -> String {
        "modern-library-\(source.rawValue)-\(kind)-\(id)"
    }

    private func alphabetLabel(for text: String) -> String {
        let normalized = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard let first = normalized.first else { return "#" }
        let label = String(first).uppercased()
        return ("A"..."Z").contains(label) ? label : "#"
    }

    private func alphabetRank(_ label: String) -> Int {
        guard label != "#", let scalar = label.unicodeScalars.first else { return 26 }
        return Int(scalar.value - UnicodeScalar("A").value)
    }
}

private struct ModernAlphabetSection<Item>: Identifiable {
    let label: String
    var items: [Item]
    var id: String { label }
}

private struct ModernLibrarySongEntry: Identifiable {
    let song: Song
    let queueIndex: Int
    var id: String { song.id }
}

private func recentDownloadedAlbums(
    from songs: [Song],
    matching availableAlbums: [Album],
    limit: Int = 30
) -> [Album] {
    var seen = Set<String>()
    var result: [Album] = []

    for song in songs {
        let match = availableAlbums.first {
            $0.id == song.albumId
                || ($0.name == song.album && $0.displayArtist == (song.albumArtist ?? song.artist ?? song.primaryArtistName))
        }
        guard let album = match, seen.insert(album.id).inserted else { continue }
        result.append(album)
        if result.count == limit { return result }
    }

    // Old downloads can lack persisted timestamps. Keep the shelf visible.
    for album in availableAlbums where seen.insert(album.id).inserted {
        result.append(album)
        if result.count == limit { break }
    }
    return result
}

private extension View {
    @ViewBuilder
    func modernLibrarySearchable(
        _ enabled: Bool,
        text: Binding<String>,
        prompt: String
    ) -> some View {
        if enabled {
            searchable(text: text, placement: .navigationBarDrawer(displayMode: .automatic), prompt: prompt)
        } else {
            self
        }
    }
}

/// Album and playlist details intentionally hide their navigation bar. Restore
/// it only when this Library screen reappears after a pop; continually forcing
/// the bar from SwiftUI updates made ordinary taps fight toolbar visibility.
private struct ModernLibraryNavigationBarRestorer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard viewIfLoaded?.window != nil else { return }
            navigationController?.setNavigationBarHidden(false, animated: false)
        }
    }
}
