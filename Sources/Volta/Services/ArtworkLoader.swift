import Foundation
import UIKit
import ImageIO
import AVFoundation

enum LockScreenArtworkAspect: String, Sendable {
    case square = "1x1"
    case portrait = "3x4"
}

struct LiveArtworkAsset {
    let artworkID: String
    let animatedImage: UIImage
    let previewImage: UIImage
    let videoURL: URL?
    let videoAspect: LockScreenArtworkAspect?
}

struct DownloadedArtworkItem: Identifiable, Sendable, Hashable {
    let id: String
    let displayName: String
    let fileName: String
    let kind: String
    let bytes: Int64
    let savedAt: Date?
    /// Small, aggressively compressed still preview. Animated sources are
    /// represented by frame zero only.
    let previewData: Data?
}

private struct PinnedArtworkMetadata: Codable, Sendable {
    let displayName: String
    let kind: String
    let savedAt: Date
    /// Stable album/artist identity. Older catalogs decode this as nil and are
    /// grouped by their display label as a migration fallback.
    let groupID: String?
    let isAnimated: Bool?
    /// Stable lookup identity used when no server URL exists in offline mode.
    let lookupID: String?
    /// URL cache keys retained as metadata aliases. Aliases never own bytes.
    let aliases: [String]?
    /// Durable features retaining this source, for example a downloaded album
    /// or an explicit local-artwork-library sync.
    let owners: [String]?

    private enum CodingKeys: String, CodingKey {
        case displayName, kind, savedAt, groupID, isAnimated, lookupID, aliases, owners
    }

    init(
        displayName: String,
        kind: String,
        savedAt: Date,
        groupID: String?,
        isAnimated: Bool?,
        lookupID: String?,
        aliases: [String]? = nil,
        owners: [String]? = nil
    ) {
        self.displayName = displayName
        self.kind = kind
        self.savedAt = savedAt
        self.groupID = groupID
        self.isAnimated = isAnimated
        self.lookupID = lookupID
        self.aliases = aliases
        self.owners = owners
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decode(String.self, forKey: .displayName)
        kind = try container.decode(String.self, forKey: .kind)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        groupID = try container.decodeIfPresent(String.self, forKey: .groupID)
        isAnimated = try container.decodeIfPresent(Bool.self, forKey: .isAnimated)
        lookupID = try container.decodeIfPresent(String.self, forKey: .lookupID)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases)
        owners = try container.decodeIfPresent([String].self, forKey: .owners)
    }
}

private struct DownloadedArtworkFileRecord: Sendable {
    let url: URL
    let relativePath: String
    let fileName: String
    let bytes: Int64
    let savedAt: Date?
}

private struct DownloadedArtworkGroup: Sendable {
    let identity: String
    var displayName: String
    var kind: String
    var bytes: Int64 = 0
    var savedAt: Date?
    var fileCount = 0
    var isAnimated = false
    var previewURL: URL?
    var previewIsAnimated = false

    mutating func add(
        _ file: DownloadedArtworkFileRecord,
        metadata: PinnedArtworkMetadata?,
        animated: Bool,
        canPreview: Bool
    ) {
        bytes += file.bytes
        fileCount += 1
        if canPreview, previewURL == nil || (animated && !previewIsAnimated) {
            previewURL = file.url
            previewIsAnimated = animated
        }
        isAnimated = isAnimated || animated || metadata?.isAnimated == true || metadata?.kind == "Animated"
        if let metadata {
            displayName = metadata.displayName
            if kind == "Artwork" || kind == "Album Cover" { kind = metadata.kind }
        }
        if let date = file.savedAt {
            if let existing = savedAt {
                if date > existing { savedAt = date }
            } else {
                savedAt = date
            }
        }
    }
}

