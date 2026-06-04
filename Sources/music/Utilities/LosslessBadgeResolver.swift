import AVFoundation
import Foundation

struct LosslessBadgeStatus: Equatable {
    let title: String
    let systemImage: String
    let status: String
    let output: String
    let reason: String
}

enum LosslessBadgeResolver {
    static func status(for song: Song?) -> LosslessBadgeStatus? {
        guard let song, song.isLossless else { return nil }

        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        let outputNames = outputs.map(\.portName).filter { !$0.isEmpty }
        let outputName = outputNames.isEmpty ? "System Output" : outputNames.joined(separator: ", ")
        let outputRate = Int(session.sampleRate.rounded())
        let output = outputRate > 0 ? "\(outputName) - \(formatSampleRate(outputRate))" : outputName

        let routeCanBeBitPerfect = outputs.contains { isBitPerfectCapableRoute($0.portType) }
        let hasBlockedRoute = outputs.contains { isLossyOrSystemRoute($0.portType) }
        let sampleRateMatches = song.samplingRate.map { abs($0 - outputRate) <= 1 } ?? false
        let hasFileDepth = song.bitDepth != nil

        let isTrue = routeCanBeBitPerfect && !hasBlockedRoute && sampleRateMatches && hasFileDepth
        if isTrue {
            return LosslessBadgeStatus(
                title: "True Lossless",
                systemImage: "checkmark.seal",
                status: "True Lossless",
                output: output,
                reason: "Output route reports matching sample rate for lossless file."
            )
        }

        return LosslessBadgeStatus(
            title: "Lossless",
            systemImage: "waveform",
            status: "Lossless File",
            output: output,
            reason: fallbackReason(song: song, outputRate: outputRate, outputs: outputs)
        )
    }

    private static func isBitPerfectCapableRoute(_ port: AVAudioSession.Port) -> Bool {
        switch port {
        case .headphones, .lineOut, .usbAudio, .HDMI:
            return true
        default:
            return false
        }
    }

    private static func isLossyOrSystemRoute(_ port: AVAudioSession.Port) -> Bool {
        switch port {
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .builtInReceiver, .builtInSpeaker, .airPlay:
            return true
        default:
            return false
        }
    }

    private static func fallbackReason(song: Song, outputRate: Int, outputs: [AVAudioSessionPortDescription]) -> String {
        if outputs.contains(where: { $0.portType == .bluetoothA2DP || $0.portType == .bluetoothHFP || $0.portType == .bluetoothLE }) {
            return "Bluetooth output uses a lossy codec, even when the file is lossless."
        }
        if outputs.contains(where: { $0.portType == .builtInReceiver || $0.portType == .builtInSpeaker }) {
            return "Built-in output is system-rendered, so this is shown as file lossless."
        }
        guard let fileRate = song.samplingRate else {
            return "File lacks sample-rate metadata needed to verify output."
        }
        if outputRate > 0, abs(fileRate - outputRate) > 1 {
            return "Output sample rate is \(formatSampleRate(outputRate)); file is \(formatSampleRate(fileRate))."
        }
        if song.bitDepth == nil {
            return "File lacks bit-depth metadata needed to verify output."
        }
        return "Output route cannot be verified as bit-perfect."
    }

    private static func formatSampleRate(_ value: Int) -> String {
        String(format: "%.1f kHz", Double(value) / 1000)
    }
}
