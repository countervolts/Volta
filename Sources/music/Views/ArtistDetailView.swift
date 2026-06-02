import SwiftUI

struct ArtistDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var vm: ArtistDetailViewModel
    @State private var drillAlbum: Album?
    @State private var addToPlaylistSong: Song? = nil
    @State private var toastMessage: String? = nil
    @State private var scrollOffset: CGFloat = 0

    init(artist: Artist) {
        _vm = State(wrappedValue: ArtistDetailViewModel(artist: artist))
    }

    private var bg: Color {
        Color(ColorExtractor.backgroundVariant(of: vm.dominantColor))
    }

    var body: some View {
        ZStack(alignment: .top) {
            bg.ignoresSafeArea()

            ScrollView {
                GeometryReader { geo in
                    Color.clear
                        .preference(key: ArtistScrollOffsetKey.self,
                                    value: geo.frame(in: .named("artistScroll")).minY)
                }
                .frame(height: 0)

                VStack(spacing: 0) {
                    headerSection
                    topSongsSection
                    albumsSection
                    similarArtistsSection
                    aboutSection
                    artistStatsSection
                    Color.clear.frame(height: 120)
                }
            }
            .coordinateSpace(name: "artistScroll")
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .onPreferenceChange(ArtistScrollOffsetKey.self) { value in
                scrollOffset = value
                // no dismiss — uses swipe-back like AlbumDetailView
            }

            if vm.isLoading && vm.albums.isEmpty {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

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
        .background(SwipeBackEnabler())
        .navigationDestination(item: $drillAlbum) { album in
            AlbumDetailView(album: album)
        }
        .sheet(item: $addToPlaylistSong) { song in
            AddToPlaylistSheet(song: song, onAdded: { name in
                withAnimation { toastMessage = "Added to \(name)" }
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    withAnimation { toastMessage = nil }
                }
            })
        }
        .task { if let c = appState.client { await vm.load(client: c) } }
    }

    // MARK: - Header (parallax: image grows when pulled down)

    private var headerSection: some View {
        // pulling up at the top (positive overscroll) zooms into the profile
        // picture: both the frame grows and the image scales up from its center.
        let extra = max(0, scrollOffset)
        return ZStack(alignment: .bottomLeading) {
            headerImage
                .frame(maxWidth: .infinity)
                .frame(height: 380 + extra)
                .scaleEffect(1 + extra / 320, anchor: .center)
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [.clear, bg.opacity(0.6), bg],
                        startPoint: .init(x: 0.5, y: 0.35),
                        endPoint: .bottom
                    )
                }

            Text(vm.displayArtist.name)
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .frame(height: 380)
    }

    @ViewBuilder
    private var headerImage: some View {
        if let ui = vm.artistImage {
            Image(uiImage: ui)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let firstAlbum = vm.albums.first {
            ArtworkView(
                coverArtID: firstAlbum.coverArt,
                size: 800,
                cornerRadius: 0,
                onImageLoaded: { vm.setDominantColor(ColorExtractor.dominantColor(from: $0)) }
            )
            .aspectRatio(1, contentMode: .fill)
        } else {
            Rectangle()
                .fill(Color(vm.dominantColor).opacity(0.3))
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 80, weight: .light))
                        .foregroundStyle(.white.opacity(0.3))
                }
        }
    }

    // MARK: - Top Songs (compact rows, horizontal peek — next column shows beside)

    private static let rowHeight: CGFloat = 52
    private static let pageSize = 5

    @ViewBuilder
    private var topSongsSection: some View {
        if !vm.topSongs.isEmpty {
            let pages = stride(from: 0, to: vm.topSongs.count, by: Self.pageSize).map { start in
                Array(vm.topSongs[start..<min(start + Self.pageSize, vm.topSongs.count)])
            }
            let pageH = CGFloat(Self.pageSize) * Self.rowHeight
            let multi = pages.count > 1

            VStack(alignment: .leading, spacing: 0) {
                SectionHeaderView("Top Songs")
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(pages.indices, id: \.self) { pageIdx in
                            VStack(spacing: 0) {
                                ForEach(Array(pages[pageIdx].enumerated()), id: \.element.id) { i, song in
                                    compactTopSongRow(song: song, index: pageIdx * Self.pageSize + i + 1)
                                    if i < pages[pageIdx].count - 1 {
                                        Divider().background(.white.opacity(0.06)).padding(.leading, 60)
                                    }
                                }
                            }
                            .frame(height: pageH, alignment: .top)
                            .containerRelativeFrame(
                                .horizontal,
                                count: multi ? 8 : 1,
                                span: multi ? 7 : 1,
                                spacing: 12
                            )
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 20)
                }
                .scrollTargetBehavior(.viewAligned)
                .frame(height: pageH)
            }
            .padding(.bottom, 8)
        }
    }

    private func compactTopSongRow(song: Song, index: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(index)")
                .font(.system(size: 12, weight: .regular).monospacedDigit())
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 16, alignment: .center)

            ArtworkView(coverArtID: song.coverArt, size: 80, cornerRadius: 4)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(song.title)
                    .font(.subheadline)
                    .foregroundStyle(appState.audioPlayer.currentSong?.id == song.id ? Theme.accent : .white)
                    .lineLimit(1)
                if let album = song.album {
                    Text(album)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)

            if let dur = song.duration {
                Text(String(format: "%d:%02d", dur / 60, dur % 60))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.35))
            }

            SongMenu(
                song: song,
                onGoToAlbum: song.albumId == nil ? nil : { goToAlbum(song) },
                onAddToPlaylist: { addToPlaylistSong = song }
            ) {
                Image(systemName: Symbols.more)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
        }
        .frame(height: Self.rowHeight)
        .contentShape(Rectangle())
        .onTapGesture { appState.audioPlayer.play(song: song) }
    }

    // MARK: - Albums

    @ViewBuilder
    private var albumsSection: some View {
        if !vm.albums.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeaderView("Albums")
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(vm.albums) { album in
                            Button { drillAlbum = album } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    ArtworkView(coverArtID: album.coverArt, size: 300, cornerRadius: 8)
                                        .aspectRatio(1, contentMode: .fit)
                                        .frame(width: 130)

                                    Text(album.name)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                        .frame(width: 130, alignment: .leading)

                                    if let year = album.year {
                                        Text(String(year))
                                            .font(.caption2)
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Similar Artists

    @ViewBuilder
    private var similarArtistsSection: some View {
        if !vm.similarArtists.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeaderView("Similar Artists")
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(vm.similarArtists) { artist in
                            NavigationLink(destination: ArtistDetailView(artist: artist)) {
                                VStack(spacing: 8) {
                                    ArtworkView(coverArtID: artist.coverArt, size: 200, cornerRadius: 50)
                                        .frame(width: 80, height: 80)
                                        .clipShape(Circle())
                                    Text(artist.name)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(width: 80)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - About

    @ViewBuilder
    private var aboutSection: some View {
        let bio = vm.info?.biography?.strippingHTML
        let genre = vm.albums.compactMap(\.genre).first
        if bio != nil || genre != nil {
            VStack(alignment: .leading, spacing: 16) {
                Text("About \(vm.displayArtist.name)")
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                if let bio {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(bio)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(vm.isDescriptionExpanded ? nil : 4)
                            .animation(.easeInOut(duration: 0.3), value: vm.isDescriptionExpanded)

                        Button { vm.toggleBio() } label: {
                            Text(vm.isDescriptionExpanded ? "Less" : "More")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }

                if let genre {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GENRE")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.4))
                        Text(genre)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Artist Stats

    @ViewBuilder
    private var artistStatsSection: some View {
        let albumCount = vm.albums.count
        let totalPlays = vm.albums.compactMap(\.playCount).reduce(0, +)
        let genres = Array(Set(vm.albums.compactMap(\.genre))).sorted()

        if albumCount > 0 {
            VStack(alignment: .leading, spacing: 16) {
                Text("Stats")
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    statsCell(value: "\(albumCount)", label: albumCount == 1 ? "Album" : "Albums")
                    if totalPlays > 0 {
                        statsCell(value: formatPlays(totalPlays), label: "Total Plays")
                    }
                    if let year = vm.albums.compactMap(\.year).min() {
                        statsCell(value: "\(year)", label: "Active Since")
                    }
                    if let latest = vm.albums.compactMap(\.year).max(),
                       let oldest = vm.albums.compactMap(\.year).min(), latest != oldest {
                        statsCell(value: "\(oldest)–\(latest)", label: "Years Active")
                    }
                }

                if !genres.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GENRES")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.4))
                        Text(genres.joined(separator: " · "))
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
    }

    private func statsCell(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func formatPlays(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1_000_000)
            : n >= 1_000 ? String(format: "%.1fK", Double(n) / 1_000)
            : "\(n)"
    }

    private func goToAlbum(_ song: Song) {
        guard let id = song.albumId else { return }
        Task {
            if let album = try? await appState.client?.album(id: id) { drillAlbum = album }
        }
    }
}

// MARK: - Scroll offset preference key

private struct ArtistScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - HTML stripper

extension String {
    var strippingHTML: String {
        guard let data = data(using: .utf8) else { return self }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var result = ""
        var inTag = false
        for char in self {
            if char == "<" { inTag = true }
            else if char == ">" { inTag = false }
            else if !inTag { result.append(char) }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
