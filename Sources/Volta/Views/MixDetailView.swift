import SwiftUI
import UIKit

enum MixSheet: Identifiable {
    case addToPlaylist(Song)
    case album(Album)
    case artist(Artist)
    var id: String {
        switch self {
        case .addToPlaylist(let s): return "song-\(s.id)"
        case .album(let a):         return "album-\(a.id)"
        case .artist(let a):        return "artist-\(a.id)"
        }
    }
}

struct MixDetailView: View {
    @EnvironmentObject private var appState: AppState
    let mix: MusicMix

    @State private var dominantColor: UIColor = .black
    @State private var activeSheet: MixSheet? = nil
    @State private var toastMessage: String? = nil
    @State private var isSavingMix = false
    @State private var explicitSongIDs = Set<String>()
    @AppStorage("showTrackArtwork") private var showTrackArtwork = true
    @AppStorage("showExplicitBadge") private var showExplicitBadge = true

    private var bg: Color { Color(ColorExtractor.backgroundVariant(of: dominantColor)) }

    var body: some View {
        ZStack(alignment: .top) {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    artworkSection
                    infoSection
                    actionRow
                    trackList
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
        .preferredColorScheme(Theme.colorScheme)
        .background(SwipeBackEnabler())
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addToPlaylist(let song):
                AddToPlaylistSheet(song: song, onAdded: { name in
                    showToast(L(.home_saved_to, name))
                })
            case .album(let album):
                NavigationStack {
                    AlbumDetailView(album: album)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) {
                            Button(L(.action_done)) { activeSheet = nil }.foregroundStyle(Theme.accent)
                        } }
                }
                .preferredColorScheme(Theme.colorScheme)
            case .artist(let artist):
                NavigationStack {
                    ArtistDetailView(artist: artist)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) {
                            Button(L(.action_done)) { activeSheet = nil }.foregroundStyle(Theme.accent)
                        } }
                }
                .preferredColorScheme(Theme.colorScheme)
            }
        }
        .task(id: mix.id) {
            explicitSongIDs = Set(mix.songs.filter(\.isExplicit).map(\.id))
            if showExplicitBadge, let client = appState.client {
                await resolveExplicitStatuses(client: client)
            }
        }
    }

    private func goToAlbum(_ song: Song) {
        guard let id = song.albumId else { return }
        Task { if let album = try? await appState.client?.album(id: id) { activeSheet = .album(album) } }
    }

    private func goToArtist(_ song: Song) {
        guard let id = song.artistId else { return }
        Task { if let artist = try? await appState.client?.artist(id: id) { activeSheet = .artist(artist) } }
    }

    private var artworkSection: some View {
        ArtworkView(coverArtID: mix.coverArt, size: 800, cornerRadius: 14,
                    onImageLoaded: { dominantColor = ColorExtractor.dominantColor(from: $0) })
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal, 36)
            .shadow(color: .black.opacity(0.45), radius: 28, x: 0, y: 10)
            .padding(.top, 32)
    }

    private var infoSection: some View {
        VStack(spacing: 6) {
            Text(mix.localizedTitle)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(mix.localizedSubtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Text(L(.home_song_count, mix.songs.count))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var actionRow: some View {
        HStack(spacing: 14) {
            Button {
                appState.audioPlayer.playQueue(mix.songs.shuffled(), startIndex: 0, source: mix.localizedTitle)
            } label: {
                Image(systemName: Symbols.shuffle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .glassCircle()
            }
            .buttonStyle(.plain)

            Button {
                appState.audioPlayer.playQueue(mix.songs, startIndex: 0, source: mix.localizedTitle)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: Symbols.play).font(.system(size: 14, weight: .bold))
                    Text(L(.action_play)).font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                saveMixAsPlaylist()
            } label: {
                ZStack {
                    if isSavingMix {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: Symbols.newPlaylist)
                    }
                }
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .glassCircle()
            }
            .buttonStyle(.plain)
            .disabled(isSavingMix || appState.client == nil || mix.songs.isEmpty)
            .opacity((appState.client == nil || mix.songs.isEmpty) ? 0.45 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }

    private var trackList: some View {
        VStack(spacing: 0) {
            Divider()
                .frame(height: 0.75)
                .overlay(.white.opacity(0.15))
                .padding(.bottom, 4)
            ForEach(Array(mix.songs.enumerated()), id: \.element.id) { i, song in
                TrackRow(
                    song: song,
                    index: i + 1,
                    isCurrentlyPlaying: appState.audioPlayer.currentSong?.id == song.id,
                    onTap: {
                        appState.audioPlayer.playQueue(mix.songs, startIndex: i, source: mix.localizedTitle)
                    },
                    showArtist: true,
                    showsExplicitBadge: showExplicitBadge,
                    explicitOverride: explicitSongIDs.contains(song.id) ? true : nil,
                    leadingArtwork: showTrackArtwork,
                    onSwipePlayNext: {
                        appState.audioPlayer.playNext(song)
                    }
                ) {
                    SongMenu(
                        song: song,
                        onGoToAlbum: song.albumId == nil ? nil : { goToAlbum(song) },
                        onGoToArtist: song.artistId == nil ? nil : { goToArtist(song) },
                        onAddToPlaylist: { activeSheet = .addToPlaylist(song) }
                    )
                }
                Divider().overlay(.white.opacity(0.14))
            }
        }
        .padding(.horizontal, 20)
    }

    private func resolveExplicitStatuses(client: any MusicService) async {
        let unresolved = mix.songs.filter { !$0.hasKnownExplicitStatus }
        guard !unresolved.isEmpty else { return }

        let resolved = await DeveloperExperiments.runConcurrently(
            unresolved,
            defaultMaxConcurrent: 3
        ) { song in
            let value = await ExplicitStatusResolver.shared.isExplicit(
                songID: song.id,
                localURL: DownloadService.shared.localURL(for: song),
                remoteURL: client.originalStreamURL(id: song.id),
                requestHeaders: client.mediaRequestHeaders()
            )
            return value == true ? song.id : nil
        }
        explicitSongIDs.formUnion(resolved.compactMap { $0 })
        AppLogger.shared.log(
            "Mix explicit metadata resolved; mixID=\(mix.id); server=\(mix.songs.filter(\.isExplicit).count); embedded=\(resolved.compactMap { $0 }.count)",
            category: .other
        )
    }

    private func showToast(_ message: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { toastMessage = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toastMessage = nil }
        }
    }

    private func saveMixAsPlaylist() {
        guard !isSavingMix, let client = appState.client, !mix.songs.isEmpty else { return }
        isSavingMix = true
        let title = mix.localizedTitle

        Task {
            do {
                let name = try await PlaylistWriter.saveMixAsPlaylist(mix, client: client, title: title)
                await MainActor.run {
                    isSavingMix = false
                    showToast(L(.home_saved_to, name))
                }
            } catch {
                AppLogger.shared.log("Failed saving mix '\(mix.title)' as playlist: \(error.localizedDescription)", category: .other, level: .error)
                await MainActor.run {
                    isSavingMix = false
                    showToast(L(.home_save_mix_failed))
                }
            }
        }
    }
}
