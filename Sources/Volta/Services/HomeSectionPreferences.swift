import SwiftUI

enum HomeSection: String, CaseIterable, Codable, Hashable, Identifiable {
    case picks
    case recentlyPlayed
    case artists
    case moreLike
    case discover
    case recentlyAdded

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .picks: return "sparkles"
        case .recentlyPlayed: return "clock.arrow.circlepath"
        case .artists: return "music.mic"
        case .moreLike: return "wand.and.stars"
        case .discover: return "safari"
        case .recentlyAdded: return "plus.circle"
        }
    }

    @MainActor
    var label: String {
        switch self {
        case .picks: return L(.home_picks_for_you)
        case .recentlyPlayed: return L(.home_recently_played)
        case .artists: return L(.home_artists)
        case .moreLike: return L(.home_more_like_this)
        case .discover: return L(.home_discover)
        case .recentlyAdded: return L(.home_recently_added)
        }
    }
}

/// The mix families that can be surfaced in Picks for You.
enum HomeMixSource: String, CaseIterable, Codable, Hashable, Identifiable {
    case discovery
    case heavyRotation
    case genres
    case artists

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .discovery: return "safari"
        case .heavyRotation: return "repeat"
        case .genres: return "guitars"
        case .artists: return "music.mic"
        }
    }

    @MainActor
    var label: String {
        switch self {
        case .discovery: return L(.home_discovery_station)
        case .heavyRotation: return L(.home_heavy_rotation)
        case .genres: return L(.home_mix_genres)
        case .artists: return L(.home_mix_artists)
        }
    }

    @MainActor
    var detail: String {
        switch self {
        case .discovery: return L(.home_discovery_station_subtitle)
        case .heavyRotation: return L(.home_heavy_rotation_subtitle)
        case .genres: return L(.home_mix_genres_detail)
        case .artists: return L(.home_mix_artists_detail)
        }
    }
}

enum HomeMixLength: String, CaseIterable, Codable, Hashable, Identifiable {
    case short
    case standard
    case long

    var id: String { rawValue }

    var songRange: ClosedRange<Int> {
        switch self {
        case .short: return 15...25
        case .standard: return 20...50
        case .long: return 40...70
        }
    }

    @MainActor
    var label: String {
        switch self {
        case .short: return L(.home_mix_length_short)
        case .standard: return L(.home_mix_length_standard)
        case .long: return L(.home_mix_length_long)
        }
    }

    func songCount(available: Int, rng: inout SeededRNG) -> Int {
        let upperBound = min(available, songRange.upperBound)
        let lowerBound = min(upperBound, max(10, songRange.lowerBound))
        return Int.random(in: lowerBound...upperBound, using: &rng)
    }
}

struct HomeMixPreferences: Codable, Equatable {
    static let mixCountRange = 1...4

    static func boundedMixCount(_ count: Int) -> Int {
        min(max(count, mixCountRange.lowerBound), mixCountRange.upperBound)
    }

    var enabledSources: Set<HomeMixSource>
    var genreMixCount: Int
    var artistMixCount: Int
    var length: HomeMixLength

    static let `default` = HomeMixPreferences(
        enabledSources: Set(HomeMixSource.allCases),
        genreMixCount: 2,
        artistMixCount: 2,
        length: .standard
    )

    func isEnabled(_ source: HomeMixSource) -> Bool {
        enabledSources.contains(source)
    }
}

private struct HomeSectionPreferences: Codable {
    var order: [HomeSection]
    var hidden: Set<HomeSection>
    var mixPreferences: HomeMixPreferences

    static let `default` = HomeSectionPreferences(
        order: HomeSection.allCases,
        hidden: [],
        mixPreferences: .default
    )

    private enum CodingKeys: String, CodingKey {
        case order
        case hidden
        case mixPreferences
    }

