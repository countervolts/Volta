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
    var pinned = false
    var matchMode: SmartMatchMode = .all
    var searchText: String = ""
    var genre: String = ""
    var artist: String = ""
    var album: String = ""
    var selectedArtists: [String] = []
    var selectedAlbums: [String] = []
    var minYear: Int?
    var maxYear: Int?
    var maxPlayCount: Int?
    var minPlayCount: Int?
    var onlyLossless = false
    var onlyHiResLossless = false
    var onlyDownloaded = false
    var neverPlayedOnly = false
    var taste: SmartTasteFilter = .notDisliked
    var sort: SmartSortMode = .random
    var limit: Int = 50

    var coverArt: String? { nil }

    init(name: String) {
        self.name = name
    }

    var ruleSummary: String {
        var parts: [String] = []
        if !searchText.isEmpty { parts.append(searchText) }
        if !genre.isEmpty { parts.append(genre) }
        if !artist.isEmpty { parts.append(artist) }
        if !selectedArtists.isEmpty { parts.append("\(selectedArtists.count) artist\(selectedArtists.count == 1 ? "" : "s")") }
        if !selectedAlbums.isEmpty { parts.append("\(selectedAlbums.count) album\(selectedAlbums.count == 1 ? "" : "s")") }
        if onlyHiResLossless {
            parts.append("Hi-Res Lossless")
        } else if onlyLossless {
            parts.append("Lossless")
        }
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
            let stableSeed = UInt64(Crypto.md5Hex(id).prefix(16), radix: 16) ?? 0
            var rng = SeededRNG(seed: stableSeed &+ SeededRNG.daySeed())
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
        if !selectedArtists.isEmpty {
            rules.append(selectedArtists.contains { selected in
                song.artist?.localizedCaseInsensitiveCompare(selected) == .orderedSame
            })
        }
        if !selectedAlbums.isEmpty {
            rules.append(selectedAlbums.contains { selected in
                song.album?.localizedCaseInsensitiveCompare(selected) == .orderedSame
            })
        }
        if let minYear { rules.append((song.year ?? 0) >= minYear) }
        if let maxYear { rules.append((song.year ?? Int.max) <= maxYear) }
        if let maxPlayCount { rules.append((song.playCount ?? 0) <= maxPlayCount) }
        if let minPlayCount { rules.append((song.playCount ?? 0) >= minPlayCount) }
        if onlyLossless { rules.append(song.isLossless) }
        if onlyHiResLossless { rules.append(song.isHiResLossless) }
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

    enum CodingKeys: String, CodingKey {
        case id, name, subtitle, pinned, matchMode, searchText, genre, artist, album
        case selectedArtists, selectedAlbums, minYear, maxYear, maxPlayCount, minPlayCount
        case onlyLossless, onlyHiResLossless, onlyDownloaded, neverPlayedOnly, taste, sort, limit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = try c.decode(String.self, forKey: .name)
        subtitle = try? c.decode(String.self, forKey: .subtitle)
        pinned = (try? c.decode(Bool.self, forKey: .pinned)) ?? false
        matchMode = (try? c.decode(SmartMatchMode.self, forKey: .matchMode)) ?? .all
        searchText = (try? c.decode(String.self, forKey: .searchText)) ?? ""
        genre = (try? c.decode(String.self, forKey: .genre)) ?? ""
        artist = (try? c.decode(String.self, forKey: .artist)) ?? ""
        album = (try? c.decode(String.self, forKey: .album)) ?? ""
        selectedArtists = (try? c.decode([String].self, forKey: .selectedArtists)) ?? []
        selectedAlbums = (try? c.decode([String].self, forKey: .selectedAlbums)) ?? []
        minYear = try? c.decode(Int.self, forKey: .minYear)
        maxYear = try? c.decode(Int.self, forKey: .maxYear)
        maxPlayCount = try? c.decode(Int.self, forKey: .maxPlayCount)
        minPlayCount = try? c.decode(Int.self, forKey: .minPlayCount)
        onlyLossless = (try? c.decode(Bool.self, forKey: .onlyLossless)) ?? false
        onlyHiResLossless = (try? c.decode(Bool.self, forKey: .onlyHiResLossless)) ?? false
        onlyDownloaded = (try? c.decode(Bool.self, forKey: .onlyDownloaded)) ?? false
        neverPlayedOnly = (try? c.decode(Bool.self, forKey: .neverPlayedOnly)) ?? false
        taste = (try? c.decode(SmartTasteFilter.self, forKey: .taste)) ?? .notDisliked
        sort = (try? c.decode(SmartSortMode.self, forKey: .sort)) ?? .random
        limit = (try? c.decode(Int.self, forKey: .limit)) ?? 50
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encode(pinned, forKey: .pinned)
        try c.encode(matchMode, forKey: .matchMode)
        try c.encode(searchText, forKey: .searchText)
        try c.encode(genre, forKey: .genre)
        try c.encode(artist, forKey: .artist)
        try c.encode(album, forKey: .album)
        try c.encode(selectedArtists, forKey: .selectedArtists)
        try c.encode(selectedAlbums, forKey: .selectedAlbums)
        try c.encodeIfPresent(minYear, forKey: .minYear)
        try c.encodeIfPresent(maxYear, forKey: .maxYear)
        try c.encodeIfPresent(maxPlayCount, forKey: .maxPlayCount)
        try c.encodeIfPresent(minPlayCount, forKey: .minPlayCount)
        try c.encode(onlyLossless, forKey: .onlyLossless)
        try c.encode(onlyHiResLossless, forKey: .onlyHiResLossless)
        try c.encode(onlyDownloaded, forKey: .onlyDownloaded)
        try c.encode(neverPlayedOnly, forKey: .neverPlayedOnly)
        try c.encode(taste, forKey: .taste)
        try c.encode(sort, forKey: .sort)
        try c.encode(limit, forKey: .limit)
    }
}
