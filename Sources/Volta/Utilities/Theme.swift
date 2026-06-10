import SwiftUI

enum Theme {
    // app theme: "dark" (default), "amoled" (pure black), "light"
    static var themeMode: String { UserDefaults.standard.string(forKey: "themeMode") ?? "dark" }

    static var background: Color {
        switch themeMode {
        case "light":  return Color(red: 0.95, green: 0.95, blue: 0.96)
        case "amoled": return .black
        default:       return .black
        }
    }

    static var secondaryBackground: Color {
        switch themeMode {
        case "light":  return .white
        case "amoled": return Color(red: 0.03, green: 0.03, blue: 0.035)
        default:       return Color(red: 0.07, green: 0.07, blue: 0.08)
        }
    }

    static var primaryText: Color {
        switch themeMode {
        case "light":  return Color(red: 0.08, green: 0.08, blue: 0.10)
        default:       return .white
        }
    }

    static var secondaryText: Color {
        switch themeMode {
        case "light":  return Color.black.opacity(0.55)
        default:       return Color.white.opacity(0.6)
        }
    }

    static var colorScheme: ColorScheme { themeMode == "light" ? .light : .dark }

    static let error = Color(red: 0.95, green: 0.26, blue: 0.30)

    static var accent: Color { accentColor(named: currentAccentName) }

    static var currentAccentName: String {
        UserDefaults.standard.string(forKey: "accentColorName") ?? "purple"
    }

    static let accentNames = ["purple", "blue", "indigo", "teal", "green", "yellow", "orange", "red", "pink"]

    static func accentColor(named name: String) -> Color {
        if name == "custom" { return customAccentColor }
        switch name {
        case "blue":   return Color(red: 0.20, green: 0.52, blue: 0.96)
        case "indigo": return Color(red: 0.35, green: 0.34, blue: 0.84)
        case "teal":   return Color(red: 0.18, green: 0.68, blue: 0.71)
        case "pink":   return Color(red: 0.96, green: 0.28, blue: 0.62)
        case "orange": return Color(red: 0.98, green: 0.55, blue: 0.20)
        case "yellow": return Color(red: 0.98, green: 0.78, blue: 0.18)
        case "red":    return Color(red: 0.94, green: 0.27, blue: 0.27)
        case "green":  return Color(red: 0.20, green: 0.78, blue: 0.45)
        default:       return Color(red: 0.55, green: 0.36, blue: 0.96)
        }
    }

    static var customAccentColor: Color {
        let defaults = UserDefaults.standard
        let r = defaults.object(forKey: "customAccentRed") as? Double ?? 0.55
        let g = defaults.object(forKey: "customAccentGreen") as? Double ?? 0.36
        let b = defaults.object(forKey: "customAccentBlue") as? Double ?? 0.96
        return Color(red: r, green: g, blue: b)
    }

    enum Layout {
        static let screenPadding: CGFloat = 20
        static let sectionSpacing: CGFloat = 30
        static let cardCorner: CGFloat = 12
        static let gridSpacing: CGFloat = 16
    }
}
