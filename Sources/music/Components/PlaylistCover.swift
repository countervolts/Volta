import SwiftUI

// playlist artwork that prefers a user-set custom cover (stored on-device via
// PlaylistCoverStore) and falls back to the server cover art. drop-in for the
// ArtworkView used elsewhere; keeps dominant-colour extraction working.
struct PlaylistCover: View {
    let playlist: Playlist
    var size: Int?
    var cornerRadius: CGFloat
    var onImageLoaded: ((UIImage) -> Void)?

    @State private var custom: UIImage?
    @State private var hasCustom: Bool

    init(playlist: Playlist,
         size: Int? = 400,
         cornerRadius: CGFloat = Theme.Layout.cardCorner,
         onImageLoaded: ((UIImage) -> Void)? = nil) {
        self.playlist = playlist
        self.size = size
        self.cornerRadius = cornerRadius
        self.onImageLoaded = onImageLoaded
        // seed synchronously so a custom cover never flashes the server art first
        _custom = State(initialValue: PlaylistCoverStore.shared.cachedImage(for: playlist.id))
        _hasCustom = State(initialValue: PlaylistCoverStore.shared.hasCover(for: playlist.id))
    }

    var body: some View {
        Group {
            if let custom {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Theme.secondaryBackground)
                    Image(uiImage: custom)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else if hasCustom {
                // a custom cover exists on disk but isn't decoded yet — show a
                // placeholder rather than fetching/flashing the server cover
                placeholder
            } else {
                ArtworkView(coverArtID: playlist.coverArt, size: size,
                            cornerRadius: cornerRadius, onImageLoaded: onImageLoaded)
            }
        }
        .task(id: playlist.id) { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .playlistCoverChanged)) { note in
            if note.object as? String == playlist.id { Task { await reload() } }
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.secondaryBackground)
            .overlay {
                Image(systemName: Symbols.playlistPlaceholder)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Theme.secondaryText)
            }
    }

    private func reload() async {
        hasCustom = PlaylistCoverStore.shared.hasCover(for: playlist.id)
        let img = await PlaylistCoverStore.shared.image(for: playlist.id)
        withAnimation(.easeOut(duration: 0.3)) { custom = img }
        if let img { onImageLoaded?(img) }
    }
}
