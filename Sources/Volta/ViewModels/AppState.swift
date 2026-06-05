import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    enum Phase: Equatable {
        case loading
        case login
        case authenticated
    }

    private(set) var phase: Phase = .loading
    private(set) var client: SubsonicClient?
    private(set) var currentServer: ServerRecord?
    // whether the server supports public sharing (probed once on activate)
    private(set) var sharingAvailable = false
    // whether the client is currently pointed at the cellular URL
    private var activeIsCellular = false

    let audioPlayer = AudioPlayer()
    let store = ServerStore()
    let homeViewModel = HomeViewModel()

    func restoreSession() {
        // re-point the client at the right per-connection URL whenever Wi-Fi/cellular flips
        NetworkMonitor.shared.onConnectionChange { [weak self] conn in
            self?.handleNetworkChange(cellular: conn == .cellular)
        }
        let cellular = NetworkMonitor.shared.isCellular
        if let record = store.currentServer(), let config = store.config(for: record, cellular: cellular) {
            activeIsCellular = cellular
            activate(config: config, record: record)
            phase = .authenticated
        } else {
            phase = .login
        }
    }

    func completeLogin(config: SubsonicConfig) {
        let name = config.baseURL.host ?? "Server"
        let record = store.upsert(config: config, displayName: name)
        // honour a cellular override that may already be stored for this record
        let cellular = NetworkMonitor.shared.isCellular
        let effective = store.config(for: record, cellular: cellular) ?? config
        activeIsCellular = cellular
        activate(config: effective, record: record)
        phase = .authenticated
    }

    // persist a cellular-only URL for the current server and apply it immediately
    // if it changes which URL we should be using right now.
    func updateCellularURL(_ urlString: String?) {
        guard let record = currentServer else { return }
        currentServer = store.setCellularURL(urlString, for: record)
        reapplyNetworkURL()
    }

    private func handleNetworkChange(cellular: Bool) {
        activeIsCellular = cellular
        reapplyNetworkURL()
    }

    private func reapplyNetworkURL() {
        guard phase == .authenticated, let record = currentServer,
              let config = store.config(for: record, cellular: activeIsCellular) else { return }
        // only rebuild the client when the effective base URL actually changed —
        // avoids re-probing sharing + reloading home on every harmless path update.
        guard config.baseURL != client?.config.baseURL else { return }
        AppLogger.shared.log("🔀 Switching to \(activeIsCellular ? "cellular" : "Wi-Fi") URL: \(config.baseURL.absoluteString)", category: .networking)
        activate(config: config, record: record)
    }

    func logout() {
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

    func switchTo(_ record: ServerRecord) {
        let cellular = NetworkMonitor.shared.isCellular
        guard let config = store.config(for: record, cellular: cellular) else {
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
        let newClient = SubsonicClient(config: config)
        client = newClient
        currentServer = record
        audioPlayer.updateClient(newClient)
        IntentBridge.shared.setup(client: newClient, audioPlayer: audioPlayer)
        AppLogger.shared.log("Activated server: \(record.displayName)", category: .networking)
        sharingAvailable = false
        // Eager-load home data in the background
        Task {
            await homeViewModel.load(appState: self)
        }
        // Probe sharing capability once for the session
        Task {
            sharingAvailable = await newClient.sharingAvailable()
        }
    }
}
