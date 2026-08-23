import Foundation
import SwiftUI
import UIKit

enum StatsShareTemplate: String, Codable, Hashable, Identifiable {
    case listening
    case rhythm
    case library

    /// `listening` remains decodable for old customizations, but the map is
    /// now the only Listening share card offered to users.
    static let availableTemplates: [StatsShareTemplate] = [.rhythm, .library]

    var id: String { rawValue }

    @MainActor var title: String {
        switch self {
        case .listening, .rhythm: return L(.stats_share_listening)
        case .library: return L(.tab_library)
        }
    }

    var icon: String {
        switch self {
        case .listening: return "waveform"
        case .rhythm: return "square.grid.3x3.fill"
        case .library: return "music.note.house"
        }
    }
}

enum StatsShareCanvas: String, CaseIterable, Codable, Hashable, Identifiable {
    case square
    case portrait
    case story

    var id: String { rawValue }

    @MainActor var title: String {
        switch self {
        case .square: return L(.stats_share_square)
        case .portrait: return L(.stats_share_portrait)
        case .story: return L(.stats_share_story)
        }
    }

    var size: CGSize {
        switch self {
        case .square: return CGSize(width: 1080, height: 1080)
        case .portrait: return CGSize(width: 1080, height: 1350)
        case .story: return CGSize(width: 1080, height: 1920)
        }
    }

    /// Share cards are designed in points, then rasterized at 3x for a crisp
    /// 1080-pixel export. Keeping this separate from `size` makes the export
    /// use the same typography and spacing as the on-device preview.
    var renderSize: CGSize {
        CGSize(width: size.width / 3, height: size.height / 3)
    }

    var exportScale: CGFloat { size.width / renderSize.width }

    var aspectRatio: CGFloat { size.width / size.height }
}

enum StatsShareWidgetLayout: String, CaseIterable, Codable, Hashable, Identifiable {
    case compact
    case standard
    /// Retained only to decode older saved customizations. It is normalized to
    /// Standard before a card is displayed or exported.
    case expanded

    var id: String { rawValue }

    @MainActor var title: String {
        switch self {
        case .compact: return L(.stats_share_compact)
        case .standard: return L(.stats_share_standard)
        case .expanded: return L(.stats_share_standard)
        }
    }
}

enum StatsShareAppearance: String, Codable, Hashable {
    /// Retained solely to turn an older Light/Dark choice into explicit card
    /// colors when a customization is next loaded.
    case light = "widgetLight"
    case dark = "widgetDark"
}

enum StatsShareAccent: String, CaseIterable, Codable, Hashable, Identifiable {
    case widgetDefault
    case appAccent
    case custom
    case orange
    case indigo
    case teal
    case blue
    case green
    case pink

    var id: String { rawValue }

    @MainActor var title: String {
        switch self {
        case .widgetDefault: return L(.stats_share_widget_default)
        case .appAccent: return L(.stats_share_app_accent)
        case .custom: return L(.stats_share_custom_color)
        case .orange: return L(.stats_share_orange)
        case .indigo: return L(.stats_share_indigo)
        case .teal: return L(.stats_share_teal)
        case .blue: return L(.stats_share_blue)
        case .green: return L(.stats_share_green)
        case .pink: return L(.stats_share_pink)
        }
    }

    func color(for template: StatsShareTemplate, customColor: StatsShareColor) -> Color {
        switch self {
        case .widgetDefault:
            return template == .library ? Color(uiColor: .systemIndigo) : Color(uiColor: .systemOrange)
        case .appAccent:
            return Theme.accent
        case .custom:
            return customColor.color
        case .orange:
            return Color(uiColor: .systemOrange)
        case .indigo:
            return Color(uiColor: .systemIndigo)
        case .teal:
            return Color(uiColor: .systemTeal)
        case .blue:
            return Color(uiColor: .systemBlue)
        case .green:
            return Color(uiColor: .systemGreen)
        case .pink:
            return Color(uiColor: .systemPink)
        }
    }
}

struct StatsShareColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double

    static let widgetOrange = StatsShareColor(red: 1, green: 0.33, blue: 0.0)
    static let shareLightBackground = StatsShareColor(red: 1, green: 1, blue: 1)
    static let shareDarkBackground = StatsShareColor(red: 0, green: 0, blue: 0)
    static let shareLightText = StatsShareColor(red: 0, green: 0, blue: 0)
    static let shareDarkText = StatsShareColor(red: 1, green: 1, blue: 1)

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    static func from(_ color: Color) -> Self {
        let uiColor = UIColor(color)
        var red: CGFloat = 1
        var green: CGFloat = 0.33
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return Self(red: Double(red), green: Double(green), blue: Double(blue))
    }
}

enum StatsShareFont: String, CaseIterable, Codable, Hashable, Identifiable {
    case widgetSerif
    case rounded
    case monospaced
    case sans

    var id: String { rawValue }

    @MainActor var title: String {
        switch self {
        case .widgetSerif: return L(.stats_share_font_widget)
        case .rounded: return L(.stats_share_font_rounded)
        case .monospaced: return L(.stats_share_font_mono)
        case .sans: return L(.stats_share_font_sans)
        }
    }

    func display(size: CGFloat, weight: Font.Weight) -> Font {
        switch self {
        case .widgetSerif:
            return .system(size: size, weight: weight, design: .serif)
        case .rounded:
            return .system(size: size, weight: weight, design: .rounded)
        case .monospaced:
            return .system(size: size, weight: weight, design: .monospaced)
        case .sans:
            return .system(size: size, weight: weight, design: .default)
        }
    }
}

