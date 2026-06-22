import Foundation

// MARK: - AutoMix musical analysis
//
// Pure analysis math for AutoMix. Audio decode and FFT live in AudioPlayer.swift;
// this file works from cheap summaries: energy, beat grid, key, and vocal hints.

// One short-time energy point.
struct AutoMixEnergyPoint: Sendable {
    let time: TimeInterval
    let value: Float
}

// One spectral frame from the vocal-band scan.
struct AutoMixSpectralFrame: Sendable {
    let time: TimeInterval
    let energy: Float
    let midRatio: Float
}

// Beats fall at `phase + k * period` in track time.
struct AutoMixBeatGrid: Sendable, Equatable {
    let bpm: Double
    let phase: TimeInterval         // offset of the grid, in [0, period)
    let firstStrongBeat: TimeInterval

    var period: TimeInterval { 60.0 / bpm }

    // First beat at or after `t`.
    func beat(atOrAfter t: TimeInterval) -> TimeInterval {
        guard period > 0 else { return t }
        let n = ((t - phase) / period).rounded(.up)
        return phase + max(0, n) * period
    }

    // First downbeat (bar line) at or after `t`, assuming `beatsPerBar` (4/4).
    func downbeat(atOrAfter t: TimeInterval, beatsPerBar: Int = 4) -> TimeInterval {
        let bar = period * Double(max(1, beatsPerBar))
        guard bar > 0 else { return t }
        let n = ((t - phase) / bar).rounded(.up)
        return phase + max(0, n) * bar
    }
}

// Estimated musical key + Camelot-wheel position for harmonic mixing.
struct MusicalKey: Sendable, Equatable {
    let pitchClass: Int    // 0 = C, 1 = C#/Db, ... 11 = B
    let isMajor: Bool

    private static let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    // Camelot number per pitch class for major (B side) and minor (A side).
    private static let majorCamelot = [8, 3, 10, 5, 12, 7, 2, 9, 4, 11, 6, 1]
    private static let minorCamelot = [5, 12, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10]

    var name: String { "\(Self.names[pitchClass]) \(isMajor ? "major" : "minor")" }

    var camelot: String {
        let n = isMajor ? Self.majorCamelot[pitchClass] : Self.minorCamelot[pitchClass]
        return "\(n)\(isMajor ? "B" : "A")"
    }

    private var camelotNumber: Int { isMajor ? Self.majorCamelot[pitchClass] : Self.minorCamelot[pitchClass] }

    // Camelot compatibility, 0...1.
    static func compatibility(_ a: MusicalKey?, _ b: MusicalKey?) -> Double {
        guard let a, let b else { return 0.6 }   // unknown is neutral
        if a == b { return 1.0 }
        let an = a.camelotNumber, bn = b.camelotNumber
        // relative major/minor share the same Camelot number
        if an == bn { return 0.9 }
        let diff = min((an - bn + 12) % 12, (bn - an + 12) % 12)
        if a.isMajor == b.isMajor {
            switch diff {
            case 1: return 0.85   // adjacent on the wheel (perfect fourth/fifth)
            case 2: return 0.55   // usable energy shift
            default: return 0.3
            }
        }
        // crossing major/minor with a number offset is generally a clash
        return diff == 1 ? 0.55 : 0.3
    }
}

// Per-track AutoMix summary. Nil grid/key means plain crossfade fallback.
struct AutoMixTrackAnalysis: Sendable {
    var leadingSilence: TimeInterval = 0
    var trailingSilence: TimeInterval = 0
    var grid: AutoMixBeatGrid? = nil
    var key: MusicalKey? = nil
    // Structure hints; zero/false means unknown:
    var duration: TimeInterval = 0       // full-file duration (0 for streamed prefixes)
    var rms: Float = 0                   // mean envelope level, loudness proxy
    var mixInPoint: TimeInterval = 0     // first sustained-energy entry (skip sparse intro)
    var mixOutPoint: TimeInterval = 0    // last strong moment before the outro decays
    var endsCold: Bool = false           // track stops abruptly at high energy
    // Vocal presence (formant-band heuristic, not true stem separation):
    var vocalIntroStart: TimeInterval? = nil  // first sung moment near the start
    var vocalTailEnd: TimeInterval? = nil     // last sung moment near the end (local files only)

    static let zero = AutoMixTrackAnalysis()
}

// MARK: - Pure DSP math

enum AutoMixDSP {

    // MARK: Beat grid

