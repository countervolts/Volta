import SwiftUI

// iOS 26 Liquid Glass everywhere. The user-facing disable toggle was removed
// (it caused rendering bugs); glass is always on. The fallback branches below
// are kept dormant behind this flag in case a future build needs them.

private let liquidGlassDisabled = false

extension View {
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        if liquidGlassDisabled {
            self.background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        }
    }

    @ViewBuilder
    func glassCircle() -> some View {
        if liquidGlassDisabled {
            self.background(.ultraThinMaterial, in: .circle)
        } else {
            self.glassEffect(.regular, in: .circle)
        }
    }

    @ViewBuilder
    func glassCapsule(tinted: Bool = false) -> some View {
        if liquidGlassDisabled {
            self.background(
                (tinted ? AnyShapeStyle(Theme.accent.opacity(0.35)) : AnyShapeStyle(.ultraThinMaterial)),
                in: .capsule
            )
        } else {
            self.glassEffect(
                tinted ? .regular.tint(Theme.accent.opacity(0.5)) : .regular,
                in: .capsule
            )
        }
    }

    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if liquidGlassDisabled {
            if prominent { self.buttonStyle(.borderedProminent) }
            else { self.buttonStyle(.bordered) }
        } else {
            if prominent { self.buttonStyle(.glassProminent) }
            else { self.buttonStyle(.glass) }
        }
    }
}

struct LiquidGlassContainer<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        if liquidGlassDisabled {
            content()
        } else {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        }
    }
}
