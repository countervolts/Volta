import Foundation

/// Resolves local library metadata to public Apple Music catalog links.
enum AppleMusicLinkService {
    static func url(for song: Song) async -> URL? {
        let target = SearchTarget(
            type: .song,
            title: song.title,
            artist: song.artist ?? song.albumArtist,
            album: song.album,
            duration: song.duration
        )
        return await resolve(target)
    }

    static func url(for album: Album) async -> URL? {
        await resolve(SearchTarget(type: .album, title: album.name, artist: album.artist))
    }

    /// A convenience search URL for an explicitly catalog-oriented playlist
    /// action. Ordinary playlist sharing uses a real server share URL or
    /// descriptive text, because Apple Music cannot represent a private list.
    static func searchURL(for playlist: Playlist) -> URL? {
        searchURL(term: playlist.name)
    }

    private enum Entity: String {
        case song
        case album
        case musicArtist
    }

    private struct SearchTarget {
        let type: Entity
        let title: String
        let artist: String?
        let album: String?
        let duration: Int?

        init(type: Entity, title: String, artist: String? = nil, album: String? = nil, duration: Int? = nil) {
            self.type = type
            self.title = title
            self.artist = artist
            self.album = album
            self.duration = duration
        }
    }

    private struct SearchResponse: Decodable {
        let results: [Result]
    }

    private struct Result: Decodable {
        let artistName: String?
        let collectionName: String?
        let trackName: String?
        let trackTimeMillis: Int?
        let artistViewUrl: String?
        let collectionViewUrl: String?
        let trackViewUrl: String?
    }

    private static func resolve(_ target: SearchTarget) async -> URL? {
        guard var components = URLComponents(string: "https://itunes.apple.com/search") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "term", value: [target.artist, target.title, target.album]
                .compactMap { $0?.nonBlank }
                .joined(separator: " ")),
            URLQueryItem(name: "country", value: storefront()),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: target.type.rawValue),
            URLQueryItem(name: "limit", value: "8"),
        ]
        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return fallbackURL(for: target) }
            let results = try JSONDecoder().decode(SearchResponse.self, from: data).results
            let result = bestConfidentMatch(for: target, in: results)
            if let rawLink = link(for: target, result: result), let link = URL(string: rawLink) {
                return link
            }
            return fallbackURL(for: target)
        } catch {
            return fallbackURL(for: target)
        }
    }

    private static func bestConfidentMatch(for target: SearchTarget, in results: [Result]) -> Result? {
        let candidates = results.compactMap { result -> (Result, Int)? in
            guard matches(target, result) else { return nil }
            let durationDifference: Int
            if target.type == .song,
               let expected = target.duration, expected > 0,
               let actual = result.trackTimeMillis, actual > 0 {
                durationDifference = abs(actual / 1_000 - expected)
                // Album versions, live takes, and remasters with a materially
                // different runtime are safer as a search link.
                guard durationDifference <= 8 else { return nil }
            } else {
                durationDifference = 0
            }
            return (result, durationDifference)
        }.sorted { left, right in
            left.1 == right.1 ? stableResultIdentity(left.0) < stableResultIdentity(right.0) : left.1 < right.1
        }

        guard let first = candidates.first else { return nil }
        // A direct catalog URL claims that this is the user's item. When two
        // equally plausible results remain, share the regional search instead.
        guard candidates.dropFirst().first?.1 != first.1 else { return nil }
        return first.0
    }

    private static func stableResultIdentity(_ result: Result) -> String {
        result.trackViewUrl ?? result.collectionViewUrl ?? result.artistViewUrl ?? ""
    }

    private static func matches(_ target: SearchTarget, _ result: Result) -> Bool {
        switch target.type {
        case .song:
            return songCandidateIsConfident(
                title: target.title,
                artist: target.artist,
                album: target.album,
                duration: target.duration,
                candidateTitle: result.trackName,
                candidateArtist: result.artistName,
                candidateAlbum: result.collectionName,
                candidateDuration: result.trackTimeMillis.map { $0 / 1_000 }
            )
        case .album:
            return exactMatch(target.title, result.collectionName) && exactMatch(target.artist, result.artistName)
        case .musicArtist:
            return exactMatch(target.title, result.artistName)
        }
    }

    private static func link(for target: SearchTarget, result: Result?) -> String? {
        switch target.type {
        case .song: return result?.trackViewUrl
        case .album: return result?.collectionViewUrl
        case .musicArtist: return result?.artistViewUrl
        }
    }

    private static func exactMatch(_ left: String?, _ right: String?) -> Bool {
        guard let left = normalized(left), let right = normalized(right) else { return false }
        return left == right
    }

    static func normalized(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        // CharacterSet.alphanumerics is Unicode-aware. The former ASCII-only
        // regex discarded Japanese, Korean, Chinese, Cyrillic, and many other
        // valid catalog titles before comparison.
        let result = String(folded.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? String($0) : " "
        }.joined())
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return result.isEmpty ? nil : result
    }

    static func songCandidateIsConfident(
        title: String,
        artist: String?,
        album: String?,
        duration: Int?,
        candidateTitle: String?,
        candidateArtist: String?,
        candidateAlbum: String?,
        candidateDuration: Int?
    ) -> Bool {
        guard exactMatch(title, candidateTitle), exactMatch(artist, candidateArtist) else { return false }
        if let album, !exactMatch(album, candidateAlbum) { return false }
        if let duration, duration > 0, let candidateDuration, candidateDuration > 0,
           abs(candidateDuration - duration) > 8 { return false }
        return true
    }

    static func storefront(for locale: Locale = .current) -> String {
        let candidate = locale.region?.identifier.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let candidate,
              candidate.range(of: "^[A-Z]{2}$", options: .regularExpression) != nil else {
            return "us"
        }
        return candidate.lowercased()
    }

    static func fallbackShareText(for song: Song) -> String {
        [song.title, song.artist ?? song.albumArtist].compactMap { $0?.nonBlank }.joined(separator: " — ")
    }

    static func fallbackShareText(for album: Album) -> String {
        [album.name, album.artist].compactMap { $0?.nonBlank }.joined(separator: " — ")
    }

    private static func fallbackURL(for target: SearchTarget) -> URL? {
        searchURL(term: [target.artist, target.title, target.album].compactMap { $0?.nonBlank }.joined(separator: " "))
    }

    static func searchURL(term: String, locale: Locale = .current) -> URL? {
        var components = URLComponents(string: "https://music.apple.com/\(storefront(for: locale))/search")
        components?.queryItems = [URLQueryItem(name: "term", value: term)]
        return components?.url
    }
}
