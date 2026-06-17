import Foundation
import AVFoundation
import os

// Bass Swap: high-pass the incoming track until it takes over.
// Tap ids keep primed and active incoming tracks separate.
final class AutoMixBassSwap {
    static let shared = AutoMixBassSwap()

    static let bypassHz: Double = 20          // effectively transparent
    static let maxCutoffHz: Double = 200      // strongest low-end roll-off

    private var lock = os_unfair_lock_s()
    private var nextID: UInt64 = 1
    private var activeID: UInt64 = 0
    private var cutoff: Double = bypassHz
    private var generation: UInt64 = 0

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "automixBassSwap") as? Bool ?? true
    }

    // Reserve an id for an incoming track's tap (assigned when the tap is created).
    func reserveID() -> UInt64 {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        let id = nextID; nextID += 1; return id
    }

    // Make `id` the active blend and reset its low-cut to transparent.
    func activate(_ id: UInt64) {
        guard id != 0 else { return }
        os_unfair_lock_lock(&lock)
        activeID = id; cutoff = Self.bypassHz; generation &+= 1
        os_unfair_lock_unlock(&lock)
    }

    // Ignored unless `id` is the active blend.
    func setCutoff(_ hz: Double, id: UInt64) {
        os_unfair_lock_lock(&lock)
        if id == activeID {
            cutoff = min(Self.maxCutoffHz, max(Self.bypassHz, hz)); generation &+= 1
        }
        os_unfair_lock_unlock(&lock)
    }

    // End the blend for `id` (returns to transparent, no track is filtered).
    func deactivate(_ id: UInt64) {
        os_unfair_lock_lock(&lock)
        if id == activeID { activeID = 0; cutoff = Self.bypassHz; generation &+= 1 }
        os_unfair_lock_unlock(&lock)
    }

    fileprivate func snapshot() -> (active: UInt64, cutoff: Double, generation: UInt64) {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        return (activeID, cutoff, generation)
    }

    // Build a tap for one incoming AVPlayerItem, tagged with `id`.
    func makeTap(id: UInt64) -> MTAudioProcessingTap? {
        let context = BassTapContext(id: id)
        let clientInfo = UnsafeMutableRawPointer(Unmanaged.passRetained(context).toOpaque())
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: clientInfo,
            init: bassTapInit,
            finalize: bassTapFinalize,
            prepare: bassTapPrepare,
            unprepare: bassTapUnprepare,
            process: bassTapProcess
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                                kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        guard status == noErr, let tap else {
            Unmanaged<BassTapContext>.fromOpaque(clientInfo).release()
            return nil
        }
        return tap
    }
}

// MARK: - Per-tap DSP state

private final class BassTapContext {
    let id: UInt64
    var sampleRate: Double = 44_100
    var channels: Int = 2
    var generation: UInt64 = .max

    // 2nd-order Butterworth high-pass: b0,b1,b2,a1,a2 (a0 normalised to 1)
    private var coeffs: [Double] = [1, 0, 0, 0, 0]
    private var bypass = true
    // direct-form-I state per channel: x1, x2, y1, y2
    private var state: [[Double]] = []

    init(id: UInt64) { self.id = id }

    func prepare(sampleRate: Double, channels: Int) {
        self.sampleRate = sampleRate > 0 ? sampleRate : 44_100
        self.channels = max(1, channels)
        state = Array(repeating: [0, 0, 0, 0], count: self.channels)
        generation = .max
    }

    func unprepare() { state = [] }

    private func recomputeIfNeeded() {
        let snap = AutoMixBassSwap.shared.snapshot()
        guard snap.generation != generation else { return }
        generation = snap.generation
        // Only filter while this tap is the active blend's incoming and the cutoff
        // is meaningfully above the bypass floor.
        guard snap.active == id, snap.cutoff > AutoMixBassSwap.bypassHz + 1 else {
            bypass = true
            return
        }
        bypass = false
        let f0 = min(sampleRate * 0.45, max(20, snap.cutoff))
        let q = 0.707
        let w0 = 2.0 * Double.pi * f0 / sampleRate
        let cosw0 = cos(w0)
        let alpha = sin(w0) / (2.0 * q)
        let b0 = (1 + cosw0) / 2
        let b1 = -(1 + cosw0)
        let b2 = (1 + cosw0) / 2
        let a0 = 1 + alpha
        let a1 = -2 * cosw0
        let a2 = 1 - alpha
        coeffs = [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]
    }

    func process(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        recomputeIfNeeded()
        guard !bypass, frames > 0, !state.isEmpty else { return }
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        let b0 = coeffs[0], b1 = coeffs[1], b2 = coeffs[2], a1 = coeffs[3], a2 = coeffs[4]
        for (ch, buffer) in abl.enumerated() {
            guard ch < channels, let raw = buffer.mData else { continue }
            let n = min(frames, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
            let samples = raw.assumingMemoryBound(to: Float.self)
            var x1 = state[ch][0], x2 = state[ch][1], y1 = state[ch][2], y2 = state[ch][3]
            for i in 0..<n {
                let x = Double(samples[i])
                let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
                x2 = x1; x1 = x
                y2 = y1; y1 = y
                samples[i] = Float(y)
            }
            state[ch][0] = x1; state[ch][1] = x2; state[ch][2] = y1; state[ch][3] = y2
        }
    }
}

// MARK: - C tap callbacks (must be non-capturing)

private func bassTapInit(_ tap: MTAudioProcessingTap,
                         _ clientInfo: UnsafeMutableRawPointer?,
                         _ tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>) {
    tapStorageOut.pointee = clientInfo
}

private func bassTapFinalize(_ tap: MTAudioProcessingTap) {
    Unmanaged<BassTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}

private func bassTapPrepare(_ tap: MTAudioProcessingTap,
                            _ maxFrames: CMItemCount,
                            _ processingFormat: UnsafePointer<AudioStreamBasicDescription>) {
    let ctx = Unmanaged<BassTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    let asbd = processingFormat.pointee
    ctx.prepare(sampleRate: asbd.mSampleRate, channels: Int(asbd.mChannelsPerFrame))
}

private func bassTapUnprepare(_ tap: MTAudioProcessingTap) {
    let ctx = Unmanaged<BassTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    ctx.unprepare()
}

private func bassTapProcess(_ tap: MTAudioProcessingTap,
                            _ numberFrames: CMItemCount,
                            _ flags: MTAudioProcessingTapFlags,
                            _ bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
                            _ numberFramesOut: UnsafeMutablePointer<CMItemCount>,
                            _ flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>) {
    let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut,
                                                    flagsOut, nil, numberFramesOut)
    guard status == noErr else { return }
    let ctx = Unmanaged<BassTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    ctx.process(bufferListInOut, frames: numberFramesOut.pointee)
}
