import Foundation
import Observation

// App UI languages. English is the default and fallback.
//
// To add a language, add the case here and fill its column in `Strings.table`.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english    = "en"
    case spanish    = "es"
    case french     = "fr"
    case german     = "de"
    case portuguese = "pt"
    case italian    = "it"
    case dutch      = "nl"
    case russian    = "ru"
    case polish     = "pl"
    case turkish    = "tr"
    case swedish    = "sv"
    case norwegian  = "nb"
    case danish     = "da"
    case finnish    = "fi"
    case chinese    = "zh-Hans"
    case japanese   = "ja"
    case korean     = "ko"

    var id: String { rawValue }

    // Shown in the picker in its own language.
    var endonym: String {
        switch self {
        case .english:    return "English"
        case .spanish:    return "Español"
        case .french:     return "Français"
        case .german:     return "Deutsch"
        case .portuguese: return "Português"
        case .italian:    return "Italiano"
        case .dutch:      return "Nederlands"
        case .russian:    return "Русский"
        case .polish:     return "Polski"
        case .turkish:    return "Türkçe"
        case .swedish:    return "Svenska"
        case .norwegian:  return "Norsk"
        case .danish:     return "Dansk"
        case .finnish:    return "Suomi"
        case .chinese:    return "简体中文"
        case .japanese:   return "日本語"
        case .korean:     return "한국어"
        }
    }
}

// Selected language + string lookup.
@MainActor
@Observable
final class LocalizationManager {
    static let shared = LocalizationManager()

    static let storageKey = "appLanguage"

    var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        }
    }

    private init() {
        // Fresh installs start in English.
        let stored = UserDefaults.standard.string(forKey: Self.storageKey)
        language = stored.flatMap(AppLanguage.init(rawValue:)) ?? .english
    }

    func string(for key: LocKey) -> String {
        let row = Strings.table[key]
        return row?[language] ?? row?[.english] ?? key.rawValue
    }
}

// View shorthand. Calling through here keeps SwiftUI watching the language setting.
@MainActor
func L(_ key: LocKey, _ arguments: CVarArg...) -> String {
    let format = LocalizationManager.shared.string(for: key)
    guard !arguments.isEmpty else { return format }
    return String(format: format, arguments: arguments)
}
