import Foundation

// errors are split so the login screen can react differently to an unreachable
// server vs. bad credentials, per the spec.
enum SubsonicError: Error, Sendable, Equatable {
    case serverUnreachable
    case invalidCredentials
    case invalidResponse
    case server(code: Int, message: String)

    var isAuthFailure: Bool {
        switch self {
        case .invalidCredentials: return true
        case .server(let code, _): return code == 40 || code == 41 || code == 44 || code == 45
        default: return false
        }
    }
}
