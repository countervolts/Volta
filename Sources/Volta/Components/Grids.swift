import SwiftUI

// Three-column media grid for Home and full-list views.
struct MediaCardGrid: View {
    let items: [MediaItem]
    var onSelect: (MediaItem) -> Void = { _ in }

#if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
#endif

    private var columns: [GridItem] {
        let count: Int
#if os(iOS)
        count = verticalSizeClass == .compact ? 5 : 3
#else
        count = 3
#endif
        return Array(repeating: GridItem(.flexible(), spacing: Theme.Layout.gridSpacing), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.Layout.gridSpacing) {
            ForEach(items) { item in
                let card = MediaCard(item: item)
                    .onTapGesture { onSelect(item) }
                if let album = item.albumRef {
                    card.albumContextMenu(album)
                } else {
                    card
                }
            }
        }
    }
}

// Three-column pick-card grid.
struct PicksGrid: View {
    let albums: [Album]
    var onSelect: (Album) -> Void = { _ in }

#if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
#endif

    private var columns: [GridItem] {
        let count: Int
#if os(iOS)
        count = verticalSizeClass == .compact ? 5 : 3
#else
        count = 3
#endif
        return Array(repeating: GridItem(.flexible(), spacing: Theme.Layout.gridSpacing), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.Layout.gridSpacing) {
            ForEach(albums) { album in
                PickCard(album: album)
                    .onTapGesture { onSelect(album) }
                    .albumContextMenu(album)
            }
        }
    }
}
