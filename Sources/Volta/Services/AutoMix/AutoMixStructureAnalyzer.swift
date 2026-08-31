import Foundation

enum AutoMixKeyAnalyzer {
    private static let majorProfile = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let minorProfile = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    static func estimate(frames: [AutoMixFeatureFrame]) -> AutoMixKeyEstimate? {
        let usable = frames.filter { $0.rms > 0.001 && $0.chroma.count == 12 }
        guard usable.count >= 24 else { return nil }
        let chroma = combinedChroma(usable)
        let hypotheses = scores(chroma)
        guard hypotheses.count >= 2 else { return nil }
        let best = hypotheses[0]
        let runnerUp = hypotheses[1]
        let concentration = max(0, (chroma.max() ?? 0) - 1.0 / 12.0) * 5.5
        let absolute = max(0, (best.score - 0.05) / 0.75)
        let margin = max(0, (best.score - runnerUp.score) / max(0.05, abs(best.score)))
        let confidence = min(1, concentration * 0.28 + absolute * 0.34 + margin * 0.38)
        guard best.score > 0.12, confidence >= 0.18 else { return nil }

        var regional: [MusicalKey] = []
        let regionCount = 3
        for region in 0..<regionCount {
            let lower = usable.count * region / regionCount
            let upper = usable.count * (region + 1) / regionCount
            guard upper - lower >= 12 else { continue }
            let localScores = scores(combinedChroma(Array(usable[lower..<upper])))
            if let local = localScores.first, local.score >= 0.16 {
                regional.append(local.key)
            }
        }
        return AutoMixKeyEstimate(
            key: best.key,
            confidence: confidence.autoMixClampedConfidence,
            runnerUp: runnerUp.key,
            runnerUpScore: runnerUp.score,
            regionalKeys: regional
        )
    }

    private static func combinedChroma(_ frames: [AutoMixFeatureFrame]) -> [Double] {
        var result = [Double](repeating: 0, count: 12)
        for frame in frames {
            let weight = min(2, max(0.15, sqrt(frame.rms / 0.02)))
            for index in 0..<12 { result[index] += frame.chroma[index] * weight }
        }
        let sum = result.reduce(0, +)
        if sum > 0 { for index in result.indices { result[index] /= sum } }
        return result
    }

    private static func scores(_ chroma: [Double]) -> [(key: MusicalKey, score: Double)] {
        guard chroma.count == 12 else { return [] }
        var output: [(MusicalKey, Double)] = []
        for pitch in 0..<12 {
            let rotated = (0..<12).map { chroma[($0 + pitch) % 12] }
            output.append((MusicalKey(pitchClass: pitch, isMajor: true), pearson(rotated, majorProfile)))
            output.append((MusicalKey(pitchClass: pitch, isMajor: false), pearson(rotated, minorProfile)))
        }
        return output.sorted { $0.1 > $1.1 }
    }

    private static func pearson(_ lhs: [Double], _ rhs: [Double]) -> Double {
        let count = Double(lhs.count)
        let lhsMean = lhs.reduce(0, +) / count
        let rhsMean = rhs.reduce(0, +) / count
        var numerator = 0.0, lhsEnergy = 0.0, rhsEnergy = 0.0
        for index in lhs.indices {
            let x = lhs[index] - lhsMean
            let y = rhs[index] - rhsMean
            numerator += x * y
            lhsEnergy += x * x
            rhsEnergy += y * y
        }
        let denominator = sqrt(lhsEnergy * rhsEnergy)
        return denominator > 1.0e-12 ? numerator / denominator : 0
    }
}

struct AutoMixStructureResult: Sendable {
    let cues: [AutoMixCuePoint]
    let confidence: Double
    let leadingSilence: TimeInterval
    let trailingSilence: TimeInterval
    let audibleEnd: TimeInterval
    let coldEndingLikelihood: Double
    let fadeOutLikelihood: Double
    let loudness: AutoMixLoudness
    let introProfile: AutoMixRegionProfile
    let outroProfile: AutoMixRegionProfile
}

