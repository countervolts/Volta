import Foundation
import Security

// minimal keychain wrapper for server passwords. keyed by server id.
enum KeychainService {
    private static let service = "com.ayo.music.credentials"
    private static func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
    }

    @discardableResult
    static func save(password: String, for account: String) -> Bool {
        let data = Data(password.utf8)
        SecItemDelete(baseQuery(for: account) as CFDictionary)

        var attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        attributes[kSecAttrSynchronizable as String] = true
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func password(for account: String) -> String? {
        var query = baseQuery(for: account)
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
    static func delete(for account: String) -> Bool {
        SecItemDelete(baseQuery(for: account) as CFDictionary) == errSecSuccess
    }
}
