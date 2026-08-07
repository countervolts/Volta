import Foundation

enum SavedLibrarySortTarget: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case albums
    case songs

    var id: String { rawValue }

    @MainActor
    var label: String {
        switch self {
        case .albums: return L(.library_view_albums)
        case .songs: return L(.library_view_songs)
        }
    }

    @MainActor
    var singularLabel: String {
        switch self {
        case .albums: return L(.library_view_album)
        case .songs: return L(.library_view_song)
        }
    }

    var defaultRules: [SavedLibrarySortRule] {
        [SavedLibrarySortRule(field: .name, direction: .ascending)]
    }
}

enum SavedLibraryRuleMatchMode: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case all
    case any

    var id: String { rawValue }

    @MainActor
    var label: String {
        switch self {
        case .all: return L(.library_view_all_filters)
        case .any: return L(.library_view_any_filter)
        }
    }
}

enum SavedLibrarySortDirection: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case ascending
    case descending

    var id: String { rawValue }

    @MainActor
    var label: String {
        switch self {
        case .ascending: return L(.library_view_ascending)
        case .descending: return L(.library_view_descending)
        }
    }

    var shortLabel: String {
        switch self {
        case .ascending: return "A-Z"
        case .descending: return "Z-A"
        }
    }
}

enum SavedLibrarySortField: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case name
    case artist
    case album
    case albumArtist
    case year
    case genre
    case duration
    case playCount
    case recentlyAdded
    case songCount
    case discNumber
    case trackNumber
    case bitRate
    case fileSize

    var id: String { rawValue }

    @MainActor
    func label(for target: SavedLibrarySortTarget) -> String {
        switch self {
        case .name:
            return target == .albums ? L(.library_view_album_name) : L(.library_view_song_title)
        case .artist:
            return L(.media_artist)
        case .album:
            return L(.media_album)
        case .albumArtist:
            return L(.library_view_album_artist)
        case .year:
            return L(.media_year)
        case .genre:
            return L(.library_view_tag_genre)
        case .duration:
            return L(.media_duration)
        case .playCount:
            return L(.media_play_count)
        case .recentlyAdded:
            return L(.home_recently_added)
        case .songCount:
            return L(.library_view_song_count)
        case .discNumber:
            return L(.library_view_disc_number)
        case .trackNumber:
            return L(.library_view_track_number)
        case .bitRate:
            return L(.detail_bitrate)
        case .fileSize:
            return L(.media_file_size)
        }
    }

    func isSupported(for target: SavedLibrarySortTarget) -> Bool {
        switch (target, self) {
        case (.albums, .name), (.albums, .artist), (.albums, .year), (.albums, .genre),
             (.albums, .duration), (.albums, .playCount), (.albums, .recentlyAdded),
             (.albums, .songCount):
            return true
        case (.songs, .name), (.songs, .artist), (.songs, .album), (.songs, .albumArtist),
             (.songs, .year), (.songs, .genre), (.songs, .duration), (.songs, .playCount),
             (.songs, .discNumber), (.songs, .trackNumber), (.songs, .bitRate),
             (.songs, .fileSize):
            return true
        default:
            return false
        }
    }

    static func fields(for target: SavedLibrarySortTarget) -> [SavedLibrarySortField] {
        allCases.filter { $0.isSupported(for: target) }
    }
}

