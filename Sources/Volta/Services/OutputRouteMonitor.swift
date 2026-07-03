import Foundation
import AVFoundation
import CoreMotion
import Combine
import CoreBluetooth

// Active output-route label and glyph for the player.
@MainActor
final class OutputRouteMonitor: NSObject, ObservableObject {
    static let shared = OutputRouteMonitor()

    @Published private(set) var iconName = "airplayaudio"
    @Published private(set) var routeName = "Output"
    @Published private(set) var isExternal = false

    private let bluetoothModelDetector = AirPodsBLEModelDetector()
    private var lastRouteIdentity: String?

    private override init() {
        super.init()
        bluetoothModelDetector.onModelChange = { [weak self] in
            Task { @MainActor in
                self?.update()
            }
        }
        update()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(routeChanged),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func routeChanged() {
        Task { @MainActor in self.update() }
    }

    func update() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        guard let port = outputs.first else {
            iconName = "airplayaudio"; routeName = "Output"; isExternal = false
            lastRouteIdentity = nil
            bluetoothModelDetector.stopScanning(reset: true)
            return
        }

        let routeIdentity = "\(port.portType.rawValue)|\(port.uid)|\(port.portName)"
        if routeIdentity != lastRouteIdentity {
            bluetoothModelDetector.stopScanning(reset: true)
            lastRouteIdentity = routeIdentity
        }

        routeName = port.portName
        switch port.portType {
        case .builtInSpeaker, .builtInReceiver:
            iconName = "airplayaudio"; isExternal = false
            bluetoothModelDetector.stopScanning(reset: true)
        case .headphones:
            // wired headphones / EarPods
            iconName = "headphones"; isExternal = true
            bluetoothModelDetector.stopScanning(reset: true)
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
            let motionDetectedAppleEarbuds = Self.appleEarbudsConnected
            let recentModel = bluetoothModelDetector.recentModel
            iconName = Self.bluetoothIcon(
                for: port.portName,
                detectedModel: recentModel,
                appleEarbudsConnected: motionDetectedAppleEarbuds
            )
            isExternal = true
            if recentModel == nil, Self.shouldProbeBluetoothModel(
                for: port.portName,
                appleEarbudsConnected: motionDetectedAppleEarbuds
            ) {
                bluetoothModelDetector.scan()
            }
        case .airPlay:
            iconName = "airplayaudio"; isExternal = true
            bluetoothModelDetector.stopScanning(reset: true)
        case .carAudio:
            iconName = "car.fill"; isExternal = true
            bluetoothModelDetector.stopScanning(reset: true)
        case .usbAudio:
            iconName = Self.wiredIcon(for: port.portName); isExternal = true
            bluetoothModelDetector.stopScanning(reset: true)
        case .HDMI, .lineOut, .displayPort:
            iconName = "hifispeaker.fill"; isExternal = true
            bluetoothModelDetector.stopScanning(reset: true)
        default:
            iconName = "airplayaudio"; isExternal = true
            bluetoothModelDetector.stopScanning(reset: true)
        }
    }

    // Use the route name first, then BLE for renamed Apple earbuds.
    private static func bluetoothIcon(
        for name: String,
        detectedModel: AppleAudioRouteModel?,
        appleEarbudsConnected: Bool
    ) -> String {
        let n = name.lowercased()
        // AirPods family (read the exact model from the advertised name)
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpod"), let detectedModel { return detectedModel.iconName }
        if n.contains("airpod") { return "airpods" }
        // Beats family all use the Beats headphones glyph.
        if n.contains("beats") || n.contains("powerbeats") { return "beats.headphones" }
        // Apple speakers
        if n.contains("homepod") { return "homepod.fill" }
        // Non-Apple speakers / soundbars
        if Self.isSpeakerLikeBluetoothName(n) {
            return "hifispeaker.fill"
        }
        // Motion tells us these are Apple earbuds; BLE narrows down the model.
        if appleEarbudsConnected { return detectedModel?.iconName ?? "airpods" }
        if let detectedModel { return detectedModel.iconName }
        return "headphones"
    }

    private static func shouldProbeBluetoothModel(for name: String, appleEarbudsConnected: Bool) -> Bool {
        let n = name.lowercased()
        if n.contains("airpods max") || n.contains("airpods pro") { return false }
        if n.contains("beats") || n.contains("powerbeats") || n.contains("homepod")
            || Self.isSpeakerLikeBluetoothName(n) {
            return false
        }
        return n.contains("airpod") || appleEarbudsConnected || !n.isEmpty
    }

    private static func isSpeakerLikeBluetoothName(_ n: String) -> Bool {
        n.contains("speaker") || n.contains("soundbar") || n.contains("boom")
            || n.contains("sonos") || n.contains("jbl") || n.contains("echo")
    }

    // USB-C/Lightning: distinguish headphones from speakers/interfaces by name.
    private static func wiredIcon(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("headphone") || n.contains("earpods") || n.contains("earphone")
            || n.contains("buds") || n.contains("airpod") {
            return "headphones"
        }
        return "hifispeaker.fill"
    }

