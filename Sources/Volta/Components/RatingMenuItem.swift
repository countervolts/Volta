import SwiftUI

enum RatingMode: String, CaseIterable, Identifiable {
    case favorite
    case stars

    static let storageKey = "ratingMode"

    var id: String { rawValue }

    var settingsLabel: String {
        switch self {
        case .favorite: return "Favorite / Love"
        case .stars: return "1–5 Star Ratings"
        }
    }
}

@MainActor
final class RatingStore: ObservableObject {
    static let shared = RatingStore()

    private static let ratingsKey = "mediaStarRatings"

    @Published private(set) var ratings: [String: Int]

    private init() {
        ratings = UserDefaults.standard.dictionary(forKey: Self.ratingsKey)?
            .reduce(into: [:]) { result, entry in
                if let value = entry.value as? Int, (1...5).contains(value) {
                    result[entry.key] = value
                }
            } ?? [:]
    }

    func rating(for itemID: String, kind: RatingItemKind) -> Int {
        ratings[key(for: itemID, kind: kind)] ?? 0
    }

    func setRating(_ rating: Int, for itemID: String, kind: RatingItemKind) {
        let key = key(for: itemID, kind: kind)
        if (1...5).contains(rating) {
            ratings[key] = rating
        } else {
            ratings.removeValue(forKey: key)
        }
        UserDefaults.standard.set(ratings, forKey: Self.ratingsKey)
    }

    private func key(for itemID: String, kind: RatingItemKind) -> String {
        "\(kind.rawValue):\(itemID)"
    }
}

enum RatingItemKind: String {
    case song
    case album
}

/// A single menu item that keeps the old favourite action available, or swaps it
/// for a nested 1–5-star picker when the user selects Ratings in Settings.
struct RatingMenuItem: View {
    let itemID: String
    let kind: RatingItemKind
    let favoriteLabel: String
    let favoriteSymbol: String
    let favoriteAction: () -> Void

    @AppStorage(RatingMode.storageKey) private var modeRaw = RatingMode.favorite.rawValue
    @StateObject private var ratings = RatingStore.shared

    private var mode: RatingMode { RatingMode(rawValue: modeRaw) ?? .favorite }
    private var currentRating: Int { ratings.rating(for: itemID, kind: kind) }

    var body: some View {
        if mode == .stars {
            Menu {
                ForEach(1...5, id: \.self) { rating in
                    Button {
                        ratings.setRating(rating, for: itemID, kind: kind)
                    } label: {
                        Label(starLabel(rating), systemImage: rating == currentRating ? "star.fill" : "star")
                    }
                }

                if currentRating > 0 {
                    Divider()
                    Button(role: .destructive) {
                        ratings.setRating(0, for: itemID, kind: kind)
                    } label: {
                        Label("Clear Rating", systemImage: "xmark")
                    }
                }
            } label: {
                Label(ratingMenuLabel, systemImage: currentRating > 0 ? "star.fill" : "star")
            }
        } else {
            Button(action: favoriteAction) {
                Label(favoriteLabel, systemImage: favoriteSymbol)
            }
        }
    }

    private var ratingMenuLabel: String {
        currentRating == 0 ? "Rate" : "Rated \(currentRating) \(currentRating == 1 ? "Star" : "Stars")"
    }

    private func starLabel(_ rating: Int) -> String {
        "\(rating) \(rating == 1 ? "Star" : "Stars")"
    }
}
