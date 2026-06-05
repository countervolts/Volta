import SwiftUI

// adds the top-right account menu and the pushed settings destination to any
// tab's navigation stack, so every tab behaves the same.
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
