import SwiftUI

struct TrackPairingSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var store = TrackPairingStore.shared

    @State private var fromSong: Song?
    @State private var toSong: Song?
    @State private var pickerRole: PickerRole?
    @State private var errorMessage: String?
    @AppStorage(TrackPairingStore.bypassAutoMixKey) private var bypassAutoMixForPairings = true

    private enum PickerRole: Identifiable {
        case from
        case to

        var id: String {
            switch self {
            case .from: return "from"
            case .to: return "to"
            }
        }

        var title: String {
            switch self {
            case .from: return "Starts With"
            case .to: return "Then Plays"
            }
        }
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: $bypassAutoMixForPairings) {
                    Label("Skip AutoMix for Pairings", systemImage: "speaker.slash")
                }
                .tint(Theme.accent)
                .onChangeCompat(of: bypassAutoMixForPairings) { _, _ in
                    appState.audioPlayer.setTransitionMode(appState.audioPlayer.transitionMode)
                }
            } footer: {
                Text("When AutoMix is on, paired tracks play as a direct handoff instead of being DJ-blended into each other.")
            }

            Section {
                songButton("Starts With", song: fromSong, systemImage: "1.circle") {
                    pickerRole = .from
                }

                songButton("Then Plays", song: toSong, systemImage: "2.circle") {
                    pickerRole = .to
                }

                Button {
                    addPairing()
                } label: {
                    Label("Add Track Pairing", systemImage: "link.badge.plus")
                }
                .disabled(fromSong == nil || toSong == nil)
            } footer: {
                Text("When the first song is queued, the second song is inserted immediately after it. Chains are supported by adding another pairing that starts with the second song.")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section("Track Pairings") {
                if store.pairings.isEmpty {
                    emptyState("No Track Pairings", systemImage: "link")
                        .listRowBackground(Theme.secondaryBackground)
                } else {
                    ForEach(store.pairings) { pairing in
                        VStack(alignment: .leading, spacing: 8) {
                            pairingSong(pairing.from, prefix: "1")
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.down")
                                    .foregroundStyle(Theme.secondaryText)
                                Text("plays next")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            .padding(.leading, 2)
                            pairingSong(pairing.to, prefix: "2")
                        }
                        .padding(.vertical, 6)
                        .swipeActions {
                            Button(role: .destructive) {
                                store.remove(pairing)
                            } label: {
                                Label(L(.action_delete), systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Track Pairings")
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .onAppear {
            store.selectServer(appState.currentServer?.id)
        }
        .sheet(item: $pickerRole, onDismiss: {
            pickerRole = nil
        }) { role in
            TrackPairingSongPicker(
                title: role.title,
                client: appState.client,
                excludedStartIDs: excludedStartIDs(for: role),
                selectedSong: selection(for: role)
            )
        }
    }

    private func songButton(_ title: String, song: Song?, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .foregroundStyle(Theme.secondaryText)
                            .font(.caption)
                        Text(song?.title ?? "Choose Song")
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(1)
                        if let song, let artist = song.artist, !artist.isEmpty {
                            Text(artist)
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
            } icon: {
                Image(systemName: systemImage)
            }
        }
        .buttonStyle(.plain)
    }

    private func pairingSong(_ song: Song, prefix: String) -> some View {
        HStack(spacing: 10) {
            Text(prefix)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.background)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text(song.artist ?? song.album ?? "Unknown Artist")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    private func emptyState(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Theme.secondaryText)
            Text(title)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func selection(for role: PickerRole) -> Binding<Song?> {
        Binding(
            get: {
                switch role {
                case .from: return fromSong
                case .to: return toSong
                }
            },
            set: { song in
                switch role {
                case .from: fromSong = song
                case .to: toSong = song
                }
                errorMessage = nil
            }
        )
    }

    private func excludedStartIDs(for role: PickerRole) -> Set<String> {
        guard role == .from else { return [] }
        return Set(store.pairings.map(\.from.id))
    }

    private func addPairing() {
        guard let fromSong, let toSong else { return }
        do {
            try store.add(from: fromSong, to: toSong)
            self.fromSong = nil
            self.toSong = nil
            errorMessage = nil
            VoltaNotificationCenter.shared.post("Track pairing added", tone: .success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct TrackPairingSongPicker: View {
    let title: String
    let client: (any MusicService)?
    let excludedStartIDs: Set<String>
    @Binding var selectedSong: Song?

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var allSongs: [Song] = []
    @State private var isLoading = false
    @State private var loadTask: Task<Void, Never>?

    private var visibleSongs: [Song] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return allSongs }
        let normalized = term.normalizedForSearch()

        return allSongs.filter { song in
            if song.title.localizedCaseInsensitiveContains(term) { return true }
            if song.artist?.localizedCaseInsensitiveContains(term) == true { return true }
            if song.album?.localizedCaseInsensitiveContains(term) == true { return true }
            guard !normalized.isEmpty else { return false }
            return song.title.normalizedForSearch().contains(normalized)
                || (song.artist?.normalizedForSearch().contains(normalized) == true)
                || (song.album?.normalizedForSearch().contains(normalized) == true)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading Library…")
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                }

                ForEach(visibleSongs) { song in
                    HStack(spacing: 12) {
                        ArtworkView(coverArtID: song.coverArt, size: 80, cornerRadius: 6)
                            .frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .foregroundStyle(Theme.primaryText)
                                .lineLimit(1)
                            Text(song.artist ?? song.album ?? "Unknown Artist")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer()
                        if selectedSong?.id == song.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !excludedStartIDs.contains(song.id) else { return }
                        selectedSong = song
                        resetLoadingState()
                        dismiss()
                    }
                    .opacity(excludedStartIDs.contains(song.id) ? 0.45 : 1)
                }

                if !isLoading, visibleSongs.isEmpty {
                    emptyState(
                        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No Songs Found" : "No Matches",
                        systemImage: "magnifyingglass"
                    )
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L(.action_cancel)) { dismiss() }
                }
            }
            .searchable(text: $query, prompt: "Search Library")
            .submitLabel(.search)
            .onSubmit(of: .search) {}
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .onAppear { loadLibraryIfNeeded() }
            .onDisappear { resetLoadingState() }
        }
    }

    private func emptyState(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Theme.secondaryText)
            Text(title)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func loadLibraryIfNeeded() {
        guard allSongs.isEmpty, loadTask == nil else { return }
        isLoading = true
        loadTask = Task {
            let songs: [Song]
            if let client {
                songs = await Self.loadAllSongs(client: client)
            } else {
                songs = DownloadService.shared.downloadedSongs()
            }

            await MainActor.run {
                guard !Task.isCancelled else { return }
                allSongs = Self.sortedUniqueSongs(HiddenAlbumStore.shared.visibleSongs(songs))
                isLoading = false
                loadTask = nil
            }
        }
    }

    private func resetLoadingState() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    private nonisolated static func loadAllSongs(client: any MusicService) async -> [Song] {
        var albums: [Album] = []
        var offset = 0
        let pageSize = 500
        while !Task.isCancelled {
            let batch = (try? await client.allAlbums(size: pageSize, offset: offset)) ?? []
            albums.append(contentsOf: batch)
            if batch.count < pageSize { break }
            offset += pageSize
            if offset > 50_000 { break }
        }

        let visibleAlbums = HiddenAlbumStore.visibleAlbums(albums)
        var songs: [Song] = []
        var seen = Set<String>()
        var index = 0
        let batchSize = 12
        while index < visibleAlbums.count, !Task.isCancelled {
            let end = min(index + batchSize, visibleAlbums.count)
            let batch = Array(visibleAlbums[index..<end])
            let songBatches = await DeveloperExperiments.runConcurrently(batch, defaultMaxConcurrent: batchSize) { album in
                (try? await client.album(id: album.id))?.song ?? album.song ?? []
            }
            for song in songBatches.flatMap({ $0 }) where seen.insert(song.id).inserted {
                songs.append(song)
            }
            index = end
        }

        return songs
    }

    private nonisolated static func sortedUniqueSongs(_ songs: [Song]) -> [Song] {
        var seen = Set<String>()
        return songs
            .filter { seen.insert($0.id).inserted }
            .sorted {
                let titleCompare = $0.title.localizedCaseInsensitiveCompare($1.title)
                if titleCompare != .orderedSame { return titleCompare == .orderedAscending }
                return ($0.artist ?? "").localizedCaseInsensitiveCompare($1.artist ?? "") == .orderedAscending
            }
    }
}
