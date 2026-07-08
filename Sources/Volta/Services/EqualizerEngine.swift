import Foundation
import AVFoundation
import os

extension Notification.Name {
    // Player re-attaches/removes taps when this fires.
    static let equalizerToggled = Notification.Name("EqualizerToggled")
}

struct AudioVisualizerSnapshot: Sendable {
    static let bandCount = 48
    static let silent = AudioVisualizerSnapshot(
        bands: [Double](repeating: 0, count: bandCount),
        rms: 0,
        peak: 0,
        beat: 0,
        timestamp: 0
    )

    let bands: [Double]
    let rms: Double
    let peak: Double
    let beat: Double
    let timestamp: Double
}

final class AudioVisualizerEngine {
    static let shared = AudioVisualizerEngine()

    private let windowSize = 1024
    private let analysisHop = 512
    private let bandCount = AudioVisualizerSnapshot.bandCount
    private var lock = os_unfair_lock_s()
    private var active = false
    private var sampleRate = 44_100.0
    private var ring = [Double](repeating: 0, count: 1024)
    private var window: [Double]
    private var bandFrequencies: [Double]
    private var writeIndex = 0
    private var hasWindow = false
    private var samplesSinceAnalysis = 0
    private var bands = [Double](repeating: 0, count: AudioVisualizerSnapshot.bandCount)
    private var rms = 0.0
    private var peak = 0.0
    private var beat = 0.0
    private var bassFloor = 0.05
    private var lastBeatAt = 0.0
    private var timestamp = 0.0

    private init() {
        let size = 1024
        let initialSampleRate = 44_100.0
        window = (0..<size).map { i in
            0.5 - 0.5 * cos((2.0 * Double.pi * Double(i)) / Double(size - 1))
        }
        bandFrequencies = Self.makeBandFrequencies(count: AudioVisualizerSnapshot.bandCount, sampleRate: initialSampleRate)
    }

    var isActive: Bool {
        os_unfair_lock_lock(&lock)
        let value = active
        os_unfair_lock_unlock(&lock)
        return value
    }

    func setActive(_ enabled: Bool) {
        os_unfair_lock_lock(&lock)
        active = enabled
        if !enabled {
            bands = [Double](repeating: 0, count: bandCount)
            rms = 0
            peak = 0
            beat = 0
        }
        os_unfair_lock_unlock(&lock)
    }

    func snapshot() -> AudioVisualizerSnapshot {
        os_unfair_lock_lock(&lock)
        let snapshot = AudioVisualizerSnapshot(
            bands: bands,
            rms: rms,
            peak: peak,
            beat: beat,
            timestamp: timestamp
        )
        os_unfair_lock_unlock(&lock)
        return snapshot
    }

