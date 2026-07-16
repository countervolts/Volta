import Foundation
import XCTest
@testable import Volta

final class AudioFormatClassificationTests: XCTestCase {
    func testALACInM4AIsLosslessAndHiRes() throws {
        let song = try decodeSong(
            suffix: "m4a",
            codec: "alac",
            contentType: "audio/mp4",
            bitDepth: 24,
            samplingRate: 96_000
        )

        XCTAssertTrue(song.isLossless)
        XCTAssertTrue(song.isHiResLossless)
    }

    func testAACInM4AIsLossyEvenWithHiResLikeMetadata() throws {
        let song = try decodeSong(
            suffix: "m4a",
            codec: "aac",
            contentType: "audio/mp4",
            bitDepth: 24,
            samplingRate: 96_000
        )

        XCTAssertFalse(song.isLossless)
        XCTAssertFalse(song.isHiResLossless)
    }

    func testALACContentTypeHandlesBackendWithoutCodecField() throws {
        let song = try decodeSong(
            suffix: "m4a",
            contentType: "audio/alac; charset=binary"
        )

        XCTAssertTrue(song.isLossless)
    }

    func testM4AWithPositiveBitDepthHandlesSubsonicWithoutCodecField() throws {
        let song = try decodeSong(
            suffix: "m4a",
            contentType: "audio/mp4",
            bitDepth: 24,
            samplingRate: 96_000
        )

        XCTAssertTrue(song.isLossless)
        XCTAssertTrue(song.isHiResLossless)
    }

    func testGenericM4AWithoutCodecRemainsAmbiguousAndIsNotMarkedLossless() throws {
        let song = try decodeSong(suffix: "m4a", contentType: "audio/mp4")

        XCTAssertFalse(song.isLossless)
    }

    func testExistingUnambiguousLosslessSuffixStillWorks() throws {
        let song = try decodeSong(suffix: "flac")

        XCTAssertTrue(song.isLossless)
    }

    private func decodeSong(
        suffix: String,
        codec: String? = nil,
        contentType: String? = nil,
        bitDepth: Int? = nil,
        samplingRate: Int? = nil
    ) throws -> Song {
        var payload: [String: Any] = [
            "id": "song-1",
            "title": "Track",
            "suffix": suffix
        ]
        payload["codec"] = codec
        payload["contentType"] = contentType
        payload["bitDepth"] = bitDepth
        payload["samplingRate"] = samplingRate
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(Song.self, from: data)
    }
}
