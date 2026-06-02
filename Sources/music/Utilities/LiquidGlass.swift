import SwiftUI

// iOS 26 Liquid Glass only — no fallbacks.

extension View {
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }

    func glassCircle() -> some View {
        self.glassEffect(.regular, in: .circle)
    }

    func glassCapsule(tinted: Bool = false) -> some View {
        self.glassEffect(
            tinted ? .regular.tint(Theme.accent.opacity(0.5)) : .regular,
            in: .capsule
        )
    }

    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if prominent {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.glass)
        }
    }
}

struct LiquidGlassContainer<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content()
        }
    }
}
