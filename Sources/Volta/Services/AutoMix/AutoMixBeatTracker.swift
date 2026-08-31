import Foundation
import Accelerate

struct AutoMixRhythmResult: Sendable {
    let tempo: AutoMixTempoEstimate?
    let beats: [AutoMixBeat]
    let beatConfidence: Double
    let meter: AutoMixMeterEstimate?
}

enum AutoMixBeatTracker {
    private struct LagCandidate {
        let lag: Double
        let bpm: Double
        let score: Double
    }

    static func track(
        onsetStrength rawOnsets: [Double],
        lowFrequency: [Double],
        harmonicChange: [Double],
        frameRate: Double,
        metadataBPM: Double?,
        coverageSeconds: TimeInterval
    ) -> AutoMixRhythmResult {
        guard frameRate > 0, rawOnsets.count >= Int(frameRate * 8) else {
            return metadataOnlyResult(metadataBPM)
        }

        let onsets = normalizedOnsets(rawOnsets, frameRate: frameRate)
        let candidates = tempoCandidates(onsets: onsets, frameRate: frameRate)
        guard let selected = selectTempoCandidate(candidates, metadataBPM: metadataBPM) else {
            return metadataOnlyResult(metadataBPM)
        }

        let runnerUp = candidates.first { candidate in
            abs(log(candidate.bpm / selected.bpm)) > log(1.08)
                && abs(log(candidate.bpm / selected.bpm)) > abs(log(2)) - 0.08
        } ?? candidates.dropFirst().first
        let dominance = runnerUp.map {
            max(0, (selected.score - $0.score) / max(0.001, selected.score))
        } ?? 1
        let periodicity = min(1, max(0, selected.score))
        let material = min(1, coverageSeconds / 45)
        let windowStability = tempoWindowStability(
            onsets: onsets,
            frameRate: frameRate,
            selectedBPM: selected.bpm
        )
        var tempoConfidence = (
            periodicity * 0.42
                + dominance * 0.22
                + windowStability * 0.24
                + material * 0.12
        ).autoMixClampedConfidence

        let source: AutoMixTempoSource
        if let metadataBPM, metadataBPM > 0 {
            let foldedMetadata = nearestPulse(metadataBPM, to: selected.bpm)
            let consistency = exp(-pow(log(foldedMetadata / selected.bpm) / 0.045, 2))
            if consistency > 0.65 {
                tempoConfidence = min(1, tempoConfidence + consistency * 0.08)
                source = .combined
            } else {
                // Strong audio evidence rejects a contradictory tag. Weak audio
                // remains weak; metadata never manufactures high confidence.
                tempoConfidence *= 0.92
                source = .audio
            }
        } else {
            source = .audio
        }

        let beatResult = dynamicBeats(
            onsets: onsets,
            frameRate: frameRate,
            bpm: selected.bpm,
            tempoConfidence: tempoConfidence
        )
        var beats = beatResult.beats
        let meter = inferMeter(
            beats: beats,
            onsets: onsets,
            lowFrequency: lowFrequency,
            harmonicChange: harmonicChange,
            frameRate: frameRate,
            beatConfidence: beatResult.confidence
        )
        if let meter, let first = meter.firstDownbeatBeatIndex {
            for index in beats.indices {
                let barBeat = ((index - first) % meter.beatsPerBar + meter.beatsPerBar) % meter.beatsPerBar
                beats[index].barBeat = barBeat + 1
                beats[index].isDownbeat = meter.downbeatConfidence >= 0.5 ? barBeat == 0 : nil
            }
        }

        let ambiguity = runnerUp.map { min(1, $0.score / max(0.001, selected.score)) } ?? 0
        let tempo = AutoMixTempoEstimate(
            bpm: selected.bpm,
            confidence: tempoConfidence,
            ambiguity: ambiguity,
            source: source,
            candidates: Array(candidates.prefix(6).enumerated()).map { index, candidate in
                AutoMixTempoCandidate(
                    bpm: candidate.bpm,
                    strength: candidate.score,
                    pulseLevel: index
                )
            }
        )
        return AutoMixRhythmResult(
            tempo: tempo,
            beats: beats,
            beatConfidence: beatResult.confidence,
            meter: meter
        )
    }

