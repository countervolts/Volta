import SwiftUI

// full-screen vertically scrolling grid, all entries loaded upfront. centered
// title with a liquid glass back button, per the spec.
struct FullMediaGrid: View {
    let title: String
    let items: [MediaItem]
    var onSelect: (MediaItem) -> Void = { _ in }

    init(title: String, items: [MediaItem], onSelect: ((MediaItem) -> Void)? = nil) {
        self.title = title
        self.items = items
        self.onSelect = onSelect ?? { _ in }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                MediaCardGrid(items: items, onSelect: onSelect)
                    .padding(.horizontal, Theme.Layout.screenPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
            }
        }
        .navigationBarBackButtonHidden(true)
        .background(SwipeBackEnabler())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
            }
            ToolbarItem(placement: .topBarLeading) {
                GlassBackButton()
            }
        }
    }
}
