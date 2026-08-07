import Foundation
import Darwin

#if canImport(MetricKit)
import MetricKit
#endif

enum ReliabilityReportKind: String, CaseIterable, Identifiable, Sendable {
    case crash
    case hang

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crash: return "Crashes"
        case .hang: return "Hangs"
        }
    }

    var singularTitle: String {
        switch self {
        case .crash: return "Crash"
        case .hang: return "Hang"
        }
    }

    var directoryName: String {
        switch self {
        case .crash: return "Crashes"
        case .hang: return "Hangs"
        }
    }

    var fileExtension: String {
        switch self {
        case .crash: return "ips"
        case .hang: return "txt"
        }
    }
}

struct ReliabilityReport: Identifiable, Equatable, Sendable {
    let url: URL
    let kind: ReliabilityReportKind
    let occurredAt: Date
    let duration: TimeInterval?
    let source: String?
    let crashType: String?
    let crashCause: String?
    let sizeBytes: Int

    var id: URL { url }

    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }

    var durationDescription: String? {
        guard let duration else { return nil }
        if duration < 1 {
            return "\(Int((duration * 1_000).rounded())) ms"
        }
        return duration.formatted(.number.precision(.fractionLength(2))) + " s"
    }
}

private struct CrashReportSummary: Sendable {
    let type: String
    let cause: String
}

private enum CrashReportSummaries {
    static func interruptedSession(afterMemoryWarning: Bool) -> CrashReportSummary {
        if afterMemoryWarning {
            return CrashReportSummary(
                type: "Possible memory-pressure termination",
                cause: "iOS sent Volta a low-memory warning before it stopped running."
            )
        }
        return CrashReportSummary(
            type: "Unexpected foreground termination",
            cause: "Volta stopped while foregrounded without a normal background transition."
        )
    }

    static func stored(type: String?, cause: String?, source: String?, details: String) -> CrashReportSummary {
        if let type, let cause {
            return CrashReportSummary(type: type, cause: cause)
        }

        let combined = "\(source ?? "")\n\(details)".lowercased()
        if combined.contains("low-memory") || combined.contains("memory pressure") || combined.contains("jetsam") {
            return interruptedSession(afterMemoryWarning: true)
        }
        if source == "MetricKit" {
            return CrashReportSummary(
                type: "iOS-reported crash",
                cause: "MetricKit delivered a system crash diagnostic; its stack data is in the attached .ips file."
            )
        }
        return interruptedSession(afterMemoryWarning: false)
    }

    #if canImport(MetricKit)
    static func metricKit(_ crash: MXCrashDiagnostic) -> CrashReportSummary {
        let terminationReason = compact(crash.terminationReason)
        let terminationLowercased = terminationReason?.lowercased() ?? ""
        if terminationLowercased.contains("memory")
            || terminationLowercased.contains("jetsam")
            || terminationLowercased.contains("highwater") {
            return CrashReportSummary(
                type: "Memory-pressure termination",
                cause: terminationReason ?? "iOS terminated Volta after it exceeded its available memory budget."
            )
        }

        if let signal = crash.signal?.intValue {
            let signalSummary: CrashReportSummary?
            switch signal {
            case Int(SIGABRT):
                signalSummary = CrashReportSummary(type: "Abort signal (SIGABRT)", cause: terminationReason ?? "The process deliberately aborted or hit a fatal runtime assertion.")
            case Int(SIGSEGV):
                signalSummary = CrashReportSummary(type: "Segmentation fault (SIGSEGV)", cause: terminationReason ?? "Volta accessed invalid memory.")
            case Int(SIGILL):
                signalSummary = CrashReportSummary(type: "Illegal instruction (SIGILL)", cause: terminationReason ?? "The runtime reached an invalid instruction.")
            case Int(SIGTRAP):
                signalSummary = CrashReportSummary(type: "Swift runtime trap (SIGTRAP)", cause: terminationReason ?? "A fatal Swift check, such as a forced unwrap or bounds check, triggered a trap.")
            case Int(SIGKILL):
                signalSummary = CrashReportSummary(type: "Process killed (SIGKILL)", cause: terminationReason ?? "iOS terminated the process without allowing Volta to run cleanup code.")
            default:
                signalSummary = nil
            }
            if let signalSummary { return signalSummary }
        }

        if let exceptionType = crash.exceptionType?.intValue {
            return CrashReportSummary(
                type: "Mach exception \(exceptionType)",
                cause: terminationReason ?? "iOS reported a low-level process exception."
            )
        }
        return CrashReportSummary(
            type: "iOS-reported crash",
            cause: terminationReason ?? "MetricKit reported the crash; the attached .ips contains the available system stack data."
        )
    }
    #endif