enum StatsShareMetric: String, CaseIterable, Codable, Hashable, Identifiable {
    case plays
    case listeningTime
    case uniqueSongs
    case uniqueAlbums
    case artists
    case sessions
    case activeDays
    case activeWeeks
    case streak
    case longestStreak
    case averagePlaysPerDay
    case averageListeningPerDay
    case averageTrackLength
    case longestSession
    case topGenre
    case bestMonth
    case topArtist
    case tracks
    case albums
    case librarySize
    case lossless
    case hiRes
    case metadata

    var id: String { rawValue }

    @MainActor var title: String {
        switch self {
        case .plays: return L(.media_plays)
        case .listeningTime: return L(.stats_share_listening_time)
        case .uniqueSongs: return L(.stats_share_unique_songs)
        case .uniqueAlbums: return L(.stats_share_unique_albums)
        case .artists: return L(.home_artists)
        case .sessions: return L(.stats_share_sessions)
        case .activeDays: return L(.stats_share_active_days)
        case .activeWeeks: return L(.stats_share_active_weeks)
        case .streak: return L(.stats_share_streak)
        case .longestStreak: return L(.stats_share_longest_streak)
        case .averagePlaysPerDay: return L(.stats_share_average_plays_per_day)
        case .averageListeningPerDay: return L(.stats_share_average_listening_per_day)
        case .averageTrackLength: return L(.stats_share_average_track_length)
        case .longestSession: return L(.stats_share_longest_session)
        case .topGenre: return L(.stats_share_top_genre)
        case .bestMonth: return L(.stats_share_best_month)
        case .topArtist: return L(.stats_share_top_artist)
        case .tracks: return L(.media_songs)
        case .albums: return L(.stats_share_albums)
        case .librarySize: return L(.stats_share_library_size)
        case .lossless: return L(.quality_lossless)
        case .hiRes: return L(.stats_share_hi_res)
        case .metadata: return L(.stats_share_metadata)
        }
    }

    static func available(for template: StatsShareTemplate) -> [StatsShareMetric] {
        switch template {
        case .listening, .rhythm:
            return [
                .plays, .listeningTime, .artists, .activeDays, .streak,
                .activeWeeks, .uniqueSongs, .uniqueAlbums, .sessions, .longestStreak,
                .averagePlaysPerDay, .averageListeningPerDay, .averageTrackLength,
                .longestSession, .topArtist, .topGenre, .bestMonth
            ]
        case .library:
            return [
                .tracks, .albums, .artists, .listeningTime, .averageTrackLength,
                .librarySize, .lossless, .hiRes, .metadata
            ]
        }
    }
}

enum StatsShareRhythmSpan: String, CaseIterable, Codable, Hashable, Identifiable {
    case weeks12
    case weeks26
    case weeks52

    var id: String { rawValue }

    var weeks: Int {
        switch self {
        case .weeks12: return 12
        case .weeks26: return 26
        case .weeks52: return 52
        }
    }

    var dayCount: Int { weeks * 7 }

    @MainActor var title: String {
        switch self {
        case .weeks12: return L(.stats_share_12_weeks)
        case .weeks26: return L(.stats_share_26_weeks)
        case .weeks52: return L(.stats_share_last_52_weeks)
        }
    }
}

enum StatsShareRhythmMeasure: String, CaseIterable, Codable, Hashable, Identifiable {
    case plays
    case listeningTime

    var id: String { rawValue }

    @MainActor var title: String {
        switch self {
        case .plays: return L(.stats_share_by_plays)
        case .listeningTime: return L(.stats_share_by_time)
        }
    }
}

struct StatsShareCustomization: Codable, Hashable {
    var template: StatsShareTemplate
    var canvas: StatsShareCanvas
    var layout: StatsShareWidgetLayout
    /// Legacy only; it migrates into the explicit colors below.
    var appearance: StatsShareAppearance
    var accent: StatsShareAccent
    var customAccent: StatsShareColor
    var customBackgroundColor: StatsShareColor?
    var customTextColor: StatsShareColor?
    var font: StatsShareFont
    var leadMetric: StatsShareMetric
    var firstMetric: StatsShareMetric
    var secondMetric: StatsShareMetric
    var thirdMetric: StatsShareMetric
    /// Optional so existing customizations keep decoding with every data point
    /// visible until the user chooses otherwise.
    var hiddenMetrics: Set<StatsShareMetric>?
    var showHeader: Bool
    /// Optional solely for backwards-compatible decoding of v3 customizations.
    /// A missing value should behave as the original visible server detail.
    var showServerAddress: Bool?
    var showFooter: Bool
    var rhythmSpan: StatsShareRhythmSpan
    var rhythmMeasure: StatsShareRhythmMeasure

    private static let storageKey = "statsShareCustomization.v3"

    static func defaults(template: StatsShareTemplate) -> Self {
        Self(
            template: template,
            canvas: .square,
            layout: .standard,
            appearance: .light,
            accent: .widgetDefault,
            customAccent: .widgetOrange,
            customBackgroundColor: .shareLightBackground,
            customTextColor: .shareLightText,
            font: .widgetSerif,
            leadMetric: defaultMetrics(for: template)[0],
            firstMetric: defaultMetrics(for: template)[1],
            secondMetric: defaultMetrics(for: template)[2],
            thirdMetric: defaultMetrics(for: template)[3],
            hiddenMetrics: [],
            showHeader: true,
            showServerAddress: true,
            showFooter: true,
            rhythmSpan: .weeks52,
            rhythmMeasure: .plays
        )
    }

