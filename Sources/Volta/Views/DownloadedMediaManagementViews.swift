import SwiftUI
import UIKit

enum DownloadedItemSort: String, CaseIterable, Identifiable {
    case name = "Name"
    case size = "Size"
    case newest = "Newest"

    var id: String { rawValue }
}

struct DownloadedAlbumItem: Identifiable, Sendable {
    let id: String
    let name: String
    let artist: String
    let coverArt: String?
    let tracks: [DownloadedTrackItem]
    let bytes: Int64
    let downloadedAt: Date?

    static func groupingID(for item: DownloadedTrackItem) -> String {
        if let albumID = item.song?.albumId?.trimmingCharacters(in: .whitespacesAndNewlines), !albumID.isEmpty {
            return "id:\(albumID)"
        }
        if let album = item.song?.album?.trimmingCharacters(in: .whitespacesAndNewlines), !album.isEmpty {
            return "name:\(album.lowercased())|\((item.song?.albumArtist ?? item.song?.artist ?? "").lowercased())"
        }
        return "file:\(item.id)"
    }

    static func make(from tracks: [DownloadedTrackItem]) -> [DownloadedAlbumItem] {
        Dictionary(grouping: tracks, by: groupingID(for:)).map { id, group in
            let songs = group.compactMap(\.song)
            return DownloadedAlbumItem(
                id: id,
                name: songs.first?.album ?? "Unknown Album",
                artist: songs.first?.albumArtist ?? songs.first?.artist ?? "Unknown Artist",
                coverArt: songs.first?.coverArt,
                tracks: group,
                bytes: group.reduce(0) { $0 + $1.bytes },
                downloadedAt: group.compactMap(\.downloadedAt).max()
            )
        }
    }
}

struct DownloadedSongsManagerView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var downloadService = DownloadService.shared
    @State private var items: [DownloadedTrackItem] = []
    @State private var searchText = ""
    @State private var sort: DownloadedItemSort = .newest
    @State private var showDeleteAll = false
    @State private var isSelecting = false
    @State private var selection: Set<String> = []

    let onStorageChanged: @MainActor () -> Void

    var body: some View {
        DownloadManagementScaffold(title: "Downloaded Songs", sort: $sort) {
            Section {
                if visibleItems.isEmpty {
                    DownloadedEmptyRow(searching: !searchText.isEmpty, noun: "songs")
                } else {
                    ForEach(visibleItems) { item in
                        HStack(spacing: isSelecting ? 10 : 0) {
                            if isSelecting { DownloadSelectionMark(isSelected: selection.contains(item.id)) }
                            DownloadedTrackRow(item: item)
                        }
                            .contentShape(Rectangle())
                            .onTapGesture { isSelecting ? toggle(item.id) : play(item) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if !isSelecting {
                                    Button(role: .destructive) { delete(item) } label: {
                                        Label(L(.action_delete), systemImage: Symbols.trash)
                                    }
                                }
                            }
                    }
                }
            } header: {
                Text("\(visibleItems.count) songs")
            } footer: {
                Text("\(downloadByteString(totalBytes)) total")
            }
            deleteAllSection(disabled: items.isEmpty) { showDeleteAll = true }
        }
        .searchable(text: $searchText, prompt: "Search downloaded songs")
        .downloadMultiSelection(
            selection: $selection,
            isSelecting: $isSelecting,
            disabled: items.isEmpty,
            noun: "songs",
            onDelete: deleteSelected
        )
        .task(id: downloadService.downloadedRevision) { await reload() }
        .alert("Delete All Downloaded Songs?", isPresented: $showDeleteAll) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                downloadService.removeAllDownloads()
                items = []
                onStorageChanged()
            }
        } message: {
            Text("This removes every downloaded song from this device.")
        }
    }

    private var visibleItems: [DownloadedTrackItem] {
        let filtered = searchText.isEmpty ? items : items.filter {
            [$0.song?.title, $0.song?.artist, $0.song?.album, $0.fileName]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
        return sortedTracks(filtered, by: sort)
    }

    private var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }

    private func reload() async {
        items = await downloadService.downloadedItemsSnapshot()
    }

    private func delete(_ item: DownloadedTrackItem) {
        downloadService.removeDownload(id: item.id)
        items.removeAll { $0.id == item.id }
        onStorageChanged()
    }

    private func toggle(_ id: String) {
        selection.formSymmetricDifference([id])
    }

    private func deleteSelected(_ ids: [String]) {
        downloadService.removeDownloads(ids: ids)
        let removed = Set(ids)
        items.removeAll { removed.contains($0.id) }
        onStorageChanged()
    }

    private func play(_ item: DownloadedTrackItem) {
        let songs = visibleItems.compactMap(\.song)
        guard let song = item.song, let index = songs.firstIndex(where: { $0.id == song.id }) else { return }
        appState.audioPlayer.playQueue(songs, startIndex: index, source: "Downloads")
    }
}