    private static func compact(_ text: String?) -> String? {
        guard let text else { return nil }
        let compacted = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !compacted.isEmpty else { return nil }
        return compacted.count > 180 ? String(compacted.prefix(177)) + "…" : compacted
    }
}

extension Notification.Name {
    static let reliabilityReportsChanged = Notification.Name("ReliabilityReportsChanged")
}

/// Keeps developer-facing crash and hang reports local until the user explicitly shares one.
final class CrashHangReportStore: @unchecked Sendable {
    static let shared = CrashHangReportStore()

    static let maxReportsPerKind = 5

    private let queue = DispatchQueue(label: "com.ayo.volta.reliability-reports")
    private let fileManager = FileManager.default
    private let foregroundSessionFileName = "active-foreground-session"
    private let foregroundSessionDefaultsKey = "com.ayo.volta.reliability.active-foreground-session"
    private let foregroundSessionHeartbeatDefaultsKey = "com.ayo.volta.reliability.active-foreground-session-heartbeat"

    private init() {}

    func reports() -> [ReliabilityReport] {
        queue.sync {
            ReliabilityReportKind.allCases
                .flatMap(reportsLocked(for:))
                .sorted { $0.occurredAt > $1.occurredAt }
        }
    }

    func reports(for kind: ReliabilityReportKind) -> [ReliabilityReport] {
        queue.sync { reportsLocked(for: kind) }
    }