enum AutoMixStructureAnalyzer {
    private struct Region {
        let time: TimeInterval
        let rms: Double
        let kEnergy: Double
        let peak: Double
        let onset: Double
        let low: Double
        let mid: Double
        let high: Double
        let centroid: Double
        let harmonicChange: Double
        let chroma: [Double]
    }

    static func analyze(
        frames: [AutoMixFeatureFrame],
        rhythm: AutoMixRhythmResult,
        coverage: AutoMixAnalysisCoverage,
        duration: TimeInterval,
        samplePeak: Double
    ) -> AutoMixStructureResult {
        guard !frames.isEmpty else {
            return AutoMixStructureResult(
                cues: [], confidence: 0, leadingSilence: 0, trailingSilence: 0,
                audibleEnd: 0, coldEndingLikelihood: 0, fadeOutLikelihood: 0,
                loudness: .unavailable, introProfile: .unavailable, outroProfile: .unavailable
            )
        }
        let regions = aggregate(frames, seconds: 0.75)
        let rmsValues = regions.map(\.rms).sorted()
        let quietReference = rmsValues[min(rmsValues.count - 1, max(0, rmsValues.count / 10))]
        let audibleThreshold = max(0.00035, quietReference * 2.8)
        let firstAudibleIndex = firstSustainedAudible(regions, threshold: audibleThreshold)
        let lastAudibleIndex = lastSustainedAudible(regions, threshold: audibleThreshold)
        let audibleStart = firstAudibleIndex.map { regions[$0].time } ?? 0
        let audibleEnd = lastAudibleIndex.map { regions[$0].time + 0.375 } ?? 0
        let leadingSilence = min(20, max(0, audibleStart))
        let trailingSilence = coverage.tailAvailable
            ? min(20, max(0, duration - audibleEnd))
            : 0

        let novelties = novelty(regions)
        let sortedNovelty = novelties.sorted()
        let noveltyReference = sortedNovelty.isEmpty
            ? 0
            : sortedNovelty[min(sortedNovelty.count - 1, sortedNovelty.count * 3 / 4)]
        let materialConfidence = min(1, Double(regions.count) / 80)
        let confidence = min(
            coverage.structureConfidenceLimit,
            (materialConfidence * 0.45 + min(1, noveltyReference * 2.2) * 0.35 + (coverage.tailAvailable ? 0.2 : 0.08))
        ).autoMixClampedConfidence

        var cues: [AutoMixCuePoint] = []
        if firstAudibleIndex != nil {
            cues.append(AutoMixCuePoint(
                time: audibleStart,
                kind: .audibleStart,
                confidence: 0.97,
                energy: regions[firstAudibleIndex!].rms,
                beatIndex: nearestBeatIndex(to: audibleStart, beats: rhythm.beats),
                isDownbeat: nearestBeat(to: audibleStart, beats: rhythm.beats)?.isDownbeat
            ))
        }

        if let entry = strongEntry(
            regions: regions,
            novelties: novelties,
            audibleStart: audibleStart,
            noveltyReference: noveltyReference
        ) {
            cues.append(cue(
                region: entry.region,
                kind: .strongEntry,
                confidence: min(confidence, entry.confidence),
                beats: rhythm.beats
            ))
        }

        let boundaries = sectionBoundaries(
            regions: regions,
            novelties: novelties,
            reference: noveltyReference,
            confidenceLimit: confidence
        )
        cues.append(contentsOf: boundaries.map {
            cue(region: $0.region, kind: $0.kind, confidence: $0.confidence, beats: rhythm.beats)
        })

        if rhythm.meter?.downbeatConfidence ?? 0 >= 0.62 {
            let phraseCandidates = rhythm.beats.enumerated().compactMap { index, beat -> AutoMixCuePoint? in
                guard beat.isDownbeat == true,
                      let meter = rhythm.meter,
                      index % max(meter.beatsPerBar * 4, 1) == (meter.firstDownbeatBeatIndex ?? 0) % max(meter.beatsPerBar * 4, 1) else {
                    return nil
                }
                let noveltyAtBeat = nearestValue(time: beat.time, regions: regions, values: novelties)
                let cueConfidence = min(
                    meter.downbeatConfidence,
                    confidence * 0.65 + min(1, noveltyAtBeat / max(0.05, noveltyReference)) * 0.35
                )
                guard cueConfidence >= 0.52 else { return nil }
                return AutoMixCuePoint(
                    time: beat.time,
                    kind: .phraseBoundary,
                    confidence: cueConfidence,
                    energy: nearestRegion(to: beat.time, regions: regions)?.rms ?? 0,
                    beatIndex: index,
                    isDownbeat: true
                )
            }
            cues.append(contentsOf: phraseCandidates.prefix(36))
        }

        let ending = endingAnalysis(
            regions: regions,
            duration: duration,
            trailingSilence: trailingSilence,
            tailAvailable: coverage.tailAvailable
        )
        if let outro = ending.outroStart {
            cues.append(cue(
                region: outro,
                kind: .outroStart,
                confidence: min(confidence, ending.fadeLikelihood),
                beats: rhythm.beats
            ))
        }
        if coverage.tailAvailable, let lastAudibleIndex {
            cues.append(AutoMixCuePoint(
                time: audibleEnd,
                kind: ending.coldLikelihood >= 0.62 ? .coldEnd : .audibleEnd,
                confidence: max(0.65, min(0.98, confidence + 0.18)),
                energy: regions[lastAudibleIndex].rms,
                beatIndex: nearestBeatIndex(to: audibleEnd, beats: rhythm.beats),
                isDownbeat: nearestBeat(to: audibleEnd, beats: rhythm.beats)?.isDownbeat
            ))
        }

        let loudness = loudness(
            frames: frames,
            coverage: coverage,
            duration: duration,
            samplePeak: samplePeak
        )
        let introEnd = min(duration > 0 ? duration : 45, max(audibleStart + 12, 35))
        let introFrames = frames.filter { $0.time >= audibleStart && $0.time <= introEnd }
        let tailStart = max(audibleStart, (duration > 0 ? duration : audibleEnd) - 35)
        let outroFrames = coverage.tailAvailable ? frames.filter { $0.time >= tailStart } : []

        return AutoMixStructureResult(
            cues: deduplicatedCues(cues),
            confidence: confidence,
            leadingSilence: leadingSilence,
            trailingSilence: trailingSilence,
            audibleEnd: audibleEnd,
            coldEndingLikelihood: ending.coldLikelihood,
            fadeOutLikelihood: ending.fadeLikelihood,
            loudness: loudness,
            introProfile: profile(introFrames),
            outroProfile: profile(outroFrames)
        )
    }

