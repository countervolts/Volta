import SwiftUI
import UIKit

enum iPadDetailPanel: String, CaseIterable {
    case songs = "Songs"
    case lyrics = "Lyrics"
    case queue = "Queue"
}

struct AlbumDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var vm: AlbumDetailViewModel
    @State private var showAddToPlaylist: Song? = nil
    @State private var toastMessage: String? = nil
    @State private var drillAlbum: Album? = nil
    @State private var drillArtist: Artist? = nil
    @State private var showAlbumLosslessInfo = false
    @State private var animatedCover: UIImage?

    // when opened from an artist profile, the animated header gets the same
    // pull-to-zoom (stretchy) behaviour the artist profile header has
    private let fromArtist: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var iPadPanel: iPadDetailPanel = .songs

    init(album: Album, fromArtist: Bool = false) {
        _vm = State(wrappedValue: AlbumDetailViewModel(album: album))
        self.fromArtist = fromArtist
    }

    private var bg: Color {
        Color(ColorExtractor.backgroundVariant(of: vm.dominantColor))
    }

    private var playFg: Color {
        let c = vm.dominantColor
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(UIColor(hue: h, saturation: min(s, 1), brightness: max(0.25, min(b * 0.72, 0.65)), alpha: 1))
    }

    var body: some View {
        ZStack(alignment: .top) {
            bg.ignoresSafeArea()
            if sizeClass == .regular {
                iPadLayout
            } else {
                phoneScrollView
            }
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
        .navigationDestination(item: $drillArtist) { artist in
            ArtistDetailView(artist: artist)
        }
        .sheet(item: $showAddToPlaylist) { song in
            AddToPlaylistSheet(song: song, onAdded: { name in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    toastMessage = "Added to \(name)"
                }
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    withAnimation { toastMessage = nil }
                }
            })
        }
        .task {
            if DeveloperExperiments.constrainedConcurrency(default: 2) == 1 {
                if let c = appState.client { await vm.load(client: c) }
                await loadAnimatedCover()
            } else {
                // Fetch animated cover alongside the song list.
                async let cover: Void = loadAnimatedCover()
                if let c = appState.client { await vm.load(client: c) }
                await cover
            }
        }
    }

    // Album detail gets live artwork; grids stay static.
    private func loadAnimatedCover() async {
        guard LiveArtworkSettings.shouldShowAnimatedArtwork,
              LiveArtworkSettings.animateAlbumHeaders,
              let client = appState.client,
              let url = client.coverArtURL(id: vm.album.coverArt) else { return }
        guard let image = await ArtworkLoader.shared.animatedImage(for: url) else { return }
        animatedCover = image
        if let first = image.images?.first {
            vm.setDominantColor(ColorExtractor.dominantColor(from: first))
        }
    }

    private var phoneScrollView: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let animated = animatedCover {
                    animatedHeader(animated)
                } else {
                    artworkSection
                    infoSection
                    actionRow
                }
                descriptionSection
                trackList
                footer
                moreBySameArtist
                Color.clear.frame(height: 120)
            }
        }
        .scrollIndicators(.hidden)
        .coordinateSpace(name: Self.scrollSpace)
        // Full-bleed animated header.
        .ignoresSafeArea(.container, edges: animatedCover != nil ? .top : [])
    }

    private static let scrollSpace = "albumScroll"

    // Taller animated header with the normal album controls over it.
    private func animatedHeader(_ animated: UIImage) -> some View {
        // Stretch on pull-down when opened from an artist profile.
        GeometryReader { geo in
            let stretch = fromArtist ? max(0, geo.frame(in: .named(Self.scrollSpace)).minY) : 0
            ZStack(alignment: .bottom) {
                AnimatedImageView(image: animated)
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.38),
                        .init(color: bg.opacity(0.55), location: 0.62),
                        .init(color: bg.opacity(0.9), location: 0.82),
                        .init(color: bg, location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                VStack(spacing: 0) {
                    infoSection
                    actionRow
                }
            }
            .frame(width: geo.size.width, height: geo.size.height + stretch)
            .clipped()
            .offset(y: -stretch)
        }
        .aspectRatio(1 / 1.35, contentMode: .fit)
    }

    private var iPadLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    artworkSection
                    infoSection
                    Color.clear.frame(height: 20)
                }
            }
            .scrollIndicators(.hidden)
            .frame(width: 340)

            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(width: 0.5)

            VStack(spacing: 0) {
                actionRow

                Picker("", selection: $iPadPanel) {
                    ForEach(iPadDetailPanel.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

                Divider().overlay(.white.opacity(0.12))

                switch iPadPanel {
                case .songs:
                    ScrollView {
                        descriptionSection
                        trackList
                        footer
                        moreBySameArtist
                        Color.clear.frame(height: 100)
                    }
                    .scrollIndicators(.hidden)
                case .lyrics:
                    LyricsViewWithState()
                case .queue:
                    QueueView()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Artwork

    @ViewBuilder
    private var artworkSection: some View {
        if let animated = animatedCover, sizeClass == .regular {
            // iPad keeps the card layout; only the artwork inside animates
            // (compact animated covers use animatedHeader instead)
            ZStack { AnimatedImageView(image: animated) }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 36)
                .shadow(color: .black.opacity(0.45), radius: 28, x: 0, y: 10)
                .padding(.top, 32)
        } else {
            ArtworkView(coverArtID: vm.album.coverArt, size: 800, cornerRadius: 14,
                        onImageLoaded: { image in
                            let color = ColorExtractor.dominantColor(from: image)
                            vm.setDominantColor(color)
                        })
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, 36)
                .shadow(color: .black.opacity(0.45), radius: 28, x: 0, y: 10)
                .padding(.top, 32)
        }
    }

    // MARK: - Info

    private var infoSection: some View {
        VStack(spacing: 6) {
            Text(vm.album.name)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Button {
                if let aid = vm.album.artistId {
                    drillArtist = Artist(id: aid, name: vm.album.displayArtist,
                                        coverArt: nil, albumCount: nil,
                                        artistImageUrl: nil, starred: nil, album: nil)
                }
            } label: {
                Text(vm.album.displayArtist)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                if let genre = vm.album.genre {
                    Text(genre).foregroundStyle(.white.opacity(0.55))
                }
                if let year = vm.album.year {
                    Text("·").foregroundStyle(.white.opacity(0.3))
                    Text(String(year)).foregroundStyle(.white.opacity(0.55))
                }
                if !vm.songs.isEmpty {
                    Text("·").foregroundStyle(.white.opacity(0.3))
                    Button { showAlbumLosslessInfo = true } label: {
                        Label(vm.isLossless ? "Lossless" : "Lossy",
                              systemImage: vm.isLossless ? "waveform" : "music.note")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showAlbumLosslessInfo) {
                        AlbumQualityInsightPopover(songs: vm.songs)
                            .presentationCompactAdaptation(.popover)
                    }
                }
            }
            .font(.footnote)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: 14) {
            Button {
                let songs = vm.songs
                if !songs.isEmpty {
                    appState.audioPlayer.playQueue(songs.shuffled(), startIndex: 0, source: vm.album.name, album: vm.album)
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
                let songs = vm.songs
                if !songs.isEmpty {
                    appState.audioPlayer.playQueue(songs, startIndex: 0, source: vm.album.name, album: vm.album)
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: Symbols.play)
                        .font(.system(size: 14, weight: .bold))
                    Text("Play")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(playFg)
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

    // MARK: - Description

    @ViewBuilder
    private var descriptionSection: some View {
        if let desc = vm.album.comment, !desc.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(desc)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(vm.isDescriptionExpanded ? nil : 3)
                    .animation(.easeInOut(duration: 0.3), value: vm.isDescriptionExpanded)

                Button {
                    vm.toggleDescription()
                } label: {
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

    // MARK: - Track list

    private var trackList: some View {
        VStack(spacing: 0) {
            Divider()
                .frame(height: 0.75)
                .overlay(.white.opacity(0.15))
                .padding(.bottom, 4)
            let discs = vm.discNumbers
            if discs.count > 1 {
                ForEach(discs, id: \.self) { disc in
                    discHeader(disc)
                    trackRows(vm.songs(forDisc: disc))
                }
            } else {
                trackRows(vm.songs)
            }
        }
        .padding(.horizontal, 20)
        .overlay(alignment: .leading) { playbackSwipeGutter }
    }

    private func discHeader(_ disc: Int) -> some View {
        Text("Disc \(disc)")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white.opacity(0.45))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }

    private func trackRows(_ songs: [Song]) -> some View {
        ForEach(Array(songs.enumerated()), id: \.element.id) { i, song in
            TrackRow(
                song: song,
                index: song.track ?? (i + 1),
                isCurrentlyPlaying: appState.audioPlayer.currentSong?.id == song.id,
                onTap: {
                    if let idx = vm.songs.firstIndex(where: { $0.id == song.id }) {
                        appState.audioPlayer.playQueue(vm.songs, startIndex: idx, source: vm.album.name, album: vm.album)
                    }
                },
                onSwipePlayNext: {
                    appState.audioPlayer.playNext(song)
                }
            ) {
                SongMenu(
                    song: song,
                    onGoToArtist: song.artistId == nil ? nil : { goToArtist(song) },
                    onAddToPlaylist: { showAddToPlaylist = song }
                )
            }
            Divider().overlay(.white.opacity(0.14))
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let date = vm.album.createdDate {
                Text(date.formatted(date: .long, time: .omitted))
            }
            if let count = vm.album.songCount {
                Text("\(count) songs")
            }
            if let dur = vm.album.duration {
                Text(formatDuration(dur))
            }
            if let label = vm.album.recordLabel {
                Text(label)
            }
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.4))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }

    // MARK: - More by artist

    @ViewBuilder
    private var moreBySameArtist: some View {
        if !vm.moreBySameArtist.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeaderView("More by \(vm.album.displayArtist)")
                    .padding(.horizontal, 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(vm.moreBySameArtist) { album in
                            Button {
                                drillAlbum = album
                            } label: {
                                MediaCard(item: MediaItem(album: album))
                                    .frame(width: 130)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 24)
            .navigationDestination(item: $drillAlbum) { album in
                AlbumDetailView(album: album)
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h) hr \(m) min" }
        return "\(m) min"
    }

    private func goToArtist(_ song: Song) {
        guard let id = song.artistId else { return }
        Task {
            if let artist = try? await appState.client?.artist(id: id) { drillArtist = artist }
        }
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
                moveWithinAlbum(delta: value.translation.height < 0 ? 1 : -1)
            }
    }

    private var playbackSwipeGutter: some View {
        Color.clear
            .frame(width: 56)
            .contentShape(Rectangle())
            .gesture(verticalPlaybackSwipe)
    }

    private func moveWithinAlbum(delta: Int) {
        guard let current = appState.audioPlayer.currentSong,
              let currentIndex = vm.songs.firstIndex(where: { $0.id == current.id }) else { return }
        let nextIndex = max(0, min(vm.songs.count - 1, currentIndex + delta))
        guard nextIndex != currentIndex else { return }
        appState.audioPlayer.playQueue(vm.songs, startIndex: nextIndex, source: vm.album.name, album: vm.album)
    }
}

// MARK: - Download button (shared by album + playlist detail)

struct DownloadAlbumButton: View {
    let songs: [Song]
    @State private var overallState: DownloadState = .notDownloaded

    var body: some View {
        Button {
            for song in songs where DownloadService.shared.state(for: song) == .notDownloaded {
                DownloadService.shared.download(song: song)
            }
        } label: {
            ZStack {
                switch overallState {
                case .notDownloaded:
                    Image(systemName: Symbols.download)
                case .downloading(let p):
                    ZStack {
                        Circle().stroke(.white.opacity(0.2), lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: p)
                            .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 20, height: 20)
                case .downloaded:
                    Image(systemName: Symbols.downloaded)
                        .foregroundStyle(.green)
                }
            }
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .glassCircle()
        }
        .buttonStyle(.plain)
        .onAppear { updateState() }
        .onChange(of: songs) { _, _ in updateState() }
    }

    private func updateState() {
        let states = songs.map { DownloadService.shared.state(for: $0) }
        if states.allSatisfy({ $0 == .downloaded }) {
            overallState = .downloaded
        } else if states.contains(where: { if case .downloading = $0 { return true }; return false }) {
            let total = states.compactMap { s -> Double? in
                if case .downloading(let p) = s { return p }
                return nil
            }.reduce(0, +) / Double(max(1, states.count))
            overallState = .downloading(progress: total)
        } else {
            overallState = .notDownloaded
        }
    }
}

// MARK: - Add to playlist sheet

struct AddToPlaylistSheet: View {
    let song: Song
    var onAdded: (String) -> Void
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var playlists: [Playlist] = []
    @State private var confirming: Playlist? = nil
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    ForEach(playlists) { pl in
                        Button {
                            confirming = pl
                        } label: {
                            HStack(spacing: 12) {
                                ArtworkView(coverArtID: pl.coverArt, size: 100, cornerRadius: 6)
                                    .frame(width: 44, height: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pl.name).font(.body).foregroundStyle(.primary)
                                    if let n = pl.songCount {
                                        Text("\(n) songs").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Add to playlist?", isPresented: Binding(
                get: { confirming != nil },
                set: { if !$0 { confirming = nil } }
            )) {
                Button("Add") {
                    if let pl = confirming, let client = appState.client {
                        Task {
                            do {
                                try await client.addToPlaylist(playlistID: pl.id, songID: song.id)
                                await PlaylistBackupStore.shared.backup(playlistID: pl.id, client: client)
                                onAdded(pl.name)
                                dismiss()
                            } catch {
                                AppLogger.shared.log("Add to playlist failed: \(error.localizedDescription)", category: .other, level: .error)
                            }
                        }
                    }
                }
                Button("Cancel", role: .cancel) { confirming = nil }
            } message: {
                Text("Add \"\(song.title)\" to \"\(confirming?.name ?? "")\"?")
            }
        }
        .task {
            if let client = appState.client {
                playlists = (try? await client.playlists()) ?? []
            }
            isLoading = false
        }
    }
}

// MARK: - Album quality insight popover

private struct AlbumQualityInsightPopover: View {
    let songs: [Song]

    private var losslessCount: Int { songs.filter(\.isLossless).count }
    private var hiResCount: Int { songs.filter(\.isHiResLossless).count }
    private var formats: [String] {
        let suffixes = songs.compactMap { $0.suffix?.uppercased() }
        return Array(Set(suffixes)).sorted()
    }
    private var sampleRates: [Int] {
        Array(Set(songs.compactMap(\.samplingRate))).sorted()
    }
    private var bitDepths: [Int] {
        Array(Set(songs.compactMap(\.bitDepth))).sorted()
    }

    private var headline: String {
        if losslessCount == 0 { return "Lossy Album" }
        if losslessCount == songs.count {
            return hiResCount == songs.count ? "Hi-Res Lossless Album" : "Lossless Album"
        }
        return "Mixed Quality Album"
    }

    private var summary: String {
        if losslessCount == 0 {
            return "All \(songs.count) tracks use a lossy format."
        }
        if losslessCount == songs.count {
            return hiResCount == songs.count
                ? "All \(songs.count) tracks are hi-res lossless."
                : "All \(songs.count) tracks are lossless."
        }
        return "\(losslessCount) of \(songs.count) tracks are lossless; the rest use a lossy format."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: losslessCount == songs.count ? "waveform" : "music.note")
                Text(headline).font(.headline)
            }
            .padding(.bottom, 2)

            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !formats.isEmpty { detailRow("Formats", formats.joined(separator: ", ")) }
            if !sampleRates.isEmpty {
                detailRow("Sample Rates", sampleRates.map { String(format: "%.1f kHz", Double($0) / 1000) }.joined(separator: ", "))
            }
            if !bitDepths.isEmpty {
                detailRow("Bit Depths", bitDepths.map { "\($0)-bit" }.joined(separator: ", "))
            }
            if hiResCount > 0 { detailRow("Hi-Res Tracks", "\(hiResCount) of \(songs.count)") }
        }
        .padding(16)
        .frame(minWidth: 240)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 24)
            Text(value).fontWeight(.medium)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
    }
}
