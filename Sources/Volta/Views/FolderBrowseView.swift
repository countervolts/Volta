import SwiftUI
import UIKit

// Folder listing source.
enum FolderSource: Hashable, Sendable {
    case indexes(musicFolderID: String?)
    case directory(id: String, name: String)
}

// MARK: - Folder contents (embeddable list)

// One level of the file tree; caller owns ScrollView/background.
struct FolderBrowseView: View {
    let source: FolderSource
    // Optional root-level search filter.
    var filterText: String = ""
    var alphabetItems: Binding<[AlphabetJumpItem]>? = nil

    @EnvironmentObject private var appState: AppState
    @AppStorage("showTrackArtwork") private var showTrackArtwork = true
    @StateObject private var hiddenAlbums = HiddenAlbumStore.shared
    @State private var entries: [BrowseEntry] = []
    @State private var isLoading = true
    @State private var addToPlaylistSong: Song? = nil
    @State private var albumToShow: Album? = nil
    @State private var artistToShow: Artist? = nil

    private var directories: [BrowseEntry] { filtered.filter(\.isDirectory) }
    private var songEntries: [BrowseEntry] { filtered.filter { !$0.isDirectory } }
    private var songs: [Song] { songEntries.compactMap(\.song) }

    private var filtered: [BrowseEntry] {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = entries.filter { entry in
            guard let song = entry.song else { return true }
            return !hiddenAlbums.isSongHidden(song)
        }
        guard !q.isEmpty else { return visible }
        return visible.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            if isLoading && entries.isEmpty {
                ProgressView().controlSize(.large).tint(Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 280)
            } else if filtered.isEmpty {
                emptyState
            } else {
                if !songs.isEmpty { playHeader }
                ForEach(directories) { entry in
                    directoryRow(entry)
                    Divider().background(Theme.secondaryText.opacity(0.12)).padding(.leading, 64)
                }
                ForEach(Array(songEntries.enumerated()), id: \.element.id) { i, entry in
                    if let song = entry.song {
                        songRow(song, position: i + 1)
                        Divider().background(Theme.secondaryText.opacity(0.12)).padding(.leading, 64)
                    }
                }
            }
        }
        .task(id: source) { await load() }
        .onAppear { publishAlphabetItems() }
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

    private var playHeader: some View {
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

    private func directoryRow(_ entry: BrowseEntry) -> some View {
        NavigationLink(value: LibraryRoute.folder(.directory(id: entry.id, name: entry.name))) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.secondaryBackground)
                        .frame(width: 44, height: 44)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.accent.opacity(0.9))
                }
                Text(entry.name)
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
        .id(alphabetAnchor(kind: "directory", id: entry.id))
    }

    private func songRow(_ song: Song, position: Int) -> some View {
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
        .id(alphabetAnchor(kind: "song", id: song.id))
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
            Image(systemName: "folder")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(Theme.secondaryText)
            Text(filterText.isEmpty ? "Empty folder" : "No matches")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    // MARK: Loading

    private var sourceTitle: String {
        if case .directory(_, let name) = source { return name }
        return "Folders"
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        defer { isLoading = false }
        switch source {
        case .indexes(let folderID):
            entries = (try? await client.indexes(musicFolderId: folderID)) ?? []
        case .directory(let id, _):
            entries = (try? await client.musicDirectory(id: id)) ?? []
        }
        publishAlphabetItems()
    }

    private func publishAlphabetItems() {
        alphabetItems?.wrappedValue = jumpItems
    }

    private var jumpItems: [AlphabetJumpItem] {
        let namesAndTargets = directories.map {
            ($0.name, alphabetAnchor(kind: "directory", id: $0.id))
        } + songEntries.compactMap { entry in
            entry.song.map { ($0.title, alphabetAnchor(kind: "song", id: $0.id)) }
        }
        var seen = Set<String>()
        return namesAndTargets.compactMap { pair in
            let label = alphabetLabel(for: pair.0)
            return seen.insert(label).inserted
                ? AlphabetJumpItem(label: label, targetID: pair.1)
                : nil
        }
        .sorted { $0.label < $1.label }
    }

    private func alphabetAnchor(kind: String, id: String) -> String {
        "folder-\(kind)-\(id)"
    }

    private func alphabetLabel(for text: String) -> String {
        let normalized = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard let first = normalized.first else { return "#" }
        let label = String(first).uppercased()
        return ("A"..."Z").contains(label) ? label : "#"
    }
}

// MARK: - Pushed directory screen

// Full-screen wrapper used when drilling into a sub-directory from the Library
// navigation stack.
struct FolderBrowseScreen: View {
    let source: FolderSource
    let title: String
    @State private var alphabetItems: [AlphabetJumpItem] = []

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollViewReader { scrollProxy in
                ZStack(alignment: .trailing) {
                    ScrollView {
                        FolderBrowseView(source: source, alphabetItems: $alphabetItems)
                            .padding(.top, 8)
                            .padding(.bottom, 100)
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
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .background(SwipeBackEnabler())
        .preferredColorScheme(Theme.colorScheme)
    }
}
