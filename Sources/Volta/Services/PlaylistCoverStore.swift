import UIKit

extension Notification.Name {
    // posted (object = playlist id) whenever a custom cover is set or removed
    static let playlistCoverChanged = Notification.Name("PlaylistCoverChanged")
}

// Subsonic has no endpoint to upload a playlist cover, so user-chosen covers are
// kept on-device, keyed by playlist id, with a small in-memory cache over disk.
final class PlaylistCoverStore: @unchecked Sendable {
    static let shared = PlaylistCoverStore()

    private let dir: URL
    private let cache = NSCache<NSString, UIImage>()
    private let io = DispatchQueue(label: "com.volta.playlist-covers", qos: .utility)

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("Volta/PlaylistCovers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func fileURL(_ id: String) -> URL {
        let safe = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
        return dir.appendingPathComponent(safe).appendingPathExtension("jpg")
    }

    // synchronous mem-cache hit only — cheap, safe to call during a view's init
    func cachedImage(for id: String) -> UIImage? { cache.object(forKey: id as NSString) }

    // a single filesystem stat; call once (e.g. on appear), not every render
    func hasCover(for id: String) -> Bool {
        cache.object(forKey: id as NSString) != nil
            || FileManager.default.fileExists(atPath: fileURL(id).path)
    }

    // mem cache, then disk read off the main thread
    func image(for id: String) async -> UIImage? {
        if let hit = cache.object(forKey: id as NSString) { return hit }
        return await withCheckedContinuation { cont in
            io.async {
                guard let data = try? Data(contentsOf: self.fileURL(id)),
                      let img = UIImage(data: data) else {
                    cont.resume(returning: nil); return
                }
                self.cache.setObject(img, forKey: id as NSString)
                cont.resume(returning: img)
            }
        }
    }

    func set(_ image: UIImage, for id: String) {
        cache.setObject(image, forKey: id as NSString)
        let url = fileURL(id)
        io.async {
            let scaled = Self.downscaled(image, maxDimension: 1000)
            if let data = scaled.jpegData(compressionQuality: 0.9) {
                try? data.write(to: url, options: .atomic)
            }
        }
        NotificationCenter.default.post(name: .playlistCoverChanged, object: id)
    }

    func remove(for id: String) {
        cache.removeObject(forKey: id as NSString)
        let url = fileURL(id)
        io.async { try? FileManager.default.removeItem(at: url) }
        NotificationCenter.default.post(name: .playlistCoverChanged, object: id)
    }

    // keep stored covers a sensible size — full-res camera shots are wasteful
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