    func beginForegroundSession() {
        queue.sync {
            let now = Date()
            let session = [
                "Volta foreground session",
                "Started-At: \(iso8601(now))",
                "App-Version: \(appVersion())",
                ""
            ].joined(separator: "\n")
            UserDefaults.standard.set(session, forKey: foregroundSessionDefaultsKey)
            UserDefaults.standard.set(now, forKey: foregroundSessionHeartbeatDefaultsKey)
            guard let url = foregroundSessionURLLocked() else { return }
            try? session.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func touchForegroundSession() {
        queue.async { [weak self] in
            guard let self else { return }
            let now = Date()
            UserDefaults.standard.set(now, forKey: self.foregroundSessionHeartbeatDefaultsKey)
            guard let url = self.foregroundSessionURLLocked(),
                  self.fileManager.fileExists(atPath: url.path) else { return }
            try? self.fileManager.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
        }
    }

    /// Preserves the fact that iOS warned the process about memory pressure before
    /// a possible termination. This is intentionally written synchronously while
    /// the app is still alive, because an out-of-memory termination can happen at
    /// any point after the warning.
    func recordMemoryWarning() {
        queue.sync {
            guard let url = foregroundSessionURLLocked() else { return }

            var session = (try? String(contentsOf: url, encoding: .utf8))
                ?? UserDefaults.standard.string(forKey: foregroundSessionDefaultsKey)
                ?? ""
            guard !session.isEmpty else { return }
            if !session.isEmpty, !session.hasSuffix("\n") {
                session.append("\n")
            }
            let now = Date()
            session += "Memory-Warning-At: \(iso8601(now))\n"
            UserDefaults.standard.set(session, forKey: foregroundSessionDefaultsKey)
            UserDefaults.standard.set(now, forKey: foregroundSessionHeartbeatDefaultsKey)
            try? session.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func endForegroundSession() {
        queue.sync {
            clearForegroundSessionDefaultsLocked()
            guard let url = foregroundSessionURLLocked() else { return }
            try? fileManager.removeItem(at: url)
        }
    }

    /// A foreground marker left from the previous run is a local fallback for a
    /// termination that prevented normal lifecycle cleanup. MetricKit can later
    /// add the richer system diagnostic when iOS makes it available.
    func recoverInterruptedForegroundSession() {
        queue.sync {
            let storedSession = UserDefaults.standard.string(forKey: foregroundSessionDefaultsKey)
            let storedHeartbeat = UserDefaults.standard.object(forKey: foregroundSessionHeartbeatDefaultsKey) as? Date
            let marker = foregroundSessionURLLocked()
            let markerExists = marker.map { fileManager.fileExists(atPath: $0.path) } ?? false
            guard markerExists || storedSession != nil else { return }

            let attributes = marker.flatMap { try? fileManager.attributesOfItem(atPath: $0.path) }
            let fileHeartbeat = attributes?[.modificationDate] as? Date
            let lastHeartbeat = [fileHeartbeat, storedHeartbeat].compactMap { $0 }.max() ?? Date()
            let startedText = marker.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
                ?? storedSession
                ?? ""
            let lastMemoryWarning = headerValues("Memory-Warning-At", in: startedText).last

            let source: String
            let crashSummary: CrashReportSummary
            var details = [
                "The app did not receive a normal foreground-to-background lifecycle transition."
            ]
            if let lastMemoryWarning {
                source = "Interrupted foreground session after low-memory warning"
                crashSummary = CrashReportSummaries.interruptedSession(afterMemoryWarning: true)
                details.append("iOS sent a low-memory warning at \(lastMemoryWarning), so memory pressure may have caused this termination. This fallback cannot confirm a jetsam/OOM reason on its own.")
            } else {
                source = "Interrupted foreground session"
                crashSummary = CrashReportSummaries.interruptedSession(afterMemoryWarning: false)
                details.append("This is a local termination marker; a detailed iOS diagnostic may arrive later through MetricKit.")
            }
            details += [
                "",
                "Previous session marker:",
                startedText
            ]

            let didWrite = writeReportLocked(
                kind: .crash,
                occurredAt: lastHeartbeat,
                duration: nil,
                source: source,
                crashType: crashSummary.type,
                crashCause: crashSummary.cause,
                details: details.joined(separator: "\n")
            )
            guard didWrite else { return }

            if let marker {
                try? fileManager.removeItem(at: marker)
            }
            clearForegroundSessionDefaultsLocked()
        }
    }

    func recordHang(occurredAt: Date, duration: TimeInterval, source: String, details: String) {
        guard duration >= CrashHangReporter.minimumHangDuration else { return }
        queue.async { [weak self] in
            self?.writeReportLocked(
                kind: .hang,
                occurredAt: occurredAt,
                duration: duration,
                source: source,
                details: details
            )
        }
    }

    func recordCrash(
        occurredAt: Date,
        source: String,
        crashType: String? = nil,
        crashCause: String? = nil,
        details: String
    ) {
        queue.async { [weak self] in
            self?.writeReportLocked(
                kind: .crash,
                occurredAt: occurredAt,
                duration: nil,
                source: source,
                crashType: crashType,
                crashCause: crashCause,
                details: details
            )
        }
    }

    func delete(_ report: ReliabilityReport) {
        queue.async { [weak self] in
            guard let self else { return }
            try? self.fileManager.removeItem(at: report.url)
            self.notifyReportsChanged()
        }
    }

    func deleteAll(kind: ReliabilityReportKind) {
        queue.async { [weak self] in
            guard let self, let directory = self.reportDirectoryLocked(for: kind) else { return }
            let urls = (try? self.fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            for url in urls where url.pathExtension.lowercased() == kind.fileExtension {
                try? self.fileManager.removeItem(at: url)
            }
            self.notifyReportsChanged()
        }
    }

    @discardableResult
    private func writeReportLocked(
        kind: ReliabilityReportKind,
        occurredAt: Date,
        duration: TimeInterval?,
        source: String,
        crashType: String? = nil,
        crashCause: String? = nil,
        details: String
    ) -> Bool {
        guard let directory = reportDirectoryLocked(for: kind) else { return false }

        let name = "Volta-\(kind.singularTitle)-\(Int(occurredAt.timeIntervalSince1970 * 1_000))-\(UUID().uuidString.prefix(8)).\(kind.fileExtension)"
        let url = directory.appendingPathComponent(name, isDirectory: false)
        var header = [
            "Volta \(kind.singularTitle) Report",
            "Report-Type: \(kind.rawValue)",
            "Occurred-At: \(iso8601(occurredAt))",
            "Source: \(source)",
            "App-Version: \(appVersion())",
            "Bundle-ID: \(Bundle.main.bundleIdentifier ?? "unknown")",
            "OS: \(ProcessInfo.processInfo.operatingSystemVersionString)"
        ]
        if let duration {
            header.append("Duration-Milliseconds: \(Int((duration * 1_000).rounded()))")
        }
        if kind == .crash {
            if let crashType {
                header.append("Crash-Type: \(crashType)")
            }
            if let crashCause {
                header.append("Crash-Cause: \(crashCause)")
            }
        }
        header.append("")
        header.append(details)

        do {
            try header.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            trimLocked(kind: kind)
            notifyReportsChanged()
            return true
        } catch {
            // A diagnostics write must never interfere with playback or app recovery.
            return false
        }
    }

    private func reportsLocked(for kind: ReliabilityReportKind) -> [ReliabilityReport] {
        guard let directory = reportDirectoryLocked(for: kind) else { return [] }
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.compactMap { reportLocked(at: $0, kind: kind) }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    private func reportLocked(at url: URL, kind: ReliabilityReportKind) -> ReliabilityReport? {
        guard url.pathExtension.lowercased() == kind.fileExtension else { return nil }
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey])
        let fallbackDate = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
        let size = values?.fileSize ?? 0

        let prefix: String
        if let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) {
            prefix = String(decoding: data.prefix(4_096), as: UTF8.self)
        } else {
            prefix = ""
        }

        let occurredAt = headerValue("Occurred-At", in: prefix).flatMap(date(from:)) ?? fallbackDate
        let duration = headerValue("Duration-Milliseconds", in: prefix)
            .flatMap(Double.init)
            .map { $0 / 1_000 }
        let source = headerValue("Source", in: prefix)
        let summary = kind == .crash
            ? CrashReportSummaries.stored(
                type: headerValue("Crash-Type", in: prefix),
                cause: headerValue("Crash-Cause", in: prefix),
                source: source,
                details: prefix
            )
            : nil

        return ReliabilityReport(
            url: url,
            kind: kind,
            occurredAt: occurredAt,
            duration: duration,
            source: source,
            crashType: summary?.type,
            crashCause: summary?.cause,
            sizeBytes: size
        )
    }

    private func trimLocked(kind: ReliabilityReportKind) {
        let reports = reportsLocked(for: kind)
        guard reports.count > Self.maxReportsPerKind else { return }
        for report in reports.dropFirst(Self.maxReportsPerKind) {
            try? fileManager.removeItem(at: report.url)
        }
    }

    private func reportDirectoryLocked(for kind: ReliabilityReportKind) -> URL? {
        guard let base = baseDirectoryLocked() else { return nil }
        let directory = base.appendingPathComponent(kind.directoryName, isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            return nil
        }
    }

    private func foregroundSessionURLLocked() -> URL? {
        guard let base = baseDirectoryLocked() else { return nil }
        return base.appendingPathComponent(foregroundSessionFileName, isDirectory: false)
    }

    private func clearForegroundSessionDefaultsLocked() {
        UserDefaults.standard.removeObject(forKey: foregroundSessionDefaultsKey)
        UserDefaults.standard.removeObject(forKey: foregroundSessionHeartbeatDefaultsKey)
    }

    private func baseDirectoryLocked() -> URL? {
        guard let applicationSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }

        let directory = applicationSupport.appendingPathComponent("ReliabilityReports", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            return nil
        }
    }

    private func notifyReportsChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .reliabilityReportsChanged, object: nil)
        }
    }

    private func headerValue(_ name: String, in text: String) -> String? {
        headerValues(name, in: text).first
    }

    private func headerValues(_ name: String, in text: String) -> [String] {
        let prefix = "\(name):"
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            guard line.hasPrefix(prefix) else { return nil }
            return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
    }

    private func date(from text: String) -> Date? {
        ISO8601DateFormatter().date(from: text)
    }

    private func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func appVersion() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}

