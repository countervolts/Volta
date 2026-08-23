import SwiftUI
import UIKit

struct EqualizerView: View {
    private struct AlertMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @AppStorage("equalizerEnabled") private var enabled = false
    @State private var gains: [Double] = EqualizerEngine.shared.gains
    @StateObject private var profiles = EqualizerProfileStore.shared
    @StateObject private var route = OutputRouteMonitor.shared
    @State private var profileName = ""
    @State private var showSaveProfile = false
    @State private var pendingPastedAutoEQ: EqualizerProfile?
    @State private var showPastedAutoEQNamePrompt = false
    @State private var showProfileManager = false
    @State private var alertMessage: AlertMessage?

    private let bandCount = EqualizerEngine.bandCount
    private let profileTransition = Animation.easeInOut(duration: 0.32)
    private let profilePanelMinHeight: CGFloat = 168

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Toggle(isOn: $enabled) {
                        Label("Enable Equalizer", systemImage: "slider.vertical.3")
                            .foregroundStyle(Theme.primaryText)
                    }
                    .tint(Theme.accent)
                    .onChangeCompat(of: enabled) { _, _ in
                        NotificationCenter.default.post(name: .equalizerToggled, object: nil)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    profilesSection

                    bandsRow
                        .opacity(enabled ? 1 : 0.4)
                        .allowsHitTesting(enabled)

                    Text("Changes apply instantly. Gains are limited to −12 dB through +12 dB.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 20)
                }
                .padding(.bottom, 120)
            }
        }
        .navigationTitle("Equalizer")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reset") { apply(EqualizerProfileStore.builtInProfiles[0]) }
                    .foregroundStyle(Theme.accent)
            }
        }
        .sheet(isPresented: $showProfileManager) {
            NavigationStack { profileManager }
                .alert("Save EQ Profile", isPresented: $showSaveProfile) {
                    TextField("Profile name", text: $profileName)
                    Button("Cancel", role: .cancel) { profileName = "" }
                    Button("Save") { saveCurrentProfile() }
                } message: {
                    Text("Save the current ten-band curve for quick reuse or assignment to an output device.")
                }
                .alert("Name AutoEQ Profile", isPresented: $showPastedAutoEQNamePrompt) {
                    TextField("Profile name", text: $profileName)
                    Button("Cancel", role: .cancel) {
                        pendingPastedAutoEQ = nil
                        profileName = ""
                    }
                    Button("Add") { savePastedAutoEQProfile() }
                } message: {
                    Text("Choose a name for this pasted ten-band AutoEQ profile.")
                }
                .alert(item: $alertMessage) { alert in
                    Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
                }
                .preferredColorScheme(Theme.colorScheme)
        }
        .preferredColorScheme(Theme.colorScheme)
        .background(SwipeBackEnabler())
        .onAppear {
            syncGainsFromEqualizer()
        }
        .onChangeCompat(of: profiles.selectedProfileID) { _, _ in
            // A device-profile assignment can be applied after an audio route
            // changes while this view is still visible. Keep the graph in sync
            // with the EQ engine instead of waiting for the view to reappear.
            syncGainsFromEqualizer()
        }
    }

    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Profiles", systemImage: "slider.horizontal.3")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Button {
                    showProfileManager = true
                } label: {
                    Text(L(.equalizer_manage_autoeq_profiles))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityLabel(L(.equalizer_manage_autoeq_profiles))
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(profiles.profiles) { profile in
                        profileButton(profile)
                    }
                }
                .padding(.horizontal, 20)
            }

            if let selected = profiles.selectedProfile {
                Text("Using \(selected.name) · \(selected.kind.detail)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 20)
            } else {
                Text("Custom curve")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 20)
            }
        }
    }

    private var profileManager: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    autoEQImportInfo
                    managedProfilesSection
                    deviceProfileSection
                }
                .padding(.vertical, 20)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(L(.equalizer_manage_autoeq_profiles))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { showProfileManager = false }
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    private var managedProfilesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Profiles", systemImage: "slider.horizontal.3")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Button {
                    profileName = ""
                    showSaveProfile = true
                } label: {
                    Label("Save Current EQ", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Theme.accent)
            }

            ForEach(profiles.profiles) { profile in
                managedProfileRow(profile)
            }
        }
        .padding(16)
        .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func managedProfileRow(_ profile: EqualizerProfile) -> some View {
        Menu {
            Button {
                apply(profile)
            } label: {
                Label(L(.equalizer_profile_apply), systemImage: "checkmark")
            }
            Button {
                assignProfileToCurrentDevice(profile)
            } label: {
                Label(L(.equalizer_profile_assign_current_device), systemImage: "headphones")
            }

            if profile.kind != .builtIn {
                Button(role: .destructive) {
                    profiles.delete(profile)
                } label: {
                    Label(L(.equalizer_profile_delete), systemImage: Symbols.trash)
                }
            }
        } label: {
            managedProfileLabel(profile)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
    }

    private func managedProfileLabel(_ profile: EqualizerProfile) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .font(.subheadline.weight(.semibold))
                Text(profile.kind.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(Theme.secondaryText)
        }
        .foregroundStyle(Theme.primaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var autoEQImportInfo: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(L(.equalizer_autoeq_imports_title), systemImage: "doc.on.clipboard")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)

            Text(L(.equalizer_autoeq_manual_paste_hint))
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

            Button {
                pasteManualAutoEQ()
            } label: {
                Label(L(.equalizer_autoeq_paste_ten_band), systemImage: "doc.on.clipboard")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
        }
        .padding(16)
        .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
    }

    private func profileButton(_ profile: EqualizerProfile) -> some View {
        let selected = profiles.selectedProfileID == profile.id
        return Button { apply(profile) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(profile.kind.detail)
                    .font(.caption2)
                    .foregroundStyle(selected ? Theme.primaryText.opacity(0.7) : Theme.secondaryText)
            }
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(selected ? Theme.accent.opacity(0.3) : Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : .white.opacity(0.08), lineWidth: selected ? 1.5 : 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Apply \(profile.name) equalizer profile")
    }

    private var deviceProfileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Device Profiles", systemImage: "headphones")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)

            Toggle("Auto-apply for connected output", isOn: $profiles.automaticallyApplyDeviceProfile)
                .tint(Theme.accent)

            Menu {
                Button("No profile") { profiles.assign(nil) }
                Divider()
                ForEach(profiles.profiles) { profile in
                    Button(profile.name) {
                        profiles.assign(profile)
                        apply(profile)
                    }
                }
            } label: {
                LabeledContent {
                    Text(profiles.assignedProfileForCurrentRoute()?.name ?? "No profile")
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                } label: {
                    Text("\(route.routeName)")
                }
            }
            .tint(Theme.primaryText)

            if !profiles.deviceProfileAssignments.isEmpty {
                Divider()

                Text(L(.equalizer_device_saved_assignments))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)

                ForEach(profiles.deviceProfileAssignments) { assignment in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(assignment.deviceName)
                                .font(.subheadline.weight(.semibold))
                            Text(assignment.profile.name)
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            profiles.removeDeviceProfileAssignment(for: assignment.routeKey)
                        } label: {
                            Image(systemName: Symbols.trash)
                        }
                        .accessibilityLabel(L(.equalizer_device_remove, assignment.deviceName))
                    }
                    .padding(.vertical, 2)
                }
            }

            Text("Choose a profile for this output once; it will be applied whenever the same device reconnects.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: profilePanelMinHeight, alignment: .topLeading)
        .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
    }

    private var bandsRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ten-band EQ")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
                .padding(.horizontal, 20)

            GeometryReader { proxy in
                let spacing: CGFloat = 4
                let bandWidth = (proxy.size.width - (spacing * CGFloat(bandCount - 1))) / CGFloat(bandCount)

                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(0..<bandCount, id: \.self) { index in
                        VStack(spacing: 6) {
                            Text(gainText(gains[index]))
                                .font(.caption2.monospacedDigit())
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                                .foregroundStyle(Theme.secondaryText)
                            Slider(value: bandBinding(index), in: EqualizerEngine.range, step: 0.1)
                                .frame(width: 150)
                                .rotationEffect(.degrees(-90))
                                .frame(width: bandWidth, height: 150)
                                .tint(Theme.accent)
                            Text(freqText(EqualizerEngine.frequencies[index]))
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .foregroundStyle(Theme.primaryText)
                        }
                        .frame(width: bandWidth)
                    }
                }
            }
            .frame(height: 190)
            .padding(.horizontal, 20)
        }
    }

    private func bandBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { gains[index] },
            set: {
                gains[index] = $0
                EqualizerEngine.shared.setGain($0, band: index)
                profiles.noteManualAdjustment()
            }
        )
    }

    private func apply(_ profile: EqualizerProfile) {
        profiles.apply(profile)
        enabled = true
        syncGainsFromEqualizer()
    }

    private func syncGainsFromEqualizer() {
        withAnimation(profileTransition) {
            gains = EqualizerEngine.shared.gains
        }
    }

    private func saveCurrentProfile() {
        guard let profile = profiles.saveProfile(
            name: profileName,
            gains: gains,
            preampDB: EqualizerEngine.shared.preampDB
        ) else { return }
        profiles.apply(profile, enablingEqualizer: enabled)
        profileName = ""
    }

    private func assignProfileToCurrentDevice(_ profile: EqualizerProfile) {
        // routeAssignments stores a single profile ID per route key, so this
        // deliberately replaces any profile previously assigned to this device.
        profiles.assign(profile)
        profiles.automaticallyApplyDeviceProfile = true
        apply(profile)
    }

    private func pasteManualAutoEQ() {
        guard let clipboardText = UIPasteboard.general.string,
              !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alertMessage = AlertMessage(
                title: "Couldn’t Paste AutoEQ",
                message: "Copy AutoEQ's ten-band table and Preamp line, then try again."
            )
            return
        }

        do {
            pendingPastedAutoEQ = try AutoEQTenBandPasteImporter.profile(from: clipboardText)
            profileName = pendingPastedAutoEQ?.name ?? "Pasted AutoEQ"
            showPastedAutoEQNamePrompt = true
        } catch {
            alertMessage = AlertMessage(title: "Couldn’t Paste AutoEQ", message: error.localizedDescription)
        }
    }

    private func savePastedAutoEQProfile() {
        guard let pendingPastedAutoEQ else { return }
        let name = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let saved = profiles.saveProfile(
            name: name.isEmpty ? pendingPastedAutoEQ.name : name,
            gains: pendingPastedAutoEQ.gains,
            preampDB: pendingPastedAutoEQ.preampDB,
            kind: .autoEQ
        ) else { return }

        apply(saved)
        let preamp = String(format: "%.1f", saved.preampDB)
        alertMessage = AlertMessage(
            title: L(.equalizer_autoeq_manual_paste_success_title),
            message: L(.equalizer_autoeq_manual_paste_success_message, saved.name, preamp)
        )
        self.pendingPastedAutoEQ = nil
        profileName = ""
    }

    private func gainText(_ value: Double) -> String {
        String(format: "%+.1f dB", value)
    }

    private func freqText(_ frequency: Double) -> String {
        frequency >= 1000 ? "\(Int(frequency / 1000))k" : "\(Int(frequency))"
    }
}
