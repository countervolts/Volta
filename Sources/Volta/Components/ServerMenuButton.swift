import SwiftUI

// Top-right server/account menu.
struct ServerMenuButton: View {
    var onOpenSettings: () -> Void

    @Environment(AppState.self) private var appState
    @State private var showSwitcher = false

    var body: some View {
        Menu {
            if appState.servers().count > 1 {
                Button {
                    showSwitcher = true
                } label: {
                    Label("Switch Server", systemImage: Symbols.switchServer)
                }
            }

            Button(action: onOpenSettings) {
                Label("Settings", systemImage: Symbols.settings)
            }

            Divider()

            Button(role: .destructive) {
                appState.logout()
            } label: {
                Label("Log Out", systemImage: Symbols.logout)
            }
        } label: {
            Image(systemName: Symbols.account)
                .font(.system(size: 22))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 38, height: 38)
                .glassCircle()
        }
        .menuStyle(.button)
        .sheet(isPresented: $showSwitcher) {
            ServerSwitcherSheet()
        }
    }
}
