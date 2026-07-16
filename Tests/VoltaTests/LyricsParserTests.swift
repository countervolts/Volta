import Foundation
import XCTest
@testable import Volta

final class LyricsParserTests: XCTestCase {
    func testLineTimedTTMLWithNestedOffsetsFramesTicksAndBreak() throws {
        let ttml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tt xmlns="http://www.w3.org/ns/ttml"
            xmlns:ttp="http://www.w3.org/ns/ttml#parameter"
            ttp:frameRate="30" ttp:subFrameRate="2" ttp:tickRate="10">
          <body begin="1s">
            <div begin="2s">
              <p begin="500ms">First &amp; line</p>
              <p begin="00:00:04:15.1"><span>Second</span><br/>part</p>
            </div>
            <div><p begin="45t">Tick line</p></div>
          </body>
        </tt>
        """

        let parsed = try XCTUnwrap(LyricsParser.parse(text: ttml, formatHint: "ttml"))
        XCTAssertEqual(parsed.raw.format, .ttml)
        XCTAssertEqual(parsed.lines.map(\.text), ["First & line", "Second\npart", "Tick line"])
        for (actual, expected) in zip(parsed.lines.map(\.time), [3.5, 4.517, 5.5]) {
            XCTAssertEqual(actual, expected, accuracy: 0.001)
        }
    }

    func testWordTimedSpansCollapseToOneLineAndProvideFallbackStart() throws {
        let ttml = """
        <tt xmlns="http://www.w3.org/ns/ttml">
          <body><div><p>
            <span begin="1.000">He</span><span begin="1.400">llo</span>
            <span begin="2.000">world</span>
          </p></div></body>
        </tt>
        """

        let parsed = try XCTUnwrap(LyricsParser.parse(text: ttml))
        XCTAssertEqual(parsed.lines.count, 1)
        XCTAssertEqual(parsed.lines[0].time, 1, accuracy: 0.001)
        XCTAssertEqual(parsed.lines[0].text, "Hello world")
    }

    func testUntimedAndMixedTTMLRemainPlain() throws {
        let ttml = """
        <tt xmlns="http://www.w3.org/ns/ttml"><body><div>
          <p begin="1s">Timed</p><p>Untimed</p>
        </div></body></tt>
        """

        let parsed = try XCTUnwrap(LyricsParser.parse(text: ttml))
        XCTAssertEqual(parsed.lines.map(\.text), ["Timed", "Untimed"])
        XCTAssertTrue(parsed.lines.allSatisfy { $0.time == -1 })
    }

    func testUTF16TTML() throws {
        let ttml = """
        <?xml version="1.0" encoding="UTF-16"?>
        <tt xmlns="http://www.w3.org/ns/ttml"><body><p begin="2s">UTF-16 ✓</p></body></tt>
        """
        let data = try XCTUnwrap(ttml.data(using: .utf16))
        let parsed = try XCTUnwrap(LyricsParser.parse(data: data))
        XCTAssertEqual(parsed.lines.first?.text, "UTF-16 ✓")
        XCTAssertEqual(parsed.lines.first?.time ?? -1, 2, accuracy: 0.001)
    }

    func testLRCFractionsMetadataOffsetSortingAndCanonicalOutput() throws {
        let lrc = """
        [ar:Artist]
        [00:02.5]Third
        [00:01.50]Second
        [00:00.500]First
        [offset:100]
        """
        let parsed = try XCTUnwrap(LyricsParser.parse(text: lrc, formatHint: "lrc"))
        XCTAssertEqual(parsed.lines.map(\.text), ["First", "Second", "Third"])
        XCTAssertEqual(parsed.lines.map(\.time), [0.6, 1.6, 2.6])
        XCTAssertEqual(parsed.lines.map(\.id), [0, 1, 2])

        let canonical = try XCTUnwrap(LyricsParser.canonicalPayload(for: parsed.lines))
        XCTAssertEqual(canonical.format, .lrc)
        let text = try XCTUnwrap(String(data: canonical.data, encoding: .utf8))
        XCTAssertTrue(text.contains("[00:00.600]First"))
    }

    func testMalformedTTMLDoesNotBecomePlainXMLLyrics() {
        let malformed = "<tt><body><p begin=\"1s\">Broken</body></tt>"
        XCTAssertNil(LyricsParser.parse(text: malformed, formatHint: "ttml"))
    }
}
