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
    static func status(for song: Song?, isTranscoding: Bool = false) -> LosslessBadgeStatus? {
        guard let song else { return nil }

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
        let isHiRes = song.isHiResLossless

        // Runtime stream state wins over source-format badges. A Dolby Atmos
        // source that is being transcoded should show Transcoding, not Atmos.
        if isTranscoding {
            return transcodingStatus(for: song, output: output)
        }

        if song.isDolbyAtmos {
            return LosslessBadgeStatus(
                title: "Dolby Atmos",
                systemImage: "airpodspro",
                status: "Dolby Atmos",
                output: output,
                reason: "Source metadata indicates a Dolby Atmos-compatible stream."
            )
        }

        guard song.isLossless else {
            return LosslessBadgeStatus(
                title: "Lossy",
                systemImage: "music.note",
                status: "Lossy File",
                output: output,
                reason: lossyReason(song: song)
            )
        }

        let isTrue = routeCanBeBitPerfect && !hasBlockedRoute && sampleRateMatches && hasFileDepth
        if isTrue {
            if isHiRes {
                return LosslessBadgeStatus(
                    title: "True Hi-Res Lossless",
                    systemImage: "checkmark.seal",
                    status: "True Hi-Res Lossless",
                    output: output,
                    reason: "Output route reports matching sample rate for hi-res lossless file."
                )
            }

            return LosslessBadgeStatus(
                title: "True Lossless",
                systemImage: "checkmark.seal",
                status: "True Lossless",
                output: output,
                reason: "Output route reports matching sample rate for lossless file."
            )
        }

        if isHiRes {
            return LosslessBadgeStatus(
                title: "Hi-Res Lossless",
                systemImage: "waveform",
                status: "Hi-Res Lossless File",
                output: output,
                reason: fallbackReason(song: song, outputRate: outputRate, outputs: outputs)
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

    private static func lossyReason(song: Song) -> String {
        if let codec = song.codec?.trimmingCharacters(in: .whitespacesAndNewlines), !codec.isEmpty {
            return "Source codec is \(codec.uppercased()), which Volta classifies as lossy."
        }
        if let format = song.suffix?.trimmingCharacters(in: .whitespacesAndNewlines), !format.isEmpty {
            return "Source format is \(format.uppercased()) and lacks lossless metadata."
        }
        if let contentType = song.contentType?.trimmingCharacters(in: .whitespacesAndNewlines), !contentType.isEmpty {
            return "Source media type is \(contentType) and lacks lossless metadata."
        }
        return "Source file lacks lossless metadata."
    }

    private static func transcodingStatus(for song: Song, output: String) -> LosslessBadgeStatus {
        LosslessBadgeStatus(
            title: "Transcoding",
            systemImage: "arrow.triangle.2.circlepath",
            status: "Transcoding",
            output: output,
            reason: song.isLossless
                ? "Lossless source file is being transcoded for playback, so the current stream is lossy."
                : "Source file is being transcoded for playback, so the current stream is lossy."
        )
    }

    private static func formatSampleRate(_ value: Int) -> String {
        String(format: "%.1f kHz", Double(value) / 1000)
    }
}
