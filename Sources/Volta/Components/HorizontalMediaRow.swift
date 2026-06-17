import SwiftUI

// Horizontal row that peeks the next card.
struct HorizontalMediaRow: View {
    let items: [MediaItem]
    var onSelect: (MediaItem) -> Void = { _ in }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: Theme.Layout.gridSpacing) {
                ForEach(items) { item in
                    let card = MediaCard(item: item)
                        .containerRelativeFrame(
                            .horizontal,
                            count: 5,
                            span: 2,
                            spacing: Theme.Layout.gridSpacing
                        )
                        .onTapGesture { onSelect(item) }
                    if let album = item.albumRef {
                        card.albumContextMenu(album)
                    } else {
                        card
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, Theme.Layout.screenPadding)
        }
        .scrollTargetBehavior(.viewAligned)
    }
}

// Picks for You row: album and mix cards share the same footprint.
struct HorizontalPickRow: View {
    let items: [PickFeedItem]
    var onSelectAlbum: (Album) -> Void = { _ in }
    var onSelectMix: (MusicMix) -> Void = { _ in }
    var onSaveMix: (MusicMix) -> Void = { _ in }
    var isSavingMix: (MusicMix) -> Bool = { _ in false }

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: Theme.Layout.gridSpacing) {
                ForEach(items) { item in
                    Group {
                        switch item {
                        case .album(let album):
                            PickCard(album: album)
                                .onTapGesture { onSelectAlbum(album) }
                        case .mix(let mix):
                            PickMixCard(mix: mix)
                                .onTapGesture { onSelectMix(mix) }
                                .contextMenu {
                                    Button {
                                        onSaveMix(mix)
                                    } label: {
                                        Label(isSavingMix(mix) ? L(.action_saving) : L(.action_save_as_playlist),
                                              systemImage: Symbols.addToPlaylist)
                                    }
                                    .disabled(isSavingMix(mix))
                                }
                        }
                    }
                    .containerRelativeFrame(
                        .horizontal,
                        count: sizeClass == .regular ? 10 : 5,
                        span: sizeClass == .regular ? 2 : 3,
                        spacing: Theme.Layout.gridSpacing
                    )
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, Theme.Layout.screenPadding)
        }
        .scrollTargetBehavior(.viewAligned)
    }
}

// Mix version of PickCard.
struct PickMixCard: View {
    let mix: MusicMix
    var cornerRadius: CGFloat = 16

    @State private var accentColor: Color = Color(white: 0.12)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geo in
                ArtworkView(coverArtID: mix.coverArt, size: 600, cornerRadius: 0,
                            onImageLoaded: { image in
                                accentColor = Color(ColorExtractor.dominantColor(from: image))
                    })
                    .frame(width: geo.size.width, height: geo.size.width)
                    .scaleEffect(1.02)
                    .clipped()
            }
            .aspectRatio(1, contentMode: .fit)
            .background(Theme.secondaryBackground)
            .clipped()
                .overlay(alignment: .topLeading) {
                    Label(L(.home_mix_badge), systemImage: "square.stack.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(10)
                }

            VStack(alignment: .leading, spacing: 4) {
                // Keep the same three-line block as album pick cards.
                Text(mix.localizedSubtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                // Long titles should truncate, not stretch the card.
                Text(mix.localizedTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(L(.home_song_count, mix.songs.count))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(accentColor.opacity(0.82))
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .heroSource(id: mix.id)
        .animation(.easeInOut(duration: 0.4), value: accentColor.description)
    }
}
