import SwiftUI

struct MediaCard: View {
    let item: MediaItem
    var width: CGFloat?
    var heroSourceID: String?

    init(item: MediaItem, width: CGFloat? = nil, heroSourceID: String? = nil) {
        self.item = item
        self.width = width
        self.heroSourceID = heroSourceID
    }

    init(album: Album, width: CGFloat? = nil, heroSourceID: String? = nil) {
        self.init(item: MediaItem(album: album), width: width, heroSourceID: heroSourceID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                ArtworkView(coverArtID: item.coverArt, size: 400)
                    .frame(width: geometry.size.width, height: geometry.size.width)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardCorner, style: .continuous))
            .heroSource(id: heroSourceID ?? item.id)

            Text(item.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)

            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
    }
}