    func ingest(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frames: Int, sampleRate incomingSampleRate: Double) {
        guard frames > 0 else { return }
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard active else { return }

        if incomingSampleRate > 0, abs(incomingSampleRate - sampleRate) > 1 {
            sampleRate = incomingSampleRate
            bandFrequencies = Self.makeBandFrequencies(count: bandCount, sampleRate: sampleRate)
        }

        var sumSquares = 0.0
        var instantPeak = 0.0
        var count = 0

        func append(_ sample: Double) {
            let clipped = max(-1.0, min(1.0, sample))
            ring[writeIndex] = clipped
            writeIndex = (writeIndex + 1) % windowSize
            if writeIndex == 0 { hasWindow = true }
            let absSample = abs(clipped)
            instantPeak = max(instantPeak, absSample)
            sumSquares += clipped * clipped
            count += 1
        }

        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        if abl.count >= 2 {
            var frameCount = frames
            for buffer in abl {
                frameCount = min(frameCount, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
            }
            for frame in 0..<frameCount {
                var mixed = 0.0
                var channelCount = 0
                for buffer in abl {
                    guard let raw = buffer.mData else { continue }
                    mixed += Double(raw.assumingMemoryBound(to: Float.self)[frame])
                    channelCount += 1
                }
                if channelCount > 0 {
                    append(mixed / Double(channelCount))
                }
            }
        } else if abl.count == 1 {
            let buffer = abl[0]
            guard let raw = buffer.mData else { return }
            let channelCount = max(1, Int(buffer.mNumberChannels))
            let samples = raw.assumingMemoryBound(to: Float.self)
            let totalSamples = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let frameCount = min(frames, totalSamples / channelCount)
            for frame in 0..<frameCount {
                var mixed = 0.0
                let base = frame * channelCount
                for channel in 0..<channelCount {
                    mixed += Double(samples[base + channel])
                }
                append(mixed / Double(channelCount))
            }
        }

        guard count > 0 else { return }
        let instantRMS = sqrt(sumSquares / Double(count))
        rms = rms * 0.78 + instantRMS * 0.22
        peak = max(instantPeak, peak * 0.88)
        samplesSinceAnalysis += count
        if hasWindow, samplesSinceAnalysis >= analysisHop {
            samplesSinceAnalysis = 0
            analyzeLocked()
        }
    }

    private func analyzeLocked() {
        let now = ProcessInfo.processInfo.systemUptime
        for band in 0..<bandCount {
            let frequency = bandFrequencies[band]
            let omega = (2.0 * Double.pi * frequency) / sampleRate
            let coefficient = 2.0 * cos(omega)
            var q1 = 0.0
            var q2 = 0.0

            for i in 0..<windowSize {
                let index = (writeIndex + i) % windowSize
                let sample = ring[index] * window[i]
                let q0 = coefficient * q1 - q2 + sample
                q2 = q1
                q1 = q0
            }

            let power = max(q1 * q1 + q2 * q2 - coefficient * q1 * q2, 1.0e-12)
            let db = 10.0 * log10(power / Double(windowSize))
            let normalized = max(0.0, min(1.0, (db + 72.0) / 56.0))
            let shaped = pow(normalized, 0.58)
            let smoothing = shaped > bands[band] ? 0.48 : 0.16
            bands[band] += (shaped - bands[band]) * smoothing
        }

        let bassValues = zip(bands, bandFrequencies).filter { $0.1 <= 180 }.map(\.0)
        let bass = bassValues.isEmpty ? bands.prefix(6).reduce(0, +) / 6.0 : bassValues.reduce(0, +) / Double(bassValues.count)
        bassFloor = max(0.025, bassFloor * 0.96 + bass * 0.04)
        if bass > max(0.16, bassFloor * 1.55), rms > 0.025, now - lastBeatAt > 0.22 {
            beat = 1
            lastBeatAt = now
        } else {
            beat *= 0.86
        }
        timestamp = now
    }

    private static func makeBandFrequencies(count: Int, sampleRate: Double) -> [Double] {
        let low = 45.0
        let high = min(16_000.0, sampleRate * 0.45)
        return (0..<count).map { index in
            let t = Double(index) / Double(max(1, count - 1))
            return low * pow(high / low, t)
        }
    }
}

// Global 10-band EQ through MTAudioProcessingTap.
// Disabled by default; no tap is attached unless an effect or the visualizer is active.
final class EqualizerEngine {
    static let shared = EqualizerEngine()

    // ISO-ish band centre frequencies (Hz)
    static let frequencies: [Double] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let bandCount = frequencies.count
    static let range: ClosedRange<Double> = -12.0...12.0

