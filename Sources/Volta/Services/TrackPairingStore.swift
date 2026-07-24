import Foundation
import Combine

struct TrackPairing: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let from: Song
    let to: Song
    let createdAt: Date

    init(id: UUID = UUID(), from: Song, to: Song, createdAt: Date = Date()) {
        self.id = id
        self.from = from
        self.to = to
        self.createdAt = createdAt
    }
}

enum TrackPairingError: LocalizedError, Equatable {
    case sameTrack
    case duplicateStart
    case circularChain

    var errorDescription: String? {
        switch self {
        case .sameTrack:
            return "Choose two different songs."
        case .duplicateStart:
            return "That song already starts a track pairing."
        case .circularChain:
            return "That pairing would create a loop."
        }
    }
}

@MainActor
final class TrackPairingStore: ObservableObject {
    static let shared = TrackPairingStore()
    nonisolated static let bypassAutoMixKey = "trackPairingsBypassAutoMix"

    @Published private(set) var pairings: [TrackPairing] = []
    @Published private(set) var serverID: String?

    private let keyPrefix = "trackPairings"

    private init() {}

    nonisolated static var bypassAutoMixEnabled: Bool {
        if UserDefaults.standard.object(forKey: bypassAutoMixKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: bypassAutoMixKey)
    }

    func selectServer(_ serverID: String?) {
        guard self.serverID != serverID else { return }
        self.serverID = serverID
        load()
    }

    func pairedSong(after song: Song) -> Song? {
        pairings.first { $0.from.id == song.id }?.to
    }

    func pairingStarting(with songID: String) -> TrackPairing? {
        pairings.first { $0.from.id == songID }
    }

    func add(from: Song, to: Song) throws {
        try validate(from: from, to: to, ignoring: nil)
        pairings.append(TrackPairing(from: from, to: to))
        save()
    }

    func remove(_ pairing: TrackPairing) {
        pairings.removeAll { $0.id == pairing.id }
        save()
    }

    func validate(from: Song, to: Song, ignoring ignoredID: UUID?) throws {
        guard from.id != to.id else { throw TrackPairingError.sameTrack }
        if pairings.contains(where: { $0.id != ignoredID && $0.from.id == from.id }) {
            throw TrackPairingError.duplicateStart
        }
        if createsCycle(fromID: from.id, toID: to.id, ignoring: ignoredID) {
            throw TrackPairingError.circularChain
        }
    }

    private func createsCycle(fromID: String, toID: String, ignoring ignoredID: UUID?) -> Bool {
        var nextByStart: [String: String] = [:]
        for pairing in pairings where pairing.id != ignoredID {
            nextByStart[pairing.from.id] = pairing.to.id
        }
        nextByStart[fromID] = toID

        var seen: Set<String> = []
        var cursor: String? = fromID
        while let id = cursor {
            if !seen.insert(id).inserted { return true }
            cursor = nextByStart[id]
        }
        return false
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([TrackPairing].self, from: data) else {
            pairings = []
            return
        }
        pairings = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pairings) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private var storageKey: String {
        guard let serverID else { return "\(keyPrefix).unscoped" }
        return "\(keyPrefix).\(serverID)"
    }
}
