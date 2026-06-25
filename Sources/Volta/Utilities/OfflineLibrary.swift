import Foundation

// Builds library-shaped objects (albums, artists) purely from a set of Songs.
// Used for the fully-offline experience, where the only metadata available is
// whatever rides along with downloaded tracks. Mirrors the grouping the offline
// Home screen uses so synthesized ids line up across screens.
enum OfflineLibrary {
    static func albumKey(for song: Song) -> String {
        song.albumId ?? "offline-album-\(song.album ?? song.id)"
    }

    static func artistKey(for song: Song) -> String {
        song.artistId ?? "offline-artist-\(song.artist ?? "Unknown Artist")"
    }

    // Group songs into synthesized albums, each carrying its tracks in disc/track
    // order. Sorted by album name.
    static func albums(from songs: [Song]) -> [Album] {
        var grouped: [String: [Song]] = [:]
        for song in songs {
            grouped[albumKey(for: song), default: []].append(song)
        }
        return grouped.map { id, albumSongs in
            let sorted = albumSongs.sorted {
                let disc0 = $0.discNumber ?? 1
                let disc1 = $1.discNumber ?? 1
                if disc0 != disc1 { return disc0 < disc1 }
                return ($0.track ?? 0) < ($1.track ?? 0)
            }
            let first = sorted[0]
            return Album(
                id: id,
                name: first.album ?? "Unknown Album",
                artist: first.artist,
                artistId: first.artistId,
                coverArt: first.coverArt,
                songCount: sorted.count,
                duration: sorted.reduce(0) { $0 + ($1.duration ?? 0) },
                playCount: nil,
                created: nil,
                year: first.year,
                genre: first.genre,
                starred: nil,
                comment: nil,
                recordLabel: nil,
                song: sorted
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func artists(from songs: [Song]) -> [Artist] {
        var grouped: [String: [Song]] = [:]
        for song in songs {
            grouped[artistKey(for: song), default: []].append(song)
        }
        return grouped.map { id, artistSongs in
            let first = artistSongs[0]
            let albumIDs = Set(artistSongs.compactMap(\.albumId))
            return Artist(
                id: id,
                name: first.artist ?? "Unknown Artist",
                coverArt: first.coverArt,
                albumCount: max(1, albumIDs.count),
                artistImageUrl: nil,
                starred: nil,
                album: nil
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // Songs whose genre exactly matches (case-insensitively) the given genre.
    static func songs(inGenre genre: String, from songs: [Song]) -> [Song] {
        let target = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        return songs.filter {
            ($0.genre ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(target) == .orderedSame
        }
    }
}
