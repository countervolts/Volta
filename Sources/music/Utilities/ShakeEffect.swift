import SwiftUI

// horizontal shake used for invalid login fields.
struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 8
    var shakesPerUnit = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = amount * sin(animatableData * .pi * CGFloat(shakesPerUnit))
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

extension View {
    // bumps the shake whenever `trigger` increments.
    func shake(with trigger: Int) -> some View {
        modifier(ShakeModifier(trigger: trigger))
    }
}

private struct ShakeModifier: ViewModifier {
    let trigger: Int
    @State private var animatable: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .modifier(ShakeEffect(animatableData: animatable))
            .onChange(of: trigger) { _, _ in
                animatable = 0
                withAnimation(.linear(duration: 0.5)) {
                    animatable = 1
                }
            }
    }
}
