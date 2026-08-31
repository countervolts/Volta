import SwiftUI

extension SettingsView {
    @ViewBuilder
    var privacySection: some View {
        let section = "Privacy"
        if sectionVisible(section, [["privacy", "diagnostics", "crash reports", "share anonymous crash reports", "crashes", "anonymous"]]) {
            Section {
                AnonymousCrashReportingToggle()
            } header: {
                Text(sectionTitle(section))
            } footer: {
                Text("Automatically sends anonymous technical crash diagnostics to help improve Volta. Reports may include the app version, device model, OS version, and crash stack trace. Music library contents, account information, server addresses, and credentials are not included.")
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }
}

private struct AnonymousCrashReportingToggle: View {
    @AppStorage(CrashReportingService.preferenceKey) private var isEnabled = false

    var body: some View {
        Toggle(isOn: $isEnabled) {
            Label("Share Anonymous Crash Reports", systemImage: "exclamationmark.shield")
        }
        .tint(Theme.accent)
        .onChangeCompat(of: isEnabled) { _, enabled in
            CrashReportingService.shared.setEnabled(enabled)
        }
    }
}
