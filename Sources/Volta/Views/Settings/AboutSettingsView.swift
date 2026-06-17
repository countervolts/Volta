import SwiftUI

extension SettingsView {
    // MARK: - About

    @ViewBuilder
    var aboutSection: some View {
        let s = "About"
        if sectionVisible(s, [["app", "version", "build", "volta"]]) {
        Section(sectionTitle(s)) {
            LabeledContent("App", value: "Volta")
                .foregroundStyle(Theme.primaryText)
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                LabeledContent("Version", value: version)
                    .foregroundStyle(Theme.primaryText)
                    .contentShape(Rectangle())
                    .onTapGesture { registerSecretDeveloperTap() }
            }
            if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                LabeledContent("Build", value: build)
                    .foregroundStyle(Theme.primaryText)
                    .contentShape(Rectangle())
                    .onTapGesture { registerSecretDeveloperTap() }
            }
        }
        .listRowBackground(Theme.secondaryBackground)
        }
    }
}
