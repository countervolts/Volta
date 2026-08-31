import Foundation
import XCTest
@testable import Volta

final class AutoMixV2Tests: XCTestCase {
    func testTempoIsDiscoveredWithoutBPMMetadata() {
        let samples = syntheticClicks(bpm: 120, seconds: 32)
        let result = DSPAutoMixAnalyzer.analyzeSamples(
            samples,
            sampleRate: 11_025,
            metadataBPM: nil
        )

        XCTAssertNotNil(result.tempo)
        XCTAssertTrue(pulseEquivalent(result.tempo?.bpm ?? 0, 120, tolerance: 0.04))
        XCTAssertGreaterThan(result.tempo?.confidence ?? 0, 0.45)
        XCTAssertGreaterThan(result.beatConfidence, 0.4)
    }

    func testTempoRangeFromAudio() {
        for bpm in [60.0, 75, 90, 100, 120, 128, 150, 175] {
            let result = DSPAutoMixAnalyzer.analyzeSamples(
                syntheticClicks(bpm: bpm, seconds: 28),
                sampleRate: 11_025
            )
            XCTAssertTrue(
                pulseEquivalent(result.tempo?.bpm ?? 0, bpm, tolerance: 0.055),
                "Expected pulse equivalent to \(bpm), got \(result.tempo?.bpm ?? 0)"
            )
        }
    }

    func testBeatTimestampsFollowSyntheticOnsets() {
        let result = DSPAutoMixAnalyzer.analyzeSamples(
            syntheticClicks(bpm: 100, seconds: 30),
            sampleRate: 11_025
        )
        let period = 0.6
        let errors = result.beats.dropFirst(2).prefix(30).map { beat -> Double in
            let nearest = (beat.time / period).rounded() * period
            return abs(beat.time - nearest)
        }
        XCTAssertFalse(errors.isEmpty)
        XCTAssertLessThan(errors.reduce(0, +) / Double(errors.count), 0.075)
    }

