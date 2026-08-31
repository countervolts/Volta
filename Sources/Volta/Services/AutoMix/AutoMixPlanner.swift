import Foundation

struct AutoMixPlanner: Sendable {
    func plan(
        outgoing: AutoMixTrackContext,
        incoming: AutoMixTrackContext,
        outgoingAnalysis: AutoMixTrackAnalysis,
        incomingAnalysis: AutoMixTrackAnalysis,
        constraints: AutoMixPlaybackConstraints
    ) -> AutoMixTransitionPlan {
        if constraints.trackPairing || outgoing.isSequentialAlbumTrack(before: incoming) {
            let plan = AutoMixTransitionPlan(
                type: .intendedGapless,
                outgoingCue: max(0, constraints.outgoingDuration),
                incomingCue: 0,
                duration: 0,
                incomingRate: 1,
                restoreRateDuration: 0,
                alignedBeatCount: 0,
                alignedBarCount: 0,
                outgoingGainCurve: .linear,
                incomingGainCurve: .linear,
                incomingOverlapAttenuation: 1,
                filters: .bypass,
                confidence: 1,
                reasons: [constraints.trackPairing ? "Track Pairing" : "sequential album handoff"],
                fallbackReason: nil
            )
            AutoMixDiagnostics.logPlan(outgoingID: outgoing.id, incomingID: incoming.id, plan: plan, keyCompatibility: 0.55)
            return plan
        }

        let duration = max(
            constraints.outgoingDuration,
            outgoingAnalysis.duration,
            outgoing.duration
        )
        let audibleEnd = outgoingAnalysis.cuePoints.last(where: {
            $0.kind == .audibleEnd || $0.kind == .coldEnd
        })?.time ?? max(0, duration - outgoingAnalysis.trailingSilence)
        let incomingAudibleStart = incomingAnalysis.cuePoints.first(where: {
            $0.kind == .audibleStart
        })?.time ?? incomingAnalysis.leadingSilence
        let baseIncomingCue = conservativeIncomingCue(
            analysis: incomingAnalysis,
            audibleStart: incomingAudibleStart
        )
        let keyCompatibility = harmonicCompatibility(outgoingAnalysis, incomingAnalysis)
        let tempoMatch = tempoCompatibility(outgoingAnalysis, incomingAnalysis)
        let styleLimit = min(constraints.maximumOverlap, maximumOverlap(for: constraints.style))
        let baseDuration = baseOverlap(for: constraints.style)

        let phraseCapability = min(
            outgoingAnalysis.beatConfidence,
            incomingAnalysis.beatConfidence,
            outgoingAnalysis.tempoConfidence,
            incomingAnalysis.tempoConfidence,
            outgoingAnalysis.downbeatConfidence,
            incomingAnalysis.downbeatConfidence,
            outgoingAnalysis.structureConfidence,
            incomingAnalysis.structureConfidence
        )
        let beatCapability = min(
            outgoingAnalysis.beatConfidence,
            incomingAnalysis.beatConfidence,
            outgoingAnalysis.tempoConfidence,
            incomingAnalysis.tempoConfidence
        )

        var type: AutoMixTransitionType
        var overlap = min(styleLimit, baseDuration)
        var reasons: [String] = []
        var fallbackReason: String?
        var incomingRate: Float = 1
        var bars = 0
        var beats = 0

        let phraseMetersCompatible = outgoingAnalysis.meter?.beatsPerBar == incomingAnalysis.meter?.beatsPerBar
            && outgoingAnalysis.meter?.beatsPerBar != nil
        if phraseCapability >= 0.68,
           phraseMetersCompatible,
           let tempoMatch,
           tempoMatch.absoluteAdjustment <= maximumTempoAdjustment(confidence: phraseCapability),
           phraseCue(analysis: outgoingAnalysis, after: constraints.currentTime + 1.5, before: audibleEnd) != nil,
           phraseCue(analysis: incomingAnalysis, after: baseIncomingCue, before: baseIncomingCue + 50) != nil {
            type = .phraseMix
            incomingRate = tempoMatch.incomingRate
            let meter = outgoingAnalysis.meter?.beatsPerBar ?? 4
            let beatPeriod = 60 / tempoMatch.outgoingBPM
            let requestedBars = constraints.style == .wide ? 4 : (constraints.style == .tight ? 2 : 3)
            bars = max(1, min(requestedBars, Int(styleLimit / max(0.1, beatPeriod * Double(meter)))))
            beats = bars * meter
            overlap = max(2, min(styleLimit, Double(beats) * beatPeriod))
            reasons += ["strong phrase/downbeat evidence", "compatible pulse", "meter \(meter)"]
        } else if beatCapability >= 0.66,
                  let tempoMatch,
                  tempoMatch.absoluteAdjustment <= maximumTempoAdjustment(confidence: beatCapability),
                  beatCue(analysis: outgoingAnalysis, after: constraints.currentTime + 1, before: audibleEnd) != nil,
                  beatCue(analysis: incomingAnalysis, after: baseIncomingCue, before: baseIncomingCue + 45) != nil {
            type = .beatMix
            incomingRate = tempoMatch.incomingRate
            let beatPeriod = 60 / tempoMatch.outgoingBPM
            beats = max(4, Int((min(styleLimit, baseDuration) / beatPeriod).rounded()))
            overlap = max(2, min(styleLimit, Double(beats) * beatPeriod))
            reasons += ["reliable beat sequence", "compatible pulse"]
            if min(outgoingAnalysis.downbeatConfidence, incomingAnalysis.downbeatConfidence) < 0.58 {
                reasons.append("downbeat uncertain; beat sync only")
            }
        } else if outgoingAnalysis.coldEndingLikelihood >= 0.66 {
            type = .tightCut
            overlap = min(1.4, max(0.65, baseDuration * 0.18))
            reasons += ["cold ending", "long overlap would smear attack"]
            fallbackReason = beatCapability < 0.66 ? "rhythmConfidenceInsufficient" : nil
        } else if (outgoingAnalysis.trailingSilence >= 0.35 || incomingAnalysis.leadingSilence >= 0.35),
                  min(outgoingAnalysis.structureConfidence, incomingAnalysis.structureConfidence) < 0.55 {
            type = .silenceTrim
            overlap = min(2.2, max(1.1, baseDuration * 0.3))
            reasons += ["reliable silence boundaries", "musical structure uncertain"]
            fallbackReason = "structureConfidenceInsufficient"
        } else {
            type = .adaptiveCrossfade
            overlap = adaptiveDuration(
                base: baseDuration,
                limit: styleLimit,
                outgoing: outgoingAnalysis,
                incoming: incomingAnalysis,
                keyCompatibility: keyCompatibility
            )
            reasons.append("confidence-aware musical crossfade")
            if beatCapability < 0.66 { reasons.append("beat sync disabled: low confidence") }
            else if tempoMatch == nil { reasons.append("beat sync disabled: incompatible tempo") }
            fallbackReason = beatCapability < 0.66 ? "rhythmConfidenceInsufficient" : "tempoCompatibilityInsufficient"
        }

        if keyCompatibility < 0.38 {
            overlap = max(type == .tightCut ? 0.65 : 1.5, overlap * 0.72)
            reasons.append("harmonic clash; shorter filtered overlap")
        } else if keyCompatibility >= 0.8,
                  min(outgoingAnalysis.keyConfidence, incomingAnalysis.keyConfidence) >= 0.55 {
            overlap = min(styleLimit, overlap * 1.08)
            reasons.append("compatible key")
        }

        if vocalOverlapRisk(outgoingAnalysis, incomingAnalysis) >= 0.62 {
            overlap = min(overlap, 4.2)
            reasons.append("vocal overlap guard")
        }
        overlap = min(
            overlap,
            max(0.65, audibleEnd - max(constraints.currentTime + 0.25, 0))
        )

        let outCue = outgoingCue(
            type: type,
            analysis: outgoingAnalysis,
            currentTime: constraints.currentTime,
            audibleEnd: audibleEnd,
            overlap: overlap,
            minimumEndLead: constraints.minimumEndLead
        )
        let alignedIncomingCue = incomingCue(
            type: type,
            analysis: incomingAnalysis,
            floor: baseIncomingCue
        )
        let pairConfidence = pairConfidence(
            type: type,
            phraseCapability: phraseCapability,
            beatCapability: beatCapability,
            outgoing: outgoingAnalysis,
            incoming: incomingAnalysis
        )
        let attenuation = loudnessAttenuation(
            outgoing: outgoingAnalysis,
            incoming: incomingAnalysis,
            replayGainHandled: constraints.replayGainModeEnabled && incoming.hasReplayGain
        )
        let filters = filters(
            type: type,
            keyCompatibility: keyCompatibility,
            outgoing: outgoingAnalysis,
            incoming: incomingAnalysis
        )
        let curve: AutoMixGainCurve = type == .tightCut ? .tightCut : (type == .adaptiveCrossfade ? .equalPower : .easedEqualPower)
        let plan = AutoMixTransitionPlan(
            type: type,
            outgoingCue: outCue,
            incomingCue: alignedIncomingCue,
            duration: overlap,
            incomingRate: abs(incomingRate - 1) >= 0.006 ? incomingRate : 1,
            restoreRateDuration: abs(incomingRate - 1) >= 0.006 ? 2 : 0,
            alignedBeatCount: beats,
            alignedBarCount: bars,
            outgoingGainCurve: curve,
            incomingGainCurve: curve,
            incomingOverlapAttenuation: attenuation,
            filters: filters,
            confidence: pairConfidence,
            reasons: reasons,
            fallbackReason: fallbackReason
        )
        AutoMixDiagnostics.logPlan(
            outgoingID: outgoing.id,
            incomingID: incoming.id,
            plan: plan,
            keyCompatibility: keyCompatibility
        )
        return plan
    }