struct DownloadedAlbumsManagerView: View {
    @StateObject private var downloadService = DownloadService.shared
    @State private var albums: [DownloadedAlbumItem] = []
    @State private var searchText = ""
    @State private var sort: DownloadedItemSort = .name
    @State private var showDeleteAll = false
    @State private var isSelecting = false
    @State private var selection: Set<String> = []

    let onStorageChanged: @MainActor () -> Void

    var body: some View {
        DownloadManagementScaffold(title: "Downloaded Albums", sort: $sort) {
            Section {
                if visibleAlbums.isEmpty {
                    DownloadedEmptyRow(searching: !searchText.isEmpty, noun: "albums")
                } else {
                    ForEach(visibleAlbums) { album in
                        Group {
                            if isSelecting {
                                Button { toggle(album.id) } label: {
                                    HStack(spacing: 10) {
                                        DownloadSelectionMark(isSelected: selection.contains(album.id))
                                        DownloadedAlbumRow(album: album)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink {
                                    DownloadedAlbumContentsView(album: album, onStorageChanged: storageChanged)
                                } label: {
                                    DownloadedAlbumRow(album: album)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if !isSelecting {
                                Button(role: .destructive) { delete(album) } label: {
                                    Label(L(.action_delete), systemImage: Symbols.trash)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("\(visibleAlbums.count) albums")
            } footer: {
                Text("\(downloadByteString(totalBytes)) total")
            }
            deleteAllSection(disabled: albums.isEmpty) { showDeleteAll = true }
        }
        .searchable(text: $searchText, prompt: "Search downloaded albums")
        .downloadMultiSelection(
            selection: $selection,
            isSelecting: $isSelecting,
            disabled: albums.isEmpty,
            noun: "albums",
            onDelete: deleteSelected
        )
        .task(id: downloadService.downloadedRevision) { await reload() }
        .alert("Delete All Downloaded Albums?", isPresented: $showDeleteAll) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                downloadService.removeAllDownloads()
                albums = []
                onStorageChanged()
            }
        } message: {
            Text("This removes every downloaded song from this device.")
        }
    }

    private var visibleAlbums: [DownloadedAlbumItem] {
        let filtered = searchText.isEmpty ? albums : albums.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.artist.localizedCaseInsensitiveContains(searchText)
        }
        switch sort {
        case .name:
            return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .size:
            return filtered.sorted { $0.bytes > $1.bytes }
        case .newest:
            return filtered.sorted { ($0.downloadedAt ?? .distantPast) > ($1.downloadedAt ?? .distantPast) }
        }
    }

    private var totalBytes: Int64 { albums.reduce(0) { $0 + $1.bytes } }

    private func reload() async {
        let tracks = await downloadService.downloadedItemsSnapshot()
        albums = await DeveloperExperiments.runSync { DownloadedAlbumItem.make(from: tracks) }
    }

    private func delete(_ album: DownloadedAlbumItem) {
        downloadService.removeDownloads(ids: album.tracks.map(\.id))
        albums.removeAll { $0.id == album.id }
        onStorageChanged()
    }

    private func toggle(_ id: String) {
        selection.formSymmetricDifference([id])
    }

    private func deleteSelected(_ ids: [String]) {
        let selectedIDs = Set(ids)
        let trackIDs = albums
            .filter { selectedIDs.contains($0.id) }
            .flatMap { $0.tracks.map(\.id) }
        downloadService.removeDownloads(ids: trackIDs)
        albums.removeAll { selectedIDs.contains($0.id) }
        onStorageChanged()
    }

    private func storageChanged() {
        onStorageChanged()
        Task { await reload() }
    }
}

private struct DownloadedAlbumContentsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var downloadService = DownloadService.shared
    @State private var tracks: [DownloadedTrackItem]
    @State private var searchText = ""
    @State private var sort: DownloadedItemSort = .name
    @State private var showDeleteAlbum = false
    @State private var isSelecting = false
    @State private var selection: Set<String> = []

    let album: DownloadedAlbumItem
    let onStorageChanged: @MainActor () -> Void

    init(album: DownloadedAlbumItem, onStorageChanged: @escaping @MainActor () -> Void) {
        self.album = album
        self.onStorageChanged = onStorageChanged
        _tracks = State(initialValue: album.tracks)
    }

    var body: some View {
        DownloadManagementScaffold(title: album.name, sort: $sort) {
            Section {
                ForEach(visibleTracks) { item in
                    HStack(spacing: isSelecting ? 10 : 0) {
                        if isSelecting { DownloadSelectionMark(isSelected: selection.contains(item.id)) }
                        DownloadedTrackRow(item: item)
                    }
                        .contentShape(Rectangle())
                        .onTapGesture { isSelecting ? toggle(item.id) : play(item) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if !isSelecting {
                                Button(role: .destructive) { delete(item) } label: {
                                    Label(L(.action_delete), systemImage: Symbols.trash)
                                }
                            }
                        }
                }
            } header: {
                Text("\(visibleTracks.count) songs")
            } footer: {
                Text("\(downloadByteString(totalBytes)) total")
            }
            deleteAllSection(disabled: tracks.isEmpty, title: "Delete Downloaded Album") {
                showDeleteAlbum = true
            }
        }
        .searchable(text: $searchText, prompt: "Search this album")
        .downloadMultiSelection(
            selection: $selection,
            isSelecting: $isSelecting,
            disabled: tracks.isEmpty,
            noun: "songs",
            onDelete: deleteSelected
        )
        .alert("Delete Downloaded Album?", isPresented: $showDeleteAlbum) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                downloadService.removeDownloads(ids: tracks.map(\.id))
                tracks = []
                onStorageChanged()
            }
        } message: {
            Text("All downloaded songs in \(album.name) will be removed.")
        }
    }

    private var visibleTracks: [DownloadedTrackItem] {
        let filtered = searchText.isEmpty ? tracks : tracks.filter {
            ($0.song?.title ?? $0.fileName).localizedCaseInsensitiveContains(searchText)
                || ($0.song?.artist ?? "").localizedCaseInsensitiveContains(searchText)
        }
        return sortedTracks(filtered, by: sort)
    }

    private var totalBytes: Int64 { tracks.reduce(0) { $0 + $1.bytes } }

    private func delete(_ item: DownloadedTrackItem) {
        downloadService.removeDownload(id: item.id)
        tracks.removeAll { $0.id == item.id }
        onStorageChanged()
    }

    private func toggle(_ id: String) {
        selection.formSymmetricDifference([id])
    }

    private func deleteSelected(_ ids: [String]) {
        downloadService.removeDownloads(ids: ids)
        let removed = Set(ids)
        tracks.removeAll { removed.contains($0.id) }
        onStorageChanged()
    }

    private func play(_ item: DownloadedTrackItem) {
        let songs = visibleTracks.compactMap(\.song)
        guard let song = item.song, let index = songs.firstIndex(where: { $0.id == song.id }) else { return }
        appState.audioPlayer.playQueue(songs, startIndex: index, source: album.name)
    }
}

struct DownloadedLyricsManagerView: View {
    @State private var items: [DownloadedLyricsItem] = []
    @State private var revision = 0
    @State private var searchText = ""
    @State private var sort: DownloadedItemSort = .name
    @State private var showDeleteAll = false
    @State private var isSelecting = false
    @State private var selection: Set<String> = []

    let onStorageChanged: @MainActor () -> Void

    var body: some View {
        DownloadManagementScaffold(title: "Downloaded Lyrics", sort: $sort) {
            Section {
                if visibleItems.isEmpty {
                    DownloadedEmptyRow(searching: !searchText.isEmpty, noun: "lyrics")
                } else {
                    ForEach(visibleItems) { item in
                        HStack(spacing: isSelecting ? 10 : 0) {
                            if isSelecting { DownloadSelectionMark(isSelected: selection.contains(item.id)) }
                            DownloadedLyricsRow(item: item)
                        }
                            .contentShape(Rectangle())
                            .onTapGesture { if isSelecting { toggle(item.id) } }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if !isSelecting {
                                    Button(role: .destructive) { delete(item) } label: {
                                        Label(L(.action_delete), systemImage: Symbols.trash)
                                    }
                                }
                            }
                    }
                }
            } header: {
                Text("\(visibleItems.count) lyric files")
            } footer: {
                Text("\(downloadByteString(totalBytes)) total")
            }
            deleteAllSection(disabled: items.isEmpty) { showDeleteAll = true }
        }
        .searchable(text: $searchText, prompt: "Search downloaded lyrics")
        .downloadMultiSelection(
            selection: $selection,
            isSelecting: $isSelecting,
            disabled: items.isEmpty,
            noun: "lyrics",
            onDelete: deleteSelected
        )
        .task(id: revision) { items = await LyricsService.shared.downloadedLyricsItems() }
        .alert("Delete All Downloaded Lyrics?", isPresented: $showDeleteAll) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                Task {
                    await LyricsService.shared.clearLocalLyrics()
                    items = []
                    revision &+= 1
                    onStorageChanged()
                }
            }
        } message: {
            Text("Every locally saved lyric file will be removed.")
        }
    }