/// Watches the foreground main queue and writes a report only after a confirmed
/// 250 ms-or-longer stall. The watchdog runs off-main, so reporting never makes
/// an existing hang worse.
final class CrashHangReporter: NSObject {
    static let shared = CrashHangReporter()

    static let minimumHangDuration: TimeInterval = 0.250

    private let stateLock = NSLock()
    private let watchdogQueue = DispatchQueue(label: "com.ayo.volta.hang-watchdog", qos: .utility)
    private var heartbeatTimer: DispatchSourceTimer?
    private var watchdogTimer: DispatchSourceTimer?
    private var isForegroundActive = false
    private var lastHeartbeat = ProcessInfo.processInfo.systemUptime
    private var hangStartedAt: TimeInterval?
    private var lastForegroundSessionTouch = 0.0
    private var hasStarted = false

    private override init() {
        super.init()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        CrashHangReportStore.shared.recoverInterruptedForegroundSession()

        #if canImport(MetricKit)
        MXMetricManager.shared.add(self)
        #endif
    }

    func beginForegroundMonitoring() {
        let shouldStart = stateLock.withLock {
            guard !isForegroundActive else { return false }
            isForegroundActive = true
            lastHeartbeat = ProcessInfo.processInfo.systemUptime
            hangStartedAt = nil
            lastForegroundSessionTouch = lastHeartbeat
            return true
        }
        guard shouldStart else { return }

        CrashHangReportStore.shared.beginForegroundSession()

        let heartbeat = DispatchSource.makeTimerSource(queue: .main)
        heartbeat.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(10))
        heartbeat.setEventHandler { [weak self] in
            self?.recordHeartbeat()
        }
        heartbeat.resume()
        heartbeatTimer = heartbeat