    private var lock = os_unfair_lock_s()
    private(set) var gains = [Double](repeating: 0, count: bandCount)   // dB
    // Bumped when running taps need fresh coefficients.
    private(set) var generation: UInt64 = 0

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: "equalizerEnabled") }

    // Cached effect flags, read on the audio thread.
    private(set) var eqEnabled = UserDefaults.standard.bool(forKey: "equalizerEnabled")
    private(set) var monoEnabled = UserDefaults.standard.bool(forKey: "monoAudio")
    private(set) var spatialEnabled = UserDefaults.standard.bool(forKey: "spatialWidener")
    private(set) var spatialAmount = (UserDefaults.standard.object(forKey: "spatialWidenerAmount") as? Double) ?? 0.65
    private(set) var spatialEnhanced = (UserDefaults.standard.string(forKey: "spatialWidenerMode") ?? "enhanced") == "enhanced"

    // True when any DSP effect needs the tap.
    var isAnyEffectActive: Bool {
        refreshEffectFlags()
        return eqEnabled || monoEnabled || spatialEnabled
    }

    // Refresh toggles from defaults; call after a setting changes.
    func refreshEffectFlags() {
        let eq = UserDefaults.standard.bool(forKey: "equalizerEnabled")
        let mono = UserDefaults.standard.bool(forKey: "monoAudio")
        let spatial = UserDefaults.standard.bool(forKey: "spatialWidener")
        let amount = (UserDefaults.standard.object(forKey: "spatialWidenerAmount") as? Double) ?? 0.65
        let enhanced = (UserDefaults.standard.string(forKey: "spatialWidenerMode") ?? "enhanced") == "enhanced"
        os_unfair_lock_lock(&lock)
        if eq != eqEnabled || mono != monoEnabled || spatial != spatialEnabled || amount != spatialAmount || enhanced != spatialEnhanced {
            eqEnabled = eq; monoEnabled = mono; spatialEnabled = spatial; spatialAmount = amount; spatialEnhanced = enhanced
            generation &+= 1
        }
        os_unfair_lock_unlock(&lock)
    }

    init() { loadGains() }

    // MARK: - Gains

    func gain(band: Int) -> Double {
        guard band >= 0, band < Self.bandCount else { return 0 }
        return gains[band]
    }

    func setGain(_ value: Double, band: Int) {
        guard band >= 0, band < Self.bandCount else { return }
        os_unfair_lock_lock(&lock)
        gains[band] = min(Self.range.upperBound, max(Self.range.lowerBound, value))
        UserDefaults.standard.set(gains[band], forKey: "eqBand\(band)")
        generation &+= 1
        os_unfair_lock_unlock(&lock)
    }

    func setAll(_ values: [Double]) {
        os_unfair_lock_lock(&lock)
        for i in 0..<Self.bandCount where i < values.count {
            gains[i] = min(Self.range.upperBound, max(Self.range.lowerBound, values[i]))
            UserDefaults.standard.set(gains[i], forKey: "eqBand\(i)")
        }
        generation &+= 1
        os_unfair_lock_unlock(&lock)
    }

    func reset() { setAll([Double](repeating: 0, count: Self.bandCount)) }

    private func loadGains() {
        for i in 0..<Self.bandCount {
            gains[i] = UserDefaults.standard.object(forKey: "eqBand\(i)") as? Double ?? 0
        }
    }

    // Tap snapshot for coefficients and effect state.
    func snapshot() -> (gains: [Double], generation: UInt64, eqEnabled: Bool, mono: Bool, spatial: Bool, spatialAmount: Double, enhanced: Bool) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return (gains, generation, eqEnabled, monoEnabled, spatialEnabled, spatialAmount, spatialEnhanced)
    }

    // MARK: - Tap creation

    // Fresh tap for one AVPlayerItem.
    func makeTap(bypassEffects: Bool = false) -> MTAudioProcessingTap? {
        let context = TapContext(bypassEffects: bypassEffects)
        let clientInfo = UnsafeMutableRawPointer(Unmanaged.passRetained(context).toOpaque())
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: clientInfo,
            init: tapInit,
            finalize: tapFinalize,
            prepare: tapPrepare,
            unprepare: tapUnprepare,
            process: tapProcess
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                                kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        guard status == noErr, let tap else {
            // Creation failed; balance the retain passed to clientInfo.
            Unmanaged<TapContext>.fromOpaque(clientInfo).release()
            return nil
        }
        return tap
    }
}

// MARK: - Per-tap DSP state

// Biquad coefficients and state for one AVPlayerItem tap.
private final class TapContext {
    let bypassEffects: Bool
    var sampleRate: Double = 44_100
    var channels: Int = 2
    var generation: UInt64 = .max   // force first compute

    // Cached effect flags.
    private var eqEnabled = false
    private var mono = false
    private var spatial = false
    private var spatialAmount = 0.65
    private var spatialEnhanced = false

    // Enhanced widener: one-pole high-pass on the side channel (keeps bass centred).
    private var sideHPAlpha: Float = 0
    private var sideHPPrevIn: Float = 0
    private var sideHPPrevOut: Float = 0

