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

    private struct PlexConnectionAttempt {
        let serverName: String
        let url: URL
        let token: String
        let connections: [PlexConnectionEndpoint]
    }

    private struct ResolvedPlexServer {
        let name: String
        let config: SubsonicConfig
    }

    private enum PlexConnectionFailure: Error {
        case noServers
        case accessDenied
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
        let hasManualAddress = !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let manualCandidates = hasManualAddress
            ? SubsonicConfig.candidateURLs(from: address, kind: .plex)
            : []
        if hasManualAddress {
            guard !manualCandidates.isEmpty else {
                failServer()
                return .completed
            }
            guard !needsImmediateInsecureHTTPConfirmation(
                candidates: manualCandidates,
                allowInsecureHTTP: allowInsecureHTTP
            ) else {
                return .needsInsecureHTTPConfirmation
            }
        }

        isPlexHostedSigningIn = true
        defer { isPlexHostedSigningIn = false }

        do {
            let accountToken: String
            if let pendingPlexHostedToken {
                accountToken = pendingPlexHostedToken
            } else {
                let authSession = try await PlexHostedAuth.start()
                openAuthURL(authSession.authURL)
                VoltaNotificationCenter.shared.post(L(.plex_finish_sign_in), tone: .info)
                accountToken = try await PlexHostedAuth.waitForToken(session: authSession)
                pendingPlexHostedToken = accountToken
            }

            let resources = try await PlexHostedAuth.servers(
                forAccountToken: accountToken,
                session: Self.probeSession
            )
            guard !resources.isEmpty else { throw PlexConnectionFailure.noServers }

            isConnecting = true
            defer { isConnecting = false }
            let resolved: ResolvedPlexServer
            do {
                resolved = try await connectToPlexServer(
                    resources: resources,
                    manualCandidates: manualCandidates,
                    allowInsecureHTTP: allowInsecureHTTP
                )
            } catch PlexConnectionFailure.unreachable(let error) {
                if await shouldOfferInsecurePlexFallback(
                    resources: resources,
                    manualCandidates: manualCandidates,
                    address: address,
                    allowInsecureHTTP: allowInsecureHTTP
                ) {
                    return .needsInsecureHTTPConfirmation
                }
                throw PlexConnectionFailure.unreachable(error)
            }

            pendingPlexHostedToken = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            appState.completeLogin(config: resolved.config, kind: .plex, displayName: resolved.name)
            didCompleteLogin = true
            return .completed
        } catch PlexHostedAuth.AuthError.timedOut {
            pendingPlexHostedToken = nil
            failCredentials(message: L(.error_plex_timeout))
            return .completed
        } catch PlexConnectionFailure.noServers {
            pendingPlexHostedToken = nil
            failServer(message: L(.error_plex_no_servers))
            return .completed
        } catch PlexConnectionFailure.accessDenied {
            pendingPlexHostedToken = nil
            failServer(message: L(.error_plex_access_denied))
            return .completed
        } catch PlexConnectionFailure.unreachable(let error) {
            pendingPlexHostedToken = nil
            failServer(message: error?.errorDescription)
            return .completed
        } catch let error as SubsonicError {
            pendingPlexHostedToken = nil
            if error.isAuthFailure {
                failCredentials(message: L(.error_plex_failed))
            } else {
                failServer(message: error.errorDescription)
            }
            return .completed
        } catch {
            pendingPlexHostedToken = nil
            failCredentials(message: L(.error_plex_failed))
            return .completed
        }
    }

    private func connectToPlexServer(
        resources: [PlexServerResource],
        manualCandidates: [URL],
        allowInsecureHTTP: Bool
    ) async throws -> ResolvedPlexServer {
        let attempts = plexConnectionAttempts(
            resources: resources,
            manualCandidates: manualCandidates,
            allowInsecureHTTP: allowInsecureHTTP
        )
        var lastError: SubsonicError?
        var sawAccessDenied = false

        for attempt in attempts {
            try Task.checkCancellation()
            let config = SubsonicConfig(
                baseURL: attempt.url,
                username: PlexClient.tokenUsername,
                password: attempt.token,
                plexConnections: attempt.connections
            )
            do {
                let validated = try await AuthService.validate(
                    config: config,
                    kind: .plex,
                    session: Self.probeSession
                )
                return ResolvedPlexServer(name: attempt.serverName, config: validated)
            } catch let error as SubsonicError {
                if error.isAuthFailure {
                    sawAccessDenied = true
                } else {
                    lastError = error
                }
            }
        }

        if let lastError { throw PlexConnectionFailure.unreachable(lastError) }
        if sawAccessDenied { throw PlexConnectionFailure.accessDenied }
        throw PlexConnectionFailure.unreachable(nil)
    }

    private func plexConnectionAttempts(
        resources: [PlexServerResource],
        manualCandidates: [URL],
        allowInsecureHTTP: Bool
    ) -> [PlexConnectionAttempt] {
        let orderedResources = resources.enumerated().sorted { lhs, rhs in
            let leftPresent = lhs.element.presence == true
            let rightPresent = rhs.element.presence == true
            return leftPresent == rightPresent ? lhs.offset < rhs.offset : leftPresent
        }.map(\.element)

        var attempts: [PlexConnectionAttempt] = []
        if manualCandidates.isEmpty {
            for resource in orderedResources {
                guard let token = resource.usableAccessToken else { continue }
                let connections = uniquePlexConnections(
                    resource.preferredConnections.compactMap(\.endpoint).filter {
                        allowInsecureHTTP || $0.url.scheme?.lowercased() != "http"
                    }
                )
                guard let connection = connections.first else { continue }
                // PlexClient cycles through this server's routes itself, so
                // validate once per server token rather than retrying the same
                // complete route list for every advertised URL.
                attempts.append(PlexConnectionAttempt(
                    serverName: resource.displayName,
                    url: connection.url,
                    token: token,
                    connections: connections
                ))
            }
        } else {
            // A manually supplied URL is an override. Try each server-specific
            // token at that URL so shared and multi-server accounts still work.
            let connections = uniquePlexConnections(manualCandidates.compactMap { url in
                guard allowInsecureHTTP || url.scheme?.lowercased() != "http" else { return nil }
                return PlexConnectionEndpoint(url: url, kind: .manual)
            })
            guard let connection = connections.first else { return [] }
            for resource in orderedResources {
                guard let token = resource.usableAccessToken else { continue }
                attempts.append(PlexConnectionAttempt(
                    serverName: resource.displayName,
                    url: connection.url,
                    token: token,
                    connections: connections
                ))
            }
        }

        var seen = Set<String>()
        return attempts.filter { attempt in
            let key = "\(attempt.url.absoluteString)|\(attempt.token)"
            guard seen.insert(key).inserted else { return false }
            return true
        }
    }

    private func uniquePlexConnections(
        _ connections: [PlexConnectionEndpoint]
    ) -> [PlexConnectionEndpoint] {
        var seen = Set<String>()
        return connections.filter { seen.insert($0.url.absoluteString).inserted }
    }

    private func shouldOfferInsecurePlexFallback(
        resources: [PlexServerResource],
        manualCandidates: [URL],
        address: String,
        allowInsecureHTTP: Bool
    ) async -> Bool {
        guard !allowInsecureHTTP, address == serverAddress else { return false }
        let insecureURLs = plexConnectionAttempts(
            resources: resources,
            manualCandidates: manualCandidates,
            allowInsecureHTTP: true
        ).flatMap(\.connections).map(\.url).filter { $0.scheme?.lowercased() == "http" }

        var seen = Set<String>()
        for url in insecureURLs where seen.insert(url.absoluteString).inserted {
            guard address == serverAddress else { return false }
            if await Self.hostResponds(url) {
                reachability = .reachable(insecure: true)
                return true
            }
        }
        return false
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
