import Foundation
import UIKit

// two-tier artwork cache: in-memory NSCache for the current session and a disk
// cache under Caches so artwork survives launches without refetching.
actor ArtworkLoader {
    static let shared = ArtworkLoader()

    private let memory = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let session: URLSession
    private let directory: URL
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
        memory.countLimit = 500
        memory.totalCostLimit = 256 * 1024 * 1024 // ~256 MB of decoded pixels

        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("artwork", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func image(for url: URL?) async -> UIImage? {
        guard let url else { return nil }
        let key = Crypto.md5Hex(url.absoluteString)

        if let cached = memory.object(forKey: key as NSString) {
            return cached
        }
        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> { [directory, session] in
            let fileURL = directory.appendingPathComponent(key)
            // disk hit: decode + force-prepare off the main thread to avoid
            // first-display jank during scroll.
            if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
                return image.preparingForDisplay() ?? image
            }
            guard let (data, _) = try? await session.data(from: url),
                  let image = UIImage(data: data) else {
                return nil
            }
            try? data.write(to: fileURL, options: .atomic)
            return image.preparingForDisplay() ?? image
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            memory.setObject(image, forKey: key as NSString, cost: image.cost)
        }
        return image
    }

    // wipes the in-memory and on-disk artwork caches; images re-fetch on demand.
    func clearCache() {
        memory.removeAllObjects()
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

private extension UIImage {
    // approx decoded byte size (w·h·scale²·4) for NSCache cost accounting.
    var cost: Int {
        let s = scale * scale
        return Int(size.width * size.height * s * 4)
    }
}