    private static func metadataOnlyResult(_ metadataBPM: Double?) -> AutoMixRhythmResult {
        guard let metadataBPM, metadataBPM >= 40, metadataBPM <= 260 else {
            return AutoMixRhythmResult(tempo: nil, beats: [], beatConfidence: 0, meter: nil)
        }
        let folded = nearestPulse(metadataBPM, to: 110)
        return AutoMixRhythmResult(
            tempo: AutoMixTempoEstimate(
                bpm: folded,
                confidence: 0.18,
                ambiguity: 1,
                source: .metadata,
                candidates: [AutoMixTempoCandidate(bpm: folded, strength: 0.18, pulseLevel: 0)]
            ),
            beats: [],
            beatConfidence: 0,
            meter: nil
        )
    }

    static func normalizedOnsets(_ values: [Double], frameRate: Double) -> [Double] {
        guard !values.isEmpty else { return [] }
        let window = max(3, Int(frameRate * 1.5))
        var prefix = [Double](repeating: 0, count: values.count + 1)
        for index in values.indices { prefix[index + 1] = prefix[index] + max(0, values[index]) }
        var normalized = [Double](repeating: 0, count: values.count)
        for index in values.indices {
            let lower = max(0, index - window)
            let upper = min(values.count, index + window + 1)
            let localMean = (prefix[upper] - prefix[lower]) / Double(max(1, upper - lower))
            normalized[index] = max(0, values[index] - localMean * 0.72)
        }
        let sorted = normalized.sorted()
        let scale = sorted[min(sorted.count - 1, sorted.count * 9 / 10)]
        guard scale > 1.0e-12 else { return [Double](repeating: 0, count: values.count) }
        var divisor = scale
        vDSP_vsdivD(normalized, 1, &divisor, &normalized, 1, vDSP_Length(normalized.count))
        for index in normalized.indices { normalized[index] = min(3, normalized[index]) }
        return normalized
    }

    private static func tempoCandidates(onsets: [Double], frameRate: Double) -> [LagCandidate] {
        let minimumLag = max(2, Int((60 * frameRate / 210).rounded(.down)))
        let maximumLag = min(onsets.count / 3, Int((60 * frameRate / 55).rounded(.up)))
        guard maximumLag > minimumLag else { return [] }

        var scores = [Double](repeating: 0, count: maximumLag + 1)
        for lag in minimumLag...maximumLag {
            let count = onsets.count - lag
            var dot = 0.0
            var lhsEnergy = 0.0
            var rhsEnergy = 0.0
            onsets.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                vDSP_dotprD(base + lag, 1, base, 1, &dot, vDSP_Length(count))
                vDSP_svesqD(base + lag, 1, &lhsEnergy, vDSP_Length(count))
                vDSP_svesqD(base, 1, &rhsEnergy, vDSP_Length(count))
            }
            let normalized = dot / max(1.0e-12, sqrt(lhsEnergy * rhsEnergy))
            // Broad preference keeps pulse interpretation musical without
            // deleting valid slow or fast candidates.
            let bpm = 60 * frameRate / Double(lag)
            let centerPreference = exp(-0.5 * pow(log(bpm / 115) / 0.55, 2))
            scores[lag] = normalized * (0.82 + centerPreference * 0.18)
        }

