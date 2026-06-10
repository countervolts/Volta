import SwiftUI

// Battery-saver submenu. The master switch turns Performance Mode on; the
// per-feature toggles choose what it overrides. Overrides never rewrite the
// user's real settings — they're applied at each read point in PerformanceMode.
struct PerformanceModeView: View {
    @AppStorage("performanceModeEnabled") private var enabled = false

    @AppStorage("pmHalfFrameRate")          private var halfFrameRate = true
    @AppStorage("pmReduceImageQuality")     private var reduceImageQuality = true
    @AppStorage("pmDisableLiveArtwork")     private var disableLiveArtwork = true
    @AppStorage("pmDisableDynamicBackground") private var disableDynamicBackground = true
    @AppStorage("pmReduceAnimations")       private var reduceAnimations = true
    @AppStorage("pmDisablePrefetch")        private var disablePrefetch = true
    @AppStorage("pmSimpleTransitions")      private var simpleTransitions = false
    @AppStorage("pmLowerStreamQuality")     private var lowerStreamQuality = false
    @AppStorage("pmBypassAudioEffects")     private var bypassAudioEffects = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                Section {
                    Toggle(isOn: $enabled.animation(.easeInOut(duration: 0.25))) {
                        Label("Performance Mode", systemImage: enabled ? "bolt.fill" : "bolt.slash")
                    }
                    .tint(Theme.accent)
                } footer: {
                    Text("Overrides the settings below to save battery and reduce load. Your real settings are kept and restored when Performance Mode is off.")
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    toggle($halfFrameRate, "Half Frame Rate", "gauge.with.dots.needle.50percent", "Caps scrolling and drag animations to half the display's refresh rate.")
                    toggle($reduceImageQuality, "Lighter Artwork Loading", "photo", "Conservative image loading + smaller cache. Applies on next launch.")
                    toggle($disableLiveArtwork, "Disable Live Artwork", "sparkles.rectangle.stack", "Skips animated cover art.")
                    toggle($disableDynamicBackground, "Static Player Background", "paintpalette", "Stops extracting a colour per song.")
                    toggle($reduceAnimations, "Reduce Animations", "wand.and.rays", "Drops artwork zoom and heavy motion.")
                    toggle($disablePrefetch, "Skip Image Prefetch", "person.crop.square.badge.camera", "Stops warming artist photos in the background.")
                    toggle($simpleTransitions, "Simple Transitions", "arrow.left.arrow.right", "Disables crossfade/AutoMix so only one player runs.")
                    toggle($lowerStreamQuality, "Cap Streaming Quality", "wifi.exclamationmark", "Limits streams to 192 kbps.")
                    toggle($bypassAudioEffects, "Bypass Audio Effects", "slider.vertical.3", "Disables EQ, mono and spatial processing.")
                } header: {
                    Text("What Performance Mode Does")
                } footer: {
                    Text("Each switch is what Performance Mode changes while it is on. Most take effect on the next track or request.")
                }
                .listRowBackground(Theme.secondaryBackground)
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.45)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle("Performance Mode")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
        }
        .preferredColorScheme(Theme.colorScheme)
        .onChange(of: bypassAudioEffects) { _, _ in
            EqualizerEngine.shared.refreshEffectFlags()
            NotificationCenter.default.post(name: .equalizerToggled, object: nil)
        }
        .onChange(of: enabled) { _, _ in
            EqualizerEngine.shared.refreshEffectFlags()
            NotificationCenter.default.post(name: .equalizerToggled, object: nil)
        }
    }

    @ViewBuilder
    private func toggle(_ binding: Binding<Bool>, _ title: String, _ icon: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: binding) {
                Label(title, systemImage: icon)
            }
            .tint(Theme.accent)
            Text(detail)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 2)
    }
}
