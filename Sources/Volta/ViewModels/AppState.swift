import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    // Shared instance so non-SwiftUI scenes (CarPlay) can drive session restore
    // and reach the live client/player even when the iPhone window never opens.
    static let shared = AppState()

    enum Phase: Equatable {
        case loading
        case login
        case authenticated
    }

    // Guards restoreSession against running twice (e.g. CarPlay restores while
    // launched in the background, then the phone scene appears and tries again).
    private var didStartRestore = false

    private(set) var phase: Phase = .loading
    private(set) var client: (any MusicService)?
    private(set) var currentServer: ServerRecord?
    // probed once on activate
    private(set) var sharingAvailable = false
    // current effective URL is the cellular override
    private var activeIsCellular = false
    // lets newer activations beat slow auth handshakes
    private var activationID = UUID()

    let audioPlayer = AudioPlayer()
    let store = ServerStore()
    let homeViewModel = HomeViewModel()

    func restoreSession() {
        guard !didStartRestore else { return }
        didStartRestore = true
        AppLogger.shared.logAlways("Session restore started", category: .other)
        // Wi-Fi/cellular can change the effective server URL.
        NetworkMonitor.shared.onConnectionChange { [weak self] conn in
            self?.handleNetworkChange(cellular: conn == .cellular)
        }
        let cellular = NetworkMonitor.shared.isCellular
        let candidates = store.startupServers()
        if let restored = candidates.compactMap({ record -> (ServerRecord, SubsonicConfig)? in
            guard let config = store.config(for: record, cellular: cellular) else { return nil }
            return (record, config)
        }).first {
            let (record, config) = restored
            AppLogger.shared.log("Stored session found; server=\(record.displayName); cellular=\(cellular)", category: .networking)
            store.setCurrent(record)
            activeIsCellular = cellular
            activate(config: config, record: store.currentServer() ?? record, allowFallback: true)
            phase = .authenticated
        } else {
            AppLogger.shared.log("No stored session; showing login", category: .other)
            phase = .login
        }
    }

    func completeLogin(config: SubsonicConfig, kind: MusicBackendKind = .subsonic) {
        let name = config.baseURL.host ?? "Server"
        let record = store.upsert(config: config, displayName: name, backend: kind)
        // Reuse any stored cellular override for this record.
        let cellular = NetworkMonitor.shared.isCellular
        let effective = store.config(for: record, cellular: cellular) ?? config
        activeIsCellular = cellular
        activate(config: effective, record: record)
        phase = .authenticated
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

    private func handleNetworkChange(cellular: Bool) {
        activeIsCellular = cellular
        reapplyNetworkURL()
    }

    private func reapplyNetworkURL() {
        guard phase == .authenticated, let record = currentServer,
              let config = store.config(for: record, cellular: activeIsCellular) else { return }
        // Rebuild only when the effective base URL changes.
        guard config != client?.config else { return }
        AppLogger.shared.log("Network URL switching to \(activeIsCellular ? "cellular" : "Wi-Fi"): \(config.baseURL.absoluteString)", category: .networking)
        activate(config: config, record: record, allowFallback: true)
    }

    func logout() {
        AppLogger.shared.logAlways("Logout started; server=\(currentServer?.displayName ?? "none")", category: .other)
        audioPlayer.stopAndClear()
        store.clearCurrent()
        client = nil
        currentServer = nil
        audioPlayer.updateClient(nil)
        IntentBridge.shared.teardown()
        phase = .login
    }

    func persistPlaybackSession() {
        audioPlayer.persistLastPlaybackSession(synchronize: true)
    }

    func servers() -> [ServerRecord] {
        store.allServers()
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
        let cellular = NetworkMonitor.shared.isCellular
        guard let config = store.config(for: record, cellular: cellular) else {
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
        activeIsCellular = cellular
        activate(config: config, record: record)
        phase = .authenticated
    }

    private func activate(config: SubsonicConfig, record: ServerRecord, allowFallback: Bool = false) {
        currentServer = record
        sharingAvailable = false
        AppLogger.shared.log("Activating server: \(record.displayName) [\(record.backend.rawValue)]", category: .networking)
        // Tag the attempt so newer server switches win.
        let token = UUID()
        activationID = token
        Task {
            let started = ProcessInfo.processInfo.systemUptime
            do {
                let service = try await MusicServiceFactory.make(config: config, kind: record.backend)
                guard activationID == token else {
                    AppLogger.shared.log("Server activation superseded; server=\(record.displayName)", category: .networking)
                    return
                }
                if await shouldUseFallback(afterBuilding: service, record: record, allowFallback: allowFallback),
                   beginFallbackActivation(from: record, reason: "primary health check failed") {
                    return
                }
                finishActivation(service: service, config: config, record: record, started: started)
            } catch {
                guard activationID == token else {
                    AppLogger.shared.log("Server activation superseded; server=\(record.displayName)", category: .networking)
                    return
                }
                if beginFallbackActivation(from: record, reason: "primary activation failed") {
                    return
                }
                AppLogger.shared.log("Server activation failed: \(record.displayName)", category: .networking, level: .error)
                return
            }
        }
    }

    private func finishActivation(service: any MusicService, config: SubsonicConfig, record: ServerRecord, started: TimeInterval) {
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

    private func shouldUseFallback(afterBuilding service: any MusicService, record: ServerRecord, allowFallback: Bool) async -> Bool {
        guard allowFallback,
              NetworkMonitor.shared.connection != .none,
              store.fallbackServer(excluding: record) != nil else { return false }
        do {
            try await service.ping()
            return false
        } catch {
            AppLogger.shared.log("Primary server health check failed; server=\(record.displayName)", category: .networking, level: .error)
            return true
        }
    }

    private func beginFallbackActivation(from record: ServerRecord, reason: String) -> Bool {
        guard NetworkMonitor.shared.connection != .none,
              let fallback = store.fallbackServer(excluding: record),
              let config = store.config(for: fallback, cellular: activeIsCellular) else { return false }
        AppLogger.shared.log("Trying fallback server; from=\(record.displayName); fallback=\(fallback.displayName); reason=\(reason)", category: .networking)
        store.setCurrent(fallback)
        activate(config: config, record: store.currentServer() ?? fallback, allowFallback: false)
        return true
    }

    private func refreshCurrentServerFromStore() {
        guard let currentServer else { return }
        self.currentServer = store.allServers().first { $0.id == currentServer.id }
    }
}
