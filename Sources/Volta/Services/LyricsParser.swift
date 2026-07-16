import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

enum LyricsFileFormat: String, Codable, Sendable, CaseIterable {
    case lrc
    case ttml
    case plain

    var pathExtension: String {
        switch self {
        case .lrc: return "lrc"
        case .ttml: return "ttml"
        case .plain: return "txt"
        }
    }

    static func from(hint: String?) -> LyricsFileFormat? {
        guard let hint = hint?.lowercased() else { return nil }
        if hint.contains("ttml") || hint.contains("dfxp") { return .ttml }
        if hint.contains("lrc") { return .lrc }
        if hint.contains("plain") || hint.contains("text") || hint == "txt" { return .plain }
        return nil
    }
}

struct RawLyricsPayload: Sendable {
    let data: Data
    let format: LyricsFileFormat
}

struct ParsedLyricsDocument: Sendable {
    let lines: [LyricLine]
    let raw: RawLyricsPayload

    var lyricsList: LyricsList {
        let synced = !lines.isEmpty && lines.allSatisfy { $0.time >= 0 }
        let structuredLines = lines.map {
            StructuredLyricLine(
                start: synced ? Int(($0.time * 1_000).rounded()) : nil,
                value: $0.text
            )
        }
        let structured = StructuredLyrics(
            displayArtist: nil,
            displayTitle: nil,
            lang: nil,
            offset: nil,
            synced: synced,
            line: structuredLines
        )
        return LyricsList(structuredLyrics: [structured], rawPayload: raw)
    }
}

enum LyricsParser {
    static func parse(data: Data, formatHint: String? = nil) -> ParsedLyricsDocument? {
        guard !data.isEmpty else { return nil }
        let hintedFormat = LyricsFileFormat.from(hint: formatHint)

        // XMLParser consumes Data directly, preserving XML declarations and
        // UTF-8/UTF-16 BOMs. Sniff TTML even when a server omits/mislabels codec.
        let shouldParseTTML = hintedFormat == .ttml || TTMLLyricsParser.looksLikeXML(data)
        if shouldParseTTML {
            guard let parsed = TTMLLyricsParser.parse(data), !parsed.isEmpty else { return nil }
            return ParsedLyricsDocument(
                lines: makeDisplayLines(parsed),
                raw: RawLyricsPayload(data: data, format: .ttml)
            )
        }

        guard let text = decodeText(data) else { return nil }
        if hintedFormat == .lrc || looksLikeLRC(text),
           let lines = parseLRC(text), !lines.isEmpty {
            return ParsedLyricsDocument(
                lines: lines,
                raw: RawLyricsPayload(data: data, format: .lrc)
            )
        }

        let lines = parsePlain(text)
        guard !lines.isEmpty else { return nil }
        return ParsedLyricsDocument(
            lines: lines,
            raw: RawLyricsPayload(data: data, format: .plain)
        )
    }

    static func parse(text: String, formatHint: String? = nil) -> ParsedLyricsDocument? {
        parse(data: Data(text.utf8), formatHint: formatHint)
    }

    static func canonicalPayload(for lines: [LyricLine]) -> RawLyricsPayload? {
        guard !lines.isEmpty else { return nil }
        let synced = lines.allSatisfy { $0.time >= 0 }
        if synced {
            let text = lines.map { line in
                "[\(lrcTimestamp(line.time))]\(line.text)"
            }.joined(separator: "\n") + "\n"
            return RawLyricsPayload(data: Data(text.utf8), format: .lrc)
        }

        let text = lines.map(\.text).joined(separator: "\n") + "\n"
        return RawLyricsPayload(data: Data(text.utf8), format: .plain)
    }