    func fixedCrossfade(
        outgoing: AutoMixTrackContext,
        incoming: AutoMixTrackContext,
        currentTime: TimeInterval,
        duration configuredDuration: TimeInterval
    ) -> AutoMixTransitionPlan {
        let duration = min(max(1, configuredDuration), max(1, outgoing.duration - currentTime))
        return AutoMixTransitionPlan(
            type: .adaptiveCrossfade,
            outgoingCue: max(currentTime + 0.1, outgoing.duration - duration),
            incomingCue: 0,
            duration: duration,
            incomingRate: 1,
            restoreRateDuration: 0,
            alignedBeatCount: 0,
            alignedBarCount: 0,
            outgoingGainCurve: .equalPower,
            incomingGainCurve: .equalPower,
            incomingOverlapAttenuation: 1,
            filters: .bypass,
            confidence: 1,
            reasons: ["fixed crossfade"],
            fallbackReason: nil
        )
    }

    private func conservativeIncomingCue(
        analysis: AutoMixTrackAnalysis,
        audibleStart: TimeInterval
    ) -> TimeInterval {
        // Digital silence is safe to trim. Musical material is skipped only for
        // a high-confidence structural entry close to the start.
        let safeStart = max(0, audibleStart - 0.04)
        guard analysis.structureConfidence >= 0.72,
              let entry = analysis.cues([.strongEntry, .phraseBoundary])
                .filter({ $0.time <= 24 && $0.confidence >= 0.78 })
                .min(by: { $0.time < $1.time }),
              entry.time - safeStart <= 16 else { return safeStart }
        return entry.time
    }

