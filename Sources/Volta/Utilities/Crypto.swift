import Foundation
import CryptoKit
import Security

enum Crypto {
    // subsonic token auth: token = md5(password + salt)
    static func subsonicToken(password: String, salt: String) -> String {
        md5Hex(password + salt)
    }

    static func randomSalt(length: Int = 12) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        // 256 / 62 = 4, so accept bytes 0..<248 (4 * 62) to avoid modulo bias
        let limit = (256 / chars.count) * chars.count
        var result: [Character] = []
        result.reserveCapacity(length)
        while result.count < length {
            var batch = [UInt8](repeating: 0, count: (length - result.count) * 2)
            guard SecRandomCopyBytes(kSecRandomDefault, batch.count, &batch) == errSecSuccess else { continue }
            for byte in batch where result.count < length && Int(byte) < limit {
                result.append(chars[Int(byte) % chars.count])
            }
        }
        return String(result)
    }

    static func md5Hex(_ input: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