        let watchdog = DispatchSource.makeTimerSource(queue: watchdogQueue)
        watchdog.schedule(deadline: .now() + .milliseconds(50), repeating: .milliseconds(50), leeway: .milliseconds(10))
        watchdog.setEventHandler { [weak self] in
            self?.watchdogTick()
        }
        watchdog.resume()
        watchdogTimer = watchdog
    }

    /// Stops hang monitoring while retaining the marker until UIKit confirms a
    /// normal background transition. A crash, OOM kill, or forced test crash must
    /// never remove the marker itself.
    func pauseForegroundMonitoring() {
        stopForegroundMonitoring(removingSessionMarker: false)
    }

    /// Call only after UIKit has confirmed a normal background transition.
    func endForegroundMonitoring() {
        stopForegroundMonitoring(removingSessionMarker: true)
    }

    func recordMemoryWarning() {
        CrashHangReportStore.shared.recordMemoryWarning()
    }

    private func stopForegroundMonitoring(removingSessionMarker: Bool) {
        stateLock.withLock {
            isForegroundActive = false
            hangStartedAt = nil
        }
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        watchdogTimer?.cancel()
        watchdogTimer = nil
        if removingSessionMarker {
            CrashHangReportStore.shared.endForegroundSession()
        }
    }

    private func recordHeartbeat() {
        stateLock.withLock {
            guard isForegroundActive else { return }
            lastHeartbeat = ProcessInfo.processInfo.systemUptime
        }
    }

    private func watchdogTick() {
        let now = ProcessInfo.processInfo.systemUptime
        var completedHang: (startedAt: TimeInterval, duration: TimeInterval)?
        var shouldTouchSession = false

        stateLock.withLock {
            guard isForegroundActive else { return }

            let elapsed = now - lastHeartbeat
            if elapsed >= Self.minimumHangDuration {
                if hangStartedAt == nil {
                    hangStartedAt = lastHeartbeat
                }
            } else if let startedAt = hangStartedAt {
                completedHang = (startedAt, max(0, now - startedAt))
                hangStartedAt = nil
            }

            if now - lastForegroundSessionTouch >= 1 {
                lastForegroundSessionTouch = now
                shouldTouchSession = true
            }
        }

        if shouldTouchSession {
            CrashHangReportStore.shared.touchForegroundSession()
        }

        guard let completedHang, completedHang.duration >= Self.minimumHangDuration else { return }
        let occurredAt = Date().addingTimeInterval(-max(0, now - completedHang.startedAt))
        CrashHangReportStore.shared.recordHang(
            occurredAt: occurredAt,
            duration: completedHang.duration,
            source: "Foreground main-thread watchdog",
            details: [
                "The foreground main queue did not process its 50 ms heartbeat for \(Int((completedHang.duration * 1_000).rounded())) ms.",
                "The report was saved after the main queue became responsive again.",
                ""
            ].joined(separator: "\n")
        )
    }
}

