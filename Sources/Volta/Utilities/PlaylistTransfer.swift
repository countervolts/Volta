import Foundation

// portable playlist file: name + comment + ordered song ids
struct ExportedPlaylist: Codable, Sendable {
    let name: String
    let comment: String?
    let songIDs: [String]
}

// Exports all server playlists to a JSON file and re-creates them from one.
// Songs are matched by their server id, so import targets the same library.
enum PlaylistTransfer {
    static func exportURL(client: SubsonicClient) async throws -> URL {
        let playlists = try await client.playlists()
        var exported: [ExportedPlaylist] = []
        for playlist in playlists {
            let full = try? await client.playlist(id: playlist.id)
            let ids = full?.entry?.map(\.id) ?? playlist.entry?.map(\.id) ?? []
            exported.append(ExportedPlaylist(
                name: playlist.name,
                comment: (full?.comment ?? playlist.comment),
                songIDs: ids
            ))
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("volta-playlists-\(Int(Date().timeIntervalSince1970)).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(exported).write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    static func importPlaylists(from url: URL, client: SubsonicClient) async throws -> Int {
        let data = try Data(contentsOf: url)
        let imported = try JSONDecoder().decode([ExportedPlaylist].self, from: data)
        var created = 0
        for playlist in imported {
            guard let newPlaylist = try await client.createPlaylist(name: playlist.name) else { continue }
            for songID in playlist.songIDs {
                try? await client.addToPlaylist(playlistID: newPlaylist.id, songID: songID)
            }
            if let comment = playlist.comment, !comment.isEmpty {
                try? await client.updatePlaylistComment(playlistID: newPlaylist.id, comment: comment)
            }
            created += 1
        }
        return created
    }
}