    private func outgoingCue(
        type: AutoMixTransitionType,
        analysis: AutoMixTrackAnalysis,
        currentTime: TimeInterval,
        audibleEnd: TimeInterval,
        overlap: TimeInterval,
        minimumEndLead: TimeInterval
    ) -> TimeInterval {
        let earliest = currentTime + 0.35
        let target = max(earliest, audibleEnd - max(overlap, minimumEndLead))
        let latest = max(earliest, min(audibleEnd - 0.35, audibleEnd - minimumEndLead))
        switch type {
        case .phraseMix:
            let candidate = analysis.cues([.phraseBoundary])
                .filter { $0.time >= earliest && $0.time <= latest && $0.confidence >= 0.58 }
                .min { abs($0.time - target) < abs($1.time - target) }
            if let candidate { return candidate.time }
        case .beatMix, .tightCut:
            if let cue = beatCueNear(
                analysis: analysis,
                target: target,
                after: earliest,
                before: latest
            ) { return cue.time }
        case .adaptiveCrossfade:
            let structural = analysis.cues([.outroStart, .sectionBoundary, .phraseBoundary])
                .filter { $0.time >= earliest && $0.time <= latest && $0.confidence >= 0.65 }
                .min { abs($0.time - target) < abs($1.time - target) }
            if let structural { return structural.time }
        case .silenceTrim, .intendedGapless:
            break
        }
        return min(latest, target)
    }

