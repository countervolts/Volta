import Foundation

// Exports locally logged play events as JSON + CSV for the user to keep or analyse.
enum StatsExporter {
    static func exportURLs() throws -> [URL] {
        let events = StatsStore.shared.allEvents()
        let dir = FileManager.default.temporaryDirectory
        let stamp = Int(Date().timeIntervalSince1970)

        let jsonURL = dir.appendingPathComponent("volta-stats-\(stamp).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(events).write(to: jsonURL, options: .atomic)

        let csvURL = dir.appendingPathComponent("volta-stats-\(stamp).csv")
        let iso = ISO8601DateFormatter()
        var csv = "timestamp,title,artist,album,genre,durationSeconds,songID\n"
        for e in events {
            let row = [
                iso.string(from: e.timestamp),
                e.title, e.artist, e.album, e.genre ?? "",
                String(e.duration), e.songID,
            ].map(escape).joined(separator: ",")
            csv += row + "\n"
        }
        try csv.data(using: .utf8)?.write(to: csvURL, options: .atomic)

        return [jsonURL, csvURL]
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
