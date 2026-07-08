import Foundation

enum ArtistNameResolver {
    static let unknownArtist = "Unknown Artist"

    private static let featureSeparators = [
        " • ",
        " featuring ",
        " feat. ",
        " feat ",
        " ft. ",
        " ft ",
        " with ",
        ";",
    ]

    private static let genericAlbumArtists: Set<String> = [
        "various",
        "various artists",
        "compilation",
        "soundtrack",
    ]

    static func primaryArtistName(for song: Song) -> String {
        primaryArtistName(trackArtist: song.artist, albumArtist: song.albumArtist)
    }

    static func primaryArtistName(trackArtist: String?, albumArtist: String? = nil) -> String {
        if let albumArtist = albumArtist?.nonBlank,
           !isGenericAlbumArtist(albumArtist) {
            return albumArtist
        }

        guard let name = trackArtist?.nonBlank else {
            return unknownArtist
        }

        var earliest = name.endIndex
        for separator in featureSeparators {
            if let range = name.range(of: separator, options: [.caseInsensitive]),
               range.lowerBound < earliest {
                earliest = range.lowerBound
            }
        }

        let primary = String(name[..<earliest]).trimmingCharacters(in: .whitespacesAndNewlines)
        return primary.isEmpty ? name : primary
    }

    static func primaryArtistID(for song: Song) -> String? {
        if let albumArtist = song.albumArtist?.nonBlank,
           !isGenericAlbumArtist(albumArtist),
           let albumArtistId = song.albumArtistId?.nonBlank {
            return albumArtistId
        }
        return song.artistId?.nonBlank
    }

    static func offlineArtistKey(for song: Song) -> String {
        primaryArtistID(for: song) ?? "offline-artist-\(primaryArtistName(for: song))"
    }

    static func splitArtistName(_ name: String) -> [String] {
        var split = name
        for separator in featureSeparators {
            split = split.replacingOccurrences(of: separator, with: "|", options: [.caseInsensitive])
        }
        return split.components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func isGenericAlbumArtist(_ name: String) -> Bool {
        genericAlbumArtists.contains(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

extension Song {
    var primaryArtistName: String {
        ArtistNameResolver.primaryArtistName(for: self)
    }

    var primaryArtistID: String? {
        ArtistNameResolver.primaryArtistID(for: self)
    }

    var offlineArtistKey: String {
        ArtistNameResolver.offlineArtistKey(for: self)
    }
}