/// Deliberately native, immediate crashes for developer diagnostics testing.
/// These functions never write or alter a report: recovery and MetricKit are
/// responsible for producing the later `.ips` entry.
enum DeveloperCrashTest {
    static func fatalError() -> Never {
        Swift.fatalError("Developer crash test: fatalError")
    }

    static func failedPrecondition() -> Never {
        Swift.preconditionFailure("Developer crash test: failed precondition")
    }

    static func forceUnwrapNil() -> Never {
        let value: String? = nil
        _ = value!
        Swift.fatalError("Unreachable after a forced nil unwrap")
    }

    static func arrayIndexOutOfRange() -> Never {
        let values = [0]
        _ = values[1]
        Swift.fatalError("Unreachable after an out-of-range array access")
    }

    static func abortSignal() -> Never {
        _ = Darwin.raise(SIGABRT)
        Swift.fatalError("SIGABRT was unexpectedly handled")
    }

    static func segmentationFault() -> Never {
        _ = Darwin.raise(SIGSEGV)
        Swift.fatalError("SIGSEGV was unexpectedly handled")
    }
}

#if canImport(MetricKit)
extension CrashHangReporter: MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXMetricPayload]) {
        // This monitor only persists crash and hang diagnostics.
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                let diagnostic = String(decoding: crash.jsonRepresentation(), as: UTF8.self)
                let summary = CrashReportSummaries.metricKit(crash)
                CrashHangReportStore.shared.recordCrash(
                    occurredAt: payload.timeStampEnd,
                    source: "MetricKit",
                    crashType: summary.type,
                    crashCause: summary.cause,
                    details: [
                        "iOS delivered this MetricKit crash diagnostic. The timestamp is the end of MetricKit's reporting window.",
                        "",
                        diagnostic
                    ].joined(separator: "\n")
                )
            }

            for hang in payload.hangDiagnostics ?? [] {
                let duration = hang.hangDuration.converted(to: .seconds).value
                guard duration >= Self.minimumHangDuration else { continue }
                let diagnostic = String(decoding: hang.jsonRepresentation(), as: UTF8.self)
                CrashHangReportStore.shared.recordHang(
                    occurredAt: payload.timeStampEnd.addingTimeInterval(-duration),
                    duration: duration,
                    source: "MetricKit",
                    details: [
                        "iOS delivered this MetricKit hang diagnostic. The report includes the system-captured call stack tree.",
                        "",
                        diagnostic
                    ].joined(separator: "\n")
                )
            }
        }
    }
}
#endif
