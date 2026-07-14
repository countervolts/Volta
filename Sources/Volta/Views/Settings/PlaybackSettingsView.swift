import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension SettingsView {
    // MARK: - Playback

    @ViewBuilder
    var playbackSection: some View {
        let s = "Playback"
        if sectionVisible(s, [["autoplay", "play"], ["autoplay", "infinite play", "infinite", "autoplay style", "fill", "similar", "random", "genre"], ["crossfade", "fade", "automix", "transition", "duration", "style", "blend", "silence", "bpm", "tempo"], ["gapless playback"], ["enhanced caching", "playback cache", "prefetch", "seamless", "buffer"], ["shuffle"], ["artwork zoom on play", "artwork", "zoom"], ["resume playback after interruption", "resume", "interruption", "interrupt", "phone call", "siri", "other app", "force stop"]]) {
            Section(sectionTitle(s)) {
                if rowVisible(s, ["autoplay", "play"]) {
                    Toggle(isOn: Binding(
                        get: { audio.isAutoplay },
                        set: { audio.isAutoplay = $0 }
                    )) {
                        Label(L(.settings_autoplay), systemImage: "play.circle")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["autoplay", "infinite play", "infinite", "autoplay style", "fill", "similar", "random", "genre"]) {
                    Picker(selection: $infinitePlayStyle) {
                        ForEach(InfinitePlayStyle.allCases) { style in
                            Text(style.label).tag(style.rawValue)
                        }
                    } label: {
                        Label(L(.settings_infinite_play), systemImage: "infinity")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["crossfade", "fade", "automix", "transition"]) {
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

                    crossfadeTuningControls
                }

                if rowVisible(s, ["automix", "transition", "style", "blend", "silence", "bpm", "tempo"]) {
                    NavigationLink(value: SettingsRoute.autoMix) {
                        Label("AutoMix", systemImage: "waveform.path")
                    }
                    .foregroundStyle(Theme.primaryText)
                }

                if rowVisible(s, ["gapless playback"]) {
                    Picker(selection: $gaplessPlayback) {
                        Text("Off").tag("off")
                        Text("Weak").tag("weak")
                        Text("On").tag("on")
                    } label: {
                        Label(L(.settings_gapless), systemImage: "music.note")
                    }
                    .tint(Theme.accent)
                    .onChangeCompat(of: gaplessPlayback) { _, mode in
                        if mode == "off", audio.transitionMode == .automix {
                            audio.setTransitionMode(.crossfade)
                        }
                        audio.refreshGaplessPlaybackMode()
                    }
                }

                if rowVisible(s, ["enhanced caching", "playback cache", "prefetch", "seamless", "buffer"]) {
                    Toggle(isOn: $enhancedPlaybackCaching) {
                        Label("Enhanced Caching", systemImage: "bolt.horizontal.circle")
                    }
                    .tint(Theme.accent)
                    .onChangeCompat(of: enhancedPlaybackCaching) { _, enabled in
                        if enabled {
                            audio.refreshPlaybackCache()
                        } else {
                            PlaybackCacheService.shared.cancelPrefetches()
                        }
                    }
                }

                if rowVisible(s, ["shuffle"]) {
                    Toggle(isOn: Binding(
                        get: { audio.isShuffle },
                        set: { _ in audio.toggleShuffle() }
                    )) {
                        Label(L(.settings_shuffle_default), systemImage: "shuffle")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["artwork zoom on play", "artwork", "zoom"]) {
                    Toggle(isOn: $artworkAnimation) {
                        Label(L(.settings_artwork_zoom), systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["resume playback after interruption", "resume", "interruption", "interrupt", "phone call", "siri", "other app", "force stop"]) {
                    Toggle(isOn: $resumeAfterInterruption) {
                        Label(L(.settings_resume_interruption), systemImage: "play.circle.fill")
                    }
                    .tint(Theme.accent)
                }
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    @ViewBuilder
    var crossfadeTuningControls: some View {
        switch audio.transitionMode {
        case .off:
            EmptyView()
        case .crossfade:
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Crossfade Duration", value: "\(Int(crossfadeDurationSeconds))s")
                    .foregroundStyle(Theme.primaryText)
                Slider(value: $crossfadeDurationSeconds, in: 1...12, step: 1)
                    .tint(Theme.accent)
                    .onChangeCompat(of: crossfadeDurationSeconds) { _, _ in
                        audio.setTransitionMode(audio.transitionMode)
                    }
            }
        case .automix:
            EmptyView()
        }
    }

    // MARK: - Audio

    @ViewBuilder
    var audioSection: some View {
        let s = "Audio"
        if sectionVisible(s, [["volume normalization", "replaygain", "replay gain", "normalize", "loudness"], ["equalizer", "eq", "bands", "graphic"], ["mono audio", "mono", "accessibility", "downmix"], ["spatial widener", "spatial", "3d", "stereo", "widener", "spatialize"]]) {
            Section(sectionTitle(s)) {
                if rowVisible(s, ["equalizer", "eq", "bands", "graphic"]) {
                    NavigationLink(value: SettingsRoute.equalizer) {
                        Label(L(.settings_equalizer), systemImage: "slider.vertical.3")
                    }
                    .foregroundStyle(Theme.primaryText)
                }

                if rowVisible(s, ["volume normalization", "replaygain", "replay gain", "normalize", "loudness"]) {
                    Picker(selection: $replayGainMode) {
                        Text("Off").tag("off")
                        Text("Track").tag("track")
                        Text("Album").tag("album")
                    } label: {
                        Label(L(.settings_volume_normalization), systemImage: "speaker.wave.2.fill")
                    }
                    .tint(Theme.accent)
                }

                if rowVisible(s, ["mono audio", "mono", "accessibility", "downmix"]) {
                    Toggle(isOn: $monoAudio) {
                        Label(L(.settings_mono_audio), systemImage: "ear")
                    }
                    .tint(Theme.accent)
                    .onChangeCompat(of: monoAudio) { _, _ in applyAudioEffectChange() }
                }

                if rowVisible(s, ["spatial widener", "spatial", "3d", "stereo", "widener", "spatialize", "width"]) {
                    Toggle(isOn: $spatialWidener) {
                        Label(L(.settings_spatial_widener), systemImage: "airpodspro")
                    }
                    .tint(Theme.accent)
                    .disabled(monoAudio)
                    .onChangeCompat(of: spatialWidener) { _, _ in applyAudioEffectChange() }

                    if spatialWidener && !monoAudio {
                        Picker(selection: $spatialWidenerMode) {
                            Text("Enhanced").tag("enhanced")
                            Text("Basic").tag("basic")
                        } label: {
                            Label("Widening Mode", systemImage: "waveform")
                        }
                        .tint(Theme.accent)
                        .onChangeCompat(of: spatialWidenerMode) { _, _ in
                            EqualizerEngine.shared.refreshEffectFlags()
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Width", value: "\(Int((spatialWidenerAmount * 100).rounded()))%")
                                .foregroundStyle(Theme.primaryText)
                            Slider(value: $spatialWidenerAmount, in: 0...1.5, step: 0.05)
                                .tint(Theme.accent)
                                .onChangeCompat(of: spatialWidenerAmount) { _, _ in
                                    EqualizerEngine.shared.refreshEffectFlags()
                                }
                        }
                    }
                }
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    // re-attach/detach the audio processing tap when mono/spatial toggles flip
    func applyAudioEffectChange() {
        EqualizerEngine.shared.refreshEffectFlags()
        NotificationCenter.default.post(name: .equalizerToggled, object: nil)
    }
}
