import Foundation

actor AutoMixAnalysisCache {
    static let shared = AutoMixAnalysisCache()

    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let maximumEntryCount = 2_000
    private let maximumBytes = 160 * 1_048_576

    init(baseDirectory: URL? = nil) {
        let root = baseDirectory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = root.appendingPathComponent("automix-v2", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    func load(trackID: String, fingerprint: String) -> AutoMixTrackAnalysis? {
        let url = entryURL(trackID: trackID, fingerprint: fingerprint)
        guard let data = try? Data(contentsOf: url),
              let analysis = try? decoder.decode(AutoMixTrackAnalysis.self, from: data),
              analysis.analysisVersion == AutoMixTrackAnalysis.currentVersion,
              analysis.trackID == trackID,
              analysis.sourceFingerprint == fingerprint else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return analysis
    }

    func store(_ analysis: AutoMixTrackAnalysis) {
        guard analysis.analysisVersion == AutoMixTrackAnalysis.currentVersion,
              !analysis.trackID.isEmpty,
              !analysis.sourceFingerprint.isEmpty,
              let data = try? encoder.encode(analysis) else { return }
        let url = entryURL(
            trackID: analysis.trackID,
            fingerprint: analysis.sourceFingerprint
        )
        do {
            try data.write(to: url, options: .atomic)
            pruneIfNeeded()
        } catch {
            AppLogger.shared.log(
                "AutoMix cache write failed; songID=\(analysis.trackID); error=\(error.localizedDescription)",
                category: .playback,
                level: .warning
            )
        }
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    private func entryURL(trackID: String, fingerprint: String) -> URL {
        let key = Crypto.md5Hex("\(AutoMixTrackAnalysis.currentVersion)|\(trackID)|\(fingerprint)")
        return directory.appendingPathComponent("\(key).json")
    }

    private func pruneIfNeeded() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var entries: [(url: URL, date: Date, bytes: Int)] = urls.compactMap { url in
            guard url.pathExtension == "json",
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
                return nil
            }
            return (url, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0)
        }
        var bytes = entries.reduce(0) { $0 + $1.bytes }
        guard entries.count > maximumEntryCount || bytes > maximumBytes else { return }
        entries.sort { $0.date < $1.date }
        while entries.count > maximumEntryCount || bytes > maximumBytes {
            let entry = entries.removeFirst()
            try? FileManager.default.removeItem(at: entry.url)
            bytes -= entry.bytes
        }
    }
}
