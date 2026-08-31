import Foundation

// Volta-owned normalized models. Analyzer backends produce these models;
// planning and playback never depend on backend-specific feature data.

enum AutoMixAnalysisSource: String, Codable, Sendable {
    case download
    case playbackCache
    case localFile
    case remotePrefix
    case unavailable
}

enum AutoMixCoverageKind: String, Codable, Sendable {
    case full
    case headAndTail
    case headOnly
    case unavailable
}

struct AutoMixAnalysisCoverage: Codable, Equatable, Sendable {
    var kind: AutoMixCoverageKind
    var headSeconds: TimeInterval
    var tailSeconds: TimeInterval
    var duration: TimeInterval

    static let unavailable = AutoMixAnalysisCoverage(
        kind: .unavailable,
        headSeconds: 0,
        tailSeconds: 0,
        duration: 0
    )

    var headAvailable: Bool { headSeconds >= 8 }
    var tailAvailable: Bool { kind == .full || kind == .headAndTail }
    var structureConfidenceLimit: Double {
        switch kind {
        case .full: 1
        case .headAndTail: 0.86
        case .headOnly: 0.58
        case .unavailable: 0
        }
    }
}

enum AutoMixTempoSource: String, Codable, Sendable {
    case audio
    case metadata
    case combined
    case unavailable
}

struct AutoMixTempoCandidate: Codable, Equatable, Sendable {
    let bpm: Double
    let strength: Double
    let pulseLevel: Int
}

struct AutoMixTempoEstimate: Codable, Equatable, Sendable {
    let bpm: Double
    let confidence: Double
    let ambiguity: Double
    let source: AutoMixTempoSource
    let candidates: [AutoMixTempoCandidate]
}

struct AutoMixBeat: Codable, Equatable, Sendable {
    let time: TimeInterval
    let strength: Double
    let confidence: Double
    var barBeat: Int?
    var isDownbeat: Bool?
}

struct AutoMixMeterEstimate: Codable, Equatable, Sendable {
    let beatsPerBar: Int
    let confidence: Double
    let downbeatConfidence: Double
    let firstDownbeatBeatIndex: Int?
}

struct MusicalKey: Codable, Equatable, Sendable {
    let pitchClass: Int
    let isMajor: Bool

    private static let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    private static let majorCamelot = [8, 3, 10, 5, 12, 7, 2, 9, 4, 11, 6, 1]
    private static let minorCamelot = [5, 12, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10]

    var name: String {
        let normalized = ((pitchClass % 12) + 12) % 12
        return "\(Self.names[normalized]) \(isMajor ? "major" : "minor")"
    }

    var camelot: String {
        let normalized = ((pitchClass % 12) + 12) % 12
        let number = isMajor ? Self.majorCamelot[normalized] : Self.minorCamelot[normalized]
        return "\(number)\(isMajor ? "B" : "A")"
    }

    private var camelotNumber: Int {
        let normalized = ((pitchClass % 12) + 12) % 12
        return isMajor ? Self.majorCamelot[normalized] : Self.minorCamelot[normalized]
    }

    static func compatibility(_ lhs: MusicalKey?, _ rhs: MusicalKey?) -> Double {
        guard let lhs, let rhs else { return 0.55 }
        if lhs == rhs { return 1 }
        let distance = min(
            (lhs.camelotNumber - rhs.camelotNumber + 12) % 12,
            (rhs.camelotNumber - lhs.camelotNumber + 12) % 12
        )
        if lhs.camelotNumber == rhs.camelotNumber { return 0.92 }
        if lhs.isMajor == rhs.isMajor {
            if distance == 1 { return 0.86 }
            if distance == 2 { return 0.58 }
            return 0.25
        }
        return distance == 1 ? 0.52 : 0.24
    }
}

struct AutoMixKeyEstimate: Codable, Equatable, Sendable {
    let key: MusicalKey
    let confidence: Double
    let runnerUp: MusicalKey?
    let runnerUpScore: Double
    let regionalKeys: [MusicalKey]
}

struct AutoMixLoudness: Codable, Equatable, Sendable {
    let integratedLUFS: Double?
    let introLUFS: Double?
    let outroLUFS: Double?
    let samplePeak: Double
    let headroomDB: Double
    let confidence: Double

    static let unavailable = AutoMixLoudness(
        integratedLUFS: nil,
        introLUFS: nil,
        outroLUFS: nil,
        samplePeak: 0,
        headroomDB: 0,
        confidence: 0
    )
}

struct AutoMixRegionProfile: Codable, Equatable, Sendable {
    let vocal: Double
    let percussion: Double
    let bass: Double
    let density: Double
    let confidence: Double

    static let unavailable = AutoMixRegionProfile(
        vocal: 0,
        percussion: 0,
        bass: 0,
        density: 0,
        confidence: 0
    )
}

enum AutoMixCueKind: String, Codable, CaseIterable, Sendable {
    case audibleStart
    case strongEntry
    case sectionBoundary
    case phraseBoundary
    case breakdown
    case outroStart
    case audibleEnd
    case coldEnd
    case beat
    case downbeat
}

