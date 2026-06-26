import SwiftUI

struct AutoMixSettingsView: View {
    @Environment(AppState.self) private var appState

    @AppStorage("gaplessPlayback") private var gaplessPlayback = "on"
    @AppStorage("automixStyle") private var automixStyle = "balanced"
    @AppStorage("automixMaxBlendSeconds") private var automixMaxBlendSeconds = 10.0
    @AppStorage("automixSilenceTrim") private var automixSilenceTrim = true
    @AppStorage("automixTempoMatch") private var automixTempoMatch = true
    @AppStorage("automixBeatAlign") private var automixBeatAlign = true
    @AppStorage("automixHarmonic") private var automixHarmonic = true
    @AppStorage("automixBassSwap") private var automixBassSwap = true
    @AppStorage("automixSweetSpot") private var automixSweetSpot = true
    @AppStorage("automixLoudnessMatch") private var automixLoudnessMatch = true

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
                            Text(mode.settingsLabel)
                                .tag(mode)
                                .disabled(mode == .automix && gaplessPlayback == "off")
                        }
                    } label: {
                        Label(L(.settings_track_transition), systemImage: audio.transitionMode.icon)
                    }
                    .tint(Theme.accent)
                } header: {
                    Text("Mode")
                } footer: {
                    Text("AutoMix requires Gapless Playback set to Weak or On.")
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    Picker(selection: $automixStyle) {
                        Text("Tight").tag("tight")
                        Text("Balanced").tag("balanced")
                        Text("Wide").tag("wide")
                    } label: {
                        Label("Style", systemImage: "slider.horizontal.3")
                    }
                    .tint(Theme.accent)
                    .onChange(of: automixStyle) { _, _ in audio.setTransitionMode(audio.transitionMode) }

                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Max Blend", value: "\(Int(automixMaxBlendSeconds))s")
                            .foregroundStyle(Theme.primaryText)
                        Slider(value: $automixMaxBlendSeconds, in: 4...18, step: 1)
                            .tint(Theme.accent)
                            .onChange(of: automixMaxBlendSeconds) { _, _ in
                                audio.setTransitionMode(audio.transitionMode)
                            }
                    }

                    Toggle(isOn: $automixSilenceTrim) {
                        Label("Silence Trim", systemImage: "scissors")
                    }
                    .tint(Theme.accent)
                    .onChange(of: automixSilenceTrim) { _, _ in audio.setTransitionMode(audio.transitionMode) }

                    Toggle(isOn: $automixTempoMatch) {
                        Label("BPM Match", systemImage: "metronome")
                    }
                    .tint(Theme.accent)
                    .onChange(of: automixTempoMatch) { _, _ in audio.setTransitionMode(audio.transitionMode) }

                    Toggle(isOn: $automixBeatAlign) {
                        Label("Beat Lock", systemImage: "waveform.path.ecg")
                    }
                    .tint(Theme.accent)
                    .disabled(!automixTempoMatch)
                    .onChange(of: automixBeatAlign) { _, _ in audio.setTransitionMode(audio.transitionMode) }

                    Toggle(isOn: $automixHarmonic) {
                        Label("Harmonic Mixing", systemImage: "pianokeys")
                    }
                    .tint(Theme.accent)
                    .onChange(of: automixHarmonic) { _, _ in audio.setTransitionMode(audio.transitionMode) }

                    Toggle(isOn: $automixBassSwap) {
                        Label("Bass Swap", systemImage: "dial.low")
                    }
                    .tint(Theme.accent)
                    .onChange(of: automixBassSwap) { _, _ in audio.setTransitionMode(audio.transitionMode) }

                    Toggle(isOn: $automixSweetSpot) {
                        Label("Sweet Spot", systemImage: "scope")
                    }
                    .tint(Theme.accent)
                    .onChange(of: automixSweetSpot) { _, _ in audio.setTransitionMode(audio.transitionMode) }

                    Toggle(isOn: $automixLoudnessMatch) {
                        Label("Loudness Match", systemImage: "speaker.wave.2")
                    }
                    .tint(Theme.accent)
                    .onChange(of: automixLoudnessMatch) { _, _ in audio.setTransitionMode(audio.transitionMode) }
                } header: {
                    Text("Mixing")
                } footer: {
                    Text("BPM Match bends the outgoing track to the incoming tempo (±6%, pitch preserved). Beat Lock then fires the blend on the downbeat so the two tracks' beats land together, like a DJ. Harmonic Mixing reads each track's musical key (Camelot) and gives compatible pairs a longer blend, clashing pairs a shorter, cleaner handover. Bass Swap rolls the incoming track's low end off and brings it in as it takes over, so the two basslines don't muddy each other (applies when the equalizer is off). Sweet Spot mixes out during a long fading outro and drops in past a sparse intro (capped at 16 seconds) instead of always blending at the track edges; sequential album tracks are handed off near-gaplessly and never DJ-blended. Loudness Match levels a hotter incoming track so the blend doesn't jump in volume.")
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    NavigationLink(value: SettingsRoute.autoMixPreview) {
                        Label("Preview AutoMix", systemImage: "waveform.badge.magnifyingglass")
                    }
                } footer: {
                    Text("Hear and see how two of your tracks blend with the current settings.")
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
