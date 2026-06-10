import SwiftUI
import AVFoundation

// Settings → AutoMix → Preview. Picks two of the user's tracks, shows how much of
// each plays and where the blend (orange) lands on a timeline, and can play the
// transition out loud so the AutoMix tuning can be auditioned before committing.
struct AutoMixPreviewView: View {
    @Environment(AppState.self) private var appState
    @State private var engine = AutoMixPreviewEngine()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    if engine.errorMessage != nil {
                        emptyState
                    } else {
                        songsRow
                        harmonicBadge
                        timeline
                        legend
                        controls
                    }
                }
                .padding(20)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Preview AutoMix")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
        }
        .preferredColorScheme(Theme.colorScheme)
        .task { await engine.prepare(appState) }
        .onDisappear { engine.stop() }
    }

    // MARK: - Two songs

    private var songsRow: some View {
        HStack(alignment: .top, spacing: 12) {
            songCard(engine.songA, key: engine.keyA, label: "Now Playing")
            Image(systemName: "arrow.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 44)
            songCard(engine.songB, key: engine.keyB, label: "Up Next")
        }
    }

    private func songCard(_ song: Song?, key: MusicalKey?, label: String) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .textCase(.uppercase)
            ArtworkView(coverArtID: song?.coverArt, size: 200, cornerRadius: 12)
                .frame(width: 110, height: 110)
                .overlay {
                    if engine.isLoading {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.black.opacity(0.25))
                        ProgressView().tint(.white)
                    }
                }
            Text(song?.title ?? "—")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
            Text(song?.artist ?? " ")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
            keyChip(key)
        }
        .frame(maxWidth: .infinity)
    }

    private func keyChip(_ key: MusicalKey?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "pianokeys")
            Text(key?.camelot ?? "—")
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(key == nil ? Theme.secondaryText : Theme.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Theme.secondaryBackground))
    }

    // Camelot harmonic-match badge shown between the two tracks.
    @ViewBuilder private var harmonicBadge: some View {
        if let compat = engine.harmonicCompatibility {
            let (text, color, icon): (String, Color, String) =
                compat >= 0.8 ? ("Harmonic match", .green, "checkmark.seal.fill")
                : compat >= 0.45 ? ("Keys blend well", Theme.accent, "circle.dashed")
                : ("Different keys — quick blend", .orange, "arrow.triangle.swap")
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(text)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.14)))
        }
    }

    // MARK: - Timeline

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Timeline")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .textCase(.uppercase)

            GeometryReader { geo in
                let total = max(0.001, engine.totalDuration)
                let w = geo.size.width
                let pxPerSec = w / total
                let leadInW = engine.leadIn * pxPerSec
                let blendW = engine.blend * pxPerSec
                let songAW = (engine.leadIn + engine.blend) * pxPerSec
                let songBW = (engine.blend + engine.leadOut) * pxPerSec
                let barHeight: CGFloat = 16
                let gap: CGFloat = 8

                ZStack(alignment: .topLeading) {
                    // Song A occupies the first part of the timeline (top row)
                    Capsule()
                        .fill(Theme.accent.opacity(0.55))
                        .frame(width: max(0, songAW), height: barHeight)
                        .offset(x: 0, y: 0)

                    // Song B starts at the blend and runs to the end (bottom row)
                    Capsule()
                        .fill(Color(red: 0.30, green: 0.62, blue: 0.95).opacity(0.65))
                        .frame(width: max(0, songBW), height: barHeight)
                        .offset(x: leadInW, y: barHeight + gap)

                    // The blend window — where AutoMix is actually happening.
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.orange.opacity(0.30))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.orange, lineWidth: 1.5)
                        )
                        .frame(width: max(0, blendW), height: barHeight * 2 + gap)
                        .offset(x: leadInW, y: 0)

                    // Playhead while previewing.
                    if engine.isPlaying {
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 2, height: barHeight * 2 + gap)
                            .offset(x: min(w - 1, max(0, engine.progress * w)), y: 0)
                            .shadow(color: .black.opacity(0.4), radius: 1)
                    }
                }
                .frame(height: barHeight * 2 + gap, alignment: .topLeading)
            }
            .frame(height: 40)

            HStack {
                Text(durationLabel(engine.leadIn) + " intro")
                Spacer()
                Text("\(Int(engine.blend.rounded()))s blend")
                    .foregroundStyle(.orange)
                Spacer()
                Text(durationLabel(engine.leadOut) + " outro")
            }
            .font(.caption2)
            .foregroundStyle(Theme.secondaryText)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.secondaryBackground))
    }

    private func durationLabel(_ seconds: TimeInterval) -> String {
        "\(Int(seconds.rounded()))s"
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendDot(Theme.accent.opacity(0.55), "Track A")
            legendDot(Color(red: 0.30, green: 0.62, blue: 0.95).opacity(0.65), "Track B")
            legendDot(.orange, "AutoMix")
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(Theme.secondaryText)
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 14) {
            Button {
                Task { await engine.reshuffle() }
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Theme.secondaryBackground))
                    .foregroundStyle(Theme.primaryText)
            }
            .disabled(engine.isLoading)

            Button {
                if engine.isPlaying { engine.stop() } else { engine.play() }
            } label: {
                Label(engine.isPlaying ? "Stop" : "Play Preview",
                      systemImage: engine.isPlaying ? "stop.fill" : "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Theme.accent))
                    .foregroundStyle(.white)
            }
            .disabled(engine.isLoading || engine.songA == nil)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.secondaryText)
            Text(engine.errorMessage ?? "")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Try Again") { Task { await engine.reshuffle() } }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// Drives the audible + visual AutoMix preview. Mirrors the live AudioPlayer blend
