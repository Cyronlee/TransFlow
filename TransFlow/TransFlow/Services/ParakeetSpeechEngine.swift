import Foundation

/// Local speech-to-text engine using sherpa-onnx + Parakeet TDT 0.6B v2 (int8).
/// Uses Silero VAD to segment audio, then runs the offline recognizer on each speech segment.
/// Emits `.sentenceComplete` events when a speech segment is fully decoded.
nonisolated final class ParakeetSpeechEngine: TranscriptionEngine, Sendable {
    private let modelDirectory: URL

    init(modelDirectory: URL) {
        self.modelDirectory = modelDirectory
    }

    func processStream(_ audioStream: AsyncStream<AudioChunk>) -> AsyncStream<TranscriptionEvent> {
        let (events, continuation) = AsyncStream<TranscriptionEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(128)
        )
        let modelDir = self.modelDirectory

        Task.detached(priority: .userInitiated) {
            do {
                // 1. Initialize offline recognizer
                let recognizer = try SherpaOnnxOfflineRecognizerBridge(
                    encoderPath: modelDir.appending(path: "encoder.int8.onnx").path(percentEncoded: false),
                    decoderPath: modelDir.appending(path: "decoder.int8.onnx").path(percentEncoded: false),
                    joinerPath: modelDir.appending(path: "joiner.int8.onnx").path(percentEncoded: false),
                    tokensPath: modelDir.appending(path: "tokens.txt").path(percentEncoded: false),
                    numThreads: 2
                )

                // 2. Initialize VAD
                let vad = try SherpaOnnxVADBridge(
                    modelPath: modelDir.appending(path: "silero_vad.onnx").path(percentEncoded: false),
                    threshold: 0.5,
                    minSilenceDuration: 0.5,
                    minSpeechDuration: 0.25,
                    maxSpeechDuration: 30.0,
                    windowSize: 512,
                    bufferSizeInSeconds: 120.0
                )

                // 3. Feed audio into VAD and decode completed speech segments
                let windowSize = 512  // VAD expects 512-sample windows at 16kHz
                var sampleBuffer: [Float] = []
                var readIndex = 0

                func emitDetectedSegments() {
                    while vad.hasSegment {
                        let segmentSamples = vad.popFrontSamples()
                        guard !segmentSamples.isEmpty else { continue }

                        let text = recognizer.decode(samples: segmentSamples)
                        if !text.isEmpty {
                            continuation.yield(.sentenceComplete(
                                TranscriptionSentence(timestamp: Date(), text: text)
                            ))
                        }
                    }
                }

                for await chunk in audioStream {
                    sampleBuffer.append(contentsOf: chunk.samples)

                    // Feed fixed-size windows without repeated front-removal copies.
                    while sampleBuffer.count - readIndex >= windowSize {
                        let endIndex = readIndex + windowSize
                        let window = Array(sampleBuffer[readIndex ..< endIndex])
                        readIndex = endIndex
                        vad.acceptWaveform(samples: window)
                        emitDetectedSegments()
                    }

                    // Compact occasionally to keep memory usage bounded.
                    if readIndex >= windowSize * 64 {
                        sampleBuffer.removeFirst(readIndex)
                        readIndex = 0
                    }
                }

                // Feed final partial frame (if any) padded with zeros before flush.
                let remainingCount = sampleBuffer.count - readIndex
                if remainingCount > 0 {
                    var tail = Array(sampleBuffer[readIndex...])
                    tail.append(contentsOf: Array(repeating: Float(0), count: windowSize - remainingCount))
                    vad.acceptWaveform(samples: tail)
                    emitDetectedSegments()
                }

                // 4. Flush remaining audio on stream end.
                vad.flush()
                emitDetectedSegments()

            } catch {
                let message = "Parakeet engine error: \(error.localizedDescription)"
                await MainActor.run { ErrorLogger.shared.log(message, source: "ParakeetEngine") }
                continuation.yield(.error(message))
            }

            continuation.finish()
        }

        return events
    }
}