    private var visibleItems: [DownloadedLyricsItem] {
        let filtered = searchText.isEmpty ? items : items.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || ($0.artist ?? "").localizedCaseInsensitiveContains(searchText)
                || $0.source.localizedCaseInsensitiveContains(searchText)
        }
        switch sort {
        case .name: return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .size: return filtered.sorted { $0.bytes > $1.bytes }
        case .newest: return filtered.sorted { ($0.savedAt ?? .distantPast) > ($1.savedAt ?? .distantPast) }
        }
    }

    private var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }

    private func delete(_ item: DownloadedLyricsItem) {
        Task {
            await LyricsService.shared.removeLocalLyrics(storageKey: item.id)
            items.removeAll { $0.id == item.id }
            revision &+= 1
            onStorageChanged()
        }
    }

    private func toggle(_ id: String) {
        selection.formSymmetricDifference([id])
    }

    private func deleteSelected(_ ids: [String]) {
        let removed = Set(ids)
        Task {
            for id in ids { await LyricsService.shared.removeLocalLyrics(storageKey: id) }
            items.removeAll { removed.contains($0.id) }
            revision &+= 1
            onStorageChanged()
        }
    }
}

enum DownloadedArtworkCategory {
    case artwork
    case artistPictures

    var title: String {
        switch self {
        case .artwork: return "Downloaded Artwork"
        case .artistPictures: return "Downloaded Artist Pictures"
        }
    }

