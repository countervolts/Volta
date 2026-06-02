import SwiftUI

// switches between login and the main app based on session phase, with an
// animated crossfade.
struct RootView: View {
    @Environment(AppState.self) private var appState
    // observe accent so the whole window tint refreshes live on change
    @AppStorage("accentColorName") private var accentColorName = "purple"

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            switch appState.phase {
            case .loading:
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.accent)
            case .login:
                LoginView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .authenticated:
                MainTabView()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            }
        }
        .tint(Theme.accent)
        .animation(.spring(response: 0.55, dampingFraction: 0.9), value: appState.phase)
        .task {
            appState.restoreSession()
        }
    }
}
