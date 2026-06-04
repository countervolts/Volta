import Foundation
import Network
import Observation

// watches the active network path so the app can switch behaviour between Wi-Fi
// and cellular — used to pick a per-connection server URL (a local LAN address on
// Wi-Fi, a public one on cellular) and to apply the cellular streaming quality.
@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    enum Connection: String, Sendable { case wifi, cellular, other, none }

    private(set) var connection: Connection = .wifi
    var isCellular: Bool { connection == .cellular }

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.ayo.music.network-monitor")
    private var onChange: [(Connection) -> Void] = []

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let conn = NetworkMonitor.classify(path)
            Task { @MainActor in self?.update(conn) }
        }
        monitor.start(queue: queue)
    }

    // register a handler fired (on the main actor) whenever the connection TYPE changes.
    func onConnectionChange(_ handler: @escaping (Connection) -> Void) {
        onChange.append(handler)
    }

    private func update(_ conn: Connection) {
        guard conn != connection else { return }
        let previous = connection
        connection = conn
        // mirror to UserDefaults so the nonisolated stream/download URL builders
        // (which can't touch this main-actor type) can read the current type cheaply.
        UserDefaults.standard.set(conn == .cellular, forKey: "networkIsCellular")
        AppLogger.shared.log("📶 Network: \(previous.rawValue) → \(conn.rawValue)", category: .networking)
        for handler in onChange { handler(conn) }
    }

    nonisolated private static func classify(_ path: NWPath) -> Connection {
        guard path.status == .satisfied else { return .none }
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.wiredEthernet) { return .wifi }   // treat wired like Wi-Fi
        if path.usesInterfaceType(.cellular) { return .cellular }
        return .other
    }
}
