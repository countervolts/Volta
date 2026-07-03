import SwiftUI

// Native server picker with saved automatic connection roles.
struct ServerSwitcherSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var servers: [ServerRecord] = []
    @State private var serverPendingRemoval: ServerRecord?
    @State private var showAddServer = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(servers) { server in
                        row(for: server)
                    }
                } header: {
                    Text("Servers")
                } footer: {
                    Text("The default server is used when Volta starts. The fallback server is tried if the default cannot connect.")
                }

                Section {
                    Button {
                        showAddServer = true
                    } label: {
                        Label("Add Server", systemImage: "plus.circle.fill")
                    }
                }

                if servers.count > 1 {
                    Section {
                        Picker("Default Server", selection: defaultServerID) {
                            ForEach(servers) { server in
                                Text(server.displayName).tag(server.id)
                            }
                        }

                        Picker("Fallback Server", selection: fallbackServerID) {
                            Text("None").tag("")
                            ForEach(servers.filter { $0.id != defaultServerID.wrappedValue }) { server in
                                Text(server.displayName).tag(server.id)
                            }
                        }
                    } header: {
                        Text("Automatic Connection")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Servers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Theme.accent)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: reload)
        .sheet(isPresented: $showAddServer) {
            AddServerSheet {
                reload()
                showAddServer = false
                dismiss()
            }
        }
        .alert("Remove Server", isPresented: removalBinding, presenting: serverPendingRemoval) { server in
            Button("Remove", role: .destructive) { remove(server) }
            Button("Cancel", role: .cancel) {}
        } message: { server in
            Text("Remove \(server.displayName)? You'll need to sign in again to use it.")
        }
    }

    private func row(for server: ServerRecord) -> some View {
        let isCurrent = server.id == appState.currentServer?.id
        return Button {
            guard !isCurrent else { return }
            appState.switchTo(server)
            reload()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon(for: server.backend))
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(server.displayName)
                        .foregroundStyle(.primary)

                    Text(server.backend.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(server.username) - \(server.urlString)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    if server.isDefault {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Default server")
                    }
                    if server.isFallback {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.blue)
                            .accessibilityLabel("Fallback server")
                    }
                    if isCurrent {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.accent)
                            .accessibilityLabel("Connected server")
                    }
                }
                .font(.system(size: 15, weight: .semibold))
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !isCurrent {
                Button {
                    appState.switchTo(server)
                    reload()
                    dismiss()
                } label: {
                    Label("Connect", systemImage: "checkmark.circle")
                }
            }

            if !server.isDefault {
                Button {
                    appState.setDefaultServer(server)
                    reload()
                } label: {
                    Label("Set as Default", systemImage: "star")
                }
            }

            if server.isFallback {
                Button {
                    appState.setFallbackServer(nil)
                    reload()
                } label: {
                    Label("Clear Fallback", systemImage: "xmark.circle")
                }
            } else if !server.isDefault && servers.count > 1 {
                Button {
                    appState.setFallbackServer(server)
                    reload()
                } label: {
                    Label("Set as Fallback", systemImage: "arrow.triangle.2.circlepath")
                }
            }

            if !isCurrent {
                Divider()
                Button(role: .destructive) {
                    serverPendingRemoval = server
                } label: {
                    Label("Remove Server", systemImage: Symbols.trash)
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !server.isDefault {
                Button {
                    appState.setDefaultServer(server)
                    reload()
                } label: {
                    Label("Default", systemImage: "star.fill")
                }
                .tint(.yellow)
            }

            if !server.isDefault && !server.isFallback && servers.count > 1 {
                Button {
                    appState.setFallbackServer(server)
                    reload()
                } label: {
                    Label("Fallback", systemImage: "arrow.triangle.2.circlepath")
                }
                .tint(.blue)
            }
        }
        .swipeActions(edge: .trailing) {
            if !isCurrent {
                Button(role: .destructive) {
                    serverPendingRemoval = server
                } label: {
                    Label("Remove", systemImage: Symbols.trash)
                }
            }
        }
    }

    private var defaultServerID: Binding<String> {
        Binding(
            get: { servers.first(where: \.isDefault)?.id ?? servers.first?.id ?? "" },
            set: { id in
                guard let server = servers.first(where: { $0.id == id }) else { return }
                appState.setDefaultServer(server)
                reload()
            }
        )
    }

    private var fallbackServerID: Binding<String> {
        Binding(
            get: { servers.first(where: \.isFallback)?.id ?? "" },
            set: { id in
                if id.isEmpty {
                    appState.setFallbackServer(nil)
                } else if let server = servers.first(where: { $0.id == id }) {
                    appState.setFallbackServer(server)
                }
                reload()
            }
        )
    }

    private var removalBinding: Binding<Bool> {
        Binding(
            get: { serverPendingRemoval != nil },
            set: { if !$0 { serverPendingRemoval = nil } }
        )
    }

    private func reload() {
        servers = appState.servers()
    }

    private func remove(_ server: ServerRecord) {
        appState.removeServer(server)
        reload()
    }

    private func icon(for backend: MusicBackendKind) -> String {
        switch backend {
        case .plex: return "play.rectangle.fill"
        case .jellyfin: return "film.stack.fill"
        case .emby: return "play.square.stack.fill"
        case .subsonic: return Symbols.server
        }
    }
}

private struct AddServerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            LoginView(onLoginComplete: {
                onComplete()
                dismiss()
            }, isEmbeddedInSheet: true)
            .navigationTitle("Add Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
