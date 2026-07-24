import CryptoKit
import DeviceCheck
import Foundation
import Security

struct GlobalLibraryStatsData: Hashable, Codable {
    struct Totals: Hashable, Codable {
        let libraryCount: Int
        let songCount: Int
        let albumCount: Int
        let durationSeconds: Int
        let librarySizeBytes: Int
    }

    struct Records: Hashable, Codable {
        struct BiggestLibrary: Hashable, Codable {
            let songCount: Int
            let albumCount: Int
            let durationSeconds: Int
            let librarySizeBytes: Int
        }

        let highestListeningTimeSeconds: Int
        let highestSongCount: Int
        let highestAlbumCount: Int
        let highestLibrarySizeBytes: Int
        let biggestLibrary: BiggestLibrary
    }

    struct Averages: Hashable, Codable {
        let songCount: Double
        let albumCount: Double
        let durationSeconds: Double
        let librarySizeBytes: Double
    }

    let totals: Totals
    let records: Records
    let averages: Averages
    let generatedAt: Date
}

enum GlobalLibraryStatsService {
    static let optInKey = "globalLibraryStatsOptIn"

    private static let endpoint = URL(string: "https://stats-api.marshes-airy-5.workers.dev")!
    private static let keychainService = "com.ayo.music.global-library-stats"
    private static let installIDAccount = "globalLibraryStats.anonymousInstallID"
    private static let appAttestKeyIDAccount = "globalLibraryStats.appAttestKeyID"
    private static let appAttestRegisteredKeyIDAccount = "globalLibraryStats.appAttestRegisteredKeyID"
    private static let appAttestAuthorizer = AppAttestAuthorizer(endpoint: endpoint)

    static var isOptedIn: Bool {
        UserDefaults.standard.bool(forKey: optInKey)
    }

    static func setOptedIn(_ optedIn: Bool) {
        UserDefaults.standard.set(optedIn, forKey: optInKey)
    }

