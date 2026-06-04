import SwiftUI

// Use iOS 26 Liquid Glass when available. Older systems silently fall back to
// material/button styles so the app still runs without a settings toggle.

private let liquidGlassDisabled = false

extension View {
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        if !liquidGlassDisabled, #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }

    @ViewBuilder
    func glassCircle() -> some View {
        if !liquidGlassDisabled, #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .circle)
        } else {
            self.background(.ultraThinMaterial, in: .circle)
        }
    }

    @ViewBuilder
    func glassCapsule(tinted: Bool = false) -> some View {
        if !liquidGlassDisabled, #available(iOS 26.0, *) {
            self.glassEffect(
                tinted ? .regular.tint(Theme.accent.opacity(0.5)) : .regular,
                in: .capsule
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
        if !liquidGlassDisabled, #available(iOS 26.0, *) {
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
        if !liquidGlassDisabled, #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}