    private static func aggregate(_ frames: [AutoMixFeatureFrame], seconds: TimeInterval) -> [Region] {
        guard let first = frames.first else { return [] }
        var output: [Region] = []
        var bucketStart = floor(first.time / seconds) * seconds
        var bucket: [AutoMixFeatureFrame] = []

        func makeRegion(_ frames: [AutoMixFeatureFrame], start: TimeInterval) -> Region? {
            guard !frames.isEmpty else { return nil }
            let count = Double(frames.count)
            var chroma = [Double](repeating: 0, count: 12)
            for frame in frames where frame.chroma.count == 12 {
                for index in 0..<12 { chroma[index] += frame.chroma[index] }
            }
            let chromaTotal = chroma.reduce(0, +)
            if chromaTotal > 0 { for index in chroma.indices { chroma[index] /= chromaTotal } }
            return Region(
                time: start + seconds / 2,
                rms: sqrt(frames.reduce(0) { $0 + $1.rms * $1.rms } / count),
                kEnergy: frames.reduce(0) { $0 + $1.kWeightedEnergy } / count,
                peak: frames.map(\.peak).max() ?? 0,
                onset: frames.reduce(0) { $0 + $1.onsetStrength } / count,
                low: frames.reduce(0) { $0 + $1.lowFrequencyRatio } / count,
                mid: frames.reduce(0) { $0 + $1.midFrequencyRatio } / count,
                high: frames.reduce(0) { $0 + $1.highFrequencyRatio } / count,
                centroid: frames.reduce(0) { $0 + $1.spectralCentroid } / count,
                harmonicChange: frames.reduce(0) { $0 + $1.harmonicChange } / count,
                chroma: chroma
            )
        }

        for frame in frames {
            if frame.time >= bucketStart + seconds || frame.time < bucketStart {
                if let region = makeRegion(bucket, start: bucketStart) { output.append(region) }
                bucketStart = floor(frame.time / seconds) * seconds
                bucket.removeAll(keepingCapacity: true)
            }
            bucket.append(frame)
        }
        if let region = makeRegion(bucket, start: bucketStart) { output.append(region) }
        return output
    }