enum SavedLibraryFilterField: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case title
    case artist
    case album
    case albumArtist
    case tag
    case year
    case duration
    case playCount
    case songCount
    case downloaded
    case lossless
    case hiRes
    case explicit
    case starred
    case bitRate
    case fileSize

    var id: String { rawValue }

    @MainActor
    func label(for target: SavedLibrarySortTarget) -> String {
        switch self {
        case .title:
            return target == .albums ? L(.library_view_album_name) : L(.library_view_song_title)
        case .artist:
            return L(.media_artist)
        case .album:
            return L(.media_album)
        case .albumArtist:
            return L(.library_view_album_artist)
        case .tag:
            return L(.library_view_tag_genre)
        case .year:
            return L(.media_year)
        case .duration:
            return L(.library_view_duration_minutes)
        case .playCount:
            return L(.media_play_count)
        case .songCount:
            return L(.library_view_song_count)
        case .downloaded:
            return L(.library_view_downloaded)
        case .lossless:
            return L(.library_view_lossless)
        case .hiRes:
            return L(.library_view_hires)
        case .explicit:
            return L(.library_view_explicit)
        case .starred:
            return L(.library_view_starred)
        case .bitRate:
            return L(.library_view_bitrate_kbps)
        case .fileSize:
            return L(.library_view_file_size_mb)
        }
    }

    var valueKind: SavedLibraryFilterValueKind {
        switch self {
        case .title, .artist, .album, .albumArtist, .tag:
            return .text
        case .year, .duration, .playCount, .songCount, .bitRate, .fileSize:
            return .number
        case .downloaded, .lossless, .hiRes, .explicit, .starred:
            return .boolean
        }
    }

    func isSupported(for target: SavedLibrarySortTarget) -> Bool {
        switch (target, self) {
        case (.albums, .title), (.albums, .artist), (.albums, .tag), (.albums, .year),
             (.albums, .duration), (.albums, .playCount), (.albums, .songCount),
             (.albums, .starred):
            return true
        case (.songs, .title), (.songs, .artist), (.songs, .album), (.songs, .albumArtist),
             (.songs, .tag), (.songs, .year), (.songs, .duration), (.songs, .playCount),
             (.songs, .downloaded), (.songs, .lossless), (.songs, .hiRes), (.songs, .explicit),
             (.songs, .starred), (.songs, .bitRate), (.songs, .fileSize):
            return true
        default:
            return false
        }
    }

    static func fields(for target: SavedLibrarySortTarget) -> [SavedLibraryFilterField] {
        allCases.filter { $0.isSupported(for: target) }
    }
}

enum SavedLibraryFilterValueKind: Equatable, Sendable {
    case text
    case number
    case boolean
}

enum SavedLibraryFilterComparison: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case contains
    case equals
    case doesNotContain
    case atLeast
    case atMost
    case between
    case isSet
    case isMissing
    case isTrue
    case isFalse

    var id: String { rawValue }

    @MainActor
    var label: String {
        switch self {
        case .contains: return L(.library_filter_contains)
        case .equals: return L(.library_filter_is)
        case .doesNotContain: return L(.library_filter_does_not_contain)
        case .atLeast: return L(.library_filter_at_least)
        case .atMost: return L(.library_filter_at_most)
        case .between: return L(.library_filter_between)
        case .isSet: return L(.library_filter_is_set)
        case .isMissing: return L(.library_filter_is_missing)
        case .isTrue: return L(.action_yes)
        case .isFalse: return L(.action_no)
        }
    }

    var needsPrimaryValue: Bool {
        switch self {
        case .contains, .equals, .doesNotContain, .atLeast, .atMost, .between:
            return true
        case .isSet, .isMissing, .isTrue, .isFalse:
            return false
        }
    }

    var needsSecondaryValue: Bool {
        self == .between
    }

    static func comparisons(for field: SavedLibraryFilterField) -> [SavedLibraryFilterComparison] {
        switch field.valueKind {
        case .text:
            return [.contains, .equals, .doesNotContain, .isSet, .isMissing]
        case .number:
            return [.atLeast, .atMost, .between, .equals, .isSet, .isMissing]
        case .boolean:
            return [.isTrue, .isFalse]
        }
    }
}