        var peaks: [LagCandidate] = []
        for lag in (minimumLag + 1)..<maximumLag where
            scores[lag] >= scores[lag - 1] && scores[lag] > scores[lag + 1] {
            let y0 = scores[lag - 1], y1 = scores[lag], y2 = scores[lag + 1]
            let denominator = y0 - 2 * y1 + y2
            let offset = abs(denominator) > 1.0e-12 ? 0.5 * (y0 - y2) / denominator : 0
            let refinedLag = Double(lag) + min(0.5, max(-0.5, offset))
            peaks.append(LagCandidate(
                lag: refinedLag,
                bpm: 60 * frameRate / refinedLag,
                score: y1
            ))
        }
        return peaks.sorted { $0.score > $1.score }
    }

    private static func selectTempoCandidate(
        _ candidates: [LagCandidate],
        metadataBPM: Double?
    ) -> LagCandidate? {
        guard !candidates.isEmpty else { return nil }
        guard let metadataBPM, metadataBPM > 0 else { return candidates[0] }
        let bestAudioScore = candidates[0].score
        return candidates.prefix(8).max { lhs, rhs in
            adjustedTempoScore(lhs, metadataBPM: metadataBPM, bestAudioScore: bestAudioScore)
                < adjustedTempoScore(rhs, metadataBPM: metadataBPM, bestAudioScore: bestAudioScore)
        }
    }

    private static func adjustedTempoScore(
        _ candidate: LagCandidate,
        metadataBPM: Double,
        bestAudioScore: Double
    ) -> Double {
        let folded = nearestPulse(metadataBPM, to: candidate.bpm)
        let consistency = exp(-pow(log(folded / candidate.bpm) / 0.05, 2))
        let audioStrength = candidate.score / max(0.001, bestAudioScore)
        let priorWeight = bestAudioScore >= 0.38 ? 0.08 : 0.14
        return audioStrength + consistency * priorWeight
    }

    private static func nearestPulse(_ bpm: Double, to target: Double) -> Double {
        AutoMixTempoMatcher.pulseCandidates(bpm).min {
            abs(log($0 / target)) < abs(log($1 / target))
        } ?? bpm
    }

    private static func tempoWindowStability(
        onsets: [Double],
        frameRate: Double,
        selectedBPM: Double
    ) -> Double {
        let windowFrames = max(Int(frameRate * 20), 64)
        guard onsets.count >= windowFrames * 2 else { return 0.55 }
        var matches: [Double] = []
        var start = 0
        while start + windowFrames <= onsets.count {
            let window = Array(onsets[start..<(start + windowFrames)])
            if let best = tempoCandidates(onsets: window, frameRate: frameRate).first {
                let folded = nearestPulse(best.bpm, to: selectedBPM)
                matches.append(abs(log(folded / selectedBPM)))
            }
            start += windowFrames
        }
        guard !matches.isEmpty else { return 0.45 }
        let agreement = matches.filter { $0 <= log(1.035) }.count
        return Double(agreement) / Double(matches.count)
    }

    private static func dynamicBeats(
        onsets: [Double],
        frameRate: Double,
        bpm: Double,
        tempoConfidence: Double
    ) -> (beats: [AutoMixBeat], confidence: Double) {
        let expected = 60 * frameRate / bpm
        let minimumLag = max(2, Int(expected * 0.68))
        let maximumLag = max(minimumLag + 1, Int(expected * 1.42))
        var score = [Double](repeating: -.greatestFiniteMagnitude, count: onsets.count)
        var previous = [Int](repeating: -1, count: onsets.count)
        let onsetWeight = 1.0
        let transitionWeight = 1.8

        for index in onsets.indices {
            var bestPredecessor = -1
            var bestScore = 0.0
            if index >= minimumLag {
                let lower = max(0, index - maximumLag)
                let upper = index - minimumLag
                if lower <= upper {
                    for candidate in lower...upper where score[candidate].isFinite {
                        let interval = Double(index - candidate)
                        let penalty = transitionWeight * pow(log(interval / expected), 2)
                        let candidateScore = score[candidate] - penalty
                        if candidateScore > bestScore {
                            bestScore = candidateScore
                            bestPredecessor = candidate
                        }
                    }
                }
            }
            score[index] = bestScore + onsets[index] * onsetWeight
            previous[index] = bestPredecessor
        }

        let tailStart = max(0, onsets.count - Int(expected * 2.2))
        guard let end = (tailStart..<onsets.count).max(by: { score[$0] < score[$1] }),
              score[end] > 0 else { return ([], 0) }
        var frameIndices: [Int] = []
        var cursor = end
        while cursor >= 0 {
            frameIndices.append(cursor)
            cursor = previous[cursor]
        }
        frameIndices.reverse()
        guard frameIndices.count >= 4 else { return ([], 0) }

        let intervals = zip(frameIndices.dropFirst(), frameIndices).map { Double($0 - $1) }
        let meanInterval = intervals.reduce(0, +) / Double(intervals.count)
        let variance = intervals.reduce(0) { $0 + pow($1 - meanInterval, 2) } / Double(intervals.count)
        let stability = exp(-sqrt(variance) / max(1, expected * 0.12))
        let supported = frameIndices.filter { onsets[$0] >= 0.35 }.count
        let support = Double(supported) / Double(frameIndices.count)
        let density = min(1, Double(frameIndices.count) / max(1, Double(onsets.count) / expected * 0.55))
        let confidence = min(
            tempoConfidence,
            (support * 0.48 + stability * 0.34 + density * 0.18).autoMixClampedConfidence
        )
        let beats = frameIndices.map { index in
            AutoMixBeat(
                time: Double(index) / frameRate,
                strength: min(1, onsets[index] / 1.5),
                confidence: confidence,
                barBeat: nil,
                isDownbeat: nil
            )
        }
        return (beats, confidence)
    }

    private static func inferMeter(
        beats: [AutoMixBeat],
        onsets: [Double],
        lowFrequency: [Double],
        harmonicChange: [Double],
        frameRate: Double,
        beatConfidence: Double
    ) -> AutoMixMeterEstimate? {
        guard beats.count >= 12, beatConfidence >= 0.35 else { return nil }
        let accents = beats.map { beat -> Double in
            let index = min(onsets.count - 1, max(0, Int((beat.time * frameRate).rounded())))
            let onset = onsets[index]
            let low = index < lowFrequency.count ? lowFrequency[index] : 0
            let harmonic = index < harmonicChange.count ? harmonicChange[index] : 0
            return onset * 0.62 + low * 0.23 + harmonic * 0.15
        }
        let mean = accents.reduce(0, +) / Double(accents.count)
        let deviation = sqrt(accents.reduce(0) { $0 + pow($1 - mean, 2) } / Double(accents.count))
        guard deviation > 0.03 else { return nil }

        var hypotheses: [(meter: Int, phase: Int, score: Double)] = []
        for meter in [3, 4] {
            for phase in 0..<meter {
                var strong: [Double] = []
                var weak: [Double] = []
                for index in accents.indices {
                    if index % meter == phase { strong.append(accents[index]) }
                    else { weak.append(accents[index]) }
                }
                guard strong.count >= 3, !weak.isEmpty else { continue }
                let strongMean = strong.reduce(0, +) / Double(strong.count)
                let weakMean = weak.reduce(0, +) / Double(weak.count)
                let contrast = max(0, (strongMean - weakMean) / deviation)
                let recurrence = strong.filter { $0 >= mean }.count
                let recurrenceScore = Double(recurrence) / Double(strong.count)
                hypotheses.append((meter, phase, contrast * 0.68 + recurrenceScore * 0.32))
            }
        }
        let sorted = hypotheses.sorted { $0.score > $1.score }
        guard let best = sorted.first, best.score >= 0.32 else { return nil }
        let competitor = sorted.first { $0.meter != best.meter || $0.phase != best.phase }?.score ?? 0
        let dominance = max(0, (best.score - competitor) / max(0.001, best.score))
        let meterConfidence = min(beatConfidence, (best.score * 0.5 + dominance * 0.5).autoMixClampedConfidence)
        let downbeatConfidence = min(meterConfidence, (dominance * 0.62 + best.score * 0.38).autoMixClampedConfidence)
        guard meterConfidence >= 0.28 else { return nil }
        return AutoMixMeterEstimate(
            beatsPerBar: best.meter,
            confidence: meterConfidence,
            downbeatConfidence: downbeatConfidence,
            firstDownbeatBeatIndex: best.phase
        )
    }
}
