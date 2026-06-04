import Foundation

enum SmartMatchMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case all = "All Rules"
    case any = "Any Rule"
    var id: String { rawValue }
}

enum SmartSortMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case title = "Title"
    case artist = "Artist"
    case album = "Album"
    case yearNewest = "Newest"
    case yearOldest = "Oldest"
    case mostPlayed = "Most Played"
    case leastPlayed = "Least Played"
    case random = "Random"
    var id: String { rawValue }
}

enum SmartTasteFilter: String, CaseIterable, Codable, Identifiable, Sendable {
    case any = "Any"
    case loved = "Loved"
    case notDisliked = "Not Disliked"
    case disliked = "Disliked"
    var id: String { rawValue }
}

struct SmartPlaylist: Identifiable, Hashable, Codable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var subtitle: String?
    var matchMode: SmartMatchMode = .all
    var searchText: String = ""
    var genre: String = ""
    var artist: String = ""
    var album: String = ""
    var minYear: Int?
    var maxYear: Int?
    var maxPlayCount: Int?
    var minPlayCount: Int?
    var onlyLossless = false
    var onlyDownloaded = false
    var neverPlayedOnly = false
    var taste: SmartTasteFilter = .notDisliked
    var sort: SmartSortMode = .random
    var limit: Int = 50

    var coverArt: String? { nil }

    var ruleSummary: String {
        var parts: [String] = []
        if !searchText.isEmpty { parts.append(searchText) }
        if !genre.isEmpty { parts.append(genre) }
        if !artist.isEmpty { parts.append(artist) }
        if onlyLossless { parts.append("Lossless") }
        if onlyDownloaded { parts.append("Downloaded") }
        if neverPlayedOnly { parts.append("Never Played") }
        if taste != .any { parts.append(taste.rawValue) }
        return parts.isEmpty ? "Smart mix" : parts.prefix(3).joined(separator: " · ")
    }

    @MainActor
    func resolve(from songs: [Song]) -> [Song] {
        let tasteStore = TasteStore.shared
        var matches = songs.filter { song in
            let rules = activeRules(for: song, tasteStore: tasteStore)
            guard !rules.isEmpty else { return true }
            switch matchMode {
            case .all: return rules.allSatisfy { $0 }
            case .any: return rules.contains(true)
            }
        }

        switch sort {
        case .title:
            matches.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artist:
            matches.sort { ($0.artist ?? "").localizedCaseInsensitiveCompare($1.artist ?? "") == .orderedAscending }
        case .album:
            matches.sort { ($0.album ?? "").localizedCaseInsensitiveCompare($1.album ?? "") == .orderedAscending }
        case .yearNewest:
            matches.sort { ($0.year ?? 0) > ($1.year ?? 0) }
        case .yearOldest:
            matches.sort { ($0.year ?? Int.max) < ($1.year ?? Int.max) }
        case .mostPlayed:
            matches.sort { ($0.playCount ?? 0) > ($1.playCount ?? 0) }
        case .leastPlayed:
            matches.sort { ($0.playCount ?? 0) < ($1.playCount ?? 0) }
        case .random:
            var rng = SeededRNG(seed: UInt64(abs(id.hashValue)) &+ SeededRNG.daySeed())
            matches.shuffle(using: &rng)
        }

        return Array(matches.prefix(max(1, limit)))
    }

    @MainActor
    private func activeRules(for song: Song, tasteStore: TasteStore) -> [Bool] {
        var rules: [Bool] = []
        if !searchText.isEmpty {
            let haystack = [song.title, song.artist, song.album, song.genre].compactMap { $0 }.joined(separator: " ")
            rules.append(haystack.localizedCaseInsensitiveContains(searchText))
        }
        if !genre.isEmpty { rules.append(song.genre?.localizedCaseInsensitiveContains(genre) == true) }
        if !artist.isEmpty { rules.append(song.artist?.localizedCaseInsensitiveContains(artist) == true) }
        if !album.isEmpty { rules.append(song.album?.localizedCaseInsensitiveContains(album) == true) }
        if let minYear { rules.append((song.year ?? 0) >= minYear) }
        if let maxYear { rules.append((song.year ?? Int.max) <= maxYear) }
        if let maxPlayCount { rules.append((song.playCount ?? 0) <= maxPlayCount) }
        if let minPlayCount { rules.append((song.playCount ?? 0) >= minPlayCount) }
        if onlyLossless { rules.append(song.isLossless) }
        if onlyDownloaded { rules.append(DownloadService.shared.state(for: song) == .downloaded) }
        if neverPlayedOnly { rules.append((song.playCount ?? 0) == 0) }

        switch taste {
        case .any:
            break
        case .loved:
            rules.append(tasteStore.state(for: song.id) == .loved)
        case .notDisliked:
            rules.append(tasteStore.state(for: song.id) != .disliked)
        case .disliked:
            rules.append(tasteStore.state(for: song.id) == .disliked)
        }

        return rules
    }
}