    private static func makeDisplayLines(_ parsed: [TTMLParsedLine]) -> [LyricLine] {
        // The current renderer is either wholly synced or wholly plain. A mixed
        // document is kept complete and displayed as plain instead of assigning
        // missing TTML timestamps to zero and seeking to the wrong position.
        let fullySynced = parsed.allSatisfy { $0.startMilliseconds != nil }
        let ordered: [TTMLParsedLine]
        if fullySynced {
            ordered = parsed.enumerated().sorted {
                let lhs = $0.element.startMilliseconds ?? 0
                let rhs = $1.element.startMilliseconds ?? 0
                return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
            }.map(\.element)
        } else {
            ordered = parsed
        }
        return ordered.enumerated().map { index, line in
            LyricLine(
                id: index,
                time: fullySynced ? Double(line.startMilliseconds ?? 0) / 1_000 : -1,
                text: line.text
            )
        }
    }

    private static func looksLikeLRC(_ text: String) -> Bool {
        text.range(of: #"\[\d{1,3}:\d{2}(?:[\.:]\d{1,3})?\]"#,
                   options: .regularExpression) != nil
    }

    private static func parseLRC(_ text: String) -> [LyricLine]? {
        let pattern = #"\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let offsetRegex = try? NSRegularExpression(
            pattern: #"^\s*\[offset\s*:\s*([+-]?\d+)\]\s*$"#,
            options: [.caseInsensitive]
        )
        var offsetMilliseconds = 0
        var parsed: [(order: Int, time: TimeInterval, text: String)] = []

        // LRC offset is document-wide even when a producer writes the metadata
        // tag after lyric lines.
        for rawLine in text.components(separatedBy: .newlines) {
            let nsLine = rawLine as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            if let match = offsetRegex?.firstMatch(in: rawLine, range: fullRange),
               match.range(at: 1).location != NSNotFound {
                offsetMilliseconds = Int(nsLine.substring(with: match.range(at: 1))) ?? 0
                break
            }
        }

        for (order, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let nsLine = rawLine as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            if offsetRegex?.firstMatch(in: rawLine, range: fullRange) != nil { continue }

            let matches = regex.matches(in: rawLine, range: fullRange)
            guard !matches.isEmpty else { continue }
            let lyric = regex.stringByReplacingMatches(
                in: rawLine,
                range: fullRange,
                withTemplate: ""
            ).trimmingCharacters(in: .whitespaces)

            for match in matches {
                let minutes = Int(nsLine.substring(with: match.range(at: 1))) ?? 0
                let seconds = Int(nsLine.substring(with: match.range(at: 2))) ?? 0
                guard seconds < 60 else { continue }
                var milliseconds = 0
                if match.range(at: 3).location != NSNotFound {
                    let fraction = nsLine.substring(with: match.range(at: 3))
                    let value = Int(fraction) ?? 0
                    switch fraction.count {
                    case 1: milliseconds = value * 100
                    case 2: milliseconds = value * 10
                    default: milliseconds = value
                    }
                }
                let total = max(0, (minutes * 60 + seconds) * 1_000 + milliseconds + offsetMilliseconds)
                parsed.append((order, Double(total) / 1_000, lyric))
            }
        }

        guard !parsed.isEmpty else { return nil }
        return parsed.sorted {
            $0.time == $1.time ? $0.order < $1.order : $0.time < $1.time
        }.enumerated().map { index, line in
            LyricLine(id: index, time: line.time, text: line.text)
        }
    }

    private static func parsePlain(_ text: String) -> [LyricLine] {
        var lines = text.components(separatedBy: .newlines)
        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeFirst()
        }
        while lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeLast()
        }
        return lines.enumerated().map {
            LyricLine(id: $0.offset, time: -1, text: $0.element)
        }
    }

    private static func decodeText(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            if let text = String(data: data, encoding: .utf16) { return text.removingLeadingBOM }
        }
        if let text = String(data: data, encoding: .utf8) { return text.removingLeadingBOM }
        for encoding in [String.Encoding.utf16, .utf16LittleEndian, .utf16BigEndian] {
            if let text = String(data: data, encoding: encoding) { return text.removingLeadingBOM }
        }
        return nil
    }

    private static func lrcTimestamp(_ time: TimeInterval) -> String {
        let totalMilliseconds = max(0, Int((time * 1_000).rounded()))
        let minutes = totalMilliseconds / 60_000
        let seconds = (totalMilliseconds % 60_000) / 1_000
        let milliseconds = totalMilliseconds % 1_000
        return String(format: "%02d:%02d.%03d", minutes, seconds, milliseconds)
    }
}

