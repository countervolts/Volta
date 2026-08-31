import Foundation
import AVFoundation
import Accelerate
import os

extension Notification.Name {
    // Player re-attaches/removes taps when this fires.
    static let equalizerToggled = Notification.Name("EqualizerToggled")
}

struct AudioVisualizerSnapshot: Sendable {
    static let bandCount = 48
    static let waveformCount = 192
    static let silent = AudioVisualizerSnapshot(
        bands: [Double](repeating: 0, count: bandCount),
        waveform: [Double](repeating: 0, count: waveformCount),
        rms: 0,
        peak: 0,
        beat: 0,
        timestamp: 0
    )

    let bands: [Double]
    let waveform: [Double]
    let rms: Double
    let peak: Double
    let beat: Double
    let timestamp: Double
}

final class AudioVisualizerEngine {
    static let shared = AudioVisualizerEngine()

    private let windowSize = 1024
    private let analysisHop = 512
    private let fftLog2n = vDSP_Length(10)
    private let bandCount = AudioVisualizerSnapshot.bandCount
    private var lock = os_unfair_lock_s()
    private var active = false
    private var sampleRate = 44_100.0
    private var bandFrequencySampleRate = 44_100.0
    private var ring = [Double](repeating: 0, count: 1024)
    private var window: [Double]
    private var bandFrequencies: [Double]
    private var fftSetup: FFTSetup?
    private var fftReal = [Float](repeating: 0, count: 512)
    private var fftImaginary = [Float](repeating: 0, count: 512)
    private var writeIndex = 0
    private var hasWindow = false
    private var samplesSinceAnalysis = 0
    private var bands = [Double](repeating: 0, count: AudioVisualizerSnapshot.bandCount)
    private var waveform = [Double](repeating: 0, count: AudioVisualizerSnapshot.waveformCount)
    private var rms = 0.0
    private var peak = 0.0
    private var beat = 0.0
    private var bassFloor = 0.05
    private var lastBeatAt = 0.0
    private var timestamp = 0.0

    private init() {
        let size = windowSize
        let initialSampleRate = 44_100.0
        window = (0..<size).map { i in
            0.5 - 0.5 * cos((2.0 * Double.pi * Double(i)) / Double(size - 1))
        }
        bandFrequencies = Self.makeBandFrequencies(count: AudioVisualizerSnapshot.bandCount, sampleRate: initialSampleRate)
        fftSetup = vDSP_create_fftsetup(fftLog2n, FFTRadix(kFFTRadix2))
    }

