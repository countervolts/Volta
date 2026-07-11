import Foundation
import Combine

@MainActor
final class HiddenAlbumStore: ObservableObject {
    static let shared = HiddenAlbumStore()
    nonisolated static let storageKey = "hiddenAlbumIDs"

    @Published private(set) var hiddenAlbumIDs: Set<String>
    @Published private(set) var revision = 0
    private var knownAlbumsByArtistID: [String: [Album]] = [:]

    private init() {
        hiddenAlbumIDs = Self.loadHiddenAlbumIDs()
    }

    func register(albums: [Album]) {
        guard !albums.isEmpty else { return }
        for album in albums {
            guard let artistID = album.artistId else { continue }
            var known = knownAlbumsByArtistID[artistID] ?? []
            if !known.contains(where: { $0.id == album.id }) {
                known.append(album)
                knownAlbumsByArtistID[artistID] = known
            }
        }
    }

    func register(artists: [Artist]) {
        for artist in artists {
            if let albums = artist.album {
                register(albums: albums)
            }
        }
    }

    func isHidden(_ album: Album) -> Bool {
        hiddenAlbumIDs.contains(album.id)
    }

    func isSongHidden(_ song: Song) -> Bool {
        Self.isSongHidden(song, hiddenAlbumIDs: hiddenAlbumIDs)
    }

    func isArtistHidden(_ artist: Artist) -> Bool {
        let albums = artist.album ?? knownAlbumsByArtistID[artist.id] ?? []
        guard !albums.isEmpty else { return false }
        if let albumCount = artist.albumCount, albums.count < albumCount {
            return false
        }
        return albums.allSatisfy { isHidden($0) }
    }

    func visibleAlbums(_ albums: [Album]) -> [Album] {
        let hidden = hiddenAlbumIDs
        return albums.filter { !hidden.contains($0.id) }
    }

    func visibleArtists(_ artists: [Artist]) -> [Artist] {
        artists.filter { !isArtistHidden($0) }
    }

    func visibleSongs(_ songs: [Song]) -> [Song] {
        let hidden = hiddenAlbumIDs
        return songs.filter { !Self.isSongHidden($0, hiddenAlbumIDs: hidden) }
    }

    func hide(_ album: Album) {
        setHidden(true, for: album.id)
    }

    func unhide(_ album: Album) {
        setHidden(false, for: album.id)
    }

    func toggle(_ album: Album) {
        setHidden(!hiddenAlbumIDs.contains(album.id), for: album.id)
    }

    func hide(albumIDs: some Sequence<String>) {
        update { ids in
            ids.formUnion(albumIDs)
        }
    }

    func unhide(albumIDs: some Sequence<String>) {
        update { ids in
            ids.subtract(albumIDs)
        }
    }

    func unhideAll() {
        update { $0.removeAll() }
    }

    func reloadFromDefaults() {
        let updated = Self.loadHiddenAlbumIDs()
        guard updated != hiddenAlbumIDs else { return }
        hiddenAlbumIDs = updated
        revision += 1
    }

    private func setHidden(_ hidden: Bool, for albumID: String) {
        update { ids in
            if hidden {
                ids.insert(albumID)
            } else {
                ids.remove(albumID)
            }
        }
    }

    private func update(_ mutate: (inout Set<String>) -> Void) {
        var updated = hiddenAlbumIDs
        mutate(&updated)
        guard updated != hiddenAlbumIDs else { return }
        hiddenAlbumIDs = updated
        revision += 1
        Self.save(updated)
    }

    nonisolated static func loadHiddenAlbumIDs() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(ids)
    }

    nonisolated static func isAlbumHidden(id: String?, hiddenAlbumIDs: Set<String> = loadHiddenAlbumIDs()) -> Bool {
        guard let id else { return false }
        return hiddenAlbumIDs.contains(id)
    }

    nonisolated static func isSongHidden(_ song: Song, hiddenAlbumIDs: Set<String> = loadHiddenAlbumIDs()) -> Bool {
        isAlbumHidden(id: song.albumId, hiddenAlbumIDs: hiddenAlbumIDs)
    }

    nonisolated static func visibleAlbums(_ albums: [Album], hiddenAlbumIDs: Set<String> = loadHiddenAlbumIDs()) -> [Album] {
        albums.filter { !hiddenAlbumIDs.contains($0.id) }
    }

    nonisolated static func visibleSongs(_ songs: [Song], hiddenAlbumIDs: Set<String> = loadHiddenAlbumIDs()) -> [Song] {
        songs.filter { !isSongHidden($0, hiddenAlbumIDs: hiddenAlbumIDs) }
    }

    private nonisolated static func save(_ ids: Set<String>) {
        let sorted = ids.sorted()
        if let data = try? JSONEncoder().encode(sorted) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

extension Artist {
    func replacingAlbums(_ albums: [Album]) -> Artist {
        Artist(
            id: id,
            name: name,
            coverArt: coverArt,
            albumCount: albums.count,
            artistImageUrl: artistImageUrl,
            starred: starred,
            album: albums
        )
    }
}
