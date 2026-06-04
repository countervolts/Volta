import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("accentColorName") private var accentColorName = "purple"
    @AppStorage("customAccentRed") private var customAccentRed = 0.55
    @AppStorage("customAccentGreen") private var customAccentGreen = 0.36
    @AppStorage("customAccentBlue") private var customAccentBlue = 0.96

    private var accentRefreshKey: String {
        "\(accentColorName)-\(customAccentRed)-\(customAccentGreen)-\(customAccentBlue)"
    }

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
        .animation(.easeInOut(duration: 0.2), value: accentRefreshKey)
        .task {
            appState.restoreSession()
        }
    }
}
