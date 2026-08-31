import Foundation
import AVFoundation
import Accelerate

struct AutoMixFeatureFrame: Sendable {
    let time: TimeInterval
    let rms: Double
    let kWeightedEnergy: Double
    let peak: Double
    let onsetStrength: Double
    let lowFrequencyRatio: Double
    let midFrequencyRatio: Double
    let highFrequencyRatio: Double
    let spectralCentroid: Double
    let harmonicChange: Double
    let chroma: [Double]
}

struct AutoMixDecodedFeatures: Sendable {
    let frames: [AutoMixFeatureFrame]
    let sampleRate: Double
    let hopSize: Int
    let samplePeak: Double
    let decodedSeconds: TimeInterval
    let reachedEnd: Bool

    var frameRate: Double { sampleRate / Double(hopSize) }
}

struct DSPAutoMixAnalyzer: AutoMixAnalyzing {
    private let analysisSampleRate = 11_025.0
    private let headSeconds: TimeInterval = 240
    private let tailSeconds: TimeInterval = 120
    private let fullDecodeLimit: TimeInterval = 720

    func analyze(_ request: AutoMixAnalysisRequest) async -> AutoMixTrackAnalysis {
        let fingerprint = request.fingerprint
        guard !Task.isCancelled else {
            return .unavailable(trackID: request.trackID, fingerprint: fingerprint)
        }

        let acquired = await acquireSource(request.source)
        guard let acquired else {
            return .unavailable(trackID: request.trackID, fingerprint: fingerprint)
        }
        defer {
            if acquired.temporary { try? FileManager.default.removeItem(at: acquired.url) }
        }

        let asset = AVURLAsset(
            url: acquired.url,
            options: acquired.complete ? [AVURLAssetPreferPreciseDurationAndTimingKey: true] : nil
        )
        let assetDuration = (try? await asset.load(.duration).seconds).flatMap {
            $0.isFinite && $0 > 0 ? $0 : nil
        } ?? request.duration
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              !Task.isCancelled else {
            return .unavailable(trackID: request.trackID, fingerprint: fingerprint)
        }

        let headLimit: TimeInterval
        let shouldDecodeTail: Bool
        if acquired.complete, assetDuration > 0, assetDuration <= fullDecodeLimit {
            headLimit = assetDuration + 1
            shouldDecodeTail = false
        } else {
            headLimit = min(
                acquired.requestedSeconds ?? headSeconds,
                assetDuration > 0 ? assetDuration : .greatestFiniteMagnitude
            )
            shouldDecodeTail = acquired.complete && assetDuration > fullDecodeLimit
        }

        let decodedHead = await DeveloperExperiments.runBlocking(qos: .utility) {
            Self.decode(
                asset: asset,
                track: track,
                startingAt: 0,
                maximumSeconds: headLimit,
                sampleRate: analysisSampleRate
            )
        }
        guard !Task.isCancelled, !decodedHead.frames.isEmpty else {
            return .unavailable(trackID: request.trackID, fingerprint: fingerprint)
        }

        var decodedTail: AutoMixDecodedFeatures?
        if shouldDecodeTail {
            let tailStart = max(0, assetDuration - tailSeconds)
            decodedTail = await DeveloperExperiments.runBlocking(qos: .utility) {
                Self.decode(
                    asset: asset,
                    track: track,
                    startingAt: tailStart,
                    maximumSeconds: tailSeconds + 1,
                    sampleRate: analysisSampleRate
                )
            }
        }
        guard !Task.isCancelled else {
            return .unavailable(trackID: request.trackID, fingerprint: fingerprint)
        }

        let coverage = Self.coverage(
            completeSource: acquired.complete,
            duration: assetDuration,
            head: decodedHead,
            tail: decodedTail
        )
        let rhythmFrames = decodedHead.frames
        let rhythm = AutoMixBeatTracker.track(
            onsetStrength: rhythmFrames.map(\.onsetStrength),
            lowFrequency: rhythmFrames.map(\.lowFrequencyRatio),
            harmonicChange: rhythmFrames.map(\.harmonicChange),
            frameRate: decodedHead.frameRate,
            metadataBPM: request.metadataBPM,
            coverageSeconds: coverage.headSeconds
        )
        let allFrames = (decodedHead.frames + (decodedTail?.frames ?? []))
            .sorted { $0.time < $1.time }
        let key = AutoMixKeyAnalyzer.estimate(frames: rhythmFrames)
        let structure = AutoMixStructureAnalyzer.analyze(
            frames: allFrames,
            rhythm: rhythm,
            coverage: coverage,
            duration: assetDuration,
            samplePeak: max(decodedHead.samplePeak, decodedTail?.samplePeak ?? 0)
        )

        let analysis = AutoMixTrackAnalysis(
            analysisVersion: AutoMixTrackAnalysis.currentVersion,
            trackID: request.trackID,
            sourceFingerprint: fingerprint,
            source: acquired.source,
            coverage: coverage,
            duration: max(assetDuration, structure.audibleEnd),
            tempo: rhythm.tempo,
            tempoConfidence: rhythm.tempo?.confidence ?? 0,
            beats: rhythm.beats,
            beatConfidence: rhythm.beatConfidence,
            meter: rhythm.meter,
            meterConfidence: rhythm.meter?.confidence ?? 0,
            downbeatConfidence: rhythm.meter?.downbeatConfidence ?? 0,
            key: key,
            keyConfidence: key?.confidence ?? 0,
            cuePoints: structure.cues,
            structureConfidence: structure.confidence,
            leadingSilence: structure.leadingSilence,
            trailingSilence: structure.trailingSilence,
            coldEndingLikelihood: structure.coldEndingLikelihood,
            fadeOutLikelihood: structure.fadeOutLikelihood,
            loudness: structure.loudness,
            introProfile: structure.introProfile,
            outroProfile: structure.outroProfile
        )
        AutoMixDiagnostics.logAnalysis(analysis)
        return analysis
    }

