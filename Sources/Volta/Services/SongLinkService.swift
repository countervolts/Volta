import Foundation

enum SongLinkService {
    static func pageURL(for song: Song) async -> URL? {
        guard let sourceURL = await iTunesURL(for: song) else { return nil }
        return await songLinkPageURL(from: sourceURL)
    }

    private static func iTunesURL(for song: Song) async -> URL? {
        let query = [song.title, song.artist].compactMap { $0 }.joined(separator: " ")
        guard var comps = URLComponents(string: "https://itunes.apple.com/search") else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = comps.url else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
            guard let raw = response.results.first?.trackViewUrl else { return nil }
            return URL(string: raw)
        } catch {
            return nil
        }
    }

    private static func songLinkPageURL(from sourceURL: URL) async -> URL? {
        guard var comps = URLComponents(string: "https://api.song.link/v1-alpha.1/links") else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "url", value: sourceURL.absoluteString),
            URLQueryItem(name: "userCountry", value: Locale.current.region?.identifier ?? "US"),
        ]
        guard let url = comps.url else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(SongLinkResponse.self, from: data)
            return URL(string: response.pageUrl)
        } catch {
            return nil
        }
    }

    private struct ITunesSearchResponse: Decodable {
        let results: [ITunesTrack]
    }

    private struct ITunesTrack: Decodable {
        let trackViewUrl: String?
    }

    private struct SongLinkResponse: Decodable {
        let pageUrl: String
    }
}