enum SavedLibraryGroupMode: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case none
    case artist
    case album
    case albumArtist
    case tag
    case year
    case decade
    case duration
    case playCount

    var id: String { rawValue }

    @MainActor
    func label(for target: SavedLibrarySortTarget) -> String {
        switch self {
        case .none:
            return L(.library_view_none)
        case .artist:
            return L(.media_artist)
        case .album:
            return L(.media_album)
        case .albumArtist:
            return L(.library_view_album_artist)
        case .tag:
            return L(.library_view_tag_genre)
        case .year:
            return L(.media_year)
        case .decade:
            return L(.library_view_decade)
        case .duration:
            return L(.media_duration)
        case .playCount:
            return L(.media_play_count)
        }
    }

    func isSupported(for target: SavedLibrarySortTarget) -> Bool {
        switch (target, self) {
        case (_, .none), (.albums, .artist), (.albums, .tag), (.albums, .year),
             (.albums, .decade), (.albums, .duration), (.albums, .playCount):
            return true
        case (.songs, .artist), (.songs, .album), (.songs, .albumArtist), (.songs, .tag),
             (.songs, .year), (.songs, .decade), (.songs, .duration), (.songs, .playCount):
            return true
        default:
            return false
        }
    }

    static func modes(for target: SavedLibrarySortTarget) -> [SavedLibraryGroupMode] {
        allCases.filter { $0.isSupported(for: target) }
    }
}

struct SavedLibrarySortRule: Identifiable, Hashable, Codable, Sendable {
    var id: String = UUID().uuidString
    var field: SavedLibrarySortField
    var direction: SavedLibrarySortDirection

    init(field: SavedLibrarySortField, direction: SavedLibrarySortDirection) {
        self.field = field
        self.direction = direction
    }
}

struct SavedLibraryFilterRule: Identifiable, Hashable, Codable, Sendable {
    var id: String = UUID().uuidString
    var field: SavedLibraryFilterField
    var comparison: SavedLibraryFilterComparison
    var value: String
    var secondaryValue: String

    init(
        field: SavedLibraryFilterField,
        comparison: SavedLibraryFilterComparison? = nil,
        value: String = "",
        secondaryValue: String = ""
    ) {
        self.field = field
        self.comparison = comparison ?? SavedLibraryFilterComparison.comparisons(for: field).first ?? .contains
        self.value = value
        self.secondaryValue = secondaryValue
    }

    var comparisonIsValid: Bool {
        SavedLibraryFilterComparison.comparisons(for: field).contains(comparison)
    }
}

struct SavedLibraryFilterGroup: Identifiable, Hashable, Codable, Sendable {
    var id: String = UUID().uuidString
    var matchMode: SavedLibraryRuleMatchMode
    var filters: [SavedLibraryFilterRule]

    init(
        matchMode: SavedLibraryRuleMatchMode = .all,
        filters: [SavedLibraryFilterRule] = []
    ) {
        self.matchMode = matchMode
        self.filters = filters
    }
}

