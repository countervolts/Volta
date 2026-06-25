import SwiftUI

// Builds a virtual file tree out of downloaded songs. Each Song keeps the
// server's original `path` (e.g. "Artist/Album/01 Track.flac"), so we can
// reconstruct the exact same folder hierarchy the server exposes — entirely
// offline, with no API calls.
enum DownloadedFolderTree {
    // Immediate children of `prefix`: the next-level sub-folder names plus the
    // songs that live directly in this folder.
    static func contents(prefix: [String], songs: [Song]) -> (folders: [String], songs: [Song]) {
        var folderSet = Set<String>()
        var here: [Song] = []

        for song in songs {
            let comps = (song.path ?? "").split(separator: "/").map(String.init)
            // Everything but the filename forms the directory chain. A flat or
            // path-less download lands at the root.
            let dirComps = comps.count > 1 ? Array(comps.dropLast()) : []

            guard dirComps.count >= prefix.count,
                  Array(dirComps.prefix(prefix.count)) == prefix else { continue }

            if dirComps.count == prefix.count {
                here.append(song)
            } else {
                folderSet.insert(dirComps[prefix.count])
            }
        }

        let folders = folderSet.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let sortedSongs = here.sorted {
            let d0 = $0.discNumber ?? 1, d1 = $1.discNumber ?? 1
            if d0 != d1 { return d0 < d1 }
            let t0 = $0.track ?? 0, t1 = $1.track ?? 0
            if t0 != t1 { return t0 < t1 }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        return (folders, sortedSongs)
    }
}

// MARK: - Folder contents (embeddable list)

// One level of the downloaded-music tree; caller owns ScrollView/background.
// Deliberately styled to match FolderBrowseView so Server and Downloaded folder
// browsing look identical.
struct DownloadedFolderView: View {
    let prefix: [String]
    var filterText: String = ""

    @Environment(AppState.self) private var appState
    @AppStorage("showTrackArtwork") private var showTrackArtwork = true
    @State private var downloadService = DownloadService.shared
    @State private var hiddenAlbums = HiddenAlbumStore.shared
    @State private var addToPlaylistSong: Song? = nil
    @State private var albumToShow: Album? = nil
    @State private var artistToShow: Artist? = nil

    // Recomputes whenever the download set changes (e.g. metadata backfill).
    private var node: (folders: [String], songs: [Song]) {
        _ = downloadService.downloadedRevision
        let visible = HiddenAlbumStore.shared.visibleSongs(downloadService.downloadedSongs())
        return DownloadedFolderTree.contents(prefix: prefix, songs: visible)
    }

    private func filtered(_ node: (folders: [String], songs: [Song])) -> (folders: [String], songs: [Song]) {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return node }
        return (
            node.folders.filter { $0.localizedCaseInsensitiveContains(q) },
            node.songs.filter { $0.title.localizedCaseInsensitiveContains(q) }
        )
    }

    var body: some View {
        // Resolve the tree once per render: `node` walks every downloaded song's
        // path, so referencing it from several computed properties used to redo
        // that work multiple times per body evaluation.
        let (folders, songs) = filtered(node)
        return LazyVStack(spacing: 0) {
            if folders.isEmpty && songs.isEmpty {
                emptyState
            } else {
                if !songs.isEmpty { playHeader(songs) }
                ForEach(folders, id: \.self) { name in
                    directoryRow(name)
                    Divider().background(Theme.secondaryText.opacity(0.12)).padding(.leading, 64)
                }
                ForEach(Array(songs.enumerated()), id: \.element.id) { i, song in
                    songRow(song, position: i + 1, in: songs)
                    Divider().background(Theme.secondaryText.opacity(0.12)).padding(.leading, 64)
                }
            }
        }
        .sheet(item: $addToPlaylistSong) { song in
            AddToPlaylistSheet(song: song, onAdded: { _ in })
        }
        .sheet(item: $albumToShow) { album in
            NavigationStack {
                AlbumDetailView(album: album)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { albumToShow = nil }
                                .foregroundStyle(Theme.accent)
                        }
                    }
            }
            .preferredColorScheme(Theme.colorScheme)
        }
        .sheet(item: $artistToShow) { artist in
            NavigationStack {
                ArtistDetailView(artist: artist)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { artistToShow = nil }
                                .foregroundStyle(Theme.accent)
                        }
                    }
            }
            .preferredColorScheme(Theme.colorScheme)
        }
    }

    // MARK: Rows

    private var sourceTitle: String { prefix.last ?? "Downloads" }

    private func playHeader(_ songs: [Song]) -> some View {
        HStack(spacing: 12) {
            Button {
                appState.audioPlayer.playQueue(songs, startIndex: 0, source: sourceTitle)
            } label: {
                Label(L(.action_play), systemImage: Symbols.play)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                appState.audioPlayer.playQueue(songs.shuffled(), startIndex: 0, source: sourceTitle)
            } label: {
                Label(L(.action_shuffle), systemImage: Symbols.shuffle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .glassCapsule(tinted: true)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Layout.screenPadding)
        .padding(.vertical, 12)
    }

    private func directoryRow(_ name: String) -> some View {
        NavigationLink(value: LibraryRoute.downloadedFolder(path: prefix + [name])) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.secondaryBackground)
                        .frame(width: 44, height: 44)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.accent.opacity(0.9))
                }
                Text(name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Spacer()
                Image(systemName: Symbols.chevron)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func songRow(_ song: Song, position: Int, in songs: [Song]) -> some View {
        TrackRow(
            song: song,
            index: song.track ?? position,
            isCurrentlyPlaying: appState.audioPlayer.currentSong?.id == song.id,
            onTap: {
                if let idx = songs.firstIndex(where: { $0.id == song.id }) {
                    appState.audioPlayer.playQueue(songs, startIndex: idx, source: sourceTitle)
                }
            },
            showArtist: true,
            leadingArtwork: showTrackArtwork,
            onSwipePlayNext: { appState.audioPlayer.playNext(song) }
        ) {
            SongMenu(
                song: song,
                onGoToAlbum: song.albumId == nil ? nil : { goToAlbum(song) },
                onGoToArtist: song.artistId == nil ? nil : { goToArtist(song) },
                onAddToPlaylist: { addToPlaylistSong = song }
            )
        }
        .padding(.horizontal, Theme.Layout.screenPadding)
    }

    private func goToAlbum(_ song: Song) {
        guard let id = song.albumId, let client = appState.client else { return }
        Task { albumToShow = try? await client.album(id: id) }
    }

    private func goToArtist(_ song: Song) {
        guard let id = song.artistId, let client = appState.client else { return }
        Task { artistToShow = try? await client.artist(id: id) }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: prefix.isEmpty ? Symbols.downloaded : "folder")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(Theme.secondaryText)
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(.horizontal, 40)
    }

    private var emptyMessage: String {
        if !filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "No matches" }
        return prefix.isEmpty ? "Download songs to browse them by folder offline." : "Empty folder"
    }
}

// MARK: - Pushed directory screen

// Full-screen wrapper used when drilling into a downloaded sub-folder from the
// Library navigation stack.
struct DownloadedFolderScreen: View {
    let path: [String]
    let title: String

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                DownloadedFolderView(prefix: path)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .background(SwipeBackEnabler())
        .preferredColorScheme(Theme.colorScheme)
    }
}
