import SwiftUI

extension SettingsView {
    // MARK: - Notifications

    @ViewBuilder
    var notificationsSection: some View {
        let s = "Notifications"
        if sectionVisible(s, [["test all notifications", "notifications", "toast", "error", "warning", "success", "queue", "info"]]) {
            Section {
                Button {
                    VoltaNotificationCenter.shared.postTestNotifications()
                } label: {
                    Label("Test All Notifications", systemImage: "bell.badge")
                }
                .foregroundStyle(Theme.primaryText)

                ForEach(VoltaNotificationTone.allCases) { tone in
                    Button {
                        VoltaNotificationCenter.shared.post(tone.testMessage, tone: tone)
                    } label: {
                        Label("Test \(tone.settingsLabel)", systemImage: tone.icon)
                    }
                    .foregroundStyle(Theme.primaryText)
                }
            } header: {
                Text(sectionTitle(s))
            } footer: {
                Text("Warnings and errors logged by the app show automatically. Use these buttons to preview every notification style.")
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }
}

struct NotificationSettingsView: View {
    @AppStorage("showWarningNotifications") private var showWarningNotifications = false
    @AppStorage("showOfflineErrorNotifications") private var showOfflineErrorNotifications = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                Section {
                    Toggle(isOn: $showWarningNotifications) {
                        Label("Show Warning Notifications", systemImage: Symbols.warning)
                    }
                    .tint(Theme.accent)

                    Toggle(isOn: $showOfflineErrorNotifications) {
                        Label("Show Offline Error Notifications", systemImage: "wifi.slash")
                    }
                    .tint(Theme.accent)
                } footer: {
                    Text("Warnings and offline error notifications stay hidden unless enabled. The app keeps logging them.")
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    Button {
                        VoltaNotificationCenter.shared.postTestNotifications()
                    } label: {
                        Label("Preview All", systemImage: "bell.badge")
                    }
                    .foregroundStyle(Theme.primaryText)

                    ForEach(VoltaNotificationTone.allCases) { tone in
                        Button {
                            VoltaNotificationCenter.shared.post(tone.testMessage, tone: tone, force: true)
                        } label: {
                            Label("Preview \(tone.settingsLabel)", systemImage: tone.icon)
                        }
                        .foregroundStyle(Theme.primaryText)
                    }
                } header: {
                    Text("Previews")
                }
                .listRowBackground(Theme.secondaryBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
        }
        .preferredColorScheme(Theme.colorScheme)
    }
}
