import SwiftUI

struct PlaylistDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var vm: PlaylistDetailViewModel
    @State private var showAddToPlaylist: Song? = nil
    @State private var toastMessage: String? = nil
    @State private var drillAlbum: Album? = nil
    @State private var drillArtist: Artist? = nil

    init(playlist: Playlist) {
        _vm = State(wrappedValue: PlaylistDetailViewModel(playlist: playlist))
    }

    private var bg: Color {
        Color(ColorExtractor.backgroundVariant(of: vm.dominantColor))
    }

    var body: some View {
        ZStack(alignment: .top) {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    artworkSection
                    infoSection
                    actionRow
                    descriptionSection
                    trackList
                    footer
                    Color.clear.frame(height: 120)
                }
            }
            .scrollIndicators(.hidden)

            HStack {
                GlassBackButton()
                Spacer()
            }
            .padding(.top, 56)

            if let msg = toastMessage {
                VStack {
                    Spacer()
                    Text(msg)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 100)
                }
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        .sheet(item: $showAddToPlaylist) { song in
            AddToPlaylistSheet(song: song, onAdded: { name in
                withAnimation { toastMessage = "Added to \(name)" }
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    withAnimation { toastMessage = nil }
                }
            })
        }
        .sheet(item: $drillAlbum) { album in
            NavigationStack {
                AlbumDetailView(album: album)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { drillAlbum = nil }.foregroundStyle(Theme.accent)
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
        .sheet(item: $drillArtist) { artist in
            NavigationStack {
                ArtistDetailView(artist: artist)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { drillArtist = nil }.foregroundStyle(Theme.accent)
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
        .task { if let c = appState.client { await vm.load(client: c) } }
    }

    private var artworkSection: some View {
        GeometryReader { geo in
            ArtworkView(coverArtID: vm.playlist.coverArt, size: 800, cornerRadius: 0,
                        onImageLoaded: { image in
                            let color = ColorExtractor.dominantColor(from: image)
                            vm.setDominantColor(color)
                        })
                .aspectRatio(1, contentMode: .fill)
                .frame(width: geo.size.width, height: geo.size.width)
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, bg], startPoint: .init(x: 0.5, y: 0.5), endPoint: .bottom)
                        .frame(height: 160)
                }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vm.playlist.name)
                .font(.title2.bold())
                .foregroundStyle(.white)
            if let owner = vm.playlist.owner {
                Text("by \(owner)")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var actionRow: some View {
        HStack(spacing: 14) {
            Button {
                let songs = vm.songs.shuffled()
                if !songs.isEmpty {
                    appState.audioPlayer.playQueue(songs, startIndex: 0, source: vm.playlist.name, playlist: vm.playlist)
                }
            } label: {
                Image(systemName: Symbols.shuffle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .glassCircle()
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                if !vm.songs.isEmpty {
                    appState.audioPlayer.playQueue(vm.songs, startIndex: 0, source: vm.playlist.name, playlist: vm.playlist)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: Symbols.play).font(.system(size: 16, weight: .bold))
                    Text("Play").font(.headline)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 32).padding(.vertical, 14)
                .glassCapsule(tinted: true)
            }
            .buttonStyle(.plain)

            Spacer()

            // spacer button to keep layout balanced
            Color.clear.frame(width: 48, height: 48)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private var descriptionSection: some View {
        if let desc = vm.playlist.comment, !desc.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(desc)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(vm.isDescriptionExpanded ? nil : 3)
                    .animation(.easeInOut(duration: 0.3), value: vm.isDescriptionExpanded)
                Button { vm.toggleDescription() } label: {
                    Text(vm.isDescriptionExpanded ? "Less" : "More")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private var trackList: some View {
        VStack(spacing: 0) {
            ForEach(Array(vm.songs.enumerated()), id: \.element.id) { i, song in
                TrackRow(
                    song: song,
                    index: i + 1,
                    isCurrentlyPlaying: appState.audioPlayer.currentSong?.id == song.id,
                    onTap: {
                        appState.audioPlayer.playQueue(vm.songs, startIndex: i, source: vm.playlist.name, playlist: vm.playlist)
                    }
                ) {
                    SongMenu(
                        song: song,
                        onGoToAlbum: song.albumId == nil ? nil : { goToAlbum(song) },
                        onGoToArtist: song.artistId == nil ? nil : { goToArtist(song) },
                        onAddToPlaylist: { showAddToPlaylist = song },
                        onDelete: { removeSong(song) },
                        deleteLabel: "Remove from Playlist"
                    )
                }
                Divider().background(.white.opacity(0.08))
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let count = vm.playlist.songCount {
                Text("\(count) songs")
            }
            if let dur = vm.playlist.duration {
                Text(formatDuration(dur))
            }
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.4))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600; let m = (seconds % 3600) / 60
        return h > 0 ? "\(h) hr \(m) min" : "\(m) min"
    }

    private func goToAlbum(_ song: Song) {
        guard let id = song.albumId else { return }
        Task {
            if let album = try? await appState.client?.album(id: id) { drillAlbum = album }
        }
    }

    private func goToArtist(_ song: Song) {
        guard let id = song.artistId else { return }
        Task {
            if let artist = try? await appState.client?.artist(id: id) { drillArtist = artist }
        }
    }

    private func removeSong(_ song: Song) {
        guard let idx = vm.songs.firstIndex(where: { $0.id == song.id }),
              let client = appState.client else { return }
        Task { await vm.removeSong(at: idx, client: client) }
    }
}
