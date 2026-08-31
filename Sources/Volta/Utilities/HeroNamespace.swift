import SwiftUI

private struct HeroNamespaceKey: EnvironmentKey {
    static var defaultValue: Namespace.ID? { nil }
}

extension EnvironmentValues {
    var heroNamespace: Namespace.ID? {
        get { self[HeroNamespaceKey.self] }
        set { self[HeroNamespaceKey.self] = newValue }
    }
}

extension View {
    @ViewBuilder
    func heroSource(id: some Hashable) -> some View {
        HeroSourceWrapper(id: AnyHashable(id), content: self)
    }

    @ViewBuilder
    func zoomNavigationTransition<ID: Hashable>(sourceID: ID, in namespace: Namespace.ID) -> some View {
        HeroNavigationTransition(content: self, sourceID: sourceID, namespace: namespace)
    }
}

/// Zooming a full card is pleasant for ordinary navigation, but is needlessly
/// disorienting when the system's Reduce Motion setting or Performance Mode is
/// active. In those cases SwiftUI falls back to its standard navigation change.
private struct HeroNavigationTransition<Content: View, ID: Hashable>: View {
    let content: Content
    let sourceID: ID
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion || PerformanceMode.reduceAnimations {
            content
        } else if #available(iOS 26.0, *) {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
    }
}

private struct HeroSourceWrapper<Content: View>: View {
    let id: AnyHashable
    let content: Content
    @Environment(\.heroNamespace) private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let ns, !reduceMotion, !PerformanceMode.reduceAnimations, #available(iOS 26.0, *) {
            content.matchedTransitionSource(id: id, in: ns)
        } else {
            content
        }
    }
}