    func testHalfDoubleTempoDoesNotCreateLargeRateChange() {
        let matchA = AutoMixTempoMatcher.match(outgoing: 75, incoming: 150)
        let matchB = AutoMixTempoMatcher.match(outgoing: 90, incoming: 180)

        XCTAssertEqual(matchA?.incomingRate ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(matchB?.incomingRate ?? 0, 1, accuracy: 0.0001)
    }

    func testMeterThreeAndFourAreDetectedSeparately() {
        let three = accentOnsets(beatsPerBar: 3)
        let four = accentOnsets(beatsPerBar: 4)
        let threeResult = AutoMixBeatTracker.track(
            onsetStrength: three.onsets,
            lowFrequency: three.low,
            harmonicChange: three.harmonic,
            frameRate: three.frameRate,
            metadataBPM: nil,
            coverageSeconds: three.seconds
        )
        let fourResult = AutoMixBeatTracker.track(
            onsetStrength: four.onsets,
            lowFrequency: four.low,
            harmonicChange: four.harmonic,
            frameRate: four.frameRate,
            metadataBPM: nil,
            coverageSeconds: four.seconds
        )

        XCTAssertEqual(threeResult.meter?.beatsPerBar, 3)
        XCTAssertEqual(fourResult.meter?.beatsPerBar, 4)
    }

    func testSustainedToneDoesNotProduceConfidentBeatGrid() {
        let sampleRate = 11_025.0
        let samples = (0..<Int(sampleRate * 24)).map { index in
            Float(sin(2 * Double.pi * 220 * Double(index) / sampleRate) * 0.2)
        }
        let result = DSPAutoMixAnalyzer.analyzeSamples(samples, sampleRate: sampleRate)

        XCTAssertLessThan(result.beatConfidence, 0.35)
    }

    func testSilenceAndColdEndingStructure() {
        let silenceFrames = featureFrames(duration: 30) { time in
            time >= 2 && time <= 27 ? 0.2 : 0
        }
        let silence = AutoMixStructureAnalyzer.analyze(
            frames: silenceFrames,
            rhythm: emptyRhythm,
            coverage: fullCoverage(duration: 30),
            duration: 30,
            samplePeak: 0.3
        )
        XCTAssertGreaterThan(silence.leadingSilence, 1.4)
        XCTAssertGreaterThan(silence.trailingSilence, 2.0)

        let cold = AutoMixStructureAnalyzer.analyze(
            frames: featureFrames(duration: 30) { _ in 0.3 },
            rhythm: emptyRhythm,
            coverage: fullCoverage(duration: 30),
            duration: 30,
            samplePeak: 0.5
        )
        XCTAssertGreaterThan(cold.coldEndingLikelihood, 0.6)
    }

    func testKeyConfidenceRejectsNonTonalInput() {
        let uniform = featureFrames(duration: 20, chroma: [Double](repeating: 1.0 / 12, count: 12)) { _ in 0.2 }
        XCTAssertNil(AutoMixKeyAnalyzer.estimate(frames: uniform))

        let cMajorProfile = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
        let total = cMajorProfile.reduce(0, +)
        let tonal = featureFrames(duration: 20, chroma: cMajorProfile.map { $0 / total }) { _ in 0.2 }
        let key = AutoMixKeyAnalyzer.estimate(frames: tonal)
        XCTAssertEqual(key?.key, MusicalKey(pitchClass: 0, isMajor: true))
        XCTAssertGreaterThan(key?.confidence ?? 0, 0.2)
    }

    func testSequentialAlbumAndTrackPairingForceIntendedHandoff() {
        let planner = AutoMixPlanner()
        let first = context(id: "a", album: "album", track: 1)
        let second = context(id: "b", album: "album", track: 2)
        let plan = planner.plan(
            outgoing: first,
            incoming: second,
            outgoingAnalysis: analysis(id: "a", beat: 0.95, downbeat: 0.9),
            incomingAnalysis: analysis(id: "b", beat: 0.95, downbeat: 0.9),
            constraints: constraints(trackPairing: false)
        )
        XCTAssertEqual(plan.type, .intendedGapless)

        let paired = planner.plan(
            outgoing: context(id: "x"),
            incoming: context(id: "y"),
            outgoingAnalysis: analysis(id: "x"),
            incomingAnalysis: analysis(id: "y"),
            constraints: constraints(trackPairing: true)
        )
        XCTAssertEqual(paired.type, .intendedGapless)
    }

    func testLowDownbeatConfidenceCannotProducePhraseMix() {
        let planner = AutoMixPlanner()
        let plan = planner.plan(
            outgoing: context(id: "a"),
            incoming: context(id: "b"),
            outgoingAnalysis: analysis(id: "a", beat: 0.92, downbeat: 0.25),
            incomingAnalysis: analysis(id: "b", beat: 0.91, downbeat: 0.28),
            constraints: constraints()
        )

        XCTAssertNotEqual(plan.type, .phraseMix)
    }

    func testLowConfidenceTempoNeverStretchesAggressively() {
        let planner = AutoMixPlanner()
        let plan = planner.plan(
            outgoing: context(id: "a"),
            incoming: context(id: "b"),
            outgoingAnalysis: analysis(id: "a", bpm: 100, beat: 0.3, downbeat: 0.2),
            incomingAnalysis: analysis(id: "b", bpm: 106, beat: 0.3, downbeat: 0.2),
            constraints: constraints()
        )

        XCTAssertEqual(plan.incomingRate, 1, accuracy: 0.0001)
        XCTAssertEqual(plan.type, .adaptiveCrossfade)
    }

    func testPartialRemoteAnalysisCannotUnlockPhraseMix() {
        var outgoing = analysis(id: "a", beat: 0.9, downbeat: 0.85)
        outgoing = replacingCoverage(outgoing, coverage: AutoMixAnalysisCoverage(
            kind: .headOnly,
            headSeconds: 120,
            tailSeconds: 0,
            duration: 240
        ), structureConfidence: 0.45)
        let planner = AutoMixPlanner()
        let plan = planner.plan(
            outgoing: context(id: "a"),
            incoming: context(id: "b"),
            outgoingAnalysis: outgoing,
            incomingAnalysis: analysis(id: "b", beat: 0.9, downbeat: 0.85),
            constraints: constraints()
        )

        XCTAssertNotEqual(plan.type, .phraseMix)
    }

    func testMinimumEndLeadConstrainsOutgoingCue() {
        let planner = AutoMixPlanner()
        let plan = planner.plan(
            outgoing: context(id: "a"),
            incoming: context(id: "b"),
            outgoingAnalysis: analysis(id: "a", beat: 0.3, downbeat: 0.2),
            incomingAnalysis: analysis(id: "b", beat: 0.3, downbeat: 0.2),
            constraints: constraints()
        )

        XCTAssertLessThanOrEqual(plan.outgoingCue, 232.001)
    }

    private var emptyRhythm: AutoMixRhythmResult {
        AutoMixRhythmResult(tempo: nil, beats: [], beatConfidence: 0, meter: nil)
    }

    private func syntheticClicks(bpm: Double, seconds: Double) -> [Float] {
        let sampleRate = 11_025.0
        var samples = [Float](repeating: 0, count: Int(sampleRate * seconds))
        let period = Int((sampleRate * 60 / bpm).rounded())
        var start = 0
        while start < samples.count {
            for offset in 0..<min(96, samples.count - start) {
                let envelope = exp(-Double(offset) / 18)
                let value = sin(2 * Double.pi * 1_300 * Double(offset) / sampleRate) * envelope
                samples[start + offset] += Float(value * 0.9)
            }
            start += max(1, period)
        }
        return samples
    }

    private func pulseEquivalent(_ actual: Double, _ expected: Double, tolerance: Double) -> Bool {
        AutoMixTempoMatcher.pulseCandidates(actual).contains { lhs in
            AutoMixTempoMatcher.pulseCandidates(expected).contains { rhs in
                abs(lhs / rhs - 1) <= tolerance
            }
        }
    }

    private func accentOnsets(beatsPerBar: Int) -> (
        onsets: [Double], low: [Double], harmonic: [Double], frameRate: Double, seconds: Double
    ) {
        let frameRate = 50.0
        let seconds = 40.0
        var onsets = [Double](repeating: 0, count: Int(frameRate * seconds))
        var low = onsets
        var harmonic = onsets
        let beatFrames = 25
        for beat in 0..<Int(seconds * 2) {
            let index = beat * beatFrames
            guard index < onsets.count else { break }
            let downbeat = beat % beatsPerBar == 0
            onsets[index] = downbeat ? 2.0 : 0.85
            low[index] = downbeat ? 1.0 : 0.2
            harmonic[index] = downbeat ? 0.75 : 0.08
        }
        return (onsets, low, harmonic, frameRate, seconds)
    }

    private func featureFrames(
        duration: Double,
        chroma: [Double] = [1, 0, 0, 0.6, 0, 0.7, 0, 0.8, 0, 0.5, 0, 0],
        energy: (Double) -> Double
    ) -> [AutoMixFeatureFrame] {
        stride(from: 0.0, to: duration, by: 0.1).map { time in
            let value = energy(time)
            return AutoMixFeatureFrame(
                time: time,
                rms: value,
                kWeightedEnergy: value * value,
                peak: value * 1.4,
                onsetStrength: value > 0 ? 0.08 : 0,
                lowFrequencyRatio: value > 0 ? 0.3 : 0,
                midFrequencyRatio: value > 0 ? 0.45 : 0,
                highFrequencyRatio: value > 0 ? 0.25 : 0,
                spectralCentroid: value > 0 ? 1_400 : 0,
                harmonicChange: 0.04,
                chroma: chroma
            )
        }
    }

    private func fullCoverage(duration: Double) -> AutoMixAnalysisCoverage {
        AutoMixAnalysisCoverage(kind: .full, headSeconds: duration, tailSeconds: duration, duration: duration)
    }

    private func context(
        id: String,
        album: String? = nil,
        track: Int? = nil
    ) -> AutoMixTrackContext {
        AutoMixTrackContext(
            id: id,
            title: id,
            albumID: album,
            artistID: nil,
            genre: nil,
            trackNumber: track,
            discNumber: 1,
            duration: 240,
            hasReplayGain: false
        )
    }

    private func constraints(trackPairing: Bool = false) -> AutoMixPlaybackConstraints {
        AutoMixPlaybackConstraints(
            currentTime: 0,
            outgoingDuration: 240,
            incomingReady: true,
            trackPairing: trackPairing,
            replayGainModeEnabled: false,
            style: .balanced,
            maximumOverlap: 11,
            minimumEndLead: 8
        )
    }

    private func analysis(
        id: String,
        bpm: Double = 120,
        beat: Double = 0.9,
        downbeat: Double = 0.8
    ) -> AutoMixTrackAnalysis {
        let beatTimes = stride(from: 0.0, through: 239.5, by: 0.5)
        let beats = beatTimes.enumerated().map { index, time in
            AutoMixBeat(
                time: time,
                strength: index % 4 == 0 ? 1 : 0.65,
                confidence: beat,
                barBeat: index % 4 + 1,
                isDownbeat: downbeat >= 0.5 ? index % 4 == 0 : nil
            )
        }
        let cues = [
            AutoMixCuePoint(time: 0, kind: .audibleStart, confidence: 0.98, energy: 0.5, beatIndex: 0, isDownbeat: true),
            AutoMixCuePoint(time: 8, kind: .phraseBoundary, confidence: downbeat, energy: 0.6, beatIndex: 16, isDownbeat: true),
            AutoMixCuePoint(time: 224, kind: .phraseBoundary, confidence: downbeat, energy: 0.5, beatIndex: 448, isDownbeat: true),
            AutoMixCuePoint(time: 239.5, kind: .audibleEnd, confidence: 0.95, energy: 0.4, beatIndex: 479, isDownbeat: false)
        ]
        return AutoMixTrackAnalysis(
            analysisVersion: AutoMixTrackAnalysis.currentVersion,
            trackID: id,
            sourceFingerprint: id,
            source: .download,
            coverage: fullCoverage(duration: 240),
            duration: 240,
            tempo: AutoMixTempoEstimate(
                bpm: bpm,
                confidence: beat,
                ambiguity: 0.1,
                source: .audio,
                candidates: [AutoMixTempoCandidate(bpm: bpm, strength: beat, pulseLevel: 0)]
            ),
            tempoConfidence: beat,
            beats: beats,
            beatConfidence: beat,
            meter: AutoMixMeterEstimate(
                beatsPerBar: 4,
                confidence: downbeat,
                downbeatConfidence: downbeat,
                firstDownbeatBeatIndex: 0
            ),
            meterConfidence: downbeat,
            downbeatConfidence: downbeat,
            key: nil,
            keyConfidence: 0,
            cuePoints: cues,
            structureConfidence: 0.85,
            leadingSilence: 0,
            trailingSilence: 0,
            coldEndingLikelihood: 0,
            fadeOutLikelihood: 0.2,
            loudness: .unavailable,
            introProfile: .unavailable,
            outroProfile: .unavailable
        )
    }

    private func replacingCoverage(
        _ value: AutoMixTrackAnalysis,
        coverage: AutoMixAnalysisCoverage,
        structureConfidence: Double
    ) -> AutoMixTrackAnalysis {
        AutoMixTrackAnalysis(
            analysisVersion: value.analysisVersion,
            trackID: value.trackID,
            sourceFingerprint: value.sourceFingerprint,
            source: .remotePrefix,
            coverage: coverage,
            duration: value.duration,
            tempo: value.tempo,
            tempoConfidence: value.tempoConfidence,
            beats: value.beats,
            beatConfidence: value.beatConfidence,
            meter: value.meter,
            meterConfidence: value.meterConfidence,
            downbeatConfidence: value.downbeatConfidence,
            key: value.key,
            keyConfidence: value.keyConfidence,
            cuePoints: value.cuePoints,
            structureConfidence: structureConfidence,
            leadingSilence: value.leadingSilence,
            trailingSilence: 0,
            coldEndingLikelihood: 0,
            fadeOutLikelihood: 0,
            loudness: value.loudness,
            introProfile: value.introProfile,
            outroProfile: .unavailable
        )
    }
}