// (volume crossfade + optional beat-match via AutoMixTempo) over a short clip of
// two tracks, without disturbing the main queue.
@MainActor
@Observable
final class AutoMixPreviewEngine {
    private(set) var songA: Song?
    private(set) var songB: Song?
    private(set) var keyA: MusicalKey?
    private(set) var keyB: MusicalKey?
    private var gridA: AutoMixBeatGrid?
    private var gridB: AutoMixBeatGrid?
    private(set) var isLoading = false
    private(set) var isPlaying = false
    private(set) var isBlending = false
    private(set) var progress: Double = 0
    private(set) var errorMessage: String?

    // Timeline (seconds). Side clips are fixed so there's musical context either
    // side; the blend tracks the user's AutoMix duration so the orange section
    // grows/shrinks with the setting.
    private(set) var leadIn: TimeInterval = 5
    private(set) var leadOut: TimeInterval = 5
    private(set) var blend: TimeInterval = 8
    var totalDuration: TimeInterval { leadIn + blend + leadOut }

    private weak var appState: AppState?
    private var clipStartA: TimeInterval = 0
    private var clipStartB: TimeInterval = 0
    private var playerA: AVPlayer?
    private var playerB: AVPlayer?
    private var driveTask: Task<Void, Never>?

    func prepare(_ appState: AppState) async {
        if self.appState == nil { self.appState = appState }
        guard songA == nil, !isLoading else { return }
        await pickSongs()
    }

    func reshuffle() async {
        stop()
        songA = nil; songB = nil
        keyA = nil; keyB = nil; gridA = nil; gridB = nil; errorMessage = nil
        await pickSongs()
    }

    // Camelot compatibility of the two previewed tracks, 0…1 (nil if a key is
    // unknown). Drives the harmonic badge + how long the blend runs.
    var harmonicCompatibility: Double? {
        guard let keyA, let keyB else { return nil }
        return MusicalKey.compatibility(keyA, keyB)
    }

    // MARK: - Song selection