    private func incomingCue(
        type: AutoMixTransitionType,
        analysis: AutoMixTrackAnalysis,
        floor: TimeInterval
    ) -> TimeInterval {
        switch type {
        case .phraseMix:
            return phraseCue(analysis: analysis, after: floor, before: floor + 50)?.time ?? floor
        case .beatMix, .tightCut:
            return beatCue(analysis: analysis, after: floor, before: floor + 45)?.time ?? floor
        default:
            return floor
        }
    }

    private func phraseCue(
        analysis: AutoMixTrackAnalysis,
        after: TimeInterval,
        before: TimeInterval
    ) -> AutoMixCuePoint? {
        analysis.cues([.phraseBoundary])
            .filter { $0.time >= after && $0.time <= before && $0.confidence >= 0.58 }
            .max { $0.confidence < $1.confidence }
    }

    private func beatCue(
        analysis: AutoMixTrackAnalysis,
        after: TimeInterval,
        before: TimeInterval
    ) -> AutoMixCuePoint? {
        guard let beatIndex = analysis.beats.firstIndex(where: { $0.time >= after && $0.time <= before }) else { return nil }
        let preferred = analysis.beats[beatIndex...]
            .prefix { $0.time <= before }
            .enumerated()
            .max { $0.element.strength < $1.element.strength }
        guard let preferred else { return nil }
        let index = beatIndex + preferred.offset
        let beat = preferred.element
        return AutoMixCuePoint(
            time: beat.time,
            kind: beat.isDownbeat == true ? .downbeat : .beat,
            confidence: min(analysis.beatConfidence, beat.confidence),
            energy: beat.strength,
            beatIndex: index,
            isDownbeat: beat.isDownbeat
        )
    }

    private func beatCueNear(
        analysis: AutoMixTrackAnalysis,
        target: TimeInterval,
        after: TimeInterval,
        before: TimeInterval
    ) -> AutoMixCuePoint? {
        guard let index = analysis.beats.indices
            .filter({ analysis.beats[$0].time >= after && analysis.beats[$0].time <= before })
            .min(by: {
                abs(analysis.beats[$0].time - target) < abs(analysis.beats[$1].time - target)
            }) else { return nil }
        let beat = analysis.beats[index]
        return AutoMixCuePoint(
            time: beat.time,
            kind: beat.isDownbeat == true ? .downbeat : .beat,
            confidence: min(analysis.beatConfidence, beat.confidence),
            energy: beat.strength,
            beatIndex: index,
            isDownbeat: beat.isDownbeat
        )
    }

    private func tempoCompatibility(
        _ outgoing: AutoMixTrackAnalysis,
        _ incoming: AutoMixTrackAnalysis
    ) -> AutoMixTempoMatcher.Match? {
        guard let outgoingBPM = outgoing.tempo?.bpm,
              let incomingBPM = incoming.tempo?.bpm else { return nil }
        return AutoMixTempoMatcher.match(outgoing: outgoingBPM, incoming: incomingBPM, maximumAdjustment: 0.06)
    }

    private func maximumTempoAdjustment(confidence: Double) -> Double {
        if confidence >= 0.86 { return 0.04 }
        if confidence >= 0.75 { return 0.03 }
        return 0.02
    }

    private func harmonicCompatibility(
        _ outgoing: AutoMixTrackAnalysis,
        _ incoming: AutoMixTrackAnalysis
    ) -> Double {
        guard let lhs = outgoing.key,
              let rhs = incoming.key,
              min(lhs.confidence, rhs.confidence) >= 0.35 else { return 0.55 }
        let raw = MusicalKey.compatibility(lhs.key, rhs.key)
        let authority = min(lhs.confidence, rhs.confidence)
        return 0.55 + (raw - 0.55) * authority
    }

