import Foundation
import Combine

enum WidgetStatsDestination: Equatable {
    case listening
    case library
}

@MainActor
final class AppState: ObservableObject {
    // Shared instance so non-SwiftUI scenes (CarPlay) can drive session restore
    // and reach the live client/player even when the iPhone window never opens.
    static let shared = AppState()

    enum Phase: Equatable {
        case loading
        case login
        case authenticated
    }

    enum ConnectionIssue: Equatable {
        case slow
        case failed(String)
    }

    // Guards restoreSession against running twice (e.g. CarPlay restores while
    // launched in the background, then the phone scene appears and tries again).
    private var didStartRestore = false

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var client: (any MusicService)?
    @Published private(set) var currentServer: ServerRecord?
    @Published private(set) var connectionIssue: ConnectionIssue?
    @Published private(set) var isConnectionAttemptActive = false
    @Published private(set) var isOfflineMode = false
    // Set by a Home Screen widget URL and consumed once the Stats tab is ready.
    @Published private(set) var requestedWidgetStatsDestination: WidgetStatsDestination?
    // probed once on activate
    @Published private(set) var sharingAvailable = false
    // The alternate endpoint is used on cellular and, when preferred SSIDs
    // are configured, on every network other than those exact Wi-Fi names.
    private var activeUsesCellularEndpoint = false
    // lets newer activations beat slow auth handshakes
    private var activationID = UUID()
    private var activationTask: Task<Void, Never>?
    private var slowConnectionTask: Task<Void, Never>?
    private var pendingConfig: SubsonicConfig?

    private static let slowConnectionThresholdNanoseconds: UInt64 = 8_000_000_000

    let audioPlayer = AudioPlayer()
    let store = ServerStore()
    let homeViewModel = HomeViewModel()

    private var cancellables: Set<AnyCancellable> = []

    private init() {
        // `currentTime` advances throughout playback. Relaying AudioPlayer's
        // unfiltered objectWillChange here invalidates every AppState consumer
        // (including hidden tabs and player stages) for each clock update.
        // Keep global presentation in sync with real player state changes, and
        // let time-sensitive surfaces subscribe to the playback clock directly.
        let audioStateChanges: [AnyPublisher<Void, Never>] = [
            audioPlayer.$currentSong.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            audioPlayer.$hasActivePlaybackSession.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            audioPlayer.$isPlaying.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            audioPlayer.$duration.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            audioPlayer.$currentArtwork.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            audioPlayer.$currentAnimatedArtwork.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            audioPlayer.$currentLiveArtwork.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            audioPlayer.$currentPlaybackUsesTranscode.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            audioPlayer.$queue.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            audioPlayer.$currentIndex.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            audioPlayer.$queueSourceTitle.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            audioPlayer.$queueSourceAlbum.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            audioPlayer.$queueSourcePlaylist.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            audioPlayer.$playbackHistory.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            audioPlayer.$isShuffle.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            audioPlayer.$repeatMode.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            audioPlayer.$autoplayMode.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            audioPlayer.$transitionMode.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            audioPlayer.$starredIDs.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            audioPlayer.$isMixing.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            audioPlayer.$autoplayArtistName.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            audioPlayer.$autoplayArtistId.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            audioPlayer.$sleepTimerActive.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            audioPlayer.$sleepEndsAtTrackEnd.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            audioPlayer.$sleepRemaining.dropFirst().map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(audioStateChanges)
            .sink { [weak self] _ in
                Task { @MainActor in self?.objectWillChange.send() }
            }
            .store(in: &cancellables)

        homeViewModel.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in self?.objectWillChange.send() }
            }
            .store(in: &cancellables)

