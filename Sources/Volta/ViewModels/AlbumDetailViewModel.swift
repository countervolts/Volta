import Foundation
import UIKit
import Combine

@MainActor
final class AlbumDetailViewModel: ObservableObject {
    @Published private(set) var album: Album
    @Published private(set) var songs: [Song] = []
    @Published private(set) var moreBySameArtist: [Album] = []
    @Published private(set) var isLoading = false
    @Published private(set) var dominantColor: UIColor = .black
    @Published private(set) var explicitSongIDs = Set<String>()

    @Published private(set) var isDescriptionExpanded = false

    var discNumbers: [Int] {
        let set = Set(songs.compactMap { $0.discNumber })
        return set.sorted()
    }

    // Lossless only when every track is lossless.
    var isLossless: Bool {
        !songs.isEmpty && songs.allSatisfy(\.isLossless)
    }

    // Hi-res when the album is lossless and contains at least one hi-res track.
    var isHiResLossless: Bool {
        isLossless && songs.contains(where: \.isHiResLossless)
    }

    func songs(forDisc disc: Int) -> [Song] {
        if discNumbers.count <= 1 { return songs }
        return songs.filter { ($0.discNumber ?? 1) == disc }
    }

    init(album: Album) {
        self.album = album
        self.songs = album.song ?? []
    }

    func load(client: any MusicService) async {
        guard !isLoading else {
            AppLogger.shared.log("Album metadata load coalesced; albumID=\(album.id)", category: .other)
            return
        }
        isLoading = true
        defer { isLoading = false }
        let started = ProcessInfo.processInfo.systemUptime

        let albumID = album.id
        let artistID = album.artistId
        let loadedAlbum: Album?
        let relatedAlbums: [Album]
        let loadArtistAlbums: () async -> [Album] = {
            guard let id = artistID else { return [] }
            let artist = try? await client.artist(id: id)
            return artist?.album ?? []
        }

        if client.backendKind == .emby || DeveloperExperiments.constrainedConcurrency(default: 2) == 1 {
            loadedAlbum = try? await client.album(id: albumID)
            relatedAlbums = await loadArtistAlbums()
        } else {
            async let fullAlbum = client.album(id: albumID)
            async let artistAlbums = loadArtistAlbums()
            loadedAlbum = try? await fullAlbum
            relatedAlbums = await artistAlbums
        }

        let sortTracks: ([Song]) -> [Song] = { list in
            list.sorted {
                let d0 = $0.discNumber ?? 1, d1 = $1.discNumber ?? 1
                if d0 != d1 { return d0 < d1 }
                return ($0.track ?? 0) < ($1.track ?? 0)
            }
        }

        if let loaded = loadedAlbum, !(loaded.song ?? []).isEmpty {
            album = loaded
            songs = sortTracks(loaded.song ?? [])
            AppLogger.shared.log(
                "Album metadata loaded from server; albumID=\(albumID); songs=\(songs.count); related=\(relatedAlbums.count); elapsedMs=\(Int((ProcessInfo.processInfo.systemUptime - started) * 1000))",
                category: .other
            )
        } else if songs.isEmpty {
            // Offline fallback: show this album's downloaded tracks.
            let local = DownloadService.shared.downloadedSongs().filter { $0.albumId == album.id }
            if !local.isEmpty {
                songs = sortTracks(local)
                AppLogger.shared.log(
                    "Album metadata used offline fallback; albumID=\(albumID); songs=\(songs.count)",
                    category: .other,
                    level: .warning
                )
            } else {
                AppLogger.shared.log(
                    "Album metadata unavailable; albumID=\(albumID); elapsedMs=\(Int((ProcessInfo.processInfo.systemUptime - started) * 1000))",
                    category: .other,
                    level: .warning
                )
            }
        }
        moreBySameArtist = relatedAlbums.filter { $0.id != album.id }
    }

    func resolveExplicitStatuses(client: any MusicService) async {
        explicitSongIDs.formUnion(songs.filter(\.isExplicit).map(\.id))
        let unresolved = songs.filter { !$0.hasKnownExplicitStatus }
        guard !unresolved.isEmpty else { return }

        let resolved = await DeveloperExperiments.runConcurrently(
            unresolved,
            defaultMaxConcurrent: 3
        ) { song in
            let value = await ExplicitStatusResolver.shared.isExplicit(
                songID: song.id,
                localURL: DownloadService.shared.localURL(for: song),
                remoteURL: client.originalStreamURL(id: song.id),
                requestHeaders: client.mediaRequestHeaders()
            )
            return value == true ? song.id : nil
        }
        explicitSongIDs.formUnion(resolved.compactMap { $0 })
        AppLogger.shared.log(
            "Album explicit metadata resolved; albumID=\(album.id); server=\(songs.filter(\.isExplicit).count); embedded=\(resolved.compactMap { $0 }.count)",
            category: .other
        )
    }

    func setDominantColor(_ color: UIColor) {
        dominantColor = color
    }

    func toggleDescription() {
        isDescriptionExpanded.toggle()
    }
}