    // Estimate tempo/phase from an energy envelope.
    static func beatGrid(energy: [AutoMixEnergyPoint], taggedBPM: Double?) -> AutoMixBeatGrid? {
        guard energy.count >= 24 else { return nil }
        let avg = energy.reduce(Float(0)) { $0 + $1.value } / Float(energy.count)
        guard avg > 0 else { return nil }

        // Local-maxima onsets that stand clearly above the rolling average.
        var peaks: [AutoMixEnergyPoint] = []
        for i in 1..<(energy.count - 1) {
            let cur = energy[i]
            guard cur.value > avg * 1.25,
                  cur.value > energy[i - 1].value,
                  cur.value >= energy[i + 1].value else { continue }
            if let last = peaks.last, cur.time - last.time < 0.18 {
                if cur.value > last.value { peaks[peaks.count - 1] = cur }
            } else {
                peaks.append(cur)
            }
        }
        guard peaks.count >= 4 else { return nil }

        let bpm: Double
        if let tagged = taggedBPM, tagged >= 60, tagged <= 210 {
            bpm = foldToTempoRange(tagged)
        } else if let estimated = tempoFromPeaks(peaks) {
            bpm = estimated
        } else {
            return nil
        }
        let period = 60.0 / bpm
        guard period.isFinite, period > 0 else { return nil }

        // Energy-weighted circular mean of onset phases.
        var sx = 0.0, sy = 0.0
        for p in peaks {
            let frac = (p.time.truncatingRemainder(dividingBy: period)) / period
            let ang = 2 * Double.pi * frac
            sx += Double(p.value) * cos(ang)
            sy += Double(p.value) * sin(ang)
        }
        var phase = atan2(sy, sx) / (2 * Double.pi) * period
        if phase < 0 { phase += period }

        // First clearly-strong onset, snapped onto the grid (the musical entry).
        let strongThreshold = avg * 1.3
        let firstStrongRaw = peaks.first(where: { $0.value > strongThreshold })?.time ?? phase
        let snapped = phase + (((firstStrongRaw - phase) / period).rounded()) * period

        return AutoMixBeatGrid(bpm: bpm, phase: phase, firstStrongBeat: max(0, snapped))
    }

    // Nearby onset pairs vote for tempo, folded into 70...180.
    static func tempoFromPeaks(_ peaks: [AutoMixEnergyPoint]) -> Double? {
        guard peaks.count >= 4 else { return nil }
        var bins: [Int: Double] = [:]
        for i in peaks.indices {
            let upper = min(peaks.count, i + 14)
            guard i + 1 < upper else { continue }
            for j in (i + 1)..<upper {
                let interval = peaks[j].time - peaks[i].time
                guard interval >= 0.28, interval <= 2.0 else { continue }
                var bpm = 60.0 / interval
                while bpm < 70 { bpm *= 2 }
                while bpm > 180 { bpm /= 2 }
                guard bpm >= 70, bpm <= 180 else { continue }
                bins[Int(bpm.rounded()), default: 0] += Double(peaks[i].value + peaks[j].value)
            }
        }
        guard let best = bins.max(by: { $0.value < $1.value }),
              best.value > Double(peaks.count) * 0.15 else { return nil }
        return Double(best.key)
    }

    // Fold tempo into a practical working range.
    static func foldToTempoRange(_ bpm: Double) -> Double {
        var b = bpm
        while b < 70 { b *= 2 }
        while b > 180 { b /= 2 }
        return b
    }

    // MARK: Structure (sweet-spot mix points)

    // Smooth to phrase-level shape, not buffer spikes.
    static func smoothedEnergy(_ energy: [AutoMixEnergyPoint], window: TimeInterval = 1.0) -> [AutoMixEnergyPoint] {
        guard energy.count > 2 else { return energy }
        var out = [AutoMixEnergyPoint]()
        out.reserveCapacity(energy.count)
        var lo = 0, hi = 0
        var sum: Double = 0
        for p in energy {
            while hi < energy.count, energy[hi].time <= p.time + window / 2 {
                sum += Double(energy[hi].value); hi += 1
            }
            while lo < hi, energy[lo].time < p.time - window / 2 {
                sum -= Double(energy[lo].value); lo += 1
            }
            let n = max(1, hi - lo)
            out.append(AutoMixEnergyPoint(time: p.time, value: Float(sum / Double(n))))
        }
        return out
    }

    // Body-energy baseline, excluding edges.
    private static func bodyMedian(_ smoothed: [AutoMixEnergyPoint], duration: TimeInterval) -> Float? {
        let upper = duration > 20 ? duration - 5 : .greatestFiniteMagnitude
        let body = smoothed.filter { $0.time >= 8 && $0.time <= upper }.map(\.value).sorted()
        guard body.count >= 16 else { return nil }
        return body[body.count / 2]
    }

    // First sustained energy section; capped so iconic intros survive.
    static func mixInPoint(energy: [AutoMixEnergyPoint], duration: TimeInterval) -> TimeInterval {
        let smoothed = smoothedEnergy(energy)
        guard let median = bodyMedian(smoothed, duration: duration) , median > 0 else { return 0 }
        let threshold = median * 0.75
        let maxSkip: TimeInterval = 16
        // first time the smoothed level reaches threshold AND holds for ~2s
        var idx = 0
        while idx < smoothed.count, smoothed[idx].time <= maxSkip {
            if smoothed[idx].value >= threshold {
                let t = smoothed[idx].time
                let windowEnd = t + 2.0
                var holdSum: Double = 0, holdCount = 0
                var j = idx
                while j < smoothed.count, smoothed[j].time <= windowEnd {
                    holdSum += Double(smoothed[j].value); holdCount += 1; j += 1
                }
                if holdCount > 0, Float(holdSum / Double(holdCount)) >= threshold * 0.85 {
                    // Already hot from the start.
                    return t < 3.0 ? 0 : t
                }
            }
            idx += 1
        }
        return 0
    }

