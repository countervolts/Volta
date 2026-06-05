import SwiftUI

struct MediaCard: View {
    let item: MediaItem
    var width: CGFloat?

    init(item: MediaItem, width: CGFloat? = nil) {
        self.item = item
        self.width = width
    }

    init(album: Album, width: CGFloat? = nil) {
        self.init(item: MediaItem(album: album), width: width)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(coverArtID: item.coverArt, size: 400)
                .aspectRatio(1, contentMode: .fit)
                .heroSource(id: item.id)

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
