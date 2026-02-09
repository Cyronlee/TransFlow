import Speech
@preconcurrency import AVFoundation

/// Uses macOS 26.0 SpeechAnalyzer + SpeechTranscriber for real-time transcription.
/// Accepts an AudioChunk stream (16kHz mono Float32), outputs TranscriptionEvent stream.
final class SpeechEngine: Sendable {
    private let locale: Locale

    init(locale: Locale) {
        self.locale = locale
    }

    func processStream(_ audioStream: AsyncStream<AudioChunk>) -> AsyncStream<TranscriptionEvent> {
        let (events, continuation) = AsyncStream<TranscriptionEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(128)
        )
        let locale = self.locale

        Task {
            do {
                // 1. Create SpeechTranscriber
                guard let supportedLocale = await SpeechTranscriber.supportedLocale(
                    equivalentTo: locale
                ) else {
                    ErrorLogger.shared.log("Language \(locale.identifier) not supported", source: "SpeechEngine")
                    continuation.yield(.error("Language \(locale.identifier) not supported"))
                    continuation.finish()
                    return
                }

                let transcriber = SpeechTranscriber(
                    locale: supportedLocale,
                    transcriptionOptions: [],
                    reportingOptions: [.fastResults, .volatileResults],
                    attributeOptions: []
                )

                // 2. Get compatible audio format
                let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                    compatibleWith: [transcriber]
                )

                // 3. Model assets are managed by SpeechModelManager;
                //    assume they are installed before processStream is called.

                // 4. Create SpeechAnalyzer and warm up
                let analyzer = SpeechAnalyzer(modules: [transcriber])
                try await analyzer.prepareToAnalyze(in: analyzerFormat)

                // 5. Create input stream
                let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()

                // 6. Audio format converter (16kHz → analyzer format)
                let sourceFormat = AVAudioFormat(
                    standardFormatWithSampleRate: 16_000, channels: 1
                )!
                let converter: AVAudioConverter?
                if let analyzerFormat {
                    converter = AVAudioConverter(from: sourceFormat, to: analyzerFormat)
                } else {
                    converter = nil
                }

                // Pre-allocate reusable output buffer
                let reusableBuffer: AVAudioPCMBuffer?
                if converter != nil, let analyzerFormat {
                    let ratio = analyzerFormat.sampleRate / sourceFormat.sampleRate
                    let capacity = AVAudioFrameCount(16_000 * 0.25 * ratio) + 64
                    reusableBuffer = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity)
                } else { reusableBuffer = nil }

                // 7. Start result consumption first (avoid losing early results)
                let resultTask = Task(priority: .userInitiated) {
                    do {
                        for try await result in transcriber.results {
                            let text = String(result.text.characters)
                            if result.isFinal {
                                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty {
                                    continuation.yield(.sentenceComplete(
                                        TranscriptionSentence(timestamp: Date(), text: trimmed)
                                    ))
                                    continuation.yield(.partial(""))
                                }
                            } else {
                                continuation.yield(.partial(text))
                            }
                        }
                    } catch {
                        ErrorLogger.shared.log("Speech error: \(error.localizedDescription)", source: "SpeechEngine")
                        continuation.yield(.error("Speech error: \(error.localizedDescription)"))
                    }
                }

                // 8. Start autonomous analysis
                try await analyzer.start(inputSequence: inputSequence)

                // 9. Feed audio: accumulate ~200ms before batch sending
                var accumulator: [Float] = []
                let batchThreshold = Int(16_000 * 0.2)

                for await chunk in audioStream {
                    accumulator.append(contentsOf: chunk.samples)
                    guard accumulator.count >= batchThreshold else { continue }

                    if let input = Self.convertToAnalyzerInput(
                        samples: accumulator, converter: converter, reusableBuffer: reusableBuffer
                    ) {
                        inputBuilder.yield(input)
                    }
                    accumulator.removeAll(keepingCapacity: true)
                }

                // Flush remaining
                if !accumulator.isEmpty, let input = Self.convertToAnalyzerInput(
                    samples: accumulator, converter: converter, reusableBuffer: reusableBuffer
                ) {
                    inputBuilder.yield(input)
                }

                // 10. Finish
                inputBuilder.finish()
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                resultTask.cancel()

            } catch {
                ErrorLogger.shared.log("Engine error: \(error.localizedDescription)", source: "SpeechEngine")
                continuation.yield(.error("Engine error: \(error.localizedDescription)"))
            }
            continuation.finish()
        }

        return events
    }

    // MARK: - Helpers

    /// Convert Float32 samples to AnalyzerInput (with format conversion).
    private static func convertToAnalyzerInput(
        samples: [Float],
        converter: AVAudioConverter?,
        reusableBuffer: AVAudioPCMBuffer?
    ) -> AnalyzerInput? {
        guard let pcmBuffer = createPCMBuffer(from: samples) else { return nil }

        if let converter, let reusableBuffer {
            reusableBuffer.frameLength = 0
            var error: NSError?
            nonisolated(unsafe) var consumed = false
            nonisolated(unsafe) let capturedBuffer = pcmBuffer
            converter.convert(to: reusableBuffer, error: &error) { _, outStatus in
                if consumed { outStatus.pointee = .noDataNow; return nil }
                consumed = true; outStatus.pointee = .haveData; return capturedBuffer
            }
            guard error == nil, reusableBuffer.frameLength > 0 else { return nil }
            return AnalyzerInput(buffer: reusableBuffer)
        } else {
            return AnalyzerInput(buffer: pcmBuffer)
        }
    }

    /// Create 16kHz mono PCM buffer from Float32 samples.
    private static func createPCMBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channelData = buffer.floatChannelData else { return nil }
        samples.withUnsafeBufferPointer { ptr in
            channelData[0].initialize(from: ptr.baseAddress!, count: samples.count)
        }
        return buffer
    }
}
