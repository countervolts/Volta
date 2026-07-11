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

    static var supportsAnimatedArtwork: Bool {
        RuntimeCompatibility.supportsAnimatedArtwork
    }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "liveArtwork") as? Bool ?? true
    }

    static var rawAnimatedArtworkEnabled: Bool {
        guard supportsAnimatedArtwork else { return false }
        return UserDefaults.standard.object(forKey: rawAnimatedArtworkKey) as? Bool ?? false
    }

    static var shouldShowAnimatedArtwork: Bool {
        guard supportsAnimatedArtwork else { return false }
        return rawAnimatedArtworkEnabled
            || (isEnabled && (DeveloperExperiments.disableRAMOptimizations || !PerformanceMode.disableLiveArtwork))
    }

    // Keep frames small so memory can go toward frame count instead of resolution.
    static var maxPixelSize: Int {
        guard supportsAnimatedArtwork else { return 0 }
        guard !rawAnimatedArtworkEnabled,
              !DeveloperExperiments.disableRAMOptimizations else { return 0 }
        switch DeviceMemoryTier.current {
        case .gb3OrLess: return 176
        case .gb4: return 224
        case .gb6: return 288
        case .gb8Plus: return 320
        }
    }

    // Keep enough frames for native-rate playback; maxPixelSize keeps the RAM cost in check.
    static var maxFrameCount: Int {
        guard supportsAnimatedArtwork else { return 0 }
        guard !rawAnimatedArtworkEnabled,
              !DeveloperExperiments.disableRAMOptimizations else { return 0 }
        switch DeviceMemoryTier.current {
        case .gb3OrLess: return 180
        case .gb4: return 220
        case .gb6: return 260
        case .gb8Plus: return 300
        }
    }

    // Full-rate display-link wakeups; accumulator keeps loop timing.
    static var lowPowerPlayback: Bool { false }

    // Build early; lock-screen support can appear after song start.
    static var prepareVideoAsset: Bool {
        guard #available(iOS 26.0, *) else { return false }
        if rawAnimatedArtworkEnabled || DeveloperExperiments.disableRAMOptimizations { return true }
        return DeviceMemoryTier.current != .gb3OrLess
    }

    // Album animation is enabled on 6 GB devices, so retain the most recent
    // decoded sequence there too. NSCache's cost limit still evicts large loops.
    static var keepDecodedFramesInRAM: Bool {
        guard supportsAnimatedArtwork else { return false }
        return rawAnimatedArtworkEnabled
            || DeveloperExperiments.disableRAMOptimizations
            || DeviceMemoryTier.current == .gb6
            || DeviceMemoryTier.current == .gb8Plus
    }

    // Album headers decode their own copy; small devices skip them.
    static var animateAlbumHeaders: Bool {
        guard supportsAnimatedArtwork else { return false }
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