    // coefficients per band: b0, b1, b2, a1, a2  (a0 normalized to 1)
    private var coeffs = [[Double]](repeating: [1, 0, 0, 0, 0], count: EqualizerEngine.bandCount)
    // direct-form-I state per channel per band: x1, x2, y1, y2
    private var state: [[[Double]]] = []

    init(bypassEffects: Bool = false) {
        self.bypassEffects = bypassEffects
    }

    func prepare(sampleRate: Double, channels: Int) {
        self.sampleRate = sampleRate > 0 ? sampleRate : 44_100
        self.channels = max(1, channels)
        state = Array(repeating: Array(repeating: [0, 0, 0, 0], count: EqualizerEngine.bandCount),
                      count: self.channels)
        // One-pole high-pass coefficient (~300 Hz) for the enhanced widener's side channel.
        let rc = 1.0 / (2.0 * Double.pi * 300.0)
        let dt = 1.0 / self.sampleRate
        sideHPAlpha = Float(rc / (rc + dt))
        sideHPPrevIn = 0
        sideHPPrevOut = 0
        generation = .max
        recomputeIfNeeded()
    }

    func unprepare() { state = [] }

    // RBJ peaking-EQ biquad per band from the current gains.
    private func recomputeIfNeeded() {
        // racy read is fine for change detection; only lock when it actually changed
        guard EqualizerEngine.shared.generation != generation else { return }
        let snap = EqualizerEngine.shared.snapshot()
        generation = snap.generation
        eqEnabled = !bypassEffects && snap.eqEnabled
        mono = !bypassEffects && snap.mono
        spatial = !bypassEffects && snap.spatial
        spatialAmount = snap.spatialAmount
        spatialEnhanced = snap.enhanced
        let q = 1.4
        for b in 0..<EqualizerEngine.bandCount {
            let f0 = EqualizerEngine.frequencies[b]
            let gainDB = snap.gains[b]
            let A = pow(10.0, gainDB / 40.0)
            let w0 = 2.0 * Double.pi * f0 / sampleRate
            let cosw0 = cos(w0)
            let alpha = sin(w0) / (2.0 * q)

            let b0 = 1 + alpha * A
            let b1 = -2 * cosw0
            let b2 = 1 - alpha * A
            let a0 = 1 + alpha / A
            let a1 = -2 * cosw0
            let a2 = 1 - alpha / A
            coeffs[b] = [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]
        }
    }

