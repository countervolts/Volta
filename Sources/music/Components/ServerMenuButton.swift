import SwiftUI

// top-right avatar that opens a liquid glass contextual menu: switch servers,
// log out, open settings. shown on every tab.
struct ServerMenuButton: View {
    var onOpenSettings: () -> Void

    @Environment(AppState.self) private var appState

    var body: some View {
        Menu {
            let servers = appState.servers()
            if servers.count > 1 {
                Menu {
                    ForEach(servers) { server in
                        Button {
                            appState.switchTo(server)
                        } label: {
                            Label(server.displayName, systemImage: Symbols.server)
                        }
                        .disabled(server.id == appState.currentServer?.id)
                    }
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
    }
}
