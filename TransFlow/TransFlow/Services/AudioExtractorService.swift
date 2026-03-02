import AVFoundation

/// Extracts audio from video/audio files as 16kHz mono Float32 samples.
final class AudioExtractorService: Sendable {

    /// Extract all audio from a file URL into a flat Float32 array at 16kHz mono.
    func extractAudio(from url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw AudioExtractorError.noAudioTrack
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        guard reader.startReading() else {
            throw AudioExtractorError.readerFailed(reader.error?.localizedDescription ?? "Unknown error")
        }

        var allSamples: [Float] = []
        allSamples.reserveCapacity(16_000 * 60)

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            var lengthAtOffset: Int = 0
            var totalLength: Int = 0
            var dataPointer: UnsafeMutablePointer<CChar>?

            let status = CMBlockBufferGetDataPointer(
                blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset,
                totalLengthOut: &totalLength, dataPointerOut: &dataPointer
            )
            guard status == kCMBlockBufferNoErr, let ptr = dataPointer else { continue }

            let floatCount = totalLength / MemoryLayout<Float>.size
            let floatPtr = UnsafeRawPointer(ptr).bindMemory(to: Float.self, capacity: floatCount)
            let buffer = UnsafeBufferPointer(start: floatPtr, count: floatCount)
            allSamples.append(contentsOf: buffer)
        }

        guard reader.status == .completed else {
            throw AudioExtractorError.readerFailed(reader.error?.localizedDescription ?? "Incomplete read")
        }

        return allSamples
    }

    /// Extract audio and deliver as an AsyncStream of AudioChunks (for SpeechEngine).
    /// Each chunk is ~200ms of audio. Also returns the total duration in seconds.
    func extractAudioStream(from url: URL) async throws -> (stream: AsyncStream<AudioChunk>, durationSeconds: Double) {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        let allSamples = try await extractAudio(from: url)

        let chunkSize = 16_000 / 5 // 200ms chunks
        let stream = AsyncStream<AudioChunk> { continuation in
            Task.detached {
                var offset = 0
                let sampleRate: Double = 16_000
                while offset < allSamples.count {
                    let end = min(offset + chunkSize, allSamples.count)
                    let slice = Array(allSamples[offset..<end])

                    let level = slice.reduce(Float(0)) { max($0, abs($1)) }
                    let timestamp = Date().addingTimeInterval(Double(offset) / sampleRate)

                    continuation.yield(AudioChunk(
                        samples: slice,
                        level: min(level, 1.0),
                        timestamp: timestamp
                    ))

                    offset = end
                }
                continuation.finish()
            }
        }

        return (stream, durationSeconds)
    }

    /// Get the duration of a media file in seconds.
    func mediaDuration(for url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }
}

enum AudioExtractorError: LocalizedError {
    case noAudioTrack
    case readerFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "No audio track found in the file."
        case .readerFailed(let message):
            return "Audio extraction failed: \(message)"
        }
    }
}
