import Foundation
import Combine

/// Owns the materialized contents of dynamic playlists. Library merging,
/// filtering, sorting, and limiting all happen on a worker so SwiftUI only
/// publishes the finished snapshot.
@MainActor
final class SmartPlaylistResults: ObservableObject {
    @Published private(set) var songsByPlaylistID: [String: [Song]] = [:]
    @Published private(set) var isEvaluating = false

    private var generation = 0

    func songs(for playlistID: String) -> [Song] {
        songsByPlaylistID[playlistID] ?? []
    }

    func refresh(
        playlists: [SmartPlaylist],
        librarySongs: [Song],
        downloadedSongs: [Song],
        context: SmartPlaylistEvaluationContext
    ) async {
        generation &+= 1
        let requestedGeneration = generation
        isEvaluating = true

        let resolved = await DeveloperExperiments.runSync(priority: .userInitiated) {
            var seen = Set<String>()
            let source = (downloadedSongs + librarySongs).filter {
                seen.insert($0.id).inserted
            }

            var values: [String: [Song]] = [:]
            values.reserveCapacity(playlists.count)
            for playlist in playlists {
                values[playlist.id] = playlist.resolve(from: source, context: context)
            }
            return values
        }

        guard requestedGeneration == generation, !Task.isCancelled else { return }
        songsByPlaylistID = resolved
        isEvaluating = false
    }
}
