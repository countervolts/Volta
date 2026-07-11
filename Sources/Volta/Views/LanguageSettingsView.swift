import SwiftUI

// Full-screen language picker; shares state with login.
struct LanguageSettingsView: View {
    @StateObject private var localization = LocalizationManager.shared

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                Section {
                    ForEach(AppLanguage.allCases) { language in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                localization.language = language
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Text(language.endonym)
                                    .foregroundStyle(Theme.primaryText)
                                Spacer()
                                if localization.language == language {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text(L(.language_picker_footer))
                }
                .listRowBackground(Theme.secondaryBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle(L(.settings_language))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
        }
        .preferredColorScheme(Theme.colorScheme)
    }
}
