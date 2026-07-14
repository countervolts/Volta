import SwiftUI
import SafariServices
import UIKit

struct LoginView: View {
    var onLoginComplete: () -> Void = {}
    var isEmbeddedInSheet = false

    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = LoginViewModel()
    @StateObject private var discovery = LocalServerDiscovery()
    @StateObject private var localization = LocalizationManager.shared
    @State private var appeared = false
    @State private var showHTTPWarning = false
    @State private var pendingHTTPWarningAction: HTTPWarningAction = .credentials
    @State private var isPasswordVisible = false
    @State private var plexAuthPage: SafariPage?
    @State private var isShowingAutoDiscovery = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case server, username, password }
    private enum HTTPWarningAction { case credentials, plexHosted }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            backdrop

            Group {
                if isShowingAutoDiscovery {
                    autoDiscoveryView
                } else if let kind = vm.selectedBackend, let option = Self.option(for: kind) {
                    credentialsForm(
                        option: option,
                        server: $vm.serverAddress,
                        username: $vm.username,
                        password: $vm.password
                    )
                } else {
                    servicePicker
                }
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        // Keep these outside the transitioning ScrollView so taps land reliably.
        .overlay(alignment: .topLeading) {
            if vm.selectedBackend != nil || isShowingAutoDiscovery { backButton }
        }
        .overlay(alignment: .topTrailing) {
            if vm.selectedBackend == nil && !isShowingAutoDiscovery && !isEmbeddedInSheet { languageMenu }
        }
        .preferredColorScheme(Theme.colorScheme)
        .opacity(isEmbeddedInSheet || appeared ? 1 : 0)
        .offset(y: isEmbeddedInSheet || appeared ? 0 : 24)
        .onAppear {
            if isEmbeddedInSheet {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                    appeared = true
                }
            }
        }
        .onChangeCompat(of: vm.serverAddress) { vm.serverAddressChanged() }
        .onChangeCompat(of: vm.selectedBackend) { _, kind in
            guard kind != nil else { return }
            // Focus the server field once the credentials form has transitioned in.
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                if vm.selectedBackend != nil { focusedField = .server }
            }
        }
        .alert(L(.http_warning_title), isPresented: $showHTTPWarning) {
            Button(L(.action_edit_server), role: .cancel) {
                vm.cancelInsecureHTTPContinuation()
            }
            Button(L(.action_continue), role: .destructive) {
                let action = pendingHTTPWarningAction
                Task { await continueAfterHTTPWarning(action) }
            }
        } message: {
            Text(L(.http_warning_message))
        }
        .sheet(item: $plexAuthPage) { page in
            SafariView(url: page.url)
                .ignoresSafeArea()
        }
        .onDisappear { discovery.stop() }
    }

    // MARK: - Language picker (service-selection step)

    private var languageMenu: some View {
        Menu {
            Picker(
                selection: Binding(
                    get: { localization.language },
                    set: { localization.language = $0 }
                )
            ) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.endonym).tag(language)
                }
            } label: { EmptyView() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 14, weight: .semibold))
                Text(localization.language.endonym)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, 14)
            .frame(height: 42)
            .glassCard(cornerRadius: 21)
            .contentShape(Capsule())
        }
        .accessibilityLabel(L(.settings_language))
        .padding(.trailing, 20)
        .padding(.top, 8)
    }

    // MARK: - Back button (credentials step)

    private var backButton: some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                isPasswordVisible = false
                if isShowingAutoDiscovery {
                    discovery.stop()
                    isShowingAutoDiscovery = false
                } else {
                    vm.deselect()
                }
            }
        } label: {
            Image(systemName: Symbols.back)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 42, height: 42)
                .glassCircle()
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 20)
        .padding(.top, 8)
    }

    // MARK: - Step 1: service picker

    private var servicePicker: some View {
        ScrollView {
            VStack(spacing: 30) {
                brandHeader

                VStack(spacing: 12) {
                    ForEach(Self.backends) { option in
                        serviceCard(option)
                    }

                    autoDiscoveryCard
                }

                Text(L(.login_add_servers_later))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 24)
            .padding(.top, isEmbeddedInSheet ? 28 : 72)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .leading)),
            removal: .opacity.combined(with: .move(edge: .leading))
        ))
    }

    private var autoDiscoveryCard: some View {
        Button {
            focusedField = nil
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                isShowingAutoDiscovery = true
            }
            discovery.start()
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Theme.accent.gradient)
                        .frame(width: 50, height: 50)
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: Theme.accent.opacity(0.35), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Auto")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text("Find compatible music servers on this network")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)
                Image(systemName: Symbols.chevron)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .glassCard(cornerRadius: 18)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.24), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Automatic server discovery

    private var autoDiscoveryView: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Theme.accent.opacity(0.16))
                            .frame(width: 82, height: 82)
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .symbolPulseRepeatingCompat()
                    }
                    Text("Servers on Your Network")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.primaryText)
                    Text(discovery.isScanning ? "Scanning for compatible services…" : "Select a server to continue")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }

                if discovery.servers.isEmpty {
                    VStack(spacing: 12) {
                        if discovery.isScanning {
                            ProgressView()
                                .controlSize(.large)
                                .tint(Theme.accent)
                            Text("This usually takes a few seconds.")
                        } else {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 30))
                                .foregroundStyle(Theme.secondaryText)
                            Text("No compatible servers found")
                                .font(.headline)
                                .foregroundStyle(Theme.primaryText)
                            Text("Make sure this iPhone is on the same Wi-Fi network as your server, then scan again.")
                                .multilineTextAlignment(.center)
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity)
                    .glassCard(cornerRadius: 18)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(discovery.servers) { server in
                            discoveredServerCard(server)
                        }
                    }
                }

                Button {
                    discovery.start()
                } label: {
                    Label(discovery.isScanning ? "Scanning…" : "Scan Again", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .glassButtonStyle(prominent: false)
                .disabled(discovery.isScanning)
                .opacity(discovery.isScanning ? 0.55 : 1)
            }
            .padding(.horizontal, 24)
            .padding(.top, isEmbeddedInSheet ? 56 : 64)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .trailing))
        ))
    }

    private func discoveredServerCard(_ server: DiscoveredMusicServer) -> some View {
        Button {
            discovery.stop()
            vm.select(server.backend)
            vm.serverAddress = server.address
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                isShowingAutoDiscovery = false
            }
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                focusedField = .username
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill((Self.option(for: server.backend)?.tint ?? Theme.accent).opacity(0.18))
                        .frame(width: 46, height: 46)
                    Image(systemName: Self.option(for: server.backend)?.icon ?? Symbols.server)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Self.option(for: server.backend)?.tint ?? Theme.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(server.primaryDisplayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Text(server.secondaryDisplayName)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    Text(server.address)
                        .font(.caption2.monospaced())
                        .foregroundStyle(Theme.secondaryText.opacity(0.8))
                        .lineLimit(1)
                }

                Spacer(minLength: 6)
                Image(systemName: Symbols.chevron)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText.opacity(0.5))
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .glassCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(server.primaryDisplayName), \(server.secondaryDisplayName), \(server.address)")
    }

    private var brandHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.16))
                    .frame(width: 96, height: 96)
                Image(systemName: "waveform")
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .symbolPulseRepeatingCompat()
            }
            Text("Volta")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.primaryText)
            Text(L(.login_tagline))
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    private func serviceCard(_ option: BackendOption) -> some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                vm.select(option.kind)
            }
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(option.tint.gradient)
                        .frame(width: 50, height: 50)
                    Image(systemName: option.icon)
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: option.tint.opacity(0.35), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(option.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text(option.subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: Symbols.chevron)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .glassCard(cornerRadius: 18)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 2: credentials

    private func credentialsForm(
        option: BackendOption,
        server: Binding<String>,
        username: Binding<String>,
        password: Binding<String>
    ) -> some View {
        ScrollView {
            VStack(spacing: 22) {
                selectedServiceBadge(option)

                VStack(spacing: 14) {
                    field(
                        text: server,
                        placeholder: option.serverPlaceholder,
                        icon: Symbols.server,
                        isError: vm.serverError != nil,
                        shake: vm.serverShake,
                        keyboard: .URL,
                        contentType: .URL,
                        errorText: vm.serverError,
                        fieldID: .server,
                        submitLabel: .next,
                        onSubmit: { focusedField = .username },
                        reachability: vm.reachability
                    )

                    if option.kind == .plex {
                        plexHostedSignInButton(tint: option.tint)
                    }

                    field(
                        text: username,
                        placeholder: option.kind == .plex ? L(.login_plex_email) : L(.login_username),
                        icon: Symbols.person,
                        isError: vm.credentialsError != nil,
                        shake: vm.credentialsShake,
                        contentType: option.kind == .plex ? .emailAddress : .username,
                        fieldID: .username,
                        submitLabel: .next,
                        onSubmit: { focusedField = .password }
                    )

                    field(
                        text: password,
                        placeholder: option.kind == .plex ? L(.login_plex_password) : L(.login_password),
                        icon: Symbols.lock,
                        isError: vm.credentialsError != nil,
                        shake: vm.credentialsShake,
                        isSecure: true,
                        isPasswordVisible: $isPasswordVisible,
                        contentType: .password,
                        errorText: vm.credentialsError,
                        fieldID: .password,
                        submitLabel: .go,
                        onSubmit: { attemptConnect() }
                    )
                }

                if let hint = option.hint {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                        Text(hint)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }

                connectButton(tint: option.tint)

                if DemoServers.entry(for: option.kind) != nil {
                    demoButton
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, isEmbeddedInSheet ? 56 : 64)   // clears the back button overlaid at the top
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .trailing))
        ))
    }

    private func plexHostedSignInButton(tint: Color) -> some View {
        Button {
            Task {
                let result = await vm.signInWithPlex(using: appState) { url in
                    plexAuthPage = SafariPage(url: url)
                }
                plexAuthPage = nil
                handleConnectionResult(result, warningAction: .plexHosted)
            }
        } label: {
            HStack(spacing: 8) {
                if vm.isPlexHostedSigningIn {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                }
                Text(vm.isPlexHostedSigningIn ? L(.login_waiting_for_plex) : L(.login_sign_in_with_plex))
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .glassButtonStyle(prominent: true)
        .tint(tint)
        .disabled(!vm.canStartPlexHostedSignIn)
        .opacity(vm.canStartPlexHostedSignIn ? 1 : 0.5)
        .animation(.easeInOut(duration: 0.2), value: vm.canStartPlexHostedSignIn)
    }

    private func selectedServiceBadge(_ option: BackendOption) -> some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(option.tint.gradient)
                    .frame(width: 78, height: 78)
                Image(systemName: option.icon)
                    .font(.system(size: 35, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: option.tint.opacity(0.45), radius: 18, y: 8)

            VStack(spacing: 4) {
                Text(L(.login_sign_in_to, option.shortTitle))
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                Text(option.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // Connect, but intercept an explicitly-typed http:// URL to confirm first.
    private func attemptConnect() {
        guard vm.canSubmit else { return }
        focusedField = nil
        if vm.usesInsecureHTTP {
            showHTTPWarning(for: .credentials)
        } else {
            Task {
                let result = await vm.connect(using: appState)
                handleConnectionResult(result, warningAction: .credentials)
            }
        }
    }

    private func showHTTPWarning(for action: HTTPWarningAction) {
        pendingHTTPWarningAction = action
        showHTTPWarning = true
    }

    private func continueAfterHTTPWarning(_ action: HTTPWarningAction) async {
        let result: LoginViewModel.ConnectionResult
        switch action {
        case .credentials:
            result = await vm.connect(using: appState, allowInsecureHTTP: true)
        case .plexHosted:
            result = await vm.signInWithPlex(using: appState, allowInsecureHTTP: true) { url in
                plexAuthPage = SafariPage(url: url)
            }
            plexAuthPage = nil
        }
        handleConnectionResult(result, warningAction: action)
    }

    private func handleConnectionResult(_ result: LoginViewModel.ConnectionResult, warningAction: HTTPWarningAction) {
        if result == .needsInsecureHTTPConfirmation {
            showHTTPWarning(for: warningAction)
        } else if vm.didCompleteLogin {
            onLoginComplete()
        }
    }

    private var demoButton: some View {
        Button {
            focusedField = nil
            // Connect directly: demo URLs are https and some (Jellyfin) use an
            // empty password, which the normal canSubmit gate would reject.
            guard vm.fillDemoServer() else { return }
            Task {
                let result = await vm.connect(using: appState)
                handleConnectionResult(result, warningAction: .credentials)
            }
        } label: {
            Text(L(.login_try_demo))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
        }
        .buttonStyle(.plain)
        .disabled(vm.isConnecting || vm.isPlexHostedSigningIn)
        .opacity(vm.isConnecting ? 0.4 : 1)
    }

    private func connectButton(tint: Color) -> some View {
        Button {
            attemptConnect()
        } label: {
            HStack(spacing: 8) {
                if vm.isConnecting {
                    ProgressView().tint(.white)
                }
                Text(vm.isConnecting ? L(.login_connecting) : L(.login_connect))
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .glassButtonStyle(prominent: true)
        .tint(tint)
        .disabled(!vm.canSubmit)
        .opacity(vm.canSubmit ? 1 : 0.5)
        .animation(.easeInOut(duration: 0.2), value: vm.canSubmit)
        .padding(.top, 4)
    }

    // MARK: - Backdrop

    // soft color wash behind the form, tinted to the selected service's brand color.
    @ViewBuilder
    private var backdrop: some View {
        let tint = vm.selectedBackend.flatMap { Self.option(for: $0)?.tint } ?? Theme.accent
        let gradient = RadialGradient(
            colors: [tint.opacity(0.30), .clear],
            center: .top,
            startRadius: 0,
            endRadius: 460
        )
        .ignoresSafeArea()
        .scaleEffect(isEmbeddedInSheet ? 1 : (appeared ? 1 : 1.3))

        if isEmbeddedInSheet {
            gradient
        } else {
            gradient
                .animation(.easeOut(duration: 0.5), value: vm.selectedBackend)
                .animation(.easeOut(duration: 1.2), value: appeared)
        }
    }

    // MARK: - Field

    @ViewBuilder
    private func field(
        text: Binding<String>,
        placeholder: String,
        icon: String,
        isError: Bool,
        shake: Int,
        isSecure: Bool = false,
        isPasswordVisible: Binding<Bool>? = nil,
        keyboard: UIKeyboardType = .default,
        contentType: UITextContentType? = nil,
        errorText: String? = nil,
        fieldID: Field,
        submitLabel: SubmitLabel = .next,
        onSubmit: @escaping () -> Void = {},
        reachability: LoginViewModel.ServerReachability? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 22)

                Group {
                    if isSecure {
                        if isPasswordVisible?.wrappedValue == true {
                            TextField(placeholder, text: text)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField(placeholder, text: text)
                        }
                    } else {
                        TextField(placeholder, text: text)
                            .keyboardType(keyboard)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                .foregroundStyle(Theme.primaryText)
                .textContentType(contentType)
                .focused($focusedField, equals: fieldID)
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)

                if let reachability {
                    reachabilityIndicator(reachability)
                        .animation(.easeInOut(duration: 0.2), value: reachability)
                }

                if isSecure, let isPasswordVisible {
                    Button {
                        isPasswordVisible.wrappedValue.toggle()
                    } label: {
                        Image(systemName: isPasswordVisible.wrappedValue ? "eye.slash" : "eye")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .glassCard(cornerRadius: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isError ? Theme.error : Color.white.opacity(0.08),
                                  lineWidth: isError ? 1.5 : 0.5)
            )
            .shake(with: shake)

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(Theme.error)
                    .padding(.leading, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isError)
    }

    // Inline server-reachability hint shown in the trailing edge of the server field.
    @ViewBuilder
    private func reachabilityIndicator(_ state: LoginViewModel.ServerReachability) -> some View {
        switch state {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView().controlSize(.small)
        case .reachable(let insecure):
            Image(systemName: insecure ? "lock.open.fill" : "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(insecure ? Color.orange : Color.green)
        case .unreachable:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 16))
                .foregroundStyle(Theme.secondaryText.opacity(0.7))
        }
    }

    // MARK: - Backend catalog

    private struct BackendOption: Identifiable {
        let kind: MusicBackendKind
        let title: String
        let shortTitle: String
        let subtitle: String
        let icon: String
        let tint: Color
        let serverPlaceholder: String
        let usernamePlaceholder: String
        let passwordPlaceholder: String
        let hint: String?
        var id: MusicBackendKind { kind }
    }

    private static let backends: [BackendOption] = [
        BackendOption(
            kind: .subsonic,
            title: "Subsonic / Navidrome",
            shortTitle: "Subsonic",
            subtitle: "Navidrome, Airsonic, Gonic & any Subsonic-compatible server",
            icon: "waveform",
            tint: Color(red: 0.18, green: 0.66, blue: 0.71),
            serverPlaceholder: "https://music.example.com",
            usernamePlaceholder: "Username",
            passwordPlaceholder: "Password",
            hint: nil
        ),
        BackendOption(
            kind: .jellyfin,
            title: "Jellyfin",
            shortTitle: "Jellyfin",
            subtitle: "The free software media system",
            icon: "play.circle.fill",
            tint: Color(red: 0.49, green: 0.36, blue: 0.86),
            serverPlaceholder: "https://jellyfin.example.com",
            usernamePlaceholder: "Username",
            passwordPlaceholder: "Password",
            hint: nil
        ),
        BackendOption(
            kind: .emby,
            title: "Emby",
            shortTitle: "Emby",
            subtitle: "Your personal Emby media server",
            icon: "play.rectangle.fill",
            tint: Color(red: 0.30, green: 0.73, blue: 0.31),
            serverPlaceholder: "https://emby.example.com",
            usernamePlaceholder: "Username",
            passwordPlaceholder: "Password",
            hint: nil
        ),
        BackendOption(
            kind: .plex,
            title: "Plex",
            shortTitle: "Plex",
            subtitle: "Stream from your Plex Media Server",
            icon: "play.tv.fill",
            tint: Color(red: 0.90, green: 0.62, blue: 0.04),
            serverPlaceholder: "http://192.168.1.10:32400",
            usernamePlaceholder: "Plex account email",
            passwordPlaceholder: "Password or Plex token",
            hint: "Use hosted Plex sign-in for Google, Apple, or 2FA. You can also enter your Plex email and password. For a raw X-Plex-Token, use Plex as the username."
        ),
    ]

    private static func option(for kind: MusicBackendKind) -> BackendOption? {
        backends.first { $0.kind == kind }
    }
}

private struct SafariPage: Identifiable {
    let id = UUID()
    let url: URL
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
