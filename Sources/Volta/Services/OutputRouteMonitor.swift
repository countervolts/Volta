import Foundation
import AVFoundation
import CoreMotion
import Combine

// Active output-route label and glyph for the player.
@MainActor
final class OutputRouteMonitor: ObservableObject {
    static let shared = OutputRouteMonitor()

    @Published private(set) var iconName = "airplayaudio"
    @Published private(set) var routeName = "Output"
    @Published private(set) var isExternal = false

    private init() {
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
            return
        }
        routeName = port.portName
        switch port.portType {
        case .builtInSpeaker, .builtInReceiver:
            iconName = "airplayaudio"; isExternal = false
        case .headphones:
            // wired headphones / EarPods
            iconName = "headphones"; isExternal = true
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
            iconName = Self.bluetoothIcon(for: port.portName); isExternal = true
        case .airPlay:
            iconName = "airplayaudio"; isExternal = true
        case .carAudio:
            iconName = "car.fill"; isExternal = true
        case .usbAudio:
            iconName = Self.wiredIcon(for: port.portName); isExternal = true
        case .HDMI, .lineOut, .displayPort:
            iconName = "hifispeaker.fill"; isExternal = true
        default:
            iconName = "airplayaudio"; isExternal = true
        }
    }

    // Best-effort specific glyph from advertised route name.
    private static func bluetoothIcon(for name: String) -> String {
        let n = name.lowercased()
        // AirPods family (read the exact model from the advertised name)
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpod") { return "airpods" }
        // Beats family all use the Beats headphones glyph.
        if n.contains("beats") || n.contains("powerbeats") { return "beats.headphones" }
        // Apple speakers
        if n.contains("homepod") { return "homepod.fill" }
        // Non-Apple speakers / soundbars
        if n.contains("speaker") || n.contains("soundbar") || n.contains("boom")
            || n.contains("sonos") || n.contains("jbl") || n.contains("echo") {
            return "hifispeaker.fill"
        }
        // Motion sensor can reveal renamed AirPods/Beats.
        if appleEarbudsConnected { return "airpods" }
        return "headphones"
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
