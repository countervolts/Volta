import Combine
import Foundation

enum PlayerQuickAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case lyrics
    case output
    case visualizer
    case sleepTimer
    case queue
    case shuffle
    case repeatMode
    case autoplay
    case transition
    case equalizer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lyrics: return "Lyrics"
        case .output: return "Output"
        case .visualizer: return "Visualizer"
        case .sleepTimer: return "Sleep Timer"
        case .queue: return "Queue"
        case .shuffle: return "Shuffle"
        case .repeatMode: return "Repeat"
        case .autoplay: return "Autoplay"
        case .transition: return "Transitions"
        case .equalizer: return "Equalizer"
        }
    }

    var icon: String {
        switch self {
        case .lyrics: return Symbols.lyricsInactive
        case .output: return Symbols.airplay
        case .visualizer: return Symbols.visualizer
        case .sleepTimer: return Symbols.sleep
        case .queue: return Symbols.queue
        case .shuffle: return Symbols.shuffle
        case .repeatMode: return Symbols.repeatAll
        case .autoplay: return "infinity"
        case .transition: return "arrow.left.arrow.right"
        case .equalizer: return "slider.vertical.3"
        }
    }
}

@MainActor
final class PlayerControlPreferences: ObservableObject {
    static let shared = PlayerControlPreferences()

    static let maximumVisibleControls = 5
    static let minimumVisibleControls = 3
    static let defaultActions: [PlayerQuickAction] = [.lyrics, .output, .visualizer, .sleepTimer, .queue]

    @Published private(set) var visibleActions: [PlayerQuickAction] = []

    private static let storageKey = "playerQuickActionOrder"

    private init() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.storageKey) ?? []
        visibleActions = Self.normalized(stored.compactMap(PlayerQuickAction.init(rawValue:)))
    }

    var hiddenActions: [PlayerQuickAction] {
        PlayerQuickAction.allCases.filter { !visibleActions.contains($0) }
    }

    var canAdd: Bool { visibleActions.count < Self.maximumVisibleControls }
    var canRemove: Bool { visibleActions.count > Self.minimumVisibleControls }

    func move(from offsets: IndexSet, to destination: Int) {
        visibleActions.move(fromOffsets: offsets, toOffset: destination)
        save()
    }

    func add(_ action: PlayerQuickAction) {
        guard canAdd, !visibleActions.contains(action) else { return }
        visibleActions.append(action)
        save()
    }

    func remove(_ action: PlayerQuickAction) {
        guard canRemove else { return }
        visibleActions.removeAll { $0 == action }
        save()
    }

    func reset() {
        visibleActions = Self.defaultActions
        save()
    }

    private func save() {
        UserDefaults.standard.set(visibleActions.map(\.rawValue), forKey: Self.storageKey)
    }

    private static func normalized(_ actions: [PlayerQuickAction]) -> [PlayerQuickAction] {
        var seen = Set<PlayerQuickAction>()
        let unique = actions.filter { seen.insert($0).inserted }
        guard unique.count >= minimumVisibleControls else { return defaultActions }
        return Array(unique.prefix(maximumVisibleControls))
    }
}
