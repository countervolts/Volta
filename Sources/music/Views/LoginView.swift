import SwiftUI
import UIKit

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = LoginViewModel()
    @State private var appeared = false

    var body: some View {
        @Bindable var vm = vm

        return ZStack {
            Theme.background.ignoresSafeArea()
            backdrop

            ScrollView {
                VStack(spacing: 26) {
                    header

                    VStack(spacing: 16) {
                        field(
                            text: $vm.serverAddress,
                            placeholder: "Server address",
                            icon: Symbols.server,
                            isError: vm.serverError != nil,
                            shake: vm.serverShake,
                            keyboard: .URL,
                            errorText: vm.serverError
                        )

                        field(
                            text: $vm.username,
                            placeholder: "Username",
                            icon: Symbols.person,
                            isError: vm.credentialsError != nil,
                            shake: vm.credentialsShake
                        )

                        field(
                            text: $vm.password,
                            placeholder: "Password",
                            icon: Symbols.lock,
                            isError: vm.credentialsError != nil,
                            shake: vm.credentialsShake,
                            isSecure: true,
                            errorText: vm.credentialsError
                        )
                    }

                    connectButton
                }
                .padding(.horizontal, 28)
                .padding(.top, 80)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 24)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                appeared = true
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.pulse, options: .repeating)
            Text("Volta")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.primaryText)
            Text("Connect to your Navidrome server")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var connectButton: some View {
        Button {
            Task { await vm.connect(using: appState) }
        } label: {
            HStack(spacing: 8) {
                if vm.isConnecting {
                    ProgressView().tint(.white)
                }
                Text(vm.isConnecting ? "Connecting" : "Connect")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .glassButtonStyle(prominent: true)
        .tint(Theme.accent)
        .disabled(!vm.canSubmit)
        .opacity(vm.canSubmit ? 1 : 0.5)
        .animation(.easeInOut(duration: 0.2), value: vm.canSubmit)
        .padding(.top, 4)
    }

    // soft animated color wash behind the form.
    private var backdrop: some View {
        RadialGradient(
            colors: [Theme.accent.opacity(0.28), .clear],
            center: .top,
            startRadius: 0,
            endRadius: 420
        )
        .ignoresSafeArea()
        .scaleEffect(appeared ? 1 : 1.3)
        .animation(.easeOut(duration: 1.2), value: appeared)
    }

    @ViewBuilder
    private func field(
        text: Binding<String>,
        placeholder: String,
        icon: String,
        isError: Bool,
        shake: Int,
        isSecure: Bool = false,
        keyboard: UIKeyboardType = .default,
        errorText: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 22)

                Group {
                    if isSecure {
                        SecureField(placeholder, text: text)
                    } else {
                        TextField(placeholder, text: text)
                            .keyboardType(keyboard)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                .foregroundStyle(Theme.primaryText)
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
}
