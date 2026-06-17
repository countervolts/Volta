import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class LoginViewModel {
    // Lightweight pre-flight result for the server address, shown as an inline
    // indicator so the user knows the URL is good before typing credentials.
    enum ServerReachability: Equatable {
        case idle
        case checking
        case reachable(insecure: Bool)
        case unreachable
    }

    // nil => the user is still on the service-selection step. Once a backend is
    // chosen the credentials form is shown and connect() targets that backend.
    var selectedBackend: MusicBackendKind?

    var serverAddress = ""
    var username = ""
    var password = ""

    private(set) var isConnecting = false
    private(set) var isPlexHostedSigningIn = false
    private(set) var serverError: String?
    private(set) var credentialsError: String?

    private(set) var reachability: ServerReachability = .idle
    @ObservationIgnored private var reachabilityTask: Task<Void, Never>?

    // incremented to retrigger the shake animation on the relevant fields.
    private(set) var serverShake = 0
    private(set) var credentialsShake = 0

    // Short-timeout, non-caching session used only for login probing so a server
    // that's slow or only speaks http doesn't make the user wait the full default.
    private static let probeSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    var canSubmit: Bool {
        selectedBackend != nil &&
        !serverAddress.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty &&
        !isConnecting &&
        !isPlexHostedSigningIn
    }

    var canStartPlexHostedSignIn: Bool {
        selectedBackend == .plex &&
        !serverAddress.trimmingCharacters(in: .whitespaces).isEmpty &&
        !isConnecting &&
        !isPlexHostedSigningIn
    }

    var usesInsecureHTTP: Bool {
        SubsonicConfig.normalizedURL(from: serverAddress)?.scheme?.lowercased() == "http"
    }

    func select(_ backend: MusicBackendKind) {
        selectedBackend = backend
        serverError = nil
        credentialsError = nil
    }

    func deselect() {
        selectedBackend = nil
        serverError = nil
        credentialsError = nil
        reachabilityTask?.cancel()
        reachability = .idle
    }

    // Prefill the public demo for the selected backend so people can explore
    // without their own server. Returns false if that backend has no demo.
    @discardableResult
    func fillDemoServer() -> Bool {
        guard let kind = selectedBackend, let demo = DemoServers.entry(for: kind) else { return false }
        serverAddress = demo.address
        username = demo.username
        password = demo.password
        serverError = nil
        credentialsError = nil
        reachability = .reachable(insecure: false)
        return true
    }

    // MARK: - Server reachability pre-check

    // Debounced from the view as the user edits the server field. Reports whether
    // the host answers (and on which scheme) without touching credentials.
    func serverAddressChanged() {
        reachabilityTask?.cancel()
        let address = serverAddress
        let candidates = SubsonicConfig.candidateURLs(from: address)
        guard !candidates.isEmpty else {
            reachability = .idle
            return
        }
        reachabilityTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.runReachabilityCheck(candidates: candidates, address: address)
        }
    }

    private func runReachabilityCheck(candidates: [URL], address: String) async {
        guard address == serverAddress else { return }
        reachability = .checking
        for url in candidates {
            if Task.isCancelled { return }
            if await Self.hostResponds(url) {
                guard address == serverAddress else { return }
                reachability = .reachable(insecure: url.scheme?.lowercased() == "http")
                return
            }
        }
        guard address == serverAddress else { return }
        reachability = .unreachable
    }

    // Any HTTP response (even 401/404) means the host is up; only a transport
    // failure — refused connection, TLS mismatch, timeout — counts as unreachable.
    private static func hostResponds(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        do {
            _ = try await probeSession.data(for: request)
            return true
        } catch {
            return false
        }
    }

    func connect(using appState: AppState) async {
        guard !isConnecting, let kind = selectedBackend else { return }
        serverError = nil
        credentialsError = nil

        let candidates = SubsonicConfig.candidateURLs(from: serverAddress)
        guard !candidates.isEmpty else {
            failServer()
            return
        }

        isConnecting = true
        defer { isConnecting = false }

        do {
            let config = try await probe(candidates: candidates, kind: kind) {
                SubsonicConfig(baseURL: $0, username: username, password: password)
            }
            warnIfInsecureFallback(config.baseURL)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            appState.completeLogin(config: config, kind: kind)
        } catch ProbeFailure.authFailure {
            failCredentials()
        } catch ProbeFailure.unreachable(let error) {
            failServer(message: error?.errorDescription)
        } catch {
            failServer()
        }
    }

    private enum ProbeFailure: Error {
        case authFailure
        case unreachable(SubsonicError?)
    }

    // Validates credentials against each candidate server root in priority order,
    // returning the first that connects. An auth failure means a server *was*
    // reached, so we stop probing instead of falling back to another scheme.
    private func probe(
        candidates: [URL],
        kind: MusicBackendKind,
        makeConfig: (URL) -> SubsonicConfig
    ) async throws -> SubsonicConfig {
        var lastError: SubsonicError?
        for url in candidates {
            let config = makeConfig(url)
            do {
                try await AuthService.validate(config: config, kind: kind, session: Self.probeSession)
                return config
            } catch let error as SubsonicError {
                if error.isAuthFailure { throw ProbeFailure.authFailure }
                lastError = error
            } catch {
                lastError = nil
            }
        }
        throw ProbeFailure.unreachable(lastError)
    }

    // When the user gave no scheme and we ended up connecting over http, surface
    // a one-off warning. Explicit http:// is already warned about before connecting.
    private func warnIfInsecureFallback(_ url: URL) {
        guard url.scheme?.lowercased() == "http",
              !SubsonicConfig.hasExplicitScheme(serverAddress) else { return }
        VoltaNotificationCenter.shared.post(L(.http_warning_title), tone: .warning)
    }

    func signInWithPlex(using appState: AppState, openAuthURL: @escaping (URL) -> Void) async {
        guard canStartPlexHostedSignIn else { return }
        serverError = nil
        credentialsError = nil

        let candidates = SubsonicConfig.candidateURLs(from: serverAddress)
        guard !candidates.isEmpty else {
            failServer()
            return
        }

        isPlexHostedSigningIn = true
        defer { isPlexHostedSigningIn = false }

        do {
            let authSession = try await PlexHostedAuth.start()
            openAuthURL(authSession.authURL)
            VoltaNotificationCenter.shared.post(L(.plex_finish_sign_in), tone: .info)

            let token = try await PlexHostedAuth.waitForToken(session: authSession)
            isConnecting = true
            defer { isConnecting = false }
            let config = try await probe(candidates: candidates, kind: .plex) {
                SubsonicConfig(baseURL: $0, username: "Plex", password: token)
            }
            warnIfInsecureFallback(config.baseURL)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            appState.completeLogin(config: config, kind: .plex)
        } catch PlexHostedAuth.AuthError.timedOut {
            failCredentials(message: L(.error_plex_timeout))
        } catch ProbeFailure.authFailure {
            failCredentials()
        } catch ProbeFailure.unreachable(let error) {
            failServer(message: error?.errorDescription)
        } catch {
            failCredentials(message: L(.error_plex_failed))
        }
    }

    private func failServer(message: String? = nil) {
        let text = message ?? L(.error_unreachable)
        serverError = text
        serverShake += 1
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        VoltaNotificationCenter.shared.post(text, tone: .error)
    }

    private func failCredentials(message: String? = nil) {
        let text = message ?? L(.error_bad_credentials)
        credentialsError = text
        credentialsShake += 1
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        VoltaNotificationCenter.shared.post(text, tone: .error)
    }
}
