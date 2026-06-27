import Foundation
import Observation

// MARK: - Metric value types

// A labelled bucket with a share of the whole library (0...100).
struct LibCountMetric: Identifiable, Hashable {
    let id: String
    let label: String
    let count: Int
    var percentage: Double = 0
}

struct LibAlbumRank: Identifiable, Hashable {
    let id: String
    let name: String
    let artist: String
    let coverArt: String?
    let tracks: Int
    let duration: Int   // seconds
    let size: Int       // bytes
}

struct LibTrackRank: Identifiable, Hashable {
    let id: String
    let name: String
    let artist: String
    let album: String
    let coverArt: String?
    let duration: Int   // seconds
    let size: Int       // bytes
    let addedAt: Date?
}

struct LibArtistRank: Identifiable, Hashable {
    let id: String
    let name: String
    let coverArt: String?
    let tracks: Int
    let albums: Int
    let duration: Int   // seconds
}

struct LibMetadataCoverage: Hashable {
    var artwork = 0
    var releaseYear = 0
    var genres = 0
    var bpm = 0
}

// The full snapshot rendered by the Library tab.
struct LibraryStatsData: Hashable {
    var source = ""
    var scannedAt = Date()

    var totalSongs = 0
    var totalAlbums = 0
    var totalArtists = 0
    var totalSeconds = 0
    var totalSize = 0

    var averageTrackSeconds = 0
    var averageAlbumTracks = 0.0
    var averageBitrate = 0

    var losslessTracks = 0
    var hiResTracks = 0

    var firstReleaseYear: Int?
    var lastReleaseYear: Int?

    var channels: [LibCountMetric] = []
    var fileFormats: [LibCountMetric] = []
    var bitDepths: [LibCountMetric] = []
    var sampleRates: [LibCountMetric] = []
    var decades: [LibCountMetric] = []
    var durationBuckets: [LibCountMetric] = []
    var genreTags: [LibCountMetric] = []

    var topArtists: [LibArtistRank] = []
    var largestAlbums: [LibAlbumRank] = []
    var longestTracks: [LibTrackRank] = []
    var topAlbums: [LibAlbumRank] = []        // most tracks per album
    var recentlyAdded: [LibTrackRank] = []     // newest albums

    var metadataCoverage = LibMetadataCoverage()

    var decadeSpan: Int {
        guard let f = firstReleaseYear, let l = lastReleaseYear, l >= f else { return 0 }
        return (l / 10) - (f / 10) + 1
    }
    var sizePerTrack: Int { totalSongs > 0 ? totalSize / totalSongs : 0 }
    var hoursTotal: Int { totalSeconds / 3600 }
    var commonResolution: String {
        let depth = bitDepths.first?.label ?? "Unknown"
        let rate = sampleRates.first?.label ?? "Unknown"
        return "\(depth) · \(rate)"
    }
}

@MainActor
@Observable
final class LibraryStatsViewModel {
    enum Phase: Equatable { case idle, loading, ready, failed }

    private(set) var phase: Phase = .idle
    private(set) var progress: Double = 0       // 0...1 while scanning
    private(set) var stats: LibraryStatsData?
    private(set) var errorMessage: String?
    private(set) var isOfflineData = false

    // Computed snapshots are expensive (a full library walk), so keep the last
    // result per server alive across tab switches.
    private static var cache: [String: LibraryStatsData] = [:]
    private static var cacheOffline: [String: Bool] = [:]

    private var currentTask: Task<Void, Never>?

    private func cacheKey(_ appState: AppState) -> String {
        appState.currentServer?.id ?? "downloads"
    }

    // Load from cache if we have a snapshot, otherwise scan once.
    func loadIfNeeded(appState: AppState) {
        if let cached = Self.cache[cacheKey(appState)] {
            stats = cached
            isOfflineData = Self.cacheOffline[cacheKey(appState)] ?? false
            phase = .ready
            return
        }
        guard phase != .loading else { return }
        scan(appState: appState)
    }