    private static func firstSustainedAudible(_ regions: [Region], threshold: Double) -> Int? {
        guard regions.count >= 2 else { return regions.firstIndex { $0.rms >= threshold } }
        for index in 0..<(regions.count - 1) where
            regions[index].rms >= threshold && regions[index + 1].rms >= threshold * 0.7 {
            return index
        }
        return nil
    }

    private static func lastSustainedAudible(_ regions: [Region], threshold: Double) -> Int? {
        guard regions.count >= 2 else { return regions.lastIndex { $0.rms >= threshold } }
        for index in (1..<regions.count).reversed() where
            regions[index].rms >= threshold && regions[index - 1].rms >= threshold * 0.7 {
            return index
        }
        return nil
    }

    private static func novelty(_ regions: [Region]) -> [Double] {
        guard !regions.isEmpty else { return [] }
        var values = [Double](repeating: 0, count: regions.count)
        for index in 1..<regions.count {
            let lhs = regions[index - 1]
            let rhs = regions[index]
            if rhs.time - lhs.time > 2 { continue }
            let energy = abs(log10(max(1.0e-7, rhs.rms)) - log10(max(1.0e-7, lhs.rms)))
            let centroid = abs(rhs.centroid - lhs.centroid) / max(500, max(rhs.centroid, lhs.centroid))
            let harmonic = cosineDistance(lhs.chroma, rhs.chroma)
            let density = abs(rhs.onset - lhs.onset) / max(1.0e-6, max(rhs.onset, lhs.onset))
            values[index] = min(2, energy * 0.34 + centroid * 0.18 + harmonic * 0.3 + density * 0.18)
        }
        return smoothed(values)
    }

    private static func strongEntry(
        regions: [Region],
        novelties: [Double],
        audibleStart: TimeInterval,
        noveltyReference: Double
    ) -> (region: Region, confidence: Double)? {
        let body = regions.filter { $0.time >= audibleStart + 8 && $0.time <= audibleStart + 90 }.map(\.rms).sorted()
        guard body.count >= 8 else { return nil }
        let median = body[body.count / 2]
        for index in regions.indices where regions[index].time <= audibleStart + 45 {
            let region = regions[index]
            guard region.time >= audibleStart + 2,
                  region.rms >= median * 0.72,
                  novelties[index] >= max(0.08, noveltyReference * 0.7) else { continue }
            let previous = index > 0 ? regions[index - 1].rms : region.rms
            let contrast = min(1, region.rms / max(1.0e-5, previous) / 3)
            let confidence = min(0.9, 0.42 + contrast * 0.25 + min(1, novelties[index]) * 0.3)
            return (region, confidence)
        }
        return nil
    }

