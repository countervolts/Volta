import SwiftUI

struct PickCard: View {
    let album: Album
    var cornerRadius: CGFloat = 16

    @State private var accentColor: Color = Color(white: 0.1)

    private var topLabel: String? {
        if let g = album.genre, !g.isEmpty { return g }
        if let y = album.year { return String(y) }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // a clear square forces the art to a true 1:1 at full card width,
            // so non-square server covers can't leave a black bar on the side
            GeometryReader { geo in
                ArtworkView(coverArtID: album.coverArt, size: 600, cornerRadius: 0,
                            onImageLoaded: { image in
                                accentColor = Color(ColorExtractor.dominantColor(from: image))
                            })
                    .frame(width: geo.size.width, height: geo.size.width)
                    .scaleEffect(1.02)
                    .clipped()
            }
            .aspectRatio(1, contentMode: .fit)
            .background(Theme.secondaryBackground)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                // always reserve the caption line (a blank space when there's no
                // genre/year) so every pick card — albums and mixes alike — has
                // an identical three-line text block and the same overall height.
                Text(topLabel ?? " ")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                // single line + tail truncation keeps every card the same height
                // so a long title can't make this card taller than its neighbours
                // (which is what left the squished art / side black bar).
                Text(album.name)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(album.displayArtist)
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
        .heroSource(id: album.id)
        .animation(.easeInOut(duration: 0.4), value: accentColor.description)
    }
}
