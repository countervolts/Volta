import SwiftUI

private let threeColumns = [
    GridItem(.flexible(), spacing: Theme.Layout.gridSpacing),
    GridItem(.flexible(), spacing: Theme.Layout.gridSpacing),
    GridItem(.flexible(), spacing: Theme.Layout.gridSpacing),
]

// 3-up grid of media cards. used for the 9-album home sections and the
// vertically scrolling full views.
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

// 3-up grid of the blurred-overlay pick cards.
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
