import UIKit
import QuartzCore

// Caps the cadence of the app's CADisplayLink-driven work (scroll/drag throttling
// etc.) to half the display's native refresh when Performance Mode's Half Frame
// Rate override is on. iOS doesn't let an app force the whole compositor down, so
// this governs the surfaces the app actually drives.
@MainActor
enum FrameRateGovernor {
    static var isHalfRate: Bool { PerformanceMode.halfFrameRate }

    static var nativeMaxFPS: Float {
        let fps = Float(UIScreen.main.maximumFramesPerSecond)
        return fps > 0 ? fps : 60
    }

    // half the native refresh (60>30, 120>60) when capped, else native
    static var maxFPS: Float {
        isHalfRate ? max(15, nativeMaxFPS / 2) : nativeMaxFPS
    }

    static var range: CAFrameRateRange {
        let cap = maxFPS
        let minimum = isHalfRate ? max(1, cap / 2) : cap
        return CAFrameRateRange(minimum: minimum, maximum: cap, preferred: cap)
    }

    // minimum redraw interval for TimelineView(.animation); nil = uncapped
    static var minimumInterval: Double? {
        isHalfRate ? Double(1.0 / maxFPS) : nil
    }

    static func apply(to link: CADisplayLink) {
        link.preferredFrameRateRange = range
    }
}
