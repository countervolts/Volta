import SwiftUI
import Observation

struct ArtistDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var vm: ArtistDetailViewModel
    @State private var drillAlbum: Album?
    @State private var addToPlaylistSong: Song? = nil
    @State private var toastMessage: String? = nil
    @State private var showBioSheet = false
    // local mirror of the VM's profile photo. updating @State guarantees a body
    // re-render (so the picture appears as soon as it loads, without needing the
    // user to interact with the page first).
    @State private var profileImage: UIImage? = nil
    @State private var scrollState = ArtistProfileScrollState()

    init(artist: Artist) {
        _vm = State(wrappedValue: ArtistDetailViewModel(artist: artist))
    }

    private var bg: Color {
        Color(ColorExtractor.backgroundVariant(of: vm.dominantColor))
    }

    private static let headerHeight: CGFloat = 380
    private static let legacyScrollSpace = "artist-scroll-space"

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let headerHeight = Self.headerHeight + proxy.safeAreaInsets.top

            ZStack(alignment: .top) {
                bg.ignoresSafeArea()

                ArtistProfileHeader(
                    width: width,
                    baseHeight: headerHeight,
                    bg: bg,
                    artistName: vm.displayArtist.name,
                    profileImage: profileImage ?? vm.artistImage,
                    fallbackAlbum: vm.artworkResolved ? vm.albums.first : nil,
                    dominantColor: vm.dominantColor,
                    scrollState: scrollState,
                    onFallbackImageLoaded: { vm.setDominantColor(ColorExtractor.dominantColor(from: $0)) }
                )

                artistScroll(headerHeight: headerHeight)

                if vm.isLoading && vm.albums.isEmpty {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if let msg = toastMessage {
                    VStack {
                        Spacer()
                        PlaybackActionToast(message: msg)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .padding(.bottom, 100)
                    }
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(Theme.colorScheme)
        .background(SwipeBackEnabler())
        .onAppear {
            scrollState.start()
        }
        .onDisappear {
            scrollState.stop()
        }
        .onChange(of: vm.artistImage) { _, img in profileImage = img }
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
        .sheet(isPresented: $showBioSheet) {
            ArtistBioSheet(
                artistName: vm.displayArtist.name,
                biography: vm.biography ?? ""
            )
        }
        .task { if let c = appState.client { await vm.load(client: c) } }
    }

    @ViewBuilder
    private func artistScroll(headerHeight: CGFloat) -> some View {
        if #available(iOS 18.0, *) {
            scrollContent(headerHeight: headerHeight, includeLegacyOffsetProbe: false)
                .onScrollGeometryChange(for: CGFloat.self) { geo in
                    geo.contentOffset.y + geo.contentInsets.top
                } action: { _, newValue in
                    updateScrollOffset(newValue)
                }
        } else {
            scrollContent(headerHeight: headerHeight, includeLegacyOffsetProbe: true)
                .coordinateSpace(name: Self.legacyScrollSpace)
                .onPreferenceChange(ArtistScrollOffsetPreferenceKey.self) { newValue in
                    updateScrollOffset(newValue)
                }
        }
    }

    private func scrollContent(headerHeight: CGFloat, includeLegacyOffsetProbe: Bool) -> some View {
        ScrollView {
            if includeLegacyOffsetProbe {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ArtistScrollOffsetPreferenceKey.self,
                        value: -geo.frame(in: .named(Self.legacyScrollSpace)).minY
                    )
                }
                .frame(height: 0)
            }

            VStack(spacing: 0) {
                Color.clear.frame(height: headerHeight)   // sits over the header
                artistActionRow
                topSongsSection
                albumsSection
                appearedOnSection
                similarArtistsSection
                aboutSection
                artistStatsSection
                Color.clear.frame(height: 120)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func updateScrollOffset(_ newValue: CGFloat) {
        scrollState.update(newValue)
    }

    // MARK: - Play / shuffle this artist

    @ViewBuilder
    private var artistActionRow: some View {
        if !vm.allSongs.isEmpty {
            HStack(spacing: 14) {
                Button { playArtist(shuffled: false) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: Symbols.play).font(.system(size: 16, weight: .bold))
                        Text("Play").font(.headline)
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)

                Button { playArtist(shuffled: true) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: Symbols.shuffle).font(.system(size: 16, weight: .semibold))
                        Text("Shuffle").font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .glassCapsule(tinted: true)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    private func playArtist(shuffled: Bool) {
        let songs = vm.allSongs
        guard !songs.isEmpty else { return }
        appState.audioPlayer.playArtist(shuffled ? songs.shuffled() : songs, artist: vm.displayArtist)
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
            Button {
                appState.audioPlayer.play(song: song)
            } label: {
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
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

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
                                        .frame(width: 130, height: 130)

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

    // MARK: - Appeared On (albums the artist is featured on, not their own)

    @ViewBuilder
    private var appearedOnSection: some View {
        if !vm.appearsOn.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeaderView("Appeared On")
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(vm.appearsOn) { album in
                            Button { drillAlbum = album } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    ArtworkView(coverArtID: album.coverArt, size: 300, cornerRadius: 8)
                                        .frame(width: 130, height: 130)

                                    Text(album.name)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                        .frame(width: 130, alignment: .leading)

                                    Text(album.displayArtist)
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.5))
                                        .lineLimit(1)
                                        .frame(width: 130, alignment: .leading)
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
        // genre is shown in the Stats section below, so About only carries the bio
        // (prevents the genre appearing twice on the profile)
        if let bio = vm.biography {
            VStack(alignment: .leading, spacing: 16) {
                Text("About \(vm.displayArtist.name)")
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 8) {
                    Text(bio)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(4)

                    Button { showBioSheet = true } label: {
                        Text("More")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.accent)
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

@MainActor
@Observable
private final class ArtistProfileScrollState {
    var offsetY: CGFloat = 0

    @ObservationIgnored private var pendingOffsetY: CGFloat = 0
    @ObservationIgnored private var throttler: VSyncThrottler?

    func start() {
        guard throttler == nil else { return }
        throttler = VSyncThrottler { [weak self] in
            guard let self else { return }
            offsetY = Self.pixelAligned(pendingOffsetY)
        }
    }

    func stop() {
        throttler?.invalidate()
        throttler = nil
    }

    func update(_ newValue: CGFloat) {
        guard abs(newValue - pendingOffsetY) > 0.5 else { return }
        pendingOffsetY = newValue
        if let throttler {
            throttler.schedule()
        } else {
            offsetY = Self.pixelAligned(newValue)
        }
    }

    private static func pixelAligned(_ value: CGFloat) -> CGFloat {
        let scale = UIScreen.main.scale
        return (value * scale).rounded() / scale
    }
}

private struct ArtistProfileHeader: View {
    let width: CGFloat
    let baseHeight: CGFloat
    let bg: Color
    let artistName: String
    let profileImage: UIImage?
    let fallbackAlbum: Album?
    let dominantColor: UIColor
    let scrollState: ArtistProfileScrollState
    let onFallbackImageLoaded: (UIImage) -> Void

    var body: some View {
        let stretch = max(0, -scrollState.offsetY)
        let shift = max(0, scrollState.offsetY)
        let headerHeight = baseHeight + stretch

        // Lives outside the ScrollView so only this small header redraws on scroll.
        ZStack(alignment: .bottomLeading) {
            headerImage
                .frame(width: width, height: headerHeight)
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [.clear, bg.opacity(0.6), bg],
                        startPoint: .init(x: 0.5, y: 0.35),
                        endPoint: .bottom
                    )
                }

            Text(artistName)
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .frame(width: width, height: headerHeight, alignment: .bottom)
        .offset(y: -shift)
        .transaction { $0.animation = nil }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var headerImage: some View {
        if let profileImage {
            Image(uiImage: profileImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let fallbackAlbum {
            ArtworkView(
                coverArtID: fallbackAlbum.coverArt,
                size: 800,
                cornerRadius: 0,
                onImageLoaded: onFallbackImageLoaded
            )
            .aspectRatio(1, contentMode: .fill)
        } else {
            Rectangle()
                .fill(Color(dominantColor).opacity(0.3))
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 80, weight: .light))
                        .foregroundStyle(.white.opacity(0.3))
                }
        }
    }
}

private struct ArtistScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ArtistBioSheet: View {
    @Environment(\.dismiss) private var dismiss
    let artistName: String
    let biography: String

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(biography)
                    .font(.body)
                    .foregroundStyle(Theme.primaryText)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("About \(artistName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(Theme.colorScheme)
    }
}

// MARK: - HTML stripper

extension String {
    // lightweight HTML > plain text. deliberately avoids NSAttributedString's
    // WebKit-backed parser: it's main-thread only and spins a nested run loop, so
    // calling it during a SwiftUI view update re-enters the AttributeGraph and
    // aborts the app (that was the artist-page crash).
    var strippingHTML: String {
        var result = ""
        result.reserveCapacity(count)
        var inTag = false
        for char in self {
            switch char {
            case "<": inTag = true
            case ">": inTag = false
            default: if !inTag { result.append(char) }
            }
        }
        return result.decodingHTMLEntities.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // decodes the handful of entities that turn up in artist bios
    private var decodingHTMLEntities: String {
        guard contains("&") else { return self }
        let map = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
                   "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&hellip;": "…",
                   "&mdash;": "—", "&ndash;": "–", "&rsquo;": "’", "&lsquo;": "‘",
                   "&ldquo;": "“", "&rdquo;": "”"]
        var s = self
        for (entity, char) in map { s = s.replacingOccurrences(of: entity, with: char) }
        return s
    }
}
