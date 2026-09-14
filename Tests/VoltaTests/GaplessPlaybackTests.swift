import XCTest

@testable import Volta

final class GaplessPlaybackTests: XCTestCase {
    func testMissingModeUsesDefaultNativeHandoff() {
        XCTAssertEqual(GaplessPlaybackMode.resolved(storedValue: nil), .default)
        XCTAssertFalse(GaplessPlaybackMode.default.usesStandbyPlayer)
    }

    func testModesSelectDifferentHandoffStrategies() {
        XCTAssertFalse(GaplessPlaybackMode.default.usesStandbyPlayer)
        XCTAssertTrue(GaplessPlaybackMode.isEnabled(storedValue: nil))
        XCTAssertTrue(GaplessPlaybackMode.isEnabled(storedValue: "weak"))
        XCTAssertFalse(GaplessPlaybackMode.isEnabled(storedValue: "off"))

        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "gaplessPlayback")
        defaults.set("on", forKey: "gaplessPlayback")
        XCTAssertTrue(GaplessPlaybackMode.experimental.usesStandbyPlayer)
        if let previous {
            defaults.set(previous, forKey: "gaplessPlayback")
        } else {
            defaults.removeObject(forKey: "gaplessPlayback")
        }
    }

    func testUnknownModeFallsBackToDefault() {
        XCTAssertEqual(GaplessPlaybackMode.resolved(storedValue: "unsupported"), .default)
    }
}
