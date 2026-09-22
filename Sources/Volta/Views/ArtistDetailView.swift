import SwiftUI
import Combine

struct ArtistDetailView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm: ArtistDetailViewModel
    @StateObject private var hiddenAlbums = HiddenAlbumStore.shared
    @StateObject private var downloads = DownloadService.shared
    @State private var drillAlbum: Album?
    @State private var addToPlaylistSong: Song? = nil
    @State private var toastMessage: String? = nil
    @State private var showBioSheet = false
    // Local profile-photo mirror.
    @State private var profileImage: UIImage? = nil
    @StateObject private var scrollState = ArtistProfileScrollState()
    /// Window-level (not view-level) top inset, so the floating buttons sit in
    /// the same place no matter which screen pushed this profile.
    @State private var windowTopInset: CGFloat?
#if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
#endif
    @Environment(\.dismiss) private var dismiss

    init(artist: Artist) {
        _vm = StateObject(wrappedValue: ArtistDetailViewModel(artist: artist))
    }

    private var bg: Color {
        Color(ColorExtractor.backgroundVariant(of: vm.dominantColor))
    }

    /// Feathered page backdrop, drawn only BELOW the hero. Making it start at the
    /// header's bottom edge is what removes the seam: the hero's own fade lands
    /// on exactly `bg`, and this gradient's first stop is that same `bg`, so the
    /// two meet on an identical colour instead of jumping to an already-darkened
    /// tint (the previous seam).
    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: ColorExtractor.featheredBackgroundColors(for: vm.dominantColor),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var showsYonkagorFish: Bool {
        vm.displayArtist.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare("Yonkagor") == .orderedSame
    }

    private static let headerHeight: CGFloat = 380
    private static let legacyScrollSpace = "artist-scroll-space"

    var body: some View {
        // The inner reader ignores the top safe area so the hero photo can bleed
        // under the status bar; the outer one still reports the real inset for
        // the floating back / menu buttons.
        GeometryReader { safeProxy in
            GeometryReader { proxy in
                artistContent(
                    topInset: windowTopInset ?? safeProxy.safeAreaInsets.top,
                    proxy: proxy
                )
            }
            .ignoresSafeArea(edges: .top)
        }
        .background(
            WindowTopInsetReader { value in
                if windowTopInset == nil || abs((windowTopInset ?? 0) - value) > 0.5 {
                    windowTopInset = value
                }
            }
            .allowsHitTesting(false)
        )
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(Theme.colorScheme)
        .background(SwipeBackEnabler())
        .onAppear {
            if !RuntimeCompatibility.isIOS16 {
                scrollState.start()
            }
        }
        .onDisappear {
            if !RuntimeCompatibility.isIOS16 {
                scrollState.stop()
            }
        }
        .onChangeCompat(of: vm.artistImage) { _, img in profileImage = img }
        .navigationDestinationItemCompat(item: $drillAlbum) { album in
            AlbumDetailView(album: album, fromArtist: true)
        }
        .sheet(item: $addToPlaylistSong) { song in
            AddToPlaylistSheet(song: song, onAdded: { name in
                withAnimation { toastMessage = L(.toast_added_to, name) }
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
        .task(id: "\(appState.isOfflineMode)|\(appState.client == nil)|\(downloads.downloadedRevision)") {
            await loadProfile()
        }
        .onChangeCompat(of: hiddenAlbums.revision) { _, _ in
            Task { await loadProfile() }
        }
    }

    private func loadProfile() async {
        if appState.isOfflineMode || appState.client == nil {
            await vm.loadOffline()
        } else if let client = appState.client {
            await vm.load(client: client)
        }
    }

    @ViewBuilder
    private func artistContent(topInset: CGFloat, proxy: GeometryProxy) -> some View {
        let width = proxy.size.width
        let compactLandscape = width > proxy.size.height
        let baseHeaderHeight = compactLandscape
            ? min(Self.headerHeight, max(180, proxy.size.height * 0.52))
            : Self.headerHeight
        let headerHeight = baseHeaderHeight + topInset

        ZStack(alignment: .top) {
            // Solid tint behind the header, and the feathered gradient starting
            // exactly at the header's bottom edge so the join is colour-matched.
            bg.ignoresSafeArea()
            VStack(spacing: 0) {
                Color.clear.frame(height: headerHeight)
                backgroundGradient
            }
            .ignoresSafeArea()

            if !RuntimeCompatibility.isIOS16 {
                ArtistProfileHeader(
                    width: width,
                    baseHeight: headerHeight,
                    bg: bg,
                    profileImage: profileImage ?? vm.artistImage,
                    fallbackAlbum: vm.artworkResolved ? vm.albums.first : nil,
                    dominantColor: vm.dominantColor,
                    scrollState: scrollState,
                    onFallbackImageLoaded: { vm.setDominantColor(ColorExtractor.dominantColor(from: $0)) }
                )
            }

            artistScroll(width: width, headerHeight: headerHeight)

            if showsYonkagorFish {
                YonkagorFishOverlay()
                    // Keep the Canvas out of the status-bar area. On this profile,
                    // extending the animated layer into that area makes iOS apply an
                    // unwanted glass blur over the top of the header.
                    .frame(
                        width: width,
                        height: max(0, proxy.size.height - topInset)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if vm.isLoading && vm.albums.isEmpty {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            artistNavOverlay(topInset: topInset)
        }
        // Anchored to the container's bottom edge (just above the mini player,
        // which already removes its own height from the safe area).
        .overlay(alignment: .bottom) {
            if let msg = toastMessage {
                PlaybackActionToast(message: msg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Floating nav (back button + scroll-aware compact title)

    @ViewBuilder
    private func artistNavOverlay(topInset: CGFloat) -> some View {
        let scrolled = scrollState.offsetY
        let collapseStart: CGFloat = 180
        let collapseEnd: CGFloat = 280
        let titleProgress = min(1, max(0, (scrolled - collapseStart) / (collapseEnd - collapseStart)))

        ZStack(alignment: .top) {
            if titleProgress > 0 {
                ZStack(alignment: .bottom) {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(titleProgress)
                    Text(vm.displayArtist.name)
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                        .padding(.bottom, 8)
                        .opacity(titleProgress)
                }
                .frame(height: topInset + 44)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)
                .transition(.opacity)
            }

            HStack {
                Button { dismissArtist() } label: {
                    Image(systemName: Symbols.back)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .glassCircle()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L(.action_done))

                Spacer(minLength: 0)

                Menu {
                    Button {
                        shuffleArtist()
                    } label: {
                        Label(L(.action_shuffle), systemImage: Symbols.shuffle)
                    }
                    Button {
                        addAllToQueue()
                    } label: {
                        Label(L(.action_add_to_queue), systemImage: Symbols.queue)
                    }
                } label: {
                    Image(systemName: Symbols.more)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .glassCircle()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L(.action_more))
            }
            .padding(.horizontal, 16)
            .padding(.top, topInset + 4)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: titleProgress > 0)
    }

    private func dismissArtist() {
        dismiss()
    }

    private func addAllToQueue() {
        let songs = vm.allSongs
        guard !songs.isEmpty else { return }
        appState.audioPlayer.addToQueue(songs)
        withAnimation { toastMessage = L(.notif_added_to_queue) }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toastMessage = nil }
        }
    }

    @ViewBuilder
    private func artistScroll(width: CGFloat, headerHeight: CGFloat) -> some View {
        if RuntimeCompatibility.isIOS16 {
            ios16ScrollContent(width: width, headerHeight: headerHeight)
        } else if #available(iOS 18.0, *) {
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
                .frame(height: 1)
                .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                Color.clear.frame(height: max(0, headerHeight - (includeLegacyOffsetProbe ? 1 : 0)))   // sits over the header
                artistBodySections
            }
        }
        .scrollIndicators(.hidden)
    }

    private func ios16ScrollContent(width: CGFloat, headerHeight: CGFloat) -> some View {
        ScrollView {
            IOS16ArtistProfileHeader(
                width: width,
                baseHeight: headerHeight,
                scrollSpaceName: Self.legacyScrollSpace,
                bg: bg,
                profileImage: profileImage ?? vm.artistImage,
                fallbackAlbum: vm.artworkResolved ? vm.albums.first : nil,
                dominantColor: vm.dominantColor,
                onFallbackImageLoaded: { vm.setDominantColor(ColorExtractor.dominantColor(from: $0)) }
            )
            .frame(height: headerHeight)

            artistBodySections
        }
        .coordinateSpace(name: Self.legacyScrollSpace)
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var artistBodySections: some View {
        heroIdentitySection
        featuredReleaseSection
        topSongsSection
        accumulatedSongsSection
        likedSongsSection
        albumsSection
        singlesSection
        appearedOnSection
        similarArtistsSection
        artistStatsSection
        Color.clear.frame(height: 120)
    }

    private func updateScrollOffset(_ newValue: CGFloat) {
        scrollState.update(newValue)
    }

    // MARK: - Hero identity (name + Apple Music action row)

    @ViewBuilder
    private var heroIdentitySection: some View {
        VStack(spacing: 14) {
            Text(vm.displayArtist.name)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                .padding(.horizontal, 24)

            artistActionRow
        }
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    // MARK: - Play / shuffle / favorite / info

    @ViewBuilder
    private var artistActionRow: some View {
        if !vm.allSongs.isEmpty {
            HStack(spacing: 26) {
                Button { showBioSheet = true } label: {
                    Image(systemName: Symbols.info)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .glassCircle()
                }
                .buttonStyle(.plain)
                .disabled(vm.biography == nil)
                .opacity(vm.biography == nil ? 0.45 : 1)
                .accessibilityLabel(L(.action_artist_info))

                Button { playArtist(shuffled: false) } label: {
                    Image(systemName: Symbols.play)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(playFg)
                        .frame(width: 68, height: 68)
                        .background(.white, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L(.action_play))

                Button { toggleFavorite() } label: {
                    Image(systemName: vm.isStarred ? Symbols.star : Symbols.starEmpty)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(vm.isStarred ? Theme.accent : .white)
                        .frame(width: 46, height: 46)
                        .glassCircle()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L(vm.isStarred ? .action_unfavorite : .action_favorite))
            }
            .padding(.horizontal, 20)
        }
    }

    /// Readable foreground for the white play button, derived from the artist's
    /// dominant color (never too bright, never pure black).
    private var playFg: Color {
        let c = vm.dominantColor
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(UIColor(hue: h, saturation: min(s, 1), brightness: max(0.25, min(b * 0.72, 0.65)), alpha: 1))
    }

    private func playArtist(shuffled: Bool) {
        let songs = vm.allSongs
        guard !songs.isEmpty else { return }
        appState.audioPlayer.playArtist(shuffled ? songs.shuffled() : songs, artist: vm.displayArtist)
    }

    private func toggleFavorite() {
        let nowStarred = !vm.isStarred
        vm.setStarred(nowStarred)
        withAnimation { toastMessage = L(nowStarred ? .notif_added_to_favorites : .notif_removed_from_favorites) }
        Task {
            if nowStarred {
                try? await appState.client?.star(id: vm.displayArtist.id)
            } else {
                try? await appState.client?.unstar(id: vm.displayArtist.id)
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toastMessage = nil }
        }
    }

    private func shuffleArtist() { playArtist(shuffled: true) }

    // MARK: - Featured release card

    @ViewBuilder
    private var featuredReleaseSection: some View {
        if let album = vm.latestRelease {
            VStack(alignment: .leading, spacing: 0) {
                Text(L(.artist_featured))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                Button { drillAlbum = album } label: {
                    HStack(spacing: 14) {
                        ArtworkView(
                            coverArtID: album.coverArt,
                            size: 300,
                            cornerRadius: 6,
                            cropsImageToSquare: true
                        )
                        .frame(width: 74, height: 74)

                        VStack(alignment: .leading, spacing: 3) {
                            if let eyebrow = featuredEyebrow(album) {
                                Text(eyebrow)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .lineLimit(1)
                            }
                            Text(album.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(L(.home_song_count, album.songCount ?? 0))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: Symbols.play)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .glassCircle()
                    }
                    .padding(12)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.white.opacity(0.06), lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .albumContextMenu(album)
                .padding(.horizontal, 20)
                .accessibilityLabel(L(.artist_latest_release))
            }
            .padding(.top, 12)
        }
    }

    private func featuredEyebrow(_ album: Album) -> String? {
        let isSingle = (album.songCount ?? album.song?.count ?? 0) <= 1
        let kind = isSingle ? L(.artist_singles) : L(.media_albums)
        if let year = album.year { return "\(kind) · \(year)" }
        return album.createdDate.map { "\(kind) · \(Self.cardDateFormatter.string(from: $0))" }
    }

    private static let cardDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    // MARK: - All songs across albums

    @ViewBuilder
    private var accumulatedSongsSection: some View {
        let songs = vm.visibleAccumulatedSongs
        if !songs.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeaderView(
                    L(.media_songs),
                    onSeeAll: vm.hasMoreAccumulated
                        ? { withAnimation(.easeInOut(duration: 0.25)) { vm.toggleAccumulated() } }
                        : nil
                )
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 4)

                ForEach(Array(songs.enumerated()), id: \.element.id) { i, song in
                    artistSongRow(song: song)
                    if i < songs.count - 1 {
                        Divider().background(.white.opacity(0.06)).padding(.leading, 60)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Top Songs

    private static let rowHeight: CGFloat = 52
    private static let topSongsCollapsedCount = 5

    @ViewBuilder
    private var topSongsSection: some View {
        if !vm.topSongs.isEmpty {
            let shown = vm.topSongsExpanded
                ? vm.topSongs
                : Array(vm.topSongs.prefix(Self.topSongsCollapsedCount))

            VStack(alignment: .leading, spacing: 0) {
                SectionHeaderView(
                    L(.section_top_songs),
                    onSeeAll: vm.topSongs.count > Self.topSongsCollapsedCount
                        ? { withAnimation(.easeInOut(duration: 0.25)) { vm.toggleTopSongsExpanded() } }
                        : nil
                )
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 4)

                ForEach(Array(shown.enumerated()), id: \.element.id) { i, song in
                    artistSongRow(song: song)
                    if i < shown.count - 1 {
                        Divider().background(.white.opacity(0.06)).padding(.leading, 60)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 8)
        }
    }

    /// One song line: artwork, title, album · year, matching Apple Music's
    /// artist tracklists.
    private func artistSongRow(song: Song) -> some View {
        HStack(spacing: 10) {
            Button {
                appState.audioPlayer.play(song: song)
            } label: {
                HStack(spacing: 10) {
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

    // MARK: - Liked Songs

    @ViewBuilder
    private var likedSongsSection: some View {
        let liked = vm.likedSongs
        if !liked.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeaderView(L(.section_liked_songs))
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 4)

                VStack(spacing: 0) {
                    ForEach(Array(liked.enumerated()), id: \.element.id) { i, song in
                        artistSongRow(song: song)
                        if i < liked.count - 1 {
                            Divider().background(.white.opacity(0.06)).padding(.leading, 60)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Albums

    @ViewBuilder
    private var albumsSection: some View {
        if !vm.albumReleases.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeaderView(L(.media_albums))
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(vm.albumReleases) { album in
                            Button { drillAlbum = album } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    ArtworkView(
                                        coverArtID: album.coverArt,
                                        size: 300,
                                        cornerRadius: 8,
                                        cropsImageToSquare: true
                                    )
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
                            .albumContextMenu(album)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var singlesSection: some View {
        if !vm.singles.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeaderView(L(.artist_singles))
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(vm.singles) { album in
                            Button { drillAlbum = album } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    ArtworkView(
                                        coverArtID: album.coverArt,
                                        size: 300,
                                        cornerRadius: 8,
                                        cropsImageToSquare: true
                                    )
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
                            .albumContextMenu(album)
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
                SectionHeaderView(L(.section_appeared_on))
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
                            .albumContextMenu(album)
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
                SectionHeaderView(L(.section_similar_artists))
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(vm.similarArtists) { artist in
                            NavigationLink(destination: ArtistDetailView(artist: artist)) {
                                VStack(spacing: 8) {
                                    ArtworkView(coverArtID: artist.coverArt, artistID: artist.id, size: 200, cornerRadius: 50)
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

    // MARK: - Artist Stats

    @ViewBuilder
    private var artistStatsSection: some View {
        let albumCount = vm.albums.count
        let totalPlays = vm.albums.compactMap(\.playCount).reduce(0, +)
        let genres = Array(Set(vm.albums.compactMap(\.genre))).sorted()

        if albumCount > 0 {
            VStack(alignment: .leading, spacing: 16) {
                Text(L(.tab_stats))
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    statsCell(value: "\(albumCount)", label: L(.media_albums))
                    if totalPlays > 0 {
                        statsCell(value: formatPlays(totalPlays), label: L(.stat_total_plays))
                    }
                    if let year = vm.albums.compactMap(\.year).min() {
                        statsCell(value: "\(year)", label: L(.stat_active_since))
                    }
                    if let latest = vm.albums.compactMap(\.year).max(),
                       let oldest = vm.albums.compactMap(\.year).min(), latest != oldest {
                        statsCell(value: "\(oldest)–\(latest)", label: L(.stat_years_active))
                    }
                }

                if !genres.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L(.media_genres).localizedUppercase)
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
private final class ArtistProfileScrollState: ObservableObject {
    @Published var offsetY: CGFloat = 0

    private var pendingOffsetY: CGFloat = 0
    private var throttler: VSyncThrottler?

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
    let profileImage: UIImage?
    let fallbackAlbum: Album?
    let dominantColor: UIColor
    @ObservedObject var scrollState: ArtistProfileScrollState
    let onFallbackImageLoaded: (UIImage) -> Void

    var body: some View {
        let stretch = max(0, -scrollState.offsetY)
        let shift = max(0, scrollState.offsetY)
        let headerHeight = baseHeight + stretch

        // Lives outside the ScrollView so only this small header redraws on scroll.
        ArtistHeroComposition(
            width: width,
            headerHeight: headerHeight,
            bg: bg,
            profileImage: profileImage,
            fallbackAlbum: fallbackAlbum,
            dominantColor: dominantColor,
            onFallbackImageLoaded: onFallbackImageLoaded
        )
        .offset(y: -shift)
        .transaction { $0.animation = nil }
        .allowsHitTesting(false)
    }
}

/// The full hero: sharp photo, a blurred copy of its lower edge laid over the
/// image so the picture itself softens, then the tint fade carrying that blurred
/// edge into the page background.
private struct ArtistHeroComposition: View {
    let width: CGFloat
    let headerHeight: CGFloat
    let bg: Color
    let profileImage: UIImage?
    let fallbackAlbum: Album?
    let dominantColor: UIColor
    let onFallbackImageLoaded: (UIImage) -> Void

    private var blendHeight: CGFloat {
        min(max(headerHeight * 0.48, 170), 300)
    }

    /// Where the blurred copy starts taking over, as a fraction of the header.
    private var blurStart: CGFloat {
        max(0, min(0.82, (headerHeight - blendHeight) / max(headerHeight, 1)))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            heroImage
                .frame(width: width, height: headerHeight)
                .clipped()

            // Blurred copy of the photo drawn OVER the sharp image, revealed
            // progressively so the picture itself dissolves toward the bottom.
            // Masking the full-size blurred image (never a clipped sub-frame)
            // keeps the band exactly over the photo.
            heroImage
                .frame(width: width, height: headerHeight)
                .clipped()
                .blur(radius: 26, opaque: true)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.00),
                            .init(color: .clear, location: blurStart),
                            .init(color: .white.opacity(0.35), location: min(1, blurStart + 0.10)),
                            .init(color: .white.opacity(0.72), location: min(1, blurStart + 0.22)),
                            .init(color: .white, location: 1.00),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Carries the blurred edge the rest of the way into the page tint. The stops
            // are eased so there is no abrupt ramp in the last few percent.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.00),
                    .init(color: bg.opacity(0.08), location: 0.35),
                    .init(color: bg.opacity(0.22), location: 0.55),
                    .init(color: bg.opacity(0.45), location: 0.72),
                    .init(color: bg.opacity(0.72), location: 0.86),
                    .init(color: bg.opacity(0.92), location: 0.95),
                    .init(color: bg, location: 1.00),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: blendHeight)
            .allowsHitTesting(false)
        }
        .frame(width: width, height: headerHeight, alignment: .bottom)
        .overlay(alignment: .top) {
            // Keeps the status-bar area readable over bright photos.
            LinearGradient(
                colors: [.black.opacity(0.35), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: headerHeight * 0.22)
            .allowsHitTesting(false)
        }
        .clipped()
    }

    @ViewBuilder
    private var heroImage: some View {
        ArtistHeroImage(
            profileImage: profileImage,
            fallbackAlbum: fallbackAlbum,
            dominantColor: dominantColor,
            onFallbackImageLoaded: onFallbackImageLoaded
        )
    }
}

/// Shared full-bleed artist photo with graceful fallbacks.
private struct ArtistHeroImage: View {
    let profileImage: UIImage?
    let fallbackAlbum: Album?
    let dominantColor: UIColor
    let onFallbackImageLoaded: (UIImage) -> Void

    var body: some View {
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
                .fill(Color(dominantColor).opacity(0.35))
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 80, weight: .light))
                        .foregroundStyle(.white.opacity(0.3))
                }
        }
    }
}

private struct IOS16ArtistProfileHeader: View {
    let width: CGFloat
    let baseHeight: CGFloat
    let scrollSpaceName: String
    let bg: Color
    let profileImage: UIImage?
    let fallbackAlbum: Album?
    let dominantColor: UIColor
    let onFallbackImageLoaded: (UIImage) -> Void

    var body: some View {
        GeometryReader { geo in
            let pullDistance = max(0, geo.frame(in: .named(scrollSpaceName)).minY)
            let headerHeight = baseHeight + pullDistance

            ArtistHeroComposition(
                width: width,
                headerHeight: headerHeight,
                bg: bg,
                profileImage: profileImage,
                fallbackAlbum: fallbackAlbum,
                dominantColor: dominantColor,
                onFallbackImageLoaded: onFallbackImageLoaded
            )
            .offset(y: pullDistance > 0 ? -pullDistance : 0)
            .transaction { $0.animation = nil }
            .allowsHitTesting(false)
        }
    }
}

private struct ArtistScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Reports the *window's* top safe-area inset.
///
/// A pushed view's own `safeAreaInsets` also includes any navigation/search
/// chrome it sits under. Search pushes artist profiles from a `NavigationStack`
/// with an always-visible search field, so its inset was ~45pt larger than when
/// the same profile is opened from Home or Library — which pushed the floating
/// header buttons down only on that route.
///
/// The window's inset reflects just the physical status-bar/notch area, so the
/// buttons and the photo's bleed point land identically from every entry point.
private struct WindowTopInsetReader: UIViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let probe = ProbeView()
        probe.onChange = onChange
        return probe
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? ProbeView)?.onChange = onChange
    }

    final class ProbeView: UIView {
        var onChange: ((CGFloat) -> Void)?
        private var lastReported: CGFloat = -1

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        private func report() {
            // Deliberately the window's inset, never this view's.
            guard let window else { return }
            let value = window.safeAreaInsets.top
            guard abs(value - lastReported) > 0.5 else { return }
            lastReported = value
            onChange?(value)
        }
    }
}

private struct YonkagorFishOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fish: [Fish]

    init() {
        _fish = State(initialValue: Self.randomFish())
    }

    private var pauseAnimation: Bool {
        reduceMotion || PerformanceMode.reduceAnimations
    }

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: FrameRateGovernor.minimumInterval,
                paused: pauseAnimation
            )
        ) { timeline in
            Canvas { context, size in
                drawFish(context: context, size: size, date: timeline.date)
            }
        }
        .opacity(0.88)
        .transaction { $0.animation = nil }
    }

    private func drawFish(context: GraphicsContext, size: CGSize, date: Date) {
        let elapsed = pauseAnimation ? 0 : date.timeIntervalSinceReferenceDate

        for swimmer in fish {
            let progress = (elapsed / swimmer.duration + swimmer.phase)
                .truncatingRemainder(dividingBy: 1)
            let travelWidth = size.width + swimmer.size * 3.2
            let x = swimmer.swimsRight
                ? -swimmer.size * 1.6 + CGFloat(progress) * travelWidth
                : size.width + swimmer.size * 1.6 - CGFloat(progress) * travelWidth
            let wave = sin(elapsed * swimmer.waveSpeed + swimmer.phase * Double.pi * 2)
            let y = min(
                max(size.height * swimmer.yPosition + CGFloat(wave) * swimmer.waveHeight, swimmer.size),
                max(swimmer.size, size.height - swimmer.size)
            )

            var fishContext = context
            fishContext.opacity = swimmer.opacity
            fishContext.translateBy(x: x, y: y)
            if !swimmer.swimsRight {
                fishContext.scaleBy(x: -1, y: 1)
            }
            let scale = swimmer.size / 44
            fishContext.scaleBy(x: scale, y: scale)
            Self.drawFishBody(
                context: &fishContext,
                bodyColor: swimmer.bodyColor,
                accentColor: swimmer.accentColor,
                tailPhase: elapsed * swimmer.tailSpeed + swimmer.phase * Double.pi * 2
            )
        }
    }

    private static func drawFishBody(
        context: inout GraphicsContext,
        bodyColor: Color,
        accentColor: Color,
        tailPhase: TimeInterval
    ) {
        let tailOffset = CGFloat(sin(tailPhase)) * 3.2

        var tail = Path()
        tail.move(to: CGPoint(x: -16, y: 0))
        tail.addLine(to: CGPoint(x: -32, y: -10 + tailOffset))
        tail.addQuadCurve(to: CGPoint(x: -25, y: 0), control: CGPoint(x: -29, y: -3))
        tail.addQuadCurve(to: CGPoint(x: -32, y: 10 + tailOffset), control: CGPoint(x: -29, y: 3))
        tail.closeSubpath()
        context.fill(tail, with: .color(accentColor.opacity(0.95)))

        let body = Path(ellipseIn: CGRect(x: -20, y: -10, width: 40, height: 20))
        context.fill(
            body,
            with: .linearGradient(
                Gradient(colors: [bodyColor, accentColor.opacity(0.82)]),
                startPoint: CGPoint(x: -18, y: -10),
                endPoint: CGPoint(x: 18, y: 10)
            )
        )

        var topFin = Path()
        topFin.move(to: CGPoint(x: -6, y: -8))
        topFin.addQuadCurve(to: CGPoint(x: 7, y: -8), control: CGPoint(x: -1, y: -17))
        topFin.addQuadCurve(to: CGPoint(x: -6, y: -8), control: CGPoint(x: 0, y: -11))
        context.fill(topFin, with: .color(accentColor.opacity(0.65)))

        var lowerFin = Path()
        lowerFin.move(to: CGPoint(x: -2, y: 5))
        lowerFin.addLine(to: CGPoint(x: 8, y: 13))
        lowerFin.addLine(to: CGPoint(x: 11, y: 4))
        lowerFin.closeSubpath()
        context.fill(lowerFin, with: .color(.white.opacity(0.22)))

        var gill = Path()
        gill.move(to: CGPoint(x: 4, y: -6))
        gill.addQuadCurve(to: CGPoint(x: 4, y: 6), control: CGPoint(x: 9, y: 0))
        context.stroke(gill, with: .color(.white.opacity(0.24)), lineWidth: 1.1)

        context.fill(
            Path(ellipseIn: CGRect(x: 10, y: -4.5, width: 3.8, height: 3.8)),
            with: .color(.black.opacity(0.65))
        )
        context.fill(
            Path(ellipseIn: CGRect(x: 11, y: -3.7, width: 1.2, height: 1.2)),
            with: .color(.white.opacity(0.85))
        )
    }

    private struct Fish {
        let yPosition: CGFloat
        let phase: Double
        let duration: TimeInterval
        let size: CGFloat
        let waveHeight: CGFloat
        let waveSpeed: Double
        let tailSpeed: Double
        let swimsRight: Bool
        let opacity: Double
        let bodyColor: Color
        let accentColor: Color
    }

    private static func randomFish(count: Int = Int.random(in: 6...9)) -> [Fish] {
        (0..<count).map { index in
            let hue = Double.random(in: 0...1)
            let accentHue = (hue + Double.random(in: 0.18...0.5))
                .truncatingRemainder(dividingBy: 1)

            return Fish(
                yPosition: CGFloat.random(in: 0.14...0.82),
                phase: (Double(index) / Double(count)) + Double.random(in: -0.04...0.04),
                duration: TimeInterval.random(in: 11...20),
                size: CGFloat.random(in: 28...52),
                waveHeight: CGFloat.random(in: 8...24),
                waveSpeed: Double.random(in: 1.1...2.4),
                tailSpeed: Double.random(in: 8.5...12.5),
                swimsRight: Bool.random(),
                opacity: Double.random(in: 0.52...0.82),
                bodyColor: Color(
                    hue: hue,
                    saturation: Double.random(in: 0.62...0.94),
                    brightness: Double.random(in: 0.78...1.0)
                ),
                accentColor: Color(
                    hue: accentHue,
                    saturation: Double.random(in: 0.58...0.9),
                    brightness: Double.random(in: 0.84...1.0)
                )
            )
        }
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
            .navigationTitle(L(.artist_about, artistName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L(.action_done)) { dismiss() }
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
