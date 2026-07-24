import SwiftUI

struct AlbumInformationSheet: View {
    let album: Album

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var loadedAlbum: Album?
    @State private var isLoading = false
    @State private var loadFailed = false

    private var resolvedAlbum: Album { loadedAlbum ?? album }
    private var songs: [Song] { resolvedAlbum.song ?? album.song ?? [] }
    private var credits: [AlbumCreditSummary] { AlbumCreditSummary.build(from: songs) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        ArtworkView(coverArtID: resolvedAlbum.coverArt, size: 180, cornerRadius: 8)
                            .frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(resolvedAlbum.name)
                                .font(.headline)
                                .foregroundStyle(Theme.primaryText)
                                .lineLimit(2)
                            Text(resolvedAlbum.displayArtist)
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    infoRow(L(.media_artist), resolvedAlbum.displayArtist)
                    infoRow(L(.media_songs), displaySongCount)
                    infoRow(L(.media_duration), resolvedAlbum.duration.map(formatDuration))
                    infoRow(L(.media_year), resolvedAlbum.year.map(String.init))
                    infoRow(L(.media_genre), resolvedAlbum.genre)
                    infoRow(L(.media_plays), resolvedAlbum.playCount.map(String.init))
                    infoRow(L(.media_added), resolvedAlbum.createdDate?.formatted(date: .abbreviated, time: .omitted))
                    infoRow(L(.media_label), resolvedAlbum.recordLabel)
                } header: {
                    Text("Album")
                }

                if let comment = resolvedAlbum.comment?.nonBlank {
                    Section("Description") {
                        Text(comment)
                            .font(.body)
                            .foregroundStyle(Theme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section(L(.media_songs)) {
                    if isLoading && songs.isEmpty {
                        ProgressView()
                    } else if songs.isEmpty {
                        Text(loadFailed ? L(.notif_couldnt_load_album) : L(.search_no_results, resolvedAlbum.name))
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            songRow(song, fallbackIndex: index + 1)
                        }
                    }
                }

                if !credits.isEmpty {
                    Section("Credits") {
                        ForEach(credits) { credit in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(credit.role)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.primaryText)
                                Text(credit.names.joined(separator: ", "))
                                    .font(.footnote)
                                    .foregroundStyle(Theme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(credit.trackCount) track\(credit.trackCount == 1 ? "" : "s")")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.secondaryText.opacity(0.8))
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Album Information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L(.action_done)) { dismiss() }
                }
            }
        }
        .preferredColorScheme(Theme.colorScheme)
        .presentationDetents([.medium, .large])
        .task(id: album.id) { await loadAlbumIfNeeded() }
    }

    private var displaySongCount: String? {
        if !songs.isEmpty { return String(songs.count) }
        return resolvedAlbum.songCount.map(String.init)
    }

    @ViewBuilder
    private func infoRow(_ title: String, _ value: String?) -> some View {
        if let value = value?.nonBlank {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer(minLength: 24)
                Text(value)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func songRow(_ song: Song, fallbackIndex: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(trackNumber(for: song, fallbackIndex: fallbackIndex))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 34, alignment: .trailing)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                if let composer = song.displayComposer?.nonBlank {
                    Text("Composer: \(composer)")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2)
                } else if let contributor = primaryContributorName(for: song) {
                    Text(contributor)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let duration = song.duration {
                Text(shortDuration(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 2)
            }
        }
    }

    private func primaryContributorName(for song: Song) -> String? {
        guard let contributor = song.contributors?.first,
              let name = contributor.artist?.name?.nonBlank else {
            return nil
        }
        let role = contributor.role?.nonBlank ?? "Contributor"
        return "\(role): \(name)"
    }

    private func loadAlbumIfNeeded() async {
        guard loadedAlbum == nil,
              album.song?.isEmpty != false,
              let client = appState.client else {
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            loadedAlbum = try await client.album(id: album.id)
            loadFailed = loadedAlbum == nil
        } catch {
            loadFailed = true
            AppLogger.shared.log("Album information load failed: \(error.localizedDescription)", category: .library, level: .error)
        }
    }

    private func trackNumber(for song: Song, fallbackIndex: Int) -> String {
        if let disc = song.discNumber, disc > 1, let track = song.track {
            return "\(disc)-\(track)"
        }
        return String(song.track ?? fallbackIndex)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h) hr \(m) min" }
        return "\(m) min"
    }

    private func shortDuration(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

private struct AlbumCreditSummary: Identifiable {
    let id: String
    let role: String
    let names: [String]
    let trackCount: Int

    static func build(from songs: [Song]) -> [AlbumCreditSummary] {
        struct Aggregate {
            var names = Set<String>()
            var tracks = Set<String>()
        }

        var grouped: [String: Aggregate] = [:]

        func add(role: String, name: String, songID: String) {
            let cleanRole = role.nonBlank ?? "Contributor"
            guard let cleanName = name.nonBlank else { return }
            var aggregate = grouped[cleanRole] ?? Aggregate()
            aggregate.names.insert(cleanName)
            aggregate.tracks.insert(songID)
            grouped[cleanRole] = aggregate
        }

        for song in songs {
            if let composer = song.displayComposer?.nonBlank {
                for name in composer.split(separator: ",").map({ String($0).trimmingCharacters(in: .whitespacesAndNewlines) }) {
                    add(role: "Composer", name: name, songID: song.id)
                }
            }

            for contributor in song.contributors ?? [] {
                let roleParts = [contributor.role?.nonBlank, contributor.subRole?.nonBlank].compactMap { $0 }
                let role = roleParts.isEmpty ? "Contributor" : roleParts.joined(separator: " - ")
                if let name = contributor.artist?.name?.nonBlank ?? contributor.artist?.id?.nonBlank {
                    add(role: role, name: name, songID: song.id)
                }
            }
        }

        return grouped.map { role, aggregate in
            AlbumCreditSummary(
                id: role,
                role: role,
                names: aggregate.names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending },
                trackCount: aggregate.tracks.count
            )
        }
        .sorted { lhs, rhs in
            let priority = ["Composer": 0, "Lyricist": 1, "Producer": 2, "Engineer": 3, "Mixer": 4]
            let lp = priority[lhs.role] ?? 100
            let rp = priority[rhs.role] ?? 100
            if lp != rp { return lp < rp }
            return lhs.role.localizedCaseInsensitiveCompare(rhs.role) == .orderedAscending
        }
    }
}
