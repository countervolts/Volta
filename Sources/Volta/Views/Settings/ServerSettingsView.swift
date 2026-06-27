import SwiftUI

extension SettingsView {
    // MARK: - Server

    @ViewBuilder
    var serverSection: some View {
        let s = "Server"
        if sectionVisible(s, [["connected to", "server url", "cellular url", "data", "wifi", "username", "edit connection", "test connection", "log out", "logout", "sign out"], ["server health & speed test", "speed test", "server health", "latency", "connection"]]) {
        Section(sectionTitle(s)) {
            if let server = appState.currentServer {
                LabeledContent("Connected to", value: server.displayName)
                    .foregroundStyle(Theme.primaryText)
                LabeledContent("Server URL", value: server.urlString)
                    .foregroundStyle(Theme.primaryText)
                if let cell = server.cellularURLString, !cell.isEmpty {
                    LabeledContent("Cellular URL", value: cell)
                        .foregroundStyle(Theme.primaryText)
                }
                if let cellularUsername = server.cellularUsername, !cellularUsername.isEmpty {
                    LabeledContent("Cellular Username", value: cellularUsername)
                        .foregroundStyle(Theme.primaryText)
                }
                LabeledContent("Username", value: server.username)
                    .foregroundStyle(Theme.primaryText)

                NavigationLink(value: SettingsRoute.editConnection) {
                    Label("Edit Connection", systemImage: Symbols.edit)
                }
                .foregroundStyle(Theme.primaryText)
            }

            Button {
                isTesting = true
                connectionStatus = ""
                Task {
                    defer { isTesting = false }
                    do {
                        try await appState.client?.ping()
                        connectionStatus = "✓ Connected"
                        VoltaNotificationCenter.shared.post(L(.notif_connection_test_passed), tone: .success)
                    } catch {
                        connectionStatus = "✗ \(error.localizedDescription)"
                        VoltaNotificationCenter.shared.post(L(.notif_connection_test_failed), tone: .error)
                    }
                }
            } label: {
                HStack {
                    Label("Test Connection", systemImage: "network")
                    Spacer()
                    if isTesting {
                        ProgressView().controlSize(.small).tint(Theme.accent)
                    } else if !connectionStatus.isEmpty {
                        Text(connectionStatus)
                            .font(.caption)
                            .foregroundStyle(connectionStatus.hasPrefix("✓") ? .green : Theme.error)
                    }
                }
            }
            .foregroundStyle(Theme.primaryText)

            if rowVisible(s, ["server health & speed test", "speed test", "server health", "latency", "connection"]) {
                NavigationLink(value: SettingsRoute.serverInfo) {
                    Label("Server Health & Speed Test", systemImage: "speedometer")
                }
                .foregroundStyle(Theme.primaryText)
            }

            Button(role: .destructive) {
                showLogoutAlert = true
            } label: {
                Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
        .listRowBackground(Theme.secondaryBackground)
        }
    }
}

// MARK: - Edit Connection View

struct EditConnectionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var serverURL: String = ""
    @State private var cellularURL: String = ""
    @State private var useSeparateCellularLogin = false
    @State private var cellularUsername: String = ""
    @State private var cellularPassword: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Form {
                Section {
                    TextField("Server URL", text: $serverURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Username", text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("Password", text: $password)
                } header: {
                    Text("Connection Details")
                } footer: {
                    Text("Enter new credentials to reconnect. Leave password blank to keep existing.")
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    TextField("Cellular URL (optional)", text: $cellularURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Toggle(isOn: $useSeparateCellularLogin.animation(.easeInOut(duration: 0.2))) {
                        Label("Separate Cellular Login", systemImage: "person.badge.key")
                    }
                    .tint(Theme.accent)
                    if useSeparateCellularLogin {
                        TextField("Cellular Username", text: $cellularUsername)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        SecureField("Cellular Password", text: $cellularPassword)
                    }
                } header: {
                    Text("Cellular")
                } footer: {
                    Text("Used automatically when off Wi-Fi. Leave cellular login blank to keep using the main username and password.")
                }
                .listRowBackground(Theme.secondaryBackground)

                if let err = errorMessage {
                    Section {
                        Text(err).foregroundStyle(Theme.error).font(.footnote)
                    }
                    .listRowBackground(Theme.secondaryBackground)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle("Edit Connection")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    saveConnection()
                } label: {
                    if isSaving {
                        ProgressView().controlSize(.small).tint(Theme.accent)
                    } else {
                        Text("Save").foregroundStyle(Theme.accent).fontWeight(.semibold)
                    }
                }
                .disabled(isSaving || serverURL.trimmingCharacters(in: .whitespaces).isEmpty || username.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .preferredColorScheme(Theme.colorScheme)
        .onAppear { prefill() }
    }

    private func prefill() {
        guard let server = appState.currentServer else { return }
        serverURL = server.urlString
        cellularURL = server.cellularURLString ?? ""
        username = server.username
        cellularUsername = server.cellularUsername ?? ""
        useSeparateCellularLogin = server.cellularUsername?.nonBlank != nil || appState.store.cellularPassword(for: server) != nil
    }

    private func saveConnection() {
        guard let currentServer = appState.currentServer else { return }
        guard let url = SubsonicConfig.normalizedURL(from: serverURL) else {
            errorMessage = "Invalid server URL"
            VoltaNotificationCenter.shared.post(L(.notif_invalid_server_url), tone: .error)
            return
        }
        // normalise the optional cellular URL (blank > cleared); reject a non-blank but malformed one
        let trimmedCell = cellularURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var normalizedCell: String? = nil
        if !trimmedCell.isEmpty {
            guard let cellURL = SubsonicConfig.normalizedURL(from: trimmedCell) else {
                errorMessage = "Invalid cellular URL"
                VoltaNotificationCenter.shared.post(L(.notif_invalid_cellular_url), tone: .error)
                return
            }
            normalizedCell = cellURL.absoluteString
        }
        let existingPassword = appState.store.config(for: currentServer)?.password ?? ""
        let existingCellularPassword = appState.store.cellularPassword(for: currentServer)
        let pwd = password.isEmpty ? existingPassword : password
        let cellUsername = useSeparateCellularLogin ? cellularUsername.nonBlank : nil
        let cellPassword: String? = {
            guard useSeparateCellularLogin else { return nil }
            if let entered = cellularPassword.nonBlank { return entered }
            return existingCellularPassword
        }()
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            let config = SubsonicConfig(baseURL: url, username: username, password: pwd)
            let backend = currentServer.backend
            do {
                let testClient = try await MusicServiceFactory.make(config: config, kind: backend)
                try await testClient.ping()
                await MainActor.run {
                    appState.completeLogin(config: config, kind: backend)
                    appState.updateCellularConnection(
                        urlString: normalizedCell,
                        username: cellUsername,
                        password: cellPassword
                    )
                    VoltaNotificationCenter.shared.post(L(.notif_connection_saved), tone: .success)
                    dismiss()
                }
            } catch {
                errorMessage = "Could not connect: \(error.localizedDescription)"
                VoltaNotificationCenter.shared.post(L(.notif_could_not_connect), tone: .error)
            }
        }
    }
}

// MARK: - Server Info View

struct ServerInfoView: View {
    @Environment(AppState.self) private var appState
    @State private var speedTestResult: String? = nil
    @State private var isTesting = false
    @State private var speedGrade: String? = nil
    @State private var health: ServerHealthSnapshot?
    @State private var healthError: String?
    @State private var isCheckingHealth = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                Section {
                    if isCheckingHealth && health == nil {
                        HStack {
                            ProgressView().controlSize(.small).tint(Theme.accent)
                            Text("Checking…").foregroundStyle(Theme.secondaryText)
                        }
                    } else if let health {
                        LabeledContent("Status", value: health.status.capitalized)
                            .foregroundStyle(Theme.primaryText)
                        LabeledContent("Latency", value: "\(health.latencyMS) ms")
                            .foregroundStyle(Theme.primaryText)
                        LabeledContent("API Version", value: health.apiVersion ?? "Unknown")
                            .foregroundStyle(Theme.primaryText)
                        LabeledContent("Server Type", value: health.serverType ?? "Subsonic")
                            .foregroundStyle(Theme.primaryText)
                        LabeledContent("Connection", value: NetworkMonitor.shared.connection.rawValue)
                            .foregroundStyle(Theme.primaryText)
                        if let activeURL = appState.client?.config.baseURL.absoluteString {
                            LabeledContent("Active URL", value: activeURL)
                                .foregroundStyle(Theme.primaryText)
                        }
                        LabeledContent("Checked", value: health.checkedAt.formatted(date: .omitted, time: .shortened))
                            .foregroundStyle(Theme.secondaryText)
                    } else if let healthError {
                        Text(healthError)
                            .foregroundStyle(Theme.error)
                    }

                    Button {
                        Task { await loadHealth() }
                    } label: {
                        HStack {
                            Label("Refresh Health", systemImage: "heart.text.square")
                            Spacer()
                            if isCheckingHealth {
                                ProgressView().controlSize(.small).tint(Theme.accent)
                            }
                        }
                    }
                    .foregroundStyle(Theme.primaryText)
                    .disabled(isCheckingHealth)
                } header: {
                    Text("Server Health")
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    Button {
                        runSpeedTest()
                    } label: {
                        HStack {
                            Label("Test Streaming Speed", systemImage: "speedometer")
                            Spacer()
                            if isTesting {
                                ProgressView().controlSize(.small).tint(Theme.accent)
                            } else if let result = speedTestResult {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(result).font(.caption).foregroundStyle(Theme.secondaryText)
                                    if let grade = speedGrade {
                                        Text(grade).font(.caption.bold()).foregroundStyle(gradeColor)
                                    }
                                }
                            }
                        }
                    }
                    .foregroundStyle(Theme.primaryText)
                } header: {
                    Text("Speed Test")
                } footer: {
                    Text("Downloads several megabytes across multiple tracks for a more accurate streaming-speed estimate.")
                }
                .listRowBackground(Theme.secondaryBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle("Server Info")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
        }
        .preferredColorScheme(Theme.colorScheme)
        .task {
            await loadHealth()
        }
    }

    private var gradeColor: Color {
        switch speedGrade {
        case "Excellent": return .green
        case "Good": return Theme.accent
        case "Fair": return .yellow
        default: return Theme.error
        }
    }

    private func loadHealth() async {
        guard let client = appState.client else { return }
        isCheckingHealth = true
        healthError = nil
        defer { isCheckingHealth = false }
        do {
            health = try await client.serverHealth()
        } catch SubsonicError.serverUnreachable {
            health = nil
            healthError = "Server unreachable"
        } catch {
            health = nil
            healthError = error.localizedDescription
        }
    }

    private func runSpeedTest() {
        guard let client = appState.client else { return }
        isTesting = true
        speedTestResult = nil
        speedGrade = nil
        Task {
            defer { isTesting = false }
            guard let songs = try? await client.randomSongs(size: 4), !songs.isEmpty else {
                speedTestResult = "No data"
                return
            }

            // pull up to 4 MB from several tracks; time only the byte transfer
            // (the random-songs request above is excluded for accuracy) and
            // average across samples to smooth out per-request variance.
            let bytesPerSample = 4 * 1024 * 1024
            var totalBytes = 0
            var totalTime: TimeInterval = 0

            for song in songs.prefix(4) {
                guard let url = client.streamURL(id: song.id) else { continue }
                var req = URLRequest(url: url)
                req.timeoutInterval = 30
                req.cachePolicy = .reloadIgnoringLocalCacheData
                req.setValue("bytes=0-\(bytesPerSample - 1)", forHTTPHeaderField: "Range")

                let t0 = Date()
                if let (data, _) = try? await URLSession.shared.data(for: req), !data.isEmpty {
                    totalTime  += Date().timeIntervalSince(t0)
                    totalBytes += data.count
                }
            }

            guard totalBytes > 0, totalTime > 0 else {
                speedTestResult = "Failed"
                speedGrade = "Poor"
                return
            }

            let kbps = Double(totalBytes) / totalTime / 1024
            let mbps = kbps / 1024
            speedTestResult = mbps >= 1
                ? String(format: "%.1f MB/s", mbps)
                : String(format: "%.0f KB/s", kbps)
            speedGrade = kbps > 2048 ? "Excellent" : kbps > 512 ? "Good" : kbps > 128 ? "Fair" : "Poor"
        }
    }
}
