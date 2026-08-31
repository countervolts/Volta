import Foundation
import Combine

@MainActor
final class ArtworkLibraryDownloader: ObservableObject {
    static let shared = ArtworkLibraryDownloader()

    @Published private(set) var isRunning = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var failed = 0
    @Published private(set) var statusText = "Ready"
    @Published private(set) var revision = 0

    private var task: Task<Void, Never>?
    private var catalogRefreshTask: Task<Void, Never>?
    private var activeServerID: String?

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(completed) / Double(total))
    }

    func start(client: any MusicService) {
        guard !isRunning else { return }
        if DemoServers.isDemo(client.config.baseURL) {
            VoltaNotificationCenter.shared.post(L(.notif_demo_no_downloads), tone: .info)
            return
        }
        isRunning = true
        completed = 0
        total = 0
        failed = 0
        statusText = "Loading artwork library…"
        activeServerID = AppState.shared.currentServer?.id
        task = Task { await run(client: client) }
    }

    func cancel() {
        task?.cancel()
    }

    private func run(client: any MusicService) async {
        let serverID = activeServerID
        let owner = "local-artwork-library:\(serverID ?? "legacy")"
        let albums: [Album]
        let artists: [Artist]
        if DeveloperExperiments.constrainedConcurrency(default: 2) == 1 {
            albums = await Self.loadAllAlbums(client: client)
            artists = (try? await client.artists()) ?? []
        } else {
            async let albumsRequest = Self.loadAllAlbums(client: client)
            async let artistsRequest = client.artists()
            albums = await albumsRequest
            artists = (try? await artistsRequest) ?? []
        }
        guard !Task.isCancelled else { finish(cancelled: true); return }

        let coverAlbums = await DeveloperExperiments.runSync {
            var values: [String: String] = [:]
            for album in albums {
                guard let cover = album.coverArt else { continue }
                values[cover] = values[cover] ?? album.name
            }
            return values.sorted { $0.key < $1.key }
        }
        let coverRequests = coverAlbums.map { cover, albumName in
            ArtworkLibraryRequest(
                url: client.coverArtURL(id: cover, size: 1024) ?? client.coverArtURL(id: cover),
                label: albumName,
                groupID: "server:\(serverID ?? "legacy")|album-cover:\(cover)",
                lookupID: ArtworkLoader.coverArtLookupID(cover, serverID: serverID),
                owner: owner
            )
        }
        total = coverRequests.count + artists.count
        statusText = "Downloading album covers…"

        await persist(requests: coverRequests)
        guard !Task.isCancelled else { finish(cancelled: true); return }

        statusText = "Downloading artist photos…"
        for artist in artists {
            guard !Task.isCancelled else { finish(cancelled: true); return }
            record(await Self.persistArtist(artist, client: client, serverID: serverID, owner: owner))
        }
        finish(cancelled: false)
    }

    private func persist(requests: [ArtworkLibraryRequest]) async {
        var index = 0
        let batchSize = 8
        while index < requests.count {
            guard !Task.isCancelled else { return }
            let batch = Array(requests[index..<min(index + batchSize, requests.count)])
            let results = await DeveloperExperiments.runConcurrently(batch, defaultMaxConcurrent: batchSize) { request in
                await ArtworkLoader.shared.persist(
                    request.url,
                    label: request.label,
                    kind: "Album Cover",
                    groupID: request.groupID,
                    lookupID: request.lookupID,
                    owner: request.owner
                )
            }
            for result in results { record(result) }
            index += batchSize
        }
    }

    private func record(_ succeeded: Bool) {
        completed += 1
        if !succeeded { failed += 1 }
        if succeeded { scheduleCatalogRefresh() }
    }

    private func finish(cancelled: Bool) {
        isRunning = false
        task = nil
        catalogRefreshTask?.cancel()
        catalogRefreshTask = nil
        revision &+= 1
        let complete = !cancelled && total > 0 && completed == total && failed == 0
        UserDefaults.standard.set(complete, forKey: "localArtworkLibraryDownloaded")
        activeServerID = nil
        statusText = cancelled
            ? "Stopped · \(completed) of \(total) checked"
            : "Done · \(completed - failed) saved · \(failed) failed"
        AppLogger.shared.log(
            "Local artwork library \(cancelled ? "stopped" : "finished"): \(completed)/\(total), failed=\(failed)",
            category: .artwork
        )
    }

    /// File persistence can complete hundreds of times during a library sync.
    /// Coalesce catalog invalidations so On This Device updates promptly without
    /// repeatedly rescanning the complete artwork directory for each file.
    private func scheduleCatalogRefresh() {
        guard catalogRefreshTask == nil else { return }
        catalogRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, !Task.isCancelled else { return }
            self.catalogRefreshTask = nil
            self.revision &+= 1
        }
    }

    private nonisolated static func loadAllAlbums(client: any MusicService) async -> [Album] {
        var albums: [Album] = []
        var offset = 0
        while true {
            let page = (try? await client.allAlbums(size: 500, offset: offset)) ?? []
            albums.append(contentsOf: page)
            if page.count < 500 || offset > 50_000 || Task.isCancelled { break }
            offset += 500
        }
        return albums
    }

    private nonisolated static func persistArtist(
        _ artist: Artist,
        client: any MusicService,
        serverID: String?,
        owner: String
    ) async -> Bool {
        if await ArtworkLoader.shared.retainOwnership(
            lookupID: ArtworkLoader.artistLookupID(artist.id, serverID: serverID),
            owner: owner
        ) { return true }
        if let directURL = artist.artistImageUrl.flatMap(URL.init(string:)),
           await ArtworkLoader.shared.persistArtistImage(id: artist.id, from: directURL, label: artist.name, serverID: serverID, owner: owner) { return true }
        if let info = try? await client.artistInfo(id: artist.id),
           let value = info.bestImageUrl,
           let url = URL(string: value),
           await ArtworkLoader.shared.persistArtistImage(id: artist.id, from: url, label: artist.name, serverID: serverID, owner: owner) { return true }
        if let fallback = client.coverArtURL(id: artist.coverArt, size: 600) {
            return await ArtworkLoader.shared.persistArtistImage(id: artist.id, from: fallback, label: artist.name, serverID: serverID, owner: owner)
        }
        return false
    }
}

private struct ArtworkLibraryRequest: Sendable {
    let url: URL?
    let label: String
    let groupID: String
    let lookupID: String
    let owner: String
}
