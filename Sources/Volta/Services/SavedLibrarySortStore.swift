import Foundation
import Combine

@MainActor
final class SavedLibrarySortStore: ObservableObject {
    static let shared = SavedLibrarySortStore()

    nonisolated static let key = "savedLibrarySorts"
    @Published private(set) var sorts: [SavedLibrarySort] = []

    private init() {
        reload()
    }

    func reload() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([SavedLibrarySort].self, from: data) else {
            sorts = []
            return
        }
        sorts = decoded
    }

    func sorts(for target: SavedLibrarySortTarget) -> [SavedLibrarySort] {
        sorts.filter { $0.target == target }
    }

    func upsert(_ sort: SavedLibrarySort) {
        if let index = sorts.firstIndex(where: { $0.id == sort.id }) {
            sorts[index] = sort
        } else {
            sorts.append(sort)
        }
        save()
    }

    func delete(_ sort: SavedLibrarySort) {
        sorts.removeAll { $0.id == sort.id }
        save()
    }

    func move(_ source: IndexSet, to destination: Int, target: SavedLibrarySortTarget) {
        var targetSorts = sorts(for: target)
        let sourceIndexes = source.sorted()
        let moving = sourceIndexes.map { targetSorts[$0] }
        for index in sourceIndexes.reversed() {
            targetSorts.remove(at: index)
        }

        var adjustedDestination = destination
        for index in sourceIndexes where index < destination {
            adjustedDestination -= 1
        }
        targetSorts.insert(contentsOf: moving, at: min(adjustedDestination, targetSorts.count))

        let otherSorts = sorts.filter { $0.target != target }
        sorts = otherSorts + targetSorts
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sorts) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
