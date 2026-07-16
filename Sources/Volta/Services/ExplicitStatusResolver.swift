import AVFoundation
import Foundation

// Resolves content-advisory metadata when a server omits OpenSubsonic's
// explicitStatus field. AVURLAsset only loads the metadata atoms/frames; it
// does not decode the track's audio. Results are cached for the app session.
actor ExplicitStatusResolver {
    static let shared = ExplicitStatusResolver()

    private enum Result {
        case explicit
        case notExplicit
        case unavailable

        var boolValue: Bool? {
            switch self {
            case .explicit: true
            case .notExplicit: false
            case .unavailable: nil
            }
        }
    }

    private var cache: [String: Result] = [:]

    func isExplicit(
        songID: String,
        localURL: URL?,
        remoteURL: URL?,
        requestHeaders: [String: String]
    ) async -> Bool? {
        if let cached = cache[songID] { return cached.boolValue }
        guard let url = localURL ?? remoteURL else {
            cache[songID] = .unavailable
            return nil
        }

        let options: [String: Any]? = requestHeaders.isEmpty
            ? nil
            : ["AVURLAssetHTTPHeaderFieldsKey": requestHeaders]
        let asset = AVURLAsset(url: url, options: options)
        let metadata = (try? await asset.load(.metadata)) ?? []

        for item in metadata {
            let extraAttributes = (try? await item.load(.extraAttributes)).map { "\($0)" }
            let keyText = [
                item.identifier?.rawValue,
                item.commonKey?.rawValue,
                item.keySpace?.rawValue,
                item.key.map { "\($0)" },
                extraAttributes
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

            guard Self.isContentAdvisoryKey(keyText) else { continue }

            if let number = try? await item.load(.numberValue),
               let result = Self.result(for: number.stringValue) {
                cache[songID] = result
                return result.boolValue
            }
            if let text = try? await item.load(.stringValue),
               let result = Self.result(for: text) {
                cache[songID] = result
                return result.boolValue
            }
        }

        cache[songID] = .unavailable
        return nil
    }

    private static func isContentAdvisoryKey(_ keyText: String) -> Bool {
        keyText.contains("itunesadvisory")
            || keyText.contains("contentadvisory")
            || keyText.contains("explicitstatus")
            || keyText.contains("rtng")
            || keyText.contains("explicit")
    }

    private static func result(for rawValue: String) -> Result? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["1", "4", "explicit", "e", "true", "yes"].contains(value) { return .explicit }
        if ["2", "clean", "c", "false", "no"].contains(value) { return .notExplicit }
        return nil
    }
}