    var noun: String {
        switch self {
        case .artwork: return "artwork"
        case .artistPictures: return "artist pictures"
        }
    }

    func contains(_ item: DownloadedArtworkItem) -> Bool {
        let isArtistPicture = item.kind == "Artist Photo"
        return self == .artistPictures ? isArtistPicture : !isArtistPicture
    }
}

struct DownloadedArtworkManagerView: View {
    @StateObject private var artworkDownloader = ArtworkLibraryDownloader.shared
    @State private var items: [DownloadedArtworkItem] = []
    @State private var searchText = ""
    @State private var sort: DownloadedItemSort = .newest
    @State private var showDeleteAll = false
    @State private var isSelecting = false
    @State private var selection: Set<String> = []

    let category: DownloadedArtworkCategory
    let onStorageChanged: @MainActor () -> Void

    var body: some View {
        DownloadManagementScaffold(title: category.title, sort: $sort) {
            Section {
                if visibleItems.isEmpty {
                    DownloadedEmptyRow(searching: !searchText.isEmpty, noun: category.noun)
                } else {
                    ForEach(visibleItems) { item in
                        HStack(spacing: isSelecting ? 10 : 0) {
                            if isSelecting { DownloadSelectionMark(isSelected: selection.contains(item.id)) }
                            DownloadedArtworkRow(item: item)
                        }
                            .contentShape(Rectangle())
                            .onTapGesture { if isSelecting { toggle(item.id) } }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if !isSelecting {
                                    Button(role: .destructive) { delete(item) } label: {
                                        Label(L(.action_delete), systemImage: Symbols.trash)
                                    }
                                }
                            }
                    }
                }
            } header: {
                Text("\(visibleItems.count) \(category.noun)")
            } footer: {
                Text("\(downloadByteString(totalBytes)) total")
            }
            deleteAllSection(disabled: items.isEmpty) { showDeleteAll = true }
        }
        .searchable(text: $searchText, prompt: "Search \(category.noun)")
        .downloadMultiSelection(
            selection: $selection,
            isSelecting: $isSelecting,
            disabled: items.isEmpty,
            noun: category.noun,
            onDelete: deleteSelected
        )
        .task(id: artworkDownloader.revision) {
            items = await ArtworkLoader.shared.downloadedArtworkItems().filter(category.contains)
        }
        .alert("Delete All \(category.title)?", isPresented: $showDeleteAll) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                Task {
                    for id in items.map(\.id) {
                        await ArtworkLoader.shared.removeDownloadedArtwork(id: id)
                    }
                    UserDefaults.standard.set(false, forKey: "localArtworkLibraryDownloaded")
                    items = []
                    onStorageChanged()
                }
            }
        } message: {
            Text("Every downloaded \(category.noun) entry will be removed. The other artwork category and normal cache are not affected.")
        }
    }

    private var visibleItems: [DownloadedArtworkItem] {
        let filtered = searchText.isEmpty ? items : items.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.kind.localizedCaseInsensitiveContains(searchText)
                || $0.fileName.localizedCaseInsensitiveContains(searchText)
        }
        switch sort {
        case .name: return filtered.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .size: return filtered.sorted { $0.bytes > $1.bytes }
        case .newest: return filtered.sorted { ($0.savedAt ?? .distantPast) > ($1.savedAt ?? .distantPast) }
        }
    }

    private var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }

    private func delete(_ item: DownloadedArtworkItem) {
        Task {
            await ArtworkLoader.shared.removeDownloadedArtwork(id: item.id)
            items.removeAll { $0.id == item.id }
            onStorageChanged()
        }
    }

    private func toggle(_ id: String) {
        selection.formSymmetricDifference([id])
    }

    private func deleteSelected(_ ids: [String]) {
        let removed = Set(ids)
        Task {
            for id in ids { await ArtworkLoader.shared.removeDownloadedArtwork(id: id) }
            items.removeAll { removed.contains($0.id) }
            onStorageChanged()
        }
    }
}

