import SwiftUI

extension View {
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else if RuntimeCompatibility.prefersSolidGlassFallback {
            self.background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    func glassCircle() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .circle)
        } else if RuntimeCompatibility.prefersSolidGlassFallback {
            self.background(Color.white.opacity(0.12), in: Circle())
        } else {
            self.background(.ultraThinMaterial, in: Circle())
        }
    }

    @ViewBuilder
    func glassCapsule(tinted: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if tinted {
                self.glassEffect(.regular.tint(Theme.accent.opacity(0.5)).interactive(), in: .capsule)
            } else {
                self.glassEffect(.regular.interactive(), in: .capsule)
            }
        } else if RuntimeCompatibility.prefersSolidGlassFallback {
            self.background(
                tinted ? AnyShapeStyle(Theme.accent.opacity(0.35)) : AnyShapeStyle(Color.white.opacity(0.12)),
                in: Capsule()
            )
        } else {
            self.background(
                (tinted ? AnyShapeStyle(Theme.accent.opacity(0.35)) : AnyShapeStyle(.ultraThinMaterial)),
                in: .capsule
            )
        }
    }

    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { self.buttonStyle(.glassProminent) }
            else { self.buttonStyle(.glass) }
        } else {
            if prominent { self.buttonStyle(.borderedProminent) }
            else { self.buttonStyle(.bordered) }
        }
    }
}

struct LiquidGlassContainer<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}
