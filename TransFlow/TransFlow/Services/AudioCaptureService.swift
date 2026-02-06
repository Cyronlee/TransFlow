@preconcurrency import AVFoundation

/// Captures microphone audio using AVAudioEngine, outputting 16kHz mono Float32 AudioChunks.
final class AudioCaptureService: @unchecked Sendable {

    /// Start capturing microphone audio.
    /// Returns a stream of AudioChunks and a stop closure.
    nonisolated func startCapture() -> (stream: AsyncStream<AudioChunk>, stop: @Sendable () -> Void) {
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream(
            bufferingPolicy: .bufferingNewest(256)
        )

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Target format: 16kHz mono Float32
        guard let targetFormat = AVAudioFormat(
            standardFormatWithSampleRate: 16_000, channels: 1
        ) else {
            continuation.finish()
            return (stream, {})
        }

        // Create converter from input format to 16kHz mono
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            continuation.finish()
            return (stream, {})
        }

        // ~100ms chunks at 16kHz = 1600 samples
        let outputFrameCapacity: AVAudioFrameCount = 1600

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: outputFrameCapacity
            ) else { return }

            var error: NSError?
            nonisolated(unsafe) var consumed = false
            converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                if consumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                consumed = true
                outStatus.pointee = .haveData
                return buffer
            }

            guard error == nil, outputBuffer.frameLength > 0,
                  let channelData = outputBuffer.floatChannelData else { return }

            let frameCount = Int(outputBuffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))

            // Calculate normalized audio level: RMS → dB → 0-1
            let level = Self.calculateNormalizedLevel(samples: samples)

            let chunk = AudioChunk(
                samples: samples,
                level: level,
                timestamp: Date()
            )
            continuation.yield(chunk)
        }

        do {
            try engine.start()
        } catch {
            continuation.finish()
            return (stream, {})
        }

        nonisolated(unsafe) let capturedEngine = engine
        nonisolated(unsafe) let capturedInputNode = inputNode
        let stop: @Sendable () -> Void = {
            capturedInputNode.removeTap(onBus: 0)
            capturedEngine.stop()
            continuation.finish()
        }

        return (stream, stop)
    }

    /// Request microphone permission.
    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Calculate normalized audio level from samples: RMS → dB → 0-1 range.
    nonisolated private static func calculateNormalizedLevel(samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        let rms = sqrt(sumOfSquares / Float(samples.count))
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        // Normalize: -60dB → 0, 0dB → 1
        let normalized = max(0, min(1, (db + 60) / 60))
        return normalized
    }
}