    private static func defaultMetrics(for template: StatsShareTemplate) -> [StatsShareMetric] {
        switch template {
        case .listening, .rhythm: return [.plays, .activeDays, .listeningTime, .streak]
        case .library: return [.tracks, .albums, .artists, .listeningTime]
        }
    }

    static func load(defaultTemplate: StatsShareTemplate) -> Self {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let value = try? JSONDecoder().decode(Self.self, from: data) else {
            return defaults(template: defaultTemplate)
        }
        return value
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    func normalized() -> Self {
        var result = self
        if result.template == .listening {
            result.template = .rhythm
        }
        let allowed = StatsShareMetric.available(for: result.template)
        let defaults = Self.defaultMetrics(for: result.template)
        result.canvas = .square
        result.layout = .standard
        if result.customBackgroundColor == nil {
            result.customBackgroundColor = result.appearance == .dark
                ? .shareDarkBackground
                : .shareLightBackground
        }
        if result.customTextColor == nil {
            result.customTextColor = result.appearance == .dark
                ? .shareDarkText
                : .shareLightText
        }
        result.hiddenMetrics = hiddenMetrics ?? []
        result.showServerAddress = showServerAddress ?? true
        var used = Set<StatsShareMetric>()

        func unique(_ candidate: StatsShareMetric, fallback: StatsShareMetric) -> StatsShareMetric {
            if allowed.contains(candidate), !used.contains(candidate) {
                used.insert(candidate)
                return candidate
            }
            let replacement = allowed.first(where: { !used.contains($0) }) ?? fallback
            used.insert(replacement)
            return replacement
        }

        result.leadMetric = unique(leadMetric, fallback: defaults[0])
        result.firstMetric = unique(firstMetric, fallback: defaults[1])
        result.secondMetric = unique(secondMetric, fallback: defaults[2])
        result.thirdMetric = unique(thirdMetric, fallback: defaults[3])
        return result
    }

    func showsMetric(_ metric: StatsShareMetric) -> Bool {
        !(hiddenMetrics ?? []).contains(metric)
    }
}

struct StatsShareSheet: View {
    @ObservedObject var listening: StatsViewModel
    @ObservedObject var library: LibraryStatsViewModel

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var customization: StatsShareCustomization

    init(listening: StatsViewModel, library: LibraryStatsViewModel, initialTemplate: StatsShareTemplate) {
        self.listening = listening
        self.library = library
        _customization = State(initialValue: .load(defaultTemplate: initialTemplate).normalized())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        StatsShareCardView(
                            settings: customization,
                            listening: listening.shareSnapshot,
                            library: library.stats
                        )
                        .aspectRatio(customization.canvas.aspectRatio, contentMode: .fit)
                        .frame(maxWidth: 390)
                        .overlay {
                            Rectangle()
                                .stroke(Color(uiColor: .separator), lineWidth: 1)
                        }
                        .padding(.horizontal, 20)

                        controls

                        Button(action: shareCard) {
                            Label(L(.action_share), systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .foregroundStyle(Theme.background)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(Theme.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canShare)
                        .opacity(canShare ? 1 : 0.42)
                        .padding(.horizontal, 20)

                        if !canShare {
                            Text(unavailableMessage)
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }

                        Color.clear.frame(height: 24)
                    }
                    .padding(.top, 18)
                }
            }
            .navigationTitle(L(.stats_share_title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L(.action_done)) { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .task { loadLibraryIfNeeded() }
            .onChangeCompat(of: customization) { _, updated in
                let normalized = updated.normalized()
                if normalized != updated {
                    customization = normalized
                    return
                }
                updated.save()
                loadLibraryIfNeeded()
            }
        }
        .preferredColorScheme(Theme.colorScheme)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L(.stats_share_customize).uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Button(L(.stats_share_reset)) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        customization = .defaults(template: customization.template)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 20)

