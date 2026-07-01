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
        if let record = store.currentServer(), let config = store.config(for: record, cellular: cellular) {
            AppLogger.shared.log("Stored session found; server=\(record.displayName); cellular=\(cellular)", category: .networking)
            activeIsCellular = cellular
            activate(config: config, record: record)
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
        activate(config: config, record: record)
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

    func servers() -> [ServerRecord] {
        store.allServers()
    }

    func removeServer(_ record: ServerRecord) {
        // Never delete the server we're currently connected to.
        guard record.id != currentServer?.id else { return }
        store.remove(record)
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

    private func activate(config: SubsonicConfig, record: ServerRecord) {
        currentServer = record
        sharingAvailable = false
        AppLogger.shared.log("Activating server: \(record.displayName) [\(record.backend.rawValue)]", category: .networking)
        // Tag the attempt so newer server switches win.
        let token = UUID()
        activationID = token
        Task {
            let started = ProcessInfo.processInfo.systemUptime
            let service = try? await MusicServiceFactory.make(config: config, kind: record.backend)
            guard activationID == token else {
                AppLogger.shared.log("Server activation superseded; server=\(record.displayName)", category: .networking)
                return
            }
            guard let service else {
                AppLogger.shared.log("Server activation failed: \(record.displayName)", category: .networking, level: .error)
                return
            }
            client = service
            audioPlayer.updateClient(service)
            IntentBridge.shared.setup(client: service, audioPlayer: audioPlayer)
            AppLogger.shared.log(
                "Server activated; server=\(record.displayName); backend=\(record.backend.rawValue); elapsedMs=\(Int((ProcessInfo.processInfo.systemUptime - started) * 1000))",
                category: .networking
            )
            // Probe sharing and warm Home in the background.
            Task { sharingAvailable = await service.sharingAvailable() }
            Task { await homeViewModel.load(appState: self) }
        }
    }
}
