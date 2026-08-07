import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
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
            CrashHangReporter.shared.start()
            updateReliabilityMonitoring(for: scenePhase)
            if !didLogDiagnostics {
                didLogDiagnostics = true
                AppDiagnostics.logLaunch()
            }
            appState.restoreSession()
        }
        .onChangeCompat(of: scenePhase) { _, phase in
            updateReliabilityMonitoring(for: phase)
            if phase == .background {
                appState.persistPlaybackSession()
            }
        }
    }

    private func updateReliabilityMonitoring(for phase: ScenePhase) {
        switch phase {
        case .active:
            CrashHangReporter.shared.beginForegroundMonitoring()
        case .inactive:
            CrashHangReporter.shared.pauseForegroundMonitoring()
        case .background:
            CrashHangReporter.shared.endForegroundMonitoring()
        @unknown default:
            CrashHangReporter.shared.pauseForegroundMonitoring()
        }
    }
}
