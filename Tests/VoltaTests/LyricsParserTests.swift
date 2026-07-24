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
            <span begin="1.000s" dur="0.300s">He</span><span begin="1.400s" dur="0.300s">llo</span>
            <span begin="2.000s" dur="0.500s">world</span>
          </p></div></body>
        </tt>
        """

        let parsed = try XCTUnwrap(LyricsParser.parse(text: ttml))
        XCTAssertEqual(parsed.lines.count, 1)
        XCTAssertEqual(parsed.lines[0].time, 1, accuracy: 0.001)
        XCTAssertEqual(parsed.lines[0].text, "Hello world")
        let cues = try XCTUnwrap(parsed.lines[0].cues)
        XCTAssertEqual(cues.map(\.text), ["He", "llo", "world"])
        XCTAssertEqual(cues.map(\.byteStart), [0, 2, 6])
        XCTAssertEqual(cues.map(\.byteEnd), [1, 4, 10])
        for (actual, expected) in zip(cues.map(\.start), [1.0, 1.4, 2.0]) {
            XCTAssertEqual(actual, expected, accuracy: 0.001)
        }
        for (actual, expected) in zip(cues.compactMap(\.end), [1.3, 1.7, 2.5]) {
            XCTAssertEqual(actual, expected, accuracy: 0.001)
        }
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

    func testOpenSubsonicEnhancedLyricsV2DecodesCueLinesAndAgents() throws {
        let json = """
        {
          "subsonic-response": {
            "status": "ok",
            "lyricsList": {
              "structuredLyrics": [
                {
                  "kind": "main",
                  "lang": "en",
                  "offset": 100,
                  "synced": true,
                  "line": [
                    { "start": 1000, "value": "Hello echo" }
                  ],
                  "agents": [
                    { "id": "lead", "role": "main", "name": "Lead Vocal" },
                    { "id": "bg", "role": "background", "name": "Backing Vocal" }
                  ],
                  "cueLine": [
                    {
                      "index": 0,
                      "agentId": "lead",
                      "start": 1000,
                      "end": 3000,
                      "value": "Hello echo",
                      "cue": [
                        { "start": 1000, "end": 1400, "value": "Hello", "byteStart": 0, "byteEnd": 4 },
                        { "start": 2000, "end": 2500, "value": "echo", "byteStart": 6, "byteEnd": 9 }
                      ]
                    },
                    {
                      "index": 0,
                      "agentId": "bg",
                      "start": 1200,
                      "end": 1800,
                      "value": "(echo)",
                      "cue": [
                        { "start": 1200, "end": 1800, "value": "(echo)", "byteStart": 0, "byteEnd": 5 }
                      ]
                    }
                  ]
                }
              ]
            }
          }
        }
        """

        let envelope = try JSONDecoder().decode(SubsonicEnvelope.self, from: Data(json.utf8))
        let document = try XCTUnwrap(envelope.response.lyricsList?.structuredLyrics?.first)
        XCTAssertEqual(document.kind, "main")
        XCTAssertEqual(document.agents?.first?.name, "Lead Vocal")
        XCTAssertEqual(document.cueLine?.first?.agentId, "lead")
        XCTAssertEqual(document.cueLine?.first?.cue?.last?.byteStart, 6)
        XCTAssertEqual(document.cueLine?.first?.cue?.last?.byteEnd, 9)

        let displayLines = try XCTUnwrap(LyricsService.displayLines(from: envelope.response.lyricsList ?? LyricsList(structuredLyrics: nil)))
        XCTAssertEqual(displayLines.map(\.text), ["Hello echo", "(echo)"])
        XCTAssertEqual(displayLines.map(\.vocalLane), [.main, .other])
        for (actual, expected) in zip(displayLines.map(\.time), [1.1, 1.3]) {
            XCTAssertEqual(actual, expected, accuracy: 0.001)
        }
        XCTAssertEqual(displayLines.last?.cues?.first?.text, "(echo)")
    }

    func testOpenSubsonicVXAgentIDsSplitToOtherVocalLaneWithoutRoles() throws {
        let json = """
        {
          "subsonic-response": {
            "status": "ok",
            "lyricsList": {
              "structuredLyrics": [
                {
                  "kind": "main",
                  "synced": true,
                  "line": [
                    { "start": 1000, "value": "Lead line" }
                  ],
                  "agents": [
                    { "id": "v1", "name": "Lead Vocal" },
                    { "id": "v2", "name": "Second Vocal" }
                  ],
                  "cueLine": [
                    {
                      "index": 0,
                      "agentId": "v1",
                      "start": 1000,
                      "value": "Lead line",
                      "cue": [
                        { "start": 1000, "end": 1300, "value": "Lead", "byteStart": 0, "byteEnd": 3 },
                        { "start": 1300, "end": 1600, "value": "line", "byteStart": 5, "byteEnd": 8 }
                      ]
                    },
                    {
                      "index": 0,
                      "agentId": "v2",
                      "start": 1000,
                      "value": "Harmony",
                      "cue": [
                        { "start": 1000, "end": 1600, "value": "Harmony", "byteStart": 0, "byteEnd": 6 }
                      ]
                    }
                  ]
                }
              ]
            }
          }
        }
        """

        let envelope = try JSONDecoder().decode(SubsonicEnvelope.self, from: Data(json.utf8))
        let displayLines = try XCTUnwrap(LyricsService.displayLines(from: envelope.response.lyricsList ?? LyricsList(structuredLyrics: nil)))
        XCTAssertEqual(displayLines.map(\.text), ["Lead line", "Harmony"])
        XCTAssertEqual(displayLines.map(\.vocalLane), [.main, .other])
    }

    func testTTMLVXAgentsSplitToOtherVocalLane() throws {
        let ttml = """
        <tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata">
          <body><div>
            <p begin="1s" ttm:agent="v1">Lead</p>
            <p begin="1s" ttm:agent="v2">Harmony</p>
            <p begin="2s" ttm:agent="vX">Ad lib</p>
          </div></body>
        </tt>
        """

        let parsed = try XCTUnwrap(LyricsParser.parse(text: ttml, formatHint: "ttml"))
        XCTAssertEqual(parsed.lines.map(\.text), ["Lead", "Harmony", "Ad lib"])
        XCTAssertEqual(parsed.lines.map(\.vocalLane), [.main, .other, .other])
    }

    func testCueLinesRoundTripThroughCanonicalTTML() throws {
        let lines = [
            LyricLine(
                id: 0,
                time: 10,
                text: "Hello echo",
                cues: [
                    LyricCue(id: 0, start: 10, end: 10.4, byteStart: 0, byteEnd: 4, text: "Hello"),
                    LyricCue(id: 1, start: 10.8, end: 11.2, byteStart: 6, byteEnd: 9, text: "echo"),
                ],
                vocalLane: .other
            )
        ]

        let payload = try XCTUnwrap(LyricsParser.canonicalPayload(for: lines))
        XCTAssertEqual(payload.format, .ttml)
        let payloadText = try XCTUnwrap(String(data: payload.data, encoding: .utf8))
        XCTAssertTrue(payloadText.contains("ttm:agent=\"other\""))
        let reparsed = try XCTUnwrap(LyricsParser.parse(data: payload.data, formatHint: payload.format.rawValue))
        XCTAssertEqual(reparsed.lines.first?.text, "Hello echo")
        XCTAssertEqual(reparsed.lines.first?.vocalLane, .other)
        let cues = try XCTUnwrap(reparsed.lines.first?.cues)
        XCTAssertEqual(cues.map(\.text), ["Hello", "echo"])
        for (actual, expected) in zip(cues.map(\.start), [10.0, 10.8]) {
            XCTAssertEqual(actual, expected, accuracy: 0.001)
        }
        for (actual, expected) in zip(cues.compactMap(\.end), [10.4, 11.2]) {
            XCTAssertEqual(actual, expected, accuracy: 0.001)
        }
    }
}