    private static func sectionBoundaries(
        regions: [Region],
        novelties: [Double],
        reference: Double,
        confidenceLimit: Double
    ) -> [(region: Region, kind: AutoMixCueKind, confidence: Double)] {
        guard regions.count >= 5 else { return [] }
        var output: [(Region, AutoMixCueKind, Double)] = []
        var lastTime = -TimeInterval.greatestFiniteMagnitude
        for index in 2..<(regions.count - 2) {
            guard regions[index].time - lastTime >= 4,
                  novelties[index] >= max(0.11, reference * 1.05),
                  novelties[index] >= novelties[index - 1],
                  novelties[index] >= novelties[index + 1] else { continue }
            let localEnergy = regions[index].rms
            let neighbours = (regions[index - 1].rms + regions[index + 1].rms) / 2
            let kind: AutoMixCueKind = localEnergy < neighbours * 0.65 ? .breakdown : .sectionBoundary
            let cueConfidence = min(confidenceLimit, 0.4 + min(1, novelties[index] / max(0.1, reference * 2)) * 0.5)
            output.append((regions[index], kind, cueConfidence))
            lastTime = regions[index].time
        }
        return Array(output.sorted { $0.2 > $1.2 }.prefix(32)).sorted { $0.0.time < $1.0.time }
    }

    private static func endingAnalysis(
        regions: [Region],
        duration: TimeInterval,
        trailingSilence: TimeInterval,
        tailAvailable: Bool
    ) -> (coldLikelihood: Double, fadeLikelihood: Double, outroStart: Region?) {
        guard tailAvailable, duration > 20 else { return (0, 0, nil) }
        let tail = regions.filter { $0.time >= duration - 45 }
        let body = regions.filter { $0.time >= min(20, duration * 0.15) && $0.time <= duration - 20 }.map(\.rms).sorted()
        guard tail.count >= 5, body.count >= 5 else { return (0, 0, nil) }
        let bodyMedian = body[body.count / 2]
        let final = tail.suffix(2).map(\.rms).reduce(0, +) / Double(min(2, tail.count))
        let cold = trailingSilence < 0.3
            ? min(1, final / max(1.0e-5, bodyMedian) * 0.9)
            : 0

        let xs = tail.map(\.time)
        let ys = tail.map { log10(max(1.0e-7, $0.rms)) }
        let slope = linearSlope(xs: xs, ys: ys)
        let totalDrop = max(0, (ys.first ?? 0) - (ys.last ?? 0))
        let fade = min(1, max(0, -slope * 18) * 0.55 + min(1, totalDrop / 1.2) * 0.45)
        var outro: Region?
        if fade >= 0.42 {
            let threshold = bodyMedian * 0.72
            outro = tail.first { $0.rms < threshold }
        }
        return (cold.autoMixClampedConfidence, fade.autoMixClampedConfidence, outro)
    }

    private static func loudness(
        frames: [AutoMixFeatureFrame],
        coverage: AutoMixAnalysisCoverage,
        duration: TimeInterval,
        samplePeak: Double
    ) -> AutoMixLoudness {
        let energies = frames.map(\.kWeightedEnergy).filter { $0 > 0 && $0.isFinite }
        guard !energies.isEmpty else { return .unavailable }
        let ungated = -0.691 + 10 * log10(max(1.0e-12, energies.reduce(0, +) / Double(energies.count)))
        let absoluteGated = energies.filter { -0.691 + 10 * log10(max(1.0e-12, $0)) >= -70 }
        let relativeThreshold = ungated - 10
        let gated = absoluteGated.filter { -0.691 + 10 * log10(max(1.0e-12, $0)) >= relativeThreshold }
        let integratedEnergy = (gated.isEmpty ? absoluteGated : gated).reduce(0, +)
            / Double(max(1, (gated.isEmpty ? absoluteGated : gated).count))
        let integrated = -0.691 + 10 * log10(max(1.0e-12, integratedEnergy))
        let intro = regionLUFS(frames.filter { $0.time <= min(35, duration > 0 ? duration : 35) })
        let outro = coverage.tailAvailable
            ? regionLUFS(frames.filter { $0.time >= max(0, duration - 35) })
            : nil
        let peak = min(8, max(0, samplePeak))
        let headroom = peak > 0 ? -20 * log10(peak) : 0
        let confidence = min(coverage.structureConfidenceLimit, min(1, Double(energies.count) / 1_200))
        return AutoMixLoudness(
            integratedLUFS: integrated.isFinite ? integrated : nil,
            introLUFS: intro,
            outroLUFS: outro,
            samplePeak: peak,
            headroomDB: headroom,
            confidence: confidence
        )
    }