    private func pairConfidence(
        type: AutoMixTransitionType,
        phraseCapability: Double,
        beatCapability: Double,
        outgoing: AutoMixTrackAnalysis,
        incoming: AutoMixTrackAnalysis
    ) -> Double {
        switch type {
        case .phraseMix:
            return phraseCapability
        case .beatMix:
            return beatCapability
        case .adaptiveCrossfade:
            return min(0.82, 0.42 + min(outgoing.structureConfidence, incoming.structureConfidence) * 0.4)
        case .silenceTrim:
            return 0.78
        case .tightCut:
            return min(0.9, outgoing.coldEndingLikelihood)
        case .intendedGapless:
            return 1
        }
    }

    private func adaptiveDuration(
        base: TimeInterval,
        limit: TimeInterval,
        outgoing: AutoMixTrackAnalysis,
        incoming: AutoMixTrackAnalysis,
        keyCompatibility: Double
    ) -> TimeInterval {
        var duration = base
        let density = max(outgoing.outroProfile.density, incoming.introProfile.density)
        if density >= 0.72 { duration *= 0.74 }
        if keyCompatibility < 0.42 { duration *= 0.78 }
        if outgoing.fadeOutLikelihood >= 0.65, keyCompatibility >= 0.55 { duration *= 1.15 }
        return min(limit, max(2.2, duration))
    }

    private func vocalOverlapRisk(
        _ outgoing: AutoMixTrackAnalysis,
        _ incoming: AutoMixTrackAnalysis
    ) -> Double {
        let confidence = min(outgoing.outroProfile.confidence, incoming.introProfile.confidence)
        return min(outgoing.outroProfile.vocal, incoming.introProfile.vocal) * confidence
    }

    private func loudnessAttenuation(
        outgoing: AutoMixTrackAnalysis,
        incoming: AutoMixTrackAnalysis,
        replayGainHandled: Bool
    ) -> Float {
        guard !replayGainHandled,
              min(outgoing.loudness.confidence, incoming.loudness.confidence) >= 0.45,
              let outgoingLUFS = outgoing.loudness.outroLUFS ?? outgoing.loudness.integratedLUFS,
              let incomingLUFS = incoming.loudness.introLUFS ?? incoming.loudness.integratedLUFS else { return 1 }
        let excess = incomingLUFS - outgoingLUFS
        guard excess > 1 else { return 1 }
        let attenuationDB = -min(6, excess - 0.5)
        return Float(pow(10, attenuationDB / 20))
    }

    private func filters(
        type: AutoMixTransitionType,
        keyCompatibility: Double,
        outgoing: AutoMixTrackAnalysis,
        incoming: AutoMixTrackAnalysis
    ) -> AutoMixFilterPlan {
        guard type == .beatMix || type == .phraseMix || type == .adaptiveCrossfade else { return .bypass }
        let bassRisk = min(outgoing.outroProfile.bass, incoming.introProfile.bass)
            * min(outgoing.outroProfile.confidence, incoming.introProfile.confidence)
        let exchange = type == .beatMix || type == .phraseMix || bassRisk >= 0.3
        let clash = keyCompatibility < 0.4
        guard exchange || clash else { return .bypass }
        return AutoMixFilterPlan(
            outgoingHighPassStartHz: 20,
            outgoingHighPassEndHz: exchange ? 180 : 20,
            outgoingLowPassStartHz: 20_000,
            outgoingLowPassEndHz: clash ? 5_500 : 20_000,
            incomingHighPassStartHz: exchange ? 220 : (clash ? 120 : 20),
            incomingHighPassEndHz: 20,
            incomingLowPassStartHz: clash ? 8_000 : 20_000,
            incomingLowPassEndHz: 20_000
        )
    }

    private func baseOverlap(for style: AutoMixStyle) -> TimeInterval {
        switch style {
        case .tight: 4.5
        case .balanced: 7.5
        case .wide: 11
        }
    }

    private func maximumOverlap(for style: AutoMixStyle) -> TimeInterval {
        switch style {
        case .tight: 7
        case .balanced: 11
        case .wide: 15
        }
    }
}
