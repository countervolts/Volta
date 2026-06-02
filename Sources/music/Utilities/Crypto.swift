import Foundation
import CryptoKit

enum Crypto {
    // subsonic token auth: token = md5(password + salt)
    static func subsonicToken(password: String, salt: String) -> String {
        md5Hex(password + salt)
    }

    static func randomSalt(length: Int = 12) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        var salt = ""
        for _ in 0..<length {
            salt.append(chars.randomElement() ?? "x")
        }
        return salt
    }

    static func md5Hex(_ input: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
