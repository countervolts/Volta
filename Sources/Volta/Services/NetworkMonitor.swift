import Foundation
import Network
import NetworkExtension
@preconcurrency import CoreLocation
import Combine

@MainActor
final class NetworkMonitor: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = NetworkMonitor()

    enum Connection: String, Sendable { case wifi, cellular, other, none }

    @Published private(set) var connection: Connection = .wifi
    @Published private(set) var currentSSID: String?
    var isCellular: Bool { connection == .cellular }

    private let monitor = NWPathMonitor()
    private let queue = DeveloperExperiments.queue(label: "com.ayo.music.network-monitor")
    private var onChange: [(Connection) -> Void] = []
    private var onSSIDChange: [(String?) -> Void] = []
    private let locationManager = CLLocationManager()

    private override init() {
        super.init()
        locationManager.delegate = self
        monitor.pathUpdateHandler = { [weak self] path in
            let conn = NetworkMonitor.classify(path)
            Task { @MainActor in self?.update(conn) }
        }
        monitor.start(queue: queue)
    }

    func onConnectionChange(_ handler: @escaping (Connection) -> Void) {
        onChange.append(handler)
    }

    func onSSIDChange(_ handler: @escaping (String?) -> Void) {
        onSSIDChange.append(handler)
    }

    /// Requests the system permission needed to read the Wi-Fi name, then
    /// returns the current SSID when available.
    func requestCurrentSSIDAccess() async -> String? {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            for _ in 0..<100 where locationManager.authorizationStatus == .notDetermined {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        return await refreshCurrentSSID()
    }

    @discardableResult
    func refreshCurrentSSID() async -> String? {
        guard connection == .wifi else {
            setCurrentSSID(nil)
            return nil
        }
        let ssid = await withCheckedContinuation { continuation in
            NEHotspotNetwork.fetchCurrent { network in
                continuation.resume(returning: network?.ssid)
            }
        }
        setCurrentSSID(ssid?.trimmingCharacters(in: .whitespacesAndNewlines).nonBlank)
        return currentSSID
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        Task { @MainActor [weak self] in await self?.refreshCurrentSSID() }
    }

    private func update(_ conn: Connection) {
        if conn == .wifi {
            Task { await refreshCurrentSSID() }
        } else {
            setCurrentSSID(nil)
        }
        guard conn != connection else { return }
        let previous = connection
        connection = conn
        UserDefaults.standard.set(conn == .cellular, forKey: "networkIsCellular")
        AppLogger.shared.log("Network changed: \(previous.rawValue) > \(conn.rawValue)", category: .networking)
        for handler in onChange { handler(conn) }
    }

    private func setCurrentSSID(_ ssid: String?) {
        guard ssid != currentSSID else { return }
        currentSSID = ssid
        AppLogger.shared.log("Wi-Fi SSID changed: \(ssid ?? "unavailable")", category: .networking)
        for handler in onSSIDChange { handler(ssid) }
    }

    nonisolated private static func classify(_ path: Network.NWPath) -> Connection {
        guard path.status == .satisfied else { return .none }
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.wiredEthernet) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        return .other
    }
}

enum WiFiSSIDPolicy {
    static let allowedSSIDsKey = "allowedWiFiLoginSSIDs"

    static var allowedSSIDs: [String] {
        let values = UserDefaults.standard.stringArray(forKey: allowedSSIDsKey) ?? []
        return Array(Set(values.compactMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).nonBlank
        })).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func add(_ ssid: String) {
        let value = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        var values = Set(allowedSSIDs)
        values.insert(value)
        UserDefaults.standard.set(Array(values).sorted(), forKey: allowedSSIDsKey)
    }

    static func remove(_ ssid: String) {
        UserDefaults.standard.set(allowedSSIDs.filter { $0 != ssid }, forKey: allowedSSIDsKey)
    }

    /// Selects the alternate (normally cellular/public) endpoint whenever the
    /// device is not on one of the user's preferred server Wi-Fi networks.
    /// With no preferred SSIDs configured, this preserves the normal behavior:
    /// main endpoint on Wi-Fi, alternate endpoint on cellular.
    static func shouldUseCellularEndpoint(
        connection: NetworkMonitor.Connection,
        currentSSID: String?
    ) -> Bool {
        shouldUseCellularEndpoint(
            connection: connection,
            currentSSID: currentSSID,
            preferredSSIDs: allowedSSIDs
        )
    }

    static func shouldUseCellularEndpoint(
        connection: NetworkMonitor.Connection,
        currentSSID: String?,
        preferredSSIDs: [String]
    ) -> Bool {
        guard !preferredSSIDs.isEmpty else { return connection == .cellular }
        guard connection == .wifi, let currentSSID else { return true }
        return !preferredSSIDs.contains(currentSSID)
    }
}
