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
    // Optional decoded-frame cache; animated covers are large.
    private let liveMemory = NSCache<NSString, LiveAssetBox>()
    private let fileManager = FileManager.default
    private let session: URLSession
    private let directory: URL
    private let liveArtworkDirectory: URL
    private let pinnedDirectory: URL
    // Downloaded live-artwork cache; survives normal artwork-cache clears.
    private let pinnedLiveDirectory: URL
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private var liveInFlight: [String: Task<LiveArtworkAsset?, Never>] = [:]
    private let prepareImages: Bool
    private let normalMemoryCountLimit: Int
    private let normalMemoryCostLimit: Int
    private let normalLiveMemoryCountLimit = 2
    private let normalLiveMemoryCostLimit = 128 * 1024 * 1024
    private var appliedDisableRAMOptimizations = false
    private var liveMemoryRawPolicy = false

    init() {
        // Performance Mode overrides the user image profile.
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

        // Decode cache is RAM-tiered; disk re-decode is cheap.
        let tierMB: Int
        switch DeviceMemoryTier.current {
        case .gb3OrLess: tierMB = 48
        case .gb4: tierMB = 64
        case .gb6: tierMB = 96
        case .gb8Plus: tierMB = 128
        }
        let megabytes = cacheMode == "aggressive" ? tierMB * 2 : (cacheMode == "light" ? min(tierMB, 32) : tierMB)
        normalMemoryCountLimit = cacheMode == "aggressive" ? 600 : (cacheMode == "light" ? 150 : 300)
        normalMemoryCostLimit = megabytes * 1024 * 1024
        memory.countLimit = normalMemoryCountLimit
        memory.totalCostLimit = normalMemoryCostLimit
        liveMemory.countLimit = normalLiveMemoryCountLimit // player + one album header
        liveMemory.totalCostLimit = normalLiveMemoryCostLimit

        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("artwork", isDirectory: true)
        liveArtworkDirectory = caches.appendingPathComponent("live-artwork", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: liveArtworkDirectory, withIntermediateDirectories: true)

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        pinnedDirectory = appSupport.appendingPathComponent("Volta/OfflineArtwork", isDirectory: true)
        try? fileManager.createDirectory(at: pinnedDirectory, withIntermediateDirectories: true)
        pinnedLiveDirectory = pinnedDirectory.appendingPathComponent("live", isDirectory: true)
        try? fileManager.createDirectory(at: pinnedLiveDirectory, withIntermediateDirectories: true)

        // NSCache is not aggressive enough under memory pressure.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { _ in
            Task { await ArtworkLoader.shared.clearMemoryCachesForWarning() }
        }
    }

    // Decode no wider than the screen; huge originals are expensive.
    @MainActor
    private static func currentScreenPixelCap() -> Int {
        let bounds = UIScreen.main.nativeBounds
        return Int(min(bounds.width, bounds.height))
    }

    private func clearMemoryCachesForWarning() {
        guard !DeveloperExperiments.disableRAMOptimizations else { return }
        memory.removeAllObjects()
        liveMemory.removeAllObjects()
    }

    // Strip auth/size noise from artwork cache keys.
    private static func cacheKey(for url: URL, sizeAgnostic: Bool = false) -> String {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return Crypto.md5Hex(url.absoluteString)
        }
        // Drop rotating auth params across Subsonic, Jellyfin, and Plex.
        var volatile: Set<String> = [
            "u", "t", "s", "p", "v", "c", "f", "salt", "token",
            "api_key", "ApiKey", "X-Plex-Token",
        ]
        // Size param names differ by backend; all are cache-key noise.
        if sizeAgnostic { volatile.formUnion(["size", "maxWidth", "maxHeight"]) }
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
        applyMemoryPolicy(rawMode: LiveArtworkSettings.rawAnimatedArtworkEnabled)
        let disableRAMOptimizations = DeveloperExperiments.disableRAMOptimizations
        let rawKey = Self.cacheKey(for: url)
        let decodeMaxPixelSize = disableRAMOptimizations ? nil : maxPixelSize
        let key = disableRAMOptimizations
            ? "\(rawKey)-ramraw"
            : (decodeMaxPixelSize.map { "\(rawKey)-max\($0)" } ?? rawKey)

        if let cached = memory.object(forKey: key as NSString) {
            return cached
        }
        if let existing = inFlight[key] {
            return await existing.value
        }

        let identityKey = Self.cacheKey(for: url, sizeAgnostic: true)
        let fallbackPixelCap = disableRAMOptimizations ? nil : await Self.currentScreenPixelCap()
        let task = Task<UIImage?, Never> { [directory, pinnedDirectory, session, prepareImages] in
            let fileURL = directory.appendingPathComponent(rawKey)
            let pinnedURL = pinnedDirectory.appendingPathComponent(rawKey)
            let identityURL = pinnedDirectory.appendingPathComponent(identityKey)
            func finish(_ data: Data) async -> UIImage? {
                // Full-size still means "screen sized" here.
                let pixelCap = disableRAMOptimizations ? nil : (decodeMaxPixelSize ?? fallbackPixelCap)
                return await Self.decodeStillImage(from: data, maxPixelSize: pixelCap, prepare: prepareImages)
            }
            if let data = try? Data(contentsOf: pinnedURL), let image = await finish(data) {
                return image
            }
            // Local artwork library wins over transient cache/network.
            if let data = try? Data(contentsOf: identityURL), let image = await finish(data) {
                return image
            }
            if let data = try? Data(contentsOf: fileURL), let image = await finish(data) {
                return image
            }
            guard let (data, _) = try? await session.data(from: url),
                  let image = await finish(data) else {
                return nil
            }
            // Demo-server artwork is shown from memory but never written to disk.
            if !DemoServers.isDemo(url) {
                try? data.write(to: fileURL, options: .atomic)
            }
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

    // Bulk prefetch stores bytes only; decoding every image blows up RAM.
    func prefetchToDisk(_ url: URL?) async {
        guard let url else { return }
        // Never persist demo-server artwork to disk.
        guard !DemoServers.isDemo(url) else { return }
        let key = Self.cacheKey(for: url)
        let fileURL = directory.appendingPathComponent(key)
        guard !fileManager.fileExists(atPath: fileURL.path),
              !fileManager.fileExists(atPath: pinnedDirectory.appendingPathComponent(key).path),
              let (data, _) = try? await session.data(from: url), !data.isEmpty else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Live (animated) artwork

    func animatedImage(for url: URL?) async -> UIImage? {
        // Album headers do not need lock-screen video.
        await liveArtwork(for: url, includeVideo: false)?.animatedImage
    }

    func liveArtwork(for url: URL?, includeVideo: Bool = true) async -> LiveArtworkAsset? {
        guard let url else { return nil }
        let requestKey = "\(Self.cacheKey(for: url))-video\(includeVideo)"
        if let existing = liveInFlight[requestKey] {
            AppLogger.shared.log(
                "Live artwork joined in-flight request; key=\(String(requestKey.prefix(12))); video=\(includeVideo)",
                category: .other
            )
            return await existing.value
        }

        let started = ProcessInfo.processInfo.systemUptime
        AppLogger.shared.log(
            "Live artwork load started; key=\(String(requestKey.prefix(12))); video=\(includeVideo); maxPixels=\(LiveArtworkSettings.maxPixelSize); maxFrames=\(LiveArtworkSettings.maxFrameCount)",
            category: .other
        )
        let task = Task<LiveArtworkAsset?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.loadLiveArtwork(for: url, includeVideo: includeVideo)
        }
        liveInFlight[requestKey] = task
        let asset = await task.value
        liveInFlight[requestKey] = nil
        AppLogger.shared.log(
            "Live artwork load finished; key=\(String(requestKey.prefix(12))); success=\(asset != nil); frames=\(asset?.animatedImage.images?.count ?? 0); videoReady=\(asset?.videoURL != nil); elapsedMs=\(Int((ProcessInfo.processInfo.systemUptime - started) * 1000))",
            category: .other,
            level: asset == nil ? .warning : .info
        )
        return asset
    }

    private func loadLiveArtwork(for url: URL, includeVideo: Bool) async -> LiveArtworkAsset? {
        let rawMode = LiveArtworkSettings.rawAnimatedArtworkEnabled
        applyMemoryPolicy(rawMode: rawMode)
        let key = Self.cacheKey(for: url)
        let maxPixelSize = LiveArtworkSettings.maxPixelSize
        let maxFrames = LiveArtworkSettings.maxFrameCount
        // Cache identity includes frame/resolution settings.
        let variantKey = rawMode ? "\(key)-raw" : "\(key)-r\(maxPixelSize)-f\(maxFrames)"
        let wantVideo = includeVideo && LiveArtworkSettings.prepareVideoAsset
        let keepInRAM = LiveArtworkSettings.keepDecodedFramesInRAM

        let pinnedURL = pinnedDirectory.appendingPathComponent(key)
        let identityURL = pinnedDirectory.appendingPathComponent(Self.cacheKey(for: url, sizeAgnostic: true))
        // Downloaded covers use durable live-artwork storage.
        let isPinned = fileManager.fileExists(atPath: pinnedURL.path)
            || fileManager.fileExists(atPath: identityURL.path)
        let liveDir = isPinned ? pinnedLiveDirectory : liveArtworkDirectory

        if keepInRAM, let box = liveMemory.object(forKey: variantKey as NSString) {
            AppLogger.shared.log(
                "Live artwork decoded-memory cache hit; key=\(String(variantKey.prefix(12)))",
                category: .other
            )
            return await Self.makeAsset(from: box.sequence, variantKey: variantKey,
                                        wantVideo: wantVideo, videoDirectory: liveDir)
        }

        // Durable cache first, then transient. Raw mode skips optimized frames.
        var sequence: AnimationSequence?
        if !rawMode {
            sequence = await Self.loadOptimizedFrameCache(variantKey: variantKey, directory: pinnedLiveDirectory)
            if sequence == nil {
                sequence = await Self.loadOptimizedFrameCache(variantKey: variantKey, directory: liveArtworkDirectory)
            }
        }
        if sequence == nil {
            let fileURL = directory.appendingPathComponent(key)
            let data: Data?
            if let d = try? Data(contentsOf: pinnedURL) {
                AppLogger.shared.log("Live artwork bytes loaded from offline cache; bytes=\(d.count)", category: .other)
                data = d
            } else if let d = try? Data(contentsOf: identityURL) {
                // Prefer the downloaded original so offline live artwork stays animated.
                AppLogger.shared.log("Live artwork bytes loaded from offline identity cache; bytes=\(d.count)", category: .other)
                data = d
            } else if let d = try? Data(contentsOf: fileURL) {
                AppLogger.shared.log("Live artwork bytes loaded from disk cache; bytes=\(d.count)", category: .other)
                data = d
            } else if let (d, _) = try? await session.data(from: url) {
                try? d.write(to: fileURL, options: .atomic)
                AppLogger.shared.log("Live artwork downloaded; bytes=\(d.count)", category: .other)
                data = d
            } else {
                AppLogger.shared.log("Live artwork download failed", category: .other, level: .warning)
                data = nil
            }
            guard let data else { return nil }
            sequence = await Self.decodeAnimation(from: data, maxPixelSize: maxPixelSize, maxFrames: maxFrames)
            if let sequence, !rawMode {
                let dir = liveDir
                DeveloperExperiments.launch(priority: .utility) {
                    await Self.writeOptimizedFrameCache(sequence, key: key, variantKey: variantKey, directory: dir)
                }
            }
        }
        guard let sequence else { return nil }
        if keepInRAM {
            let box = LiveAssetBox(sequence)
            liveMemory.setObject(box, forKey: variantKey as NSString, cost: box.cost)
        }
        return await Self.makeAsset(from: sequence, variantKey: variantKey,
                                    wantVideo: wantVideo, videoDirectory: liveDir)
    }

    private func applyMemoryPolicy(rawMode: Bool) {
        let disableRAMOptimizations = DeveloperExperiments.disableRAMOptimizations
        guard appliedDisableRAMOptimizations != disableRAMOptimizations
                || liveMemoryRawPolicy != rawMode else { return }
        appliedDisableRAMOptimizations = disableRAMOptimizations
        liveMemoryRawPolicy = rawMode
        memory.countLimit = disableRAMOptimizations ? 0 : normalMemoryCountLimit
        memory.totalCostLimit = disableRAMOptimizations ? 0 : normalMemoryCostLimit

        let unlimitedLiveMemory = disableRAMOptimizations || rawMode
        liveMemory.countLimit = unlimitedLiveMemory ? 0 : normalLiveMemoryCountLimit
        liveMemory.totalCostLimit = unlimitedLiveMemory ? 0 : normalLiveMemoryCostLimit
        if !unlimitedLiveMemory {
            liveMemory.removeAllObjects()
        }
    }

    private struct AnimationSequence: @unchecked Sendable {
        let frames: [UIImage]
        let delays: [TimeInterval]
        let image: UIImage
    }

    private final class LiveAssetBox {
        let sequence: AnimationSequence
        var cost: Int { sequence.frames.reduce(0) { $0 + $1.cost } }
        init(_ sequence: AnimationSequence) { self.sequence = sequence }
    }

    private nonisolated static func makeAsset(
        from sequence: AnimationSequence,
        variantKey: String,
        wantVideo: Bool,
        videoDirectory: URL
    ) async -> LiveArtworkAsset {
        let videoURL = wantVideo
            ? await videoAsset(for: sequence, key: variantKey, directory: videoDirectory)
            : nil
        return LiveArtworkAsset(
            artworkID: variantKey,
            animatedImage: sequence.image,
            previewImage: sequence.frames.first ?? sequence.image,
            videoURL: videoURL
        )
    }

    private nonisolated static func decodeStillImage(from data: Data, maxPixelSize: Int?, prepare: Bool) async -> UIImage? {
        await DeveloperExperiments.runBlocking(qos: .userInitiated) {
            decodeImage(from: data, maxPixelSize: maxPixelSize, prepare: prepare)
        }
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

    private nonisolated static func decodeAnimation(from data: Data, maxPixelSize: Int, maxFrames: Int) async -> AnimationSequence? {
        await DeveloperExperiments.runBlocking(qos: .userInitiated) {
            makeAnimation(from: data, maxPixelSize: maxPixelSize, maxFrames: maxFrames)
        }
    }

    private nonisolated static func makeAnimation(from data: Data, maxPixelSize: Int, maxFrames: Int) -> AnimationSequence? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return nil }

        // Drop frames evenly while preserving total loop timing.
        let target = (maxFrames > 0 && count > maxFrames) ? maxFrames : count
        var frames: [UIImage] = []
        var delays: [TimeInterval] = []
        var total: TimeInterval = 0
        var carried: TimeInterval = 0
        var lastBucket = -1
        for i in 0..<count {
            carried += max(0.02, frameDelay(source: source, index: i))
            let bucket = i * target / count
            guard bucket > lastBucket else { continue }
            guard let cg = decodeFrame(source, index: i, maxPixelSize: maxPixelSize) else { continue }
            lastBucket = bucket
            // Pre-decode frames so the first animation loop does not hitch.
            let frame = UIImage(cgImage: cg)
            frames.append(frame.preparingForDisplay() ?? frame)
            delays.append(carried)
            total += carried
            carried = 0
        }
        if carried > 0, !delays.isEmpty {
            delays[delays.count - 1] += carried
            total += carried
        }
        guard frames.count > 1 else { return nil }
        if total <= 0 { total = Double(frames.count) * 0.1 }
        let image = UIImage.animatedImage(with: frames, duration: total)
            ?? UIImage.animatedImage(with: frames, duration: Double(frames.count) * 0.1)
        guard let image else { return nil }
        image.frameDelays = delays
        let sizeLabel = maxPixelSize > 0 ? "≤\(maxPixelSize)px" : "raw size"
        AppLogger.shared.log("Live artwork: decoded \(frames.count)/\(count) frames at \(sizeLabel)", category: .other)
        return AnimationSequence(frames: frames, delays: delays, image: image)
    }

    // Downsample during decode; fall back if thumbnailing breaks animation.
    private nonisolated static func decodeFrame(_ source: CGImageSource, index: Int, maxPixelSize: Int) -> CGImage? {
        if maxPixelSize > 0 {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            if let cg = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) {
                return cg
            }
        }
        return CGImageSourceCreateImageAtIndex(source, index, nil)
    }

    // MARK: - Optimized frame cache (downsampled JPEG sequence on disk)

    // Downsampled JPEG frames make large WebP covers reopen fast.
    // Write temp-then-rename; any missing frame invalidates the cache.
    private struct FrameCacheManifest: Codable {
        var version: Int
        var delays: [TimeInterval]
    }

    private nonisolated static func loadFrameCache(variantKey: String, directory: URL) -> AnimationSequence? {
        let dir = directory.appendingPathComponent(variantKey + ".frames", isDirectory: true)
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
              let manifest = try? JSONDecoder().decode(FrameCacheManifest.self, from: data),
              manifest.version == 1, manifest.delays.count > 1 else { return nil }
        var frames: [UIImage] = []
        frames.reserveCapacity(manifest.delays.count)
        for index in manifest.delays.indices {
            guard let frameData = try? Data(contentsOf: dir.appendingPathComponent(frameFileName(index))),
                  let frame = UIImage(data: frameData) else { return nil }
            frames.append(frame.preparingForDisplay() ?? frame)
        }
        let total = max(manifest.delays.reduce(0, +), Double(frames.count) * 0.02)
        guard let image = UIImage.animatedImage(with: frames, duration: total) else { return nil }
        image.frameDelays = manifest.delays
        AppLogger.shared.log("Live artwork: loaded \(frames.count) frames from optimized frame cache", category: .other)
        return AnimationSequence(frames: frames, delays: manifest.delays, image: image)
    }

    private nonisolated static func loadOptimizedFrameCache(variantKey: String, directory: URL) async -> AnimationSequence? {
        await DeveloperExperiments.runBlocking(qos: .utility) {
            loadFrameCache(variantKey: variantKey, directory: directory)
        }
    }

    private nonisolated static func writeOptimizedFrameCache(_ sequence: AnimationSequence, key: String, variantKey: String, directory: URL) async {
        await DeveloperExperiments.runBlocking(qos: .utility) {
            writeFrameCache(sequence, key: key, variantKey: variantKey, directory: directory)
        }
    }

    private nonisolated static func writeFrameCache(_ sequence: AnimationSequence, key: String, variantKey: String, directory: URL) {
        let fm = FileManager.default
        let dir = directory.appendingPathComponent(variantKey + ".frames", isDirectory: true)
        guard !fm.fileExists(atPath: dir.appendingPathComponent("manifest.json").path) else { return }
        let tmp = directory.appendingPathComponent(variantKey + ".frames.tmp", isDirectory: true)
        try? fm.removeItem(at: tmp)
        do {
            try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            for (index, frame) in sequence.frames.enumerated() {
                guard let jpeg = frame.jpegData(compressionQuality: 0.8) else {
                    try fm.removeItem(at: tmp)
                    return
                }
                try jpeg.write(to: tmp.appendingPathComponent(frameFileName(index)))
            }
            let manifest = FrameCacheManifest(version: 1, delays: sequence.delays)
            try JSONEncoder().encode(manifest).write(to: tmp.appendingPathComponent("manifest.json"))
            try? fm.removeItem(at: dir)
            try fm.moveItem(at: tmp, to: dir)
            // Other variants of this artwork are stale now.
            if let entries = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                for entry in entries where entry.lastPathComponent.hasPrefix(key)
                    && entry.lastPathComponent.hasSuffix(".frames")
                    && entry.lastPathComponent != variantKey + ".frames" {
                    try? fm.removeItem(at: entry)
                }
            }
        } catch {
            try? fm.removeItem(at: tmp)
        }
    }

    private nonisolated static func frameFileName(_ index: Int) -> String {
        String(format: "frame-%04d.jpg", index)
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
            if let t = webp[kCGImagePropertyWebPUnclampedDelayTime] as? Double, t > 0 { return normalizedWebPDelay(t) }
            if let t = webp[kCGImagePropertyWebPDelayTime] as? Double, t > 0 { return normalizedWebPDelay(t) }
        }
        if let container = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
           let webp = container[kCGImagePropertyWebPDictionary] as? [CFString: Any],
           let info = webp[kCGImagePropertyWebPFrameInfoArray] as? [[CFString: Any]],
           info.indices.contains(index) {
            let frame = info[index]
            if let t = frame[kCGImagePropertyWebPUnclampedDelayTime] as? Double, t > 0 { return normalizedWebPDelay(t) }
            if let t = frame[kCGImagePropertyWebPDelayTime] as? Double, t > 0 { return normalizedWebPDelay(t) }
        }
        return 0.1
    }

    private nonisolated static func normalizedWebPDelay(_ value: Double) -> TimeInterval {
        value > 10 ? value / 1000 : value
    }

    private nonisolated static func videoAsset(
        for sequence: AnimationSequence,
        key: String,
        directory: URL
    ) async -> URL? {
        // Lock-screen artwork wants a 3:4 HEVC video; H.264 is ignored.
        let url = directory.appendingPathComponent(key + "-3x4f30").appendingPathExtension("mov")
        if FileManager.default.fileExists(atPath: url.path) {
            await logVideoSpecs(url, cached: true)
            return url
        }

        let frames = sequence.frames
        guard let first = frames.first else { return nil }
        // Upscale to lock-screen canvas size.
        let decoded = max(2, Int(max(first.size.width * first.scale, first.size.height * first.scale)))
        let base = max(decoded, 1080)
        // 3:4 portrait; HEVC wants even dimensions
        let height = base % 2 == 0 ? base : base + 1
        let width = max(2, { let w = Int((Double(height) * 3.0 / 4.0).rounded()); return w % 2 == 0 ? w : w + 1 }())
        let size = CGSize(width: width, height: height)

        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return nil }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        // Tag Rec.709 SDR; untagged HEVC can be silently rejected.
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoExpectedSourceFrameRateKey: 30
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)

        // Constant 30 fps. Low-fps animated sources get requested, then shown static.
        // Frames are just held longer; motion timing stays the same.
        let timescale: CMTimeScale = 600
        let fps = 30.0
        let frameDur = 1.0 / fps
        var starts: [Double] = []
        starts.reserveCapacity(frames.count)
        var acc = 0.0
        for idx in frames.indices {
            starts.append(acc)
            acc += sequence.delays.indices.contains(idx) ? max(sequence.delays[idx], 0.02) : 0.1
        }
        let totalDuration = max(acc, frameDur)
        let tickCount = max(1, Int((totalDuration * fps).rounded()))
        var tick = 0
        for (idx, frame) in frames.enumerated() {
            let frameEnd = (idx + 1 < starts.count) ? starts[idx + 1] : totalDuration
            guard let buffer = pixelBuffer(from: frame, size: size) else { continue }
            while tick < tickCount, Double(tick) * frameDur < frameEnd {
                while !input.isReadyForMoreMediaData {
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
                adaptor.append(buffer, withPresentationTime: CMTime(seconds: Double(tick) * frameDur, preferredTimescale: timescale))
                tick += 1
            }
        }
        // Pad trailing ticks for exact CFR.
        if tick < tickCount, let last = frames.last, let buffer = pixelBuffer(from: last, size: size) {
            while tick < tickCount {
                while !input.isReadyForMoreMediaData {
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
                adaptor.append(buffer, withPresentationTime: CMTime(seconds: Double(tick) * frameDur, preferredTimescale: timescale))
                tick += 1
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            AppLogger.shared.log("Live artwork video: write FAILED status=\(writer.status.rawValue) err=\(String(describing: writer.error))", category: .other, level: .warning)
            return nil
        }
        // Lock-screen reads this from another process while locked.
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.none], ofItemAtPath: url.path
        )
        await logVideoSpecs(url, cached: false)
        return url
    }

    // Debug specs for lock-screen video output.
    private nonisolated static func logVideoSpecs(_ url: URL, cached: Bool) async {
        let asset = AVURLAsset(url: url)
        let playable = (try? await asset.load(.isPlayable)) ?? false
        let dur = ((try? await asset.load(.duration))?.seconds) ?? 0
        let vtracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        var fps: Float = 0
        var natural = CGSize.zero
        var codecs = "?"
        if let t = vtracks.first {
            fps = (try? await t.load(.nominalFrameRate)) ?? 0
            natural = (try? await t.load(.naturalSize)) ?? .zero
            if let descs = try? await t.load(.formatDescriptions) {
                codecs = descs.map { fourCC(CMFormatDescriptionGetMediaSubType($0)) }.joined(separator: ",")
            }
        }
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        AppLogger.shared.log("Live artwork video \(cached ? "cached" : "built"): \(Int(natural.width))x\(Int(natural.height)) \(String(format: "%.2f", dur))s \(String(format: "%.0f", fps))fps codec=\(codecs) playable=\(playable) vtracks=\(vtracks.count) bytes=\(bytes) (\(url.lastPathComponent))", category: .other)
    }

    private nonisolated static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF), UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)]
        return String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "\(code)"
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
        // Aspect-fill the portrait canvas.
        let scale = max(size.width / image.size.width, size.height / image.size.height)
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
        liveMemory.removeAllObjects()
        try? fileManager.removeItem(at: directory)
        try? fileManager.removeItem(at: liveArtworkDirectory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: liveArtworkDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Offline (pinned) artwork

    @discardableResult
    func persist(_ url: URL?) async -> Bool {
        guard let url else { return false }
        // Demo-server artwork is never pinned for offline use.
        guard !DemoServers.isDemo(url) else { return false }
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
        guard !DemoServers.isDemo(url) else { return false }
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
        liveMemory.removeAllObjects()
        try? fileManager.removeItem(at: pinnedDirectory)
        try? fileManager.createDirectory(at: pinnedDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: pinnedLiveDirectory, withIntermediateDirectories: true)
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

private var frameDelaysKey: UInt8 = 0

extension UIImage {
    // Per-frame delays for animated images; count should match `images`.
    var frameDelays: [TimeInterval]? {
        get { objc_getAssociatedObject(self, &frameDelaysKey) as? [TimeInterval] }
        set { objc_setAssociatedObject(self, &frameDelaysKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}
