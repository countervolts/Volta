import SwiftUI

// Every tab uses NavigationPath so its native routes and SettingsRoute can share
// one stack. Keep these destinations attached at each stack's root: nesting them
// under SettingsView caused NavigationRequestObserver to resubmit indefinitely
// on iOS versions before 26.
enum SettingsRoute: Hashable {
    case root
    case autoMix
    case autoMixPreview
    case equalizer
    case language
    case hiddenAlbums
    case performanceMode
    case developerTools
    case developerExperiments
    case playbackCacheDiagnostics
    case performanceOverlay
    case notifications
    case scrobbling
    case logs
    case changelog
    case editConnection
    case serverInfo
}

// Shared account/settings affordance for tab navigation stacks.
struct AccountToolbar: ViewModifier {
    @Binding var path: NavigationPath

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ServerMenuButton(onOpenSettings: { path.append(SettingsRoute.root) })
                }
            }
            .settingsDestinations()
    }
}

extension View {
    func accountToolbar(path: Binding<NavigationPath>) -> some View {
        modifier(AccountToolbar(path: path))
    }

    func settingsDestinations() -> some View {
        modifier(SettingsDestinations())
    }
}

private struct SettingsDestinations: ViewModifier {
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        content.navigationDestination(for: SettingsRoute.self) { route in
            switch route {
            case .root:
                SettingsView()
            case .autoMix:
                AutoMixSettingsView()
            case .autoMixPreview:
                AutoMixPreviewView()
            case .equalizer:
                EqualizerView()
            case .language:
                LanguageSettingsView()
            case .hiddenAlbums:
                HiddenAlbumsSettingsView(client: appState.client)
            case .performanceMode:
                PerformanceModeView()
            case .developerTools:
                DeveloperToolsView()
            case .developerExperiments:
                DeveloperExperimentsView()
            case .playbackCacheDiagnostics:
                PlaybackCacheDiagnosticsView()
            case .performanceOverlay:
                PerformanceOverlaySettingsView()
            case .notifications:
                NotificationSettingsView()
            case .scrobbling:
                ScrobblingSettingsView()
            case .logs:
                LogsView()
            case .changelog:
                ChangelogSettingsView()
            case .editConnection:
                EditConnectionView()
            case .serverInfo:
                ServerInfoView()
            }
        }
    }
}
