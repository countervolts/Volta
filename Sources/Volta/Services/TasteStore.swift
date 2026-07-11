import Foundation
import Combine

enum TasteState: String, Codable, Sendable {
    case neutral
    case loved
    case disliked
}

@MainActor
final class TasteStore: ObservableObject {
    static let shared = TasteStore()

    private static let lovedKey = "lovedSongIDs"
    private static let dislikedKey = "dislikedSongIDs"

    @Published private(set) var lovedIDs: Set<String>
    @Published private(set) var dislikedIDs: Set<String>

    private init() {
        lovedIDs = Set(UserDefaults.standard.stringArray(forKey: Self.lovedKey) ?? [])
        dislikedIDs = Set(UserDefaults.standard.stringArray(forKey: Self.dislikedKey) ?? [])
    }

    func state(for songID: String) -> TasteState {
        if lovedIDs.contains(songID) { return .loved }
        if dislikedIDs.contains(songID) { return .disliked }
        return .neutral
    }

    func toggleLove(_ songID: String) {
        if lovedIDs.contains(songID) {
            lovedIDs.remove(songID)
        } else {
            lovedIDs.insert(songID)
            dislikedIDs.remove(songID)
        }
        save()
    }

    func toggleDislike(_ songID: String) {
        if dislikedIDs.contains(songID) {
            dislikedIDs.remove(songID)
        } else {
            dislikedIDs.insert(songID)
            lovedIDs.remove(songID)
        }
        save()
    }

    private func save() {
        UserDefaults.standard.set(Array(lovedIDs), forKey: Self.lovedKey)
        UserDefaults.standard.set(Array(dislikedIDs), forKey: Self.dislikedKey)
    }
}
