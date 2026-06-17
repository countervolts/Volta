import SwiftUI

private let threeColumns = [
    GridItem(.flexible(), spacing: Theme.Layout.gridSpacing),
    GridItem(.flexible(), spacing: Theme.Layout.gridSpacing),
    GridItem(.flexible(), spacing: Theme.Layout.gridSpacing),
]

// Three-column media grid for Home and full-list views.
struct MediaCardGrid: View {
    let items: [MediaItem]
    var onSelect: (MediaItem) -> Void = { _ in }

    var body: some View {
        LazyVGrid(columns: threeColumns, spacing: Theme.Layout.gridSpacing) {
            ForEach(items) { item in
                MediaCard(item: item)
                    .onTapGesture { onSelect(item) }
            }
        }
    }
}

// Three-column pick-card grid.
struct PicksGrid: View {
    let albums: [Album]
    var onSelect: (Album) -> Void = { _ in }

    var body: some View {
        LazyVGrid(columns: threeColumns, spacing: Theme.Layout.gridSpacing) {
            ForEach(albums) { album in
                PickCard(album: album)
                    .onTapGesture { onSelect(album) }
            }
        }
    }
}