    private func pickSongs() async {
        isLoading = true
        defer { isLoading = false }

        var pool = DownloadService.shared.downloadedSongs().filter { ($0.duration ?? 0) >= 30 }
        if pool.count < 2, let client = appState?.client {
            let random = (try? await client.randomSongs(size: 40)) ?? []
            pool += random.filter { ($0.duration ?? 0) >= 30 }
        }
        var seen = Set<String>()
        pool = pool.filter { seen.insert($0.id).inserted }
        guard pool.count >= 2 else {
            errorMessage = "Add or download some music to preview AutoMix."
            return
        }
        // Downloaded candidates first (fast, cached); only fall back to streamed.
        pool.sort { (DownloadService.shared.localURL(for: $0) != nil ? 0 : 1)
                  < (DownloadService.shared.localURL(for: $1) != nil ? 0 : 1) }
        if pool.allSatisfy({ DownloadService.shared.localURL(for: $0) != nil }) { pool.shuffle() }

        let a = pool[0]
        songA = a
        let aAnalysis = await appState?.audioPlayer.autoMixAnalysis(for: a)
        guard songA?.id == a.id else { return }
        keyA = aAnalysis?.key; gridA = aAnalysis?.grid

        // Audition the feature at its best: from a handful of candidates, pick the
        // Up Next track that mixes most smoothly with A (harmonic + lockable tempo)
        // rather than a fully random pair — most random pairs clash on key.
        let candidates = Array(pool.dropFirst().prefix(6))
        var best: (song: Song, analysis: AutoMixTrackAnalysis?, score: Double)?
        for cand in candidates {
            guard songA?.id == a.id else { return }
            let ca = await appState?.audioPlayer.autoMixAnalysis(for: cand)
            let score = Self.mixScore(aKey: keyA, aGrid: gridA, bKey: ca?.key, bGrid: ca?.grid)
            if best == nil || score > best!.score { best = (cand, ca, score) }
            if score >= 0.85 { break }   // great match — stop early
        }
        guard songA?.id == a.id, let chosen = best else {
            errorMessage = "Add or download some music to preview AutoMix."
            return
        }
        songB = chosen.song
        keyB = chosen.analysis?.key
        gridB = chosen.analysis?.grid
        computePlan(a: a)
    }

    // How well two tracks would mix: Camelot harmonic compatibility plus a bonus
    // when their tempos can actually lock into a beat-match.
    private static func mixScore(aKey: MusicalKey?, aGrid: AutoMixBeatGrid?, bKey: MusicalKey?, bGrid: AutoMixBeatGrid?) -> Double {
        var score = (aKey != nil && bKey != nil) ? MusicalKey.compatibility(aKey, bKey) : 0.5
        if let aGrid, let bGrid, AutoMixTempo.outgoingRate(currentBPM: aGrid.bpm, nextBPM: bGrid.bpm) != nil {
            score += 0.15
        }
        return score
    }

    private func computePlan(a: Song) {
        var b = Self.crossSongBlend()
        // Harmonic length scaling — mirrors the live engine.
        let harmonicOn = UserDefaults.standard.object(forKey: "automixHarmonic") as? Bool ?? true
        if harmonicOn, let compat = harmonicCompatibility {
            if compat < 0.5 { b = max(2.5, b * 0.6) }
            else if compat < 0.85 { b = max(3, b * 0.85) }
        }
        blend = b
        leadIn = 5
        leadOut = 5
        let durA = Double(a.duration ?? 180)
        let need = leadIn + blend + 1
        let ideal = max(20, durA * 0.35)
        var startA = max(0, min(ideal, durA - need))
        // Snap so the blend opens on a downbeat of track A (the phase-locked drop).
        if let ga = gridA {
            let open = ga.downbeat(atOrAfter: startA + leadIn)
            startA = max(0, min(open - leadIn, durA - need))
        }
        clipStartA = startA
        // Start track B on its first strong downbeat (skip soft intro, land on beat).
        if let gb = gridB {
            clipStartB = gb.downbeat(atOrAfter: max(0, gb.firstStrongBeat))
        } else {
            clipStartB = 0
        }
    }

    // Mirrors PlaybackTransitionSettings.automixDuration for two unrelated tracks.
    private static func crossSongBlend() -> TimeInterval {
        let style = UserDefaults.standard.string(forKey: "automixStyle") ?? "balanced"
        let raw = UserDefaults.standard.double(forKey: "automixMaxBlendSeconds")
        let maxBlend = min(18, max(4, raw > 0 ? raw : 10))
        let base: TimeInterval
        switch style {
        case "tight": base = 5
        case "wide": base = 10
        default: base = 8
        }
        return min(maxBlend, max(3, base))
    }

    // Constant rate for the outgoing track so its beats match the incoming track's
    // tempo, or nil when BPM Match is off / tempos aren't known or close enough.
    private func outgoingRate() -> Float? {
        let enabled = UserDefaults.standard.object(forKey: "automixTempoMatch") as? Bool ?? true
        guard enabled, let a = gridA?.bpm, let b = gridB?.bpm,
              let r = AutoMixTempo.outgoingRate(currentBPM: a, nextBPM: b) else { return nil }
        return r.rate
    }

