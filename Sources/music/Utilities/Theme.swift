import SwiftUI

// central design tokens. colors defined in code so they resolve regardless
// of bundle, with the asset catalog AccentColor mirroring `accent`.
enum Theme {
    static let background = Color.black
    static let secondaryBackground = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.6)
    static let error = Color(red: 0.95, green: 0.26, blue: 0.30)

    // accent resolves live from the user's chosen palette name (AppStorage
    // "accentColorName"). any view body that re-evaluates picks up the change.
    static var accent: Color { accentColor(named: currentAccentName) }

    static var currentAccentName: String {
        UserDefaults.standard.string(forKey: "accentColorName") ?? "purple"
    }

    static let accentNames = ["purple", "blue", "pink", "orange", "green"]

    static func accentColor(named name: String) -> Color {
        switch name {
        case "blue":   return Color(red: 0.20, green: 0.52, blue: 0.96)
        case "pink":   return Color(red: 0.96, green: 0.28, blue: 0.62)
        case "orange": return Color(red: 0.98, green: 0.55, blue: 0.20)
        case "green":  return Color(red: 0.20, green: 0.78, blue: 0.45)
        default:       return Color(red: 0.55, green: 0.36, blue: 0.96) // purple
        }
    }

    enum Layout {
        static let screenPadding: CGFloat = 20
        static let sectionSpacing: CGFloat = 30
        static let cardCorner: CGFloat = 12
        static let gridSpacing: CGFloat = 16
    }
}