struct DownloadManagementScaffold<Content: View>: View {
    let title: String
    @Binding var sort: DownloadedItemSort
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List { content() }
                .scrollContentBackground(.hidden)
                .background(Theme.background)
                .listRowBackground(Theme.secondaryBackground)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .background(SwipeBackEnabler())
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(DownloadedItemSort.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(Theme.colorScheme)
    }
}

private extension View {
    func downloadMultiSelection(
        selection: Binding<Set<String>>,
        isSelecting: Binding<Bool>,
        disabled: Bool,
        noun: String,
        onDelete: @escaping @MainActor ([String]) -> Void
    ) -> some View {
        modifier(DownloadMultiSelectionModifier(
            selection: selection,
            isSelecting: isSelecting,
            disabled: disabled,
            noun: noun,
            onDelete: onDelete
        ))
    }
}

private struct DownloadMultiSelectionModifier: ViewModifier {
    @Binding var selection: Set<String>
    @Binding var isSelecting: Bool
    let disabled: Bool
    let noun: String
    let onDelete: @MainActor ([String]) -> Void

    @State private var showDeleteConfirmation = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSelecting {
                    DownloadSelectionActionBar(selectionCount: selection.count) {
                        showDeleteConfirmation = true
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSelecting ? "Done" : "Select") {
                        isSelecting.toggle()
                        if !isSelecting { selection.removeAll() }
                    }
                    .disabled(disabled && !isSelecting)
                }
            }
            .alert("Delete Selected \(noun.capitalized)?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete \(selection.count)", role: .destructive) {
                    let ids = Array(selection)
                    onDelete(ids)
                    selection.removeAll()
                    isSelecting = false
                }
            } message: {
                Text("The selected \(noun) will be removed from this device.")
            }
    }
}

