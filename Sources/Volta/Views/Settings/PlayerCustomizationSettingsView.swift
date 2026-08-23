import SwiftUI

struct PlayerCustomizationSettingsView: View {
    @StateObject private var preferences = PlayerControlPreferences.shared

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                Section {
                    ForEach(preferences.visibleActions) { action in
                        HStack(spacing: 12) {
                            Image(systemName: action.icon)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 22)
                            Text(action.title)
                                .foregroundStyle(Theme.primaryText)
                            Spacer()
                            Button {
                                preferences.remove(action)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(preferences.canRemove ? Theme.error : Theme.secondaryText)
                            }
                            .buttonStyle(.plain)
                            .disabled(!preferences.canRemove)
                            .accessibilityLabel("Remove \(action.title)")
                        }
                    }
                    .onMove(perform: preferences.move)
                } header: {
                    Text("Player Controls")
                } footer: {
                    Text("Drag to change the order. Keep at least \(PlayerControlPreferences.minimumVisibleControls) and up to \(PlayerControlPreferences.maximumVisibleControls) controls in the player.")
                }
                .listRowBackground(Theme.secondaryBackground)

                if !preferences.hiddenActions.isEmpty {
                    Section("Add Controls") {
                        ForEach(preferences.hiddenActions) { action in
                            Button {
                                preferences.add(action)
                            } label: {
                                Label(action.title, systemImage: "plus.circle")
                                    .foregroundStyle(preferences.canAdd ? Theme.primaryText : Theme.secondaryText)
                            }
                            .disabled(!preferences.canAdd)
                        }
                    }
                    .listRowBackground(Theme.secondaryBackground)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle("Player Controls")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Restore") { preferences.reset() }
                    .foregroundStyle(Theme.accent)
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
                    .foregroundStyle(Theme.accent)
            }
        }
        .preferredColorScheme(Theme.colorScheme)
    }
}
