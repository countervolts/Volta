import SwiftUI
import AVFoundation

struct AutoMixPreviewView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var engine = AutoMixPreviewEngine()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    if let error = engine.errorMessage {
                        emptyState(error)
                    } else {
                        tracks
                        transitionSummary
                        timeline
                        reasons
                        controls
                    }
                }
                .padding(20)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("AutoMix Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
        }
        .preferredColorScheme(Theme.colorScheme)
        .task { await engine.prepare(appState) }
        .onDisappear { engine.stop() }
    }

    private var tracks: some View {
        VStack(spacing: 12) {
            trackCard(song: engine.songA, analysis: engine.analysisA, label: "Track A")
            Image(systemName: "arrow.down").foregroundStyle(Theme.secondaryText)
            trackCard(song: engine.songB, analysis: engine.analysisB, label: "Track B")
        }
    }

    private func trackCard(
        song: Song?,
        analysis: AutoMixTrackAnalysis?,
        label: String
    ) -> some View {
        HStack(spacing: 14) {
            ArtworkView(coverArtID: song?.coverArt, size: 160, cornerRadius: 12)
                .frame(width: 88, height: 88)
                .overlay {
                    if engine.isLoading {
                        RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.25))
                        ProgressView().tint(.white)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.accent)
                Text(song?.title ?? "—")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text(song?.artist ?? " ")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                if let analysis {
                    Text(trackFacts(analysis))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.secondaryBackground))
    }

    private func trackFacts(_ analysis: AutoMixTrackAnalysis) -> String {
        let tempo = analysis.tempo.map {
            "\(String(format: "%.1f", $0.bpm)) BPM \(percent($0.confidence))"
        } ?? "Tempo unavailable"
        let meter = analysis.meter.map {
            "meter \($0.beatsPerBar) \(percent($0.confidence))"
        } ?? "meter uncertain"
        let key = analysis.key.map {
            "\($0.key.camelot) \(percent($0.confidence))"
        } ?? "key uncertain"
        return "\(tempo)  •  beat \(percent(analysis.beatConfidence))\n\(meter)  •  downbeat \(percent(analysis.downbeatConfidence))  •  \(key)"
    }

    @ViewBuilder private var transitionSummary: some View {
        if let plan = engine.plan {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(plan.type.displayName, systemImage: transitionIcon(plan.type))
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                    Spacer()
                    Text(percent(plan.confidence))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                diagnosticRow("Out cue", clock(plan.outgoingCue))
                diagnosticRow("In cue", clock(plan.incomingCue))
                diagnosticRow("Overlap", "\(String(format: "%.2f", plan.duration)) s")
                diagnosticRow("Tempo", tempoAdjustment(plan))
                diagnosticRow("Alignment", alignment(plan))
                if let fallback = plan.fallbackReason {
                    diagnosticRow("Fallback", fallback)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.secondaryBackground))
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PREVIEW TIMELINE")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.secondaryText)
            GeometryReader { geometry in
                let width = geometry.size.width
                let total = max(0.01, engine.previewDuration)
                let leadWidth = width * engine.leadIn / total
                let blendWidth = width * engine.blend / total
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.accent.opacity(0.6)).frame(height: 13)
                    Capsule()
                        .fill(Color.blue.opacity(0.7))
                        .frame(width: max(0, width - leadWidth), height: 13)
                        .offset(x: leadWidth, y: 18)
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.orange, lineWidth: 1.5)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.orange.opacity(0.18)))
                        .frame(width: blendWidth, height: 31)
                        .offset(x: leadWidth)
                    if engine.isPlaying {
                        Rectangle()
                            .fill(.white)
                            .frame(width: 2, height: 34)
                            .offset(x: min(width - 1, max(0, width * engine.progress)))
                    }
                }
            }
            .frame(height: 34)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.secondaryBackground))
    }

    @ViewBuilder private var reasons: some View {
        if let plan = engine.plan {
            VStack(alignment: .leading, spacing: 7) {
                Text("PLANNER REASONS")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.secondaryText)
                ForEach(Array(plan.reasons.enumerated()), id: \.offset) { _, reason in
                    Label(reason, systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(Theme.primaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.secondaryBackground))
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { Task { await engine.reshuffle() } } label: {
                Label("New Pair", systemImage: "shuffle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Theme.secondaryBackground))
            }
            .disabled(engine.isLoading)

            Button { engine.isPlaying ? engine.stop() : engine.play() } label: {
                Label(engine.isPlaying ? "Stop" : "Play", systemImage: engine.isPlaying ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Theme.accent))
                    .foregroundStyle(.white)
            }
            .disabled(engine.isLoading || engine.plan?.usesDualPlayers != true)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Theme.primaryText)
    }

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Theme.secondaryText)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Try Again") { Task { await engine.reshuffle() } }
                .foregroundStyle(Theme.accent)
        }
        .padding(.top, 60)
    }

    private func diagnosticRow(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name).foregroundStyle(Theme.secondaryText)
            Spacer()
            Text(value).foregroundStyle(Theme.primaryText).monospacedDigit()
        }
        .font(.caption)
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    private func clock(_ value: TimeInterval) -> String {
        let totalMilliseconds = Int((max(0, value) * 1_000).rounded())
        return String(format: "%d:%02d.%03d", totalMilliseconds / 60_000, (totalMilliseconds / 1_000) % 60, totalMilliseconds % 1_000)
    }
    private func tempoAdjustment(_ plan: AutoMixTransitionPlan) -> String {
        guard abs(plan.incomingRate - 1) >= 0.001 else { return "native" }
        return String(format: "%+.2f%% incoming", (Double(plan.incomingRate) - 1) * 100)
    }
    private func alignment(_ plan: AutoMixTransitionPlan) -> String {
        if plan.alignedBarCount > 0 { return "\(plan.alignedBarCount) bars" }
        if plan.alignedBeatCount > 0 { return "\(plan.alignedBeatCount) beats" }
        return "none"
    }
    private func transitionIcon(_ type: AutoMixTransitionType) -> String {
        switch type {
        case .intendedGapless: "link"
        case .silenceTrim: "scissors"
        case .adaptiveCrossfade: "waveform"
        case .beatMix: "metronome"
        case .phraseMix: "music.note.list"
        case .tightCut: "bolt.fill"
        }
    }
}

