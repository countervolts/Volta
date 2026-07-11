import SwiftUI

// Skeleton loading shimmer.
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.18), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .scaleEffect(x: 1.5)
                .offset(x: phase * 260)
                .blendMode(.plusLighter)
            )
            .mask(content)
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}

extension View {
    @ViewBuilder
    func shimmering() -> some View {
        if RuntimeCompatibility.allowsArtworkShimmer {
            modifier(Shimmer())
        } else {
            self
        }
    }
}
