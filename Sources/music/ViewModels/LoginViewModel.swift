import Foundation
import Observation

@MainActor
@Observable
final class LoginViewModel {
    var serverAddress = ""
    var username = ""
    var password = ""

    private(set) var isConnecting = false
    private(set) var serverError: String?
    private(set) var credentialsError: String?

    // incremented to retrigger the shake animation on the relevant fields.
    private(set) var serverShake = 0
    private(set) var credentialsShake = 0

    var canSubmit: Bool {
        !serverAddress.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty &&
        !isConnecting
    }

    var usesInsecureHTTP: Bool {
        SubsonicConfig.normalizedURL(from: serverAddress)?.scheme?.lowercased() == "http"
    }

    func connect(using appState: AppState) async {
        guard !isConnecting else { return }
        serverError = nil
        credentialsError = nil

        guard let url = SubsonicConfig.normalizedURL(from: serverAddress) else {
            failServer()
            return
        }

        let config = SubsonicConfig(baseURL: url, username: username, password: password)
        isConnecting = true
        defer { isConnecting = false }

        do {
            try await AuthService.validate(config: config)
            appState.completeLogin(config: config)
        } catch let error as SubsonicError {
            if error.isAuthFailure {
                failCredentials()
            } else {
                failServer()
            }
        } catch {
            failServer()
        }
    }

    private func failServer() {
        serverError = "Could not reach the server."
        serverShake += 1
    }

    private func failCredentials() {
        credentialsError = "Incorrect username or password."
        credentialsShake += 1
    }
}
