import Foundation
import UIKit
import Combine

@MainActor
final class LoginViewModel: ObservableObject {
    // Server-address preflight state.
    enum ServerReachability: Equatable {
        case idle
        case checking
        case reachable(insecure: Bool)
        case unreachable
    }

    enum ConnectionResult: Equatable {
        case completed
        case needsInsecureHTTPConfirmation
    }

    // nil while choosing a service.
    @Published var selectedBackend: MusicBackendKind?

    @Published var serverAddress = ""
    @Published var username = ""
    @Published var password = ""

    @Published private(set) var isConnecting = false
    @Published private(set) var isPlexHostedSigningIn = false
    @Published private(set) var serverError: String?
    @Published private(set) var credentialsError: String?
    @Published private(set) var didCompleteLogin = false

    @Published private(set) var reachability: ServerReachability = .idle
    private var reachabilityTask: Task<Void, Never>?
    private var pendingPlexHostedToken: String?

    // incremented to retrigger the shake animation on the relevant fields.
    @Published private(set) var serverShake = 0
    @Published private(set) var credentialsShake = 0

    // Short, uncached session for login probes.
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
        pendingPlexHostedToken = nil
    }

    func deselect() {
        selectedBackend = nil
        serverError = nil
        credentialsError = nil
        reachabilityTask?.cancel()
        reachability = .idle
        pendingPlexHostedToken = nil
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
        pendingPlexHostedToken = nil
        let address = serverAddress
        let candidates = SubsonicConfig.candidateURLs(from: address, kind: selectedBackend)
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

    // Any HTTP response means the host is reachable.
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

    @discardableResult
    func connect(using appState: AppState, allowInsecureHTTP: Bool = false) async -> ConnectionResult {
        guard !isConnecting, let kind = selectedBackend else { return .completed }
        didCompleteLogin = false
        serverError = nil
        credentialsError = nil

        let address = serverAddress
        let candidates = SubsonicConfig.candidateURLs(from: serverAddress, kind: kind)
        guard !candidates.isEmpty else {
            failServer()
            return .completed
        }
        guard !needsImmediateInsecureHTTPConfirmation(candidates: candidates, allowInsecureHTTP: allowInsecureHTTP) else {
            return .needsInsecureHTTPConfirmation
        }
        let credentialCandidates = candidatesForCredentialProbe(candidates, allowInsecureHTTP: allowInsecureHTTP)
        guard !credentialCandidates.isEmpty else {
            failServer()
            return .completed
        }

        isConnecting = true
        defer { isConnecting = false }

        do {
            let config = try await probe(candidates: credentialCandidates, kind: kind) {
                SubsonicConfig(baseURL: $0, username: username, password: password)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            appState.completeLogin(config: config, kind: kind)
            didCompleteLogin = true
            return .completed
        } catch ProbeFailure.authFailure {
            failCredentials()
            return .completed
        } catch ProbeFailure.unreachable(let error) {
            if await shouldOfferInsecureHTTPFallback(candidates: candidates, address: address, allowInsecureHTTP: allowInsecureHTTP) {
                return .needsInsecureHTTPConfirmation
            }
            failServer(message: error?.errorDescription)
            return .completed
        } catch {
            failServer()
            return .completed
        }
    }

    private enum ProbeFailure: Error {
        case authFailure
        case unreachable(SubsonicError?)
    }

    // Try candidate roots in order; auth failure stops the search.
    private func probe(
        candidates: [URL],
        kind: MusicBackendKind,
        makeConfig: (URL) -> SubsonicConfig
    ) async throws -> SubsonicConfig {
        var lastError: SubsonicError?
        for url in candidates {
            let config = makeConfig(url)
            do {
                return try await AuthService.validate(config: config, kind: kind, session: Self.probeSession)
            } catch let error as SubsonicError {
                if error.isAuthFailure { throw ProbeFailure.authFailure }
                lastError = error
            } catch {
                lastError = nil
            }
        }
        throw ProbeFailure.unreachable(lastError)
    }

    private func candidatesForCredentialProbe(_ candidates: [URL], allowInsecureHTTP: Bool) -> [URL] {
        guard !allowInsecureHTTP,
              !SubsonicConfig.hasExplicitScheme(serverAddress) else {
            return candidates
        }
        return candidates.filter { $0.scheme?.lowercased() != "http" }
    }

    private func needsImmediateInsecureHTTPConfirmation(candidates: [URL], allowInsecureHTTP: Bool) -> Bool {
        !allowInsecureHTTP
            && SubsonicConfig.hasExplicitScheme(serverAddress)
            && candidates.contains { $0.scheme?.lowercased() == "http" }
    }

    private func shouldOfferInsecureHTTPFallback(
        candidates: [URL],
        address: String,
        allowInsecureHTTP: Bool
    ) async -> Bool {
        guard !allowInsecureHTTP,
              !SubsonicConfig.hasExplicitScheme(address),
              address == serverAddress else {
            return false
        }
        for httpURL in candidates where httpURL.scheme?.lowercased() == "http" {
            guard address == serverAddress else { return false }
            if await Self.hostResponds(httpURL) {
                guard address == serverAddress else { return false }
                reachability = .reachable(insecure: true)
                return true
            }
        }
        return false
    }

    func cancelInsecureHTTPContinuation() {
        pendingPlexHostedToken = nil
    }

    @discardableResult
    func signInWithPlex(
        using appState: AppState,
        allowInsecureHTTP: Bool = false,
        openAuthURL: @escaping (URL) -> Void
    ) async -> ConnectionResult {
        guard canStartPlexHostedSignIn || pendingPlexHostedToken != nil else { return .completed }
        didCompleteLogin = false
        serverError = nil
        credentialsError = nil

        let address = serverAddress
        let candidates = SubsonicConfig.candidateURLs(from: serverAddress, kind: .plex)
        guard !candidates.isEmpty else {
            failServer()
            return .completed
        }
        guard !needsImmediateInsecureHTTPConfirmation(candidates: candidates, allowInsecureHTTP: allowInsecureHTTP) else {
            return .needsInsecureHTTPConfirmation
        }
        let credentialCandidates = candidatesForCredentialProbe(candidates, allowInsecureHTTP: allowInsecureHTTP)
        guard !credentialCandidates.isEmpty else {
            failServer()
            return .completed
        }

        isPlexHostedSigningIn = true
        defer { isPlexHostedSigningIn = false }

        do {
            let token: String
            if let pendingPlexHostedToken {
                token = pendingPlexHostedToken
            } else {
                let authSession = try await PlexHostedAuth.start()
                openAuthURL(authSession.authURL)
                VoltaNotificationCenter.shared.post(L(.plex_finish_sign_in), tone: .info)
                token = try await PlexHostedAuth.waitForToken(session: authSession)
                pendingPlexHostedToken = token
            }

            isConnecting = true
            defer { isConnecting = false }
            let config = try await probe(candidates: credentialCandidates, kind: .plex) {
                SubsonicConfig(baseURL: $0, username: PlexClient.tokenUsername, password: token)
            }
            pendingPlexHostedToken = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            appState.completeLogin(config: config, kind: .plex)
            didCompleteLogin = true
            return .completed
        } catch PlexHostedAuth.AuthError.timedOut {
            pendingPlexHostedToken = nil
            failCredentials(message: L(.error_plex_timeout))
            return .completed
        } catch ProbeFailure.authFailure {
            pendingPlexHostedToken = nil
            failCredentials()
            return .completed
        } catch ProbeFailure.unreachable(let error) {
            if await shouldOfferInsecureHTTPFallback(candidates: candidates, address: address, allowInsecureHTTP: allowInsecureHTTP) {
                return .needsInsecureHTTPConfirmation
            }
            pendingPlexHostedToken = nil
            failServer(message: error?.errorDescription)
            return .completed
        } catch {
            pendingPlexHostedToken = nil
            failCredentials(message: L(.error_plex_failed))
            return .completed
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
