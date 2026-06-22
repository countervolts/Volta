import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension SettingsView {
    var customAccentColor: Color {
        Color(red: customAccentRed, green: customAccentGreen, blue: customAccentBlue)
    }

    var customAccentSwatch: some View {
        let selected = accentColorName == "custom"
        return Circle()
            .fill(customAccentColor)
            .frame(width: 32, height: 32)
            .overlay(
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(selected ? 1 : 0)
            )
            .overlay(
                Circle().stroke(.white.opacity(0.9), lineWidth: selected ? 2 : 0)
                    .padding(-3)
            )
            .scaleEffect(selected ? 1.12 : 1)
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    accentColorName = "custom"
                }
            }
    }

    func setCustomAccent(_ color: Color) {
        let ui = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let nr = Double(r), ng = Double(g), nb = Double(b)
        // ColorPicker hands its selection back through a slightly different
        // color space, so the value it emits never exactly equals what we
        // stored. Persisting every emission re-invalidates the view, which
        // makes ColorPicker emit again, which persists again — an unbounded
        // set -> @AppStorage -> re-render loop that pegs the main thread and
        // gets the app watchdog-killed on iOS < 26 (iOS 26 coalesces it away).
        // Only persist a change the user can actually see; a sub-epsilon delta
        // is round-trip noise, and bailing also avoids hijacking a preset
        // accent to "custom" just because the picker was rendered.
        let eps = 0.01
        if abs(nr - customAccentRed) < eps,
           abs(ng - customAccentGreen) < eps,
           abs(nb - customAccentBlue) < eps {
            return
        }
        customAccentRed = nr
        customAccentGreen = ng
        customAccentBlue = nb
        accentColorName = "custom"
    }

    // MARK: - Appearance

    @ViewBuilder
    var appearanceSection: some View {
        let s = "Appearance"
        if sectionVisible(s, [["language", "languages", "idioma", "langue", "sprache", "lingua", "translate", "translation", "localization", "localisation"], ["hidden albums", "hide albums", "visibility", "library visibility", "artist visibility"], ["theme", "dark", "light", "amoled", "oled", "black", "appearance"], ["show lossless badge", "lossless", "badge"], ["live artwork", "animated artwork", "live", "gif", "webp", "motion", "animation"], ["stylized player cover", "stylised player cover", "full bleed", "edge to edge", "player cover", "cover style"], ["dynamic player background", "dynamic", "background"], ["song artwork in lists", "artwork", "thumbnail", "cover", "track"], ["accent color", "accent", "color", "colour", "theme"]]) {
            Section {
                if rowVisible(s, ["language", "languages", "idioma", "langue", "sprache", "lingua", "translate", "translation", "localization", "localisation"]) {
                    NavigationLink {
                        LanguageSettingsView()
                    } label: {
                        Label(L(.settings_language), systemImage: "globe")
                    }
                }

                if rowVisible(s, ["hidden albums", "hide albums", "visibility", "library visibility", "artist visibility"]) {
                    NavigationLink {
                        HiddenAlbumsSettingsView(client: appState.client)
                    } label: {
                        LabeledContent {
                            Text(hiddenAlbums.hiddenAlbumIDs.isEmpty ? L(.hidden_albums_none) : "\(hiddenAlbums.hiddenAlbumIDs.count)")
                                .foregroundStyle(Theme.secondaryText)
                        } label: {
                            Label(L(.appearance_hidden_albums), systemImage: "eye.slash")
                        }
                    }
                    .foregroundStyle(Theme.primaryText)
                }

                if rowVisible(s, ["theme", "dark", "light", "amoled", "oled", "black", "appearance"]) {
                    Picker(selection: $themeMode) {
                        Text(L(.theme_dark)).tag("dark")
                        Text(L(.theme_amoled)).tag("amoled")
                        Text(L(.theme_light)).tag("light")
                    } label: {
                        Label(L(.appearance_theme), systemImage: "circle.lefthalf.filled")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["show lossless badge", "lossless", "badge"]) {
                    Toggle(isOn: $showLosslessBadge) {
                        Label(L(.appearance_lossless_badge), systemImage: "waveform.badge.plus")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["live artwork", "animated artwork", "live", "gif", "webp", "motion", "animation"]) {
                    Toggle(isOn: $liveArtwork) {
                        Label(L(.appearance_live_artwork), systemImage: "sparkles.rectangle.stack")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["stylized player cover", "stylised player cover", "full bleed", "edge to edge", "player cover", "cover style"]) {
                    Toggle(isOn: $stylizedPlayerCover) {
                        Label(L(.appearance_stylized_cover), systemImage: "rectangle.portrait.arrowtriangle.2.outward")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["song artwork in lists", "artwork", "thumbnail", "cover", "track"]) {
                    Toggle(isOn: $showTrackArtwork) {
                        Label(L(.appearance_song_artwork_lists), systemImage: "photo")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["dynamic player background", "dynamic", "background"]) {
                    Toggle(isOn: $dynamicBackground) {
                        Label(L(.appearance_dynamic_background), systemImage: "paintpalette")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["accent color", "accent", "color", "colour", "theme"]) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(L(.appearance_accent_color), systemImage: "paintbrush")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                customAccentSwatch
                                ForEach(Theme.accentNames, id: \.self) { name in
                                    let color = Theme.accentColor(named: name)
                                    let selected = accentColorName == name
                                    Circle()
                                        .fill(color)
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundStyle(.white)
                                                .opacity(selected ? 1 : 0)
                                        )
                                        .overlay(
                                            Circle().stroke(.white.opacity(0.9), lineWidth: selected ? 2 : 0)
                                                .padding(-3)
                                        )
                                        .scaleEffect(selected ? 1.12 : 1)
                                        .onTapGesture {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                accentColorName = name
                                            }
                                        }
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 10)
                        }

                        ColorPicker(
                            "Custom Accent",
                            selection: Binding(get: { customAccentColor }, set: { setCustomAccent($0) }),
                            supportsOpacity: false
                        )
                    }
                }
            } header: {
                Text(sectionTitle(s))
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }
}
