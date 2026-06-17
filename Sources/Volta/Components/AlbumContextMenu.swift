import SwiftUI

// Long-press album menu with a larger cover preview.
struct AlbumContextMenu: ViewModifier {
    let album: Album
    var onAddToPlaylist: ((Song) -> Void)? = nil

    @Environment(AppState.self) private var appState
    @State private var showStats = false
    private var audio: AudioPlayer { appState.audioPlayer }

    func body(content: Content) -> some View {
        content.contextMenu {
            Button { play(shuffled: false) } label: { Label(L(.action_play), systemImage: Symbols.play) }
            Button { play(shuffled: true) } label: { Label(L(.action_shuffle), systemImage: Symbols.shuffle) }
            Section {
                Button { queue(next: true) } label: {
                    Label(L(.action_play_next), systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                Button { queue(next: false) } label: {
                    Label(L(.action_add_to_queue), systemImage: "text.line.last.and.arrowtriangle.forward")
                }
            }
            Section {
                Button { download() } label: { Label(L(.action_download), systemImage: Symbols.download) }
                Button { favorite() } label: { Label(L(.action_favorite), systemImage: Symbols.starEmpty) }
                Button { showStats = true } label: { Label(L(.action_view_stats), systemImage: Symbols.stats) }
            }
            Section {
                Button(role: .destructive) { removeDownload() } label: {
                    Label(L(.action_remove_download), systemImage: Symbols.trash)
                }
            }
        } preview: {
            VStack(alignment: .leading, spacing: 10) {
                ContextAlbumArtwork(url: appState.client?.coverArtURL(id: album.coverArt, size: 600))
                    .aspectRatio(1, contentMode: .fit)
                    .frame(width: 240, height: 240)
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.name).font(.headline).foregroundStyle(.white).lineLimit(1)
                    Text(album.displayArtist).font(.subheadline).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
            }
            .padding(16)
            .background(Theme.secondaryBackground)
        }
        .sheet(isPresented: $showStats) {
            AlbumStatsSheet(album: album)
        }
    }

    // MARK: - Actions

    private func fetchSongs() async -> [Song] {
        if let s = album.song, !s.isEmpty { return s }
        guard let client = appState.client else { return [] }
        return (try? await client.album(id: album.id))?.song ?? []
    }

    private func play(shuffled: Bool) {
        Task {
            let songs = await fetchSongs()
            guard !songs.isEmpty else { return }
            audio.playQueue(shuffled ? songs.shuffled() : songs, startIndex: 0, source: album.name, album: album)
        }
    }

    private func queue(next: Bool) {
        Task {
            let songs = await fetchSongs()
            for song in (next ? songs.reversed() : songs) {
                if next { audio.playNext(song) } else { audio.addToQueue(song) }
            }
        }
    }

    private func download() {
        Task {
            for song in await fetchSongs() where DownloadService.shared.state(for: song) == .notDownloaded {
                DownloadService.shared.download(song: song)
            }
        }
    }

    private func favorite() {
        Task { try? await appState.client?.star(id: album.id) }
    }

    private func removeDownload() {
        Task {
            let songs = await fetchSongs()
            var removed = 0
            for song in songs where DownloadService.shared.state(for: song) == .downloaded {
                DownloadService.shared.removeDownload(for: song)
                removed += 1
            }
            if removed == 0 {
                VoltaNotificationCenter.shared.post(L(.notif_no_downloads_to_remove), tone: .info)
            }
        }
    }
}

private struct AlbumStatsSheet: View {
    let album: Album
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(album.name) {
                    statRow(L(.media_artist), album.displayArtist)
                    statRow(L(.media_songs), album.songCount.map(String.init))
                    statRow(L(.media_duration), album.duration.map(formatDuration))
                    statRow(L(.media_plays), album.playCount.map(String.init))
                    statRow(L(.media_year), album.year.map(String.init))
                    statRow(L(.media_genre), album.genre)
                    statRow(L(.media_added), album.createdDate?.formatted(date: .abbreviated, time: .omitted))
                    statRow(L(.media_label), album.recordLabel)
                }
            }
            .navigationTitle(L(.album_stats_title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L(.action_done)) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func statRow(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack {
                Text(title)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h) hr \(m) min" }
        return "\(m) min"
    }
}

private struct ContextAlbumArtwork: View {
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.secondaryBackground)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: Symbols.albumPlaceholder)
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: url) {
            image = await ArtworkLoader.shared.image(for: url, maxPixelSize: 600)
        }
    }
}

extension View {
    func albumContextMenu(_ album: Album, onAddToPlaylist: ((Song) -> Void)? = nil) -> some View {
        modifier(AlbumContextMenu(album: album, onAddToPlaylist: onAddToPlaylist))
    }
}
