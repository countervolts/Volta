import Foundation
import XCTest
@testable import Volta

final class ExplicitStatusTests: XCTestCase {
    func testOpenSubsonicExplicitStatusIsRecognized() throws {
        let song = try decodeSong(explicitStatus: "explicit")

        XCTAssertTrue(song.isExplicit)
    }

    func testExplicitStatusIsCaseAndWhitespaceInsensitive() throws {
        let song = try decodeSong(explicitStatus: "  ExPliCiT ")

        XCTAssertTrue(song.isExplicit)
    }

    func testNavidromeAndTagValueAliasesAreRecognized() throws {
        XCTAssertTrue(try decodeSong(explicitStatus: "e").isExplicit)
        XCTAssertTrue(try decodeSong(explicitStatus: "1").isExplicit)
        XCTAssertTrue(try decodeSong(explicitStatus: "4").isExplicit)
    }

    func testCleanAndMissingStatusesAreNotExplicit() throws {
        XCTAssertFalse(try decodeSong(explicitStatus: "clean").isExplicit)
        XCTAssertFalse(try decodeSong(explicitStatus: "").isExplicit)
        XCTAssertFalse(try decodeSong(explicitStatus: nil).isExplicit)
    }

    private func decodeSong(explicitStatus: String?) throws -> Song {
        var payload: [String: Any] = [
            "id": "song-1",
            "title": "Track"
        ]
        payload["explicitStatus"] = explicitStatus
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(Song.self, from: data)
    }
}
