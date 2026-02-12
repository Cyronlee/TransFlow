import Foundation

/// Local streaming speech-to-text engine using sherpa-onnx + Nemotron Speech Streaming EN 0.6B int8.
/// Emits partial updates while speaking and finalized sentences on endpoint detection.
nonisolated final class NemotronStreamingSpeechEngine: TranscriptionEngine, Sendable {
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
                let recognizer = try SherpaOnnxOnlineRecognizerBridge(
                    encoderPath: modelDir.appending(path: "encoder.int8.onnx").path(percentEncoded: false),
                    decoderPath: modelDir.appending(path: "decoder.int8.onnx").path(percentEncoded: false),
                    joinerPath: modelDir.appending(path: "joiner.int8.onnx").path(percentEncoded: false),
                    tokensPath: modelDir.appending(path: "tokens.txt").path(percentEncoded: false),
                    numThreads: 2,
                    modelType: "nemo_transducer",
                    modelingUnit: "bpe"
                )

                var lastPartial = ""

                func emitPartialIfChanged(_ text: String) {
                    guard text != lastPartial else { return }
                    lastPartial = text
                    continuation.yield(.partial(text))
                }

                func emitFinalIfNeeded(_ text: String) {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    continuation.yield(.sentenceComplete(TranscriptionSentence(timestamp: Date(), text: trimmed)))
                    lastPartial = ""
                    continuation.yield(.partial(""))
                }

                for await chunk in audioStream {
                    recognizer.acceptWaveform(samples: chunk.samples)
                    recognizer.decodeWhileReady()

                    let text = recognizer.currentText()
                    if recognizer.isEndpoint() {
                        emitFinalIfNeeded(text)
                        recognizer.reset()
                    } else {
                        emitPartialIfChanged(text)
                    }
                }

                recognizer.inputFinished()
                recognizer.decodeWhileReady()
                emitFinalIfNeeded(recognizer.currentText())

            } catch {
                let message = "Nemotron engine error: \(error.localizedDescription)"
                await MainActor.run { ErrorLogger.shared.log(message, source: "NemotronEngine") }
                continuation.yield(.error(message))
            }

            continuation.finish()
        }

        return events
    }
}