    init(
        order: [HomeSection],
        hidden: Set<HomeSection>,
        mixPreferences: HomeMixPreferences
    ) {
        self.order = order
        self.hidden = hidden
        self.mixPreferences = mixPreferences
    }

    // Existing installs only have `order` and `hidden`. Decode those saved
    // layouts without resetting them when mix controls are introduced.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        order = try container.decodeIfPresent([HomeSection].self, forKey: .order) ?? HomeSection.allCases
        hidden = try container.decodeIfPresent(Set<HomeSection>.self, forKey: .hidden) ?? []
        mixPreferences = try container.decodeIfPresent(HomeMixPreferences.self, forKey: .mixPreferences) ?? .default
    }
}

@MainActor
final class HomeSectionPreferencesStore: ObservableObject {
    static let shared = HomeSectionPreferencesStore()
    nonisolated static let storageKey = "homeSectionPreferences"

    @Published private var preferences: HomeSectionPreferences

    private init() {
        let decoded = UserDefaults.standard.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(HomeSectionPreferences.self, from: $0) }
        preferences = Self.normalized(decoded ?? .default)
    }

    var orderedSections: [HomeSection] { preferences.order }

    var visibleSections: [HomeSection] {
        preferences.order.filter { !preferences.hidden.contains($0) }
    }

    var visibleSectionCount: Int { visibleSections.count }

    var mixPreferences: HomeMixPreferences { preferences.mixPreferences }

    var enabledMixSourceCount: Int { preferences.mixPreferences.enabledSources.count }

    func isVisible(_ section: HomeSection) -> Bool {
        !preferences.hidden.contains(section)
    }

    func setVisible(_ visible: Bool, for section: HomeSection) {
        guard visible || visibleSectionCount > 1 else { return }
        if visible {
            preferences.hidden.remove(section)
        } else {
            preferences.hidden.insert(section)
        }
        save()
    }

    func isMixEnabled(_ source: HomeMixSource) -> Bool {
        preferences.mixPreferences.isEnabled(source)
    }

    func setMixEnabled(_ enabled: Bool, for source: HomeMixSource) {
        if enabled {
            preferences.mixPreferences.enabledSources.insert(source)
        } else {
            preferences.mixPreferences.enabledSources.remove(source)
        }
        save()
    }

    func setGenreMixCount(_ count: Int) {
        preferences.mixPreferences.genreMixCount = HomeMixPreferences.boundedMixCount(count)
        save()
    }

    func setArtistMixCount(_ count: Int) {
        preferences.mixPreferences.artistMixCount = HomeMixPreferences.boundedMixCount(count)
        save()
    }

    func setMixLength(_ length: HomeMixLength) {
        preferences.mixPreferences.length = length
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        preferences.order.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func reset() {
        preferences.order = HomeSection.allCases
        preferences.hidden = []
        save()
    }

    func resetMixes() {
        preferences.mixPreferences = .default
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func normalized(_ raw: HomeSectionPreferences) -> HomeSectionPreferences {
        var seen = Set<HomeSection>()
        var order = raw.order.filter { seen.insert($0).inserted }
        for section in HomeSection.allCases where seen.insert(section).inserted {
            order.append(section)
        }
        var hidden = raw.hidden.intersection(Set(HomeSection.allCases))
        // A layout with no visible section would make Home look broken, and can be produced by a backup from an older build.
        if hidden.count == HomeSection.allCases.count {
            hidden.remove(.picks)
        }

        var mixPreferences = raw.mixPreferences
        mixPreferences.enabledSources.formIntersection(Set(HomeMixSource.allCases))
        mixPreferences.genreMixCount = HomeMixPreferences.boundedMixCount(mixPreferences.genreMixCount)
        mixPreferences.artistMixCount = HomeMixPreferences.boundedMixCount(mixPreferences.artistMixCount)

        return HomeSectionPreferences(
            order: order,
            hidden: hidden,
            mixPreferences: mixPreferences
        )
    }
}