            VStack(spacing: 0) {
                ShareControlRow(L(.stats_share_template)) {
                    Picker(L(.stats_share_template), selection: $customization.template) {
                        ForEach(StatsShareTemplate.availableTemplates) { template in
                            Label(template.title, systemImage: template.icon).tag(template)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(Theme.accent)
                }

                ShareControlRow(L(.stats_share_background_color)) {
                    ColorPicker(
                        L(.stats_share_background_color),
                        selection: Binding(
                            get: {
                                customization.customBackgroundColor?.color
                                    ?? StatsShareColor.shareLightBackground.color
                            },
                            set: { customization.customBackgroundColor = StatsShareColor.from($0) }
                        ),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                }

                ShareControlRow(L(.stats_share_text_color)) {
                    ColorPicker(
                        L(.stats_share_text_color),
                        selection: Binding(
                            get: {
                                customization.customTextColor?.color
                                    ?? StatsShareColor.shareLightText.color
                            },
                            set: { customization.customTextColor = StatsShareColor.from($0) }
                        ),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                }

                ShareControlRow(L(.appearance_accent_color)) {
                    Picker(L(.appearance_accent_color), selection: $customization.accent) {
                        ForEach(StatsShareAccent.allCases) { accent in
                            Text(accent.title).tag(accent)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(Theme.accent)
                }

                if customization.accent == .custom {
                    ShareControlRow(L(.stats_share_custom_color)) {
                        ColorPicker(
                            L(.stats_share_custom_color),
                            selection: Binding(
                                get: { customization.customAccent.color },
                                set: { customization.customAccent = StatsShareColor.from($0) }
                            ),
                            supportsOpacity: false
                        )
                        .labelsHidden()
                    }
                }

                ShareControlRow(L(.stats_share_font)) {
                    Picker(L(.stats_share_font), selection: $customization.font) {
                        ForEach(StatsShareFont.allCases) { font in
                            Text(font.title).tag(font)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(Theme.accent)
                }

                ShareControlRow(L(.stats_share_lead_metric)) {
                    metricPicker(
                        L(.stats_share_lead_metric),
                        selection: $customization.leadMetric,
                        excluding: []
                    )
                }

                ShareControlRow(L(.stats_share_data_one)) {
                    metricPicker(
                        L(.stats_share_data_one),
                        selection: $customization.firstMetric,
                        excluding: [customization.leadMetric]
                    )
                }

                ShareControlRow(L(.stats_share_data_two)) {
                    metricPicker(
                        L(.stats_share_data_two),
                        selection: $customization.secondMetric,
                        excluding: [customization.leadMetric, customization.firstMetric]
                    )
                }

                ShareControlRow(L(.stats_share_data_three)) {
                    metricPicker(
                        L(.stats_share_data_three),
                        selection: $customization.thirdMetric,
                        excluding: [customization.leadMetric, customization.firstMetric, customization.secondMetric]
                    )
                }

                Text(L(.stats_share_visible_data).uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 4)

                ForEach(displayedMetrics) { metric in
                    ShareControlRow(metricTitle(metric)) {
                        Toggle(metricTitle(metric), isOn: metricVisibilityBinding(for: metric))
                            .labelsHidden()
                            .tint(Theme.accent)
                    }
                }

                ShareControlRow(L(.stats_share_show_header)) {
                    Toggle(L(.stats_share_show_header), isOn: $customization.showHeader)
                        .labelsHidden()
                        .tint(Theme.accent)
                }

                if customization.template == .rhythm {
                    ShareControlRow(L(.stats_share_map_span)) {
                        Picker(L(.stats_share_map_span), selection: $customization.rhythmSpan) {
                            ForEach(StatsShareRhythmSpan.allCases) { span in
                                Text(span.title).tag(span)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(Theme.accent)
                    }

                    ShareControlRow(L(.stats_share_map_measure)) {
                        Picker(L(.stats_share_map_measure), selection: $customization.rhythmMeasure) {
                            ForEach(StatsShareRhythmMeasure.allCases) { measure in
                                Text(measure.title).tag(measure)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(Theme.accent)
                    }
                }

                if customization.template == .library, customization.showHeader {
                    ShareControlRow(L(.stats_share_show_server_address)) {
                        Toggle(
                            L(.stats_share_show_server_address),
                            isOn: Binding(
                                get: { customization.showServerAddress ?? true },
                                set: { customization.showServerAddress = $0 }
                            )
                        )
                        .labelsHidden()
                        .tint(Theme.accent)
                    }
                }
            }
            .background(Theme.secondaryBackground)
            .overlay {
                Rectangle()
                    .stroke(Theme.secondaryText.opacity(0.14), lineWidth: 1)
            }
            .padding(.horizontal, 20)
        }
    }

    private var canShare: Bool {
        switch customization.template {
        case .library:
            return library.stats != nil
        case .listening, .rhythm:
            return listening.totalPlays > 0
        }
    }

    private var unavailableMessage: String {
        switch customization.template {
        case .library: return L(.stats_share_scanning_library)
        case .listening, .rhythm: return L(.stats_share_need_listening)
        }
    }

    private func metricPicker(
        _ title: String,
        selection: Binding<StatsShareMetric>,
        excluding: Set<StatsShareMetric>
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(metricChoices(selected: selection.wrappedValue, excluding: excluding)) { metric in
                Text(metricTitle(metric)).tag(metric)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .tint(Theme.accent)
    }

    private func metricChoices(selected: StatsShareMetric, excluding: Set<StatsShareMetric>) -> [StatsShareMetric] {
        StatsShareMetric.available(for: customization.template).filter {
            $0 == selected || !excluding.contains($0)
        }
    }

    private var displayedMetrics: [StatsShareMetric] {
        let selected = [
            customization.leadMetric,
            customization.firstMetric,
            customization.secondMetric,
            customization.thirdMetric
        ]

        guard customization.template != .library else { return selected }
        let remaining = StatsShareMetric.available(for: .rhythm).filter { !selected.contains($0) }
        // The map has one lead plus five supporting positions. More choices
        // should not add more rendered positions to the card.
        return selected + Array(remaining.prefix(max(0, 5 - selected.count)))
    }

    private func metricVisibilityBinding(for metric: StatsShareMetric) -> Binding<Bool> {
        Binding(
            get: { customization.showsMetric(metric) },
            set: { isVisible in
                var hidden = customization.hiddenMetrics ?? []
                if isVisible {
                    hidden.remove(metric)
                } else {
                    hidden.insert(metric)
                }
                customization.hiddenMetrics = hidden
            }
        )
    }

    private func metricTitle(_ metric: StatsShareMetric) -> String {
        switch metric {
        case .plays: return L(.media_plays)
        case .listeningTime: return L(.stats_share_listening_time)
        case .uniqueSongs: return L(.stats_share_unique_songs)
        case .uniqueAlbums: return L(.stats_share_unique_albums)
        case .artists: return L(.home_artists)
        case .sessions: return L(.stats_share_sessions)
        case .activeDays: return L(.stats_share_active_days)
        case .activeWeeks: return L(.stats_share_active_weeks)
        case .streak: return L(.stats_share_streak)
        case .longestStreak: return L(.stats_share_longest_streak)
        case .averagePlaysPerDay: return L(.stats_share_average_plays_per_day)
        case .averageListeningPerDay: return L(.stats_share_average_listening_per_day)
        case .averageTrackLength: return L(.stats_share_average_track_length)
        case .longestSession: return L(.stats_share_longest_session)
        case .topGenre: return L(.stats_share_top_genre)
        case .bestMonth: return L(.stats_share_best_month)
        case .topArtist: return L(.stats_share_top_artist)
        case .tracks: return L(.media_songs)
        case .albums: return L(.stats_share_albums)
        case .librarySize: return L(.stats_share_library_size)
        case .lossless: return L(.quality_lossless)
        case .hiRes: return L(.stats_share_hi_res)
        case .metadata: return L(.stats_share_metadata)
        }
    }

    private func loadLibraryIfNeeded() {
        guard customization.template == .library else { return }
        library.loadIfNeeded(appState: appState)
    }

    @MainActor
    private func shareCard() {
        guard canShare else { return }

        let normalized = customization.normalized()
        let canvas = normalized.canvas
        let card = StatsShareCardView(
            settings: normalized,
            listening: listening.shareSnapshot,
            library: library.stats
        )
        .frame(width: canvas.renderSize.width, height: canvas.renderSize.height)

        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = .init(
            width: canvas.renderSize.width,
            height: canvas.renderSize.height
        )
        renderer.scale = canvas.exportScale
        guard let image = renderer.uiImage else { return }
        ShareSheet.present([image])
    }
}

private struct ShareControlRow<Accessory: View>: View {
    let title: String
    let accessory: Accessory

    init(_ title: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 8)
            accessory
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.secondaryText.opacity(0.14))
                .frame(height: 1)
        }
    }
}

private struct WidgetShareTone {
    let accent: Color
    let customBackgroundColor: StatsShareColor?
    let customTextColor: StatsShareColor?

    var background: Color { customBackgroundColor?.color ?? StatsShareColor.shareLightBackground.color }
    var primary: Color { customTextColor?.color ?? StatsShareColor.shareLightText.color }
    var secondary: Color {
        guard let customTextColor else { return StatsShareColor.shareLightText.color.opacity(0.64) }
        return customTextColor.color.opacity(0.64)
    }
    var rule: Color {
        guard let customTextColor else { return StatsShareColor.shareLightText.color.opacity(0.22) }
        return customTextColor.color.opacity(0.22)
    }
}

private struct WidgetShareDatum: Identifiable {
    let id: String
    let value: String
    let label: String
}

private struct StatsShareCardView: View {
    let settings: StatsShareCustomization
    let listening: ListeningShareSnapshot
    let library: LibraryStatsData?

    private var tone: WidgetShareTone {
        WidgetShareTone(
            accent: settings.accent.color(for: settings.template, customColor: settings.customAccent),
            customBackgroundColor: settings.customBackgroundColor,
            customTextColor: settings.customTextColor
        )
    }

    private var rhythmDays: [ListeningRhythmDay] {
        Array(listening.rhythm.suffix(settings.rhythmSpan.dayCount))
    }

    private var rhythmPlays: Int { rhythmDays.reduce(0) { $0 + $1.plays } }
    private var rhythmSeconds: Int { rhythmDays.reduce(0) { $0 + $1.seconds } }
    private var rhythmActiveDays: Int { rhythmDays.filter { $0.plays > 0 }.count }
    private var rhythmObservedDays: Int { max(1, rhythmDays.filter { !$0.isFuture }.count) }
    private var rhythmActiveWeeks: Int {
        let calendar = Calendar.current
        return Set(
            rhythmDays.lazy
                .filter { $0.plays > 0 }
                .map {
                    let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: $0.date)
                    return "\(parts.yearForWeekOfYear ?? 0)-\(parts.weekOfYear ?? 0)"
                }
        ).count
    }

    var body: some View {
        GeometryReader { proxy in
            let measurements = WidgetShareMeasurements(size: proxy.size, layout: settings.layout)

            VStack(alignment: .leading, spacing: measurements.spacing) {
                switch settings.template {
                case .listening, .rhythm:
                    rhythmCard(measurements)
                case .library:
                    libraryCard(measurements)
                }
            }
            .padding(measurements.padding)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .background(tone.background)
        }
    }

    @ViewBuilder
    private func rhythmCard(_ measurements: WidgetShareMeasurements) -> some View {
        if settings.showHeader {
            WidgetShareHeader(
                title: L(.stats_share_listening),
                detail: settings.rhythmSpan.title,
                tone: tone,
                measurements: measurements,
                font: settings.font
            )
        }

        if isLeadMetricVisible {
            WidgetShareLead(
                value: leadDatum.value,
                label: leadDatum.label,
                accentDetail: settings.rhythmMeasure.title,
                tone: tone,
                measurements: measurements,
                font: settings.font
            )

            WidgetShareRule(tone: tone, measurements: measurements)
        }

        ListeningRhythmHeatmap(
            days: rhythmDays,
            span: settings.rhythmSpan,
            measure: settings.rhythmMeasure,
            tone: tone
        )

        if hasSelectedMetrics {
            WidgetShareRule(tone: tone, measurements: measurements)
            Spacer(minLength: measurements.sectionBreathingRoom)
            metricStrip(selectedMetrics, measurements: measurements)
        }
    }

    @ViewBuilder
    private func libraryCard(_ measurements: WidgetShareMeasurements) -> some View {
        if let library {
            if settings.showHeader {
                WidgetShareHeader(
                    title: L(.tab_library),
                    detail: (settings.showServerAddress ?? true) ? library.source : nil,
                    tone: tone,
                    measurements: measurements,
                    font: settings.font
                )
            }

            if isLeadMetricVisible {
                WidgetShareLead(
                    value: leadDatum.value,
                    label: leadDatum.label,
                    accentDetail: settings.leadMetric == .tracks ? formatLibDuration(library.totalSeconds) : nil,
                    tone: tone,
                    measurements: measurements,
                    font: settings.font
                )

                WidgetShareRule(tone: tone, measurements: measurements)
            }

            if settings.layout != .compact {
                WidgetShareLosslessMix(library: library, tone: tone, measurements: measurements, font: settings.font)
                if hasSelectedMetrics {
                    WidgetShareRule(tone: tone, measurements: measurements)
                }
            }

            if hasSelectedMetrics {
                Spacer(minLength: measurements.sectionBreathingRoom)
                metricStrip(selectedMetrics, measurements: measurements)
            }

        } else {
            if settings.showHeader {
                WidgetShareHeader(
                    title: L(.tab_library),
                    detail: (settings.showServerAddress ?? true) ? "VOLTA" : nil,
                    tone: tone,
                    measurements: measurements,
                    font: settings.font
                )
            }
            Spacer(minLength: measurements.sectionBreathingRoom)
            Text(L(.stats_share_scanning_library))
                .font(settings.font.display(size: measurements.placeholderSize, weight: .medium))
                .foregroundStyle(tone.primary)
        }
    }

    private var isLeadMetricVisible: Bool { settings.showsMetric(settings.leadMetric) }

    private var leadDatum: WidgetShareDatum { datum(for: settings.leadMetric) }

    private var configuredSupportingMetrics: [StatsShareMetric] {
        let selected = [settings.firstMetric, settings.secondMetric, settings.thirdMetric]
        guard settings.template != .library else { return selected }

        // Preserve the map's existing six total metric positions even as more
        // values become available in the metric pickers.
        let remaining = StatsShareMetric.available(for: .rhythm).filter {
            $0 != settings.leadMetric && !selected.contains($0)
        }
        return selected + Array(remaining.prefix(max(0, 5 - selected.count)))
    }

    private var selectedMetrics: [WidgetShareDatum] {
        configuredSupportingMetrics
            .filter { settings.showsMetric($0) }
            .map(datum(for:))
    }

    private var hasSelectedMetrics: Bool { !selectedMetrics.isEmpty }

    private func datum(for metric: StatsShareMetric) -> WidgetShareDatum {
        switch settings.template {
        case .listening, .rhythm:
            return rhythmDatum(for: metric)
        case .library:
            return libraryDatum(for: metric)
        }
    }

    private func rhythmDatum(for metric: StatsShareMetric) -> WidgetShareDatum {
        switch metric {
        case .plays:
            return .init(id: metric.rawValue, value: rhythmPlays.formatted(), label: metric.title)
        case .listeningTime:
            return .init(id: metric.rawValue, value: formatLibDuration(rhythmSeconds), label: metric.title)
        case .uniqueSongs:
            return .init(id: metric.rawValue, value: listening.uniqueSongs.formatted(), label: metric.title)
        case .uniqueAlbums:
            return .init(id: metric.rawValue, value: listening.uniqueAlbums.formatted(), label: metric.title)
        case .artists:
            return .init(id: metric.rawValue, value: listening.uniqueArtists.formatted(), label: metric.title)
        case .sessions:
            return .init(id: metric.rawValue, value: listening.sessions.formatted(), label: metric.title)
        case .activeDays:
            return .init(id: metric.rawValue, value: rhythmActiveDays.formatted(), label: metric.title)
        case .activeWeeks:
            return .init(id: metric.rawValue, value: rhythmActiveWeeks.formatted(), label: metric.title)
        case .streak:
            return .init(id: metric.rawValue, value: listening.streak > 0 ? "\(listening.streak)d" : "—", label: metric.title)
        case .longestStreak:
            return .init(id: metric.rawValue, value: listening.longestStreak > 0 ? "\(listening.longestStreak)d" : "—", label: metric.title)
        case .averagePlaysPerDay:
            return .init(
                id: metric.rawValue,
                value: shareDecimal(Double(rhythmPlays) / Double(rhythmObservedDays)),
                label: metric.title
            )
        case .averageListeningPerDay:
            return .init(
                id: metric.rawValue,
                value: shareDuration(rhythmSeconds / rhythmObservedDays),
                label: metric.title
            )
        case .averageTrackLength:
            return .init(
                id: metric.rawValue,
                value: shareDuration(rhythmPlays > 0 ? rhythmSeconds / rhythmPlays : 0),
                label: metric.title
            )
        case .longestSession:
            return .init(id: metric.rawValue, value: shareDuration(listening.longestSession), label: metric.title)
        case .topGenre:
            return .init(id: metric.rawValue, value: shareText(listening.topGenre), label: metric.title)
        case .bestMonth:
            return .init(id: metric.rawValue, value: shareText(listening.bestMonth), label: metric.title)
        case .topArtist:
            return .init(id: metric.rawValue, value: shareText(listening.topArtist), label: metric.title)
        default:
            return unavailableDatum(for: metric)
        }
    }

    private func libraryDatum(for metric: StatsShareMetric) -> WidgetShareDatum {
        guard let library else { return unavailableDatum(for: metric) }
        switch metric {
        case .tracks:
            return .init(id: metric.rawValue, value: library.totalSongs.formatted(), label: metric.title)
        case .albums:
            return .init(id: metric.rawValue, value: library.totalAlbums.formatted(), label: metric.title)
        case .artists:
            return .init(id: metric.rawValue, value: library.totalArtists.formatted(), label: metric.title)
        case .listeningTime:
            return .init(id: metric.rawValue, value: formatLibDuration(library.totalSeconds), label: metric.title)
        case .averageTrackLength:
            return .init(id: metric.rawValue, value: shareDuration(library.averageTrackSeconds), label: metric.title)
        case .librarySize:
            return .init(id: metric.rawValue, value: formatLibBytes(library.totalSize), label: metric.title)
        case .lossless:
            return .init(id: metric.rawValue, value: library.losslessTracks.formatted(), label: metric.title)
        case .hiRes:
            return .init(id: metric.rawValue, value: library.hiResTracks.formatted(), label: metric.title)
        case .metadata:
            return .init(id: metric.rawValue, value: "\(metadataCoverage(for: library))%", label: metric.title)
        default:
            return unavailableDatum(for: metric)
        }
    }

    private func unavailableDatum(for metric: StatsShareMetric) -> WidgetShareDatum {
        .init(id: metric.rawValue, value: "—", label: metric.title)
    }

    private func shareDecimal(_ value: Double) -> String {
        guard value > 0 else { return "—" }
        return value >= 10 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    private func shareDuration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "—" }
        return formatDuration(seconds)
    }

    private func shareText(_ value: String?) -> String {
        guard let value, !value.isEmpty, value != "-" else { return "—" }
        return value
    }

    private func metadataCoverage(for library: LibraryStatsData) -> Int {
        let items = library.metadataCoverage.items
        guard !items.isEmpty else { return 0 }
        return Int((items.map(\.percentage).reduce(0, +) / Double(items.count)).rounded())
    }

    @ViewBuilder
    private func metricStrip(_ values: [WidgetShareDatum], measurements: WidgetShareMeasurements) -> some View {
        if settings.template != .library {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: measurements.metricSpacing),
                    count: 3
                ),
                alignment: .leading,
                spacing: measurements.metricRowSpacing
            ) {
                ForEach(values) { value in
                    WidgetShareDatumView(
                        value: value,
                        tone: tone,
                        measurements: measurements,
                        compact: settings.layout == .compact,
                        font: settings.font
                    )
                }
            }
        } else {
            HStack(alignment: .top, spacing: measurements.metricSpacing) {
                ForEach(values) { value in
                    WidgetShareDatumView(
                        value: value,
                        tone: tone,
                        measurements: measurements,
                        compact: settings.layout == .compact,
                        font: settings.font
                    )
                }
            }
        }
    }
}

private struct WidgetShareMeasurements {
    let size: CGSize
    let layout: StatsShareWidgetLayout

    var padding: CGFloat { max(22, min(82, size.width * 0.07)) }

    var spacing: CGFloat {
        switch layout {
        case .compact: return max(10, size.width * 0.024)
        case .standard, .expanded: return max(14, size.width * 0.032)
        }
    }

    var sectionBreathingRoom: CGFloat {
        switch layout {
        case .compact: return max(8, size.height * 0.012)
        case .standard, .expanded: return max(14, size.height * 0.02)
        }
    }

    var metricSpacing: CGFloat {
        switch layout {
        case .compact: return max(10, size.width * 0.022)
        case .standard, .expanded: return max(14, size.width * 0.03)
        }
    }

    var metricRowSpacing: CGFloat { max(10, spacing * 0.8) }

    var leadSize: CGFloat {
        switch layout {
        case .compact: return max(44, size.width * 0.105)
        case .standard, .expanded: return max(54, size.width * 0.128)
        }
    }

    // The renderer uses the same 360-point design canvas as the preview and
    // rasterizes it at 3x, so these values remain visually identical in both.
    var headerSize: CGFloat { max(16, size.width * 0.022) }
    var labelSize: CGFloat { max(16, size.width * 0.022) }
    var metricValueSize: CGFloat {
        switch layout {
        case .compact: return max(16, size.width * 0.03)
        case .standard, .expanded: return max(20, size.width * 0.037)
        }
    }
    var detailSize: CGFloat { max(17, size.width * 0.022) }
    var ruleHeight: CGFloat { max(1, size.width / 1080) }
    var placeholderSize: CGFloat { max(22, size.width * 0.035) }

    var weekBarsHeight: CGFloat {
        switch layout {
        case .compact: return max(28, size.width * 0.068)
        case .standard, .expanded: return max(44, size.width * 0.105)
        }
    }
}

private struct WidgetShareHeader: View {
    let title: String
    let detail: String?
    let tone: WidgetShareTone
    let measurements: WidgetShareMeasurements
    let font: StatsShareFont

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title.uppercased())
                .font(font.display(size: measurements.headerSize, weight: .bold))
                .tracking(measurements.headerSize * 0.075)
                .foregroundStyle(tone.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if let detail, !detail.isEmpty {
                Spacer(minLength: 6)
                Text(detail)
                    .font(font.display(size: measurements.headerSize, weight: .regular))
                    .foregroundStyle(tone.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
        }
    }
}

private struct WidgetShareRule: View {
    let tone: WidgetShareTone
    let measurements: WidgetShareMeasurements

    var body: some View {
        Rectangle()
            .fill(tone.rule)
            .frame(height: measurements.ruleHeight)
    }
}

private struct WidgetShareLead: View {
    let value: String
    let label: String
    let accentDetail: String?
    let tone: WidgetShareTone
    let measurements: WidgetShareMeasurements
    let font: StatsShareFont

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 9) {
            Text(value)
                .font(font.display(size: measurements.leadSize, weight: .medium))
                .foregroundStyle(tone.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(font.display(size: measurements.detailSize, weight: .regular))
                    .foregroundStyle(tone.secondary)
                    .lineLimit(1)
                if let accentDetail {
                    Text(accentDetail)
                        .font(font.display(size: measurements.labelSize, weight: .semibold))
                        .foregroundStyle(tone.accent)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct WidgetShareDatumView: View {
    let value: WidgetShareDatum
    let tone: WidgetShareTone
    let measurements: WidgetShareMeasurements
    let compact: Bool
    let font: StatsShareFont

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.value)
                .font(font.display(size: compact ? measurements.metricValueSize * 0.88 : measurements.metricValueSize, weight: .semibold))
                .foregroundStyle(tone.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            Text(value.label)
                .font(font.display(size: measurements.labelSize, weight: .regular))
                .foregroundStyle(tone.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WidgetShareTopEntry: View {
    let artist: String?
    let song: String?
    let songArtist: String?
    let tone: WidgetShareTone
    let measurements: WidgetShareMeasurements
    let font: StatsShareFont

    var body: some View {
        VStack(alignment: .leading, spacing: max(3, measurements.spacing * 0.35)) {
            Text(L(.stats_share_top_artist).uppercased())
                .font(font.display(size: measurements.labelSize, weight: .bold))
                .tracking(measurements.labelSize * 0.065)
                .foregroundStyle(tone.secondary)
            Text(artist?.isEmpty == false ? artist! : "—")
                .font(font.display(size: max(17, measurements.leadSize * 0.42), weight: .medium))
                .foregroundStyle(tone.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            if let song, !song.isEmpty {
                Text(songArtist?.isEmpty == false ? "\(song) · \(songArtist!)" : song)
                    .font(font.display(size: measurements.labelSize, weight: .regular))
                    .foregroundStyle(tone.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct ListeningWeekBars: View {
    let days: [ListeningRhythmDay]
    let tone: WidgetShareTone
    let height: CGFloat

    private var values: [Int] {
        let source = days.map(\.plays)
        return source + Array(repeating: 0, count: max(0, 7 - source.count))
    }

    var body: some View {
        let maximum = max(values.max() ?? 0, 1)

        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Rectangle()
                    .fill(index == values.count - 1 ? tone.accent : tone.rule)
                    .frame(height: max(2, CGFloat(value) / CGFloat(maximum) * height))
                    .frame(maxWidth: .infinity, alignment: .bottom)
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L(.stats_share_listening))
    }
}

private struct ListeningRhythmHeatmap: View {
    let days: [ListeningRhythmDay]
    let span: StatsShareRhythmSpan
    let measure: StatsShareRhythmMeasure
    let tone: WidgetShareTone

    private var normalizedDays: [ListeningRhythmDay] {
        let missing = max(0, span.dayCount - days.count)
        guard missing > 0 else { return days }
        let calendar = Calendar.current
        let seed = days.first?.date ?? calendar.startOfDay(for: Date())
        let padding = (0..<missing).map { offset in
            ListeningRhythmDay(
                date: calendar.date(byAdding: .day, value: -(missing - offset), to: seed) ?? seed,
                plays: 0,
                seconds: 0,
                isFuture: false
            )
        }
        return padding + days
    }

    private var maxValue: Int {
        max(normalizedDays.map(value(for:)).max() ?? 0, 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let columns = span.weeks
            let gap = max(1.5, min(5, proxy.size.width * 0.008))
            let cell = max(1, (proxy.size.width - gap * CGFloat(columns - 1)) / CGFloat(columns))

            HStack(spacing: gap) {
                ForEach(0..<columns, id: \.self) { week in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { day in
                            let index = week * 7 + day
                            if normalizedDays.indices.contains(index) {
                                let entry = normalizedDays[index]
                                Rectangle()
                                    .fill(color(for: entry))
                                    .frame(width: cell, height: cell)
                            }
                        }
                    }
                }
            }
        }
        .aspectRatio(CGFloat(span.weeks) / 7, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(L(.stats_share_listening)), \(span.title)")
    }

    private func value(for day: ListeningRhythmDay) -> Int {
        switch measure {
        case .plays: return day.plays
        case .listeningTime: return day.seconds
        }
    }

    private func color(for day: ListeningRhythmDay) -> Color {
        if day.isFuture { return tone.rule.opacity(0.28) }
        let value = value(for: day)
        guard value > 0 else { return tone.rule.opacity(0.72) }

        let normalized = log(Double(value) + 1) / log(Double(maxValue) + 1)
        switch normalized {
        case 0.76...: return tone.accent
        case 0.51...: return tone.accent.opacity(0.74)
        case 0.26...: return tone.accent.opacity(0.48)
        default: return tone.accent.opacity(0.25)
        }
    }
}

private struct WidgetShareLosslessMix: View {
    let library: LibraryStatsData
    let tone: WidgetShareTone
    let measurements: WidgetShareMeasurements
    let font: StatsShareFont

    private var share: Double {
        guard library.totalSongs > 0 else { return 0 }
        return min(1, Double(library.losslessTracks) / Double(library.totalSongs))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(L(.stats_share_lossless_share).uppercased())
                    .font(font.display(size: measurements.labelSize, weight: .bold))
                    .tracking(measurements.labelSize * 0.065)
                    .foregroundStyle(tone.secondary)
                Spacer()
                Text("\(Int((share * 100).rounded()))%")
                    .font(font.display(size: measurements.detailSize, weight: .semibold))
                    .foregroundStyle(tone.accent)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(tone.rule)
                    Rectangle()
                        .fill(tone.accent)
                        .frame(width: proxy.size.width * share)
                }
            }
            .frame(height: max(5, measurements.ruleHeight * 5))
            HStack {
                Text("\(library.losslessTracks.formatted()) \(L(.quality_lossless).lowercased())")
                Spacer()
                Text(library.commonResolution)
            }
            .font(font.display(size: measurements.labelSize, weight: .regular))
            .foregroundStyle(tone.secondary)
            .lineLimit(1)
        }
    }
}
