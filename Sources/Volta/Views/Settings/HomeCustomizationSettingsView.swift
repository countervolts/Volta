import SwiftUI

struct HomeCustomizationSettingsView: View {
    @StateObject private var store = HomeSectionPreferencesStore.shared

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                Section {
                    ForEach(store.orderedSections) { section in
                        Toggle(isOn: Binding(
                            get: { store.isVisible(section) },
                            set: { store.setVisible($0, for: section) }
                        )) {
                            Label(section.label, systemImage: section.icon)
                        }
                        .tint(Theme.accent)
                        // Keep at least one section visible so Home cannot
                        // accidentally become an empty screen.
                        .disabled(store.visibleSectionCount == 1 && store.isVisible(section))
                    }
                    .onMove(perform: store.move)
                } header: {
                    HStack {
                        Text(L(.home_sections))
                        Spacer()
                        Text(L(.home_layout_visible, store.visibleSectionCount, HomeSection.allCases.count))
                            .textCase(nil)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                } footer: {
                    Text(L(.home_sections_footer))
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    NavigationLink {
                        HomeMixCustomizationSettingsView()
                    } label: {
                        LabeledContent {
                            Text(L(.home_mix_sources_enabled, store.enabledMixSourceCount, HomeMixSource.allCases.count))
                                .foregroundStyle(Theme.secondaryText)
                        } label: {
                            Label(L(.home_mix_customize), systemImage: "slider.horizontal.3")
                        }
                    }
                    .foregroundStyle(Theme.primaryText)
                } header: {
                    Text(L(.home_mixes))
                } footer: {
                    Text(L(.home_mixes_footer))
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    Button(L(.home_reset_layout)) {
                        store.reset()
                    }
                    .foregroundStyle(Theme.accent)
                }
                .listRowBackground(Theme.secondaryBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle(L(.home_customize))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .preferredColorScheme(Theme.colorScheme)
    }
}

struct HomeMixCustomizationSettingsView: View {
    @StateObject private var store = HomeSectionPreferencesStore.shared

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                Section {
                    ForEach(HomeMixSource.allCases) { source in
                        Toggle(isOn: Binding(
                            get: { store.isMixEnabled(source) },
                            set: { store.setMixEnabled($0, for: source) }
                        )) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.label)
                                    Text(source.detail)
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                            } icon: {
                                Image(systemName: source.icon)
                            }
                        }
                        .tint(Theme.accent)
                    }
                } header: {
                    Text(L(.home_mix_sources))
                } footer: {
                    Text(L(.home_mix_sources_footer))
                }
                .listRowBackground(Theme.secondaryBackground)

                if store.isMixEnabled(.genres) || store.isMixEnabled(.artists) {
                    Section {
                        if store.isMixEnabled(.genres) {
                            Stepper(
                                value: Binding(
                                    get: { store.mixPreferences.genreMixCount },
                                    set: { store.setGenreMixCount($0) }
                                ),
                                in: HomeMixPreferences.mixCountRange
                            ) {
                                LabeledContent {
                                    Text("\(store.mixPreferences.genreMixCount)")
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.secondaryText)
                                } label: {
                                    Text(L(.home_mix_genre_count))
                                }
                            }
                        }

                        if store.isMixEnabled(.artists) {
                            Stepper(
                                value: Binding(
                                    get: { store.mixPreferences.artistMixCount },
                                    set: { store.setArtistMixCount($0) }
                                ),
                                in: HomeMixPreferences.mixCountRange
                            ) {
                                LabeledContent {
                                    Text("\(store.mixPreferences.artistMixCount)")
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.secondaryText)
                                } label: {
                                    Text(L(.home_mix_artist_count))
                                }
                            }
                        }
                    } header: {
                        Text(L(.home_mixes))
                    }
                    .listRowBackground(Theme.secondaryBackground)
                }

                Section {
                    Picker(selection: Binding(
                        get: { store.mixPreferences.length },
                        set: { store.setMixLength($0) }
                    )) {
                        ForEach(HomeMixLength.allCases) { length in
                            Text(length.label).tag(length)
                        }
                    } label: {
                        Label(L(.home_mix_length), systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                    .tint(Theme.accent)
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    Button(L(.home_mix_reset)) {
                        store.resetMixes()
                    }
                    .foregroundStyle(Theme.accent)
                }
                .listRowBackground(Theme.secondaryBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle(L(.home_mix_customize))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
        }
        .preferredColorScheme(Theme.colorScheme)
    }
}
