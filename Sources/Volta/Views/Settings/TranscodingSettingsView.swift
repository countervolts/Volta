import SwiftUI

struct TranscodingSettingsView: View {
    @AppStorage(StreamingPreferences.transcodingEnabledKey) private var transcodingEnabled = true
    @AppStorage(StreamingPreferences.transcodingModeKey) private var modeRaw = TranscodingSettingsMode.simple.rawValue
    @AppStorage(StreamingPreferences.transcodingCellularOnlyKey) private var cellularOnly = false
    @AppStorage("transcodingFormat") private var fallbackFormat = "raw"
    @AppStorage(StreamingPreferences.transcodeFileTypeRulesKey) private var rulesRaw = ""
    @AppStorage(StreamingPreferences.transcodeRuleDefaultBitrateKey) private var ruleDefaultBitrate = 320

    private let bitrateOptions = [96, 128, 160, 192, 256, 320]
    private var mode: TranscodingSettingsMode { TranscodingSettingsMode(rawValue: modeRaw) ?? .simple }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                Section {
                    Toggle(isOn: $transcodingEnabled) {
                        Label("Transcoding", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .tint(Theme.accent)

                    Picker(selection: modeBinding) {
                        ForEach(TranscodingSettingsMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    } label: {
                        Label("Mode", systemImage: "slider.horizontal.2.square")
                    }
                    .pickerStyle(.segmented)
                    .disabled(!transcodingEnabled)

                    Toggle(isOn: $cellularOnly) {
                        Label("Only on Cellular", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .tint(Theme.accent)
                    .disabled(!transcodingEnabled)
                } header: {
                    Text("Mode")
                } footer: {
                    Text("Simple keeps the original Volta behavior. Advanced lets you choose target codecs by source file type. Only on Cellular asks the connected server to transcode only while Volta is on cellular data.")
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    Picker(selection: $fallbackFormat) {
                        Text("Automatic").tag("raw")
                        Text("MP3").tag("mp3")
                        Text("AAC").tag("aac")
                        Text("Opus").tag("opus")
                    } label: {
                        Label("Default Target", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .tint(Theme.accent)
                    .disabled(!transcodingEnabled)
                } header: {
                    Text("Simple")
                } footer: {
                    Text("Simple uses Wi-Fi, cellular, and download quality limits. Automatic lets the server choose the codec when a quality limit requires transcoding.")
                }
                .listRowBackground(Theme.secondaryBackground)

                if mode == .advanced {
                    Section {
                        Picker(selection: $ruleDefaultBitrate) {
                            ForEach(bitrateOptions, id: \.self) { bitrate in
                                Text("\(bitrate) kbps").tag(bitrate)
                            }
                        } label: {
                            Label("Rule Bitrate", systemImage: "speedometer")
                        }
                        .tint(Theme.accent)
                        .disabled(!transcodingEnabled)
                    } header: {
                        Text("Advanced")
                    } footer: {
                        Text("Codec rules use this bitrate when Wi-Fi or download quality is set to Original.")
                    }
                    .listRowBackground(Theme.secondaryBackground)

                    Section {
                        ForEach(TranscodeSourceKind.allCases) { kind in
                            Picker(selection: targetBinding(for: kind)) {
                                ForEach(TranscodeRuleTarget.allCases) { target in
                                    Text(target.label).tag(target)
                                }
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(kind.title)
                                            .foregroundStyle(Theme.primaryText)
                                        Text(kind.detail)
                                            .font(.caption)
                                            .foregroundStyle(Theme.secondaryText)
                                    }
                                } icon: {
                                    Image(systemName: kind.systemImage)
                                }
                            }
                            .tint(Theme.accent)
                            .disabled(!transcodingEnabled)
                        }
                    } header: {
                        Text("File Types")
                    } footer: {
                        Text("Automatic follows the Simple default target. Original skips transcoding for that file type even when a quality limit is active.")
                    }
                    .listRowBackground(Theme.secondaryBackground)

                    Section {
                        Button {
                            rulesRaw = ""
                        } label: {
                            Label("Reset File-Type Rules", systemImage: "arrow.counterclockwise")
                        }
                        .disabled(rulesRaw.isEmpty || !transcodingEnabled)
                    }
                    .listRowBackground(Theme.secondaryBackground)
                }
            }
            .labelStyle(AccentIconLabelStyle())
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle("Transcode")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(Theme.colorScheme)
        .onAppear {
            if !bitrateOptions.contains(ruleDefaultBitrate) {
                ruleDefaultBitrate = 320
            }
            StreamingPreferences.migrateTranscodingSettingsIfNeeded()
        }
    }

    private var modeBinding: Binding<TranscodingSettingsMode> {
        Binding {
            TranscodingSettingsMode(rawValue: modeRaw) ?? .simple
        } set: { newMode in
            modeRaw = newMode.rawValue
        }
    }

    private func targetBinding(for kind: TranscodeSourceKind) -> Binding<TranscodeRuleTarget> {
        Binding {
            StreamingPreferences.ruleTarget(
                for: kind,
                targets: StreamingPreferences.decodeRuleTargets(rulesRaw)
            )
        } set: { newTarget in
            var targets = StreamingPreferences.decodeRuleTargets(rulesRaw)
            if newTarget == .automatic {
                targets.removeValue(forKey: kind)
            } else {
                targets[kind] = newTarget
            }
            rulesRaw = StreamingPreferences.encodeRuleTargets(targets)
        }
    }
}