    deinit {
        if let fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
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
            waveform = [Double](repeating: 0, count: AudioVisualizerSnapshot.waveformCount)
            rms = 0
            peak = 0
            beat = 0
        }
        os_unfair_lock_unlock(&lock)
    }

    func snapshot() -> AudioVisualizerSnapshot {
        os_unfair_lock_lock(&lock)
        if active, hasWindow, samplesSinceAnalysis >= analysisHop {
            samplesSinceAnalysis = 0
            if abs(sampleRate - bandFrequencySampleRate) > 1 {
                bandFrequencies = Self.makeBandFrequencies(count: bandCount, sampleRate: sampleRate)
                bandFrequencySampleRate = sampleRate
            }
            analyzeLocked()
        }
        let snapshot = AudioVisualizerSnapshot(
            bands: bands,
            waveform: waveform,
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
        // Visualization is best-effort. Never make the real-time audio callback
        // wait for a UI snapshot or FFT analysis.
        guard os_unfair_lock_trylock(&lock) else { return }
        defer { os_unfair_lock_unlock(&lock) }
        guard active else { return }

        if incomingSampleRate > 0, abs(incomingSampleRate - sampleRate) > 1 {
            sampleRate = incomingSampleRate
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
    }

    private func analyzeLocked() {
        let now = ProcessInfo.processInfo.systemUptime
        guard let fftSetup else { return }

        // vDSP expects a real signal packed as the even samples in the real
        // buffer and odd samples in the imaginary buffer. Window it first to
        // keep leakage from neighbouring frequencies out of the spectrum.
        fftReal.withUnsafeMutableBufferPointer { realBuffer in
            fftImaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                guard let real = realBuffer.baseAddress,
                      let imaginary = imaginaryBuffer.baseAddress else { return }

                for complexIndex in 0..<(windowSize / 2) {
                    let sampleIndex = complexIndex * 2
                    real[complexIndex] = Float(ring[(writeIndex + sampleIndex) % windowSize] * window[sampleIndex])
                    imaginary[complexIndex] = Float(ring[(writeIndex + sampleIndex + 1) % windowSize] * window[sampleIndex + 1])
                }

                var splitComplex = DSPSplitComplex(realp: real, imagp: imaginary)
                vDSP_fft_zrip(
                    fftSetup,
                    &splitComplex,
                    1,
                    fftLog2n,
                    FFTDirection(FFT_FORWARD)
                )
            }
        }

        for band in 0..<bandCount {
            let centerBin = min(
                (windowSize / 2) - 1,
                max(1, Int((bandFrequencies[band] / sampleRate) * Double(windowSize)))
            )
            let radius = max(1, min(6, Int(Double(centerBin) * 0.14)))
            let lowerBin = max(1, centerBin - radius)
            let upperBin = min((windowSize / 2) - 1, centerBin + radius)
            var power = 0.0

            for bin in lowerBin...upperBin {
                let real = Double(fftReal[bin])
                let imaginary = Double(fftImaginary[bin])
                power += real * real + imaginary * imaginary
            }

            let magnitude = sqrt(power / Double(upperBin - lowerBin + 1)) / (Double(windowSize) * 0.5)
            let db = 20.0 * log10(max(magnitude, 1.0e-7))
            let normalized = max(0.0, min(1.0, (db + 78.0) / 66.0))
            let shaped = pow(normalized, 0.58)
            let smoothing = shaped > bands[band] ? 0.48 : 0.16
            bands[band] += (shaped - bands[band]) * smoothing
        }

        for waveformIndex in waveform.indices {
            let sourceIndex = min(
                windowSize - 1,
                Int((Double(waveformIndex) + 0.5) * Double(windowSize) / Double(waveform.count))
            )
            waveform[waveformIndex] = ring[(writeIndex + sourceIndex) % windowSize]
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
enum EqualizerProcessingMode: String, CaseIterable, Identifiable, Sendable {
    case accurate
    case efficient
    case batterySaver

    static let defaultsKey = "equalizerProcessingMode"

    var id: String { rawValue }

    var minimumBandGainDB: Double {
        self == .batterySaver ? 0.75 : 1.0e-12
    }

    static func resolved(_ rawValue: String?) -> Self {
        Self(rawValue: rawValue ?? "") ?? .efficient
    }
}

final class EqualizerEngine {
    static let shared = EqualizerEngine()

    // ISO-ish band centre frequencies (Hz)
    static let frequencies: [Double] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let bandCount = frequencies.count
    static let range: ClosedRange<Double> = -12.0...12.0
    static let filterQ = 1.4

    private var lock = os_unfair_lock_s()
    private(set) var gains = [Double](repeating: 0, count: bandCount)   // dB
    private(set) var preampDB = 0.0
    // Bumped when running taps need a fresh, precomputed configuration.
    private(set) var generation: UInt64 = 0
    private var contexts: [WeakTapContext] = []

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: "equalizerEnabled") }

    // Cached effect flags, read on the audio thread.
    private(set) var eqEnabled = UserDefaults.standard.bool(forKey: "equalizerEnabled")
    private(set) var monoEnabled = UserDefaults.standard.bool(forKey: "monoAudio")
    private(set) var spatialEnabled = UserDefaults.standard.bool(forKey: "spatialWidener")
    private(set) var spatialAmount = (UserDefaults.standard.object(forKey: "spatialWidenerAmount") as? Double) ?? 0.65
    private(set) var spatialEnhanced = (UserDefaults.standard.string(forKey: "spatialWidenerMode") ?? "enhanced") == "enhanced"
    private(set) var processingMode = EqualizerProcessingMode.resolved(
        UserDefaults.standard.string(forKey: EqualizerProcessingMode.defaultsKey)
    )

    // True when any DSP effect needs the tap.
    var isAnyEffectActive: Bool {
        refreshEffectFlags()
        let settings = snapshot()
        return EqualizerBiquadDesigner.shouldProcess(
            gains: settings.gains,
            preampDB: settings.preampDB,
            enabled: settings.eqEnabled
        ) || settings.mono || settings.spatial
    }

    // Refresh toggles from defaults; call after a setting changes.
    func refreshEffectFlags() {
        let eq = UserDefaults.standard.bool(forKey: "equalizerEnabled")
        let mono = UserDefaults.standard.bool(forKey: "monoAudio")
        let spatial = UserDefaults.standard.bool(forKey: "spatialWidener")
        let amount = (UserDefaults.standard.object(forKey: "spatialWidenerAmount") as? Double) ?? 0.65
        let enhanced = (UserDefaults.standard.string(forKey: "spatialWidenerMode") ?? "enhanced") == "enhanced"
        var update: (EqualizerSettingsSnapshot, [TapContext])?
        os_unfair_lock_lock(&lock)
        if eq != eqEnabled || mono != monoEnabled || spatial != spatialEnabled || amount != spatialAmount || enhanced != spatialEnhanced {
            eqEnabled = eq; monoEnabled = mono; spatialEnabled = spatial; spatialAmount = amount; spatialEnhanced = enhanced
            generation &+= 1
            update = configurationUpdateLocked()
        }
        os_unfair_lock_unlock(&lock)
        if let update {
            update.1.forEach { $0.stage(update.0, coefficientsChanged: false) }
        }
    }

    func setProcessingMode(_ mode: EqualizerProcessingMode) {
        var update: (EqualizerSettingsSnapshot, [TapContext])?
        os_unfair_lock_lock(&lock)
        if processingMode != mode {
            processingMode = mode
            generation &+= 1
            update = configurationUpdateLocked()
        }
        os_unfair_lock_unlock(&lock)
        UserDefaults.standard.set(mode.rawValue, forKey: EqualizerProcessingMode.defaultsKey)
        if let update {
            update.1.forEach { $0.stage(update.0, coefficientsChanged: true) }
        }
    }

    init() { loadGains() }

    // MARK: - Gains

    func gain(band: Int) -> Double {
        guard band >= 0, band < Self.bandCount else { return 0 }
        return gains[band]
    }

    func setGain(_ value: Double, band: Int) {
        guard band >= 0, band < Self.bandCount else { return }
        let clamped = EqualizerBiquadDesigner.sanitizedGain(value)
        var update: (EqualizerSettingsSnapshot, [TapContext])?
        os_unfair_lock_lock(&lock)
        if gains[band] != clamped {
            gains[band] = clamped
            generation &+= 1
            update = configurationUpdateLocked()
        }
        os_unfair_lock_unlock(&lock)
        guard let update else { return }
        UserDefaults.standard.set(clamped, forKey: "eqBand\(band)")
        update.1.forEach { $0.stage(update.0, coefficientsChanged: true) }
    }

    func setAll(_ values: [Double], preampDB: Double = 0) {
        var persistedGains: [Double] = []
        let clampedPreamp = EqualizerBiquadDesigner.sanitizedPreampDB(preampDB)
        var coefficientsChanged = false
        var changed = false
        var update: (EqualizerSettingsSnapshot, [TapContext])?
        os_unfair_lock_lock(&lock)
        for i in 0..<Self.bandCount where i < values.count {
            let clamped = EqualizerBiquadDesigner.sanitizedGain(values[i])
            if gains[i] != clamped {
                gains[i] = clamped
                coefficientsChanged = true
                changed = true
            }
        }
        if self.preampDB != clampedPreamp {
            self.preampDB = clampedPreamp
            changed = true
        }
        if changed {
            generation &+= 1
            persistedGains = gains
            update = configurationUpdateLocked()
        }
        os_unfair_lock_unlock(&lock)
        guard let update else { return }
        for (index, gain) in persistedGains.enumerated() {
            UserDefaults.standard.set(gain, forKey: "eqBand\(index)")
        }
        UserDefaults.standard.set(clampedPreamp, forKey: "equalizerPreampDB")
        update.1.forEach { $0.stage(update.0, coefficientsChanged: coefficientsChanged) }
    }

    func reset() { setAll([Double](repeating: 0, count: Self.bandCount)) }

    private func loadGains() {
        for i in 0..<Self.bandCount {
            let stored = UserDefaults.standard.object(forKey: "eqBand\(i)") as? Double ?? 0
            gains[i] = EqualizerBiquadDesigner.sanitizedGain(stored)
        }
        let storedPreamp = UserDefaults.standard.object(forKey: "equalizerPreampDB") as? Double ?? 0
        preampDB = EqualizerBiquadDesigner.sanitizedPreampDB(storedPreamp)
    }

    fileprivate func snapshot() -> EqualizerSettingsSnapshot {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return snapshotLocked()
    }

    private func snapshotLocked() -> EqualizerSettingsSnapshot {
        EqualizerSettingsSnapshot(
            gains: gains,
            preampDB: preampDB,
            generation: generation,
            eqEnabled: eqEnabled,
            mono: monoEnabled,
            spatial: spatialEnabled,
            spatialAmount: spatialAmount,
            enhanced: spatialEnhanced,
            processingMode: processingMode
        )
    }

    private func configurationUpdateLocked() -> (EqualizerSettingsSnapshot, [TapContext]) {
        contexts.removeAll { $0.value == nil }
        return (snapshotLocked(), contexts.compactMap(\.value))
    }

    fileprivate func register(_ context: TapContext) {
        os_unfair_lock_lock(&lock)
        contexts.removeAll { $0.value == nil }
        contexts.append(WeakTapContext(context))
        let settings = snapshotLocked()
        os_unfair_lock_unlock(&lock)
        context.stage(settings, coefficientsChanged: true)
    }

    // MARK: - Tap creation

    // Fresh tap for one AVPlayerItem.
    func makeTap(
        bypassEffects: Bool = false,
        autoMixChannelID: UInt64 = 0
    ) -> MTAudioProcessingTap? {
        let context = TapContext(
            bypassEffects: bypassEffects,
            autoMixChannelID: autoMixChannelID
        )
        register(context)
        AutoMixTransitionDSP.shared.register(
            channelID: autoMixChannelID,
            context: context
        )
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

fileprivate struct EqualizerSettingsSnapshot {
    let gains: [Double]
    let preampDB: Double
    let generation: UInt64
    let eqEnabled: Bool
    let mono: Bool
    let spatial: Bool
    let spatialAmount: Double
    let enhanced: Bool
    let processingMode: EqualizerProcessingMode
}

private final class WeakTapContext {
    weak var value: TapContext?

    init(_ value: TapContext) {
        self.value = value
    }
}

// Kept internal so the coefficient layout and response can be unit tested.
enum EqualizerBiquadDesigner {
    private static let headroomMarginDB = 0.25

    static func sanitizedGain(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(EqualizerEngine.range.upperBound, max(EqualizerEngine.range.lowerBound, value))
    }

    static func sanitizedPreampDB(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(0, max(-24, value))
    }

    static func shouldProcess(gains: [Double], preampDB: Double, enabled: Bool) -> Bool {
        enabled && (
            abs(sanitizedPreampDB(preampDB)) > 1.0e-12
                || gains.contains { abs(sanitizedGain($0)) > 1.0e-12 }
        )
    }

    /// Positive filters need digital headroom. Respect a more conservative
    /// imported preamp, otherwise offset the peak of the complete cascade (not
    /// just the largest slider) so overlapping bands cannot overload playback.
    static func effectivePreampDB(
        gains: [Double],
        configuredPreampDB: Double,
        sampleRate: Double = 48_000
    ) -> Double {
        let configured = sanitizedPreampDB(configuredPreampDB)
        let compoundBoost = maximumBoostDB(gains: gains, sampleRate: sampleRate)
        guard compoundBoost > 1.0e-9 else { return configured }
        return min(configured, -(compoundBoost + headroomMarginDB))
    }

    /// Samples the actual ten-section response densely on a log-frequency grid.
    /// This mirrors how AutoEQ derives preamp headroom for a compound curve.
    static func maximumBoostDB(gains: [Double], sampleRate: Double) -> Double {
        guard sampleRate.isFinite, sampleRate > 40 else { return 0 }
        let nyquist = sampleRate * 0.5
        let low = min(20, nyquist * 0.25)
        let high = min(20_000, nyquist * 0.999)
        guard high > low else { return 0 }

        let sanitized = (0..<EqualizerEngine.bandCount).map { index in
            sanitizedGain(index < gains.count ? gains[index] : 0)
        }
        let sections = zip(EqualizerEngine.frequencies, sanitized).map { frequency, gain in
            sectionCoefficients(gainDB: gain, frequency: frequency, sampleRate: sampleRate)
        }
        let sampleCount = 2_048
        let ratio = high / low
        var maximum = 0.0

        func measure(at frequency: Double) {
            guard frequency > 0, frequency < nyquist else { return }
            let omega = 2 * Double.pi * frequency / sampleRate
            let c1 = cos(omega), s1 = sin(omega)
            let c2 = cos(2 * omega), s2 = sin(2 * omega)
            var responseDB = 0.0
            for section in sections {
                let numeratorReal = section.0 + section.1 * c1 + section.2 * c2
                let numeratorImaginary = -(section.1 * s1 + section.2 * s2)
                let denominatorReal = 1 + section.3 * c1 + section.4 * c2
                let denominatorImaginary = -(section.3 * s1 + section.4 * s2)
                let numeratorPower = numeratorReal * numeratorReal + numeratorImaginary * numeratorImaginary
                let denominatorPower = denominatorReal * denominatorReal + denominatorImaginary * denominatorImaginary
                guard numeratorPower.isFinite, denominatorPower.isFinite, denominatorPower > 1.0e-30 else {
                    responseDB = 0
                    return
                }
                responseDB += 10 * log10(max(1.0e-30, numeratorPower / denominatorPower))
            }
            if responseDB.isFinite { maximum = max(maximum, responseDB) }
        }

        for index in 0..<sampleCount {
            let position = Double(index) / Double(sampleCount - 1)
            measure(at: low * pow(ratio, position))
        }
        for frequency in EqualizerEngine.frequencies where frequency < nyquist {
            measure(at: frequency)
        }
        return maximum
    }

    static func coefficients(gains: [Double], sampleRate: Double, channels: Int) -> [Double] {
        let channelCount = max(1, channels)
        var result = [Double](
            repeating: 0,
            count: EqualizerEngine.bandCount * channelCount * 5
        )
        for band in 0..<EqualizerEngine.bandCount {
            let gainDB = sanitizedGain(band < gains.count ? gains[band] : 0)
            let f0 = EqualizerEngine.frequencies[band]
            let section = sectionCoefficients(gainDB: gainDB, frequency: f0, sampleRate: sampleRate)

            // vDSP_biquadm is section-major, then coefficient-major, with
            // channel values interleaved for every coefficient.
            let base = band * channelCount * 5
            for channel in 0..<channelCount {
                result[base + channel] = section.0
                result[base + channelCount + channel] = section.1
                result[base + channelCount * 2 + channel] = section.2
                result[base + channelCount * 3 + channel] = section.3
                result[base + channelCount * 4 + channel] = section.4
            }
        }
        return result
    }

    private static func sectionCoefficients(
        gainDB: Double,
        frequency: Double,
        sampleRate: Double
    ) -> (Double, Double, Double, Double, Double) {
        // A band at or above Nyquist has no representable centre frequency.
        // Designing it anyway makes sin(w0) negative and can create unstable
        // poles on low-rate material. Exact unity also avoids cancellation noise.
        guard sampleRate.isFinite,
              sampleRate > 0,
              frequency < sampleRate * 0.5,
              abs(gainDB) >= 1.0e-12 else {
            return (1, 0, 0, 0, 0)
        }

        let amplitude = pow(10.0, gainDB / 40.0)
        let omega = 2.0 * Double.pi * frequency / sampleRate
        let alpha = sin(omega) / (2.0 * EqualizerEngine.filterQ)
        let a0 = 1 + alpha / amplitude
        guard amplitude.isFinite, alpha.isFinite, a0.isFinite, abs(a0) > 1.0e-12 else {
            return (1, 0, 0, 0, 0)
        }
        let cosine = cos(omega)
        return (
            (1 + alpha * amplitude) / a0,
            (-2 * cosine) / a0,
            (1 - alpha * amplitude) / a0,
            (-2 * cosine) / a0,
            (1 - alpha / amplitude) / a0
        )
    }
}

private struct TapDSPConfiguration {
    let generation: UInt64
    let eqEnabled: Bool
    let preampLinear: Float
    let mono: Bool
    let spatial: Bool
    let spatialAmount: Float
    let spatialEnhanced: Bool
}

// vDSP setup and persistent filter state for one AVPlayerItem tap.
// Retained while the vector backend is investigated, but not attached to
// playback. The shipped scalar backend below is the active implementation.
private final class VectorTapContext {
    let bypassEffects: Bool
    private var sampleRate: Double = 44_100
    private var channels: Int = 2
    private var supportsInPlaceFloat32 = false
    private var generation: UInt64 = .max
    private var setup: vDSP_biquadm_Setup?
    private var inputPointers: [UnsafePointer<Float>] = []
    private var outputPointers: [UnsafeMutablePointer<Float>] = []

    // Cached effect flags.
    private var eqEnabled = false
    private var currentPreamp: Float = 1
    private var targetPreamp: Float = 1
    private var preampRampFramesRemaining = 0
    private var mono = false
    private var spatial = false
    private var spatialAmount: Float = 0.65
    private var spatialEnhanced = false

    // Control-thread updates are fully prepared before publication. The render
    // thread uses try-lock so it never waits behind UI/preset work.
    private var pendingLock = os_unfair_lock_s()
    private var pendingConfiguration: TapDSPConfiguration?
    private var pendingCoefficients = [Double](
        repeating: 0,
        count: EqualizerEngine.bandCount * 2 * 5
    )
    private var hasPendingCoefficients = false

    // Enhanced widener: one-pole high-pass on the side channel (keeps bass centred).
    private var sideHPAlpha: Float = 0
    private var sideHPPrevIn: Float = 0
    private var sideHPPrevOut: Float = 0
    private var spatialLimiterGain: Float = 1

    init(bypassEffects: Bool = false) {
        self.bypassEffects = bypassEffects
    }

    deinit {
        if let setup { vDSP_biquadm_DestroySetup(setup) }
    }

    func prepare(format: AudioStreamBasicDescription, maxFrames: Int) {
        if let setup { vDSP_biquadm_DestroySetup(setup) }
        // Discard pre-prepare work before reading the authoritative engine
        // snapshot. Updates arriving after this point remain staged and cannot
        // be erased at the end of preparation.
        os_unfair_lock_lock(&pendingLock)
        pendingConfiguration = nil
        self.sampleRate = format.mSampleRate > 0 ? format.mSampleRate : 44_100
        self.channels = max(1, Int(format.mChannelsPerFrame))
        pendingCoefficients = [Double](
            repeating: 0,
            count: EqualizerEngine.bandCount * self.channels * 5
        )
        hasPendingCoefficients = false
        os_unfair_lock_unlock(&pendingLock)
        let flags = format.mFormatFlags
        let isNonInterleaved = (flags & kAudioFormatFlagIsNonInterleaved) != 0
        let expectedBytesPerFrame = UInt32(MemoryLayout<Float>.size * (isNonInterleaved ? 1 : self.channels))
        supportsInPlaceFloat32 = format.mFormatID == kAudioFormatLinearPCM
            && (flags & kAudioFormatFlagIsFloat) != 0
            && (flags & kAudioFormatFlagIsBigEndian) == 0
            && format.mBitsPerChannel == 32
            && format.mBytesPerFrame == expectedBytesPerFrame
        if !supportsInPlaceFloat32 {
            let formatID = format.mFormatID
            let bits = format.mBitsPerChannel
            let bytesPerFrame = format.mBytesPerFrame
            DispatchQueue.global(qos: .utility).async {
                AppLogger.shared.log(
                    "Audio effects bypassed for unsupported tap PCM; formatID=\(formatID); bits=\(bits); bytesPerFrame=\(bytesPerFrame)",
                    category: .playback,
                    level: .warning
                )
            }
        }
        inputPointers = []
        outputPointers = []
        inputPointers.reserveCapacity(self.channels)
        outputPointers.reserveCapacity(self.channels)

        let settings = EqualizerEngine.shared.snapshot()
        let coefficients = EqualizerBiquadDesigner.coefficients(
            gains: settings.gains,
            sampleRate: self.sampleRate,
            channels: self.channels
        )
        if supportsInPlaceFloat32 {
            setup = coefficients.withUnsafeBufferPointer {
                guard let base = $0.baseAddress else { return nil }
                return vDSP_biquadm_CreateSetup(
                    base,
                    vDSP_Length(EqualizerEngine.bandCount),
                    vDSP_Length(self.channels)
                )
            }
        } else {
            // The source audio has already been copied into bufferListInOut.
            // Fail open rather than interpreting integer/fixed-point PCM as Float.
            setup = nil
        }
        generation = settings.generation
        eqEnabled = !bypassEffects && EqualizerBiquadDesigner.shouldProcess(
            gains: settings.gains,
            preampDB: settings.preampDB,
            enabled: settings.eqEnabled
        )
        let effectivePreampDB = EqualizerBiquadDesigner.effectivePreampDB(
            gains: settings.gains,
            configuredPreampDB: settings.preampDB,
            sampleRate: self.sampleRate
        )
        targetPreamp = Float(pow(10, effectivePreampDB / 20))
        currentPreamp = targetPreamp
        preampRampFramesRemaining = 0
        mono = !bypassEffects && settings.mono
        spatial = !bypassEffects && settings.spatial
        spatialAmount = Float(settings.spatialAmount)
        spatialEnhanced = settings.enhanced

        // One-pole high-pass coefficient (~300 Hz) for the enhanced widener's side channel.
        let rc = 1.0 / (2.0 * Double.pi * 300.0)
        let dt = 1.0 / self.sampleRate
        sideHPAlpha = Float(rc / (rc + dt))
        sideHPPrevIn = 0
        sideHPPrevOut = 0
        spatialLimiterGain = 1
    }

    func unprepare() {
        if let setup { vDSP_biquadm_DestroySetup(setup) }
        setup = nil
        inputPointers = []
        outputPointers = []
    }

    // Called from control threads. All trigonometry and allocation happens
    // here, never in MTAudioProcessingTap's render callback.
    fileprivate func stage(_ settings: EqualizerSettingsSnapshot, coefficientsChanged: Bool) {
        os_unfair_lock_lock(&pendingLock)
        if coefficientsChanged {
            let designed = EqualizerBiquadDesigner.coefficients(
                gains: settings.gains,
                sampleRate: sampleRate,
                channels: channels
            )
            if pendingCoefficients.count == designed.count {
                for index in designed.indices {
                    pendingCoefficients[index] = designed[index]
                }
            } else {
                pendingCoefficients = designed
            }
            hasPendingCoefficients = true
        }
        // A later flag-only update deliberately leaves an unconsumed coefficient
        // buffer intact.
        let configuration = TapDSPConfiguration(
            generation: settings.generation,
            eqEnabled: !bypassEffects && EqualizerBiquadDesigner.shouldProcess(
                gains: settings.gains,
                preampDB: settings.preampDB,
                enabled: settings.eqEnabled
            ),
            preampLinear: Float(pow(
                10,
                EqualizerBiquadDesigner.effectivePreampDB(
                    gains: settings.gains,
                    configuredPreampDB: settings.preampDB,
                    sampleRate: sampleRate
                ) / 20
            )),
            mono: !bypassEffects && settings.mono,
            spatial: !bypassEffects && settings.spatial,
            spatialAmount: Float(settings.spatialAmount),
            spatialEnhanced: settings.enhanced
        )
        pendingConfiguration = configuration
        os_unfair_lock_unlock(&pendingLock)
    }

    private func consumePendingConfiguration() {
        guard os_unfair_lock_trylock(&pendingLock) else { return }
        guard let configuration = pendingConfiguration else {
            os_unfair_lock_unlock(&pendingLock)
            return
        }
        pendingConfiguration = nil
        guard configuration.generation != generation else {
            hasPendingCoefficients = false
            os_unfair_lock_unlock(&pendingLock)
            return
        }

        let wasEQEnabled = eqEnabled
        generation = configuration.generation
        eqEnabled = configuration.eqEnabled
        mono = configuration.mono
        spatial = configuration.spatial
        spatialAmount = configuration.spatialAmount
        spatialEnhanced = configuration.spatialEnhanced
        if targetPreamp != configuration.preampLinear {
            targetPreamp = configuration.preampLinear
            preampRampFramesRemaining = max(1, Int(sampleRate * 0.05))
        }
        let coefficientsChanged = hasPendingCoefficients
        if coefficientsChanged, let setup {
            pendingCoefficients.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                if wasEQEnabled {
                    // Smooth coefficient targets prevent zipper noise while a
                    // slider or complete preset changes during playback.
                    vDSP_biquadm_SetTargetsDouble(
                        setup,
                        base,
                        0.002,
                        1.0e-8,
                        0,
                        0,
                        vDSP_Length(EqualizerEngine.bandCount),
                        vDSP_Length(channels)
                    )
                } else {
                    vDSP_biquadm_SetCoefficientsDouble(
                        setup,
                        base,
                        0,
                        0,
                        vDSP_Length(EqualizerEngine.bandCount),
                        vDSP_Length(channels)
                    )
                }
            }
            if !wasEQEnabled { vDSP_biquadm_ResetState(setup) }
        }
        hasPendingCoefficients = false
        if !coefficientsChanged, eqEnabled && !wasEQEnabled, let setup {
            vDSP_biquadm_ResetState(setup)
        }
        os_unfair_lock_unlock(&pendingLock)
    }

    // Process source buffers in place.
    func process(
        _ bufferList: UnsafeMutablePointer<AudioBufferList>,
        frames: Int,
        discontinuity: Bool
    ) {
        consumePendingConfiguration()
        guard frames > 0, supportsInPlaceFloat32 else { return }
        if discontinuity {
            if let setup { vDSP_biquadm_ResetState(setup) }
            sideHPPrevIn = 0
            sideHPPrevOut = 0
            spatialLimiterGain = 1
        }
        AudioVisualizerEngine.shared.ingest(bufferList, frames: frames, sampleRate: sampleRate)

        let abl = UnsafeMutableAudioBufferListPointer(bufferList)

        // 1) Graphic EQ per channel.
        if eqEnabled, let layout = audioLayout(in: abl, frames: frames) {
            applyPreamp(frameCount: layout.frames, stride: layout.stride)
            inputPointers.withUnsafeMutableBufferPointer { inputs in
                outputPointers.withUnsafeMutableBufferPointer { outputs in
                    guard let setup,
                          let inputBase = inputs.baseAddress,
                          let outputBase = outputs.baseAddress else { return }
                    vDSP_biquadm(
                        setup,
                        inputBase,
                        vDSP_Stride(layout.stride),
                        outputBase,
                        vDSP_Stride(layout.stride),
                        vDSP_Length(layout.frames)
                    )
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
            let w = 1 + max(0, min(1.5, spatialAmount))
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
                let widenedL = mid + wideSide
                let widenedR = mid - wideSide
                lPtr[j] = widenedL
                rPtr[j] = widenedR
            }
            sideHPPrevIn = prevIn
            sideHPPrevOut = prevOut
            applySpatialPeakLimiter(lPtr: lPtr, rPtr: rPtr, stride: step, frames: n)
        } else {
            // Basic: flat mid/side gain followed by transparent linear limiting.
            let w = 1 + max(0, min(1.5, spatialAmount))
            for i in 0..<n {
                let j = i * step
                let l = lPtr[j], r = rPtr[j]
                let mid = (l + r) * 0.5
                let side = (l - r) * 0.5 * w
                lPtr[j] = mid + side
                rPtr[j] = mid - side
            }
            applySpatialPeakLimiter(lPtr: lPtr, rPtr: rPtr, stride: step, frames: n)
        }
    }

    private func audioLayout(
        in abl: UnsafeMutableAudioBufferListPointer,
        frames: Int
    ) -> (frames: Int, stride: Int)? {
        guard setup != nil else { return nil }
        inputPointers.removeAll(keepingCapacity: true)
        outputPointers.removeAll(keepingCapacity: true)

        if abl.count == channels, abl.allSatisfy({ $0.mNumberChannels == 1 }) {
            var frameCount = frames
            for channel in 0..<channels {
                guard let raw = abl[channel].mData else { return nil }
                let pointer = raw.assumingMemoryBound(to: Float.self)
                inputPointers.append(UnsafePointer(pointer))
                outputPointers.append(pointer)
                frameCount = min(
                    frameCount,
                    Int(abl[channel].mDataByteSize) / MemoryLayout<Float>.size
                )
            }
            return frameCount > 0 ? (frameCount, 1) : nil
        }

        if abl.count == 1,
           Int(abl[0].mNumberChannels) == channels,
           let raw = abl[0].mData {
            let pointer = raw.assumingMemoryBound(to: Float.self)
            let totalSamples = Int(abl[0].mDataByteSize) / MemoryLayout<Float>.size
            let frameCount = min(frames, totalSamples / channels)
            guard frameCount > 0 else { return nil }
            for channel in 0..<channels {
                inputPointers.append(UnsafePointer(pointer + channel))
                outputPointers.append(pointer + channel)
            }
            return (frameCount, channels)
        }
        return nil
    }

    private func applyPreamp(frameCount: Int, stride: Int) {
        guard frameCount > 0 else { return }
        let rampFrames = min(frameCount, preampRampFramesRemaining)
        if rampFrames > 0 {
            let start = currentPreamp
            let step = (targetPreamp - currentPreamp) / Float(preampRampFramesRemaining)
            for channel in 0..<channels {
                let samples = outputPointers[channel]
                var channelStart = start
                var channelStep = step
                vDSP_vrampmul(
                    samples,
                    vDSP_Stride(stride),
                    &channelStart,
                    &channelStep,
                    samples,
                    vDSP_Stride(stride),
                    vDSP_Length(rampFrames)
                )
                if rampFrames < frameCount {
                    var gain = targetPreamp
                    vDSP_vsmul(
                        samples + rampFrames * stride,
                        vDSP_Stride(stride),
                        &gain,
                        samples + rampFrames * stride,
                        vDSP_Stride(stride),
                        vDSP_Length(frameCount - rampFrames)
                    )
                }
            }
            currentPreamp += step * Float(rampFrames)
            preampRampFramesRemaining -= rampFrames
            if preampRampFramesRemaining == 0 { currentPreamp = targetPreamp }
        } else if currentPreamp != 1 {
            var gain = currentPreamp
            for channel in 0..<channels {
                let samples = outputPointers[channel]
                vDSP_vsmul(
                    samples,
                    vDSP_Stride(stride),
                    &gain,
                    samples,
                    vDSP_Stride(stride),
                    vDSP_Length(frameCount)
                )
            }
        }
    }

    private func applySpatialPeakLimiter(
        lPtr: UnsafeMutablePointer<Float>,
        rPtr: UnsafeMutablePointer<Float>,
        stride: Int,
        frames: Int
    ) {
        guard frames > 0 else { return }
        var peak: Float = 0
        for i in 0..<frames {
            let sampleIndex = i * stride
            let left = lPtr[sampleIndex]
            let right = rPtr[sampleIndex]
            if left.isFinite {
                peak = max(peak, abs(left))
            } else {
                lPtr[sampleIndex] = 0
            }
            if right.isFinite {
                peak = max(peak, abs(right))
            } else {
                rPtr[sampleIndex] = 0
            }
        }

        let target = peak > 0.98 ? 0.98 / peak : 1
        if target < spatialLimiterGain {
            spatialLimiterGain = target
        } else {
            let releaseFraction = min(1, Float(frames) / Float(max(1, sampleRate * 0.25)))
            spatialLimiterGain = min(target, spatialLimiterGain + (1 - spatialLimiterGain) * releaseFraction)
        }
        guard spatialLimiterGain < 0.999_999 else { return }
        var gain = spatialLimiterGain
        vDSP_vsmul(lPtr, vDSP_Stride(stride), &gain, lPtr, vDSP_Stride(stride), vDSP_Length(frames))
        vDSP_vsmul(rPtr, vDSP_Stride(stride), &gain, rPtr, vDSP_Stride(stride), vDSP_Length(frames))
    }
}

// Known-good scalar backend used by the shipped player. Keep it as the active
// tap until the vector implementation has on-device route coverage.
final class TapContext: AutoMixTransitionDSPContext {
    private struct EfficientBiquad {
        let b0: Float
        // Peaking EQ has b1 == a1. Store it once and multiply it by
        // (x1 - y1), saving one multiply per section and sample.
        let sharedX1MinusY1: Float
        let b2: Float
        let a2: Float
        let b0Stereo: SIMD2<Float>
        let sharedX1MinusY1Stereo: SIMD2<Float>
        let b2Stereo: SIMD2<Float>
        let a2Stereo: SIMD2<Float>
    }

    private struct EfficientStereoState {
        var x1: SIMD2<Float> = .zero
        var x2: SIMD2<Float> = .zero
        var y1: SIMD2<Float> = .zero
        var y2: SIMD2<Float> = .zero
    }

    let bypassEffects: Bool
    let autoMixChannelID: UInt64
    private var sampleRate: Double = 44_100
    private var channels = 2
    private var supportsFloat32 = true
    private var generation: UInt64 = .max

    private var eqEnabled = false
    private var preampLinear = 1.0
    private var mono = false
    private var spatial = false
    private var spatialAmount = 0.65
    private var spatialEnhanced = false
    private var processingMode: EqualizerProcessingMode = .efficient

    private var sideHPAlpha: Float = 0
    private var sideHPPrevIn: Float = 0
    private var sideHPPrevOut: Float = 0
    private var coeffs = [[Double]](
        repeating: [1, 0, 0, 0, 0],
        count: EqualizerEngine.bandCount
    )
    private var state: [[[Double]]] = []
    // The efficient backend keeps its state in a compact Float buffer and only
    // iterates filters whose band gain is non-zero. It intentionally does not
    // use vDSP so route behaviour remains independent of that experiment.
    private var efficientFilters: [EfficientBiquad] = []
    private var efficientState: [Float] = []
    private var efficientStereoState: [EfficientStereoState] = []
    private var pendingLock = os_unfair_lock_s()
    private var pendingSettings: EqualizerSettingsSnapshot?
    private var pendingAutoMixFilter: AutoMixPreparedFilter?
    private var hasPendingAutoMixUpdate = false
    private var autoMixFilter: AutoMixPreparedFilter?
    private var autoMixHighPassPreviousInput: [Float] = []
    private var autoMixHighPassPreviousOutput: [Float] = []
    private var autoMixLowPassPreviousOutput: [Float] = []

    init(bypassEffects: Bool = false, autoMixChannelID: UInt64 = 0) {
        self.bypassEffects = bypassEffects
        self.autoMixChannelID = autoMixChannelID
        efficientFilters.reserveCapacity(EqualizerEngine.bandCount)
    }

    func prepare(format: AudioStreamBasicDescription, maxFrames: Int) {
        sampleRate = format.mSampleRate > 0 ? format.mSampleRate : 44_100
        channels = max(1, Int(format.mChannelsPerFrame))
        let flags = format.mFormatFlags
        supportsFloat32 = format.mFormatID == kAudioFormatLinearPCM
            && (flags & kAudioFormatFlagIsFloat) != 0
            && (flags & kAudioFormatFlagIsBigEndian) == 0
            && format.mBitsPerChannel == 32
        state = Array(
            repeating: Array(
                repeating: [0, 0, 0, 0],
                count: EqualizerEngine.bandCount
            ),
            count: channels
        )
        efficientState = [Float](
            repeating: 0,
            count: channels * EqualizerEngine.bandCount * 4
        )
        efficientStereoState = [EfficientStereoState](
            repeating: EfficientStereoState(),
            count: EqualizerEngine.bandCount
        )
        let rc = 1.0 / (2.0 * Double.pi * 300.0)
        let dt = 1.0 / sampleRate
        sideHPAlpha = Float(rc / (rc + dt))
        sideHPPrevIn = 0
        sideHPPrevOut = 0
        autoMixHighPassPreviousInput = [Float](repeating: 0, count: channels)
        autoMixHighPassPreviousOutput = [Float](repeating: 0, count: channels)
        autoMixLowPassPreviousOutput = [Float](repeating: 0, count: channels)
        os_unfair_lock_lock(&pendingLock)
        pendingSettings = nil
        pendingAutoMixFilter = nil
        hasPendingAutoMixUpdate = false
        os_unfair_lock_unlock(&pendingLock)
        generation = .max
        apply(EqualizerEngine.shared.snapshot())
        if let descriptor = AutoMixTransitionDSP.shared.descriptor(channelID: autoMixChannelID) {
            autoMixFilter = AutoMixPreparedFilter(descriptor: descriptor, sampleRate: sampleRate)
        } else {
            autoMixFilter = nil
        }
    }

    func unprepare() {
        state = []
        efficientState = []
        efficientStereoState = []
        autoMixHighPassPreviousInput = []
        autoMixHighPassPreviousOutput = []
        autoMixLowPassPreviousOutput = []
    }

    fileprivate func stage(_ settings: EqualizerSettingsSnapshot, coefficientsChanged: Bool) {
        os_unfair_lock_lock(&pendingLock)
        pendingSettings = settings
        os_unfair_lock_unlock(&pendingLock)
    }

    func stageAutoMixFilter(_ descriptor: AutoMixTransitionFilterDescriptor?) {
        let prepared = descriptor.map {
            AutoMixPreparedFilter(descriptor: $0, sampleRate: sampleRate)
        }
        os_unfair_lock_lock(&pendingLock)
        pendingAutoMixFilter = prepared
        hasPendingAutoMixUpdate = true
        os_unfair_lock_unlock(&pendingLock)
    }

    private func consumePendingSettings() {
        var settings: EqualizerSettingsSnapshot?
        if os_unfair_lock_trylock(&pendingLock) {
            settings = pendingSettings
            pendingSettings = nil
            os_unfair_lock_unlock(&pendingLock)
        }
        if let settings {
            apply(settings)
        }
    }

    private func consumePendingAutoMixFilter() {
        guard os_unfair_lock_trylock(&pendingLock) else { return }
        guard hasPendingAutoMixUpdate else {
            os_unfair_lock_unlock(&pendingLock)
            return
        }
        autoMixFilter = pendingAutoMixFilter
        pendingAutoMixFilter = nil
        hasPendingAutoMixUpdate = false
        for index in autoMixHighPassPreviousInput.indices {
            autoMixHighPassPreviousInput[index] = 0
            autoMixHighPassPreviousOutput[index] = 0
            autoMixLowPassPreviousOutput[index] = 0
        }
        os_unfair_lock_unlock(&pendingLock)
    }

    private func apply(_ settings: EqualizerSettingsSnapshot) {
        generation = settings.generation
        eqEnabled = !bypassEffects && EqualizerBiquadDesigner.shouldProcess(
            gains: settings.gains,
            preampDB: settings.preampDB,
            enabled: settings.eqEnabled
        )
        preampLinear = pow(10, settings.preampDB / 20)
        mono = !bypassEffects && settings.mono
        spatial = !bypassEffects && settings.spatial
        spatialAmount = settings.spatialAmount
        spatialEnhanced = settings.enhanced
        processingMode = settings.processingMode

        guard processingMode == .accurate else {
            rebuildEfficientFilters(settings)
            return
        }

        for band in 0..<EqualizerEngine.bandCount {
            let frequency = EqualizerEngine.frequencies[band]
            let gainDB = EqualizerBiquadDesigner.sanitizedGain(
                band < settings.gains.count ? settings.gains[band] : 0
            )
            guard frequency < sampleRate * 0.5,
                  abs(gainDB) >= 1.0e-12 else {
                coeffs[band] = [1, 0, 0, 0, 0]
                continue
            }
            let amplitude = pow(10.0, gainDB / 40.0)
            let omega = 2.0 * Double.pi * frequency / sampleRate
            let alpha = sin(omega) / (2.0 * EqualizerEngine.filterQ)
            let a0 = 1 + alpha / amplitude
            guard amplitude.isFinite,
                  alpha.isFinite,
                  a0.isFinite,
                  abs(a0) > 1.0e-12 else {
                coeffs[band] = [1, 0, 0, 0, 0]
                continue
            }
            let cosine = cos(omega)
            coeffs[band] = [
                (1 + alpha * amplitude) / a0,
                (-2 * cosine) / a0,
                (1 - alpha * amplitude) / a0,
                (-2 * cosine) / a0,
                (1 - alpha / amplitude) / a0,
            ]
        }
    }

    private func rebuildEfficientFilters(_ settings: EqualizerSettingsSnapshot) {
        efficientFilters.removeAll(keepingCapacity: true)
        guard eqEnabled else { return }

        for band in 0..<EqualizerEngine.bandCount {
            let frequency = EqualizerEngine.frequencies[band]
            let gainDB = EqualizerBiquadDesigner.sanitizedGain(
                band < settings.gains.count ? settings.gains[band] : 0
            )
            guard frequency < sampleRate * 0.5,
                  abs(gainDB) >= settings.processingMode.minimumBandGainDB else { continue }

            let amplitude = pow(10.0, gainDB / 40.0)
            let omega = 2.0 * Double.pi * frequency / sampleRate
            let alpha = sin(omega) / (2.0 * EqualizerEngine.filterQ)
            let a0 = 1 + alpha / amplitude
            guard amplitude.isFinite,
                  alpha.isFinite,
                  a0.isFinite,
                  abs(a0) > 1.0e-12 else { continue }

            let cosine = cos(omega)
            let b0 = Float((1 + alpha * amplitude) / a0)
            let sharedX1MinusY1 = Float((-2 * cosine) / a0)
            let b2 = Float((1 - alpha * amplitude) / a0)
            let a2 = Float((1 - alpha / amplitude) / a0)
            let filter = EfficientBiquad(
                b0: b0,
                sharedX1MinusY1: sharedX1MinusY1,
                b2: b2,
                a2: a2,
                b0Stereo: SIMD2(repeating: b0),
                sharedX1MinusY1Stereo: SIMD2(repeating: sharedX1MinusY1),
                b2Stereo: SIMD2(repeating: b2),
                a2Stereo: SIMD2(repeating: a2)
            )
            guard filter.b0.isFinite,
                  filter.sharedX1MinusY1.isFinite,
                  filter.b2.isFinite,
                  filter.a2.isFinite else { continue }
            efficientFilters.append(filter)
        }

        resetEfficientState()
    }

    private func resetEfficientState() {
        // Coefficients and filter order can both change. Reset the compact
        // state at that boundary to avoid carrying history into a new cascade.
        for index in efficientState.indices {
            efficientState[index] = 0
        }
        for index in efficientStereoState.indices {
            efficientStereoState[index] = EfficientStereoState()
        }
    }

    func process(
        _ bufferList: UnsafeMutablePointer<AudioBufferList>,
        frames: Int,
        discontinuity: Bool,
        mediaTime: TimeInterval
    ) {
        consumePendingSettings()
        consumePendingAutoMixFilter()
        guard frames > 0, supportsFloat32, !state.isEmpty else { return }
        if discontinuity {
            for channel in state.indices {
                for band in state[channel].indices {
                    for value in state[channel][band].indices {
                        state[channel][band][value] = 0
                    }
                }
            }
            resetEfficientState()
            sideHPPrevIn = 0
            sideHPPrevOut = 0
            for index in autoMixHighPassPreviousInput.indices {
                autoMixHighPassPreviousInput[index] = 0
                autoMixHighPassPreviousOutput[index] = 0
                autoMixLowPassPreviousOutput[index] = 0
            }
        }
        AudioVisualizerEngine.shared.ingest(
            bufferList,
            frames: frames,
            sampleRate: sampleRate
        )

        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        defer {
            processAutoMixFilter(
                audioBufferList: abl,
                frames: frames,
                mediaTime: mediaTime
            )
        }
        if eqEnabled {
            let processedStereo = processEfficientStereoIfPossible(
                audioBufferList: abl,
                frames: frames
            )
            if !processedStereo,
               abl.count == channels,
               abl.allSatisfy({ $0.mNumberChannels == 1 }) {
                for channel in 0..<channels {
                    guard let raw = abl[channel].mData else { continue }
                    let frameCount = min(
                        frames,
                        Int(abl[channel].mDataByteSize) / MemoryLayout<Float>.size
                    )
                    processEQ(
                        raw.assumingMemoryBound(to: Float.self), stride: 1,
                        frames: frameCount, channel: channel
                    )
                }
            } else if !processedStereo,
                      abl.count == 1,
                      let raw = abl[0].mData {
                let bufferChannels = max(1, Int(abl[0].mNumberChannels))
                let frameCount = min(
                    frames,
                    Int(abl[0].mDataByteSize) / MemoryLayout<Float>.size / bufferChannels
                )
                let samples = raw.assumingMemoryBound(to: Float.self)
                for channel in 0..<min(channels, bufferChannels) {
                    processEQ(
                        samples + channel, stride: bufferChannels,
                        frames: frameCount, channel: channel
                    )
                }
            }
        }

        guard mono || spatial else { return }
        let lPtr: UnsafeMutablePointer<Float>
        let rPtr: UnsafeMutablePointer<Float>
        let stride: Int
        let frameCount: Int
        if abl.count >= 2,
           let left = abl[0].mData,
           let right = abl[1].mData {
            lPtr = left.assumingMemoryBound(to: Float.self)
            rPtr = right.assumingMemoryBound(to: Float.self)
            stride = 1
            frameCount = min(
                frames,
                Int(abl[0].mDataByteSize) / MemoryLayout<Float>.size,
                Int(abl[1].mDataByteSize) / MemoryLayout<Float>.size
            )
        } else if abl.count == 1,
                  abl[0].mNumberChannels >= 2,
                  let raw = abl[0].mData {
            let bufferChannels = Int(abl[0].mNumberChannels)
            lPtr = raw.assumingMemoryBound(to: Float.self)
            rPtr = lPtr + 1
            stride = bufferChannels
            frameCount = min(
                frames,
                Int(abl[0].mDataByteSize) / MemoryLayout<Float>.size / bufferChannels
            )
        } else {
            return
        }

        if mono {
            for frame in 0..<frameCount {
                let index = frame * stride
                let mixed = (lPtr[index] + rPtr[index]) * 0.5
                lPtr[index] = mixed
                rPtr[index] = mixed
            }
        } else {
            let width = Float(1 + max(0, min(1.5, spatialAmount)))
            let alpha = sideHPAlpha
            var previousInput = sideHPPrevIn
            var previousOutput = sideHPPrevOut
            for frame in 0..<frameCount {
                let index = frame * stride
                let left = lPtr[index]
                let right = rPtr[index]
                let mid = (left + right) * 0.5
                let side = (left - right) * 0.5
                let widenedSide: Float
                if spatialEnhanced {
                    let highPassed = alpha * (previousOutput + side - previousInput)
                    previousInput = side
                    previousOutput = highPassed
                    widenedSide = side + highPassed * (width - 1)
                } else {
                    widenedSide = side * width
                }
                lPtr[index] = Self.softClip(mid + widenedSide)
                rPtr[index] = Self.softClip(mid - widenedSide)
            }
            sideHPPrevIn = previousInput
            sideHPPrevOut = previousOutput
        }
    }

    private func processAutoMixFilter(
        audioBufferList: UnsafeMutableAudioBufferListPointer,
        frames: Int,
        mediaTime: TimeInterval
    ) {
        guard let filter = autoMixFilter,
              !filter.descriptor.isBypassed,
              mediaTime.isFinite,
              filter.descriptor.mediaDuration > 0,
              !autoMixHighPassPreviousInput.isEmpty else { return }

        if audioBufferList.count == channels,
           audioBufferList.allSatisfy({ $0.mNumberChannels == 1 }) {
            for channel in 0..<channels {
                guard let raw = audioBufferList[channel].mData else { continue }
                let frameCount = min(
                    frames,
                    Int(audioBufferList[channel].mDataByteSize) / MemoryLayout<Float>.size
                )
                processAutoMixChannel(
                    raw.assumingMemoryBound(to: Float.self),
                    stride: 1,
                    frameCount: frameCount,
                    channel: channel,
                    filter: filter,
                    mediaTime: mediaTime
                )
            }
        } else if audioBufferList.count == 1,
                  let raw = audioBufferList[0].mData {
            let bufferChannels = max(1, Int(audioBufferList[0].mNumberChannels))
            let frameCount = min(
                frames,
                Int(audioBufferList[0].mDataByteSize) / MemoryLayout<Float>.size / bufferChannels
            )
            let samples = raw.assumingMemoryBound(to: Float.self)
            for channel in 0..<min(channels, bufferChannels) {
                processAutoMixChannel(
                    samples + channel,
                    stride: bufferChannels,
                    frameCount: frameCount,
                    channel: channel,
                    filter: filter,
                    mediaTime: mediaTime
                )
            }
        }
    }

    @inline(__always)
    private func processAutoMixChannel(
        _ samples: UnsafeMutablePointer<Float>,
        stride: Int,
        frameCount: Int,
        channel: Int,
        filter: AutoMixPreparedFilter,
        mediaTime: TimeInterval
    ) {
        guard channel < autoMixHighPassPreviousInput.count else { return }
        var highPassPreviousInput = autoMixHighPassPreviousInput[channel]
        var highPassPreviousOutput = autoMixHighPassPreviousOutput[channel]
        var lowPassPreviousOutput = autoMixLowPassPreviousOutput[channel]
        let sampleDuration = 1 / max(8_000, sampleRate)
        let descriptor = filter.descriptor
        let highPassActive = descriptor.highPassStartHz > 21 || descriptor.highPassEndHz > 21
        let lowPassActive = descriptor.lowPassStartHz < 19_000 || descriptor.lowPassEndHz < 19_000

        for frame in 0..<frameCount {
            let index = frame * stride
            let progress = (
                mediaTime + Double(frame) * sampleDuration - descriptor.mediaStart
            ) / descriptor.mediaDuration
            let coefficients = filter.coefficients(progress: progress)
            var value = samples[index]
            if highPassActive {
                let output = coefficients.highPass
                    * (highPassPreviousOutput + value - highPassPreviousInput)
                highPassPreviousInput = value
                highPassPreviousOutput = output
                value = output
            }
            if lowPassActive {
                lowPassPreviousOutput += coefficients.lowPass * (value - lowPassPreviousOutput)
                value = lowPassPreviousOutput
            }
            samples[index] = value.isFinite ? value : 0
        }
        autoMixHighPassPreviousInput[channel] = highPassPreviousInput
        autoMixHighPassPreviousOutput[channel] = highPassPreviousOutput
        autoMixLowPassPreviousOutput[channel] = lowPassPreviousOutput
    }

    private func processEQChannel(
        _ samples: UnsafeMutablePointer<Float>,
        stride: Int,
        frames: Int,
        channel: Int
    ) {
        guard channel < state.count else { return }
        for frame in 0..<frames {
            let index = frame * stride
            var input = Double(samples[index]) * preampLinear
            for band in 0..<EqualizerEngine.bandCount {
                let x1 = state[channel][band][0]
                let x2 = state[channel][band][1]
                let y1 = state[channel][band][2]
                let y2 = state[channel][band][3]
                let output = coeffs[band][0] * input
                    + coeffs[band][1] * x1
                    + coeffs[band][2] * x2
                    - coeffs[band][3] * y1
                    - coeffs[band][4] * y2
                state[channel][band][1] = x1
                state[channel][band][0] = input
                state[channel][band][3] = y1
                state[channel][band][2] = output
                input = output
            }
            samples[index] = Float(input)
        }
    }

    private func processEQ(
        _ samples: UnsafeMutablePointer<Float>,
        stride: Int,
        frames: Int,
        channel: Int
    ) {
        if processingMode != .accurate {
            processEfficientEQChannel(samples, stride: stride, frames: frames, channel: channel)
        } else {
            processEQChannel(samples, stride: stride, frames: frames, channel: channel)
        }
    }

    private func processEfficientStereoIfPossible(
        audioBufferList: UnsafeMutableAudioBufferListPointer,
        frames: Int
    ) -> Bool {
        guard processingMode != .accurate, channels == 2 else { return false }

        if audioBufferList.count == 2,
           audioBufferList[0].mNumberChannels == 1,
           audioBufferList[1].mNumberChannels == 1,
           let left = audioBufferList[0].mData,
           let right = audioBufferList[1].mData {
            let frameCount = min(
                frames,
                Int(audioBufferList[0].mDataByteSize) / MemoryLayout<Float>.size,
                Int(audioBufferList[1].mDataByteSize) / MemoryLayout<Float>.size
            )
            processEfficientStereo(
                left: left.assumingMemoryBound(to: Float.self),
                right: right.assumingMemoryBound(to: Float.self),
                stride: 1,
                frames: frameCount
            )
            return true
        }

        if audioBufferList.count == 1,
           audioBufferList[0].mNumberChannels >= 2,
           let raw = audioBufferList[0].mData {
            let bufferChannels = Int(audioBufferList[0].mNumberChannels)
            let frameCount = min(
                frames,
                Int(audioBufferList[0].mDataByteSize) / MemoryLayout<Float>.size / bufferChannels
            )
            let samples = raw.assumingMemoryBound(to: Float.self)
            processEfficientStereo(
                left: samples,
                right: samples + 1,
                stride: bufferChannels,
                frames: frameCount
            )
            return true
        }

        return false
    }

    @inline(__always)
    private func processEfficientStereo(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        stride: Int,
        frames: Int
    ) {
        let filterCount = efficientFilters.count
        guard efficientStereoState.count >= filterCount else { return }
        let preamp = SIMD2<Float>(repeating: Float(preampLinear))

        for frame in 0..<frames {
            let index = frame * stride
            var input = SIMD2(left[index], right[index]) * preamp
            for filterIndex in 0..<filterCount {
                let filter = efficientFilters[filterIndex]
                var state = efficientStereoState[filterIndex]
                let output = filter.b0Stereo * input
                    + filter.sharedX1MinusY1Stereo * (state.x1 - state.y1)
                    + filter.b2Stereo * state.x2
                    - filter.a2Stereo * state.y2
                state.x2 = state.x1
                state.x1 = input
                state.y2 = state.y1
                state.y1 = output
                efficientStereoState[filterIndex] = state
                input = output
            }
            left[index] = input[0]
            right[index] = input[1]
        }
    }

    private func processEfficientEQChannel(
        _ samples: UnsafeMutablePointer<Float>,
        stride: Int,
        frames: Int,
        channel: Int
    ) {
        guard channel < channels else { return }
        let filterCount = efficientFilters.count
        let channelOffset = channel * EqualizerEngine.bandCount * 4
        let preamp = Float(preampLinear)

        for frame in 0..<frames {
            let index = frame * stride
            var input = samples[index] * preamp
            for filterIndex in 0..<filterCount {
                let filter = efficientFilters[filterIndex]
                let stateIndex = channelOffset + filterIndex * 4
                let x1 = efficientState[stateIndex]
                let x2 = efficientState[stateIndex + 1]
                let y1 = efficientState[stateIndex + 2]
                let y2 = efficientState[stateIndex + 3]
                let output = filter.b0 * input
                    + filter.sharedX1MinusY1 * (x1 - y1)
                    + filter.b2 * x2
                    - filter.a2 * y2
                efficientState[stateIndex + 1] = x1
                efficientState[stateIndex] = input
                efficientState[stateIndex + 3] = y1
                efficientState[stateIndex + 2] = output
                input = output
            }
            samples[index] = input
        }
    }

    @inline(__always)
    private static func softClip(_ value: Float) -> Float {
        let knee: Float = 0.7
        let magnitude = abs(value)
        if magnitude <= knee { return value }
        let shaped = knee + (1 - knee) * tanhf((magnitude - knee) / (1 - knee))
        return value < 0 ? -shaped : shaped
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
    ctx.prepare(
        format: asbd,
        maxFrames: Int(maxFrames)
    )
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
    var timeRange = CMTimeRange.invalid
    let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut,
                                                    flagsOut, &timeRange, numberFramesOut)
    guard status == noErr else { return }
    let ctx = Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    let discontinuity = (flagsOut.pointee & MTAudioProcessingTapFlags(kMTAudioProcessingTapFlag_StartOfStream)) != 0
    ctx.process(
        bufferListInOut,
        frames: numberFramesOut.pointee,
        discontinuity: discontinuity,
        mediaTime: timeRange.start.seconds
    )
}
