import SwiftUI

// horizontally scrolling row showing ~2.5 cards at once (count 5 / span 2).
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

// Picks for You: mixes + pick albums interleaved at one card size.
// Square artwork + colored text panel below; only width is constrained.
struct HorizontalPickRow: View {
    let items: [PickFeedItem]
    var onSelectAlbum: (Album) -> Void = { _ in }
    var onSelectMix: (MusicMix) -> Void = { _ in }

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
                        }
                    }
                    .containerRelativeFrame(
                        .horizontal,
                        count: 5,
                        span: 3,
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

// mix card matching PickCard's size + colored-panel styling.
struct PickMixCard: View {
    let mix: MusicMix
    var cornerRadius: CGFloat = 16

    @State private var accentColor: Color = Color(white: 0.12)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ArtworkView(coverArtID: mix.coverArt, size: 400, cornerRadius: 0,
                                onImageLoaded: { image in
                                    accentColor = Color(ColorExtractor.dominantColor(from: image))
                                })
                }
                .clipped()
                .overlay(alignment: .topLeading) {
                    Label("MIX", systemImage: "square.stack.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(10)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(mix.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text("\(mix.songs.count) songs")
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
        .animation(.easeInOut(duration: 0.4), value: accentColor.description)
    }
}
