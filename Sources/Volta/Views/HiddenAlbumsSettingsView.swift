import SwiftUI

private enum HiddenAlbumListSort: String, CaseIterable, Identifiable {
    case visibleFirst
    case hiddenFirst

    var id: String { rawValue }

    var titleKey: LocKey {
        switch self {
        case .visibleFirst: return .hidden_albums_sort_visible_first
        case .hiddenFirst: return .hidden_albums_sort_hidden_first
        }
    }
}

struct HiddenAlbumsSettingsView: View {
    let client: (any MusicService)?

    @State private var hiddenAlbums = HiddenAlbumStore.shared
    @State private var albums: [Album] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var sort = HiddenAlbumListSort.visibleFirst
    @State private var errorMessage: String?

    private var filteredAlbums: [Album] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var list = albums
        if !q.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(q) ||
                ($0.artist ?? "").localizedCaseInsensitiveContains(q)
            }
        }
        return list.sorted { lhs, rhs in
            let lhsHidden = hiddenAlbums.isHidden(lhs)
            let rhsHidden = hiddenAlbums.isHidden(rhs)
            if lhsHidden != rhsHidden {
                return sort == .hiddenFirst ? lhsHidden : !lhsHidden
            }
            let artistCompare = lhs.displayArtist.localizedCaseInsensitiveCompare(rhs.displayArtist)
            if artistCompare != .orderedSame { return artistCompare == .orderedAscending }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                Section {
                    Picker(L(.hidden_albums_sort), selection: $sort) {
                        ForEach(HiddenAlbumListSort.allCases) { option in
                            Text(L(option.titleKey)).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    if isLoading && albums.isEmpty {
                        ProgressView()
                            .tint(Theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else if filteredAlbums.isEmpty {
                        Text(searchText.isEmpty ? L(.hidden_albums_empty) : L(.hidden_albums_no_matches))
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else {
                        ForEach(filteredAlbums) { album in
                            albumRow(album)
                        }
                    }
                } header: {
                    Text(L(.hidden_albums_count, hiddenAlbums.hiddenAlbumIDs.count))
                }
                .listRowBackground(Theme.secondaryBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle(L(.appearance_hidden_albums))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: L(.hidden_albums_search))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        hiddenAlbums.hide(albumIDs: filteredAlbums.map(\.id))
                    } label: {
                        Label(L(.hidden_albums_hide_visible), systemImage: "eye.slash")
                    }
                    .disabled(filteredAlbums.isEmpty)

                    Button {
                        hiddenAlbums.unhide(albumIDs: filteredAlbums.map(\.id))
                    } label: {
                        Label(L(.hidden_albums_show_visible), systemImage: "eye")
                    }
                    .disabled(filteredAlbums.isEmpty)

                    Divider()

                    Button(role: .destructive) {
                        hiddenAlbums.unhideAll()
                    } label: {
                        Label(L(.hidden_albums_show_all), systemImage: "checkmark.circle")
                    }
                    .disabled(hiddenAlbums.hiddenAlbumIDs.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .preferredColorScheme(Theme.colorScheme)
        .task(id: client?.config.baseURL.absoluteString ?? "no-client") {
            await loadAlbums()
        }
    }

    private func albumRow(_ album: Album) -> some View {
        let hidden = hiddenAlbums.isHidden(album)
        return Button {
            hiddenAlbums.toggle(album)
        } label: {
            HStack(spacing: 12) {
                ArtworkView(coverArtID: album.coverArt, size: 120, cornerRadius: 6)
                    .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text(album.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(2)
                    Text(albumSubtitle(album))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: hidden ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(hidden ? Theme.accent : Theme.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    private func albumSubtitle(_ album: Album) -> String {
        if let year = album.year {
            return "\(album.displayArtist) - \(year)"
        }
        return album.displayArtist
    }

    private func loadAlbums() async {
        guard let client else {
            albums = []
            errorMessage = L(.hidden_albums_no_server)
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var loaded: [Album] = []
        var offset = 0
        let size = 500
        while true {
            let batch = (try? await client.allAlbums(size: size, offset: offset)) ?? []
            loaded.append(contentsOf: batch)
            if batch.count < size { break }
            offset += size
            if offset > 20_000 { break }
        }

        hiddenAlbums.register(albums: loaded)
        albums = loaded
        if loaded.isEmpty {
            errorMessage = nil
        }
    }
}
