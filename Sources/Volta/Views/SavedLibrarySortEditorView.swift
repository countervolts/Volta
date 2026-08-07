import SwiftUI

struct SavedLibrarySortEditorContext: Identifiable, Hashable {
    let target: SavedLibrarySortTarget
    let sort: SavedLibrarySort?

    var id: String {
        sort?.id ?? "new-\(target.rawValue)"
    }
}

struct SavedLibrarySortEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = SavedLibrarySortStore.shared

    @State private var draft: SavedLibrarySort
    @State private var criteriaDestination: CriteriaDestination?

    let previewCountProvider: ((SavedLibrarySort) -> Int)?
    let onSave: (SavedLibrarySort) -> Void

    init(
        target: SavedLibrarySortTarget,
        sort: SavedLibrarySort? = nil,
        previewCountProvider: ((SavedLibrarySort) -> Int)? = nil,
        onSave: @escaping (SavedLibrarySort) -> Void
    ) {
        _draft = State(initialValue: sort ?? SavedLibrarySort.draft(target: target))
        self.previewCountProvider = previewCountProvider
        self.onSave = onSave
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                savedViewSection
                quickFiltersSection
                smartFilterSection
                ruleGroupSections
                viewSection
                sortSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle(L(.library_view_filter_settings))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(L(.action_cancel)) { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(L(.action_save)) { save() }
                    .fontWeight(.semibold)
                    .disabled(saveDisabled)
            }
        }
        .sheet(item: $criteriaDestination) { destination in
            SavedLibraryCriteriaPickerView(target: draft.target) { field in
                addFilter(field, to: destination)
                criteriaDestination = nil
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .tint(Theme.accent)
        .preferredColorScheme(Theme.colorScheme)
    }

    private var savedViewSection: some View {
        Section {
            TextField(L(.sort_name), text: $draft.name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            if let previewCountProvider {
                Text(L(.library_view_matching_now, previewCountProvider(normalizedDraft()), draft.target.label.lowercased()))
                    .foregroundStyle(Theme.primaryText)
            }
        } header: {
            Text(L(.library_view_saved_view))
        } footer: {
            Text(L(.library_view_saved_footer, draft.target.label.lowercased()))
        }
        .listRowBackground(Theme.secondaryBackground)
    }

    private var quickFiltersSection: some View {
        Section {
            Toggle(isOn: $draft.onlyFavorites) {
                Label(L(.library_view_only_favorites), systemImage: "star.fill")
            }
            .tint(Theme.accent)

            if draft.target == .albums {
                Toggle(isOn: $draft.hideSmallAlbums) {
                    Label(L(.library_view_hide_small_albums), systemImage: "rectangle.stack.badge.minus")
                }
                .tint(Theme.accent)
            }
        } header: {
            Text(L(.library_view_quick_filters))
        }
        .listRowBackground(Theme.secondaryBackground)
    }

    private var smartFilterSection: some View {
        Section {
            Picker(L(.smart_match), selection: $draft.filterMatchMode) {
                ForEach(SavedLibraryRuleMatchMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if draft.filters.isEmpty && draft.groups.isEmpty {
                Text(L(.library_view_no_rules))
                    .foregroundStyle(.secondary)
            }

            ForEach($draft.filters) { $filter in
                SavedLibraryFilterRuleRow(target: draft.target, filter: $filter)
                    .swipeActions {
                        Button(role: .destructive) {
                            removeFilter(id: filter.id)
                        } label: {
                            Label(L(.action_delete), systemImage: Symbols.trash)
                        }
                    }
            }

            Button {
                criteriaDestination = .direct
            } label: {
                Label(L(.library_view_add_rule), systemImage: "plus.circle.fill")
            }

            Button {
                addGroup()
            } label: {
                Label(L(.library_view_add_rule_group), systemImage: "rectangle.stack.badge.plus")
            }

            loadMenu

            Button(role: .destructive) {
                clearDraftRules()
            } label: {
                Label(L(.library_view_clear_filter), systemImage: "xmark.circle")
            }
        } header: {
            Text(L(.library_view_smart_filter))
        } footer: {
            Text(L(.library_view_smart_filter_footer))
        }
        .listRowBackground(Theme.secondaryBackground)
    }

    @ViewBuilder
    private var ruleGroupSections: some View {
        ForEach($draft.groups) { $group in
            Section {
                Picker(L(.smart_match), selection: $group.matchMode) {
                    ForEach(SavedLibraryRuleMatchMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                ForEach($group.filters) { $filter in
                    SavedLibraryFilterRuleRow(target: draft.target, filter: $filter)
                        .swipeActions {
                            Button(role: .destructive) {
                                removeFilter(filter.id, fromGroup: group.id)
                            } label: {
                                Label(L(.action_delete), systemImage: Symbols.trash)
                            }
                        }
                }

                Button {
                    criteriaDestination = .group(group.id)
                } label: {
                    Label(L(.library_view_add_rule), systemImage: "plus.circle.fill")
                }

                Button(role: .destructive) {
                    removeGroup(id: group.id)
                } label: {
                    Label(L(.library_view_delete_rule_group), systemImage: Symbols.trash)
                }
            } header: {
                Text(L(.library_view_rule_group))
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    private var viewSection: some View {
        Section {
            Picker(L(.library_view_group_by), selection: $draft.groupMode) {
                ForEach(SavedLibraryGroupMode.modes(for: draft.target)) { mode in
                    Text(mode.label(for: draft.target)).tag(mode)
                }
            }
        } header: {
            Text(L(.library_view_view))
        }
        .listRowBackground(Theme.secondaryBackground)
    }

    private var sortSection: some View {
        Section {
            ForEach($draft.rules) { $rule in
                SavedLibrarySortRuleRow(
                    target: draft.target,
                    rule: $rule,
                    canMoveUp: canMoveUp(rule.id),
                    canMoveDown: canMoveDown(rule.id),
                    canDelete: draft.rules.count > 1,
                    onMoveUp: { moveRule(id: rule.id, delta: -1) },
                    onMoveDown: { moveRule(id: rule.id, delta: 1) },
                    onDelete: { removeRule(id: rule.id) }
                )
            }

            Button {
                addSortRule()
            } label: {
                Label(L(.library_view_add_sort_rule), systemImage: "plus.circle.fill")
            }
        } header: {
            Text(L(.smart_sort))
        }
        .listRowBackground(Theme.secondaryBackground)
    }

    private var loadMenu: some View {
        Menu {
            let saved = store.sorts(for: draft.target)
            if saved.isEmpty {
                Button(L(.library_view_no_saved)) {}
                    .disabled(true)
            } else {
                ForEach(saved) { view in
                    Button(view.name) {
                        draft = view
                    }
                }
            }
        } label: {
            Label(L(.library_view_load_saved), systemImage: "tray.and.arrow.down")
        }
    }

    private var saveDisabled: Bool {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.rules.isEmpty
    }

    private func addFilter(_ field: SavedLibraryFilterField, to destination: CriteriaDestination) {
        let filter = SavedLibraryFilterRule(field: field)
        switch destination {
        case .direct:
            draft.filters.append(filter)
        case .group(let id):
            guard let index = draft.groups.firstIndex(where: { $0.id == id }) else { return }
            draft.groups[index].filters.append(filter)
        }
    }

    private func removeFilter(id: String) {
        draft.filters.removeAll { $0.id == id }
    }

    private func addGroup() {
        let firstField = SavedLibraryFilterField.fields(for: draft.target).first ?? .artist
        draft.groups.append(
            SavedLibraryFilterGroup(filters: [SavedLibraryFilterRule(field: firstField)])
        )
    }

    private func removeGroup(id: String) {
        draft.groups.removeAll { $0.id == id }
    }

    private func removeFilter(_ filterID: String, fromGroup groupID: String) {
        guard let index = draft.groups.firstIndex(where: { $0.id == groupID }) else { return }
        draft.groups[index].filters.removeAll { $0.id == filterID }
        if draft.groups[index].filters.isEmpty {
            draft.groups.remove(at: index)
        }
    }

    private func addSortRule() {
        let existing = Set(draft.rules.map(\.field))
        let field = SavedLibrarySortField.fields(for: draft.target)
            .first { !existing.contains($0) }
            ?? SavedLibrarySortField.fields(for: draft.target).first
            ?? .name
        draft.rules.append(SavedLibrarySortRule(field: field, direction: .ascending))
    }

    private func removeRule(id: String) {
        guard draft.rules.count > 1 else { return }
        draft.rules.removeAll { $0.id == id }
    }

    private func moveRule(id: String, delta: Int) {
        guard let index = draft.rules.firstIndex(where: { $0.id == id }) else { return }
        let newIndex = index + delta
        guard draft.rules.indices.contains(newIndex) else { return }
        draft.rules.swapAt(index, newIndex)
    }

    private func canMoveUp(_ id: String) -> Bool {
        guard let index = draft.rules.firstIndex(where: { $0.id == id }) else { return false }
        return index > 0
    }

    private func canMoveDown(_ id: String) -> Bool {
        guard let index = draft.rules.firstIndex(where: { $0.id == id }) else { return false }
        return index < draft.rules.count - 1
    }

    private func clearDraftRules() {
        draft.onlyFavorites = false
        draft.hideSmallAlbums = false
        draft.filterMatchMode = .all
        draft.filters = []
        draft.groups = []
        draft.groupMode = .none
        draft.rules = draft.target.defaultRules
    }

    private func save() {
        let normalized = normalizedDraft()
        onSave(normalized)
        dismiss()
    }

    private func normalizedDraft() -> SavedLibrarySort {
        var normalized = draft
        normalized.name = normalized.name.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.filters = normalized.filters.compactMap(normalizedFilter)
        normalized.groups = normalized.groups.compactMap { group in
            let filters = group.filters.compactMap(normalizedFilter)
            guard !filters.isEmpty else { return nil }
            var normalizedGroup = group
            normalizedGroup.filters = filters
            return normalizedGroup
        }
        if !normalized.groupMode.isSupported(for: normalized.target) {
            normalized.groupMode = .none
        }
        normalized.rules = normalized.rules.filter { $0.field.isSupported(for: normalized.target) }
        if normalized.rules.isEmpty {
            normalized.rules = normalized.target.defaultRules
        }
        return normalized
    }

    private func normalizedFilter(_ filter: SavedLibraryFilterRule) -> SavedLibraryFilterRule? {
        guard filter.field.isSupported(for: draft.target),
              filter.comparisonIsValid else { return nil }
        var trimmed = filter
        trimmed.value = trimmed.value.trimmingCharacters(in: .whitespacesAndNewlines)
        trimmed.secondaryValue = trimmed.secondaryValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.comparison.needsPrimaryValue && trimmed.value.isEmpty { return nil }
        if trimmed.comparison.needsSecondaryValue && trimmed.secondaryValue.isEmpty { return nil }
        return trimmed
    }

    private enum CriteriaDestination: Identifiable {
        case direct
        case group(String)

        var id: String {
            switch self {
            case .direct: return "direct"
            case .group(let id): return "group-\(id)"
            }
        }
    }
}

private struct SavedLibraryFilterRuleRow: View {
    let target: SavedLibrarySortTarget
    @Binding var filter: SavedLibraryFilterRule

    private var comparisonOptions: [SavedLibraryFilterComparison] {
        SavedLibraryFilterComparison.comparisons(for: filter.field)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(L(.library_view_criteria), selection: fieldBinding) {
                ForEach(SavedLibraryFilterField.fields(for: target)) { field in
                    Label(field.label(for: target), systemImage: field.systemImage(for: target))
                        .tag(field)
                }
            }

            Picker(L(.library_view_condition), selection: comparisonBinding) {
                ForEach(comparisonOptions) { comparison in
                    Text(comparison.label).tag(comparison)
                }
            }

            if filter.comparison.needsPrimaryValue {
                TextField(primaryPlaceholder, text: $filter.value)
                    .keyboardType(filter.field.valueKind == .number ? .decimalPad : .default)
                    .textInputAutocapitalization(filter.field.valueKind == .text ? .words : .never)
                    .autocorrectionDisabled()
            }

            if filter.comparison.needsSecondaryValue {
                TextField(L(.library_view_maximum), text: $filter.secondaryValue)
                    .keyboardType(.decimalPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .foregroundStyle(Theme.primaryText)
    }

    private var primaryPlaceholder: String {
        switch filter.field.valueKind {
        case .text: return L(.library_view_value)
        case .number:
            return filter.comparison == .between ? L(.library_view_minimum) : L(.library_view_value)
        case .boolean: return ""
        }
    }

    private var fieldBinding: Binding<SavedLibraryFilterField> {
        Binding(
            get: { filter.field },
            set: { newField in
                filter.field = newField
                let comparisons = SavedLibraryFilterComparison.comparisons(for: newField)
                if !comparisons.contains(filter.comparison) {
                    filter.comparison = comparisons.first ?? .contains
                    filter.value = ""
                    filter.secondaryValue = ""
                }
            }
        )
    }

    private var comparisonBinding: Binding<SavedLibraryFilterComparison> {
        Binding(
            get: { filter.comparison },
            set: { newComparison in
                filter.comparison = newComparison
                if !newComparison.needsPrimaryValue {
                    filter.value = ""
                    filter.secondaryValue = ""
                } else if !newComparison.needsSecondaryValue {
                    filter.secondaryValue = ""
                }
            }
        )
    }
}

private struct SavedLibrarySortRuleRow: View {
    let target: SavedLibrarySortTarget
    @Binding var rule: SavedLibrarySortRule
    let canMoveUp: Bool
    let canMoveDown: Bool
    let canDelete: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(L(.library_view_sort_by), selection: $rule.field) {
                ForEach(SavedLibrarySortField.fields(for: target)) { field in
                    Label(field.label(for: target), systemImage: field.systemImage(for: target))
                        .tag(field)
                }
            }

            Picker(L(.library_view_order), selection: $rule.direction) {
                ForEach(SavedLibrarySortDirection.allCases) { direction in
                    Text(direction.label).tag(direction)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 22) {
                Button(action: onMoveUp) {
                    Label(L(.library_view_earlier), systemImage: "chevron.up")
                        .labelStyle(.iconOnly)
                }
                .disabled(!canMoveUp)
                .accessibilityLabel(L(.library_view_move_earlier))

                Button(action: onMoveDown) {
                    Label(L(.library_view_later), systemImage: "chevron.down")
                        .labelStyle(.iconOnly)
                }
                .disabled(!canMoveDown)
                .accessibilityLabel(L(.library_view_move_later))

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Label(L(.action_delete), systemImage: Symbols.trash)
                        .labelStyle(.iconOnly)
                }
                .disabled(!canDelete)
            }
            .buttonStyle(.borderless)
        }
        .foregroundStyle(Theme.primaryText)
    }
}

private struct SavedLibraryCriteriaPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let target: SavedLibrarySortTarget
    let onSelect: (SavedLibraryFilterField) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                List {
                    ForEach(criteriaSections) { section in
                        Section(section.title) {
                            ForEach(section.fields) { field in
                                Button {
                                    onSelect(field)
                                } label: {
                                    Label {
                                        Text(field.label(for: target))
                                            .foregroundStyle(Theme.primaryText)
                                    } icon: {
                                        Image(systemName: field.systemImage(for: target))
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                            }
                        }
                        .listRowBackground(Theme.secondaryBackground)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Theme.background)
            }
            .navigationTitle(L(.library_view_choose_criteria))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L(.action_cancel)) { dismiss() }
                }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(Theme.colorScheme)
    }

    private var criteriaSections: [CriteriaSection] {
        switch target {
        case .albums:
            return [
                CriteriaSection(title: L(.media_album), fields: [.title, .artist, .tag, .year, .songCount]),
                CriteriaSection(title: L(.library_view_stats), fields: [.duration, .playCount]),
                CriteriaSection(title: L(.library_view_status), fields: [.starred])
            ].supported(for: target)
        case .songs:
            return [
                CriteriaSection(title: L(.smart_sort_title), fields: [.title]),
                CriteriaSection(title: L(.media_album), fields: [.album, .albumArtist, .tag, .year]),
                CriteriaSection(title: L(.media_artist), fields: [.artist]),
                CriteriaSection(title: L(.library_view_stats), fields: [.duration, .playCount]),
                CriteriaSection(title: L(.library_view_audio), fields: [.lossless, .hiRes, .bitRate, .fileSize, .explicit]),
                CriteriaSection(title: L(.library_view_status), fields: [.starred, .downloaded])
            ].supported(for: target)
        }
    }
}

private struct CriteriaSection: Identifiable {
    let title: String
    var fields: [SavedLibraryFilterField]

    var id: String { title }
}

private extension Array where Element == CriteriaSection {
    func supported(for target: SavedLibrarySortTarget) -> [CriteriaSection] {
        compactMap { section in
            let fields = section.fields.filter { $0.isSupported(for: target) }
            guard !fields.isEmpty else { return nil }
            return CriteriaSection(title: section.title, fields: fields)
        }
    }
}

private extension SavedLibraryFilterField {
    func systemImage(for target: SavedLibrarySortTarget) -> String {
        switch self {
        case .title:
            return target == .albums ? "square.stack" : "music.note"
        case .artist:
            return "person"
        case .album:
            return "square.stack"
        case .albumArtist:
            return "person.2"
        case .tag:
            return "tag"
        case .year:
            return "calendar"
        case .duration:
            return "timer"
        case .playCount:
            return "play.circle"
        case .songCount:
            return "number"
        case .downloaded:
            return "arrow.down.circle"
        case .lossless:
            return "waveform"
        case .hiRes:
            return "hifispeaker"
        case .explicit:
            return "exclamationmark.circle"
        case .starred:
            return "star"
        case .bitRate:
            return "speedometer"
        case .fileSize:
            return "externaldrive"
        }
    }
}

private extension SavedLibrarySortField {
    func systemImage(for target: SavedLibrarySortTarget) -> String {
        switch self {
        case .name:
            return target == .albums ? "square.stack" : "music.note"
        case .artist:
            return "person"
        case .album:
            return "square.stack"
        case .albumArtist:
            return "person.2"
        case .year:
            return "calendar"
        case .genre:
            return "tag"
        case .duration:
            return "timer"
        case .playCount:
            return "play.circle"
        case .recentlyAdded:
            return "clock"
        case .songCount:
            return "number"
        case .discNumber:
            return "opticaldisc"
        case .trackNumber:
            return "number"
        case .bitRate:
            return "speedometer"
        case .fileSize:
            return "externaldrive"
        }
    }
}
