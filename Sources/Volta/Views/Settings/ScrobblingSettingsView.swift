import SwiftUI

extension SettingsView {
    @ViewBuilder
    var scrobblingSection: some View {
        let s = "Scrobbling"
        if sectionVisible(s, [["last.fm", "lastfm", "koito", "maloja", "listenbrainz", "third party", "external scrobbling", "stats"]]) {
            Section {
                NavigationLink(value: SettingsRoute.scrobbling) {
                    HStack {
                        Label("Third-Party Scrobbling", systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        Text(scrobblingSummary)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .foregroundStyle(Theme.primaryText)
            } header: {
                Text(s)
            } footer: {
                Text("External scrobbling is additive. Volta still records local listening stats for the Stats tab.")
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    private var scrobblingSummary: String {
        let names = ScrobbleProviderSettings.activeProviderNames
        return names.isEmpty ? "Off" : names.joined(separator: ", ")
    }
}

struct ScrobblingSettingsView: View {
    @AppStorage(ScrobbleProviderSettings.Keys.lastFMEnabled) private var lastFMEnabled = false
    @AppStorage(ScrobbleProviderSettings.Keys.lastFMAPIKey) private var lastFMAPIKey = ""
    @AppStorage(ScrobbleProviderSettings.Keys.lastFMUsername) private var lastFMUsername = ""

    @AppStorage(ScrobbleProviderSettings.Keys.koitoEnabled) private var koitoEnabled = false
    @AppStorage(ScrobbleProviderSettings.Keys.koitoURL) private var koitoURL = ""

    @AppStorage(ScrobbleProviderSettings.Keys.malojaEnabled) private var malojaEnabled = false
    @AppStorage(ScrobbleProviderSettings.Keys.malojaURL) private var malojaURL = ""

    @State private var lastFMSecret = ""
    @State private var lastFMSessionKey = ""
    @State private var lastFMPassword = ""
    @State private var lastFMStatus: ProviderStatus?
    @State private var koitoToken = ""
    @State private var koitoStatus: ProviderStatus?
    @State private var malojaKey = ""
    @State private var malojaStatus: ProviderStatus?
    @State private var busyProvider: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                Section {
                    Text("Volta records local play events before any external request is made, so the built-in Stats tab keeps working even if a scrobbling service is offline.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .listRowBackground(Theme.secondaryBackground)

                lastFMSection
                koitoSection
                malojaSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle("Scrobbling")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
        }
        .preferredColorScheme(Theme.colorScheme)
        .onAppear(perform: loadSecrets)
        .onDisappear(perform: saveSecrets)
        .onChangeCompat(of: lastFMSecret) { _, _ in saveLastFMSecrets() }
        .onChangeCompat(of: lastFMSessionKey) { _, _ in saveLastFMSecrets() }
        .onChangeCompat(of: koitoToken) { _, _ in saveKoitoSecret() }
        .onChangeCompat(of: malojaKey) { _, _ in saveMalojaSecret() }
    }

    private var lastFMSection: some View {
        Section {
            Toggle(isOn: $lastFMEnabled) {
                Label("Enable Last.fm", systemImage: "record.circle")
            }
            .tint(Theme.accent)

            TextField("API Key", text: $lastFMAPIKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("Shared Secret", text: $lastFMSecret)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("Session Key", text: $lastFMSessionKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField("Username", text: $lastFMUsername)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("Password for Session Key", text: $lastFMPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                authenticateLastFM()
            } label: {
                providerButtonLabel(title: "Get Last.fm Session Key", provider: "lastfm")
            }
            .disabled(!canAuthenticateLastFM || busyProvider != nil)

            Button {
                validateLastFM()
            } label: {
                providerButtonLabel(title: "Test Last.fm", provider: "lastfm-test")
            }
            .disabled(!canTestLastFM || busyProvider != nil)

            if let lastFMStatus {
                ProviderStatusRow(status: lastFMStatus)
            }
        } header: {
            Text("Last.fm")
        } footer: {
            Text("Use your Last.fm API account details. The password is only used to request a session key and is not stored.")
        }
        .listRowBackground(Theme.secondaryBackground)
    }

    private var koitoSection: some View {
        Section {
            Toggle(isOn: $koitoEnabled) {
                Label("Enable Koito", systemImage: "music.quarternote.3")
            }
            .tint(Theme.accent)

            TextField("Koito URL", text: $koitoURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("API Key", text: $koitoToken)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                validateKoito()
            } label: {
                providerButtonLabel(title: "Test Koito", provider: "koito")
            }
            .disabled(!canTestKoito || busyProvider != nil)

            if let koitoStatus {
                ProviderStatusRow(status: koitoStatus)
            }
        } header: {
            Text("Koito")
        } footer: {
            Text("Enter your Koito instance URL and the API key from Koito settings. Volta submits to its ListenBrainz-compatible endpoint.")
        }
        .listRowBackground(Theme.secondaryBackground)
    }

    private var malojaSection: some View {
        Section {
            Toggle(isOn: $malojaEnabled) {
                Label("Enable Maloja", systemImage: "chart.line.uptrend.xyaxis")
            }
            .tint(Theme.accent)

            TextField("Maloja URL", text: $malojaURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("API Key", text: $malojaKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                validateMaloja()
            } label: {
                providerButtonLabel(title: "Test Maloja", provider: "maloja")
            }
            .disabled(!canTestMaloja || busyProvider != nil)

            if let malojaStatus {
                ProviderStatusRow(status: malojaStatus)
            }
        } header: {
            Text("Maloja")
        } footer: {
            Text("Enter your Maloja instance URL and one of its API keys. Volta uses Maloja's native scrobble endpoint so listened duration is preserved.")
        }
        .listRowBackground(Theme.secondaryBackground)
    }

    private var canAuthenticateLastFM: Bool {
        !lastFMUsername.trimmedForSettings.isEmpty
            && !lastFMPassword.isEmpty
            && !lastFMAPIKey.trimmedForSettings.isEmpty
            && !lastFMSecret.trimmedForSettings.isEmpty
    }

    private var canTestLastFM: Bool {
        !lastFMAPIKey.trimmedForSettings.isEmpty
            && !lastFMSecret.trimmedForSettings.isEmpty
            && !lastFMSessionKey.trimmedForSettings.isEmpty
    }

    private var canTestKoito: Bool {
        !koitoURL.trimmedForSettings.isEmpty && !koitoToken.trimmedForSettings.isEmpty
    }

    private var canTestMaloja: Bool {
        !malojaURL.trimmedForSettings.isEmpty && !malojaKey.trimmedForSettings.isEmpty
    }

    private func providerButtonLabel(title: String, provider: String) -> some View {
        HStack {
            Label(title, systemImage: "checkmark.shield")
            Spacer()
            if busyProvider == provider {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.accent)
            }
        }
    }

    private func loadSecrets() {
        lastFMSecret = ScrobbleProviderSettings.secret(for: ScrobbleProviderSettings.SecretAccounts.lastFMSecret)
        lastFMSessionKey = ScrobbleProviderSettings.secret(for: ScrobbleProviderSettings.SecretAccounts.lastFMSessionKey)
        koitoToken = ScrobbleProviderSettings.secret(for: ScrobbleProviderSettings.SecretAccounts.koitoToken)
        malojaKey = ScrobbleProviderSettings.secret(for: ScrobbleProviderSettings.SecretAccounts.malojaKey)
    }

    private func saveSecrets() {
        saveLastFMSecrets()
        saveKoitoSecret()
        saveMalojaSecret()
    }

    private func saveLastFMSecrets() {
        ScrobbleProviderSettings.saveSecret(lastFMSecret, for: ScrobbleProviderSettings.SecretAccounts.lastFMSecret)
        ScrobbleProviderSettings.saveSecret(lastFMSessionKey, for: ScrobbleProviderSettings.SecretAccounts.lastFMSessionKey)
    }

    private func saveKoitoSecret() {
        ScrobbleProviderSettings.saveSecret(koitoToken, for: ScrobbleProviderSettings.SecretAccounts.koitoToken)
    }

    private func saveMalojaSecret() {
        ScrobbleProviderSettings.saveSecret(malojaKey, for: ScrobbleProviderSettings.SecretAccounts.malojaKey)
    }

    private func authenticateLastFM() {
        busyProvider = "lastfm"
        lastFMStatus = nil
        Task {
            defer { busyProvider = nil }
            do {
                let session = try await ThirdPartyScrobbler.shared.authenticateLastFM(
                    username: lastFMUsername,
                    password: lastFMPassword,
                    apiKey: lastFMAPIKey,
                    secret: lastFMSecret
                )
                lastFMUsername = session.username
                lastFMSessionKey = session.sessionKey
                lastFMPassword = ""
                saveLastFMSecrets()
                lastFMStatus = .success("Authenticated as \(session.username).")
                VoltaNotificationCenter.shared.post("Last.fm connected", tone: .success)
            } catch {
                lastFMStatus = .failure(error.localizedDescription)
                VoltaNotificationCenter.shared.post("Last.fm failed: \(error.localizedDescription)", tone: .error)
            }
        }
    }

    private func validateLastFM() {
        busyProvider = "lastfm-test"
        lastFMStatus = nil
        Task {
            defer { busyProvider = nil }
            do {
                let username = try await ThirdPartyScrobbler.shared.validateLastFM(
                    apiKey: lastFMAPIKey,
                    secret: lastFMSecret,
                    sessionKey: lastFMSessionKey
                )
                if let username, !username.isEmpty { lastFMUsername = username }
                lastFMStatus = .success(username.map { "Connected as \($0)." } ?? "Connected.")
                VoltaNotificationCenter.shared.post("Last.fm test passed", tone: .success)
            } catch {
                lastFMStatus = .failure(error.localizedDescription)
                VoltaNotificationCenter.shared.post("Last.fm test failed", tone: .error)
            }
        }
    }

    private func validateKoito() {
        busyProvider = "koito"
        koitoStatus = nil
        Task {
            defer { busyProvider = nil }
            do {
                try await ThirdPartyScrobbler.shared.validateKoito(urlString: koitoURL, token: koitoToken)
                koitoStatus = .success("Connected.")
                VoltaNotificationCenter.shared.post("Koito test passed", tone: .success)
            } catch {
                koitoStatus = .failure(error.localizedDescription)
                VoltaNotificationCenter.shared.post("Koito test failed", tone: .error)
            }
        }
    }

    private func validateMaloja() {
        busyProvider = "maloja"
        malojaStatus = nil
        Task {
            defer { busyProvider = nil }
            do {
                try await ThirdPartyScrobbler.shared.validateMaloja(urlString: malojaURL, key: malojaKey)
                malojaStatus = .success("Connected.")
                VoltaNotificationCenter.shared.post("Maloja test passed", tone: .success)
            } catch {
                malojaStatus = .failure(error.localizedDescription)
                VoltaNotificationCenter.shared.post("Maloja test failed", tone: .error)
            }
        }
    }
}

private enum ProviderStatus: Equatable {
    case success(String)
    case failure(String)

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: return .green
        case .failure: return Theme.error
        }
    }

    var message: String {
        switch self {
        case .success(let message), .failure(let message):
            return message
        }
    }
}

private struct ProviderStatusRow: View {
    let status: ProviderStatus

    var body: some View {
        Label(status.message, systemImage: status.icon)
            .font(.footnote)
            .foregroundStyle(status.color)
    }
}

private extension String {
    var trimmedForSettings: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
