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

    /// Apple Music cannot represent a user's private server playlist. Keep the
    /// share destination on Apple Music without exposing the server URL.
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
            URLQueryItem(name: "country", value: "US"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: target.type.rawValue),
            URLQueryItem(name: "limit", value: "8"),
        ]
        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return fallbackURL(for: target) }
            let results = try JSONDecoder().decode(SearchResponse.self, from: data).results
                .filter { matches(target, $0) }
            let result = target.duration.map { duration in
                results.min { abs(($0.trackTimeMillis ?? 0) / 1000 - duration) < abs(($1.trackTimeMillis ?? 0) / 1000 - duration) }
            } ?? results.first
            if let rawLink = link(for: target, result: result), let link = URL(string: rawLink) {
                return link
            }
            return fallbackURL(for: target)
        } catch {
            return fallbackURL(for: target)
        }
    }

    private static func matches(_ target: SearchTarget, _ result: Result) -> Bool {
        switch target.type {
        case .song:
            return matches(target.title, result.trackName) && matches(target.artist, result.artistName)
        case .album:
            return matches(target.title, result.collectionName) && matches(target.artist, result.artistName)
        case .musicArtist:
            return matches(target.title, result.artistName)
        }
    }

    private static func link(for target: SearchTarget, result: Result?) -> String? {
        switch target.type {
        case .song: return result?.trackViewUrl
        case .album: return result?.collectionViewUrl
        case .musicArtist: return result?.artistViewUrl
        }
    }

    private static func matches(_ left: String?, _ right: String?) -> Bool {
        guard let left = normalized(left), let right = normalized(right) else { return false }
        return left == right || left.contains(right) || right.contains(left)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let result = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-zA-Z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return result.isEmpty ? nil : result
    }

    private static func fallbackURL(for target: SearchTarget) -> URL? {
        searchURL(term: [target.artist, target.title, target.album].compactMap { $0?.nonBlank }.joined(separator: " "))
    }

    private static func searchURL(term: String) -> URL? {
        var components = URLComponents(string: "https://music.apple.com/us/search")
        components?.queryItems = [URLQueryItem(name: "term", value: term)]
        return components?.url
    }
}