private extension String {
    var removingLeadingBOM: String {
        first == "\u{FEFF}" ? String(dropFirst()) : self
    }
}

private struct TTMLParsedLine {
    let order: Int
    let startMilliseconds: Int?
    let text: String
}

private final class TTMLLyricsParser: NSObject, XMLParserDelegate {
    private enum TimeKind { case absolute, offset, ambiguous }

    private struct TimingParameters {
        var frameRate = 30.0
        var subFrameRate = 1.0
        var tickRate = 1.0
    }

    private struct TimingContext {
        var begin = 0
        var hasBegin = false
        var end = 0
        var hasEnd = false
        var invalid = false
        var preserveSpace = false
    }

    private enum TextPiece {
        case text(String, preserveSpace: Bool)
        case lineBreak
    }

    private struct Paragraph {
        let order: Int
        let context: TimingContext
        var earliestChildStart: Int?
        var pieces: [TextPiece]
    }

    private var parameters = TimingParameters()
    private var contexts: [TimingContext] = [TimingContext()]
    private var elementNames: [String] = []
    private var paragraph: Paragraph?
    private var parsedLines: [TTMLParsedLine] = []
    private var paragraphOrder = 0
    private var bodyDepth = 0
    private var sawRootTT = false
    private var parseError = false

    static func looksLikeXML(_ data: Data) -> Bool {
        let prefix = data.prefix(512)
        // UTF-16 XML has NULs between ASCII code units; decoding it as UTF-8
        // can technically succeed while producing a string that cannot be
        // sniffed. XMLParser will validate whether it is actually TTML.
        if prefix.contains(0) { return true }
        guard let text = LyricsParserTextDecoder.decode(prefix) else {
            return false
        }
        let lower = text.lowercased()
        return lower.contains("<?xml") || lower.contains("<tt") || lower.contains(":tt")
    }

    static func parse(_ data: Data) -> [TTMLParsedLine]? {
        let delegate = TTMLLyricsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), delegate.sawRootTT, !delegate.parseError else { return nil }
        return delegate.parsedLines.isEmpty ? nil : delegate.parsedLines
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = elementName.lowercased()
        if elementNames.isEmpty {
            guard name == "tt" else {
                parseError = true
                parser.abortParsing()
                return
            }
            sawRootTT = true
            updateTimingParameters(attributeDict)
        }

        let parent = contexts.last ?? TimingContext()
        let context = childContext(attributes: attributeDict, parent: parent)
        contexts.append(context)
        elementNames.append(name)

        if name == "body" { bodyDepth += 1 }
        guard bodyDepth > 0 else { return }

