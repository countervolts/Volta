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
                StartupConnectionView(
                    issue: appState.connectionIssue,
                    serverName: appState.activeServerURLString ?? appState.currentServer?.displayName,
                    isStillTrying: appState.isConnectionAttemptActive,
                    onContinue: appState.continueConnectionAttempt,
                    onOffline: appState.useOfflineMode
                )
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
        .onOpenURL { appState.handleIncomingURL($0) }
    }

    private func updateReliabilityMonitoring(for phase: ScenePhase) {
        switch phase {
        case .active:
            CrashHangReporter.shared.beginForegroundMonitoring()
            Task { await NetworkMonitor.shared.refreshCurrentSSID() }
        case .inactive:
            CrashHangReporter.shared.pauseForegroundMonitoring()
        case .background:
            CrashHangReporter.shared.endForegroundMonitoring()
        @unknown default:
            CrashHangReporter.shared.pauseForegroundMonitoring()
        }
    }
}

private struct StartupConnectionView: View {
    let issue: AppState.ConnectionIssue?
    let serverName: String?
    let isStillTrying: Bool
    let onContinue: () -> Void
    let onOffline: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            if issue == nil {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.accent)

                VStack(spacing: 7) {
                    Text(L(.login_connecting))
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                    if let serverName {
                        Text(serverName)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            } else {
                issueContent
            }
        }
        .padding(.horizontal, 34)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    private var issueContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)

            VStack(spacing: 9) {
                Text("Unable to Connect")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.primaryText)

                Text(issueMessage)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isStillTrying {
                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.accent)
                    Text("Still trying in the background…")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            VStack(spacing: 12) {
                Button(action: onContinue) {
                    Label("Continue Trying", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onOffline) {
                    Label("Offline Mode", systemImage: "arrow.down.circle")
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var issueMessage: String {
        switch issue {
        case .slow:
            return "The server is taking longer than expected. You can let Volta keep trying, or use your downloaded music offline."
        case .failed(let reason):
            return "\(reason) Check the server and this device’s network, then try again or continue with downloaded music."
        case nil:
            return ""
        }
    }
}
