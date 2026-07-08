import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("accentColorName") private var accentColorName = "purple"
    @AppStorage("customAccentRed") private var customAccentRed = 0.55
    @AppStorage("customAccentGreen") private var customAccentGreen = 0.36
    @AppStorage("customAccentBlue") private var customAccentBlue = 0.96
    @AppStorage("themeMode") private var themeMode = "dark"
    @State private var didLogDiagnostics = false

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
                    .id(themeMode)   // rebuild on dark/amoled switch (light handled by colorScheme)
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            }

            VoltaNotificationHost()
                .zIndex(100)
        }
        .tint(Theme.accent)
        .animation(.spring(response: 0.55, dampingFraction: 0.9), value: appState.phase)
        .animation(.easeInOut(duration: 0.2), value: accentRefreshKey)
        .task {
            if !didLogDiagnostics {
                didLogDiagnostics = true
                AppDiagnostics.logLaunch()
            }
            appState.restoreSession()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            appState.persistPlaybackSession()
        }
    }
}