    private struct AcquiredSource {
        let url: URL
        let source: AutoMixAnalysisSource
        let complete: Bool
        let requestedSeconds: TimeInterval?
        let temporary: Bool
    }

    private func acquireSource(_ source: AutoMixAudioSource) async -> AcquiredSource? {
        switch source {
        case .file(let url, let kind, let complete):
            guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
            return AcquiredSource(
                url: url,
                source: kind,
                complete: complete,
                requestedSeconds: nil,
                temporary: false
            )
        case .remote(let url, let headers, let fileExtension, let requestedSeconds, let maximumBytes):
            guard let result = await AutoMixRemotePrefixDownloader.download(
                url: url,
                headers: headers,
                fileExtension: fileExtension,
                maximumBytes: maximumBytes
            ) else { return nil }
            return AcquiredSource(
                url: result.url,
                source: .remotePrefix,
                complete: result.complete,
                requestedSeconds: requestedSeconds,
                temporary: true
            )
        case .unavailable:
            return nil
        }
    }

    private static func coverage(
        completeSource: Bool,
        duration: TimeInterval,
        head: AutoMixDecodedFeatures,
        tail: AutoMixDecodedFeatures?
    ) -> AutoMixAnalysisCoverage {
        let normalizedDuration = duration.isFinite ? max(0, duration) : 0
        if completeSource,
           tail == nil,
           (head.reachedEnd || normalizedDuration <= head.decodedSeconds + 1.5) {
            return AutoMixAnalysisCoverage(
                kind: .full,
                headSeconds: max(head.decodedSeconds, normalizedDuration),
                tailSeconds: max(head.decodedSeconds, normalizedDuration),
                duration: normalizedDuration
            )
        }
        if let tail, !tail.frames.isEmpty {
            return AutoMixAnalysisCoverage(
                kind: .headAndTail,
                headSeconds: head.decodedSeconds,
                tailSeconds: tail.decodedSeconds,
                duration: normalizedDuration
            )
        }
        return AutoMixAnalysisCoverage(
            kind: .headOnly,
            headSeconds: head.decodedSeconds,
            tailSeconds: 0,
            duration: normalizedDuration
        )
    }

