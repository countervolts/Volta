import SwiftUI

struct ArtworkView: View {
    let coverArtID: String?
    var size: Int? = 400
    var cornerRadius: CGFloat = Theme.Layout.cardCorner
    var onImageLoaded: ((UIImage) -> Void)? = nil

    // Context-menu previews live outside the app environment.
    @Environment(AppState.self) private var appState: AppState?
    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.secondaryBackground)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Image(systemName: Symbols.albumPlaceholder)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Theme.secondaryText)
                if isLoading {
                    Rectangle().fill(Theme.secondaryBackground).shimmering()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: coverArtID) { await load() }
    }

    private func load() async {
        isLoading = true
        let url = appState?.client?.coverArtURL(id: coverArtID, size: size)
        // Some servers ignore the size param; cap decode size here too.
        let loaded = await ArtworkLoader.shared.image(for: url, maxPixelSize: size)
        withAnimation(.easeOut(duration: 0.35)) {
            image = loaded
            isLoading = false
        }
        if let loaded { onImageLoaded?(loaded) }
    }
}
