import SwiftUI
import PhotosUI

enum PlaylistSheet: Identifiable {
    case addToPlaylist(Song)
    case album(Album)
    case artist(Artist)
    case edit

    var id: String {
        switch self {
        case .addToPlaylist(let s): return "song-\(s.id)"
        case .album(let a):         return "album-\(a.id)"
        case .artist(let a):        return "artist-\(a.id)"
        case .edit:                 return "edit"
        }
    }
}

struct PlaylistDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var vm: PlaylistDetailViewModel
    @State private var activeSheet: PlaylistSheet? = nil
    @State private var toastMessage: String? = nil
    @State private var editText = ""
    @State private var editName = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedCover: UIImage?
    @AppStorage("showTrackArtwork") private var showTrackArtwork = true

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
            sheetContent(sheet)
        }
        .task { if let c = appState.client { await vm.load(client: c) } }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: PlaylistSheet) -> some View {
        switch sheet {
        case .addToPlaylist(let song):
            AddToPlaylistSheet(song: song, onAdded: { name in
                withAnimation { toastMessage = "Added to \(name)" }
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    withAnimation { toastMessage = nil }
                }
            })
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
            editSheet
        }
    }

    private var editSheet: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        HStack {
                            Spacer()
                            ZStack(alignment: .bottomTrailing) {
                                editCoverPreview
                                    .frame(width: 150, height: 150)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                                Image(systemName: "pencil.circle.fill")
                                    .font(.system(size: 28))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, Theme.accent)
                                    .padding(6)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
                Section("Name") {
                    TextField("Playlist name", text: $editName)
                }
                Section("Description") {
                    TextField("Add a description", text: $editText, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { activeSheet = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveEdits() }
                        .disabled(editName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        withAnimation { pickedCover = img }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var editCoverPreview: some View {
        if let pickedCover {
            Image(uiImage: pickedCover)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            PlaylistCover(playlist: vm.playlist, size: 400, cornerRadius: 14)
        }
    }

    private func openEdit() {
        editName = vm.playlist.name
        editText = vm.playlist.comment ?? ""
        pickedCover = nil
        pickerItem = nil
        activeSheet = .edit
    }

    private func saveEdits() {
        guard let client = appState.client else { return }
        if let cover = pickedCover {
            PlaylistCoverStore.shared.set(cover, for: vm.playlist.id)
        }
        let name = editName
        let comment = editText
        Task {
            await vm.update(name: name, comment: comment, client: client)
            activeSheet = nil
        }
    }

    private var artworkSection: some View {
        GeometryReader { geo in
            PlaylistCover(playlist: vm.playlist, size: 800, cornerRadius: 0,
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
            HStack(spacing: 10) {
                Text(vm.playlist.name)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                // small edit affordance right beside the title (replaces the old
                // top-right pencil) — opens the name/description/cover editor
                Button { openEdit() } label: {
                    Image(systemName: Symbols.edit)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .glassCircle()
                }
                .buttonStyle(.plain)
            }
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

    // mirrors the album action row: shuffle circle · white Play · download
    private var actionRow: some View {
        HStack(spacing: 14) {
            Button {
                let songs = vm.songs.shuffled()
                if !songs.isEmpty {
                    appState.audioPlayer.playQueue(songs, startIndex: 0, source: vm.playlist.name, playlist: vm.playlist)
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
                if !vm.songs.isEmpty {
                    appState.audioPlayer.playQueue(vm.songs, startIndex: 0, source: vm.playlist.name, playlist: vm.playlist)
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

            DownloadAlbumButton(songs: vm.songs)
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
            // defined separator between the action row and the first track
            Divider()
                .frame(height: 0.75)
                .overlay(.white.opacity(0.15))
                .padding(.bottom, 4)
            ForEach(Array(vm.songs.enumerated()), id: \.element.id) { i, song in
                TrackRow(
                    song: song,
                    index: i + 1,
                    isCurrentlyPlaying: appState.audioPlayer.currentSong?.id == song.id,
                    onTap: {
                        appState.audioPlayer.playQueue(vm.songs, startIndex: i, source: vm.playlist.name, playlist: vm.playlist)
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
                        onAddToPlaylist: { activeSheet = .addToPlaylist(song) },
                        onDelete: { removeSong(song) },
                        deleteLabel: "Remove from Playlist"
                    )
                }
                Divider().overlay(.white.opacity(0.14))
            }
        }
        .padding(.horizontal, 20)
        .simultaneousGesture(verticalPlaybackSwipe)
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
            if let album = try? await appState.client?.album(id: id) { activeSheet = .album(album) }
        }
    }

    private func goToArtist(_ song: Song) {
        guard let id = song.artistId else { return }
        Task {
            if let artist = try? await appState.client?.artist(id: id) { activeSheet = .artist(artist) }
        }
    }

    private func removeSong(_ song: Song) {
        guard let idx = vm.songs.firstIndex(where: { $0.id == song.id }),
              let client = appState.client else { return }
        Task { await vm.removeSong(at: idx, client: client) }
    }

    private func showToast(_ message: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { toastMessage = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toastMessage = nil }
        }
    }

    private var verticalPlaybackSwipe: some Gesture {
        DragGesture(minimumDistance: 80)
            .onEnded { value in
                guard abs(value.translation.height) > 180,
                      abs(value.translation.width) < 55 else { return }
                moveWithinPlaylist(delta: value.translation.height < 0 ? 1 : -1)
            }
    }

    private func moveWithinPlaylist(delta: Int) {
        guard let current = appState.audioPlayer.currentSong,
              let currentIndex = vm.songs.firstIndex(where: { $0.id == current.id }) else { return }
        let nextIndex = max(0, min(vm.songs.count - 1, currentIndex + delta))
        guard nextIndex != currentIndex else { return }
        appState.audioPlayer.playQueue(vm.songs, startIndex: nextIndex, source: vm.playlist.name, playlist: vm.playlist)
    }
}
