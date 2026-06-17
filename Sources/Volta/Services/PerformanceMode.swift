import Foundation

// Battery-saver overrides. User settings are left alone.
enum PerformanceMode {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "performanceModeEnabled") }

    // Master switch plus per-feature switch.
    private static func flag(_ key: String, default def: Bool) -> Bool {
        guard isEnabled else { return false }
        return UserDefaults.standard.object(forKey: key) as? Bool ?? def
    }

    // Default-on battery wins.
    static var halfFrameRate: Bool           { flag("pmHalfFrameRate", default: true) }
    static var reduceImageQuality: Bool {
        DeveloperExperiments.disableRAMOptimizations ? false : flag("pmReduceImageQuality", default: true)
    }
    static var disableLiveArtwork: Bool      { flag("pmDisableLiveArtwork", default: true) }
    static var disableDynamicBackground: Bool { flag("pmDisableDynamicBackground", default: true) }
    static var reduceAnimations: Bool        { flag("pmReduceAnimations", default: true) }
    static var disablePrefetch: Bool         { flag("pmDisablePrefetch", default: true) }

    // Intrusive overrides default off.
    static var simpleTransitions: Bool       { flag("pmSimpleTransitions", default: false) }
    static var lowerStreamQuality: Bool      { flag("pmLowerStreamQuality", default: false) }
    static var bypassAudioEffects: Bool      { flag("pmBypassAudioEffects", default: false) }

    // capped stream bitrate when lowerStreamQuality is on (0 = no cap)
    static var streamBitrateCap: Int { lowerStreamQuality ? 192 : 0 }
}
