import SwiftUI

// Every tab uses NavigationPath so its native routes and SettingsRoute can share
// one stack. Keep these destinations attached at each stack's root: nesting them
// under SettingsView caused NavigationRequestObserver to resubmit indefinitely
// on iOS versions before 26.
enum SettingsRoute: Hashable {
    case root
    case autoMix
    case autoMixPreview
    case trackPairings
    case transcoding
    case equalizer
    case language
    case hiddenAlbums
    case savedLibrarySorts
    case downloadManager
    case homeCustomization
    case performanceMode
    case developerTools
    case developerExperiments
    case playbackCacheDiagnostics
    case reliabilityReports
    case performanceOverlay
    case notifications
    case scrobbling
    case logs
    case changelog
    case editConnection
    case serverInfo
}

/// Leaf settings screens intentionally use their own route type.
///
/// Settings categories are pushed with a direct `NavigationLink`, which lives
/// outside the route scope used to present the Settings root. Reusing
/// `SettingsRoute` for the category's value links makes SwiftUI either ignore
/// the destination or repeatedly resolve the root Settings screen. A leaf-only
/// route keeps the graph one-way: root -> category -> leaf screen.
enum SettingsDetailRoute: Hashable {
    case autoMix
    case autoMixPreview
    case trackPairings
    case transcoding
    case equalizer
    case language
    case hiddenAlbums
    case savedLibrarySorts
    case downloadManager
    case homeCustomization
    case performanceMode
    case developerTools
    case developerExperiments
    case playbackCacheDiagnostics
    case reliabilityReports
    case performanceOverlay
    case notifications
    case scrobbling
    case logs
    case changelog
    case editConnection
    case serverInfo

    init?(_ route: SettingsRoute) {
        switch route {
        case .root:
            return nil
        case .autoMix:
            self = .autoMix
        case .autoMixPreview:
            self = .autoMixPreview
        case .trackPairings:
            self = .trackPairings
        case .transcoding:
            self = .transcoding
        case .equalizer:
            self = .equalizer
        case .language:
            self = .language
        case .hiddenAlbums:
            self = .hiddenAlbums
        case .savedLibrarySorts:
            self = .savedLibrarySorts
        case .downloadManager:
            self = .downloadManager
        case .homeCustomization:
            self = .homeCustomization
        case .performanceMode:
            self = .performanceMode
        case .developerTools:
            self = .developerTools
        case .developerExperiments:
            self = .developerExperiments
        case .playbackCacheDiagnostics:
            self = .playbackCacheDiagnostics
        case .reliabilityReports:
            self = .reliabilityReports
        case .performanceOverlay:
            self = .performanceOverlay
        case .notifications:
            self = .notifications
        case .scrobbling:
            self = .scrobbling
        case .logs:
            self = .logs
        case .changelog:
            self = .changelog
        case .editConnection:
            self = .editConnection
        case .serverInfo:
            self = .serverInfo
        }
    }
}

/// A direct, leaf-only Settings link.
///
/// A category page is itself a direct navigation destination. On iOS 26/27,
/// value links declared within that destination cannot reliably see a handler
/// installed at the tab root. Pushing the leaf view directly avoids that scope
/// boundary while keeping the graph acyclic.
struct SettingsDetailNavigationLink<Label: View>: View {
    let route: SettingsDetailRoute
    private let label: () -> Label

    init(
        _ route: SettingsDetailRoute,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.route = route
        self.label = label
    }

    var body: some View {
        NavigationLink {
            SettingsDetailDestination(route: route)
        } label: {
            label()
        }
    }
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
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: SettingsRoute.self) { route in
                SettingsRouteDestination(route: route)
            }
            .navigationDestination(for: SettingsDetailRoute.self) { route in
                SettingsDetailDestination(route: route)
            }
    }
}

private struct SettingsRouteDestination: View {
    let route: SettingsRoute

    @ViewBuilder
    var body: some View {
        if case .root = route {
            SettingsView()
        } else if let detailRoute = SettingsDetailRoute(route) {
            SettingsDetailDestination(route: detailRoute)
        } else {
            EmptyView()
        }
    }
}

private struct SettingsDetailDestination: View {
    @EnvironmentObject private var appState: AppState
    let route: SettingsDetailRoute

    @ViewBuilder
    var body: some View {
        switch route {
        case .autoMix:
            AutoMixSettingsView()
        case .autoMixPreview:
            AutoMixPreviewView()
        case .trackPairings:
            TrackPairingSettingsView()
        case .transcoding:
            TranscodingSettingsView()
        case .equalizer:
            EqualizerView()
        case .language:
            LanguageSettingsView()
        case .hiddenAlbums:
            HiddenAlbumsSettingsView(client: appState.client)
        case .savedLibrarySorts:
            SavedLibrarySortsSettingsView()
        case .downloadManager:
            DownloadManagerView()
        case .homeCustomization:
            HomeCustomizationSettingsView()
        case .performanceMode:
            PerformanceModeView()
        case .developerTools:
            DeveloperToolsView()
        case .developerExperiments:
            DeveloperExperimentsView()
        case .playbackCacheDiagnostics:
            PlaybackCacheDiagnosticsView()
        case .reliabilityReports:
            ReliabilityReportsView()
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
