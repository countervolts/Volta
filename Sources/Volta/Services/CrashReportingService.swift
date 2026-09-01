import Foundation
#if canImport(Sentry)
import Sentry
#endif

/// Opt-in Sentry crash reporting with a deliberately minimal event payload.
@MainActor
final class CrashReportingService {
    static let preferenceKey = "shareAnonymousCrashReports"
    static let shared = CrashReportingService()

    private let defaults: UserDefaults
    private let cacheDirectory: URL
    private var isStarted = false

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.cacheDirectory = (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("VoltaCrashReporting", isDirectory: true)
    }

    var isEnabled: Bool {
        defaults.bool(forKey: Self.preferenceKey)
    }

    func startIfEnabled() {
#if canImport(Sentry)
        guard isEnabled, !isStarted else { return }
        let cacheDirectoryPath = prepareCacheDirectory()

        SentrySDK.start { options in
            options.dsn = "https://4ce67bb27db84672bd198024147a1c35@crash.voltamusic.xyz/1"
            options.cacheDirectoryPath = cacheDirectoryPath
            options.releaseName = releaseName()
            options.environment = "production"
            options.shutdownTimeInterval = 0

            options.sendDefaultPii = false
            options.enableMemoryIntrospection = false
            options.enableCrashHandler = true
            options.enableSigtermReporting = false
            options.enableWatchdogTerminationTracking = false
            options.enableAutoSessionTracking = false
            options.sendClientReports = false

            options.maxBreadcrumbs = 0
            options.enableAutoBreadcrumbTracking = false
            options.enableNetworkBreadcrumbs = false
            options.beforeBreadcrumb = { _ in nil }

            options.tracesSampleRate = 0
            options.enableAutoPerformanceTracing = false
            options.enablePersistingTracesWhenCrashing = false
            options.enableUIViewControllerTracing = false
            options.enableUserInteractionTracing = false
            options.enablePreWarmedAppStartTracing = false
            options.enableNetworkTracking = false
            options.enableFileIOTracing = false
            options.enableDataSwizzling = false
            options.enableFileManagerSwizzling = false
            options.enableCoreDataTracing = false
            options.enableCaptureFailedRequests = false
            options.tracePropagationTargets = []
            options.failedRequestTargets = []
            options.configureProfiling = nil
            options.enableAppHangTracking = false
            options.enableReportNonFullyBlockingAppHangs = false
            options.enableMetricKit = false
            options.enableMetricKitRawPayload = false
            options.enableLogs = false

            options.attachScreenshot = false
            options.attachViewHierarchy = false
            options.reportAccessibilityIdentifier = false
            options.sessionReplay.sessionSampleRate = 0
            options.sessionReplay.onErrorSampleRate = 0

            options.initialScope = { scope in
                scope.clear()
                return scope
            }
            options.beforeSend = sanitize
        }
        isStarted = true
#endif
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.preferenceKey)
        if enabled {
            startIfEnabled()
        } else {
            close()
        }
    }

    func sendTestEvent() -> Bool {
#if canImport(Sentry)
        guard isEnabled else { return false }
        startIfEnabled()
        SentrySDK.capture(message: syntheticTestMessage)
        return true
#else
        return false
#endif
    }

    private func close() {
#if canImport(Sentry)
        guard isStarted else { return }
        SentrySDK.close()
        try? FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent("INSTALLATION"))
        isStarted = false
#endif
    }

    private func prepareCacheDirectory() -> String {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent("INSTALLATION"))
        return cacheDirectory.path
    }
}

#if canImport(Sentry)
private let syntheticTestMessage = "Volta crash reporting connectivity test"

private func releaseName() -> String {
    let bundle = Bundle.main
    let identifier = bundle.bundleIdentifier ?? "com.ayo.music"
    let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    return "\(identifier)@\(version)+\(build)"
}

private func sanitize(_ event: Event) -> Event {
    event.user = nil
    event.request = nil
    event.breadcrumbs = nil
    event.tags = nil
    event.extra = nil
    event.context = nil
    event.serverName = nil
    event.transaction = nil

    if event.message?.formatted != syntheticTestMessage {
        event.message = nil
    }

    for exception in event.exceptions ?? [] {
        exception.value = nil
        exception.module = nil
        exception.mechanism?.desc = nil
        exception.mechanism?.data = nil
        exception.mechanism?.helpLink = nil
    }

    return event
}
#endif
