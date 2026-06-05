import Foundation
import AVFoundation
import os

extension Notification.Name {
    // posted when the EQ is enabled/disabled so the player re-attaches/removes the tap
    static let equalizerToggled = Notification.Name("EqualizerToggled")
}

// Global 10-band graphic equalizer applied to AVPlayer audio through an
// MTAudioProcessingTap. Each playing AVPlayerItem gets a tap whose context
// reads the shared band gains and applies a cascade of peaking biquad filters.
//
// Gains live in UserDefaults ("eqBand0"…"eqBand9") and "equalizerEnabled".
// The EQ is OFF by default and no tap is attached unless enabled, so it can
// never affect normal playback.
final class EqualizerEngine {
    static let shared = EqualizerEngine()

    // ISO-ish band centre frequencies (Hz)
    static let frequencies: [Double] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let bandCount = frequencies.count
    static let range: ClosedRange<Double> = -12.0...12.0

    private var lock = os_unfair_lock_s()
    private(set) var gains = [Double](repeating: 0, count: bandCount)   // dB
    // bumped whenever gains change, so a running tap knows to recompute coeffs
    private(set) var generation: UInt64 = 0

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: "equalizerEnabled") }

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

    // snapshot used by a tap when (re)computing coefficients
    func snapshot() -> (gains: [Double], generation: UInt64) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return (gains, generation)
    }

    // MARK: - Tap creation

    // builds a fresh MTAudioProcessingTap for one AVPlayerItem.
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
            // creation failed → balance the retain we handed to clientInfo
            Unmanaged<TapContext>.fromOpaque(clientInfo).release()
            return nil
        }
        return tap
    }
}

// MARK: - Per-tap DSP state

// holds biquad coefficients + filter state for one tap (one AVPlayerItem).
private final class TapContext {
    var sampleRate: Double = 44_100
    var channels: Int = 2
    var generation: UInt64 = .max   // force first compute

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

    // processes the source audio buffers in place (non-interleaved Float32).
    func process(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        recomputeIfNeeded()
        guard frames > 0, !state.isEmpty else { return }

        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        for (ch, buffer) in abl.enumerated() {
            guard ch < channels, let raw = buffer.mData else { continue }
            let n = min(frames, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
            let samples = raw.assumingMemoryBound(to: Float.self)

            for i in 0..<n {
                var x = Double(samples[i])
                // cascade the band biquads (in-place index mutation → no per-sample
                // array copies/allocations on the audio thread)
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