    func refresh(appState: AppState) {
        scan(appState: appState)
    }

    private func scan(appState: AppState) {
        currentTask?.cancel()
        phase = .loading
        progress = 0
        errorMessage = nil
        let key = cacheKey(appState)

        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.buildStats(appState: appState)
                if Task.isCancelled { return }
                Self.cache[key] = result.data
                Self.cacheOffline[key] = result.offline
                self.stats = result.data
                self.isOfflineData = result.offline
                self.phase = .ready
            } catch is CancellationError {
                // superseded by a newer scan; leave state untouched
            } catch {
                if Task.isCancelled { return }
                self.errorMessage = error.localizedDescription
                self.phase = .failed
            }
        }
    }

    // MARK: - Fetch

    private func buildStats(appState: AppState) async throws -> (data: LibraryStatsData, offline: Bool) {
        let offline = NetworkMonitor.shared.connection == .none
        // Offline, or no live connection: compute from what's on disk.
        if offline || appState.client == nil {
            let songs = DownloadService.shared.downloadedSongs()
            let data = await Task.detached(priority: .utility) {
                Self.computeStats(songs: songs, albumMeta: [:], source: "Downloaded Music")
            }.value
            return (data, true)
        }

        guard let client = appState.client else {
            throw NSError(domain: "LibraryStats", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No server connected."])
        }

        // 1. Page through the album index for the album-level metadata.
        var albumMeta: [Album] = []
        var offset = 0
        while true {
            try Task.checkCancellation()
            let batch = (try? await client.allAlbums(size: 500, offset: offset)) ?? []
            albumMeta.append(contentsOf: batch)
            if batch.count < 500 { break }
            offset += 500
            if offset > 50_000 { break }
        }

        // 2. Expand each album into its tracks for the per-song audio detail.
        var allSongs: [Song] = []
        let total = max(1, albumMeta.count)
        var done = 0
        var index = 0
        let batchSize = 12
        while index < albumMeta.count {
            try Task.checkCancellation()
            let slice = Array(albumMeta[index..<min(index + batchSize, albumMeta.count)])
            let songBatches = await DeveloperExperiments.runConcurrently(slice, defaultMaxConcurrent: batchSize) { album in
                (try? await client.album(id: album.id))?.song ?? album.song ?? []
            }
            allSongs.append(contentsOf: songBatches.flatMap { $0 })
            done += slice.count
            index += batchSize
            await MainActor.run { self.progress = Double(done) / Double(total) }
        }

        let source = appState.currentServer?.displayName ?? "Library"
        let albumLookup = Dictionary(albumMeta.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let data = await Task.detached(priority: .utility) {
            Self.computeStats(songs: allSongs, albumMeta: albumLookup, source: source)
        }.value
        return (data, false)
    }

    // MARK: - Compute

    nonisolated private static func computeStats(
        songs: [Song],
        albumMeta: [String: Album],
        source: String
    ) -> LibraryStatsData {
        var data = LibraryStatsData()
        data.source = source
        data.scannedAt = Date()
        data.totalSongs = songs.count
        guard !songs.isEmpty else { return data }

        // Running aggregates over a single pass.
        var totalSeconds = 0
        var totalSize = 0
        var bitrateSum = 0
        var bitrateCount = 0
        var lossless = 0
        var hiRes = 0
        var minYear = Int.max
        var maxYear = Int.min

        var formatCounts: [String: Int] = [:]
        var bitDepthCounts: [Int: Int] = [:]
        var sampleRateCounts: [Int: Int] = [:]
        var channelCounts: [Int: Int] = [:]
        var decadeCounts: [Int: Int] = [:]
        var durationBucketCounts: [Int: Int] = [:]   // bucket index -> count
        var genreCounts: [String: Int] = [:]

        var coverage = LibMetadataCoverage()

        // Per-album rollups.
        struct AlbumAgg { var name = ""; var artist = ""; var cover: String?; var tracks = 0; var duration = 0; var size = 0 }
        var albumAgg: [String: AlbumAgg] = [:]
        // Per-artist rollups.
        struct ArtistAgg { var name = ""; var cover: String?; var tracks = 0; var duration = 0; var albums = Set<String>() }
        var artistAgg: [String: ArtistAgg] = [:]

        let durationEdges = [120, 180, 240, 300, 600]   // 2,3,4,5,10 min
        let durationLabels = ["<2m", "2–3m", "3–4m", "4–5m", "5–10m", "10m+"]

        for song in songs {
            let dur = song.duration ?? 0
            totalSeconds += dur
            totalSize += song.size ?? 0

            if let br = song.bitRate, br > 0 { bitrateSum += br; bitrateCount += 1 }
            if song.isLossless { lossless += 1 }
            if song.isHiResLossless { hiRes += 1 }

            // metadata coverage
            if song.coverArt != nil { coverage.artwork += 1 }
            if let y = song.year, y > 0 { coverage.releaseYear += 1 }
            if song.genre?.nonBlank != nil { coverage.genres += 1 }
            if let b = song.bpm, b > 0 { coverage.bpm += 1 }

            // release year / decade
            if let y = song.year, y > 0 {
                minYear = min(minYear, y)
                maxYear = max(maxYear, y)
                decadeCounts[(y / 10) * 10, default: 0] += 1
            }

            // formats / audio profile
            let suffix = (song.suffix ?? song.contentType?.components(separatedBy: "/").last ?? "other")
                .lowercased()
            formatCounts[suffix, default: 0] += 1
            if let bd = song.bitDepth, bd > 0 { bitDepthCounts[bd, default: 0] += 1 }
            if let sr = song.samplingRate, sr > 0 { sampleRateCounts[sr, default: 0] += 1 }
            if let ch = song.channelCount, ch > 0 { channelCounts[ch, default: 0] += 1 }

            // duration distribution
            var bucket = durationEdges.count
            for (i, edge) in durationEdges.enumerated() where dur < edge { bucket = i; break }
            durationBucketCounts[bucket, default: 0] += 1

            // genres
            if let g = song.genre?.nonBlank { genreCounts[g, default: 0] += 1 }

            // album rollup
            let aKey = song.albumId ?? song.album ?? "—"
            var ag = albumAgg[aKey] ?? AlbumAgg()
            if ag.name.isEmpty { ag.name = song.album ?? "Unknown Album" }
            if ag.artist.isEmpty { ag.artist = song.artist ?? "Unknown Artist" }
            if ag.cover == nil { ag.cover = song.coverArt }
            ag.tracks += 1
            ag.duration += dur
            ag.size += song.size ?? 0
            albumAgg[aKey] = ag

            // artist rollup (group features under the lead artist)
            let leadName = StatsViewModel.primaryArtist(song.artist ?? "Unknown Artist")
            let artKey = song.artistId ?? leadName
            var rg = artistAgg[artKey] ?? ArtistAgg()
            if rg.name.isEmpty { rg.name = leadName }
            if rg.cover == nil { rg.cover = song.coverArt }
            rg.tracks += 1
            rg.duration += dur
            rg.albums.insert(aKey)
            artistAgg[artKey] = rg
        }

        data.totalSeconds = totalSeconds
        data.totalSize = totalSize
        data.totalAlbums = albumAgg.count
        data.totalArtists = artistAgg.count
        data.averageTrackSeconds = totalSeconds / max(1, songs.count)
        data.averageAlbumTracks = Double(songs.count) / Double(max(1, albumAgg.count))
        data.averageBitrate = bitrateCount > 0 ? bitrateSum / bitrateCount : 0
        data.losslessTracks = lossless
        data.hiResTracks = hiRes
        data.firstReleaseYear = minYear == Int.max ? nil : minYear
        data.lastReleaseYear = maxYear == Int.min ? nil : maxYear
        data.metadataCoverage = coverage

        let n = Double(songs.count)
        func pct(_ c: Int) -> Double { (Double(c) / n * 1000).rounded() / 10 }

        data.fileFormats = formatCounts.sorted { $0.value > $1.value }.prefix(8).map {
            LibCountMetric(id: $0.key, label: $0.key.uppercased(), count: $0.value, percentage: pct($0.value))
        }
        data.bitDepths = bitDepthCounts.sorted { $0.value > $1.value }.map {
            LibCountMetric(id: "\($0.key)", label: "\($0.key)-bit", count: $0.value, percentage: pct($0.value))
        }
        data.sampleRates = sampleRateCounts.sorted { $0.value > $1.value }.map {
            LibCountMetric(id: "\($0.key)", label: Self.formatSampleRate($0.key), count: $0.value, percentage: pct($0.value))
        }
        data.channels = channelCounts.sorted { $0.value > $1.value }.map {
            LibCountMetric(id: "\($0.key)", label: Self.channelLabel($0.key), count: $0.value, percentage: pct($0.value))
        }
        data.decades = decadeCounts.sorted { $0.key < $1.key }.map {
            LibCountMetric(id: "\($0.key)", label: "\($0.key)s", count: $0.value, percentage: pct($0.value))
        }
        data.durationBuckets = (0..<durationLabels.count).map { i in
            LibCountMetric(id: "\(i)", label: durationLabels[i], count: durationBucketCounts[i] ?? 0,
                           percentage: pct(durationBucketCounts[i] ?? 0))
        }
        data.genreTags = genreCounts.sorted { $0.value > $1.value }.prefix(10).map {
            LibCountMetric(id: $0.key, label: $0.key, count: $0.value, percentage: pct($0.value))
        }

        // Rankings.
        data.topArtists = artistAgg.map {
            LibArtistRank(id: $0.key, name: $0.value.name, coverArt: $0.value.cover,
                          tracks: $0.value.tracks, albums: $0.value.albums.count, duration: $0.value.duration)
        }
        .sorted { $0.tracks > $1.tracks }.prefix(12).map { $0 }

        let albumRanks = albumAgg.map { kv in
            LibAlbumRank(id: kv.key, name: kv.value.name, artist: kv.value.artist, coverArt: kv.value.cover,
                         tracks: kv.value.tracks, duration: kv.value.duration, size: kv.value.size)
        }
        data.largestAlbums = albumRanks.sorted { $0.size > $1.size }.prefix(10).map { $0 }
        data.topAlbums = albumRanks.sorted { $0.tracks > $1.tracks }.prefix(10).map { $0 }

        data.longestTracks = songs.sorted { ($0.duration ?? 0) > ($1.duration ?? 0) }.prefix(10).map {
            LibTrackRank(id: $0.id, name: $0.title, artist: $0.artist ?? "Unknown Artist",
                         album: $0.album ?? "Unknown Album", coverArt: $0.coverArt,
                         duration: $0.duration ?? 0, size: $0.size ?? 0, addedAt: nil)
        }

        // Recently added: newest albums by their created date.
        let recent = albumMeta.values
            .compactMap { a -> (Album, Date)? in a.createdDate.map { (a, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(8)
        data.recentlyAdded = recent.map { (album, date) in
            LibTrackRank(id: album.id, name: album.name, artist: album.displayArtist,
                         album: album.name, coverArt: album.coverArt,
                         duration: album.duration ?? 0, size: 0, addedAt: date)
        }

        return data
    }

    // MARK: - Formatting helpers

    nonisolated static func formatSampleRate(_ hz: Int) -> String {
        let khz = Double(hz) / 1000
        if khz == khz.rounded() { return "\(Int(khz)) kHz" }
        return String(format: "%.1f kHz", khz)
    }

    nonisolated static func channelLabel(_ count: Int) -> String {
        switch count {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(count) ch"
        }
    }
}
