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

    let audioPlayer = AudioPlayer()
    let store = ServerStore()
    let homeViewModel = HomeViewModel()

    func restoreSession() {
        if let record = store.currentServer(), let config = store.config(for: record) {
            activate(config: config, record: record)
            phase = .authenticated
        } else {
            phase = .login
        }
    }

    func completeLogin(config: SubsonicConfig) {
        let name = config.baseURL.host ?? "Server"
        let record = store.upsert(config: config, displayName: name)
        activate(config: config, record: record)
        phase = .authenticated
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
        guard let config = store.config(for: record) else {
            store.setCurrent(record)
            phase = .login
            return
        }
        store.setCurrent(record)
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
        // Eager-load home data in the background
        Task {
            await homeViewModel.load(appState: self)
        }
    }
}