@MainActor
final class AutoMixPreviewEngine: ObservableObject {
    @Published private(set) var songA: Song?
    @Published private(set) var songB: Song?
    @Published private(set) var analysisA: AutoMixTrackAnalysis?
    @Published private(set) var analysisB: AutoMixTrackAnalysis?
    @Published private(set) var plan: AutoMixTransitionPlan?
    @Published private(set) var isLoading = false
    @Published private(set) var isPlaying = false
    @Published private(set) var progress = 0.0
    @Published private(set) var errorMessage: String?

    let leadIn: TimeInterval = 5
    let leadOut: TimeInterval = 5
    var blend: TimeInterval { plan?.duration ?? 0 }
    var previewDuration: TimeInterval { leadIn + blend + leadOut }

    private weak var appState: AppState?
    private var outgoingPlayer: AVPlayer?
    private var incomingPlayer: AVPlayer?
    private var observers: [(AVPlayer, Any)] = []
    private var generation: UInt64 = 0

    func prepare(_ appState: AppState) async {
        self.appState = appState
        guard songA == nil, !isLoading else { return }
        await pickSongs()
    }

    func reshuffle() async {
        stop()
        songA = nil
        songB = nil
        analysisA = nil
        analysisB = nil
        plan = nil
        errorMessage = nil
        await pickSongs()
    }

    private func pickSongs() async {
        guard let appState else { return }
        isLoading = true
        defer { isLoading = false }
        var pool = DownloadService.shared.downloadedSongs().filter { ($0.duration ?? 0) >= 45 }
        if pool.count < 2, let client = appState.client {
            pool += ((try? await client.randomSongs(size: 30)) ?? []).filter { ($0.duration ?? 0) >= 45 }
        }
        var seen = Set<String>()
        pool = pool.filter { seen.insert($0.id).inserted }
        guard pool.count >= 2 else {
            errorMessage = "Add or download at least two tracks to inspect AutoMix."
            return
        }
        pool.shuffle()
        let first = pool[0]
        let second = pool.dropFirst().first(where: {
            $0.albumId == nil || first.albumId == nil || $0.albumId != first.albumId
        }) ?? pool[1]
        songA = first
        songB = second
        async let firstAnalysis = appState.audioPlayer.autoMixAnalysis(for: first)
        async let secondAnalysis = appState.audioPlayer.autoMixAnalysis(for: second)
        async let pairPlan = appState.audioPlayer.autoMixPlan(current: first, next: second)
        let results = await (firstAnalysis, secondAnalysis, pairPlan)
        guard !Task.isCancelled,
              songA?.id == first.id,
              songB?.id == second.id else { return }
        analysisA = results.0
        analysisB = results.1
        plan = results.2
    }