struct AutoMixCuePoint: Codable, Equatable, Sendable {
    let time: TimeInterval
    let kind: AutoMixCueKind
    let confidence: Double
    let energy: Double
    let beatIndex: Int?
    let isDownbeat: Bool?
}

struct AutoMixTrackAnalysis: Codable, Equatable, Sendable {
    static let currentVersion = 2

    let analysisVersion: Int
    let trackID: String
    let sourceFingerprint: String
    let source: AutoMixAnalysisSource
    let coverage: AutoMixAnalysisCoverage
    let duration: TimeInterval
    let tempo: AutoMixTempoEstimate?
    let tempoConfidence: Double
    let beats: [AutoMixBeat]
    let beatConfidence: Double
    let meter: AutoMixMeterEstimate?
    let meterConfidence: Double
    let downbeatConfidence: Double
    let key: AutoMixKeyEstimate?
    let keyConfidence: Double
    let cuePoints: [AutoMixCuePoint]
    let structureConfidence: Double
    let leadingSilence: TimeInterval
    let trailingSilence: TimeInterval
    let coldEndingLikelihood: Double
    let fadeOutLikelihood: Double
    let loudness: AutoMixLoudness
    let introProfile: AutoMixRegionProfile
    let outroProfile: AutoMixRegionProfile

    static func unavailable(trackID: String, fingerprint: String = "") -> AutoMixTrackAnalysis {
        AutoMixTrackAnalysis(
            analysisVersion: currentVersion,
            trackID: trackID,
            sourceFingerprint: fingerprint,
            source: .unavailable,
            coverage: .unavailable,
            duration: 0,
            tempo: nil,
            tempoConfidence: 0,
            beats: [],
            beatConfidence: 0,
            meter: nil,
            meterConfidence: 0,
            downbeatConfidence: 0,
            key: nil,
            keyConfidence: 0,
            cuePoints: [],
            structureConfidence: 0,
            leadingSilence: 0,
            trailingSilence: 0,
            coldEndingLikelihood: 0,
            fadeOutLikelihood: 0,
            loudness: .unavailable,
            introProfile: .unavailable,
            outroProfile: .unavailable
        )
    }

    var estimatedBPM: Double? { tempo?.bpm }
    var musicalKey: MusicalKey? { key?.key }

    func cues(_ kinds: Set<AutoMixCueKind>) -> [AutoMixCuePoint] {
        cuePoints.filter { kinds.contains($0.kind) }
    }

    func beat(atOrAfter time: TimeInterval, downbeatOnly: Bool = false) -> AutoMixBeat? {
        beats.first { beat in
            beat.time >= time && (!downbeatOnly || beat.isDownbeat == true)
        }
    }
}

struct AutoMixTrackContext: Equatable, Sendable {
    let id: String
    let title: String
    let albumID: String?
    let artistID: String?
    let genre: String?
    let trackNumber: Int?
    let discNumber: Int?
    let duration: TimeInterval
    let hasReplayGain: Bool

    func isSequentialAlbumTrack(before next: AutoMixTrackContext) -> Bool {
        guard let albumID, albumID == next.albumID,
              let trackNumber, let nextTrack = next.trackNumber,
              (discNumber ?? 1) == (next.discNumber ?? 1) else { return false }
        return nextTrack == trackNumber + 1
    }
}

enum AutoMixStyle: String, CaseIterable, Codable, Sendable {
    case tight
    case balanced
    case wide

    static var current: AutoMixStyle {
        AutoMixStyle(rawValue: UserDefaults.standard.string(forKey: "automixStyle") ?? "") ?? .balanced
    }
}

struct AutoMixPlaybackConstraints: Equatable, Sendable {
    let currentTime: TimeInterval
    let outgoingDuration: TimeInterval
    let incomingReady: Bool
    let trackPairing: Bool
    let replayGainModeEnabled: Bool
    let style: AutoMixStyle
    let maximumOverlap: TimeInterval
    let minimumEndLead: TimeInterval
}

enum AutoMixTransitionType: String, Codable, CaseIterable, Sendable {
    case intendedGapless
    case silenceTrim
    case adaptiveCrossfade
    case beatMix
    case phraseMix
    case tightCut

    var displayName: String {
        switch self {
        case .intendedGapless: "Intended Gapless"
        case .silenceTrim: "Silence Trim"
        case .adaptiveCrossfade: "Adaptive Crossfade"
        case .beatMix: "Beat Mix"
        case .phraseMix: "Phrase Mix"
        case .tightCut: "Tight Cut"
        }
    }
}

enum AutoMixGainCurve: String, Codable, Sendable {
    case equalPower
    case easedEqualPower
    case tightCut
    case linear
}

struct AutoMixFilterPlan: Codable, Equatable, Sendable {
    let outgoingHighPassStartHz: Double
    let outgoingHighPassEndHz: Double
    let outgoingLowPassStartHz: Double
    let outgoingLowPassEndHz: Double
    let incomingHighPassStartHz: Double
    let incomingHighPassEndHz: Double
    let incomingLowPassStartHz: Double
    let incomingLowPassEndHz: Double

