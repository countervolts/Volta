import SwiftUI

// iOS 26 only — matchedTransitionSource available unconditionally.

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
    func heroSource(id: some Hashable) -> some View {
        HeroSourceWrapper(id: AnyHashable(id), content: self)
    }
}

private struct HeroSourceWrapper<Content: View>: View {
    let id: AnyHashable
    let content: Content
    @Environment(\.heroNamespace) private var ns

    var body: some View {
        if let ns {
            content.matchedTransitionSource(id: id, in: ns)
        } else {
            content
        }
    }
}
