import SwiftUI

extension SettingsView {
    // MARK: - Library

    @ViewBuilder
    var librarySection: some View {
        let s = "Library"
        if sectionVisible(s, [["home", "home tab", "customize home", "sections", "section order"], ["custom sorting", "saved sorts", "saved views", "smart filters", "library views", "albums", "songs", "sort", "group", "filters"], ["rating", "ratings", "stars", "favorite", "favourite", "love"]]) {
            Section {
                if rowVisible(s, ["home", "home tab", "customize home", "sections", "section order"]) {
                    SettingsDetailNavigationLink(.homeCustomization) {
                        Label(L(.home_customize), systemImage: "rectangle.3.group")
                    }
                    .foregroundStyle(Theme.primaryText)
                }

                if rowVisible(s, ["custom sorting", "saved sorts", "saved views", "smart filters", "library views", "albums", "songs", "sort", "group", "filters"]) {
                    SettingsDetailNavigationLink(.savedLibrarySorts) {
                        Label(L(.library_views_title), systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .foregroundStyle(Theme.primaryText)
                }
            } header: {
                Text(sectionTitle(s))
            } footer: {
                Text(L(.library_view_settings_footer))
            }
            .listRowBackground(Theme.secondaryBackground)

            if rowVisible(s, ["rating", "ratings", "stars", "favorite", "favourite", "love"]) {
                RatingModeSettingsRow()
                    .listRowBackground(Theme.secondaryBackground)
            }
        }
    }
}

private struct RatingModeSettingsRow: View {
    @AppStorage(RatingMode.storageKey) private var modeRaw = RatingMode.favorite.rawValue

    var body: some View {
        Section {
            Picker("Menu Action", selection: $modeRaw) {
                ForEach(RatingMode.allCases) { mode in
                    Text(mode.settingsLabel).tag(mode.rawValue)
                }
            }
            .tint(Theme.accent)
        } header: {
            Text("Ratings")
        } footer: {
            Text("Choose the existing favorite or love action, or rate songs and albums from 1 to 5 stars in their more menus.")
        }
    }
}

struct SavedLibrarySortsSettingsView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                Section {
                    ForEach(SavedLibrarySortTarget.allCases) { target in
                        NavigationLink {
                            SavedLibrarySortTargetSettingsView(target: target)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(target.label)
                                        .foregroundStyle(Theme.primaryText)
                                    Text(target == .albums ? L(.library_view_album_filters_grouping) : L(.library_view_song_filters_grouping))
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                            } icon: {
                                Image(systemName: target == .albums ? "square.grid.2x2" : "music.note.list")
                            }
                        }
                    }
                } footer: {
                    Text(L(.library_view_target_footer))
                }
                .listRowBackground(Theme.secondaryBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle(L(.library_views_title))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
        }
        .preferredColorScheme(Theme.colorScheme)
    }
}

struct SavedLibrarySortTargetSettingsView: View {
    @StateObject private var store = SavedLibrarySortStore.shared
    @State private var editorContext: SavedLibrarySortEditorContext?

    let target: SavedLibrarySortTarget

    private var targetSorts: [SavedLibrarySort] {
        store.sorts(for: target)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                Section {
                    Button {
                        editorContext = SavedLibrarySortEditorContext(target: target, sort: nil)
                    } label: {
                        Label(L(.library_view_create), systemImage: "plus.circle")
                    }
                    .foregroundStyle(Theme.primaryText)
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    if targetSorts.isEmpty {
                        Text(target == .albums ? L(.library_view_no_saved_album_views) : L(.library_view_no_saved_song_views))
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        ForEach(targetSorts) { sort in
                            Button {
                                editorContext = SavedLibrarySortEditorContext(target: target, sort: sort)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(sort.name)
                                        .foregroundStyle(Theme.primaryText)
                                    Text(sort.ruleSummary)
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    store.delete(sort)
                                } label: {
                                    Label(L(.action_delete), systemImage: Symbols.trash)
                                }
                            }
                        }
                        .onMove { source, destination in
                            store.move(source, to: destination, target: target)
                        }
                    }
                } header: {
                    Text(L(.library_views_saved))
                }
                .listRowBackground(Theme.secondaryBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle(target.label)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .sheet(item: $editorContext) { context in
            NavigationStack {
                SavedLibrarySortEditorView(
                    target: context.target,
                    sort: context.sort
                ) { sort in
                    store.upsert(sort)
                }
            }
        }
        .preferredColorScheme(Theme.colorScheme)
    }
}