    func play() {
        guard !isPlaying,
              let appState,
              let songA,
              let songB,
              let plan,
              plan.usesDualPlayers,
              let urlA = appState.audioPlayer.autoMixPreviewURL(for: songA),
              let urlB = appState.audioPlayer.autoMixPreviewURL(for: songB) else { return }
        appState.audioPlayer.pause()
        generation &+= 1
        let token = generation
        Task { @MainActor [weak self] in
            await self?.startPreview(urlA: urlA, urlB: urlB, plan: plan, generation: token)
        }
    }

    private func startPreview(
        urlA: URL,
        urlB: URL,
        plan: AutoMixTransitionPlan,
        generation token: UInt64
    ) async {
        let itemA = AVPlayerItem(url: urlA)
        let itemB = AVPlayerItem(url: urlB)
        itemA.audioTimePitchAlgorithm = .spectral
        itemB.audioTimePitchAlgorithm = .spectral
        guard let trackA = try? await itemA.asset.loadTracks(withMediaType: .audio).first,
              let trackB = try? await itemB.asset.loadTracks(withMediaType: .audio).first,
              generation == token else { return }

        let parametersA = AVMutableAudioMixInputParameters(track: trackA)
        let parametersB = AVMutableAudioMixInputParameters(track: trackB)
        AutoMixTimedEnvelope.applyOutgoing(plan, to: parametersA)
        AutoMixTimedEnvelope.applyIncoming(plan, to: parametersB)
        let mixA = AVMutableAudioMix(); mixA.inputParameters = [parametersA]
        let mixB = AVMutableAudioMix(); mixB.inputParameters = [parametersB]
        itemA.audioMix = mixA
        itemB.audioMix = mixB

        let playerA = AVPlayer(playerItem: itemA)
        let playerB = AVPlayer(playerItem: itemB)
        outgoingPlayer = playerA
        incomingPlayer = playerB
        let startA = max(0, plan.outgoingCue - leadIn)
        await seek(playerA, to: startA)
        await seek(playerB, to: plan.incomingCue)
        let ready = await waitUntilReady(itemB, timeout: 3)
        guard ready, generation == token else {
            stop()
            return
        }

        isPlaying = true
        progress = 0
        try? AVAudioSession.sharedInstance().setActive(true)
        playerA.playImmediately(atRate: 1)
        addBoundary(player: playerA, time: plan.outgoingCue) { [weak self, weak playerB] in
            guard self?.generation == token else { return }
            playerB?.playImmediately(atRate: plan.incomingRate)
        }
        addBoundary(
            player: playerB,
            time: plan.incomingCue + plan.incomingMediaDuration + leadOut * Double(plan.incomingRate)
        ) { [weak self] in self?.stop() }
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        let progressToken = playerA.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.progress = min(1, max(0, (time.seconds - startA) / self.previewDuration))
            }
        }
        observers.append((playerA, progressToken))
    }

    func stop() {
        generation &+= 1
        for (player, observer) in observers { player.removeTimeObserver(observer) }
        observers.removeAll()
        outgoingPlayer?.pause()
        incomingPlayer?.pause()
        outgoingPlayer?.rate = 1
        incomingPlayer?.rate = 1
        outgoingPlayer = nil
        incomingPlayer = nil
        isPlaying = false
        progress = 0
    }

    private func addBoundary(player: AVPlayer, time: TimeInterval, action: @escaping @MainActor () -> Void) {
        let observer = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: CMTime(seconds: time, preferredTimescale: 600))],
            queue: .main
        ) { Task { @MainActor in action() } }
        observers.append((player, observer))
    }

    private func seek(_ player: AVPlayer, to seconds: TimeInterval) async {
        await withCheckedContinuation { continuation in
            player.seek(
                to: CMTime(seconds: seconds, preferredTimescale: 600),
                toleranceBefore: CMTime(seconds: 0.012, preferredTimescale: 600),
                toleranceAfter: CMTime(seconds: 0.012, preferredTimescale: 600)
            ) { _ in continuation.resume() }
        }
    }

    private func waitUntilReady(_ item: AVPlayerItem, timeout: TimeInterval) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if item.status == .readyToPlay { return true }
            if item.status == .failed { return false }
            try? await Task.sleep(nanoseconds: 50_000_000)
            if Task.isCancelled { return false }
        }
        return item.status == .readyToPlay
    }
}
