import UIKit

extension Notification.Name {
    // posted (object = playlist id) whenever a custom cover is set or removed
    static let playlistCoverChanged = Notification.Name("PlaylistCoverChanged")
}

// Local playlist covers; Subsonic has no upload endpoint for them.
final class PlaylistCoverStore: @unchecked Sendable {
    static let shared = PlaylistCoverStore()

    private let dir: URL
    private let cache = NSCache<NSString, UIImage>()
    private let io = DeveloperExperiments.queue(label: "com.volta.playlist-covers", qos: .utility)

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("Volta/PlaylistCovers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func fileURL(_ id: String) -> URL {
        let safe = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
        return dir.appendingPathComponent(safe).appendingPathExtension("jpg")
    }

    // Sync memory hit only; safe during view init.
    func cachedImage(for id: String) -> UIImage? { cache.object(forKey: id as NSString) }

    // One filesystem stat; call from lifecycle, not every render.
    func hasCover(for id: String) -> Bool {
        cache.object(forKey: id as NSString) != nil
            || FileManager.default.fileExists(atPath: fileURL(id).path)
    }

    // Memory first, then disk off the main thread.
    func image(for id: String) async -> UIImage? {
        if let hit = cache.object(forKey: id as NSString) { return hit }
        return await DeveloperExperiments.runBlocking(qos: .utility) {
            guard let data = try? Data(contentsOf: self.fileURL(id)),
                  let img = UIImage(data: data) else { return nil }
            self.cache.setObject(img, forKey: id as NSString)
            return img
        }
    }

    func set(_ image: UIImage, for id: String) {
        cache.setObject(image, forKey: id as NSString)
        let url = fileURL(id)
        runIO {
            let scaled = DeveloperExperiments.disableRAMOptimizations
                ? image
                : Self.downscaled(image, maxDimension: 1000)
            if let data = scaled.jpegData(compressionQuality: 0.9) {
                try? data.write(to: url, options: .atomic)
            }
        }
        NotificationCenter.default.post(name: .playlistCoverChanged, object: id)
    }

    func remove(for id: String) {
        cache.removeObject(forKey: id as NSString)
        let url = fileURL(id)
        runIO { try? FileManager.default.removeItem(at: url) }
        NotificationCenter.default.post(name: .playlistCoverChanged, object: id)
    }

    private func runIO(_ operation: @escaping () -> Void) {
        io.async(execute: operation)
    }

    // Keep camera-roll covers reasonably sized.
    private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: newSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