    // One decode and FFT pass produces rhythm, structure, timbre, chroma, and
    // loudness features. No feature requests a second full decode.
    nonisolated static func decode(
        asset: AVURLAsset,
        track: AVAssetTrack,
        startingAt: TimeInterval,
        maximumSeconds: TimeInterval,
        sampleRate: Double
    ) -> AutoMixDecodedFeatures {
        guard let reader = try? AVAssetReader(asset: asset) else {
            return AutoMixDecodedFeatures(frames: [], sampleRate: sampleRate, hopSize: 512, samplePeak: 0, decodedSeconds: 0, reachedEnd: false)
        }
        if startingAt > 0 || maximumSeconds.isFinite {
            reader.timeRange = CMTimeRange(
                start: CMTime(seconds: startingAt, preferredTimescale: 600),
                duration: CMTime(seconds: maximumSeconds, preferredTimescale: 600)
            )
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: sampleRate
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            return AutoMixDecodedFeatures(frames: [], sampleRate: sampleRate, hopSize: 512, samplePeak: 0, decodedSeconds: 0, reachedEnd: false)
        }
        reader.add(output)
        guard reader.startReading() else {
            return AutoMixDecodedFeatures(frames: [], sampleRate: sampleRate, hopSize: 512, samplePeak: 0, decodedSeconds: 0, reachedEnd: false)
        }

        var extractor = AutoMixFeatureExtractor(sampleRate: sampleRate, startingAt: startingAt)
        while !Task.isCancelled, let sampleBuffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            var length = 0
            var rawPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(
                block,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &rawPointer
            )
            guard status == kCMBlockBufferNoErr,
                  let rawPointer,
                  length >= MemoryLayout<Float>.size else { continue }
            let count = length / MemoryLayout<Float>.size
            rawPointer.withMemoryRebound(to: Float.self, capacity: count) { samples in
                extractor.consume(UnsafeBufferPointer(start: samples, count: count))
            }
        }
        return extractor.finish(reachedEnd: reader.status == .completed)
    }

    // Test entry point; production decode feeds the same extractor.
    nonisolated static func analyzeSamples(
        _ samples: [Float],
        sampleRate: Double,
        metadataBPM: Double? = nil
    ) -> AutoMixRhythmResult {
        var extractor = AutoMixFeatureExtractor(sampleRate: sampleRate, startingAt: 0)
        samples.withUnsafeBufferPointer { extractor.consume($0) }
        let decoded = extractor.finish(reachedEnd: true)
        return AutoMixBeatTracker.track(
            onsetStrength: decoded.frames.map(\.onsetStrength),
            lowFrequency: decoded.frames.map(\.lowFrequencyRatio),
            harmonicChange: decoded.frames.map(\.harmonicChange),
            frameRate: decoded.frameRate,
            metadataBPM: metadataBPM,
            coverageSeconds: decoded.decodedSeconds
        )
    }
}

private struct AutoMixFeatureExtractor {
    private let sampleRate: Double
    private let startingAt: TimeInterval
    private let fftSize = 2_048
    private let hopSize = 512
    private let log2FFT = vDSP_Length(11)
    private var fftSetup: FFTSetup?
    private var ring = [Float](repeating: 0, count: 2_048)
    private var writeIndex = 0
    private var filled = 0
    private var sinceFrame = 0
    private var totalSamples = 0
    private var samplePeak = 0.0
    private var hopSquareSum = 0.0
    private var hopKSum = 0.0
    private var hopCount = 0
    private var hopPeak = 0.0
    private var kWeighting: AutoMixKWeightingFilter
    private var window = [Float](repeating: 0, count: 2_048)
    private var windowed = [Float](repeating: 0, count: 2_048)
    private var real = [Float](repeating: 0, count: 1_024)
    private var imaginary = [Float](repeating: 0, count: 1_024)
    private var magnitudes = [Float](repeating: 0, count: 1_024)
    private var previousLogMagnitudes = [Float](repeating: 0, count: 1_024)
    private var previousChroma = [Double](repeating: 0, count: 12)
    private var binPitchClass = [Int](repeating: -1, count: 1_024)
    private var frames: [AutoMixFeatureFrame] = []

    init(sampleRate: Double, startingAt: TimeInterval) {
        self.sampleRate = sampleRate
        self.startingAt = startingAt
        self.kWeighting = AutoMixKWeightingFilter(sampleRate: sampleRate)
        fftSetup = vDSP_create_fftsetup(log2FFT, FFTRadix(kFFTRadix2))
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        for bin in 1..<(fftSize / 2) {
            let frequency = Double(bin) * sampleRate / Double(fftSize)
            guard frequency >= 55, frequency <= 5_000 else { continue }
            let midi = 69 + 12 * log2(frequency / 440)
            binPitchClass[bin] = ((Int(midi.rounded()) % 12) + 12) % 12
        }
        frames.reserveCapacity(12_000)
    }

    mutating func consume(_ samples: UnsafeBufferPointer<Float>) {
        for sample in samples {
            if Task.isCancelled { return }
            let finite = sample.isFinite ? sample : 0
            ring[writeIndex] = finite
            writeIndex = (writeIndex + 1) % fftSize
            filled = min(fftSize, filled + 1)
            sinceFrame += 1
            totalSamples += 1

            let value = Double(finite)
            let absolute = abs(value)
            samplePeak = max(samplePeak, absolute)
            hopPeak = max(hopPeak, absolute)
            hopSquareSum += value * value
            let weighted = kWeighting.process(value)
            hopKSum += weighted * weighted
            hopCount += 1

            if filled == fftSize, sinceFrame >= hopSize {
                processFrame()
                sinceFrame = 0
                hopSquareSum = 0
                hopKSum = 0
                hopCount = 0
                hopPeak = 0
            }
        }
    }

