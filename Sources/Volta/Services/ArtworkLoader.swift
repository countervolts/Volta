import Foundation
import UIKit
import ImageIO
import AVFoundation

struct LiveArtworkAsset {
    let artworkID: String
    let animatedImage: UIImage
    let previewImage: UIImage
    let videoURL: URL?
}

actor ArtworkLoader {
    static let shared = ArtworkLoader()

    private let memory = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let session: URLSession
    private let directory: URL
    private let liveArtworkDirectory: URL
    private let pinnedDirectory: URL
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let prepareImages: Bool

    init() {
        // Performance Mode forces the lightest image profile (overrides the user pick)
        let imageMode = PerformanceMode.reduceImageQuality
            ? "conservative"
            : (UserDefaults.standard.string(forKey: "imageLoadMode") ?? "balanced")
        let cacheMode = PerformanceMode.reduceImageQuality
            ? "light"
            : (UserDefaults.standard.string(forKey: "cacheMode") ?? "balanced")

        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        config.httpMaximumConnectionsPerHost = imageMode == "fast" ? 8 : (imageMode == "conservative" ? 2 : 6)
        session = URLSession(configuration: config)
        prepareImages = imageMode != "conservative"

        memory.countLimit = cacheMode == "aggressive" ? 1000 : (cacheMode == "light" ? 200 : 500)
        let megabytes = cacheMode == "aggressive" ? 512 : (cacheMode == "light" ? 64 : 256)
        memory.totalCostLimit = megabytes * 1024 * 1024

        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("artwork", isDirectory: true)
        liveArtworkDirectory = caches.appendingPathComponent("live-artwork", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: liveArtworkDirectory, withIntermediateDirectories: true)

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        pinnedDirectory = appSupport.appendingPathComponent("Volta/OfflineArtwork", isDirectory: true)
        try? fileManager.createDirectory(at: pinnedDirectory, withIntermediateDirectories: true)
    }

    // Strip volatile Subsonic auth params so one cover maps to one cache file.
    private static func cacheKey(for url: URL) -> String {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return Crypto.md5Hex(url.absoluteString)
        }
        let volatile: Set<String> = ["u", "t", "s", "p", "v", "c", "f", "salt", "token"]
        let kept = (comps.queryItems ?? [])
            .filter { !volatile.contains($0.name) }
            .map { "\($0.name)=\($0.value ?? "")" }
            .sorted()
            .joined(separator: "&")
        comps.queryItems = nil
        return Crypto.md5Hex((comps.host ?? "") + comps.path + "?" + kept)
    }

    func image(for url: URL?, maxPixelSize: Int? = nil) async -> UIImage? {
        guard let url else { return nil }
        let rawKey = Self.cacheKey(for: url)
        let key = maxPixelSize.map { "\(rawKey)-max\($0)" } ?? rawKey

        if let cached = memory.object(forKey: key as NSString) {
            return cached
        }
        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> { [directory, pinnedDirectory, session, prepareImages] in
            let fileURL = directory.appendingPathComponent(rawKey)
            let pinnedURL = pinnedDirectory.appendingPathComponent(rawKey)
            func finish(_ data: Data) -> UIImage? {
                Self.decodeImage(from: data, maxPixelSize: maxPixelSize, prepare: prepareImages)
            }
            if let data = try? Data(contentsOf: pinnedURL), let image = finish(data) {
                return image
            }
            if let data = try? Data(contentsOf: fileURL), let image = finish(data) {
                return image
            }
            guard let (data, _) = try? await session.data(from: url),
                  let image = finish(data) else {
                return nil
            }
            try? data.write(to: fileURL, options: .atomic)
            return image
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            memory.setObject(image, forKey: key as NSString, cost: image.cost)
        }
        return image
    }

    // MARK: - Live (animated) artwork

    func animatedImage(for url: URL?) async -> UIImage? {
        await liveArtwork(for: url)?.animatedImage
    }

    func liveArtwork(for url: URL?) async -> LiveArtworkAsset? {
        guard let url else { return nil }
        let key = Self.cacheKey(for: url)
        let fileURL = directory.appendingPathComponent(key)
        let pinnedURL = pinnedDirectory.appendingPathComponent(key)

        let data: Data?
        if let d = try? Data(contentsOf: pinnedURL) {
            data = d
        } else if let d = try? Data(contentsOf: fileURL) {
            data = d
        } else if let (d, _) = try? await session.data(from: url) {
            try? d.write(to: fileURL, options: .atomic)
            data = d
        } else {
            data = nil
        }
        guard let data else { return nil }
        guard let sequence = Self.makeAnimation(from: data) else { return nil }
        let videoURL = await Self.videoAsset(
            for: sequence,
            key: key,
            directory: liveArtworkDirectory
        )
        return LiveArtworkAsset(
            artworkID: key,
            animatedImage: sequence.image,
            previewImage: sequence.frames.first ?? sequence.image,
            videoURL: videoURL
        )
    }

    private struct AnimationSequence {
        let frames: [UIImage]
        let delays: [TimeInterval]
        let image: UIImage
    }

    private nonisolated static func decodeImage(from data: Data, maxPixelSize: Int?, prepare: Bool) -> UIImage? {
        let image: UIImage?
        if let maxPixelSize, maxPixelSize > 0,
           let source = CGImageSourceCreateWithData(data as CFData, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
                .map { UIImage(cgImage: $0) }
        } else {
            image = UIImage(data: data)
        }
        guard let image else { return nil }
        return prepare ? (image.preparingForDisplay() ?? image) : image
    }

    private nonisolated static func makeAnimation(from data: Data) -> AnimationSequence? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return nil }

        var frames: [UIImage] = []
        var delays: [TimeInterval] = []
        var total: TimeInterval = 0
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            let delay = max(0.02, frameDelay(source: source, index: i))
            delays.append(delay)
            total += delay
            frames.append(UIImage(cgImage: cg))
        }
        guard frames.count > 1 else { return nil }
        if total <= 0 { total = Double(frames.count) * 0.1 }
        let image = UIImage.animatedImage(with: frames, duration: total)
            ?? UIImage.animatedImage(with: frames, duration: Double(frames.count) * 0.1)
        guard let image else { return nil }
        return AnimationSequence(frames: frames, delays: delays, image: image)
    }

    private nonisolated static func frameDelay(source: CGImageSource, index: Int) -> TimeInterval {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else { return 0.1 }
        if let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            if let t = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double, t > 0 { return t }
            if let t = gif[kCGImagePropertyGIFDelayTime] as? Double, t > 0 { return t }
        }
        if let png = props[kCGImagePropertyPNGDictionary] as? [CFString: Any] {
            if let t = png[kCGImagePropertyAPNGUnclampedDelayTime] as? Double, t > 0 { return t }
            if let t = png[kCGImagePropertyAPNGDelayTime] as? Double, t > 0 { return t }
        }
        if let webp = props[kCGImagePropertyWebPDictionary] as? [CFString: Any] {
            if let t = webp[kCGImagePropertyWebPUnclampedDelayTime] as? Double, t > 0 { return t }
            if let t = webp[kCGImagePropertyWebPDelayTime] as? Double, t > 0 { return t }
        }
        if let container = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
           let webp = container[kCGImagePropertyWebPDictionary] as? [CFString: Any],
           let info = webp[kCGImagePropertyWebPFrameInfoArray] as? [[CFString: Any]],
           info.indices.contains(index) {
            let frame = info[index]
            if let t = frame[kCGImagePropertyWebPUnclampedDelayTime] as? Double, t > 0 { return t }
            if let t = frame[kCGImagePropertyWebPDelayTime] as? Double, t > 0 { return t }
        }
        return 0.1
    }

    private nonisolated static func videoAsset(
        for sequence: AnimationSequence,
        key: String,
        directory: URL
    ) async -> URL? {
        let url = directory.appendingPathComponent(key).appendingPathExtension("mp4")
        if FileManager.default.fileExists(atPath: url.path) { return url }

        let frames = sequence.frames
        guard let first = frames.first else { return nil }
        let side = max(2, Int(max(first.size.width * first.scale, first.size.height * first.scale)))
        let size = CGSize(width: side, height: side)

        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: side,
            AVVideoHeightKey: side
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: side,
                kCVPixelBufferHeightKey as String: side
            ]
        )
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)

        let timescale: CMTimeScale = 600
        var seconds: TimeInterval = 0
        for (idx, frame) in frames.enumerated() {
            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            guard let buffer = pixelBuffer(from: frame, size: size) else { continue }
            let time = CMTime(seconds: seconds, preferredTimescale: timescale)
            adaptor.append(buffer, withPresentationTime: time)
            seconds += sequence.delays.indices.contains(idx) ? sequence.delays[idx] : 0.1
        }
        if let last = frames.last, let buffer = pixelBuffer(from: last, size: size) {
            adaptor.append(buffer, withPresentationTime: CMTime(seconds: seconds, preferredTimescale: timescale))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return writer.status == .completed ? url : nil
    }

    private nonisolated static func pixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32ARGB,
            attrs as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }
        context.clear(CGRect(origin: .zero, size: size))
        UIGraphicsPushContext(context)
        let scale = min(size.width / image.size.width, size.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let rect = CGRect(
            x: (size.width - drawSize.width) / 2,
            y: (size.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        image.draw(in: rect)
        UIGraphicsPopContext()
        return buffer
    }

    func clearCache() {
        memory.removeAllObjects()
        try? fileManager.removeItem(at: directory)
        try? fileManager.removeItem(at: liveArtworkDirectory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: liveArtworkDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Offline (pinned) artwork

    @discardableResult
    func persist(_ url: URL?) async -> Bool {
        guard let url else { return false }
        let key = Self.cacheKey(for: url)
        let pinnedURL = pinnedDirectory.appendingPathComponent(key)
        guard !fileManager.fileExists(atPath: pinnedURL.path) else { return true }

        let cacheURL = directory.appendingPathComponent(key)
        if let data = try? Data(contentsOf: cacheURL), UIImage(data: data) != nil {
            try? data.write(to: pinnedURL, options: .atomic)
            return fileManager.fileExists(atPath: pinnedURL.path)
        }
        guard let (data, _) = try? await session.data(from: url),
              UIImage(data: data) != nil else { return false }
        try? data.write(to: cacheURL, options: .atomic)
        try? data.write(to: pinnedURL, options: .atomic)
        return fileManager.fileExists(atPath: pinnedURL.path)
    }

    @discardableResult
    func persistArtistImage(id: String, from url: URL) async -> Bool {
        let idKey = Crypto.md5Hex("artist:" + id)
        let pinnedIDURL = pinnedDirectory.appendingPathComponent(idKey)
        guard !fileManager.fileExists(atPath: pinnedIDURL.path) else { return true }
        guard let (data, _) = try? await session.data(from: url),
              UIImage(data: data) != nil else { return false }
        try? data.write(to: pinnedIDURL, options: .atomic)
        let urlKey = Self.cacheKey(for: url)
        try? data.write(to: pinnedDirectory.appendingPathComponent(urlKey), options: .atomic)
        try? data.write(to: directory.appendingPathComponent(urlKey), options: .atomic)
        return fileManager.fileExists(atPath: pinnedIDURL.path)
    }

    func pinnedArtistImage(id: String) -> UIImage? {
        let idKey = Crypto.md5Hex("artist:" + id)
        let url = pinnedDirectory.appendingPathComponent(idKey)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func unpin(_ urls: [URL]) {
        for url in urls {
            let key = Self.cacheKey(for: url)
            try? fileManager.removeItem(at: pinnedDirectory.appendingPathComponent(key))
        }
    }

    func unpinArtist(id: String) {
        let idKey = Crypto.md5Hex("artist:" + id)
        try? fileManager.removeItem(at: pinnedDirectory.appendingPathComponent(idKey))
    }

    func pinnedArtworkSize() -> Int {
        Self.directorySize(at: pinnedDirectory)
    }

    func clearPinnedArtwork() {
        memory.removeAllObjects()
        try? fileManager.removeItem(at: pinnedDirectory)
        try? fileManager.createDirectory(at: pinnedDirectory, withIntermediateDirectories: true)
    }

    private nonisolated static func directorySize(at url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        return enumerator.compactMap { ($0 as? URL) }
            .compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
            .reduce(0, +)
    }
}

private extension UIImage {
    var cost: Int {
        let s = scale * scale
        return Int(size.width * size.height * s * 4)
    }
}