struct SavedLibrarySort: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var name: String
    var target: SavedLibrarySortTarget
    var onlyFavorites: Bool
    var hideSmallAlbums: Bool
    var filterMatchMode: SavedLibraryRuleMatchMode
    var filters: [SavedLibraryFilterRule]
    var groups: [SavedLibraryFilterGroup]
    var groupMode: SavedLibraryGroupMode
    var rules: [SavedLibrarySortRule]

    init(
        id: String = UUID().uuidString,
        name: String,
        target: SavedLibrarySortTarget,
        onlyFavorites: Bool = false,
        hideSmallAlbums: Bool = false,
        filterMatchMode: SavedLibraryRuleMatchMode = .all,
        filters: [SavedLibraryFilterRule] = [],
        groups: [SavedLibraryFilterGroup] = [],
        groupMode: SavedLibraryGroupMode = .none,
        rules: [SavedLibrarySortRule]? = nil
    ) {
        self.id = id
        self.name = name
        self.target = target
        self.onlyFavorites = onlyFavorites
        self.hideSmallAlbums = hideSmallAlbums
        self.filterMatchMode = filterMatchMode
        self.filters = filters
        self.groups = groups
        self.groupMode = groupMode.isSupported(for: target) ? groupMode : .none
        self.rules = rules ?? target.defaultRules
    }

    @MainActor
    static func draft(target: SavedLibrarySortTarget) -> SavedLibrarySort {
        SavedLibrarySort(
            name: target == .albums ? L(.library_view_custom_album) : L(.library_view_custom_song),
            target: target,
            rules: target.defaultRules
        )
    }

    @MainActor
    var ruleSummary: String {
        var parts: [String] = []
        if onlyFavorites { parts.append(L(.library_view_summary_favorites)) }
        if hideSmallAlbums, target == .albums { parts.append(L(.library_view_summary_no_small_albums)) }
        if !activeFilters.isEmpty {
            parts.append(
                activeFilters.count == 1
                    ? L(.library_view_summary_filter_count_one)
                    : L(.library_view_summary_filter_count_many, activeFilters.count)
            )
        }
        if !activeGroups.isEmpty {
            parts.append(
                activeGroups.count == 1
                    ? L(.library_view_summary_group_count_one)
                    : L(.library_view_summary_group_count_many, activeGroups.count)
            )
        }
        if groupMode != .none, groupMode.isSupported(for: target) {
            parts.append(L(.library_view_summary_grouped_by, groupMode.label(for: target)))
        }

        let sortPart = activeSortRules.prefix(2)
            .map { "\($0.field.label(for: target)) \($0.direction.shortLabel)" }
            .joined(separator: ", ")
        if !sortPart.isEmpty {
            parts.append(sortPart)
        }

        return parts.isEmpty ? L(.library_view_no_rules) : parts.joined(separator: " · ")
    }

    var activeSortRules: [SavedLibrarySortRule] {
        rules.filter { $0.field.isSupported(for: target) }
    }

    var activeFilters: [SavedLibraryFilterRule] {
        filters.filter { filter in
            filter.field.isSupported(for: target) && filter.comparisonIsValid
        }
    }

    var activeGroups: [SavedLibraryFilterGroup] {
        groups.compactMap { group in
            let filters = group.filters.filter { filter in
                filter.field.isSupported(for: target) && filter.comparisonIsValid
            }
            guard !filters.isEmpty else { return nil }
            var normalized = group
            normalized.filters = filters
            return normalized
        }
    }

    var usesAlbumAlphabetSections: Bool {
        groupMode == .none
            && target == .albums
            && firstSupportedRule?.field == .name
            && firstSupportedRule?.direction == .ascending
    }

    var usesSongAlphabetSections: Bool {
        groupMode == .none
            && target == .songs
            && firstSupportedRule?.field == .name
            && firstSupportedRule?.direction == .ascending
    }

    @MainActor
    func matchesAlbum(_ album: Album) -> Bool {
        if onlyFavorites && Self.nonBlank(album.starred) == nil { return false }
        if hideSmallAlbums && (album.songCount ?? 0) < 3 { return false }
        return matches(
            directFilters: activeFilters,
            groups: activeGroups,
            evaluator: { filter in
            Self.matchesAlbum(album, filter: filter)
            }
        )
    }

    @MainActor
    func matchesSong(_ song: Song) -> Bool {
        if onlyFavorites && Self.nonBlank(song.starred) == nil { return false }
        return matches(
            directFilters: activeFilters,
            groups: activeGroups,
            evaluator: { filter in
            Self.matchesSong(song, filter: filter)
            }
        )
    }

    func sortedAlbums(_ albums: [Album]) -> [Album] {
        let validRules = activeSortRules
        guard !validRules.isEmpty else {
            return albums.sorted { Self.compareText($0.name, $1.name, direction: .ascending) == .orderedAscending }
        }

        return albums.sorted { lhs, rhs in
            for rule in validRules {
                let comparison = Self.albumComparison(lhs, rhs, rule: rule)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            }
            return Self.albumFallbackComparison(lhs, rhs) == .orderedAscending
        }
    }

    func sortedSongs(_ songs: [Song]) -> [Song] {
        let validRules = activeSortRules
        guard !validRules.isEmpty else {
            return songs.sorted { Self.compareText($0.title, $1.title, direction: .ascending) == .orderedAscending }
        }

        return songs.sorted { lhs, rhs in
            for rule in validRules {
                let comparison = Self.songComparison(lhs, rhs, rule: rule)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            }
            return Self.songFallbackComparison(lhs, rhs) == .orderedAscending
        }
    }

    @MainActor
    func groupLabel(for album: Album) -> String {
        switch groupMode {
        case .none:
            return ""
        case .artist:
            return Self.nonBlank(album.artist) ?? L(.library_view_unknown_artist)
        case .tag:
            return Self.nonBlank(album.genre) ?? L(.library_view_no_tag)
        case .year:
            return album.year.map(String.init) ?? L(.library_view_unknown_year)
        case .decade:
            return album.year.map { "\(($0 / 10) * 10)s" } ?? L(.library_view_unknown_decade)
        case .duration:
            return Self.durationBucket(album.duration)
        case .playCount:
            return Self.playCountBucket(album.playCount)
        case .album, .albumArtist:
            return ""
        }
    }

    @MainActor
    func groupLabel(for song: Song) -> String {
        switch groupMode {
        case .none:
            return ""
        case .artist:
            return Self.nonBlank(song.artist) ?? L(.library_view_unknown_artist)
        case .album:
            return Self.nonBlank(song.album) ?? L(.library_view_unknown_album)
        case .albumArtist:
            return Self.nonBlank(song.albumArtist) ?? L(.library_view_unknown_album_artist)
        case .tag:
            return Self.nonBlank(song.genre) ?? L(.library_view_no_tag)
        case .year:
            return song.year.map(String.init) ?? L(.library_view_unknown_year)
        case .decade:
            return song.year.map { "\(($0 / 10) * 10)s" } ?? L(.library_view_unknown_decade)
        case .duration:
            return Self.durationBucket(song.duration)
        case .playCount:
            return Self.playCountBucket(song.playCount)
        }
    }

    private var firstSupportedRule: SavedLibrarySortRule? {
        activeSortRules.first
    }

    @MainActor
    private func matches(
        directFilters: [SavedLibraryFilterRule],
        groups: [SavedLibraryFilterGroup],
        evaluator: (SavedLibraryFilterRule) -> Bool
    ) -> Bool {
        let directResults = directFilters.map(evaluator)
        let groupResults = groups.map { group in
            let results = group.filters.map(evaluator)
            switch group.matchMode {
            case .all:
                return results.allSatisfy { $0 }
            case .any:
                return results.contains(true)
            }
        }
        let results = directResults + groupResults
        guard !results.isEmpty else { return true }
        switch filterMatchMode {
        case .all:
            return results.allSatisfy { $0 }
        case .any:
            return results.contains(true)
        }
    }

    @MainActor
    private static func matchesAlbum(_ album: Album, filter: SavedLibraryFilterRule) -> Bool {
        switch filter.field.valueKind {
        case .text:
            return matchText(albumText(album, field: filter.field), filter: filter)
        case .number:
            return matchNumber(albumNumber(album, field: filter.field), filter: filter)
        case .boolean:
            return matchBool(albumBool(album, field: filter.field), filter: filter)
        }
    }

    @MainActor
    private static func matchesSong(_ song: Song, filter: SavedLibraryFilterRule) -> Bool {
        switch filter.field.valueKind {
        case .text:
            return matchText(songText(song, field: filter.field), filter: filter)
        case .number:
            return matchNumber(songNumber(song, field: filter.field), filter: filter)
        case .boolean:
            return matchBool(songBool(song, field: filter.field), filter: filter)
        }
    }

    private static func matchText(_ text: String?, filter: SavedLibraryFilterRule) -> Bool {
        let value = normalizedText(filter.value)
        let text = normalizedText(text)
        switch filter.comparison {
        case .contains:
            guard let text, let value else { return false }
            return text.localizedCaseInsensitiveContains(value)
        case .equals:
            guard let text, let value else { return false }
            return text.localizedCaseInsensitiveCompare(value) == .orderedSame
        case .doesNotContain:
            guard let value else { return true }
            return text?.localizedCaseInsensitiveContains(value) != true
        case .isSet:
            return text != nil
        case .isMissing:
            return text == nil
        case .atLeast, .atMost, .between, .isTrue, .isFalse:
            return true
        }
    }

    private static func matchNumber(_ number: Double?, filter: SavedLibraryFilterRule) -> Bool {
        let first = Double(filter.value.trimmingCharacters(in: .whitespacesAndNewlines))
        let second = Double(filter.secondaryValue.trimmingCharacters(in: .whitespacesAndNewlines))
        switch filter.comparison {
        case .atLeast:
            guard let number, let first else { return false }
            return number >= first
        case .atMost:
            guard let number, let first else { return false }
            return number <= first
        case .between:
            guard let number, let first, let second else { return false }
            return number >= min(first, second) && number <= max(first, second)
        case .equals:
            guard let number, let first else { return false }
            return number == first
        case .isSet:
            return number != nil
        case .isMissing:
            return number == nil
        case .contains, .doesNotContain, .isTrue, .isFalse:
            return true
        }
    }

    @MainActor
    private static func matchBool(_ value: Bool, filter: SavedLibraryFilterRule) -> Bool {
        switch filter.comparison {
        case .isTrue:
            return value
        case .isFalse:
            return !value
        case .contains, .equals, .doesNotContain, .atLeast, .atMost, .between, .isSet, .isMissing:
            return true
        }
    }

    private static func albumText(_ album: Album, field: SavedLibraryFilterField) -> String? {
        switch field {
        case .title:
            return album.name
        case .artist:
            return album.artist
        case .tag:
            return album.genre
        case .album, .albumArtist, .year, .duration, .playCount, .songCount, .downloaded,
             .lossless, .hiRes, .explicit, .starred, .bitRate, .fileSize:
            return nil
        }
    }

    private static func songText(_ song: Song, field: SavedLibraryFilterField) -> String? {
        switch field {
        case .title:
            return song.title
        case .artist:
            return song.artist
        case .album:
            return song.album
        case .albumArtist:
            return song.albumArtist
        case .tag:
            return song.genre
        case .year, .duration, .playCount, .songCount, .downloaded, .lossless, .hiRes,
             .explicit, .starred, .bitRate, .fileSize:
            return nil
        }
    }

    private static func albumNumber(_ album: Album, field: SavedLibraryFilterField) -> Double? {
        switch field {
        case .year:
            return album.year.map(Double.init)
        case .duration:
            return album.duration.map { Double($0) / 60.0 }
        case .playCount:
            return album.playCount.map(Double.init)
        case .songCount:
            return album.songCount.map(Double.init)
        case .title, .artist, .album, .albumArtist, .tag, .downloaded, .lossless, .hiRes,
             .explicit, .starred, .bitRate, .fileSize:
            return nil
        }
    }

    private static func albumBool(_ album: Album, field: SavedLibraryFilterField) -> Bool {
        switch field {
        case .starred:
            return nonBlank(album.starred) != nil
        case .title, .artist, .album, .albumArtist, .tag, .year, .duration, .playCount,
             .songCount, .downloaded, .lossless, .hiRes, .explicit, .bitRate, .fileSize:
            return false
        }
    }

    private static func songNumber(_ song: Song, field: SavedLibraryFilterField) -> Double? {
        switch field {
        case .year:
            return song.year.map(Double.init)
        case .duration:
            return song.duration.map { Double($0) / 60.0 }
        case .playCount:
            return song.playCount.map(Double.init)
        case .bitRate:
            return song.bitRate.map(Double.init)
        case .fileSize:
            return song.size.map { Double($0) / 1_048_576.0 }
        case .title, .artist, .album, .albumArtist, .tag, .songCount, .downloaded,
             .lossless, .hiRes, .explicit, .starred:
            return nil
        }
    }

    @MainActor
    private static func songBool(_ song: Song, field: SavedLibraryFilterField) -> Bool {
        switch field {
        case .downloaded:
            return DownloadService.shared.state(for: song) == .downloaded
        case .lossless:
            return song.isLossless
        case .hiRes:
            return song.isHiResLossless
        case .explicit:
            return song.isExplicit
        case .starred:
            return nonBlank(song.starred) != nil
        case .title, .artist, .album, .albumArtist, .tag, .year, .duration, .playCount,
             .songCount, .bitRate, .fileSize:
            return false
        }
    }

    private static func albumComparison(_ lhs: Album, _ rhs: Album, rule: SavedLibrarySortRule) -> ComparisonResult {
        switch rule.field {
        case .name:
            return compareText(lhs.name, rhs.name, direction: rule.direction)
        case .artist:
            return compareOptionalText(lhs.artist, rhs.artist, direction: rule.direction)
        case .year:
            return compareOptionalValues(lhs.year, rhs.year, direction: rule.direction)
        case .genre:
            return compareOptionalText(lhs.genre, rhs.genre, direction: rule.direction)
        case .duration:
            return compareValues(lhs.duration ?? 0, rhs.duration ?? 0, direction: rule.direction)
        case .playCount:
            return compareValues(lhs.playCount ?? 0, rhs.playCount ?? 0, direction: rule.direction)
        case .recentlyAdded:
            return compareOptionalValues(lhs.createdDate, rhs.createdDate, direction: rule.direction)
        case .songCount:
            return compareValues(lhs.songCount ?? 0, rhs.songCount ?? 0, direction: rule.direction)
        case .album, .albumArtist, .discNumber, .trackNumber, .bitRate, .fileSize:
            return .orderedSame
        }
    }

    private static func songComparison(_ lhs: Song, _ rhs: Song, rule: SavedLibrarySortRule) -> ComparisonResult {
        switch rule.field {
        case .name:
            return compareText(lhs.title, rhs.title, direction: rule.direction)
        case .artist:
            return compareOptionalText(lhs.artist, rhs.artist, direction: rule.direction)
        case .album:
            return compareOptionalText(lhs.album, rhs.album, direction: rule.direction)
        case .albumArtist:
            return compareOptionalText(lhs.albumArtist, rhs.albumArtist, direction: rule.direction)
        case .year:
            return compareOptionalValues(lhs.year, rhs.year, direction: rule.direction)
        case .genre:
            return compareOptionalText(lhs.genre, rhs.genre, direction: rule.direction)
        case .duration:
            return compareValues(lhs.duration ?? 0, rhs.duration ?? 0, direction: rule.direction)
        case .playCount:
            return compareValues(lhs.playCount ?? 0, rhs.playCount ?? 0, direction: rule.direction)
        case .discNumber:
            return compareValues(lhs.discNumber ?? 0, rhs.discNumber ?? 0, direction: rule.direction)
        case .trackNumber:
            return compareValues(lhs.track ?? 0, rhs.track ?? 0, direction: rule.direction)
        case .bitRate:
            return compareValues(lhs.bitRate ?? 0, rhs.bitRate ?? 0, direction: rule.direction)
        case .fileSize:
            return compareValues(lhs.size ?? 0, rhs.size ?? 0, direction: rule.direction)
        case .recentlyAdded, .songCount:
            return .orderedSame
        }
    }

    private static func albumFallbackComparison(_ lhs: Album, _ rhs: Album) -> ComparisonResult {
        let name = compareText(lhs.name, rhs.name, direction: .ascending)
        if name != .orderedSame { return name }
        return compareText(lhs.id, rhs.id, direction: .ascending)
    }

    private static func songFallbackComparison(_ lhs: Song, _ rhs: Song) -> ComparisonResult {
        let title = compareText(lhs.title, rhs.title, direction: .ascending)
        if title != .orderedSame { return title }
        return compareText(lhs.id, rhs.id, direction: .ascending)
    }

    private static func compareText(
        _ lhs: String,
        _ rhs: String,
        direction: SavedLibrarySortDirection
    ) -> ComparisonResult {
        directed(lhs.localizedCaseInsensitiveCompare(rhs), direction: direction)
    }

    private static func compareOptionalText(
        _ lhs: String?,
        _ rhs: String?,
        direction: SavedLibrarySortDirection
    ) -> ComparisonResult {
        let left = normalizedText(lhs)
        let right = normalizedText(rhs)
        switch (left, right) {
        case (nil, nil):
            return .orderedSame
        case (nil, _):
            return .orderedDescending
        case (_, nil):
            return .orderedAscending
        case let (left?, right?):
            return compareText(left, right, direction: direction)
        }
    }

    private static func compareValues<T: Comparable>(
        _ lhs: T,
        _ rhs: T,
        direction: SavedLibrarySortDirection
    ) -> ComparisonResult {
        let result: ComparisonResult
        if lhs < rhs {
            result = .orderedAscending
        } else if lhs > rhs {
            result = .orderedDescending
        } else {
            result = .orderedSame
        }
        return directed(result, direction: direction)
    }

    private static func compareOptionalValues<T: Comparable>(
        _ lhs: T?,
        _ rhs: T?,
        direction: SavedLibrarySortDirection
    ) -> ComparisonResult {
        switch (lhs, rhs) {
        case (nil, nil):
            return .orderedSame
        case (nil, _):
            return .orderedDescending
        case (_, nil):
            return .orderedAscending
        case let (lhs?, rhs?):
            return compareValues(lhs, rhs, direction: direction)
        }
    }

    private static func directed(
        _ result: ComparisonResult,
        direction: SavedLibrarySortDirection
    ) -> ComparisonResult {
        guard direction == .descending else { return result }
        switch result {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }

    @MainActor
    private static func durationBucket(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return L(.library_view_unknown_duration) }
        let minutes = seconds / 60
        switch minutes {
        case ..<3: return L(.library_view_duration_under_3)
        case 3..<5: return L(.library_view_duration_3_5)
        case 5..<10: return L(.library_view_duration_5_10)
        case 10..<30: return L(.library_view_duration_10_30)
        case 30..<60: return L(.library_view_duration_30_60)
        default: return L(.library_view_duration_over_60)
        }
    }

    @MainActor
    private static func playCountBucket(_ count: Int?) -> String {
        guard let count else { return L(.library_view_unknown_plays) }
        switch count {
        case 0: return L(.library_view_plays_never)
        case 1..<5: return L(.library_view_plays_1_4)
        case 5..<20: return L(.library_view_plays_5_19)
        default: return L(.library_view_plays_20_plus)
        }
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func nonBlank(_ value: String?) -> String? {
        normalizedText(value)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, target, onlyFavorites, hideSmallAlbums, filterMatchMode, filters, groups, groupMode, rules
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? "Custom Library View"
        target = (try? c.decode(SavedLibrarySortTarget.self, forKey: .target)) ?? .albums
        onlyFavorites = (try? c.decode(Bool.self, forKey: .onlyFavorites)) ?? false
        hideSmallAlbums = (try? c.decode(Bool.self, forKey: .hideSmallAlbums)) ?? false
        filterMatchMode = (try? c.decode(SavedLibraryRuleMatchMode.self, forKey: .filterMatchMode)) ?? .all
        filters = (try? c.decode([SavedLibraryFilterRule].self, forKey: .filters)) ?? []
        groups = (try? c.decode([SavedLibraryFilterGroup].self, forKey: .groups)) ?? []
        let decodedGroup = (try? c.decode(SavedLibraryGroupMode.self, forKey: .groupMode)) ?? .none
        groupMode = decodedGroup.isSupported(for: target) ? decodedGroup : .none
        rules = (try? c.decode([SavedLibrarySortRule].self, forKey: .rules)) ?? target.defaultRules
    }
}