        if name == "p", paragraph == nil {
            paragraph = Paragraph(
                order: paragraphOrder,
                context: context,
                earliestChildStart: nil,
                pieces: []
            )
            paragraphOrder += 1
        } else if name == "br", paragraph != nil {
            paragraph?.pieces.append(.lineBreak)
        } else if name == "span", paragraph != nil, context.hasBegin, !context.invalid {
            if let current = paragraph?.earliestChildStart {
                paragraph?.earliestChildStart = min(current, context.begin)
            } else {
                paragraph?.earliestChildStart = context.begin
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard paragraph != nil else { return }
        let preserve = contexts.last?.preserveSpace ?? false
        paragraph?.pieces.append(.text(string, preserveSpace: preserve))
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard paragraph != nil, let text = LyricsParserTextDecoder.decode(CDATABlock) else { return }
        let preserve = contexts.last?.preserveSpace ?? false
        paragraph?.pieces.append(.text(text, preserveSpace: preserve))
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        if name == "p", let paragraph {
            let text = Self.flatten(paragraph.pieces)
            if !text.isEmpty, !paragraph.context.invalid {
                let start = paragraph.context.hasBegin
                    ? paragraph.context.begin
                    : paragraph.earliestChildStart
                parsedLines.append(TTMLParsedLine(
                    order: paragraph.order,
                    startMilliseconds: start,
                    text: text
                ))
            }
            self.paragraph = nil
        }
        if name == "body" { bodyDepth = max(0, bodyDepth - 1) }
        if !contexts.isEmpty { contexts.removeLast() }
        if !elementNames.isEmpty { elementNames.removeLast() }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = true
    }

    private func childContext(
        attributes: [String: String],
        parent: TimingContext
    ) -> TimingContext {
        var context = parent
        if let value = attribute("space", in: attributes)?.lowercased() {
            context.preserveSpace = value == "preserve"
        }

        let beginExpression = attribute("begin", in: attributes)
        let endExpression = attribute("end", in: attributes)
        let durationExpression = attribute("dur", in: attributes)

        if let beginExpression {
            guard let parsed = parseTime(beginExpression) else {
                context.invalid = true
                return context
            }
            let base = parent.hasBegin ? parent.begin : 0
            context.begin = resolve(parsed.value, kind: parsed.kind, base: base, parent: parent)
            context.hasBegin = true
        } else {
            context.begin = parent.begin
            context.hasBegin = parent.hasBegin
        }

        var calculatedEnd: Int?
        if let endExpression {
            guard let parsed = parseTime(endExpression) else {
                context.invalid = true
                return context
            }
            let base = context.hasBegin ? context.begin : (parent.hasBegin ? parent.begin : 0)
            calculatedEnd = resolve(parsed.value, kind: parsed.kind, base: base, parent: parent)
        }
        if let durationExpression {
            guard let duration = parseTime(durationExpression)?.value else {
                context.invalid = true
                return context
            }
            if context.hasBegin {
                let durationEnd = context.begin + duration
                calculatedEnd = min(calculatedEnd ?? durationEnd, durationEnd)
            }
        }
        if calculatedEnd == nil, parent.hasEnd { calculatedEnd = parent.end }
        if let calculatedEnd {
            context.end = calculatedEnd
            context.hasEnd = true
        } else {
            context.end = 0
            context.hasEnd = false
        }
        return context
    }

    private func updateTimingParameters(_ attributes: [String: String]) {
        if let raw = attribute("frameRate", in: attributes),
           let value = Double(raw), value > 0 {
            parameters.frameRate = value
        }
        if let raw = attribute("frameRateMultiplier", in: attributes) {
            let parts = raw.split(whereSeparator: \.isWhitespace).compactMap { Double($0) }
            if parts.count == 2, parts[1] > 0 {
                parameters.frameRate *= parts[0] / parts[1]
            }
        }
        if let raw = attribute("subFrameRate", in: attributes),
           let value = Double(raw), value > 0 {
            parameters.subFrameRate = value
        }
        if let raw = attribute("tickRate", in: attributes),
           let value = Double(raw), value > 0 {
            parameters.tickRate = value
        }
    }

    private func attribute(_ localName: String, in attributes: [String: String]) -> String? {
        if let exact = attributes[localName] { return exact.trimmingCharacters(in: .whitespacesAndNewlines) }
        for (key, value) in attributes {
            if key.split(separator: ":").last?.caseInsensitiveCompare(localName) == .orderedSame {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func parseTime(_ expression: String) -> (value: Int, kind: TimeKind)? {
        let value = expression.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty,
              !value.contains("wallclock("),
              !value.contains(".begin"),
              !value.contains(".end") else { return nil }

        if let seconds = Double(value), seconds >= 0 {
            return (Int((seconds * 1_000).rounded()), .ambiguous)
        }

        let offsetPattern = #"^([0-9]+(?:\.[0-9]+)?)(ms|h|m|s|f|t)$"#
        if let regex = try? NSRegularExpression(pattern: offsetPattern),
           let match = regex.firstMatch(
                in: value,
                range: NSRange(location: 0, length: (value as NSString).length)
           ) {
            let nsValue = value as NSString
            guard let number = Double(nsValue.substring(with: match.range(at: 1))) else { return nil }
            let unit = nsValue.substring(with: match.range(at: 2))
            let seconds: Double
            switch unit {
            case "h": seconds = number * 3_600
            case "m": seconds = number * 60
            case "s": seconds = number
            case "ms": seconds = number / 1_000
            case "f": seconds = number / parameters.frameRate
            case "t": seconds = number / parameters.tickRate
            default: return nil
            }
            return (Int((seconds * 1_000).rounded()), .offset)
        }

        let components = value.split(separator: ":", omittingEmptySubsequences: false)
        if components.count == 2 || components.count == 3 {
            var hours = 0.0
            var minutesIndex = 0
            if components.count == 3 {
                guard let parsedHours = Double(components[0]) else { return nil }
                hours = parsedHours
                minutesIndex = 1
            }
            guard let minutes = Double(components[minutesIndex]),
                  let seconds = Double(components[minutesIndex + 1]),
                  minutes >= 0, seconds >= 0 else { return nil }
            let total = hours * 3_600 + minutes * 60 + seconds
            return (Int((total * 1_000).rounded()), .absolute)
        }

        if components.count == 4,
           let hours = Double(components[0]),
           let minutes = Double(components[1]),
           let seconds = Double(components[2]) {
            let frameComponents = components[3].split(separator: ".", maxSplits: 1)
            guard let frames = Double(frameComponents[0]) else { return nil }
            let subframes = frameComponents.count == 2 ? (Double(frameComponents[1]) ?? 0) : 0
            let total = hours * 3_600 + minutes * 60 + seconds
                + frames / parameters.frameRate
                + subframes / (parameters.frameRate * parameters.subFrameRate)
            return (Int((total * 1_000).rounded()), .absolute)
        }
        return nil
    }

    private func resolve(
        _ value: Int,
        kind: TimeKind,
        base: Int,
        parent: TimingContext
    ) -> Int {
        switch kind {
        case .absolute:
            return value
        case .offset:
            return base + value
        case .ambiguous:
            let absolute = value
            let offset = base + value
            if parent.hasBegin, parent.hasEnd {
                let absoluteInParent = absolute >= parent.begin && absolute <= parent.end
                let offsetInParent = offset >= parent.begin && offset <= parent.end
                if absoluteInParent != offsetInParent {
                    return absoluteInParent ? absolute : offset
                }
            }
            if parent.hasBegin {
                if absolute < parent.begin && offset >= parent.begin { return offset }
                if absolute >= parent.begin && offset > absolute { return absolute }
            }
            return offset
        }
    }

    private static func flatten(_ pieces: [TextPiece]) -> String {
        var logicalLines: [[TextPiece]] = [[]]
        for piece in pieces {
            if case .lineBreak = piece {
                logicalLines.append([])
            } else {
                logicalLines[logicalLines.count - 1].append(piece)
            }
        }

        var lines = logicalLines.map { line -> String in
            var result = ""
            for case let .text(raw, preserve) in line {
                let normalized = preserve ? normalizeLineEndings(raw) : collapseXMLWhitespace(raw)
                if !preserve, result.last == " ", normalized.first == " " {
                    result.append(contentsOf: normalized.dropFirst())
                } else {
                    result.append(normalized)
                }
            }
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        while lines.first?.isEmpty == true { lines.removeFirst() }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    private static func collapseXMLWhitespace(_ raw: String) -> String {
        var result = ""
        var previousWasSpace = false
        for character in raw {
            let isXMLSpace = character == " " || character == "\t" || character == "\r" || character == "\n"
            if isXMLSpace {
                if !previousWasSpace { result.append(" ") }
                previousWasSpace = true
            } else {
                result.append(character)
                previousWasSpace = false
            }
        }
        return result
    }

    private static func normalizeLineEndings(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

private enum LyricsParserTextDecoder {
    static func decode<D: DataProtocol>(_ data: D) -> String? {
        let bytes = Data(data)
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]),
           let text = String(data: bytes, encoding: .utf16) {
            return text
        }
        if let text = String(data: bytes, encoding: .utf8) { return text }
        if let text = String(data: bytes, encoding: .utf16) { return text }
        if let text = String(data: bytes, encoding: .utf16LittleEndian) { return text }
        return String(data: bytes, encoding: .utf16BigEndian)
    }
}