    // Last strong moment before a long decaying outro.
    static func mixOutPoint(energy: [AutoMixEnergyPoint], duration: TimeInterval) -> TimeInterval {
        guard duration > 40 else { return 0 }
        let smoothed = smoothedEnergy(energy)
        guard let last = smoothed.last, last.time >= duration - 8 else { return 0 }  // tail not decoded
        guard let median = bodyMedian(smoothed, duration: duration), median > 0 else { return 0 }
        let threshold = median * 0.55
        var lastStrong: TimeInterval = 0
        for p in smoothed where p.value >= threshold {
            lastStrong = p.time
        }
        guard lastStrong > 20 else { return 0 }
        let outroLength = duration - lastStrong
        // Tiny fades are not worth skipping; cap long ones.
        guard outroLength >= 7 else { return 0 }
        return max(lastStrong + 0.5, duration - 40)
    }

    // Abrupt ending while still loud.
    static func endsCold(energy: [AutoMixEnergyPoint], duration: TimeInterval, trailingSilence: TimeInterval) -> Bool {
        guard duration > 30, trailingSilence < 0.3 else { return false }
        let smoothed = smoothedEnergy(energy)
        guard let median = bodyMedian(smoothed, duration: duration), median > 0 else { return false }
        let tail = smoothed.filter { $0.time >= duration - 1.5 }
        guard !tail.isEmpty else { return false }
        let tailMean = tail.reduce(Float(0)) { $0 + $1.value } / Float(tail.count)
        return tailMean >= median * 0.6
    }

    // MARK: Vocal presence (formant-band heuristic)

    // Heuristic vocal flag: formant-band energy plus a short run requirement.
    private static func vocalActiveFlags(_ frames: [AutoMixSpectralFrame]) -> [Bool]? {
        guard frames.count >= 16 else { return nil }
        let energies = frames.map(\.energy).sorted()
        let loudRef = energies[energies.count * 3 / 4]
        guard loudRef > 0 else { return nil }
        let loud = frames.filter { $0.energy >= loudRef * 0.35 }
        guard loud.count >= 12 else { return nil }
        let ratios = loud.map(\.midRatio).sorted()
        let baseline = ratios[ratios.count / 2]
        let threshold = max(0.35, baseline * 1.15)
        return frames.map { $0.energy >= loudRef * 0.35 && $0.midRatio >= threshold }
    }

    // First time vocals appear to come in (nil = none found / inconclusive).
    static func firstVocalActivity(frames: [AutoMixSpectralFrame], minRun: Int = 3) -> TimeInterval? {
        guard let flags = vocalActiveFlags(frames) else { return nil }
        var run = 0
        for i in flags.indices {
            run = flags[i] ? run + 1 : 0
            if run >= minRun { return frames[i - minRun + 1].time }
        }
        return nil
    }

    // Last time vocals appear to stop (nil = none found / inconclusive).
    static func lastVocalActivity(frames: [AutoMixSpectralFrame], minRun: Int = 3) -> TimeInterval? {
        guard let flags = vocalActiveFlags(frames) else { return nil }
        var run = 0
        for i in flags.indices.reversed() {
            run = flags[i] ? run + 1 : 0
            if run >= minRun { return frames[i + minRun - 1].time }
        }
        return nil
    }

    // MARK: Key (Krumhansl-Schmuckler)

    // Krumhansl-Kessler tonal-hierarchy profiles.
    private static let majorProfile: [Double] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let minorProfile: [Double] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    // Estimate key from a 12-bin chromagram by correlating every rotation of the
    // major and minor profiles and taking the best Pearson correlation.
    static func estimateKey(chroma: [Double]) -> MusicalKey? {
        guard chroma.count == 12 else { return nil }
        let total = chroma.reduce(0, +)
        guard total > 0 else { return nil }

        var best: (corr: Double, pitch: Int, major: Bool)?
        for pitch in 0..<12 {
            let rotated = (0..<12).map { chroma[($0 + pitch) % 12] }
            let cMaj = pearson(rotated, majorProfile)
            let cMin = pearson(rotated, minorProfile)
            if best == nil || cMaj > best!.corr { best = (cMaj, pitch, true) }
            if cMin > best!.corr { best = (cMin, pitch, false) }
        }
        guard let best, best.corr > 0.1 else { return nil }
        return MusicalKey(pitchClass: best.pitch, isMajor: best.major)
    }

    private static func pearson(_ a: [Double], _ b: [Double]) -> Double {
        let n = Double(a.count)
        let ma = a.reduce(0, +) / n
        let mb = b.reduce(0, +) / n
        var num = 0.0, da = 0.0, db = 0.0
        for i in a.indices {
            let xa = a[i] - ma, xb = b[i] - mb
            num += xa * xb; da += xa * xa; db += xb * xb
        }
        let den = (da * db).squareRoot()
        return den > 0 ? num / den : 0
    }
}