    private static func regionLUFS(_ frames: [AutoMixFeatureFrame]) -> Double? {
        let energies = frames.map(\.kWeightedEnergy).filter { $0 > 0 && $0.isFinite }
        guard !energies.isEmpty else { return nil }
        let mean = energies.reduce(0, +) / Double(energies.count)
        let value = -0.691 + 10 * log10(max(1.0e-12, mean))
        return value.isFinite ? value : nil
    }

    private static func profile(_ frames: [AutoMixFeatureFrame]) -> AutoMixRegionProfile {
        guard frames.count >= 12 else { return .unavailable }
        let count = Double(frames.count)
        let mid = frames.reduce(0) { $0 + $1.midFrequencyRatio } / count
        let low = frames.reduce(0) { $0 + $1.lowFrequencyRatio } / count
        let high = frames.reduce(0) { $0 + $1.highFrequencyRatio } / count
        let onsetValues = frames.map(\.onsetStrength).sorted()
        let onsetReference = onsetValues[onsetValues.count * 3 / 4]
        let harmonic = frames.reduce(0) { $0 + $1.harmonicChange } / count
        let vocal = min(1, max(0, (mid - 0.28) * 2.1) * (1 - min(0.6, high)))
        let percussion = min(1, onsetReference * 14 + high * 0.25)
        let bass = min(1, low * 2.3)
        let density = min(1, onsetReference * 8 + harmonic * 0.55 + frames.map(\.rms).max()! * 1.2)
        return AutoMixRegionProfile(
            vocal: vocal,
            percussion: percussion,
            bass: bass,
            density: density,
            // Handcrafted activity estimates inform planning but never receive
            // neural-detector authority.
            confidence: min(0.62, 0.35 + min(1, count / 400) * 0.27)
        )
    }

    private static func cue(
        region: Region,
        kind: AutoMixCueKind,
        confidence: Double,
        beats: [AutoMixBeat]
    ) -> AutoMixCuePoint {
        let beatIndex = nearestBeatIndex(to: region.time, beats: beats)
        return AutoMixCuePoint(
            time: region.time,
            kind: kind,
            confidence: confidence.autoMixClampedConfidence,
            energy: region.rms,
            beatIndex: beatIndex,
            isDownbeat: beatIndex.map { beats[$0].isDownbeat } ?? nil
        )
    }

    private static func nearestBeatIndex(to time: TimeInterval, beats: [AutoMixBeat]) -> Int? {
        guard !beats.isEmpty else { return nil }
        return beats.indices.min { abs(beats[$0].time - time) < abs(beats[$1].time - time) }
    }

    private static func nearestBeat(to time: TimeInterval, beats: [AutoMixBeat]) -> AutoMixBeat? {
        nearestBeatIndex(to: time, beats: beats).map { beats[$0] }
    }

    private static func nearestRegion(to time: TimeInterval, regions: [Region]) -> Region? {
        regions.min { abs($0.time - time) < abs($1.time - time) }
    }

    private static func nearestValue(
        time: TimeInterval,
        regions: [Region],
        values: [Double]
    ) -> Double {
        guard let index = regions.indices.min(by: {
            abs(regions[$0].time - time) < abs(regions[$1].time - time)
        }), values.indices.contains(index) else { return 0 }
        return values[index]
    }

    private static func deduplicatedCues(_ cues: [AutoMixCuePoint]) -> [AutoMixCuePoint] {
        let sorted = cues.sorted {
            if abs($0.time - $1.time) > 0.35 { return $0.time < $1.time }
            return $0.confidence > $1.confidence
        }
        var result: [AutoMixCuePoint] = []
        for cue in sorted {
            if let last = result.last,
               abs(last.time - cue.time) < 0.35,
               last.kind == cue.kind {
                if cue.confidence > last.confidence { result[result.count - 1] = cue }
            } else {
                result.append(cue)
            }
        }
        return Array(result.prefix(96))
    }

