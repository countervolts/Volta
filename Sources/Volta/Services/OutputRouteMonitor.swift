import Foundation
import AVFoundation
import CoreMotion
import Combine

// Watches the active audio output route and exposes an SF Symbol + label so the
// player's route button can show AirPods / headphones / car / speaker instead of
// the generic AirPlay glyph. Built-in speaker keeps the default AirPlay icon.
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

    // best-effort device-specific glyph from the route's advertised name. Falls
    // back to a headphone-motion probe so renamed AirPods/Beats (whose Bluetooth
    // name no longer contains "AirPods") still show an AirPods glyph instead of
    // the generic wired-headphones one.
    private static func bluetoothIcon(for name: String) -> String {
        let n = name.lowercased()
        // AirPods family (read the exact model from the advertised name)
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpod") { return "airpods" }
        // Beats family — all map to the Beats headphones glyph
        if n.contains("beats") || n.contains("powerbeats") { return "beats.headphones" }
        // Apple speakers
        if n.contains("homepod") { return "homepod.fill" }
        // Non-Apple speakers / soundbars
        if n.contains("speaker") || n.contains("soundbar") || n.contains("boom")
            || n.contains("sonos") || n.contains("jbl") || n.contains("echo") {
            return "hifispeaker.fill"
        }
        // Unknown Bluetooth name: if motion-capable Apple earbuds are connected,
        // the headphone motion sensor reports available even after a rename —
        // use that to still show an AirPods glyph rather than wired headphones.
        if appleEarbudsConnected { return "airpods" }
        return "headphones"
    }

    // wired USB-C / Lightning route: distinguish headphone-style outputs from
    // speakers/interfaces by name so EarPods don't show a speaker glyph.
    private static func wiredIcon(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("headphone") || n.contains("earpods") || n.contains("earphone")
            || n.contains("buds") || n.contains("airpod") {
            return "headphones"
        }
        return "hifispeaker.fill"
    }

    // CMHeadphoneMotionManager reports motion availability only while AirPods
    // (Pro / 3 / 4 / Max) or motion-capable Beats are the connected headphones.
    // Reading availability needs no authorization and shows no prompt.
    private static let headphoneMotion = CMHeadphoneMotionManager()
    private static var appleEarbudsConnected: Bool {
        headphoneMotion.isDeviceMotionAvailable
    }
}