    mutating func finish(reachedEnd: Bool) -> AutoMixDecodedFeatures {
        if let fftSetup { vDSP_destroy_fftsetup(fftSetup) }
        fftSetup = nil
        return AutoMixDecodedFeatures(
            frames: frames,
            sampleRate: sampleRate,
            hopSize: hopSize,
            samplePeak: samplePeak,
            decodedSeconds: Double(totalSamples) / sampleRate,
            reachedEnd: reachedEnd
        )
    }

    private mutating func processFrame() {
        guard let fftSetup, hopCount > 0 else { return }
        for index in 0..<fftSize {
            windowed[index] = ring[(writeIndex + index) % fftSize] * window[index]
        }
        real.withUnsafeMutableBufferPointer { realBuffer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                guard let realBase = realBuffer.baseAddress,
                      let imaginaryBase = imaginaryBuffer.baseAddress else { return }
                var split = DSPSplitComplex(realp: realBase, imagp: imaginaryBase)
                windowed.withUnsafeBufferPointer { buffer in
                    buffer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(fftSize / 2))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2FFT, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        var flux = 0.0
        var fluxBins = 0
        var low = 0.0, mid = 0.0, high = 0.0
        var total = 0.0, weightedFrequency = 0.0
        var chroma = [Double](repeating: 0, count: 12)
        for bin in 1..<(fftSize / 2) {
            let frequency = Double(bin) * sampleRate / Double(fftSize)
            guard frequency <= 10_000 else { break }
            let magnitude = Double(magnitudes[bin])
            let compressed = Float(log1p(magnitude))
            let difference = max(0, Double(compressed - previousLogMagnitudes[bin]))
            if frequency >= 45 {
                let weight = frequency < 120 ? 0.7 : (frequency > 7_000 ? 0.72 : 1)
                flux += difference * weight
                fluxBins += 1
            }
            previousLogMagnitudes[bin] = compressed

            let power = magnitude * magnitude
            if frequency >= 30, frequency < 250 { low += power }
            if frequency >= 250, frequency < 4_000 { mid += power }
            if frequency >= 4_000, frequency <= 10_000 { high += power }
            if frequency >= 30 {
                total += power
                weightedFrequency += power * frequency
            }
            let pitch = binPitchClass[bin]
            if pitch >= 0 { chroma[pitch] += log1p(magnitude) }
        }
        let spectralTotal = max(1.0e-12, low + mid + high)
        let chromaTotal = chroma.reduce(0, +)
        if chromaTotal > 0 {
            for index in chroma.indices { chroma[index] /= chromaTotal }
        }
        let harmonicChange = Self.cosineDistance(chroma, previousChroma)
        previousChroma = chroma
        let centerSample = max(0, totalSamples - fftSize / 2)
        let time = startingAt + Double(centerSample) / sampleRate
        frames.append(AutoMixFeatureFrame(
            time: time,
            rms: sqrt(hopSquareSum / Double(hopCount)),
            kWeightedEnergy: hopKSum / Double(hopCount),
            peak: hopPeak,
            onsetStrength: flux / Double(max(1, fluxBins)),
            lowFrequencyRatio: low / spectralTotal,
            midFrequencyRatio: mid / spectralTotal,
            highFrequencyRatio: high / spectralTotal,
            spectralCentroid: total > 0 ? weightedFrequency / total : 0,
            harmonicChange: harmonicChange,
            chroma: chroma
        ))
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
}

private struct AutoMixKWeightingFilter {
    private var shelf: AutoMixBiquad
    private var highPass: AutoMixBiquad

    init(sampleRate: Double) {
        shelf = AutoMixBiquad.highShelf(
            sampleRate: sampleRate,
            frequency: 1_500,
            gainDB: 4,
            q: 0.707
        )
        highPass = AutoMixBiquad.highPass(
            sampleRate: sampleRate,
            frequency: 38,
            q: 0.5
        )
    }

    mutating func process(_ sample: Double) -> Double {
        highPass.process(shelf.process(sample))
    }
}

private struct AutoMixBiquad {
    let b0: Double
    let b1: Double
    let b2: Double
    let a1: Double
    let a2: Double
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    mutating func process(_ input: Double) -> Double {
        let output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = input
        y2 = y1; y1 = output
        return output
    }

    static func highPass(sampleRate: Double, frequency: Double, q: Double) -> AutoMixBiquad {
        let omega = 2 * Double.pi * frequency / sampleRate
        let cosine = cos(omega)
        let alpha = sin(omega) / (2 * q)
        let a0 = 1 + alpha
        return AutoMixBiquad(
            b0: (1 + cosine) / 2 / a0,
            b1: -(1 + cosine) / a0,
            b2: (1 + cosine) / 2 / a0,
            a1: -2 * cosine / a0,
            a2: (1 - alpha) / a0
        )
    }

    static func highShelf(
        sampleRate: Double,
        frequency: Double,
        gainDB: Double,
        q: Double
    ) -> AutoMixBiquad {
        let amplitude = pow(10, gainDB / 40)
        let omega = 2 * Double.pi * frequency / sampleRate
        let cosine = cos(omega)
        let sine = sin(omega)
        let alpha = sine / (2 * q)
        let beta = 2 * sqrt(amplitude) * alpha
        let a0 = (amplitude + 1) - (amplitude - 1) * cosine + beta
        return AutoMixBiquad(
            b0: amplitude * ((amplitude + 1) + (amplitude - 1) * cosine + beta) / a0,
            b1: -2 * amplitude * ((amplitude - 1) + (amplitude + 1) * cosine) / a0,
            b2: amplitude * ((amplitude + 1) + (amplitude - 1) * cosine - beta) / a0,
            a1: 2 * ((amplitude - 1) - (amplitude + 1) * cosine) / a0,
            a2: ((amplitude + 1) - (amplitude - 1) * cosine - beta) / a0
        )
    }
}

private enum AutoMixRemotePrefixDownloader {
    struct Result {
        let url: URL
        let complete: Bool
    }

    static func download(
        url: URL,
        headers: [String: String],
        fileExtension: String,
        maximumBytes: Int
    ) async -> Result? {
        let delegate = Delegate(maximumBytes: max(256 * 1_024, maximumBytes))
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("bytes=0-\(delegate.maximumBytes - 1)", forHTTPHeaderField: "Range")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        guard let payload = await delegate.load(request) else { return nil }
        let ext = fileExtension
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("automix-v2-\(UUID().uuidString)")
            .appendingPathExtension(ext.isEmpty ? "audio" : ext)
        do {
            try payload.data.write(to: destination, options: .atomic)
            return Result(url: destination, complete: payload.complete)
        } catch {
            return nil
        }
    }

    private final class Delegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        struct Payload {
            let data: Data
            let complete: Bool
        }

        let maximumBytes: Int
        private var data = Data()
        private var continuation: CheckedContinuation<Payload?, Never>?
        private var session: URLSession?
        private var hitLimit = false
        private var responseStatus = 0
        private var expectedLength: Int64 = NSURLSessionTransferSizeUnknown

        init(maximumBytes: Int) {
            self.maximumBytes = maximumBytes
            super.init()
            data.reserveCapacity(maximumBytes)
        }

        func load(_ request: URLRequest) async -> Payload? {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                let queue = OperationQueue()
                queue.maxConcurrentOperationCount = 1
                let configuration = URLSessionConfiguration.ephemeral
                configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
                self.session = session
                session.dataTask(with: request).resume()
            }
        }

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            responseStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            expectedLength = response.expectedContentLength
            let mime = response.mimeType?.lowercased() ?? ""
            let acceptableStatus = responseStatus == 0 || (200...299).contains(responseStatus)
            let acceptableType = !mime.contains("json") && !mime.contains("html") && !mime.contains("text")
            completionHandler(acceptableStatus && acceptableType ? .allow : .cancel)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive incoming: Data) {
            let remaining = maximumBytes - data.count
            guard remaining > 0 else {
                hitLimit = true
                dataTask.cancel()
                return
            }
            if incoming.count > remaining {
                data.append(incoming.prefix(remaining))
                hitLimit = true
                dataTask.cancel()
            } else {
                data.append(incoming)
                if data.count >= maximumBytes {
                    hitLimit = true
                    dataTask.cancel()
                }
            }
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didCompleteWithError error: Error?
        ) {
            defer {
                self.session?.finishTasksAndInvalidate()
                self.session = nil
            }
            guard data.count >= 64 * 1_024 else {
                continuation?.resume(returning: nil)
                continuation = nil
                return
            }
            let wasCancelledAtLimit = hitLimit && (error as NSError?)?.code == NSURLErrorCancelled
            guard error == nil || wasCancelledAtLimit else {
                continuation?.resume(returning: nil)
                continuation = nil
                return
            }
            let complete = !hitLimit
                && responseStatus != 206
                && (expectedLength <= 0 || Int64(data.count) >= expectedLength)
            continuation?.resume(returning: Payload(data: data, complete: complete))
            continuation = nil
        }
    }
}
