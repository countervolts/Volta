import Foundation
import AVFoundation
import os

struct AutoMixTransitionFilterDescriptor: Sendable {
    let mediaStart: TimeInterval
    let mediaDuration: TimeInterval
    let highPassStartHz: Double
    let highPassEndHz: Double
    let lowPassStartHz: Double
    let lowPassEndHz: Double

    var isBypassed: Bool {
        highPassStartHz <= 21 && highPassEndHz <= 21
            && lowPassStartHz >= 19_000 && lowPassEndHz >= 19_000
    }
}

protocol AutoMixTransitionDSPContext: AnyObject {
    func stageAutoMixFilter(_ descriptor: AutoMixTransitionFilterDescriptor?)
}

final class AutoMixTransitionDSP: @unchecked Sendable {
    static let shared = AutoMixTransitionDSP()

    private final class WeakContext {
        weak var value: AutoMixTransitionDSPContext?
        init(_ value: AutoMixTransitionDSPContext) { self.value = value }
    }

    private var lock = os_unfair_lock_s()
    private var nextChannelID: UInt64 = 1
    private var descriptors: [UInt64: AutoMixTransitionFilterDescriptor] = [:]
    private var contexts: [UInt64: [WeakContext]] = [:]

    func reserveChannel() -> UInt64 {
        os_unfair_lock_lock(&lock)
        let id = nextChannelID
        nextChannelID &+= 1
        os_unfair_lock_unlock(&lock)
        return id
    }

    func register(channelID: UInt64, context: AutoMixTransitionDSPContext) {
        guard channelID != 0 else { return }
        os_unfair_lock_lock(&lock)
        var current = contexts[channelID, default: []]
        current.removeAll { $0.value == nil }
        current.append(WeakContext(context))
        contexts[channelID] = current
        let descriptor = descriptors[channelID]
        os_unfair_lock_unlock(&lock)
        context.stageAutoMixFilter(descriptor)
    }

    func descriptor(channelID: UInt64) -> AutoMixTransitionFilterDescriptor? {
        os_unfair_lock_lock(&lock)
        let descriptor = descriptors[channelID]
        os_unfair_lock_unlock(&lock)
        return descriptor
    }

    func configure(channelID: UInt64, descriptor: AutoMixTransitionFilterDescriptor) {
        guard channelID != 0 else { return }
        os_unfair_lock_lock(&lock)
        descriptors[channelID] = descriptor
        var current = contexts[channelID, default: []]
        current.removeAll { $0.value == nil }
        contexts[channelID] = current
        let live = current.compactMap(\.value)
        os_unfair_lock_unlock(&lock)
        live.forEach { $0.stageAutoMixFilter(descriptor) }
    }

    func reset(channelID: UInt64) {
        guard channelID != 0 else { return }
        os_unfair_lock_lock(&lock)
        descriptors.removeValue(forKey: channelID)
        var current = contexts[channelID, default: []]
        current.removeAll { $0.value == nil }
        contexts[channelID] = current
        let live = current.compactMap(\.value)
        os_unfair_lock_unlock(&lock)
        live.forEach { $0.stageAutoMixFilter(nil) }
    }

    func release(channelID: UInt64) {
        guard channelID != 0 else { return }
        reset(channelID: channelID)
        os_unfair_lock_lock(&lock)
        contexts.removeValue(forKey: channelID)
        os_unfair_lock_unlock(&lock)
    }
}

enum AutoMixTimedEnvelope {
    static func applyOutgoing(
        _ plan: AutoMixTransitionPlan,
        to parameters: AVMutableAudioMixInputParameters
    ) {
        apply(
            start: plan.outgoingCue,
            duration: plan.duration,
            to: parameters
        ) { progress in
            AutoMixGainEnvelope.outgoing(progress, curve: plan.outgoingGainCurve)
        }
    }

    static func applyIncoming(
        _ plan: AutoMixTransitionPlan,
        to parameters: AVMutableAudioMixInputParameters
    ) {
        apply(
            start: plan.incomingCue,
            duration: plan.incomingMediaDuration,
            to: parameters
        ) { progress in
            AutoMixGainEnvelope.incoming(
                progress,
                curve: plan.incomingGainCurve,
                overlapAttenuation: plan.incomingOverlapAttenuation
            )
        }
    }

    static func setUnity(
        to parameters: AVMutableAudioMixInputParameters,
        at mediaTime: TimeInterval
    ) {
        parameters.setVolume(
            1,
            at: CMTime(seconds: max(0, mediaTime), preferredTimescale: 600)
        )
    }

    private static func apply(
        start: TimeInterval,
        duration: TimeInterval,
        to parameters: AVMutableAudioMixInputParameters,
        value: (Double) -> Float
    ) {
        let segments = AutoMixGainEnvelope.segmentCount
        for index in 0..<segments {
            let lower = Double(index) / Double(segments)
            let upper = Double(index + 1) / Double(segments)
            let range = CMTimeRange(
                start: CMTime(seconds: start + duration * lower, preferredTimescale: 600),
                duration: CMTime(seconds: duration * (upper - lower), preferredTimescale: 600)
            )
            parameters.setVolumeRamp(
                fromStartVolume: value(lower),
                toEndVolume: value(upper),
                timeRange: range
            )
        }
    }
}

struct AutoMixPreparedFilter {
    static let tableCount = 129

    let descriptor: AutoMixTransitionFilterDescriptor
    let highPassAlpha: [Float]
    let lowPassAlpha: [Float]

    init(descriptor: AutoMixTransitionFilterDescriptor, sampleRate: Double) {
        self.descriptor = descriptor
        var highPass: [Float] = []
        var lowPass: [Float] = []
        highPass.reserveCapacity(Self.tableCount)
        lowPass.reserveCapacity(Self.tableCount)
        for index in 0..<Self.tableCount {
            let progress = Double(index) / Double(Self.tableCount - 1)
            let highPassHz = Self.logInterpolate(
                descriptor.highPassStartHz,
                descriptor.highPassEndHz,
                progress
            )
            let lowPassHz = Self.logInterpolate(
                descriptor.lowPassStartHz,
                descriptor.lowPassEndHz,
                progress
            )
            let highPassRC = 1 / (2 * Double.pi * max(10, highPassHz))
            let lowPassRC = 1 / (2 * Double.pi * min(sampleRate * 0.45, max(100, lowPassHz)))
            let dt = 1 / max(8_000, sampleRate)
            highPass.append(Float(highPassRC / (highPassRC + dt)))
            lowPass.append(Float(dt / (lowPassRC + dt)))
        }
        highPassAlpha = highPass
        lowPassAlpha = lowPass
    }

    func coefficients(progress: Double) -> (highPass: Float, lowPass: Float) {
        let position = min(1, max(0, progress)) * Double(Self.tableCount - 1)
        let lower = min(Self.tableCount - 1, Int(position.rounded(.down)))
        let upper = min(Self.tableCount - 1, lower + 1)
        let fraction = Float(position - Double(lower))
        return (
            highPassAlpha[lower] + (highPassAlpha[upper] - highPassAlpha[lower]) * fraction,
            lowPassAlpha[lower] + (lowPassAlpha[upper] - lowPassAlpha[lower]) * fraction
        )
    }

    private static func logInterpolate(_ start: Double, _ end: Double, _ progress: Double) -> Double {
        guard start > 0, end > 0 else { return max(1, start + (end - start) * progress) }
        return exp(log(start) + (log(end) - log(start)) * progress)
    }
}