    // Process source buffers in place.
    func process(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        recomputeIfNeeded()
        guard frames > 0, !state.isEmpty else { return }
        AudioVisualizerEngine.shared.ingest(bufferList, frames: frames, sampleRate: sampleRate)

        let abl = UnsafeMutableAudioBufferListPointer(bufferList)

        // 1) Graphic EQ per channel.
        if eqEnabled {
            for (ch, buffer) in abl.enumerated() {
                guard ch < channels, let raw = buffer.mData else { continue }
                let n = min(frames, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
                let samples = raw.assumingMemoryBound(to: Float.self)

                for i in 0..<n {
                    var x = Double(samples[i])
                    // Cascade bands without per-sample allocation.
                    for b in 0..<EqualizerEngine.bandCount {
                        let x1 = state[ch][b][0], x2 = state[ch][b][1]
                        let y1 = state[ch][b][2], y2 = state[ch][b][3]
                        let y = coeffs[b][0] * x + coeffs[b][1] * x1 + coeffs[b][2] * x2
                                - coeffs[b][3] * y1 - coeffs[b][4] * y2
                        state[ch][b][1] = x1; state[ch][b][0] = x
                        state[ch][b][3] = y1; state[ch][b][2] = y
                        x = y
                    }
                    samples[i] = Float(x)
                }
            }
        }

        // 2) Stereo image. Mono wins over widening; handle both buffer layouts.
        guard mono || spatial else { return }

        let lPtr: UnsafeMutablePointer<Float>
        let rPtr: UnsafeMutablePointer<Float>
        let step: Int   // float distance from one frame's L to the next
        let n: Int      // frame count

        if abl.count >= 2, let lRaw = abl[0].mData, let rRaw = abl[1].mData {
            // Non-interleaved: channel 0 = L, channel 1 = R, contiguous.
            lPtr = lRaw.assumingMemoryBound(to: Float.self)
            rPtr = rRaw.assumingMemoryBound(to: Float.self)
            step = 1
            let nL = Int(abl[0].mDataByteSize) / MemoryLayout<Float>.size
            let nR = Int(abl[1].mDataByteSize) / MemoryLayout<Float>.size
            n = min(frames, nL, nR)
        } else if abl.count == 1, abl[0].mNumberChannels >= 2, let raw = abl[0].mData {
            // Interleaved: [L, R, ...].
            let base = raw.assumingMemoryBound(to: Float.self)
            let ch = Int(abl[0].mNumberChannels)
            lPtr = base
            rPtr = base + 1
            step = ch
            let total = Int(abl[0].mDataByteSize) / MemoryLayout<Float>.size
            n = min(frames, total / ch)
        } else {
            return   // mono source or unexpected layout: nothing to downmix
        }

        if mono {
            for i in 0..<n {
                let j = i * step
                let m = (lPtr[j] + rPtr[j]) * 0.5
                lPtr[j] = m
                rPtr[j] = m
            }
        } else if spatialEnhanced {
            // Widen high-frequency side content; keep bass centred.
            let w = Float(1.0 + max(0.0, min(1.5, spatialAmount)))
            let a = sideHPAlpha
            var prevIn = sideHPPrevIn
            var prevOut = sideHPPrevOut
            for i in 0..<n {
                let j = i * step
                let l = lPtr[j], r = rPtr[j]
                let mid = (l + r) * 0.5
                let side = (l - r) * 0.5
                // one-pole high-pass; only the high band gets the extra width.
                let hp = a * (prevOut + side - prevIn)
                prevIn = side
                prevOut = hp
                let wideSide = side + hp * (w - 1)
                lPtr[j] = Self.softClip(mid + wideSide)
                rPtr[j] = Self.softClip(mid - wideSide)
            }
            sideHPPrevIn = prevIn
            sideHPPrevOut = prevOut
        } else {
            // Basic: flat mid/side gain with hard clamp.
            let w = Float(1.0 + max(0.0, min(1.5, spatialAmount)))
            for i in 0..<n {
                let j = i * step
                let l = lPtr[j], r = rPtr[j]
                let mid = (l + r) * 0.5
                let side = (l - r) * 0.5 * w
                lPtr[j] = max(-1.0, min(1.0, mid + side))
                rPtr[j] = max(-1.0, min(1.0, mid - side))
            }
        }
    }

    // Linear to the knee, then soft tanh rounding.
    @inline(__always)
    private static func softClip(_ x: Float) -> Float {
        let knee: Float = 0.7
        let ax = abs(x)
        if ax <= knee { return x }
        let shaped = knee + (1 - knee) * tanhf((ax - knee) / (1 - knee))
        return x < 0 ? -shaped : shaped
    }
}

// MARK: - C tap callbacks (must be non-capturing)

private func tapInit(_ tap: MTAudioProcessingTap,
                     _ clientInfo: UnsafeMutableRawPointer?,
                     _ tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>) {
    tapStorageOut.pointee = clientInfo
}

private func tapFinalize(_ tap: MTAudioProcessingTap) {
    Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}

private func tapPrepare(_ tap: MTAudioProcessingTap,
                        _ maxFrames: CMItemCount,
                        _ processingFormat: UnsafePointer<AudioStreamBasicDescription>) {
    let ctx = Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    let asbd = processingFormat.pointee
    ctx.prepare(sampleRate: asbd.mSampleRate, channels: Int(asbd.mChannelsPerFrame))
}

private func tapUnprepare(_ tap: MTAudioProcessingTap) {
    let ctx = Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    ctx.unprepare()
}

private func tapProcess(_ tap: MTAudioProcessingTap,
                        _ numberFrames: CMItemCount,
                        _ flags: MTAudioProcessingTapFlags,
                        _ bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
                        _ numberFramesOut: UnsafeMutablePointer<CMItemCount>,
                        _ flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>) {
    let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut,
                                                    flagsOut, nil, numberFramesOut)
    guard status == noErr else { return }
    let ctx = Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    ctx.process(bufferListInOut, frames: numberFramesOut.pointee)
}