    // Motion availability needs no authorization and shows no prompt.
    private static let headphoneMotion = CMHeadphoneMotionManager()
    private static var appleEarbudsConnected: Bool {
        headphoneMotion.isDeviceMotionAvailable
    }
}

private enum AppleAudioRouteModel: Equatable {
    case airPods
    case airPodsPro
    case airPodsMax
    case beats

    var iconName: String {
        switch self {
        case .airPods: return "airpods"
        case .airPodsPro: return "airpodspro"
        case .airPodsMax: return "airpodsmax"
        case .beats: return "beats.headphones"
        }
    }

    static func fromBluetoothModelCode(_ code: UInt16) -> AppleAudioRouteModel? {
        Self.model(forBluetoothProductID: code) ?? Self.model(forBluetoothProductID: code.byteSwapped)
    }

    private static func model(forBluetoothProductID code: UInt16) -> AppleAudioRouteModel? {
        switch code {
        case 0x0220, 0x0F20, 0x1320, 0x1920, 0x1B20:
            return .airPods
        case 0x0E20, 0x1420, 0x2420, 0x2720:
            return .airPodsPro
        case 0x0A20, 0x1F20, 0x2D20:
            return .airPodsMax
        case 0x0320, 0x0520, 0x0620, 0x0B20, 0x0C20, 0x0D20,
             0x1020, 0x1120, 0x1220, 0x1620, 0x1720, 0x1D20,
             0x2520, 0x2620:
            return .beats
        default:
            return nil
        }
    }
}

private final class AirPodsBLEModelDetector: NSObject, CBCentralManagerDelegate {
    var onModelChange: (() -> Void)?

    private struct Candidate {
        let model: AppleAudioRouteModel
        let rssi: Int
        let seenAt: Date
    }

    private let candidateTTL: TimeInterval = 90
    private let scanDuration: TimeInterval = 6
    private let minimumRSSI = -75
    private var candidate: Candidate?
    private var central: CBCentralManager?
    private var shouldScanWhenPoweredOn = false
    private var isScanning = false
    private var stopWorkItem: DispatchWorkItem?

    var recentModel: AppleAudioRouteModel? {
        guard let candidate, Date().timeIntervalSince(candidate.seenAt) <= candidateTTL else {
            return nil
        }
        return candidate.model
    }

    func scan() {
        guard CBCentralManager.authorization != .denied,
              CBCentralManager.authorization != .restricted else {
            return
        }

        guard let central else {
            shouldScanWhenPoweredOn = true
            self.central = CBCentralManager(
                delegate: self,
                queue: .main,
                options: [CBCentralManagerOptionShowPowerAlertKey: false]
            )
            return
        }

        guard central.state == .poweredOn else {
            shouldScanWhenPoweredOn = true
            return
        }

        startScanning()
    }

    func stopScanning(reset: Bool = false) {
        shouldScanWhenPoweredOn = false
        isScanning = false
        central?.stopScan()
        stopWorkItem?.cancel()
        stopWorkItem = nil
        if reset {
            candidate = nil
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn, shouldScanWhenPoweredOn else { return }
        startScanning()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let rssi = RSSI.intValue
        guard rssi >= minimumRSSI,
              let model = Self.model(from: advertisementData) else {
            return
        }

        if let current = candidate,
           Date().timeIntervalSince(current.seenAt) <= candidateTTL,
           current.rssi > rssi {
            return
        }

        if candidate?.model != model {
            candidate = Candidate(model: model, rssi: rssi, seenAt: Date())
            onModelChange?()
        } else {
            candidate = Candidate(model: model, rssi: rssi, seenAt: Date())
        }
    }

    private func startScanning() {
        guard !isScanning else { return }
        shouldScanWhenPoweredOn = false
        isScanning = true
        central?.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )

        stopWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.stopScanning()
        }
        stopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + scanDuration, execute: workItem)
    }

    private static func model(from advertisementData: [String: Any]) -> AppleAudioRouteModel? {
        guard let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else {
            return nil
        }
        return model(fromManufacturerData: [UInt8](data))
    }

    private static func model(fromManufacturerData bytes: [UInt8]) -> AppleAudioRouteModel? {
        guard bytes.count >= 5 else { return nil }

        if let model = model(fromContinuityPayload: bytes) {
            return model
        }

        if bytes.count >= 7,
           (bytes[0] == 0x4C && bytes[1] == 0x00) || (bytes[0] == 0x00 && bytes[1] == 0x4C) {
            return model(fromContinuityPayload: Array(bytes.dropFirst(2)))
        }

        return nil
    }

    private static func model(fromContinuityPayload bytes: [UInt8]) -> AppleAudioRouteModel? {
        var offset = 0
        while offset + 1 < bytes.count {
            let type = bytes[offset]
            let length = Int(bytes[offset + 1])
            let start = offset + 2
            let end = start + length
            guard length > 0, end <= bytes.count else { return nil }

            if type == 0x07, length >= 3, bytes[start] == 0x01 {
                let code = UInt16(bytes[start + 1]) << 8 | UInt16(bytes[start + 2])
                if let model = AppleAudioRouteModel.fromBluetoothModelCode(code) {
                    return model
                }
            }

            offset = end
        }

        return nil
    }
}
