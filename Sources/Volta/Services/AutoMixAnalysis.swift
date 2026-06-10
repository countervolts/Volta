import Foundation

// MARK: - AutoMix musical analysis types + pure DSP math
//
// This file holds the *pure* musical-analysis math behind Volta's AutoMix engine
// (the audio decode + FFT live in the analyzer actor in AudioPlayer.swift, which
// hands the cheap summaries — an energy envelope and a 12-bin chromagram — to the
// pure functions here). Keeping the math pure makes the beat-matching and harmonic
// logic easy to reason about and reuse from both the live engine and the Settings
// preview.
//
// What we model, to mirror Apple Music's AutoMix as closely as we can on-device:
//   • a BEAT GRID per track (tempo + phase + the first strong beat) so we can line
//     up *downbeats*, not just match tempo — that phase lock is what makes a blend
//     sound DJ-mixed instead of merely crossfaded;
//   • a MUSICAL KEY per track (Krumhansl–Schmuckler key-finding over a chromagram)
//     plus Camelot-wheel compatibility, so harmonically clashing pairs get a
//     shorter/cleaner handover and compatible pairs get a longer blended mix —
//     Apple "opts not to create a transition if a seamless one is not available."

// One short-time energy reading from the decoded audio (envelope point).
struct AutoMixEnergyPoint: Sendable {
    let time: TimeInterval
    let value: Float
}

// A track's beat grid: beats fall at `phase + k * period` (track time, seconds).
// `firstStrongBeat` is the first musically prominent beat (used to skip soft
// intros so the incoming track "drops" on the beat rather than on dead air).
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
    let pitchClass: Int    // 0 = C, 1 = C#/Db … 11 = B
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

    // Harmonic compatibility on the Camelot wheel, 0…1. 1 = same key, ~0.9 =
    // relative major/minor, ~0.85 = adjacent (±1 / dominant), down to ~0.3 for a
    // clash. Used to scale how much the two tracks should overlap.
    static func compatibility(_ a: MusicalKey?, _ b: MusicalKey?) -> Double {
        guard let a, let b else { return 0.6 }   // unknown → neutral
        if a == b { return 1.0 }
        let an = a.camelotNumber, bn = b.camelotNumber
        // relative major/minor share the same Camelot number
        if an == bn { return 0.9 }
        let diff = min((an - bn + 12) % 12, (bn - an + 12) % 12)
        if a.isMajor == b.isMajor {
            switch diff {
            case 1: return 0.85   // adjacent on the wheel (perfect fourth/fifth)
            case 2: return 0.55   // a whole step around — usable energy shift
            default: return 0.3
            }
        }
        // crossing major/minor with a number offset is generally a clash
        return diff == 1 ? 0.55 : 0.3
    }
}

// Full per-track AutoMix analysis. Silence is in seconds at each end; grid/key are
// nil when the track couldn't be analysed (e.g. ambient/arrhythmic material), in
// which case the engine falls back to a plain crossfade.
struct AutoMixTrackAnalysis: Sendable {
    var leadingSilence: TimeInterval = 0
    var trailingSilence: TimeInterval = 0
    var grid: AutoMixBeatGrid? = nil
    var key: MusicalKey? = nil

    static let zero = AutoMixTrackAnalysis()
}

// MARK: - Pure DSP math

enum AutoMixDSP {

    // MARK: Beat grid

    // Estimate a beat grid (tempo + phase + first strong beat) from an energy
    // envelope. When `taggedBPM` is supplied (file metadata) it's trusted for the
    // tempo and we only solve for phase; otherwise tempo is found from inter-onset
    // intervals. Phase is the energy-weighted circular mean of the onsets folded
    // into one beat period — i.e. where the beats actually sit.
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

        // Energy-weighted circular mean of onset phases → grid offset.
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

    // Tempo from an inter-onset-interval histogram (same approach as the original
    // estimator: every nearby onset pair votes for a tempo, folded into 70…180).
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

    // Octave-fold a tempo into a sensible 70…140 working range.
    static func foldToTempoRange(_ bpm: Double) -> Double {
        var b = bpm
        while b < 70 { b *= 2 }
        while b > 180 { b /= 2 }
        return b
    }

    // MARK: Key (Krumhansl–Schmuckler)

    // Krumhansl–Kessler tonal-hierarchy profiles (major / minor).
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
