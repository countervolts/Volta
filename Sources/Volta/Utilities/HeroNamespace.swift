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
        if #available(iOS 26.0, *) {
            self.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }
}

private struct HeroSourceWrapper<Content: View>: View {
    let id: AnyHashable
    let content: Content
    @Environment(\.heroNamespace) private var ns

    var body: some View {
        if let ns, #available(iOS 26.0, *) {
            content.matchedTransitionSource(id: id, in: ns)
        } else {
            content
        }
    }
}