        LiveLyricsActivityManager.shared.connect(appState: self)
    }

    func restoreSession() {
        guard !didStartRestore else { return }
        didStartRestore = true
        AppLogger.shared.logAlways("Session restore started", category: .settings)
        // Wi-Fi/cellular can change the effective server URL.
        NetworkMonitor.shared.onConnectionChange { [weak self] _ in
            self?.handleNetworkChange()
        }
        NetworkMonitor.shared.onSSIDChange { [weak self] _ in
            self?.reapplyNetworkURL()
        }
        Task { [weak self] in
            await NetworkMonitor.shared.refreshCurrentSSID()
            self?.restoreStoredSession()
        }
    }

    private func restoreStoredSession() {
        let useCellularEndpoint = shouldUseCellularEndpoint
        let candidates = store.startupServers()
        if let restored = candidates.compactMap({ record -> (ServerRecord, SubsonicConfig)? in
            guard let config = store.config(for: record, cellular: useCellularEndpoint) else { return nil }
            return (record, config)
        }).first {
            let (record, config) = restored
            AppLogger.shared.log(
                "Stored session found; server=\(record.displayName); alternateEndpoint=\(useCellularEndpoint)",
                category: .networking
            )
            store.setCurrent(record)
            applyEndpointRoute(useCellularEndpoint)
            let activeRecord = store.currentServer() ?? record
            activate(config: config, record: activeRecord, allowFallback: true)
        } else {
            AppLogger.shared.log("No stored session; showing login", category: .ui)
            phase = .login
        }
    }

    func completeLogin(
        config: SubsonicConfig,
        kind: MusicBackendKind = .subsonic,
        displayName: String? = nil
    ) {
        let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (trimmedName?.isEmpty == false ? trimmedName : nil) ?? config.baseURL.host ?? "Server"
        let record = store.upsert(config: config, displayName: name, backend: kind)
        // Reuse any stored cellular override for this record.
        let useCellularEndpoint = shouldUseCellularEndpoint
        let effective = store.config(for: record, cellular: useCellularEndpoint) ?? config
        applyEndpointRoute(useCellularEndpoint)
        activate(config: effective, record: record)
    }

    // Persist and apply the current server's cellular override.
    func updateCellularConnection(urlString: String?, username: String?, password: String?) {
        guard let record = currentServer else { return }
        currentServer = store.setCellularConnection(
            urlString: urlString,
            username: username,
            password: password,
            for: record
        )
        reapplyNetworkURL()
    }

    private func handleNetworkChange() {
        reapplyNetworkURL()
    }

    private func reapplyNetworkURL() {
        guard !isOfflineMode,
              phase == .authenticated || phase == .loading,
              let record = currentServer else { return }
        let useCellularEndpoint = shouldUseCellularEndpoint
        applyEndpointRoute(useCellularEndpoint)
        guard let config = store.config(for: record, cellular: useCellularEndpoint) else { return }
        if isConnectionAttemptActive, config == pendingConfig { return }
        if phase == .authenticated, config == client?.config {
            if let plex = client as? PlexClient {
                AppLogger.shared.log(
                    "Refreshing Plex connection preference for \(useCellularEndpoint ? "alternate" : "preferred Wi-Fi") endpoint",
                    category: .networking
                )
                Task { await plex.refreshConnection(preferLocal: !useCellularEndpoint) }
            }
            return
        }
        AppLogger.shared.log(
            "Network URL switching to \(useCellularEndpoint ? "alternate" : "preferred Wi-Fi"): \(config.baseURL.absoluteString)",
            category: .networking
        )
        activate(config: config, record: record, allowFallback: true)
    }

    func refreshWiFiLoginPolicy() {
        Task {
            await NetworkMonitor.shared.refreshCurrentSSID()
            reapplyNetworkURL()
        }
    }

    private var shouldUseCellularEndpoint: Bool {
        WiFiSSIDPolicy.shouldUseCellularEndpoint(
            connection: NetworkMonitor.shared.connection,
            currentSSID: NetworkMonitor.shared.currentSSID
        )
    }

    private func applyEndpointRoute(_ usesCellularEndpoint: Bool) {
        activeUsesCellularEndpoint = usesCellularEndpoint
        // Plex connection ranking and playback quality already consume this
        // route flag. Keep them aligned with effective SSID routing, not merely
        // the device's physical radio type.
        UserDefaults.standard.set(usesCellularEndpoint, forKey: "networkIsCellular")
    }

    func continueConnectionAttempt() {
        if isConnectionAttemptActive {
            connectionIssue = nil
            scheduleSlowConnectionNotice(for: activationID)
        } else {
            retryConnection()
        }
    }

    func retryConnection() {
        guard let record = currentServer else {
            phase = .login
            return
        }
        isOfflineMode = false
        let useCellularEndpoint = shouldUseCellularEndpoint
        applyEndpointRoute(useCellularEndpoint)
        guard let config = store.config(for: record, cellular: useCellularEndpoint) else {
            phase = .login
            return
        }
        activate(config: config, record: record, allowFallback: true)
    }

    func useOfflineMode() {
        activationID = UUID()
        activationTask?.cancel()
        activationTask = nil
        slowConnectionTask?.cancel()
        slowConnectionTask = nil
        pendingConfig = nil
        isConnectionAttemptActive = false
        connectionIssue = nil
        isOfflineMode = true
        client = nil
        sharingAvailable = false
        audioPlayer.updateClient(nil)
        IntentBridge.shared.teardown()
        phase = .authenticated
        AppLogger.shared.log("Offline mode selected", category: .networking)
    }

    func logout() {
        AppLogger.shared.logAlways("Logout started; server=\(currentServer?.displayName ?? "none")", category: .settings)
        audioPlayer.stopAndClear()
        store.clearCurrent()
        activationID = UUID()
        activationTask?.cancel()
        activationTask = nil
        slowConnectionTask?.cancel()
        slowConnectionTask = nil
        pendingConfig = nil
        isConnectionAttemptActive = false
        connectionIssue = nil
        isOfflineMode = false
        client = nil
        currentServer = nil
        audioPlayer.updateClient(nil)
        IntentBridge.shared.teardown()
        phase = .login
    }

    func persistPlaybackSession() {
        audioPlayer.persistLastPlaybackSession(synchronize: true)
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "volta", url.host?.lowercased() == "stats" else { return }
        let destination = url.pathComponents.drop(while: { $0 == "/" }).first?.lowercased()
        requestedWidgetStatsDestination = destination == "library" ? .library : .listening
    }

    func consumeWidgetStatsDestination() -> WidgetStatsDestination? {
        defer { requestedWidgetStatsDestination = nil }
        return requestedWidgetStatsDestination
    }

    func servers() -> [ServerRecord] {
        store.allServers()
    }

    /// URL used by the active or pending connection attempt. This differs
    /// from the saved primary URL while a cellular route is selected.
    var activeServerURLString: String? {
        client?.config.baseURL.absoluteString ?? pendingConfig?.baseURL.absoluteString
    }

    func defaultServer() -> ServerRecord? {
        store.defaultServer()
    }

    func fallbackServer() -> ServerRecord? {
        store.fallbackServer()
    }

    func setDefaultServer(_ record: ServerRecord) {
        _ = store.setDefault(record)
        refreshCurrentServerFromStore()
    }

    func setFallbackServer(_ record: ServerRecord?) {
        _ = store.setFallback(record)
        refreshCurrentServerFromStore()
    }

    func removeServer(_ record: ServerRecord) {
        // Never delete the server we're currently connected to.
        guard record.id != currentServer?.id else { return }
        store.remove(record)
        refreshCurrentServerFromStore()
    }

    func switchTo(_ record: ServerRecord) {
        let useCellularEndpoint = shouldUseCellularEndpoint
        guard let config = store.config(for: record, cellular: useCellularEndpoint) else {
            audioPlayer.stopAndClear()
            client = nil
            currentServer = nil
            audioPlayer.updateClient(nil)
            IntentBridge.shared.teardown()
            store.setCurrent(record)
            phase = .login
            return
        }
        store.setCurrent(record)
        applyEndpointRoute(useCellularEndpoint)
        activate(config: config, record: record)
    }

    private func activate(config: SubsonicConfig, record: ServerRecord, allowFallback: Bool = false) {
        activationTask?.cancel()
        slowConnectionTask?.cancel()
        currentServer = record
        sharingAvailable = false
        isOfflineMode = false
        connectionIssue = nil
        isConnectionAttemptActive = true
        pendingConfig = config
        phase = .loading
        AppLogger.shared.log("Activating server: \(record.displayName) [\(record.backend.rawValue)]", category: .networking)
        // Tag the attempt so newer server switches win.
        let token = UUID()
        activationID = token
        scheduleSlowConnectionNotice(for: token)
        activationTask = Task {
            let started = ProcessInfo.processInfo.systemUptime
            do {
                let service = try await MusicServiceFactory.make(config: config, kind: record.backend)
                try await service.ping()
                guard activationID == token else {
                    AppLogger.shared.log("Server activation superseded; server=\(record.displayName)", category: .networking)
                    return
                }
                finishActivation(service: service, config: config, record: record, started: started)
            } catch {
                guard activationID == token else {
                    AppLogger.shared.log("Server activation superseded; server=\(record.displayName)", category: .networking)
                    return
                }
                if allowFallback,
                   beginFallbackActivation(from: record, reason: "primary activation or health check failed") {
                    return
                }
                failActivation(record: record, error: error)
            }
        }
    }

    private func finishActivation(service: any MusicService, config: SubsonicConfig, record: ServerRecord, started: TimeInterval) {
        slowConnectionTask?.cancel()
        slowConnectionTask = nil
        activationTask = nil
        pendingConfig = nil
        isConnectionAttemptActive = false
        connectionIssue = nil
        isOfflineMode = false
        var activeRecord = record
        if record.backend == .plex, service.config != config {
            activeRecord = store.update(
                record: record,
                config: service.config,
                displayName: record.displayName,
                backend: record.backend
            )
            currentServer = activeRecord
        }
        client = service
        phase = .authenticated
        TrackPairingStore.shared.selectServer(activeRecord.id)
        audioPlayer.updateClient(service, serverID: activeRecord.id)
        IntentBridge.shared.setup(client: service, audioPlayer: audioPlayer)
        AppLogger.shared.log(
            "Server activated; server=\(activeRecord.displayName); backend=\(activeRecord.backend.rawValue); elapsedMs=\(Int((ProcessInfo.processInfo.systemUptime - started) * 1000))",
            category: .networking
        )
        Task { await audioPlayer.restoreLastPlaybackSessionIfNeeded() }
        // Probe sharing and warm Home in the background.
        Task { sharingAvailable = await service.sharingAvailable() }
        Task { await homeViewModel.load(appState: self) }
    }

    private func beginFallbackActivation(from record: ServerRecord, reason: String) -> Bool {
        guard NetworkMonitor.shared.connection != .none,
              let fallback = store.fallbackServer(excluding: record),
              let config = store.config(for: fallback, cellular: activeUsesCellularEndpoint) else { return false }
        AppLogger.shared.log("Trying fallback server; from=\(record.displayName); fallback=\(fallback.displayName); reason=\(reason)", category: .networking)
        store.setCurrent(fallback)
        activate(config: config, record: store.currentServer() ?? fallback, allowFallback: false)
        return true
    }

    private func scheduleSlowConnectionNotice(for token: UUID) {
        slowConnectionTask?.cancel()
        slowConnectionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.slowConnectionThresholdNanoseconds)
            guard !Task.isCancelled,
                  let self,
                  self.activationID == token,
                  self.isConnectionAttemptActive else { return }
            self.connectionIssue = .slow
        }
    }

    private func failActivation(record: ServerRecord, error: Error) {
        slowConnectionTask?.cancel()
        slowConnectionTask = nil
        activationTask = nil
        pendingConfig = nil
        isConnectionAttemptActive = false
        connectionIssue = .failed(connectionFailureReason(for: error))
        AppLogger.shared.log(
            "Server activation failed: \(record.displayName) - \(error.localizedDescription)",
            category: .networking,
            level: .error
        )
    }

    private func connectionFailureReason(for error: Error) -> String {
        if NetworkMonitor.shared.connection == .none {
            return "No network connection is available."
        }
        if let subsonicError = error as? SubsonicError {
            switch subsonicError {
            case .invalidCredentials:
                return "The server rejected the saved username or password."
            case .invalidResponse:
                return "The server replied, but its response could not be read."
            case .serverUnreachable:
                return "The server did not respond. It may be offline, unreachable from this network, or still starting up."
            case .server(_, let message):
                return message.isEmpty ? "The server returned an error." : message
            }
        }
        return "The connection could not be established: \(error.localizedDescription)"
    }

    private func refreshCurrentServerFromStore() {
        guard let currentServer else { return }
        self.currentServer = store.allServers().first { $0.id == currentServer.id }
    }
}
