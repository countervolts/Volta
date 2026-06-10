import Foundation

enum DeveloperSimulation {
    enum Keys {
        static let slowServerEnabled = "developerSimSlowServer"
        static let slowServerDelayMS = "developerSimSlowServerDelayMS"
        static let expiredSession = "developerSimExpiredSession"
        static let noNetwork = "developerSimNoNetwork"
    }

    static var slowServerEnabled: Bool {
        UserDefaults.standard.bool(forKey: Keys.slowServerEnabled)
    }

    static var slowServerDelayMS: Int {
        let value = UserDefaults.standard.integer(forKey: Keys.slowServerDelayMS)
        return value > 0 ? value : 1200
    }

    static var expiredSession: Bool {
        UserDefaults.standard.bool(forKey: Keys.expiredSession)
    }

    static var noNetwork: Bool {
        UserDefaults.standard.bool(forKey: Keys.noNetwork)
    }

    static var isActive: Bool {
        slowServerEnabled || expiredSession || noNetwork
    }

    static func prepareRequest(endpoint: String) async throws {
        if noNetwork {
            AppLogger.shared.logAlways(
                "Developer simulation: no network for \(endpoint)",
                category: .networking,
                level: .warning
            )
            throw SubsonicError.serverUnreachable
        }

        if expiredSession {
            AppLogger.shared.logAlways(
                "Developer simulation: expired session for \(endpoint)",
                category: .networking,
                level: .warning
            )
            throw SubsonicError.invalidCredentials
        }

        if slowServerEnabled {
            let delay = max(100, min(slowServerDelayMS, 10_000))
            AppLogger.shared.log(
                "Developer simulation: delaying \(endpoint) by \(delay)ms",
                category: .networking
            )
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
        }
    }

    static func reset() {
        UserDefaults.standard.set(false, forKey: Keys.slowServerEnabled)
        UserDefaults.standard.set(false, forKey: Keys.expiredSession)
        UserDefaults.standard.set(false, forKey: Keys.noNetwork)
    }
}
