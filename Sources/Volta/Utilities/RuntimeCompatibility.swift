import Foundation
import UIKit

enum RuntimeCompatibility {
    static var isIOS16: Bool {
        if #available(iOS 17.0, *) { return false }
        return true
    }

    static var supportsAnimatedArtwork: Bool {
        !isIOS16
    }

    static var usesPassiveVisualizer: Bool {
        isIOS16
    }

    static var allowsArtworkShimmer: Bool {
        !isIOS16
    }

    static var prefersSolidGlassFallback: Bool {
        isIOS16
    }

    static func cappedArtworkSize(_ requested: Int?) -> Int? {
        guard isIOS16, let requested else {
            return requested ?? (isIOS16 ? 640 : nil)
        }
        if requested <= 220 { return requested }
        if requested <= 400 { return min(requested, 320) }
        if requested <= 600 { return min(requested, 480) }
        return min(requested, 640)
    }

    static func artworkCacheMegabytes(for tier: DeviceMemoryTier, cacheMode: String) -> Int {
        guard isIOS16 else {
            let base: Int
            switch tier {
            case .gb3OrLess: base = 48
            case .gb4: base = 64
            case .gb6: base = 96
            case .gb8Plus: base = 128
            }
            return cacheMode == "aggressive" ? base * 2 : (cacheMode == "light" ? min(base, 32) : base)
        }

        let base: Int
        switch tier {
        case .gb3OrLess: base = 24
        case .gb4: base = 28
        case .gb6: base = 36
        case .gb8Plus: base = 48
        }
        return cacheMode == "aggressive" ? min(base * 2, 64) : (cacheMode == "light" ? min(base, 24) : base)
    }

    static func artworkCacheCountLimit(cacheMode: String) -> Int {
        guard isIOS16 else {
            return cacheMode == "aggressive" ? 600 : (cacheMode == "light" ? 150 : 300)
        }
        return cacheMode == "aggressive" ? 160 : (cacheMode == "light" ? 64 : 96)
    }

    static func artworkConnectionLimit(imageMode: String) -> Int {
        guard isIOS16 else {
            return imageMode == "fast" ? 8 : (imageMode == "conservative" ? 2 : 6)
        }
        return imageMode == "fast" ? 4 : (imageMode == "conservative" ? 2 : 3)
    }
}
