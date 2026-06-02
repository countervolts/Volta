import SwiftUI

// horizontally scrolling row showing ~2.5 cards at once (count 5 / span 2).
struct HorizontalMediaRow: View {
    let items: [MediaItem]
    var onSelect: (MediaItem) -> Void = { _ in }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: Theme.Layout.gridSpacing) {
                ForEach(items) { item in
                    MediaCard(item: item)
                        .containerRelativeFrame(
                            .horizontal,
                            count: 5,
                            span: 2,
                            spacing: Theme.Layout.gridSpacing
                        )
                        .onTapGesture { onSelect(item) }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, Theme.Layout.screenPadding)
        }
        .scrollTargetBehavior(.viewAligned)
    }
}

// Picks for You: square artwork + glass text panel below.
// Height is natural (art width + text panel); only width is constrained.
struct HorizontalPickRow: View {
    let albums: [Album]
    var onSelect: (Album) -> Void = { _ in }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: Theme.Layout.gridSpacing) {
                ForEach(albums) { album in
                    PickCard(album: album)
                        .containerRelativeFrame(
                            .horizontal,
                            count: 5,
                            span: 3,
                            spacing: Theme.Layout.gridSpacing
                        )
                        .onTapGesture { onSelect(album) }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, Theme.Layout.screenPadding)
        }
        .scrollTargetBehavior(.viewAligned)
    }
}
