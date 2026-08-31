import SwiftUI

struct AutoMixSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("automixStyle") private var automixStyle = AutoMixStyle.balanced.rawValue
    @AppStorage("automixMinimumEndLeadSeconds") private var minimumEndLead = 8.0

    private var audio: AudioPlayer { appState.audioPlayer }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                Section {
                    Picker(selection: Binding(
                        get: { audio.transitionMode },
                        set: { audio.setTransitionMode($0) }
                    )) {
                        ForEach(PlaybackTransitionMode.allCases) { mode in
                            Text(mode.settingsLabel).tag(mode)
                        }
                    } label: {
                        Label(L(.settings_track_transition), systemImage: audio.transitionMode.icon)
                    }
                    .tint(Theme.accent)
                } header: {
                    Text("Transition")
                } footer: {
                    Text("Crossfade uses a fixed overlap. AutoMix analyzes each pair and chooses gapless handoff, silence trim, adaptive fade, beat or phrase mix, or a tight cut.")
                }
                .listRowBackground(Theme.secondaryBackground)

                if audio.transitionMode == .automix {
                    Section {
                        Picker("AutoMix Style", selection: $automixStyle) {
                            Text("Tight").tag(AutoMixStyle.tight.rawValue)
                            Text("Balanced").tag(AutoMixStyle.balanced.rawValue)
                            Text("Wide").tag(AutoMixStyle.wide.rawValue)
                        }
                        .tint(Theme.accent)
                        .onChangeCompat(of: automixStyle) { _, _ in
                            audio.setTransitionMode(.automix)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent(
                                "Minimum End Lead",
                                value: "\(Int(minimumEndLead.rounded()))s"
                            )
                            Slider(value: $minimumEndLead, in: 4...20, step: 1)
                                .tint(Theme.accent)
                        }
                        .onChangeCompat(of: minimumEndLead) { _, _ in
                            audio.setTransitionMode(.automix)
                        }
                    } footer: {
                        Text("Minimum End Lead controls how much audible outro should remain when AutoMix tries to start. Style never overrides confidence safety.")
                    }
                    .listRowBackground(Theme.secondaryBackground)
                }

                Section {
                    SettingsDetailNavigationLink(.autoMixPreview) {
                        Label("Preview & Diagnostics", systemImage: "waveform.badge.magnifyingglass")
                    }
                } footer: {
                    Text("Analyze a real pair with the same cache, normalized models, planner, gain envelopes, and media-time scheduling used during playback.")
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    Label("Analysis stays on this device", systemImage: "lock.shield")
                        .foregroundStyle(Theme.primaryText)
                } footer: {
                    Text("Tempo comes from decoded audio. BPM tags are optional hints. Results are versioned and cached locally; no audio or analysis is uploaded.")
                }
                .listRowBackground(Theme.secondaryBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle("AutoMix")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
        }
        .preferredColorScheme(Theme.colorScheme)
    }
}