private struct DownloadSelectionActionBar: View {
    let selectionCount: Int
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(selectionCount) selected")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            Button(role: .destructive, action: delete) {
                Label("Delete Selected", systemImage: Symbols.trash)
            }
            .disabled(selectionCount == 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.secondaryBackground)
        .overlay(alignment: .top) {
            Divider().overlay(Theme.primaryText.opacity(0.12))
        }
    }
}

private struct DownloadSelectionMark: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(isSelected ? Theme.accent : Theme.secondaryText)
            .accessibilityHidden(true)
    }
}

private struct DownloadedTrackRow: View {
    let item: DownloadedTrackItem

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(coverArtID: item.song?.coverArt, size: 100, cornerRadius: 8)
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.song?.title ?? item.fileName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text(item.song?.artist ?? item.song?.album ?? item.id)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(downloadByteString(item.bytes))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

private struct DownloadedAlbumRow: View {
    let album: DownloadedAlbumItem

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(coverArtID: album.coverArt, size: 100, cornerRadius: 8)
                .frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(album.name).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(album.artist).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                Text("\(album.tracks.count) songs · \(downloadByteString(album.bytes))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct DownloadedLyricsRow: View {
    let item: DownloadedLyricsItem

    var body: some View {
        HStack(spacing: 12) {
            DownloadedAssetIcon(systemName: Symbols.lyrics)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(item.artist ?? item.source).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                Text("\(item.source) · \(item.format)")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            Text(downloadByteString(item.bytes))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 3)
    }
}

private struct DownloadedArtworkRow: View {
    let item: DownloadedArtworkItem

    var body: some View {
        HStack(spacing: 12) {
            if let data = item.previewData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                DownloadedAssetIcon(systemName: item.kind == "Animated" ? "sparkles.tv" : "photo")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(item.kind).font(.caption).foregroundStyle(Theme.secondaryText)
                if item.displayName == item.fileName {
                    Text(item.fileName).font(.caption2.monospaced()).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(downloadByteString(item.bytes))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 3)
    }
}

private struct DownloadedAssetIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(Theme.accent)
            .frame(width: 44, height: 44)
            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DownloadedEmptyRow: View {
    let searching: Bool
    let noun: String

    var body: some View {
        Text(searching ? "No matching \(noun)." : "No downloaded \(noun).")
            .font(.subheadline)
            .foregroundStyle(Theme.secondaryText)
    }
}

@ViewBuilder
private func deleteAllSection(
    disabled: Bool,
    title: String = "Delete All",
    action: @escaping () -> Void
) -> some View {
    Section {
        Button(role: .destructive, action: action) {
            Label(title, systemImage: Symbols.trash)
        }
        .disabled(disabled)
    }
    .listRowBackground(Theme.secondaryBackground)
}

private func sortedTracks(_ items: [DownloadedTrackItem], by sort: DownloadedItemSort) -> [DownloadedTrackItem] {
    switch sort {
    case .name:
        return items.sorted {
            ($0.song?.title ?? $0.fileName).localizedCaseInsensitiveCompare($1.song?.title ?? $1.fileName) == .orderedAscending
        }
    case .size:
        return items.sorted { $0.bytes > $1.bytes }
    case .newest:
        return items.sorted { ($0.downloadedAt ?? .distantPast) > ($1.downloadedAt ?? .distantPast) }
    }
}