    // MARK: - Playback

    func play() {
        guard !isPlaying, let a = songA, let b = songB,
              let urlA = playbackURL(for: a), let urlB = playbackURL(for: b) else { return }

        appState?.audioPlayer.pause()
        try? AVAudioSession.sharedInstance().setActive(true)

        // One cheap pitch-preserving algorithm for both, fixed at creation — never
        // switched mid-playback (which re-primes the unit and drops to silence).
        let outgoingRate = self.outgoingRate()
        let itemA = AVPlayerItem(url: urlA)
        itemA.audioTimePitchAlgorithm = .timeDomain
        let itemB = AVPlayerItem(url: urlB)
        itemB.audioTimePitchAlgorithm = .timeDomain

        let pa = AVPlayer(playerItem: itemA)
        let pb = AVPlayer(playerItem: itemB)
        pa.volume = 1
        pb.volume = 0
        playerA = pa
        playerB = pb

        // Both players start together so the incoming track is already rolling
        // (warmed up, past any leading silence) by the time the blend begins —
        // that's what keeps the start of the mix from being silent then jumping in.
        pa.seek(to: CMTime(seconds: clipStartA, preferredTimescale: 600))
        pb.seek(to: CMTime(seconds: clipStartB, preferredTimescale: 600))

        isPlaying = true
        isBlending = false
        progress = 0
        pa.play()
        pb.play()

        let total = totalDuration
        let leadIn = self.leadIn
        let blend = self.blend
        driveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let start = Date()
            var blendStarted = false
            var blendDone = false
            var phaseLocked = false
            while !Task.isCancelled {
                let t = Date().timeIntervalSince(start)
                if t >= total { break }
                self.progress = min(1, t / total)

                if t < leadIn {
                    // intro: only track A is heard, track B plays underneath muted
                    pa.volume = 1
                    pb.volume = 0
                } else if !blendDone {
                    self.isBlending = true
                    // At the instant the blend opens, nudge B onto its nearest
                    // downbeat (still muted, so inaudible) so its beats land on A's —
                    // the same phase lock the live engine performs.
                    if !phaseLocked {
                        phaseLocked = true
                        if let gb = self.gridB {
                            let pIn = pb.currentTime().seconds
                            if pIn.isFinite {
                                let db = gb.downbeat(atOrAfter: pIn + 0.02)
                                let tol = CMTime(seconds: 0.012, preferredTimescale: 600)
                                pb.seek(to: CMTime(seconds: db, preferredTimescale: 600), toleranceBefore: tol, toleranceAfter: tol, completionHandler: { _ in })
                            }
                        }
                    }
                    let x = min(1, max(0, (t - leadIn) / blend))
                    if x < 1 {
                        // constant-power (equal-power) eased blend — no mid dip, so
                        // loudness stays steady; matches the live AutoMix character.
                        let phase = x * x * (3 - 2 * x)
                        let theta = phase * (Double.pi / 2)
                        pa.volume = Float(cos(theta))
                        pb.volume = Float(sin(theta))
                        // Bend the outgoing track (A) once, ~15% into the fade so it's
                        // already ducking (masks the engage). Single change = no stutter;
                        // incoming (B) plays clean at its true tempo.
                        if let outgoingRate, !blendStarted, x >= 0.15 {
                            blendStarted = true
                            pa.rate = outgoingRate
                        }
                    } else {
                        blendDone = true
                        self.isBlending = false
                        pa.volume = 0
                        pa.pause()
                        pb.volume = 1
                    }
                }

                try? await Task.sleep(nanoseconds: 33_000_000)
            }
            self.finish()
        }
    }

    func stop() {
        driveTask?.cancel()
        driveTask = nil
        finish()
    }

    private func finish() {
        playerA?.pause()
        playerB?.pause()
        playerA = nil
        playerB = nil
        isPlaying = false
        isBlending = false
        progress = 0
    }

    private func playbackURL(for song: Song) -> URL? {
        if let local = DownloadService.shared.localURL(for: song) { return local }
        return appState?.client?.streamURL(id: song.id)
    }
}
