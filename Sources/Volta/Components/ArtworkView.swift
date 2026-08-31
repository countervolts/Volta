import SwiftUI
import UIKit

struct ArtworkView: View {
    let coverArtID: String?
    var artistID: String? = nil
    var size: Int? = 400
    var cornerRadius: CGFloat = Theme.Layout.cardCorner
    /// Full-bleed headers need a square cover to fill their rectangular frame.
    var squareContentMode: ContentMode = .fit
    /// Album covers use a centre crop so provider artwork never controls layout.
    var cropsImageToSquare = false
    var onImageLoaded: ((UIImage) -> Void)? = nil

    @State private var image: UIImage?
    @State private var isLoading = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var artworkLoadAnimation: Animation {
        reduceMotion || PerformanceMode.reduceAnimations
            ? .linear(duration: 0.01)
            : .easeOut(duration: 0.35)
    }

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
        // Artwork may arrive in any aspect ratio; presentation stays square.
        .aspectRatio(1, contentMode: squareContentMode)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: artworkTaskID) { await load() }
    }

    private var artworkTaskID: String {
        "\(AppState.shared.isOfflineMode ? "offline" : "online")|\(artistID ?? "")|\(coverArtID ?? "")"
    }

    private func load() async {
        isLoading = true
        let requestedSize = RuntimeCompatibility.cappedArtworkSize(size)
        // Some servers ignore the size param; cap decode size here too.
        let loaded: UIImage?
        if !AppState.shared.isOfflineMode,
           let url = AppState.shared.client?.coverArtURL(id: coverArtID, size: requestedSize),
           let online = await ArtworkLoader.shared.image(for: url, maxPixelSize: requestedSize) {
            loaded = online
        } else if let cover = await ArtworkLoader.shared.image(
            forCoverArtID: coverArtID,
            serverID: AppState.shared.currentServer?.id,
            maxPixelSize: requestedSize
        ) {
            loaded = cover
        } else if let source = DownloadService.shared.localArtworkSource(
            forCoverArtID: coverArtID,
            serverID: AppState.shared.currentServer?.id
        ),
                  let cover = await ArtworkLoader.shared.image(
                    fromEmbeddedArtworkAt: source.url,
                    coverArtID: coverArtID,
                    serverID: source.serverID,
                    groupID: source.groupID,
                    owner: source.owner,
                    maxPixelSize: requestedSize
                  ) {
            loaded = cover
        } else {
            loaded = await ArtworkLoader.shared.image(
                forArtistID: artistID,
                serverID: AppState.shared.currentServer?.id,
                maxPixelSize: requestedSize
            )
        }
        let displayed = cropsImageToSquare ? loaded?.centerCroppedSquare() : loaded
        withAnimation(artworkLoadAnimation) {
            image = displayed
            isLoading = false
        }
        if let displayed { onImageLoaded?(displayed) }
    }
}

extension UIImage {
    /// Crop still or animated artwork around its centre, preserving animation timing.
    func centerCroppedSquare() -> UIImage {
        if let frames = images, !frames.isEmpty {
            let croppedFrames = frames.map { $0.centerCroppedSquare() }
            guard let animated = UIImage.animatedImage(with: croppedFrames, duration: duration) else { return self }
            animated.frameDelays = frameDelays
            return animated
        }

        let sourceSize = size
        let side = min(sourceSize.width, sourceSize.height)
        guard side > 0, abs(sourceSize.width - sourceSize.height) > 0.5 else { return self }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            draw(in: CGRect(
                x: (side - sourceSize.width) / 2,
                y: (side - sourceSize.height) / 2,
                width: sourceSize.width,
                height: sourceSize.height
            ))
        }
    }
}
