import SwiftUI

// Shared account/settings affordance for tab navigation stacks.
struct AccountToolbar: ViewModifier {
    @State private var showSettings = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ServerMenuButton(onOpenSettings: { showSettings = true })
                }
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
    }
}

extension View {
    func accountToolbar() -> some View {
        modifier(AccountToolbar())
    }
}