    private static func smoothed(_ values: [Double]) -> [Double] {
        guard values.count >= 3 else { return values }
        var output = values
        for index in 1..<(values.count - 1) {
            output[index] = values[index - 1] * 0.25 + values[index] * 0.5 + values[index + 1] * 0.25
        }
        return output
    }

    private static func cosineDistance(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var dot = 0.0, lhsEnergy = 0.0, rhsEnergy = 0.0
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            lhsEnergy += lhs[index] * lhs[index]
            rhsEnergy += rhs[index] * rhs[index]
        }
        let denominator = sqrt(lhsEnergy * rhsEnergy)
        return denominator > 1.0e-12 ? max(0, 1 - dot / denominator) : 0
    }

    private static func linearSlope(xs: [Double], ys: [Double]) -> Double {
        guard xs.count == ys.count, xs.count >= 2 else { return 0 }
        let count = Double(xs.count)
        let xMean = xs.reduce(0, +) / count
        let yMean = ys.reduce(0, +) / count
        var numerator = 0.0, denominator = 0.0
        for index in xs.indices {
            numerator += (xs[index] - xMean) * (ys[index] - yMean)
            denominator += pow(xs[index] - xMean, 2)
        }
        return denominator > 0 ? numerator / denominator : 0
    }
}

enum AutoMixDiagnostics {
    static func logAnalysis(_ analysis: AutoMixTrackAnalysis) {
        let tempo = analysis.tempo.map { String(format: "%.2f", $0.bpm) } ?? "none"
        let tempoSource = analysis.tempo?.source.rawValue ?? "unavailable"
        let key = analysis.key?.key.camelot ?? "none"
        AppLogger.shared.log(
            "AutoMix analysis: songID=\(analysis.trackID); source=\(analysis.source.rawValue); coverage=\(analysis.coverage.kind.rawValue); tempo=\(tempo); tempoSource=\(tempoSource); tempoConfidence=\(percent(analysis.tempoConfidence)); beatConfidence=\(percent(analysis.beatConfidence)); meter=\(analysis.meter?.beatsPerBar.description ?? "none"); meterConfidence=\(percent(analysis.meterConfidence)); downbeatConfidence=\(percent(analysis.downbeatConfidence)); key=\(key); keyConfidence=\(percent(analysis.keyConfidence)); leadingSilence=\(seconds(analysis.leadingSilence)); trailingSilence=\(seconds(analysis.trailingSilence)); cueCount=\(analysis.cuePoints.count); structureConfidence=\(percent(analysis.structureConfidence))",
            category: .playback
        )
    }

    static func logPlan(
        outgoingID: String,
        incomingID: String,
        plan: AutoMixTransitionPlan,
        keyCompatibility: Double
    ) {
        AppLogger.shared.log(
            "AutoMix planner: A=\(outgoingID); B=\(incomingID); type=\(plan.type.rawValue); confidence=\(percent(plan.confidence)); outCue=\(seconds(plan.outgoingCue)); inCue=\(seconds(plan.incomingCue)); duration=\(seconds(plan.duration)); tempoAdjust=\(String(format: "%+.2f%%", (Double(plan.incomingRate) - 1) * 100)); keyCompatibility=\(percent(keyCompatibility)); reason=\(plan.reasons.joined(separator: "|")); fallback=\(plan.fallbackReason ?? "none")",
            category: .playback
        )
    }

    static func logFallback(planned: AutoMixTransitionType, actual: AutoMixTransitionType?, reason: String) {
        AppLogger.shared.log(
            "AutoMix fallback: planned=\(planned.rawValue); actual=\(actual?.rawValue ?? "trackEnd"); reason=\(reason)",
            category: .playback,
            level: .warning
        )
    }

    private static func percent(_ value: Double) -> String { String(format: "%.0f%%", value * 100) }
    private static func seconds(_ value: TimeInterval) -> String { String(format: "%.3f", value) }
}
