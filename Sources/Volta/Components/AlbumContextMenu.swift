import SwiftUI

// Apple Music-style long-press menu for an album card: enlarges the cover in a
// preview and offers play / shuffle / queue / download / favourite actions.
struct AlbumContextMenu: ViewModifier {
    let album: Album
    var onAddToPlaylist: ((Song) -> Void)? = nil

    @Environment(AppState.self) private var appState
    @State private var showStats = false
    private var audio: AudioPlayer { appState.audioPlayer }

    func body(content: Content) -> some View {
        content.contextMenu {
            Button { play(shuffled: false) } label: { Label("Play", systemImage: Symbols.play) }
            Button { play(shuffled: true) } label: { Label("Shuffle", systemImage: Symbols.shuffle) }
            Section {
                Button { queue(next: true) } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                Button { queue(next: false) } label: {
                    Label("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward")
                }
            }
            Section {
                Button { download() } label: { Label("Download", systemImage: Symbols.download) }
                Button { favorite() } label: { Label("Favorite", systemImage: Symbols.starEmpty) }
                Button { showStats = true } label: { Label("View Stats", systemImage: Symbols.stats) }
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
}

private struct AlbumStatsSheet: View {
    let album: Album
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(album.name) {
                    statRow("Artist", album.displayArtist)
                    statRow("Songs", album.songCount.map(String.init))
                    statRow("Duration", album.duration.map(formatDuration))
                    statRow("Plays", album.playCount.map(String.init))
                    statRow("Year", album.year.map(String.init))
                    statRow("Genre", album.genre)
                    statRow("Added", album.createdDate?.formatted(date: .abbreviated, time: .omitted))
                    statRow("Label", album.recordLabel)
                }
            }
            .navigationTitle("Album Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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
