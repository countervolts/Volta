import SwiftUI

// 10-band graphic equalizer. Gains feed EqualizerEngine live; the enable toggle
// attaches/removes the audio tap on the currently playing item.
struct EqualizerView: View {
    @AppStorage("equalizerEnabled") private var enabled = false
    @State private var gains: [Double] = EqualizerEngine.shared.gains

    private let bandCount = EqualizerEngine.bandCount

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
                    .onChange(of: enabled) { _, _ in
                        NotificationCenter.default.post(name: .equalizerToggled, object: nil)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    presetsRow

                    bandsRow
                        .opacity(enabled ? 1 : 0.4)
                        .allowsHitTesting(enabled)

                    Text("Adjust each frequency band from −12 dB to +12 dB. Changes apply instantly to playback.")
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
                Button("Reset") { applyPreset([Double](repeating: 0, count: bandCount)) }
                    .foregroundStyle(Theme.accent)
            }
        }
        .preferredColorScheme(.dark)
        .background(SwipeBackEnabler())
    }

    // MARK: - Presets

    private var presetsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Self.presets, id: \.name) { preset in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            applyPreset(preset.gains)
                        }
                    } label: {
                        Text(preset.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Theme.secondaryBackground, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Bands

    private var bandsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 14) {
                ForEach(0..<bandCount, id: \.self) { i in
                    VStack(spacing: 8) {
                        Text(gainText(gains[i]))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.secondaryText)
                        Slider(value: bandBinding(i), in: EqualizerEngine.range)
                            .frame(width: 150)
                            .rotationEffect(.degrees(-90))
                            .frame(width: 40, height: 150)
                            .tint(Theme.accent)
                        Text(freqText(EqualizerEngine.frequencies[i]))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.primaryText)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func bandBinding(_ i: Int) -> Binding<Double> {
        Binding(
            get: { gains[i] },
            set: { gains[i] = $0; EqualizerEngine.shared.setGain($0, band: i) }
        )
    }

    private func applyPreset(_ values: [Double]) {
        gains = values
        EqualizerEngine.shared.setAll(values)
    }

    private func gainText(_ v: Double) -> String {
        String(format: "%+.0f", v)
    }

    private func freqText(_ f: Double) -> String {
        f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))"
    }

    // MARK: - Presets data

    private struct Preset { let name: String; let gains: [Double] }
    private static let presets: [Preset] = [
        Preset(name: "Flat",        gains: [0,0,0,0,0,0,0,0,0,0]),
        Preset(name: "Bass Boost",  gains: [9,7,5,3,1,0,0,0,0,0]),
        Preset(name: "Treble Boost",gains: [0,0,0,0,0,1,3,5,7,8]),
        Preset(name: "Vocal",       gains: [-2,-1,0,2,4,4,3,1,0,-1]),
        Preset(name: "Loudness",    gains: [6,4,1,0,-1,0,1,3,5,6]),
        Preset(name: "Acoustic",    gains: [4,3,2,0,1,1,3,3,2,1]),
    ]
}