actor ArtworkLoader {
    static let shared = ArtworkLoader()
    private static let lockScreenVideoVersion = 3
    private static let liveDecodePolicyVersion = 3
    private static let oversizedAnimatedDataBytes = 48 * 1024 * 1024
    private static let oversizedAnimatedPixelCount = 3_000_000
    private static let oversizedAnimatedFrameCount = 360
    private static let oversizedAnimatedPixelLimit = 192
    private static let oversizedAnimatedDecodedBytes = 64 * 1024 * 1024
    private static let extremeAnimatedDataBytes = 120 * 1024 * 1024
    private static let extremeAnimatedPixelCount = 8_000_000
    private static let extremeAnimatedFrameCount = 720
    private static let extremeAnimatedPixelLimit = 160
    private static let extremeAnimatedDecodedBytes = 48 * 1024 * 1024
    private static let minimumAnimatedPixelLimit = 64
    private static let catalogSchemaVersion = 3
    private static let staticCachePruneInterval: TimeInterval = 5 * 60
    private static let liveCachePruneInterval: TimeInterval = 5 * 60

    private let memory = NSCache<NSString, UIImage>()
    // Optional decoded-frame cache; animated covers are large.
    private let liveMemory = NSCache<NSString, LiveAssetBox>()
    private let fileManager = FileManager.default
    private let session: URLSession
    private let directory: URL
    private let liveArtworkDirectory: URL
    private var pinnedDirectory: URL
    private let pinnedCatalogURL: URL
    private let pinnedCatalogSchemaURL: URL
    // Legacy location for reconstructible pinned animation derivatives. New
    // derivatives always live in Caches/live-artwork.
    private var pinnedLiveDirectory: URL
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private var liveInFlight: [String: Task<LiveArtworkAsset?, Never>] = [:]
    private let prepareImages: Bool
    private let normalMemoryCountLimit: Int
    private let normalMemoryCostLimit: Int
    private let normalLiveMemoryCountLimit = 2
    private let normalLiveMemoryCostLimit = 128 * 1024 * 1024
    private var appliedDisableRAMOptimizations = false
    private var liveMemoryRawPolicy = false
    private var pinnedCatalog: [String: PinnedArtworkMetadata] = [:]
    private var pinnedLookupKeys: [String: [String]] = [:]
    private var pinnedAliasKeys: [String: String] = [:]
    private var storedCatalogSchemaVersion = 0
    private var lastStaticCachePrune = Date.distantPast
    private var lastLiveCachePrune = Date.distantPast

    init() {
        // Performance Mode overrides the user image profile.
        let imageMode = PerformanceMode.reduceImageQuality
            ? "conservative"
            : (UserDefaults.standard.string(forKey: "imageLoadMode") ?? "balanced")
        let cacheMode = PerformanceMode.reduceImageQuality
            ? "light"
            : (UserDefaults.standard.string(forKey: "cacheMode") ?? "balanced")

        // Artwork already has a bounded, explicit disk cache. Keep Foundation's
        // HTTP cache in memory so one response cannot occupy three disk tiers.
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        config.httpMaximumConnectionsPerHost = RuntimeCompatibility.artworkConnectionLimit(imageMode: imageMode)
        session = URLSession(configuration: config)
        prepareImages = imageMode != "conservative"

        // Decode cache is RAM-tiered; disk re-decode is cheap.
        let megabytes = RuntimeCompatibility.artworkCacheMegabytes(for: DeviceMemoryTier.current, cacheMode: cacheMode)
        normalMemoryCountLimit = RuntimeCompatibility.artworkCacheCountLimit(cacheMode: cacheMode)
        normalMemoryCostLimit = megabytes * 1024 * 1024
        memory.countLimit = normalMemoryCountLimit
        memory.totalCostLimit = normalMemoryCostLimit
        liveMemory.countLimit = LiveArtworkSettings.supportsAnimatedArtwork ? normalLiveMemoryCountLimit : 0
        liveMemory.totalCostLimit = LiveArtworkSettings.supportsAnimatedArtwork ? normalLiveMemoryCostLimit : 0

        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("artwork", isDirectory: true)
        liveArtworkDirectory = caches.appendingPathComponent("live-artwork", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        pinnedDirectory = DownloadStorageLocation.current.artworkDirectory()
        pinnedCatalogURL = appSupport.appendingPathComponent("Volta/OfflineArtworkCatalog.json")
        pinnedCatalogSchemaURL = appSupport.appendingPathComponent("Volta/OfflineArtworkCatalogSchema.json")
        pinnedLiveDirectory = pinnedDirectory.appendingPathComponent("live", isDirectory: true)
        try? fileManager.createDirectory(at: pinnedDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: pinnedCatalogURL),
           let decoded = try? JSONDecoder().decode([String: PinnedArtworkMetadata].self, from: data) {
            pinnedCatalog = decoded
        }
        pinnedLookupKeys = Self.lookupIndex(for: pinnedCatalog)
        pinnedAliasKeys = Self.aliasIndex(for: pinnedCatalog)
        if let data = try? Data(contentsOf: pinnedCatalogSchemaURL),
           let version = try? JSONDecoder().decode(Int.self, from: data) {
            storedCatalogSchemaVersion = version
        }
        if LiveArtworkSettings.supportsAnimatedArtwork {
            try? fileManager.createDirectory(at: liveArtworkDirectory, withIntermediateDirectories: true)
            // Derived assets moved to Caches/live-artwork in schema v3.
            if storedCatalogSchemaVersion >= Self.catalogSchemaVersion {
                try? fileManager.removeItem(at: pinnedLiveDirectory)
            }
        } else {
            try? fileManager.removeItem(at: liveArtworkDirectory)
            try? fileManager.removeItem(at: pinnedLiveDirectory)
        }

        // NSCache is not aggressive enough under memory pressure.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { _ in
            Task { await ArtworkLoader.shared.clearMemoryCachesForWarning() }
        }

        if storedCatalogSchemaVersion < Self.catalogSchemaVersion {
            Task { await self.migrateLegacyPinnedArtworkIfNeeded() }
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
        let cappedMaxPixelSize = RuntimeCompatibility.cappedArtworkSize(maxPixelSize)
        let decodeMaxPixelSize = disableRAMOptimizations ? nil : cappedMaxPixelSize
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
        let pinnedKeys = [
            pinnedAliasKeys[rawKey],
            pinnedAliasKeys[identityKey],
            rawKey,
            identityKey
        ].compactMap { $0 }
        let fallbackPixelCap = disableRAMOptimizations ? nil : RuntimeCompatibility.cappedArtworkSize(await Self.currentScreenPixelCap())
        let fm = fileManager
        let task = Task<UIImage?, Never> { [directory, pinnedDirectory, session, prepareImages, pinnedKeys, fm] in
            let canonicalCacheURL = directory.appendingPathComponent(identityKey)
            let legacyCacheURL = directory.appendingPathComponent(rawKey)
            var lowResolutionFallback: UIImage?
            func finish(_ data: Data) async -> UIImage? {
                // Full-size still means "screen sized" here.
                let pixelCap = disableRAMOptimizations ? nil : (decodeMaxPixelSize ?? fallbackPixelCap)
                return await Self.decodeStillImage(from: data, maxPixelSize: pixelCap, prepare: prepareImages)
            }
            func isLargeEnough(_ image: UIImage) -> Bool {
                guard let requested = decodeMaxPixelSize, requested > 0 else { return true }
                let longest = max(image.size.width, image.size.height) * image.scale
                // Do not upscale a list thumbnail into the player cover. A
                // server refresh can replace a previously cached small image.
                return longest >= CGFloat(requested) * 0.9
            }
            // Durable downloaded artwork wins over transient cache/network.
            for pinnedKey in pinnedKeys {
                let url = pinnedDirectory.appendingPathComponent(pinnedKey)
                if let data = try? Data(contentsOf: url), let image = await finish(data) {
                    if isLargeEnough(image) { return image }
                    lowResolutionFallback = image
                }
            }
            for cacheURL in [canonicalCacheURL, legacyCacheURL] where fm.fileExists(atPath: cacheURL.path) {
                if let data = try? Data(contentsOf: cacheURL), let image = await finish(data) {
                    if isLargeEnough(image) {
                        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: cacheURL.path)
                        return image
                    }
                    lowResolutionFallback = image
                }
            }
            guard let (data, response) = try? await session.data(from: url),
                  Self.isImageResponse(response, data: data),
                  let image = await finish(data) else {
                return lowResolutionFallback
            }
            // Demo-server artwork is shown from memory but never written to disk.
            if !DemoServers.isDemo(url) {
                try? data.write(to: canonicalCacheURL, options: .atomic)
                if legacyCacheURL != canonicalCacheURL {
                    try? fm.removeItem(at: legacyCacheURL)
                }
            }
            return image
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            memory.setObject(image, forKey: key as NSString, cost: image.cost)
        }
        pruneStaticCacheIfNeeded()
        return image
    }

    /// Loads pinned cover art without needing a live server URL.
    func image(forCoverArtID id: String?, maxPixelSize: Int? = nil) async -> UIImage? {
        guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { return nil }
        return await image(
            forPinnedLookupIDs: Self.coverArtLookupIDs(id),
            maxPixelSize: maxPixelSize
        )
    }

    /// Loads a namespaced offline cover. The legacy, unscoped lookup remains a
    /// fallback for catalogs written before server namespacing existed.
    func image(
        forCoverArtID id: String?,
        serverID: String?,
        maxPixelSize: Int? = nil
    ) async -> UIImage? {
        guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { return nil }
        return await image(
            forPinnedLookupIDs: Self.coverArtLookupIDs(id, serverID: serverID),
            maxPixelSize: maxPixelSize
        )
    }

    /// Last-resort offline artwork recovery. Some servers expose cover art only
    /// while online, but many downloaded audio files contain the same still in
    /// their common metadata. Once recovered, pin it under the server's cover
    /// identity so every album/track view can reuse it without parsing audio.
    func image(
        fromEmbeddedArtworkAt audioURL: URL,
        coverArtID id: String?,
        serverID: String?,
        groupID: String?,
        owner: String,
        maxPixelSize: Int? = nil
    ) async -> UIImage? {
        guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty,
              fileManager.fileExists(atPath: audioURL.path) else { return nil }

        applyMemoryPolicy(rawMode: LiveArtworkSettings.rawAnimatedArtworkEnabled)
        let disableRAMOptimizations = DeveloperExperiments.disableRAMOptimizations
        let cappedMaxPixelSize = RuntimeCompatibility.cappedArtworkSize(maxPixelSize)
        let decodeMaxPixelSize = disableRAMOptimizations ? nil : cappedMaxPixelSize
        let cacheKey = "embedded-cover-\(Crypto.md5Hex(id))-\(decodeMaxPixelSize.map(String.init) ?? "raw")"
        if let cached = memory.object(forKey: cacheKey as NSString) { return cached }

        let asset = AVURLAsset(url: audioURL)
        guard let metadata = try? await asset.load(.commonMetadata),
              let artwork = metadata.first(where: { $0.commonKey == .commonKeyArtwork }),
              let data = try? await artwork.load(.dataValue),
              let image = await Self.decodeStillImage(
                from: data,
                maxPixelSize: decodeMaxPixelSize,
                prepare: prepareImages
              ) else { return nil }

        let lookupID = Self.coverArtLookupID(id, serverID: serverID)
        _ = persistCanonicalData(
            data,
            aliases: [],
            label: audioURL.deletingPathExtension().lastPathComponent,
            kind: "Album Cover",
            groupID: groupID,
            lookupID: lookupID,
            owner: owner,
            isAnimated: false
        )
        memory.setObject(image, forKey: cacheKey as NSString, cost: image.cost)
        AppLogger.shared.log("Recovered offline cover art from downloaded audio", category: .artwork)
        return image
    }

    /// Loads pinned artist art without needing a live server URL.
    func image(forArtistID id: String?, maxPixelSize: Int? = nil) async -> UIImage? {
        guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { return nil }
        return await image(
            forPinnedKeys: pinnedLookupKeys[Self.artistLookupID(id)] ?? [Crypto.md5Hex("artist:" + id)],
            cacheNamespace: "artist:\(id)",
            maxPixelSize: maxPixelSize
        )
    }

    func image(forArtistID id: String?, serverID: String?, maxPixelSize: Int? = nil) async -> UIImage? {
        guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { return nil }
        let lookupIDs = Self.artistLookupIDs(id, serverID: serverID)
        let keys = lookupIDs.flatMap { pinnedLookupKeys[$0] ?? [] }
        return await image(
            forPinnedKeys: keys.isEmpty ? [Crypto.md5Hex("artist:" + id)] : keys,
            cacheNamespace: lookupIDs.first ?? "artist:\(id)",
            maxPixelSize: maxPixelSize
        )
    }

    /// Associates already-pinned URL artwork with its stable cover-art ID.
    /// Used to migrate downloads created before offline ID lookup existed.
    @discardableResult
    func associatePinnedCoverArt(
        id: String,
        urls: [URL],
        label: String?,
        groupID: String?,
        serverID: String? = nil,
        owner: String? = nil,
        legacyGroupIDs: [String] = []
    ) -> Bool {
        let lookupID = Self.coverArtLookupID(id, serverID: serverID)
        return associatePinnedArtwork(
            lookupID: lookupID,
            urls: urls,
            label: label,
            groupID: groupID,
            owner: owner ?? "manual:\(lookupID)",
            legacyGroupIDs: legacyGroupIDs,
            requireAnimation: false
        )
    }

    @discardableResult
    func associatePinnedAnimatedArtwork(
        id: String,
        urls: [URL],
        label: String?,
        groupID: String?,
        serverID: String? = nil,
        owner: String? = nil,
        legacyGroupIDs: [String] = []
    ) -> Bool {
        let lookupID = Self.liveArtworkLookupID(id, serverID: serverID)
        return associatePinnedArtwork(
            lookupID: lookupID,
            urls: urls,
            label: label,
            groupID: groupID,
            owner: owner ?? "manual:\(lookupID)",
            legacyGroupIDs: legacyGroupIDs,
            requireAnimation: true
        )
    }

    private func associatePinnedArtwork(
        lookupID: String,
        urls: [URL],
        label: String?,
        groupID: String?,
        owner: String,
        legacyGroupIDs: [String],
        requireAnimation: Bool
    ) -> Bool {
        let urlAliases = urls.flatMap { [Self.cacheKey(for: $0), Self.cacheKey(for: $0, sizeAgnostic: true)] }
        let allowedGroups = Set(([groupID].compactMap { $0 }) + legacyGroupIDs)
        let candidateKeys = Set(urlAliases.compactMap { pinnedAliasKeys[$0] ?? $0 })
            .union(pinnedCatalog.compactMap { key, metadata in
                guard !allowedGroups.isEmpty,
                      allowedGroups.contains(metadata.groupID ?? "") else { return nil }
                return key
            })
        let candidates = candidateKeys.compactMap { key -> (key: String, data: Data, descriptor: ImageDescriptor, metadata: PinnedArtworkMetadata?)? in
            let url = pinnedDirectory.appendingPathComponent(key)
            guard let data = try? Data(contentsOf: url),
                  let descriptor = Self.imageDescriptor(at: url),
                  (descriptor.frameCount > 1) == requireAnimation else { return nil }
            return (key, data, descriptor, pinnedCatalog[key])
        }
        guard let source = candidates.max(by: { lhs, rhs in
            if lhs.descriptor.pixelCount != rhs.descriptor.pixelCount {
                return lhs.descriptor.pixelCount < rhs.descriptor.pixelCount
            }
            if lhs.descriptor.frameCount != rhs.descriptor.frameCount {
                return lhs.descriptor.frameCount < rhs.descriptor.frameCount
            }
            return lhs.descriptor.bytes < rhs.descriptor.bytes
        }) else { return false }
        let aliases = Set(urlAliases)
            .union(candidates.map(\.key))
            .union(candidates.flatMap { $0.metadata?.aliases ?? [] })
        let saved = persistCanonicalData(
            source.data,
            aliases: aliases.sorted(),
            label: label,
            kind: requireAnimation ? "Animated" : "Album Cover",
            groupID: groupID,
            lookupID: lookupID,
            owner: owner,
            isAnimated: requireAnimation
        )
        guard saved else { return false }
        let canonicalKey = Self.canonicalFileKey(for: lookupID)
        for candidate in candidates where candidate.key != canonicalKey {
            try? fileManager.removeItem(at: pinnedDirectory.appendingPathComponent(candidate.key))
            removePinnedDerivatives(for: candidate.key)
            pinnedCatalog.removeValue(forKey: candidate.key)
        }
        rebuildPinnedIndexesAndSave()
        return true
    }

    private func image(
        forPinnedLookupIDs lookupIDs: [String],
        maxPixelSize: Int?
    ) async -> UIImage? {
        let keys = lookupIDs.flatMap { pinnedLookupKeys[$0] ?? [] }
        return await image(
            forPinnedKeys: keys,
            cacheNamespace: lookupIDs.first ?? "pinned",
            maxPixelSize: maxPixelSize
        )
    }

    private func image(
        forPinnedKeys keys: [String],
        cacheNamespace: String,
        maxPixelSize: Int?
    ) async -> UIImage? {
        guard !keys.isEmpty else { return nil }
        applyMemoryPolicy(rawMode: LiveArtworkSettings.rawAnimatedArtworkEnabled)
        let disableRAMOptimizations = DeveloperExperiments.disableRAMOptimizations
        let cappedMaxPixelSize = RuntimeCompatibility.cappedArtworkSize(maxPixelSize)
        let decodeMaxPixelSize = disableRAMOptimizations ? nil : cappedMaxPixelSize
        let cacheKey = "pinned-\(Crypto.md5Hex(cacheNamespace))-\(decodeMaxPixelSize.map(String.init) ?? "raw")"

        if let cached = memory.object(forKey: cacheKey as NSString) {
            return cached
        }
        if let existing = inFlight[cacheKey] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> { [pinnedDirectory, prepareImages] in
            let fallbackPixelCap = disableRAMOptimizations
                ? nil
                : RuntimeCompatibility.cappedArtworkSize(await Self.currentScreenPixelCap())
            for key in keys.reversed() {
                let url = pinnedDirectory.appendingPathComponent(key)
                guard let data = try? Data(contentsOf: url) else { continue }
                let pixelCap = disableRAMOptimizations ? nil : (decodeMaxPixelSize ?? fallbackPixelCap)
                if let image = await Self.decodeStillImage(from: data, maxPixelSize: pixelCap, prepare: prepareImages) {
                    return image
                }
            }
            return nil
        }
        inFlight[cacheKey] = task
        let image = await task.value
        inFlight[cacheKey] = nil
        if let image {
            memory.setObject(image, forKey: cacheKey as NSString, cost: image.cost)
        }
        return image
    }

    // Bulk prefetch stores bytes only; decoding every image blows up RAM.
    func prefetchToDisk(_ url: URL?) async {
        guard let url else { return }
        // Never persist demo-server artwork to disk.
        guard !DemoServers.isDemo(url) else { return }
        let key = Self.cacheKey(for: url)
        let identityKey = Self.cacheKey(for: url, sizeAgnostic: true)
        let fileURL = directory.appendingPathComponent(identityKey)
        guard !fileManager.fileExists(atPath: fileURL.path),
              pinnedAliasKeys[key] == nil,
              let (data, response) = try? await session.data(from: url),
              Self.isImageResponse(response, data: data) else { return }
        try? data.write(to: fileURL, options: .atomic)
        if key != identityKey {
            try? fileManager.removeItem(at: directory.appendingPathComponent(key))
        }
        pruneStaticCacheIfNeeded()
    }

    // MARK: - Live (animated) artwork

    func animatedImage(for url: URL?) async -> UIImage? {
        guard LiveArtworkSettings.supportsAnimatedArtwork else { return nil }
        // Album headers do not need lock-screen video.
        return await liveArtwork(for: url, includeVideo: false)?.animatedImage
    }

    /// Loads animation persisted beside a downloaded album without needing a
    /// live server URL. Static artwork intentionally does not qualify.
    func animatedImage(forCoverArtID id: String?, serverID: String?) async -> UIImage? {
        guard LiveArtworkSettings.supportsAnimatedArtwork,
              LiveArtworkSettings.shouldShowAnimatedArtwork,
              let id = id?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty else { return nil }

        let scoped = Self.liveArtworkLookupID(id, serverID: serverID)
        let legacy = Self.liveArtworkLookupID(id)
        let lookupIDs = scoped == legacy ? [legacy] : [scoped, legacy]
        let keys = lookupIDs.flatMap { pinnedLookupKeys[$0] ?? [] }
        guard !keys.isEmpty else { return nil }

        for key in keys.reversed() {
            let url = pinnedDirectory.appendingPathComponent(key)
            guard let data = try? Data(contentsOf: url),
                  let descriptor = Self.imageDescriptor(at: url),
                  descriptor.frameCount > 1,
                  let sequence = await Self.decodeAnimation(
                    from: data,
                    maxPixelSize: LiveArtworkSettings.maxPixelSize,
                    maxFrames: LiveArtworkSettings.maxFrameCount
                  ) else { continue }
            return sequence.image
        }
        return nil
    }

    func liveArtwork(
        for url: URL?,
        includeVideo: Bool = true,
        videoAspect: LockScreenArtworkAspect = .portrait
    ) async -> LiveArtworkAsset? {
        guard LiveArtworkSettings.supportsAnimatedArtwork,
              LiveArtworkSettings.shouldShowAnimatedArtwork else { return nil }
        guard let url else { return nil }
        let videoVariant = includeVideo ? videoAspect.rawValue : "none"
        let requestKey = "\(Self.cacheKey(for: url))-video-\(videoVariant)"
        if let existing = liveInFlight[requestKey] {
            AppLogger.shared.log(
                "Live artwork joined in-flight request; key=\(String(requestKey.prefix(12))); video=\(includeVideo)",
                category: .artwork
            )
            return await existing.value
        }

        let started = ProcessInfo.processInfo.systemUptime
        AppLogger.shared.log(
            "Live artwork load started; key=\(String(requestKey.prefix(12))); video=\(includeVideo); maxPixels=\(LiveArtworkSettings.maxPixelSize); frameQualityBudget=\(LiveArtworkSettings.maxFrameCount)",
            category: .artwork
        )
        let task = Task<LiveArtworkAsset?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.loadLiveArtwork(
                for: url,
                includeVideo: includeVideo,
                videoAspect: videoAspect
            )
        }
        liveInFlight[requestKey] = task
        let asset = await task.value
        liveInFlight[requestKey] = nil
        pruneLiveCacheIfNeeded()
        AppLogger.shared.log(
            "Live artwork load finished; key=\(String(requestKey.prefix(12))); success=\(asset != nil); frames=\(asset?.animatedImage.images?.count ?? 0); videoReady=\(asset?.videoURL != nil); elapsedMs=\(Int((ProcessInfo.processInfo.systemUptime - started) * 1000))",
            category: .artwork,
            level: asset == nil ? .warning : .info
        )
        return asset
    }

    private func loadLiveArtwork(
        for url: URL,
        includeVideo: Bool,
        videoAspect: LockScreenArtworkAspect
    ) async -> LiveArtworkAsset? {
        let rawMode = LiveArtworkSettings.rawAnimatedArtworkEnabled
        applyMemoryPolicy(rawMode: rawMode)
        let key = Self.cacheKey(for: url)
        let identityKey = Self.cacheKey(for: url, sizeAgnostic: true)
        let pinnedKey = pinnedAliasKeys[key] ?? pinnedAliasKeys[identityKey]
        let sourceKey = pinnedKey ?? key
        let maxPixelSize = LiveArtworkSettings.maxPixelSize
        let maxFrames = LiveArtworkSettings.maxFrameCount
        // Cache identity includes frame/resolution settings.
        let variantKey = rawMode
            ? "\(sourceKey)-raw"
            : "\(sourceKey)-v\(Self.liveDecodePolicyVersion)-r\(maxPixelSize)-f\(maxFrames)"
        let wantVideo = includeVideo && LiveArtworkSettings.prepareVideoAsset
        let keepInRAM = LiveArtworkSettings.keepDecodedFramesInRAM

        let pinnedURL = pinnedKey.map { pinnedDirectory.appendingPathComponent($0) }
        // Canonical downloaded source stays durable. Every frame/video artifact
        // stays reconstructible under Caches/live-artwork.
        let isPinned = pinnedURL.map { fileManager.fileExists(atPath: $0.path) } ?? false
        let liveDir = liveArtworkDirectory

        if keepInRAM, let box = liveMemory.object(forKey: variantKey as NSString) {
            AppLogger.shared.log(
                "Live artwork decoded-memory cache hit; key=\(String(variantKey.prefix(12)))",
                category: .artwork
            )
            return await Self.makeAsset(from: box.sequence, variantKey: variantKey,
                                        wantVideo: wantVideo, videoAspect: videoAspect,
                                        videoDirectory: liveDir)
        }

        // Durable cache first, then transient. Raw mode skips optimized frames.
        var sequence: AnimationSequence?
        if !rawMode {
            sequence = await Self.loadOptimizedFrameCache(variantKey: variantKey, directory: liveDir)
        }
        if sequence == nil {
            let fileURL = liveArtworkDirectory.appendingPathComponent(key + ".source")
            let data: Data?
            if let pinnedURL, let d = try? Data(contentsOf: pinnedURL) {
                AppLogger.shared.log("Live artwork bytes loaded from offline cache; bytes=\(d.count)", category: .artwork)
                data = d
            } else if let d = try? Data(contentsOf: fileURL) {
                AppLogger.shared.log("Live artwork bytes loaded from disk cache; bytes=\(d.count)", category: .artwork)
                try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
                data = d
            } else {
                data = await Self.downloadLiveArtworkBytes(from: url, using: session)
            }
            if data == nil {
                AppLogger.shared.log("Live artwork download failed", category: .artwork, level: .warning)
            }
            guard let data else { return nil }
            sequence = await Self.decodeAnimation(from: data, maxPixelSize: maxPixelSize, maxFrames: maxFrames)
            if sequence != nil, !isPinned {
                try? data.write(to: fileURL, options: .atomic)
            } else {
                try? fileManager.removeItem(at: fileURL)
            }
            if let sequence, !rawMode {
                let dir = liveDir
                DeveloperExperiments.launch(priority: .utility) {
                    await Self.writeOptimizedFrameCache(sequence, key: sourceKey, variantKey: variantKey, directory: dir)
                }
            }
        }
        guard let sequence else { return nil }
        if keepInRAM {
            let box = LiveAssetBox(sequence)
            liveMemory.setObject(box, forKey: variantKey as NSString, cost: box.cost)
        }
        return await Self.makeAsset(from: sequence, variantKey: variantKey,
                                    wantVideo: wantVideo, videoAspect: videoAspect,
                                    videoDirectory: liveDir)
    }

    private nonisolated static func downloadLiveArtworkBytes(
        from url: URL,
        using session: URLSession
    ) async -> Data? {
        do {
            let (data, response) = try await session.data(from: url)
            let contentType = response.mimeType ?? "unknown"
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard isImageResponse(response, data: data) else {
                AppLogger.shared.log(
                    "Live artwork response rejected; status=\(status); contentType=\(contentType); bytes=\(data.count); url=\(redactedURLString(url))",
                    category: .artwork,
                    level: .warning
                )
                return nil
            }
            AppLogger.shared.log(
                "Live artwork downloaded; status=\(status); contentType=\(contentType); bytes=\(data.count); url=\(redactedURLString(url))",
                category: .artwork
            )
            return data
        } catch {
            AppLogger.shared.log(
                "Live artwork download failed; error=\(error.localizedDescription); url=\(redactedURLString(url))",
                category: .artwork,
                level: .warning
            )
            return nil
        }
    }

    private nonisolated static func redactedURLString(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return url.absoluteString
        }
        components.queryItems = queryItems.map { item in
            let lower = item.name.lowercased()
            if lower.contains("token") || lower.contains("api_key") || lower.contains("password") || lower == "pw" {
                return URLQueryItem(name: item.name, value: "<redacted>")
            }
            return item
        }
        return components.url?.absoluteString ?? url.absoluteString
    }

    private func applyMemoryPolicy(rawMode: Bool) {
        let disableRAMOptimizations = DeveloperExperiments.disableRAMOptimizations
        guard appliedDisableRAMOptimizations != disableRAMOptimizations
                || liveMemoryRawPolicy != rawMode else { return }
        appliedDisableRAMOptimizations = disableRAMOptimizations
        liveMemoryRawPolicy = rawMode
        memory.countLimit = disableRAMOptimizations ? 0 : normalMemoryCountLimit
        memory.totalCostLimit = disableRAMOptimizations ? 0 : normalMemoryCostLimit

        guard LiveArtworkSettings.supportsAnimatedArtwork else {
            liveMemory.countLimit = 0
            liveMemory.totalCostLimit = 0
            liveMemory.removeAllObjects()
            return
        }

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

    private struct AnimationDecodeBudget {
        let maxPixelSize: Int
        let sourceWidth: Int
        let sourceHeight: Int
        let reason: String?

        var sourceSizeLabel: String {
            sourceWidth > 0 && sourceHeight > 0 ? "\(sourceWidth)x\(sourceHeight)" : "unknown"
        }
    }

    private struct ImageDescriptor {
        let width: Int
        let height: Int
        let frameCount: Int
        let bytes: Int
        var pixelCount: Int64 { Int64(width) * Int64(height) }
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
        videoAspect: LockScreenArtworkAspect,
        videoDirectory: URL
    ) async -> LiveArtworkAsset {
        let videoURL = wantVideo
            ? await videoAsset(
                for: sequence,
                key: variantKey,
                aspect: videoAspect,
                directory: videoDirectory
            )
            : nil
        let sourcePreview = sequence.frames.first ?? sequence.image
        let lockScreenPreview = videoURL.map { _ in
            aspectFillImage(
                sourcePreview,
                size: videoCanvasSize(for: sourcePreview, aspect: videoAspect)
            )
        }
        return LiveArtworkAsset(
            // Version the identifier so the system doesn't reuse an earlier
            // rejected preview/video pair after an app update.
            artworkID: videoURL == nil
                ? variantKey
                : "\(variantKey)-lock-v\(lockScreenVideoVersion)-\(videoAspect.rawValue)",
            animatedImage: sequence.image,
            previewImage: lockScreenPreview ?? sourcePreview,
            videoURL: videoURL,
            videoAspect: videoURL == nil ? nil : videoAspect
        )
    }

    private nonisolated static func decodeStillImage(from data: Data, maxPixelSize: Int?, prepare: Bool) async -> UIImage? {
        await DeveloperExperiments.runBlocking(qos: .userInitiated) {
            decodeImage(from: data, maxPixelSize: maxPixelSize, prepare: prepare)
        }
    }

    private nonisolated static func isImageResponse(_ response: URLResponse, data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return false
        }
        if let mimeType = response.mimeType?.lowercased(), mimeType.hasPrefix("image/") {
            return true
        }
        if isLikelyImageData(data) {
            return true
        }
        return response.mimeType == nil
    }

    private nonisolated static func isLikelyImageData(_ data: Data) -> Bool {
        startsWith(data, [0xFF, 0xD8, 0xFF])
            || startsWith(data, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            || startsWith(data, [0x47, 0x49, 0x46, 0x38])
            || isLikelyWebPData(data)
    }

    private nonisolated static func startsWith(_ data: Data, _ bytes: [UInt8]) -> Bool {
        data.count >= bytes.count && data.prefix(bytes.count).elementsEqual(bytes)
    }

    private nonisolated static func isLikelyWebPData(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        let header = [UInt8](data.prefix(12))
        return header[0...3].elementsEqual([0x52, 0x49, 0x46, 0x46])
            && header[8...11].elementsEqual([0x57, 0x45, 0x42, 0x50])
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
        guard count > 1 else {
            let type = (CGImageSourceGetType(source) as String?) ?? "unknown"
            AppLogger.shared.log(
                "Live artwork: source is not animated; type=\(type); frames=\(count); bytes=\(data.count)",
                category: .artwork,
                level: .warning
            )
            return nil
        }

        let budget = animationDecodeBudget(
            source: source,
            frameCount: count,
            dataBytes: data.count,
            maxPixelSize: maxPixelSize,
            maxFrames: maxFrames
        )
        if let reason = budget.reason {
            let pixelLabel = budget.maxPixelSize > 0 ? "\(budget.maxPixelSize)" : "raw"
            AppLogger.shared.log(
                "Live artwork: oversized source downscaled; reason=\(reason); sourceFrames=\(count); sourcePixels=\(budget.sourceSizeLabel); bytes=\(data.count); framesPreserved=\(count); targetPixels=\(pixelLabel)",
                category: .artwork
            )
        }

        // Preserve every source frame and reduce pixel size for complex art.
        var frames: [UIImage] = []
        frames.reserveCapacity(count)
        var delays: [TimeInterval] = []
        delays.reserveCapacity(count)
        var total: TimeInterval = 0
        var carried: TimeInterval = 0
        for i in 0..<count {
            carried += max(0.02, frameDelay(source: source, index: i))
            guard let cg = decodeFrame(source, index: i, maxPixelSize: budget.maxPixelSize) else { continue }
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
        let sizeLabel = budget.maxPixelSize > 0 ? "≤\(budget.maxPixelSize)px" : "raw size"
        AppLogger.shared.log("Live artwork: decoded \(frames.count)/\(count) frames at \(sizeLabel)", category: .artwork)
        return AnimationSequence(frames: frames, delays: delays, image: image)
    }

    private nonisolated static func animationDecodeBudget(
        source: CGImageSource,
        frameCount: Int,
        dataBytes: Int,
        maxPixelSize: Int,
        maxFrames: Int
    ) -> AnimationDecodeBudget {
        let sourceSize = animationSourcePixelSize(source)
        let pixelCount = sourceSize.width > 0 && sourceSize.height > 0
            ? sourceSize.width * sourceSize.height
            : 0
        var targetPixels = maxPixelSize

        // Raw/developer mode intentionally disables the normal reduction policy.
        guard maxFrames > 0 || maxPixelSize > 0 else {
            return AnimationDecodeBudget(
                maxPixelSize: targetPixels,
                sourceWidth: sourceSize.width,
                sourceHeight: sourceSize.height,
                reason: nil
            )
        }

        var reasons: [String] = []
        if maxFrames > 0, frameCount > maxFrames {
            reasons.append("frame-budget")
        }
        if frameCount > oversizedAnimatedFrameCount {
            reasons.append("frames")
        }
        if dataBytes >= oversizedAnimatedDataBytes {
            reasons.append("bytes")
        }
        if pixelCount >= oversizedAnimatedPixelCount {
            reasons.append("pixels")
        }

        let extreme = frameCount > extremeAnimatedFrameCount
            || dataBytes >= extremeAnimatedDataBytes
            || pixelCount >= extremeAnimatedPixelCount

        if !reasons.isEmpty, targetPixels > 0 {
            let fixedLimit = extreme ? extremeAnimatedPixelLimit : oversizedAnimatedPixelLimit
            let byteBudget = extreme ? extremeAnimatedDecodedBytes : oversizedAnimatedDecodedBytes
            let dynamicLimit = pixelLimitForPreservingFrames(frameCount: frameCount, decodedByteBudget: byteBudget)
            targetPixels = min(targetPixels, min(fixedLimit, dynamicLimit))
        }

        if extreme {
            if !reasons.contains("extreme") {
                reasons.append("extreme")
            }
        }

        return AnimationDecodeBudget(
            maxPixelSize: targetPixels,
            sourceWidth: sourceSize.width,
            sourceHeight: sourceSize.height,
            reason: reasons.isEmpty ? nil : reasons.joined(separator: "+")
        )
    }

    private nonisolated static func pixelLimitForPreservingFrames(
        frameCount: Int,
        decodedByteBudget: Int
    ) -> Int {
        guard frameCount > 0, decodedByteBudget > 0 else { return minimumAnimatedPixelLimit }
        let bytesPerFramePixel = 4.0
        let edge = (Double(decodedByteBudget) / (Double(frameCount) * bytesPerFramePixel)).squareRoot()
        return max(minimumAnimatedPixelLimit, Int(edge.rounded(.down)))
    }

    private nonisolated static func animationSourcePixelSize(_ source: CGImageSource) -> (width: Int, height: Int) {
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            return (
                intProperty(props[kCGImagePropertyPixelWidth]),
                intProperty(props[kCGImagePropertyPixelHeight])
            )
        }
        if let props = CGImageSourceCopyProperties(source, nil) as? [CFString: Any] {
            return (
                intProperty(props[kCGImagePropertyPixelWidth]),
                intProperty(props[kCGImagePropertyPixelHeight])
            )
        }
        return (0, 0)
    }

    private nonisolated static func intProperty(_ value: Any?) -> Int {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        return 0
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
        AppLogger.shared.log("Live artwork: loaded \(frames.count) frames from optimized frame cache", category: .artwork)
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
                for entry in entries where entry.lastPathComponent.hasPrefix(key + "-") {
                    let name = entry.lastPathComponent
                    let isDerived = name.hasSuffix(".frames") || name.hasSuffix(".mov")
                    let isCurrent = name == variantKey + ".frames"
                    if isDerived && !isCurrent {
                        try? fm.removeItem(at: entry)
                    }
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
        aspect: LockScreenArtworkAspect,
        directory: URL
    ) async -> URL? {
        let url = directory
            .appendingPathComponent(key + "-\(aspect.rawValue)-v\(lockScreenVideoVersion)-f30")
            .appendingPathExtension("mov")
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.none], ofItemAtPath: url.path
            )
            await logVideoSpecs(url, cached: true)
            return url
        }

        let frames = sequence.frames
        guard let first = frames.first else { return nil }
        let size = videoCanvasSize(for: first, aspect: aspect)
        let width = Int(size.width)
        let height = Int(size.height)

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
            AppLogger.shared.log("Live artwork video: write FAILED status=\(writer.status.rawValue) err=\(String(describing: writer.error))", category: .artwork, level: .warning)
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
        AppLogger.shared.log("Live artwork video \(cached ? "cached" : "built"): \(Int(natural.width))x\(Int(natural.height)) \(String(format: "%.2f", dur))s \(String(format: "%.0f", fps))fps codec=\(codecs) playable=\(playable) vtracks=\(vtracks.count) bytes=\(bytes) (\(url.lastPathComponent))", category: .artwork)
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
        // CVPixelBuffer rows are consumed top-to-bottom, while this bitmap
        // CGContext uses Core Graphics' bottom-left origin. UIKit drawing into
        // it without this transform produces a vertically inverted movie.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        // Aspect-fill the same canvas used for the system preview image.
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

    private nonisolated static func videoCanvasSize(
        for image: UIImage,
        aspect: LockScreenArtworkAspect
    ) -> CGSize {
        // Use an even-sized 1080p-or-better canvas for efficient video encoding.
        let decoded = max(2, Int(max(image.size.width * image.scale, image.size.height * image.scale)))
        let base = max(decoded, 1080)
        let height = base.isMultiple(of: 2) ? base : base + 1
        let rawWidth: Int
        switch aspect {
        case .square:
            rawWidth = height
        case .portrait:
            rawWidth = Int((Double(height) * 3.0 / 4.0).rounded())
        }
        let width = max(2, rawWidth.isMultiple(of: 2) ? rawWidth : rawWidth + 1)
        return CGSize(width: width, height: height)
    }

    private nonisolated static func aspectFillImage(_ image: UIImage, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let scale = max(size.width / image.size.width, size.height / image.size.height)
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(
                x: (size.width - drawSize.width) / 2,
                y: (size.height - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            ))
        }
    }

    // MARK: - Bounded disposable caches

    private var staticCacheLimitBytes: Int {
        let megabytes: Int
        switch PerformanceMode.reduceImageQuality ? "light" : (UserDefaults.standard.string(forKey: "cacheMode") ?? "balanced") {
        case "light": megabytes = 100
        case "aggressive": megabytes = 384
        default: megabytes = 200
        }
        return megabytes * 1_048_576
    }

    private var liveCacheLimitBytes: Int {
        let megabytes: Int
        switch PerformanceMode.reduceImageQuality ? "light" : (UserDefaults.standard.string(forKey: "cacheMode") ?? "balanced") {
        case "light": megabytes = 160
        case "aggressive": megabytes = 512
        default: megabytes = 320
        }
        return megabytes * 1_048_576
    }

    private func pruneStaticCacheIfNeeded(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastStaticCachePrune) >= Self.staticCachePruneInterval else { return }
        lastStaticCachePrune = now
        Self.pruneFlatDirectory(directory, limitBytes: staticCacheLimitBytes)
    }

    private func pruneLiveCacheIfNeeded(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastLiveCachePrune) >= Self.liveCachePruneInterval else { return }
        lastLiveCachePrune = now
        Self.pruneArtifactDirectory(liveArtworkDirectory, limitBytes: liveCacheLimitBytes)
    }

    private nonisolated static func pruneFlatDirectory(_ directory: URL, limitBytes: Int) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let files = entries.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                  values.isRegularFile == true else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
        var total = files.reduce(0) { $0 + $1.1 }
        guard total > limitBytes else { return }
        for file in files.sorted(by: { $0.2 < $1.2 }) {
            guard total > limitBytes else { break }
            try? FileManager.default.removeItem(at: file.0)
            total -= file.1
        }
    }

    private nonisolated static func pruneArtifactDirectory(_ directory: URL, limitBytes: Int) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let artifacts = entries.map { url -> (URL, Int, Date) in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            return (url, directorySize(at: url), values?.contentModificationDate ?? .distantPast)
        }
        var total = artifacts.reduce(0) { $0 + $1.1 }
        guard total > limitBytes else { return }
        for artifact in artifacts.sorted(by: { $0.2 < $1.2 }) {
            guard total > limitBytes else { break }
            try? FileManager.default.removeItem(at: artifact.0)
            total -= artifact.1
        }
    }

    func clearCache() {
        memory.removeAllObjects()
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        lastStaticCachePrune = .now
    }

    /// Clears only disposable animated sources and derived frame/video assets.
    /// Downloaded animated sources stay in OfflineArtwork.
    func clearLiveCache() {
        liveMemory.removeAllObjects()
        try? fileManager.removeItem(at: liveArtworkDirectory)
        if LiveArtworkSettings.supportsAnimatedArtwork {
            try? fileManager.createDirectory(at: liveArtworkDirectory, withIntermediateDirectories: true)
        }
        lastLiveCachePrune = .now
    }

    // MARK: - Offline (pinned) artwork

    @discardableResult
    func persist(
        _ url: URL?,
        label: String? = nil,
        kind: String = "Artwork",
        groupID: String? = nil,
        requireAnimation: Bool = false,
        lookupID: String? = nil,
        owner: String? = nil
    ) async -> Bool {
        guard let url else { return false }
        // Demo-server artwork is never pinned for offline use.
        guard !DemoServers.isDemo(url) else { return false }
        let rawKey = Self.cacheKey(for: url)
        let identityKey = Self.cacheKey(for: url, sizeAgnostic: true)
        let resolvedLookupID = lookupID ?? "url:\(identityKey)"
        let resolvedOwner = owner ?? "manual:\(resolvedLookupID)"
        let canonicalKey = Self.canonicalFileKey(for: resolvedLookupID)
        let canonicalURL = pinnedDirectory.appendingPathComponent(canonicalKey)

        if fileManager.fileExists(atPath: canonicalURL.path) {
            guard !requireAnimation || Self.isAnimatedImage(at: canonicalURL) else { return false }
            recordPinnedArtwork(
                id: canonicalKey,
                label: label,
                kind: kind,
                groupID: groupID,
                isAnimated: Self.isAnimatedImage(at: canonicalURL),
                lookupID: resolvedLookupID,
                aliases: [rawKey, identityKey],
                owner: resolvedOwner
            )
            let aliases = (pinnedCatalog[canonicalKey]?.aliases ?? []) + [rawKey, identityKey]
            removeTransientAliases(aliases)
            if requireAnimation { removeTransientLiveSources(aliases) }
            return true
        }

        let data: Data?
        let aliases = [rawKey, identityKey]
        if requireAnimation,
           let cached = firstValidData(at: aliases.map { liveArtworkDirectory.appendingPathComponent($0 + ".source") }),
           Self.isAnimatedImageData(cached) {
            data = cached
        } else if let cached = firstValidData(at: aliases.map { directory.appendingPathComponent($0) }) {
            data = cached
        } else if let downloaded = try? await session.data(from: url),
                  Self.isImageResponse(downloaded.1, data: downloaded.0),
                  UIImage(data: downloaded.0) != nil {
            data = downloaded.0
        } else {
            data = nil
        }
        guard let data, !requireAnimation || Self.isAnimatedImageData(data) else { return false }
        return persistCanonicalData(
            data,
            aliases: aliases,
            label: label,
            kind: kind,
            groupID: groupID,
            lookupID: resolvedLookupID,
            owner: resolvedOwner,
            isAnimated: Self.isAnimatedImageData(data)
        )
    }

    @discardableResult
    func persistArtistImage(
        id: String,
        from url: URL,
        label: String? = nil,
        serverID: String? = nil,
        owner: String? = nil
    ) async -> Bool {
        guard !DemoServers.isDemo(url) else { return false }
        let lookupID = Self.artistLookupID(id, serverID: serverID)
        let canonicalKey = Self.canonicalFileKey(for: lookupID)
        let pinnedIDURL = pinnedDirectory.appendingPathComponent(canonicalKey)
        let urlKey = Self.cacheKey(for: url)
        let identityKey = Self.cacheKey(for: url, sizeAgnostic: true)
        let retainedBy = owner ?? "manual:\(lookupID)"
        if fileManager.fileExists(atPath: pinnedIDURL.path) {
            recordPinnedArtwork(
                id: canonicalKey,
                label: label,
                kind: "Artist Photo",
                groupID: "artist:\(id)",
                lookupID: lookupID,
                aliases: [urlKey, identityKey],
                owner: retainedBy
            )
            removeTransientAliases((pinnedCatalog[canonicalKey]?.aliases ?? []) + [urlKey, identityKey])
            return true
        }
        guard let (data, response) = try? await session.data(from: url),
              Self.isImageResponse(response, data: data),
              UIImage(data: data) != nil else { return false }
        return persistCanonicalData(
            data,
            aliases: [urlKey, identityKey],
            label: label,
            kind: "Artist Photo",
            groupID: "artist:\(id)",
            lookupID: lookupID,
            owner: retainedBy,
            isAnimated: Self.isAnimatedImageData(data)
        )
    }

    func pinnedArtistImage(id: String, serverID: String? = nil) -> UIImage? {
        let lookupIDs = Self.artistLookupIDs(id, serverID: serverID)
        let key = lookupIDs.compactMap { pinnedLookupKeys[$0]?.last }.first ?? Crypto.md5Hex("artist:" + id)
        let url = pinnedDirectory.appendingPathComponent(key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func unpin(_ urls: [URL]) {
        let aliases = urls.flatMap { [Self.cacheKey(for: $0), Self.cacheKey(for: $0, sizeAgnostic: true)] }
        let keys = Set(aliases.compactMap { pinnedAliasKeys[$0] } + aliases)
        removePinnedRecords(keys)
    }

    func unpinArtist(id: String) {
        let keys = Set(pinnedLookupKeys[Self.artistLookupID(id)] ?? [])
            .union([Crypto.md5Hex("artist:" + id)])
        removePinnedRecords(keys)
    }

    /// Releases one durable owner without guessing URL variants. A canonical
    /// source and its pinned animation derivatives are removed only after its
    /// final owner disappears.
    func removeOwnership(lookupID: String, owner: String) {
        let keys = pinnedLookupKeys[lookupID] ?? []
        var removals: Set<String> = []
        for key in keys {
            guard var metadata = pinnedCatalog[key] else { continue }
            var owners = Set(metadata.owners ?? [])
            guard owners.remove(owner) != nil else { continue }
            if owners.isEmpty {
                removals.insert(key)
            } else {
                metadata = PinnedArtworkMetadata(
                    displayName: metadata.displayName,
                    kind: metadata.kind,
                    savedAt: metadata.savedAt,
                    groupID: metadata.groupID,
                    isAnimated: metadata.isAnimated,
                    lookupID: metadata.lookupID,
                    aliases: metadata.aliases,
                    owners: owners.sorted()
                )
                pinnedCatalog[key] = metadata
            }
        }
        if !removals.isEmpty {
            removePinnedRecords(removals, save: false)
        }
        rebuildPinnedIndexesAndSave()
    }

    func removeOwnership(lookupIDs: [String], owner: String) {
        for lookupID in Set(lookupIDs) {
            removeOwnership(lookupID: lookupID, owner: owner)
        }
    }

    @discardableResult
    func retainOwnership(lookupID: String, owner: String) -> Bool {
        guard let key = pinnedLookupKeys[lookupID]?.last,
              let metadata = pinnedCatalog[key],
              fileManager.fileExists(atPath: pinnedDirectory.appendingPathComponent(key).path)
        else { return false }
        recordPinnedArtwork(
            id: key,
            label: metadata.displayName,
            kind: metadata.kind,
            groupID: metadata.groupID,
            isAnimated: metadata.isAnimated == true,
            lookupID: lookupID,
            aliases: metadata.aliases ?? [],
            owner: owner
        )
        return true
    }

    func pinnedArtworkSize() -> Int {
        Self.directorySize(at: pinnedDirectory)
    }

    /// Catalog stays private; it contains metadata only. Artwork bytes move to
    /// the selected location after every downloader has stopped.
    func migrateStorage(to location: DownloadStorageLocation, method: DownloadStorageTransferMethod) throws {
        let destination = location.artworkDirectory()
        try DownloadStorageTransfer.transfer(from: pinnedDirectory, to: destination, method: method)
        pinnedDirectory = destination
        pinnedLiveDirectory = pinnedDirectory.appendingPathComponent("live", isDirectory: true)
        memory.removeAllObjects()
        liveMemory.removeAllObjects()
    }

    func hasLocalArtworkLibrary(serverID: String?) -> Bool {
        let owner = "local-artwork-library:\(serverID ?? "legacy")"
        return pinnedCatalog.values.contains { $0.owners?.contains(owner) == true }
    }

    /// Converges cataloged URL/size variants into one canonical file per lookup
    /// without a network request. Copy succeeds and decodes before old files
    /// are removed, so interruption leaves the previous source readable.
    private func migrateLegacyPinnedArtworkIfNeeded() {
        var groups: [String: [(key: String, metadata: PinnedArtworkMetadata)]] = [:]
        for (key, metadata) in pinnedCatalog {
            guard let lookupID = metadata.lookupID,
                  !lookupID.isEmpty,
                  !key.hasPrefix("live/") else { continue }
            let animated = Self.imageDescriptor(at: pinnedDirectory.appendingPathComponent(key))?.frameCount ?? 0 > 1
                || metadata.isAnimated == true
            let typedLookupID: String
            if animated {
                typedLookupID = lookupID.hasSuffix(":animated") ? lookupID : "\(lookupID):animated"
            } else {
                typedLookupID = lookupID.hasSuffix(":animated")
                    ? String(lookupID.dropLast(":animated".count))
                    : lookupID
            }
            groups[typedLookupID, default: []].append((key, metadata))
        }

        for (lookupID, entries) in groups {
            let targetKey = Self.canonicalFileKey(for: lookupID)
            let targetURL = pinnedDirectory.appendingPathComponent(targetKey)
            let wantsAnimation = lookupID.hasSuffix(":animated")
            let candidates = entries.compactMap { entry -> (key: String, metadata: PinnedArtworkMetadata, descriptor: ImageDescriptor)? in
                let url = pinnedDirectory.appendingPathComponent(entry.key)
                guard let descriptor = Self.imageDescriptor(at: url),
                      descriptor.frameCount > 0,
                      (descriptor.frameCount > 1) == wantsAnimation else { return nil }
                return (entry.key, entry.metadata, descriptor)
            }
            guard !candidates.isEmpty else { continue }

            let source = candidates.max { lhs, rhs in
                if lhs.descriptor.pixelCount != rhs.descriptor.pixelCount {
                    return lhs.descriptor.pixelCount < rhs.descriptor.pixelCount
                }
                if lhs.descriptor.frameCount != rhs.descriptor.frameCount {
                    return lhs.descriptor.frameCount < rhs.descriptor.frameCount
                }
                return lhs.descriptor.bytes < rhs.descriptor.bytes
            }!

            if !fileManager.fileExists(atPath: targetURL.path) {
                let sourceURL = pinnedDirectory.appendingPathComponent(source.key)
                let temporary = pinnedDirectory.appendingPathComponent(targetKey + ".migration-\(UUID().uuidString)")
                do {
                    try fileManager.copyItem(at: sourceURL, to: temporary)
                    guard let descriptor = Self.imageDescriptor(at: temporary),
                          descriptor.frameCount > 0,
                          (descriptor.frameCount > 1) == wantsAnimation else {
                        try? fileManager.removeItem(at: temporary)
                        continue
                    }
                    try fileManager.moveItem(at: temporary, to: targetURL)
                } catch {
                    try? fileManager.removeItem(at: temporary)
                    continue
                }
            }

            guard fileManager.fileExists(atPath: targetURL.path) else { continue }
            let current = pinnedCatalog[targetKey]
            let aliases = Set(entries.flatMap { $0.metadata.aliases ?? [] }).union(entries.map(\.key))
            let owners = Set(entries.flatMap { $0.metadata.owners ?? [] })
            let selected = current ?? source.metadata
            pinnedCatalog[targetKey] = PinnedArtworkMetadata(
                displayName: selected.displayName,
                kind: selected.kind,
                savedAt: selected.savedAt,
                groupID: selected.groupID,
                isAnimated: wantsAnimation,
                lookupID: lookupID,
                aliases: aliases.sorted(),
                owners: owners.sorted()
            )
            // Persist canonical metadata before removing any legacy file.
            rebuildPinnedIndexesAndSave()
            for entry in entries where entry.key != targetKey {
                try? fileManager.removeItem(at: pinnedDirectory.appendingPathComponent(entry.key))
                removePinnedDerivatives(for: entry.key)
                pinnedCatalog.removeValue(forKey: entry.key)
            }
        }
        // Old pinned live entries are derived frame/video artifacts, never
        // canonical sources. Cache tier now owns all such artifacts.
        try? fileManager.removeItem(at: pinnedLiveDirectory)
        rebuildPinnedIndexesAndSave()
        storedCatalogSchemaVersion = Self.catalogSchemaVersion
        if let data = try? JSONEncoder().encode(storedCatalogSchemaVersion) {
            try? data.write(to: pinnedCatalogSchemaURL, options: .atomic)
        }
        AppLogger.shared.log("Offline artwork catalog schema migrated", category: .artwork)
    }

    func downloadedArtworkItems() -> [DownloadedArtworkItem] {
        let files = downloadedArtworkFiles()
        var groups: [String: DownloadedArtworkGroup] = [:]

        for file in files {
            let metadata = metadataForArtwork(relativePath: file.relativePath)
            let identity = artworkGroupIdentity(relativePath: file.relativePath, metadata: metadata)
            let liveArtwork = Self.animatedArtworkKey(forRelativePath: file.relativePath) != nil
            let frameCount = Self.imageFrameCount(at: file.url)
            let animated = liveArtwork || frameCount > 1
            var group = groups[identity] ?? DownloadedArtworkGroup(
                identity: identity,
                displayName: metadata?.displayName ?? file.fileName,
                kind: metadata?.kind ?? (liveArtwork ? "Animated" : "Artwork")
            )
            group.add(file, metadata: metadata, animated: animated, canPreview: frameCount > 0)
            groups[identity] = group
        }

        return groups.values.map { group in
            DownloadedArtworkItem(
                id: Self.artworkGroupToken(group.identity),
                displayName: group.displayName,
                fileName: "\(group.fileCount) cached file\(group.fileCount == 1 ? "" : "s")",
                kind: group.isAnimated ? "Animated" : group.kind,
                bytes: group.bytes,
                savedAt: group.savedAt,
                previewData: group.previewURL.flatMap(Self.compressedPreviewData)
            )
        }.sorted {
            if $0.savedAt != $1.savedAt {
                return ($0.savedAt ?? .distantPast) > ($1.savedAt ?? .distantPast)
            }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func downloadedArtworkFiles() -> [DownloadedArtworkFileRecord] {
        guard let enumerator = fileManager.enumerator(
            at: pinnedDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let rootPath = pinnedDirectory.standardizedFileURL.path + "/"
        var files: [DownloadedArtworkFileRecord] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                  values.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(rootPath) else { continue }
            let relativePath = String(path.dropFirst(rootPath.count))
            files.append(DownloadedArtworkFileRecord(
                url: url,
                relativePath: relativePath,
                fileName: url.lastPathComponent,
                bytes: Int64(values.fileSize ?? 0),
                savedAt: values.contentModificationDate
            ))
        }
        return files
    }

    func removeDownloadedArtwork(id: String) {
        if let token = Self.artworkGroupHash(from: id) {
            let files = downloadedArtworkFiles()
            var removed = 0
            for file in files {
                let metadata = metadataForArtwork(relativePath: file.relativePath)
                let identity = artworkGroupIdentity(relativePath: file.relativePath, metadata: metadata)
                guard Crypto.md5Hex(identity) == token else { continue }
                try? fileManager.removeItem(at: file.url)
                pinnedCatalog.removeValue(forKey: file.relativePath)
                removed += 1
            }
            pinnedCatalog = pinnedCatalog.filter { key, metadata in
                Crypto.md5Hex(artworkGroupIdentity(relativePath: key, metadata: metadata)) != token
            }
            removeEmptyLiveArtworkDirectories()
            rebuildPinnedIndexesAndSave()
            memory.removeAllObjects()
            liveMemory.removeAllObjects()
            AppLogger.shared.log("Downloaded artwork group removed: \(token); files=\(removed)", category: .artwork)
            return
        }
        if let key = Self.animatedArtworkKey(fromGroupID: id) {
            if let entries = try? fileManager.contentsOfDirectory(
                at: pinnedLiveDirectory,
                includingPropertiesForKeys: nil
            ) {
                for entry in entries where Self.animatedArtworkKey(forLiveEntryName: entry.lastPathComponent) == key {
                    try? fileManager.removeItem(at: entry)
                }
            }
            try? fileManager.removeItem(at: pinnedDirectory.appendingPathComponent(key))
            pinnedCatalog.removeValue(forKey: key)
            rebuildPinnedIndexesAndSave()
            memory.removeAllObjects()
            liveMemory.removeAllObjects()
            AppLogger.shared.log("Downloaded animated artwork removed: \(key)", category: .artwork)
            return
        }
        guard !id.isEmpty, !id.hasPrefix("/"), !id.split(separator: "/").contains("..") else { return }
        let rootPath = pinnedDirectory.standardizedFileURL.path + "/"
        let target = pinnedDirectory.appendingPathComponent(id).standardizedFileURL
        guard target.path.hasPrefix(rootPath) else { return }
        try? fileManager.removeItem(at: target)
        pinnedCatalog.removeValue(forKey: id)
        rebuildPinnedIndexesAndSave()
        memory.removeAllObjects()
        liveMemory.removeAllObjects()
        AppLogger.shared.log("Downloaded artwork removed: \(id)", category: .artwork)
    }

    private func metadataForArtwork(relativePath: String) -> PinnedArtworkMetadata? {
        if let direct = pinnedCatalog[relativePath] { return direct }
        if let liveKey = Self.animatedArtworkKey(forRelativePath: relativePath) {
            return pinnedCatalog[liveKey]
        }
        return nil
    }

    private func artworkGroupIdentity(relativePath: String, metadata: PinnedArtworkMetadata?) -> String {
        if let groupID = metadata?.groupID?.trimmingCharacters(in: .whitespacesAndNewlines), !groupID.isEmpty {
            return "stable:\(groupID)"
        }
        if let metadata {
            // Old catalogs lacked a stable identity. The phone can already have
            // dozens of URL/size variants for one album, all carrying the same
            // label; collapse those immediately without requiring a redownload.
            let category = metadata.kind == "Artist Photo" ? "artist" : "artwork"
            let label = metadata.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return "legacy:\(category):\(label)"
        }
        if let liveKey = Self.animatedArtworkKey(forRelativePath: relativePath) {
            return "live:\(liveKey)"
        }
        return "file:\(relativePath)"
    }

    private func removeEmptyLiveArtworkDirectories() {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: pinnedLiveDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }
        for entry in entries {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory, Self.directorySize(at: entry) == 0 {
                try? fileManager.removeItem(at: entry)
            }
        }
    }

    private nonisolated static func artworkGroupToken(_ identity: String) -> String {
        "group:\(Crypto.md5Hex(identity))"
    }

    private nonisolated static func artworkGroupHash(from id: String) -> String? {
        let prefix = "group:"
        guard id.hasPrefix(prefix) else { return nil }
        let value = String(id.dropFirst(prefix.count))
        guard value.count == 32, isHexCacheKey(value) else { return nil }
        return value
    }

    private nonisolated static func animatedArtworkKey(forRelativePath path: String) -> String? {
        guard path.hasPrefix("live/") else { return nil }
        return animatedArtworkKey(forLiveEntryName: String(path.dropFirst("live/".count)))
    }

    private nonisolated static func animatedArtworkKey(forLiveEntryName name: String) -> String? {
        guard let component = name.split(separator: "-", maxSplits: 1).first else { return nil }
        let candidate = String(component)
        guard candidate.count == 32,
              isHexCacheKey(candidate) else { return nil }
        return candidate
    }

    private nonisolated static func animatedArtworkKey(fromGroupID id: String) -> String? {
        let prefix = "animated:"
        guard id.hasPrefix(prefix) else { return nil }
        let key = String(id.dropFirst(prefix.count))
        guard key.count == 32,
              isHexCacheKey(key) else { return nil }
        return key
    }

    private nonisolated static func isHexCacheKey(_ value: String) -> Bool {
        value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
        }
    }

    private nonisolated static func isAnimatedImage(at url: URL) -> Bool {
        imageFrameCount(at: url) > 1
    }

    private nonisolated static func imageFrameCount(at url: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return 0 }
        return CGImageSourceGetCount(source)
    }

    private nonisolated static func imageDescriptor(at url: URL) -> ImageDescriptor? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = intProperty(properties?[kCGImagePropertyPixelWidth])
        let height = intProperty(properties?[kCGImagePropertyPixelHeight])
        let bytes = fileSize(at: url)
        guard width > 0, height > 0, bytes > 0 else { return nil }
        return ImageDescriptor(width: width, height: height, frameCount: frameCount, bytes: bytes)
    }

    private nonisolated static func compressedPreviewData(at url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 80
        ]
        // Index zero deliberately turns GIF/APNG/WebP artwork into a static
        // first-frame preview for the low-resolution management list.
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.5)
    }

    private nonisolated static func isAnimatedImageData(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 1
    }

    func clearPinnedArtwork() {
        memory.removeAllObjects()
        liveMemory.removeAllObjects()
        try? fileManager.removeItem(at: pinnedDirectory)
        pinnedCatalog.removeAll()
        pinnedLookupKeys.removeAll()
        pinnedAliasKeys.removeAll()
        try? fileManager.removeItem(at: pinnedCatalogURL)
        try? fileManager.removeItem(at: pinnedCatalogSchemaURL)
        storedCatalogSchemaVersion = 0
        try? fileManager.createDirectory(at: pinnedDirectory, withIntermediateDirectories: true)
    }

    private func recordPinnedArtwork(
        id: String,
        label: String?,
        kind: String,
        groupID: String? = nil,
        isAnimated: Bool = false,
        lookupID: String? = nil,
        aliases: [String] = [],
        owner: String? = nil
    ) {
        let previous = pinnedCatalog[id]
        let displayName = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let mergedAliases = Set((previous?.aliases ?? []) + aliases)
        var mergedOwners = Set(previous?.owners ?? [])
        if let owner, !owner.isEmpty { mergedOwners.insert(owner) }
        pinnedCatalog[id] = PinnedArtworkMetadata(
            displayName: (displayName?.isEmpty == false ? displayName! : previous?.displayName) ?? kind,
            kind: isAnimated ? "Animated" : kind,
            savedAt: .now,
            groupID: groupID ?? previous?.groupID,
            isAnimated: isAnimated || previous?.isAnimated == true,
            lookupID: lookupID ?? previous?.lookupID,
            aliases: mergedAliases.sorted(),
            owners: mergedOwners.sorted()
        )
        rebuildPinnedIndexesAndSave()
    }

    private func persistCanonicalData(
        _ data: Data,
        aliases: [String],
        label: String?,
        kind: String,
        groupID: String?,
        lookupID: String,
        owner: String,
        isAnimated: Bool
    ) -> Bool {
        guard UIImage(data: data) != nil else { return false }
        let key = Self.canonicalFileKey(for: lookupID)
        let target = pinnedDirectory.appendingPathComponent(key)
        if !fileManager.fileExists(atPath: target.path) {
            let temporary = pinnedDirectory.appendingPathComponent(key + ".tmp-\(UUID().uuidString)")
            do {
                try data.write(to: temporary, options: .atomic)
                guard Self.imageFrameCount(at: temporary) > 0 else {
                    try? fileManager.removeItem(at: temporary)
                    return false
                }
                try fileManager.moveItem(at: temporary, to: target)
            } catch {
                try? fileManager.removeItem(at: temporary)
                return false
            }
        }
        guard fileManager.fileExists(atPath: target.path) else { return false }
        recordPinnedArtwork(
            id: key,
            label: label,
            kind: kind,
            groupID: groupID,
            isAnimated: isAnimated,
            lookupID: lookupID,
            aliases: aliases,
            owner: owner
        )
        removeTransientAliases(aliases)
        if isAnimated { removeTransientLiveSources(aliases) }
        return true
    }

    private func firstValidData(at urls: [URL]) -> Data? {
        for url in urls {
            if let data = try? Data(contentsOf: url), UIImage(data: data) != nil {
                return data
            }
        }
        return nil
    }

    private func removeTransientAliases(_ aliases: [String]) {
        for alias in Set(aliases) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(alias))
        }
    }

    private func removeTransientLiveSources(_ aliases: [String]) {
        for alias in Set(aliases) {
            try? fileManager.removeItem(at: liveArtworkDirectory.appendingPathComponent(alias + ".source"))
        }
    }

    private func removePinnedRecords(_ keys: Set<String>, save: Bool = true) {
        for key in keys {
            let url = pinnedDirectory.appendingPathComponent(key)
            try? fileManager.removeItem(at: url)
            removePinnedDerivatives(for: key)
            pinnedCatalog.removeValue(forKey: key)
        }
        removeEmptyLiveArtworkDirectories()
        if save { rebuildPinnedIndexesAndSave() }
    }

    private func removePinnedDerivatives(for key: String) {
        try? fileManager.removeItem(at: pinnedLiveDirectory.appendingPathComponent(key + ".frames"))
        if let entries = try? fileManager.contentsOfDirectory(at: pinnedLiveDirectory, includingPropertiesForKeys: nil) {
            for entry in entries where entry.lastPathComponent.hasPrefix(key + "-") {
                try? fileManager.removeItem(at: entry)
            }
        }
    }

    private func rebuildPinnedIndexesAndSave() {
        pinnedLookupKeys = Self.lookupIndex(for: pinnedCatalog)
        pinnedAliasKeys = Self.aliasIndex(for: pinnedCatalog)
        savePinnedCatalog()
    }

    nonisolated static func coverArtLookupID(_ id: String, serverID: String? = nil) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let serverID = serverID?.trimmingCharacters(in: .whitespacesAndNewlines), !serverID.isEmpty else {
            return "coverArt:\(trimmed)"
        }
        return "coverArt:\(serverID):\(trimmed)"
    }

    nonisolated static func coverArtLookupIDs(_ id: String, serverID: String? = nil) -> [String] {
        let scoped = coverArtLookupID(id, serverID: serverID)
        let legacy = coverArtLookupID(id)
        return scoped == legacy ? [legacy] : [scoped, legacy]
    }

    nonisolated static func liveArtworkLookupID(_ id: String, serverID: String? = nil) -> String {
        "\(coverArtLookupID(id, serverID: serverID)):animated"
    }

    nonisolated static func artistLookupID(_ id: String, serverID: String? = nil) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let serverID = serverID?.trimmingCharacters(in: .whitespacesAndNewlines), !serverID.isEmpty else {
            return "artist:\(trimmed)"
        }
        return "artist:\(serverID):\(trimmed)"
    }

    nonisolated static func artistLookupIDs(_ id: String, serverID: String? = nil) -> [String] {
        let scoped = artistLookupID(id, serverID: serverID)
        let legacy = artistLookupID(id)
        return scoped == legacy ? [legacy] : [scoped, legacy]
    }

    private nonisolated static func canonicalFileKey(for lookupID: String) -> String {
        Crypto.md5Hex("canonical:\(lookupID)")
    }

    private nonisolated static func lookupIndex(
        for catalog: [String: PinnedArtworkMetadata]
    ) -> [String: [String]] {
        catalog.reduce(into: [:]) { index, entry in
            guard let lookupID = entry.value.lookupID else { return }
            index[lookupID, default: []].append(entry.key)
        }
    }

    private nonisolated static func aliasIndex(
        for catalog: [String: PinnedArtworkMetadata]
    ) -> [String: String] {
        catalog.reduce(into: [:]) { index, entry in
            for alias in entry.value.aliases ?? [] {
                index[alias] = entry.key
            }
        }
    }

    private func savePinnedCatalog() {
        guard let data = try? JSONEncoder().encode(pinnedCatalog) else { return }
        try? data.write(to: pinnedCatalogURL, options: .atomic)
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

    private nonisolated static func fileSize(at url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
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
