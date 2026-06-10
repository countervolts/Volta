import Foundation

// Battery-saver mode. When enabled it *overrides* (never rewrites) user settings
// at their read points. Each override is individually toggleable so the user
// chooses what Performance Mode does. Reads are cheap and pulled live from
// UserDefaults so a change applies on the next track / artwork / request.
enum PerformanceMode {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "performanceModeEnabled") }

    // an override is active only when the master switch is on AND its own toggle is on
    private static func flag(_ key: String, default def: Bool) -> Bool {
        guard isEnabled else { return false }
        return UserDefaults.standard.object(forKey: key) as? Bool ?? def
    }

    // default-on overrides (the obvious battery wins)
    static var halfFrameRate: Bool           { flag("pmHalfFrameRate", default: true) }
    static var reduceImageQuality: Bool      { flag("pmReduceImageQuality", default: true) }
    static var disableLiveArtwork: Bool      { flag("pmDisableLiveArtwork", default: true) }
    static var disableDynamicBackground: Bool { flag("pmDisableDynamicBackground", default: true) }
    static var reduceAnimations: Bool        { flag("pmReduceAnimations", default: true) }
    static var disablePrefetch: Bool         { flag("pmDisablePrefetch", default: true) }

    // default-off overrides (more intrusive — opt in)
    static var simpleTransitions: Bool       { flag("pmSimpleTransitions", default: false) }
    static var lowerStreamQuality: Bool      { flag("pmLowerStreamQuality", default: false) }
    static var bypassAudioEffects: Bool      { flag("pmBypassAudioEffects", default: false) }

    // capped stream bitrate when lowerStreamQuality is on (0 = no cap)
    static var streamBitrateCap: Int { lowerStreamQuality ? 192 : 0 }
}
