import Foundation
import MediaPlayer

// Live artwork performance profile. Limits come from RAM tier and apply live.

enum DeviceMemoryTier: Equatable {
    case gb3OrLess, gb4, gb6, gb8Plus

    static let current: DeviceMemoryTier = {
        let gb = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        // physicalMemory under-reports nominal RAM.
        if gb < 3.5 { return .gb3OrLess }
        if gb < 5.0 { return .gb4 }
        if gb < 7.0 { return .gb6 }
        return .gb8Plus
    }()
}

enum LiveArtworkSettings {
    static let rawAnimatedArtworkKey = "rawAnimatedArtwork"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "liveArtwork") as? Bool ?? true
    }

    static var rawAnimatedArtworkEnabled: Bool {
        UserDefaults.standard.object(forKey: rawAnimatedArtworkKey) as? Bool ?? false
    }

    static var shouldShowAnimatedArtwork: Bool {
        rawAnimatedArtworkEnabled
            || (isEnabled && (DeveloperExperiments.disableRAMOptimizations || !PerformanceMode.disableLiveArtwork))
    }

    // longest decoded side of one animation frame, in pixels
    static var maxPixelSize: Int {
        guard !rawAnimatedArtworkEnabled,
              !DeveloperExperiments.disableRAMOptimizations else { return 0 }
        switch DeviceMemoryTier.current {
        case .gb3OrLess: return 192
        case .gb4: return 288
        case .gb6: return 448
        case .gb8Plus: return 768
        }
    }

    // Keep native frame cadence; maxPixelSize handles RAM.
    static var maxFrameCount: Int { 0 }

    // Full-rate display-link wakeups; accumulator keeps loop timing.
    static var lowPowerPlayback: Bool { false }

    // Build early; lock-screen support can appear after song start.
    static var prepareVideoAsset: Bool {
        guard #available(iOS 26.0, *) else { return false }
        if rawAnimatedArtworkEnabled || DeveloperExperiments.disableRAMOptimizations { return true }
        return DeviceMemoryTier.current != .gb3OrLess
    }

    // Decoded animations are large; keep them in RAM only on the top tier.
    static var keepDecodedFramesInRAM: Bool {
        rawAnimatedArtworkEnabled
            || DeveloperExperiments.disableRAMOptimizations
            || DeviceMemoryTier.current == .gb8Plus
    }

    // Album headers decode their own copy; small devices skip them.
    static var animateAlbumHeaders: Bool {
        if rawAnimatedArtworkEnabled || DeveloperExperiments.disableRAMOptimizations { return true }
        switch DeviceMemoryTier.current {
        case .gb3OrLess, .gb4: return false
        case .gb6, .gb8Plus: return true
        }
    }

    // Evaluated live (not a one-time static let): on iOS 26/27 the supported-keys
    // set can read empty very early in cold launch, and caching that once would
    // disable lock-screen animated artwork for the whole session.
    static var lockScreenVideoSupported: Bool {
        if #available(iOS 26.0, *) {
            if rawAnimatedArtworkEnabled { return true }
            let keys = MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys
            return keys.contains(MPNowPlayingInfoProperty3x4AnimatedArtwork)
                || keys.contains(MPNowPlayingInfoProperty1x1AnimatedArtwork)
        }
        return false
    }
}
