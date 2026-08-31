import Foundation

enum AutoMixAudioSource: Sendable {
    case file(url: URL, source: AutoMixAnalysisSource, complete: Bool)
    case remote(
        url: URL,
        headers: [String: String],
        fileExtension: String,
        requestedSeconds: TimeInterval,
        maximumBytes: Int
    )
    case unavailable
}

struct AutoMixAnalysisRequest: Sendable {
    let trackID: String
    let duration: TimeInterval
    let fileSize: Int?
    let bitrateKbps: Int?
    let metadataBPM: Double?
    let source: AutoMixAudioSource

    var fingerprint: String {
        var parts = [
            "v\(AutoMixTrackAnalysis.currentVersion)",
            trackID,
            String(format: "%.3f", duration),
            fileSize.map(String.init) ?? "?",
            bitrateKbps.map(String.init) ?? "?"
        ]
        switch source {
        case .file(let url, let source, let complete):
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            parts += [
                source.rawValue,
                url.lastPathComponent,
                values?.fileSize.map(String.init) ?? "?",
                values?.contentModificationDate?.timeIntervalSince1970.description ?? "?",
                complete ? "full" : "partial"
            ]
        case .remote(let url, _, let ext, let seconds, let maximumBytes):
            parts += [
                "remote",
                stableRemoteIdentity(url),
                ext,
                String(format: "%.1f", seconds),
                String(maximumBytes)
            ]
        case .unavailable:
            parts.append("unavailable")
        }
        return Crypto.md5Hex(parts.joined(separator: "|"))
    }

    private func stableRemoteIdentity(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "\(url.host ?? "")\(url.path)"
        }
        let volatileNames: Set<String> = [
            "u", "p", "t", "s", "token", "apikey", "api_key", "x-plex-token"
        ]
        components.queryItems = components.queryItems?
            .filter { !volatileNames.contains($0.name.lowercased()) }
            .sorted {
                if $0.name != $1.name { return $0.name < $1.name }
                return ($0.value ?? "") < ($1.value ?? "")
            }
        components.fragment = nil
        return components.string ?? "\(url.host ?? "")\(url.path)"
    }
}

protocol AutoMixAnalyzing: Sendable {
    func analyze(_ request: AutoMixAnalysisRequest) async -> AutoMixTrackAnalysis
}

actor AutoMixAnalysisService {
    static let shared = AutoMixAnalysisService()

    private let analyzer: any AutoMixAnalyzing
    private let cache: AutoMixAnalysisCache
    private let executionGate = AutoMixAnalysisExecutionGate()
    private var inFlight: [String: Task<AutoMixTrackAnalysis, Never>] = [:]
    private var prefetchTasks: [Task<Void, Never>] = []

    init(
        analyzer: any AutoMixAnalyzing = DSPAutoMixAnalyzer(),
        cache: AutoMixAnalysisCache = .shared
    ) {
        self.analyzer = analyzer
        self.cache = cache
    }

    func analysis(for request: AutoMixAnalysisRequest) async -> AutoMixTrackAnalysis {
        let fingerprint = request.fingerprint
        let key = "\(request.trackID)|\(fingerprint)"
        if let cached = await cache.load(trackID: request.trackID, fingerprint: fingerprint) {
            return cached
        }
        if let task = inFlight[key] { return await task.value }

        let analyzer = self.analyzer
        let cache = self.cache
        let gate = executionGate
        let task = Task(priority: .utility) {
            guard !Task.isCancelled else {
                return AutoMixTrackAnalysis.unavailable(
                    trackID: request.trackID,
                    fingerprint: fingerprint
                )
            }
            await gate.acquire()
            guard !Task.isCancelled else {
                await gate.release()
                return AutoMixTrackAnalysis.unavailable(
                    trackID: request.trackID,
                    fingerprint: fingerprint
                )
            }
            let analysis = await analyzer.analyze(request)
            await gate.release()
            guard !Task.isCancelled else { return analysis }
            await cache.store(analysis)
            return analysis
        }
        inFlight[key] = task
        let result = await task.value
        inFlight.removeValue(forKey: key)
        return result
    }

    // Current, next, and optionally +2 are the only queue analyses retained.
    // Replacing this window cancels obsolete decode/FFT work after skips.
    func setUpcoming(_ requests: [AutoMixAnalysisRequest]) {
        prefetchTasks.forEach { $0.cancel() }
        prefetchTasks.removeAll()

        let desired = Set(requests.map { "\($0.trackID)|\($0.fingerprint)" })
        for (key, task) in inFlight where !desired.contains(key) {
            task.cancel()
            inFlight.removeValue(forKey: key)
        }

        for (index, request) in requests.prefix(2).enumerated() {
            let priority: TaskPriority = index < 2 ? .userInitiated : .utility
            prefetchTasks.append(Task(priority: priority) { [weak self] in
                _ = await self?.analysis(for: request)
            })
        }
    }

    func cancelAll() {
        prefetchTasks.forEach { $0.cancel() }
        prefetchTasks.removeAll()
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
    }
}

private actor AutoMixAnalysisExecutionGate {
    private var available = true
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if available {
            available = false
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            available = true
        } else {
            waiters.removeFirst().resume()
        }
    }
}