    static func fetchGlobalStats() async throws -> GlobalLibraryStatsData {
        var request = URLRequest(url: endpoint.appendingPathComponent("stats/global"))
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response)
        return try decoder.decode(GlobalLibraryStatsData.self, from: data)
    }

    static func submit(stats: LibraryStatsData) async throws -> GlobalLibraryStatsData {
        _ = try await appAttestAuthorizer.sendAuthorized(
            path: "/stats/me",
            method: "PUT"
        ) { challenge in
            Submission(
                stats: stats,
                anonymousId: anonymousInstallID(),
                challenge: challenge
            )
        }
        return try await fetchGlobalStats()
    }

    @discardableResult
    static func deleteSharedStats() async throws -> Bool {
        let data = try await appAttestAuthorizer.sendAuthorized(
            path: "/stats/me",
            method: "DELETE"
        ) { challenge in
            DeleteRequest(anonymousId: anonymousInstallID(), challenge: challenge)
        }
        return (try? JSONDecoder().decode(DeleteResponse.self, from: data).deleted) ?? false
    }

    private static func anonymousInstallID() -> String {
        if let existing = keychainString(for: installIDAccount), !existing.isEmpty {
            return existing
        }

        let id = UUID().uuidString + "-" + UUID().uuidString
        saveKeychainString(id, for: installIDAccount)
        return id
    }

    private static func keychainString(for account: String) -> String? {
        var query = baseKeychainQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private static func saveKeychainString(_ value: String, for account: String) -> Bool {
        SecItemDelete(baseKeychainQuery(for: account) as CFDictionary)

        var attributes = baseKeychainQuery(for: account)
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    private static func baseKeychainQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
    }

    private static func deleteKeychainValue(for account: String) {
        SecItemDelete(baseKeychainQuery(for: account) as CFDictionary)
    }

    private static func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(
                domain: "GlobalLibraryStats",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Stats service returned \(http.statusCode)."]
            )
        }
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = iso8601WithFractionalSeconds.date(from: value) ?? iso8601.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date.")
        }
        return decoder
    }

    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601 = ISO8601DateFormatter()

    private actor AppAttestAuthorizer {
        private let endpoint: URL
        private let service = DCAppAttestService.shared
        private let encoder = JSONEncoder()
        private let session = URLSession.shared

        init(endpoint: URL) {
            self.endpoint = endpoint
        }

        func sendAuthorized<Body: Encodable>(
            path: String,
            method: String,
            makeBody: (String) -> Body
        ) async throws -> Data {
            guard service.isSupported else {
                throw AppAttestClientError.unsupported
            }

            for attempt in 0..<2 {
                let keyID = try await registeredKeyID()

                do {
                    let challenge = try await requestChallenge(
                        purpose: "assertion",
                        keyID: keyID,
                        method: method,
                        path: path
                    )
                    let body = try encoder.encode(makeBody(challenge))
                    let clientDataHash = Data(SHA256.hash(data: body))
                    let assertion = try await service.generateAssertion(
                        keyID,
                        clientDataHash: clientDataHash
                    )

                    var request = URLRequest(url: url(for: path))
                    request.httpMethod = method
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    request.setValue(keyID, forHTTPHeaderField: "x-volta-app-attest-key-id")
                    request.setValue(
                        assertion.base64EncodedString(),
                        forHTTPHeaderField: "x-volta-app-attest-assertion"
                    )
                    request.httpBody = body

                    let (data, response) = try await session.data(for: request)
                    if isSuccessful(response) {
                        return data
                    }

                    let serverCode = apiErrorCode(from: data)
                    if attempt == 0, shouldReplaceKey(status: statusCode(response), code: serverCode) {
                        clearAttestationKey()
                        continue
                    }

                    throw AppAttestClientError.server(status: statusCode(response), code: serverCode)
                } catch {
                    if attempt == 0, shouldRetryWithFreshKey(after: error) {
                        clearAttestationKey()
                        continue
                    }
                    throw error
                }
            }

            throw AppAttestClientError.registrationFailed
        }

        private func registeredKeyID() async throws -> String {
            if let keyID = GlobalLibraryStatsService.keychainString(for: appAttestKeyIDAccount),
               let registeredKeyID = GlobalLibraryStatsService.keychainString(
                   for: appAttestRegisteredKeyIDAccount
               ),
               keyID == registeredKeyID {
                return keyID
            }

            for attempt in 0..<2 {
                let keyID: String
                if let existing = GlobalLibraryStatsService.keychainString(for: appAttestKeyIDAccount),
                   !existing.isEmpty {
                    keyID = existing
                } else {
                    keyID = try await service.generateKey()
                    guard GlobalLibraryStatsService.saveKeychainString(
                        keyID,
                        for: appAttestKeyIDAccount
                    ) else {
                        throw AppAttestClientError.keyStorageFailed
                    }
                }

                do {
                    try await register(keyID: keyID)
                    guard GlobalLibraryStatsService.saveKeychainString(
                        keyID,
                        for: appAttestRegisteredKeyIDAccount
                    ) else {
                        throw AppAttestClientError.keyStorageFailed
                    }
                    return keyID
                } catch {
                    if attempt == 0, shouldRetryWithFreshKey(after: error) {
                        clearAttestationKey()
                        continue
                    }
                    throw error
                }
            }

            throw AppAttestClientError.registrationFailed
        }

        private func register(keyID: String) async throws {
            let challenge = try await requestChallenge(
                purpose: "attestation",
                keyID: keyID,
                method: nil,
                path: nil
            )
            let clientDataHash = Data(SHA256.hash(data: Data(challenge.utf8)))
            let attestation = try await service.attestKey(
                keyID,
                clientDataHash: clientDataHash
            )
            let body = try encoder.encode(
                RegistrationRequest(
                    keyId: keyID,
                    challenge: challenge,
                    attestation: attestation.base64EncodedString()
                )
            )

            var request = URLRequest(url: url(for: "/attest/register"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = body

            let (data, response) = try await session.data(for: request)
            guard isSuccessful(response) else {
                throw AppAttestClientError.server(
                    status: statusCode(response),
                    code: apiErrorCode(from: data)
                )
            }
        }

        private func requestChallenge(
            purpose: String,
            keyID: String,
            method: String?,
            path: String?
        ) async throws -> String {
            var request = URLRequest(url: url(for: "/attest/challenge"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try encoder.encode(
                ChallengeRequest(
                    purpose: purpose,
                    keyId: keyID,
                    method: method,
                    path: path
                )
            )

            let (data, response) = try await session.data(for: request)
            guard isSuccessful(response) else {
                throw AppAttestClientError.server(
                    status: statusCode(response),
                    code: apiErrorCode(from: data)
                )
            }

            guard let challenge = try? JSONDecoder().decode(
                ChallengeResponse.self,
                from: data
            ).challenge, !challenge.isEmpty else {
                throw AppAttestClientError.invalidResponse
            }
            return challenge
        }

        private func clearAttestationKey() {
            GlobalLibraryStatsService.deleteKeychainValue(for: appAttestKeyIDAccount)
            GlobalLibraryStatsService.deleteKeychainValue(for: appAttestRegisteredKeyIDAccount)
        }

        private func url(for path: String) -> URL {
            endpoint.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        }

        private func isSuccessful(_ response: URLResponse) -> Bool {
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        }

        private func statusCode(_ response: URLResponse) -> Int {
            (response as? HTTPURLResponse)?.statusCode ?? -1
        }

        private func apiErrorCode(from data: Data) -> String? {
            try? JSONDecoder().decode(APIErrorResponse.self, from: data).error
        }

        private func shouldReplaceKey(status: Int, code: String?) -> Bool {
            guard status == 401 else { return false }
            return [
                "app_attest_registration_required",
                "invalid_app_attestation",
                "invalid_app_assertion",
                "replayed_app_assertion",
            ].contains(code)
        }

        private func shouldRetryWithFreshKey(after error: Error) -> Bool {
            if isInvalidKey(error) { return true }
            if case let AppAttestClientError.server(status, code) = error {
                return shouldReplaceKey(status: status, code: code)
            }
            return false
        }

        private func isInvalidKey(_ error: Error) -> Bool {
            let nsError = error as NSError
            return nsError.domain == DCErrorDomain && nsError.code == DCError.invalidKey.rawValue
        }
    }

    private struct Submission: Encodable {
        let challenge: String
        let anonymousId: String
        let songCount: Int
        let albumCount: Int
        let durationSeconds: Int
        let librarySizeBytes: Int
        let appVersion: String

        init(stats: LibraryStatsData, anonymousId: String, challenge: String) {
            self.challenge = challenge
            self.anonymousId = anonymousId
            songCount = stats.totalSongs
            albumCount = stats.totalAlbums
            durationSeconds = stats.totalSeconds
            librarySizeBytes = stats.totalSize
            appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        }
    }

    private struct DeleteRequest: Encodable {
        let anonymousId: String
        let challenge: String
    }

    private struct DeleteResponse: Decodable {
        let deleted: Bool
    }

    private struct ChallengeRequest: Encodable {
        let purpose: String
        let keyId: String
        let method: String?
        let path: String?
    }

    private struct ChallengeResponse: Decodable {
        let challenge: String
    }

    private struct RegistrationRequest: Encodable {
        let keyId: String
        let challenge: String
        let attestation: String
    }

    private struct APIErrorResponse: Decodable {
        let error: String
    }

    private enum AppAttestClientError: LocalizedError {
        case unsupported
        case keyStorageFailed
        case invalidResponse
        case registrationFailed
        case server(status: Int, code: String?)

        var errorDescription: String? {
            switch self {
            case .unsupported:
                return "This device cannot securely share global stats."
            case .keyStorageFailed:
                return "Volta could not securely store its stats identity."
            case .invalidResponse:
                return "The stats service returned an invalid security response."
            case .registrationFailed:
                return "Volta could not verify this app installation."
            case let .server(status, code):
                let detail = code.map { " (\($0))" } ?? ""
                return "Stats service returned \(status)\(detail)."
            }
        }
    }
}
