import SwiftUI

// Switch between saved servers; touch-and-hold (or swipe) a server to remove it.
struct ServerSwitcherSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var servers: [ServerRecord] = []
    @State private var serverPendingRemoval: ServerRecord?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                List {
                    Section {
                        ForEach(servers) { server in
                            row(for: server)
                        }
                    } footer: {
                        Text("Touch and hold a server to remove it. The server you're connected to can't be removed.")
                    }
                    .listRowBackground(Theme.secondaryBackground)
                }
                .scrollContentBackground(.hidden)
                .background(Theme.background)
            }
            .navigationTitle("Switch Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .preferredColorScheme(Theme.colorScheme)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { servers = appState.servers() }
        .alert("Remove Server", isPresented: removalBinding, presenting: serverPendingRemoval) { server in
            Button("Remove", role: .destructive) { remove(server) }
            Button("Cancel", role: .cancel) {}
        } message: { server in
            Text("Remove \(server.displayName)? You'll need to sign in again to use it.")
        }
    }

    @ViewBuilder
    private func row(for server: ServerRecord) -> some View {
        let isCurrent = server.id == appState.currentServer?.id
        Button {
            guard !isCurrent else { return }
            appState.switchTo(server)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: Symbols.server)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.displayName)
                        .foregroundStyle(Theme.primaryText)
                    Text(server.username)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                if isCurrent {
                    Image(systemName: Symbols.check)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !isCurrent {
                Button(role: .destructive) {
                    serverPendingRemoval = server
                } label: {
                    Label("Remove Server", systemImage: Symbols.trash)
                }
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

    private var removalBinding: Binding<Bool> {
        Binding(
            get: { serverPendingRemoval != nil },
            set: { if !$0 { serverPendingRemoval = nil } }
        )
    }

    private func remove(_ server: ServerRecord) {
        appState.removeServer(server)
        servers = appState.servers()
        // Nothing left to switch between once only the current server remains.
        if servers.count < 2 { dismiss() }
    }
}
