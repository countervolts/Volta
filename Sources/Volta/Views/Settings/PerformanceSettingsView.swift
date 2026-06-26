import SwiftUI

extension SettingsView {
    // MARK: - Performance

    @ViewBuilder
    var performanceSection: some View {
        let s = "Performance"
        if sectionVisible(s, [["performance mode", "battery", "power save", "saver", "low power"], ["image loading", "images", "speed", "power", "threads", "fast", "conservative"], ["data caching", "cache", "aggressive", "memory"], ["prefetch artist images", "prefetch", "artist", "profile", "pictures"]]) {
            Section {
                if rowVisible(s, ["performance mode", "battery", "power save", "saver", "low power"]) {
                    NavigationLink(value: SettingsRoute.performanceMode) {
                        Label("Performance Mode", systemImage: "bolt.badge.a")
                    }
                    .foregroundStyle(Theme.primaryText)
                }

                if rowVisible(s, ["image loading", "images", "speed", "power", "threads", "fast", "conservative"]) {
                    Picker(selection: $imageLoadMode) {
                        Text("Fast").tag("fast")
                        Text("Balanced").tag("balanced")
                        Text("Conservative").tag("conservative")
                    } label: {
                        Label("Image Loading", systemImage: "bolt.horizontal")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["data caching", "cache", "aggressive", "memory"]) {
                    Picker(selection: $cacheMode) {
                        Text("Aggressive").tag("aggressive")
                        Text("Balanced").tag("balanced")
                        Text("Light").tag("light")
                    } label: {
                        Label("Data Caching", systemImage: "memorychip")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["prefetch artist images", "prefetch", "artist", "profile", "pictures"]) {
                    Toggle(isOn: $prefetchArtistImages) {
                        Label("Prefetch Artist Images", systemImage: "person.crop.square.badge.camera")
                    }
                    .tint(Theme.accent)
                }
            } header: {
                Text(sectionTitle(s))
            } footer: {
                Text("Fast uses more connections and CPU for snappier loading; Conservative saves battery. Aggressive caching keeps more artwork in memory. Loading/caching changes apply on next launch.")
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }
}

struct PerformanceOverlaySettingsView: View {
    @AppStorage("developerPerformanceOverlay") private var overlayEnabled = false
    @AppStorage(PerformanceOverlayConfiguration.itemsKey) private var overlayItemsRaw = PerformanceOverlayConfiguration.defaultRaw

    private var selectedItems: [PerformanceOverlayItem] {
        PerformanceOverlayConfiguration.items(from: overlayItemsRaw)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                Section {
                    Toggle(isOn: $overlayEnabled) {
                        Label("Live Performance Overlay", systemImage: "chart.xyaxis.line")
                    }
                    .tint(Theme.accent)
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    HStack {
                        Spacer(minLength: 0)
                        PerformanceOverlay()
                            .allowsHitTesting(false)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                } header: {
                    Text("Preview")
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    ForEach(PerformanceOverlayItem.allCases) { item in
                        Toggle(isOn: metricBinding(for: item)) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .foregroundStyle(Theme.primaryText)
                                    Text(item.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                            } icon: {
                                Image(systemName: item.systemImage)
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .tint(Theme.accent)
                    }
                } header: {
                    Text("Visible Items")
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    Button {
                        overlayItemsRaw = PerformanceOverlayConfiguration.defaultRaw
                    } label: {
                        Label("Show All Items", systemImage: "checklist.checked")
                    }
                    .foregroundStyle(Theme.primaryText)

                    Button(role: .destructive) {
                        overlayItemsRaw = ""
                    } label: {
                        Label("Remove All Items", systemImage: "checklist.unchecked")
                    }
                }
                .listRowBackground(Theme.secondaryBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle("Performance Overlay")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
        }
        .preferredColorScheme(Theme.colorScheme)
    }

    private func metricBinding(for item: PerformanceOverlayItem) -> Binding<Bool> {
        Binding {
            selectedItems.contains(item)
        } set: { enabled in
            var updated = selectedItems
            if enabled {
                if !updated.contains(item) { updated.append(item) }
                updated.sort { lhs, rhs in
                    guard let li = PerformanceOverlayItem.allCases.firstIndex(of: lhs),
                          let ri = PerformanceOverlayItem.allCases.firstIndex(of: rhs) else {
                        return lhs.rawValue < rhs.rawValue
                    }
                    return li < ri
                }
            } else {
                updated.removeAll { $0 == item }
            }
            overlayItemsRaw = PerformanceOverlayConfiguration.raw(from: updated)
        }
    }
}
