import Foundation
import AVFoundation
import os

extension Notification.Name {
    // Player re-attaches/removes taps when this fires.
    static let equalizerToggled = Notification.Name("EqualizerToggled")
}

// Global 10-band EQ through MTAudioProcessingTap.
// Disabled by default; no tap is attached unless an effect is active.
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
        os_unfair_lock_lock(&lock)
        if eq != eqEnabled || mono != monoEnabled || spatial != spatialEnabled || amount != spatialAmount {
            eqEnabled = eq; monoEnabled = mono; spatialEnabled = spatial; spatialAmount = amount
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
    func snapshot() -> (gains: [Double], generation: UInt64, eqEnabled: Bool, mono: Bool, spatial: Bool, spatialAmount: Double) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return (gains, generation, eqEnabled, monoEnabled, spatialEnabled, spatialAmount)
    }

    // MARK: - Tap creation

    // Fresh tap for one AVPlayerItem.
    func makeTap() -> MTAudioProcessingTap? {
        let context = TapContext()
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
    var sampleRate: Double = 44_100
    var channels: Int = 2
    var generation: UInt64 = .max   // force first compute

    // Cached effect flags.
    private var eqEnabled = false
    private var mono = false
    private var spatial = false
    private var spatialAmount = 0.65

    // coefficients per band: b0, b1, b2, a1, a2  (a0 normalized to 1)
    private var coeffs = [[Double]](repeating: [1, 0, 0, 0, 0], count: EqualizerEngine.bandCount)
    // direct-form-I state per channel per band: x1, x2, y1, y2
    private var state: [[[Double]]] = []

    func prepare(sampleRate: Double, channels: Int) {
        self.sampleRate = sampleRate > 0 ? sampleRate : 44_100
        self.channels = max(1, channels)
        state = Array(repeating: Array(repeating: [0, 0, 0, 0], count: EqualizerEngine.bandCount),
                      count: self.channels)
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
        eqEnabled = snap.eqEnabled
        mono = snap.mono
        spatial = snap.spatial
        spatialAmount = snap.spatialAmount
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

        // 2) Stereo image; mono wins over widening.
        guard abl.count >= 2, (mono || spatial),
              let lRaw = abl[0].mData, let rRaw = abl[1].mData else { return }
        let lSamples = lRaw.assumingMemoryBound(to: Float.self)
        let rSamples = rRaw.assumingMemoryBound(to: Float.self)
        let nL = min(frames, Int(abl[0].mDataByteSize) / MemoryLayout<Float>.size)
        let nR = min(frames, Int(abl[1].mDataByteSize) / MemoryLayout<Float>.size)
        let n = min(nL, nR)
        if mono {
            for i in 0..<n {
                let m = (lSamples[i] + rSamples[i]) * 0.5
                lSamples[i] = m
                rSamples[i] = m
            }
        } else {
            // Mid/side widen; clamp so widening cannot clip.
            let w = Float(1.0 + max(0.0, min(1.0, spatialAmount)))
            for i in 0..<n {
                let l = lSamples[i], r = rSamples[i]
                let mid = (l + r) * 0.5
                let side = (l - r) * 0.5 * w
                lSamples[i] = max(-1.0, min(1.0, mid + side))
                rSamples[i] = max(-1.0, min(1.0, mid - side))
            }
        }
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