    static let bypass = AutoMixFilterPlan(
        outgoingHighPassStartHz: 20,
        outgoingHighPassEndHz: 20,
        outgoingLowPassStartHz: 20_000,
        outgoingLowPassEndHz: 20_000,
        incomingHighPassStartHz: 20,
        incomingHighPassEndHz: 20,
        incomingLowPassStartHz: 20_000,
        incomingLowPassEndHz: 20_000
    )
}

struct AutoMixTransitionPlan: Codable, Equatable, Sendable {
    let type: AutoMixTransitionType
    let outgoingCue: TimeInterval
    let incomingCue: TimeInterval
    let duration: TimeInterval
    let incomingRate: Float
    let restoreRateDuration: TimeInterval
    let alignedBeatCount: Int
    let alignedBarCount: Int
    let outgoingGainCurve: AutoMixGainCurve
    let incomingGainCurve: AutoMixGainCurve
    let incomingOverlapAttenuation: Float
    let filters: AutoMixFilterPlan
    let confidence: Double
    let reasons: [String]
    let fallbackReason: String?

    var usesDualPlayers: Bool { type != .intendedGapless }
    var isBeatSynchronized: Bool { type == .beatMix || type == .phraseMix }
    var incomingMediaDuration: TimeInterval { duration * Double(max(0.01, incomingRate)) }

    func readinessFallback(outgoingNow: TimeInterval, outgoingDuration: TimeInterval) -> AutoMixTransitionPlan? {
        let remaining = max(0, outgoingDuration - outgoingNow)
        guard remaining >= 1.2 else { return nil }
        let fallbackDuration = min(3.5, max(1.0, remaining - 0.35))
        return AutoMixTransitionPlan(
            type: .adaptiveCrossfade,
            outgoingCue: outgoingNow,
            incomingCue: incomingCue,
            duration: fallbackDuration,
            incomingRate: 1,
            restoreRateDuration: 0,
            alignedBeatCount: 0,
            alignedBarCount: 0,
            outgoingGainCurve: .equalPower,
            incomingGainCurve: .equalPower,
            incomingOverlapAttenuation: incomingOverlapAttenuation,
            filters: .bypass,
            confidence: min(confidence, 0.45),
            reasons: ["incoming became ready late", "safe crossfade"],
            fallbackReason: "incomingNotReady"
        )
    }
}

enum AutoMixTempoMatcher {
    struct Match: Equatable, Sendable {
        let outgoingBPM: Double
        let incomingBPM: Double
        let incomingRate: Float
        let absoluteAdjustment: Double
    }

    static func match(outgoing: Double, incoming: Double, maximumAdjustment: Double = 0.04) -> Match? {
        guard outgoing.isFinite, incoming.isFinite, outgoing > 0, incoming > 0 else { return nil }
        let outgoingCandidates = pulseCandidates(outgoing)
        let incomingCandidates = pulseCandidates(incoming)
        var best: Match?
        for lhs in outgoingCandidates {
            for rhs in incomingCandidates {
                let ratio = lhs / rhs
                let adjustment = abs(ratio - 1)
                guard adjustment <= maximumAdjustment else { continue }
                let candidate = Match(
                    outgoingBPM: lhs,
                    incomingBPM: rhs,
                    incomingRate: Float(ratio),
                    absoluteAdjustment: adjustment
                )
                if best == nil || candidate.absoluteAdjustment < best!.absoluteAdjustment {
                    best = candidate
                }
            }
        }
        return best
    }

    static func pulseCandidates(_ bpm: Double) -> [Double] {
        [bpm / 2, bpm, bpm * 2]
            .filter { $0 >= 55 && $0 <= 210 }
            .reduce(into: [Double]()) { result, value in
                if !result.contains(where: { abs($0 - value) < 0.01 }) { result.append(value) }
            }
    }
}

enum AutoMixGainEnvelope {
    static let segmentCount = 24

    static func outgoing(_ progress: Double, curve: AutoMixGainCurve) -> Float {
        let x = min(1, max(0, progress))
        switch curve {
        case .equalPower:
            return Float(cos(x * .pi / 2))
        case .easedEqualPower:
            let eased = x * x * (3 - 2 * x)
            return Float(cos(eased * .pi / 2))
        case .tightCut:
            return Float(1 - min(1, pow(x, 3) * 1.15))
        case .linear:
            return Float(1 - x)
        }
    }

    static func incoming(
        _ progress: Double,
        curve: AutoMixGainCurve,
        overlapAttenuation: Float
    ) -> Float {
        let x = min(1, max(0, progress))
        let base: Double
        switch curve {
        case .equalPower:
            base = sin(x * .pi / 2)
        case .easedEqualPower:
            let eased = x * x * (3 - 2 * x)
            base = sin(eased * .pi / 2)
        case .tightCut:
            base = min(1, pow(x, 0.35))
        case .linear:
            base = x
        }
        let attenuation = Double(overlapAttenuation) + (1 - Double(overlapAttenuation)) * x
        return Float(base * attenuation)
    }
}

extension Double {
    var autoMixClampedConfidence: Double { min(1, max(0, isFinite ? self : 0)) }
}
