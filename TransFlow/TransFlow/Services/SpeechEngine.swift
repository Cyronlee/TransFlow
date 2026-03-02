import Speech
import CoreMedia
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
                let outputSampleRate: Double
                if let analyzerFormat {
                    converter = AVAudioConverter(from: sourceFormat, to: analyzerFormat)
                    outputSampleRate = analyzerFormat.sampleRate
                } else {
                    converter = nil
                    outputSampleRate = 16_000
                }

                // Pre-allocate reusable output buffer
                let reusableBuffer: AVAudioPCMBuffer?
                if converter != nil, let analyzerFormat {
                    let ratio = analyzerFormat.sampleRate / sourceFormat.sampleRate
                    let capacity = AVAudioFrameCount(16_000 * 0.25 * ratio) + 64
                    reusableBuffer = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity)
                } else { reusableBuffer = nil }

                // Wall-clock anchor: maps CMTime(0) in the analyzer timeline to a real Date.
                let sessionStartDate = Date()

                // 7. Start result consumption first (avoid losing early results)
                nonisolated(unsafe) let capturedStartDate = sessionStartDate
                let resultTask = Task(priority: .userInitiated) {
                    do {
                        for try await result in transcriber.results {
                            let text = String(result.text.characters)
                            if result.isFinal {
                                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty {
                                    let range = result.range
                                    let startSec = CMTimeGetSeconds(range.start)
                                    let endSec = CMTimeGetSeconds(CMTimeRangeGetEnd(range))
                                    let startDate = startSec.isFinite
                                        ? capturedStartDate.addingTimeInterval(startSec)
                                        : Date()
                                    let endDate = endSec.isFinite
                                        ? capturedStartDate.addingTimeInterval(endSec)
                                        : Date()
                                    continuation.yield(.sentenceComplete(
                                        TranscriptionSentence(startTimestamp: startDate, timestamp: endDate, text: trimmed)
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

                // 9. Feed audio: accumulate ~200ms before batch sending.
                //    Track cumulative sample count to provide accurate bufferStartTime.
                var accumulator: [Float] = []
                let batchThreshold = Int(16_000 * 0.2)
                var cumulativeOutputFrames: Int64 = 0

                for await chunk in audioStream {
                    accumulator.append(contentsOf: chunk.samples)
                    guard accumulator.count >= batchThreshold else { continue }

                    let startTime = CMTime(value: cumulativeOutputFrames, timescale: CMTimeScale(outputSampleRate))
                    if let (input, frameCount) = Self.convertToAnalyzerInput(
                        samples: accumulator, converter: converter,
                        reusableBuffer: reusableBuffer, bufferStartTime: startTime
                    ) {
                        inputBuilder.yield(input)
                        cumulativeOutputFrames += Int64(frameCount)
                    }
                    accumulator.removeAll(keepingCapacity: true)
                }

                // Flush remaining
                if !accumulator.isEmpty {
                    let startTime = CMTime(value: cumulativeOutputFrames, timescale: CMTimeScale(outputSampleRate))
                    if let (input, _) = Self.convertToAnalyzerInput(
                        samples: accumulator, converter: converter,
                        reusableBuffer: reusableBuffer, bufferStartTime: startTime
                    ) {
                        inputBuilder.yield(input)
                    }
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
    /// Returns the input and the number of output frames written.
    /// Allocates a fresh output buffer each call so the AnalyzerInput's backing data
    /// is never overwritten before the analyzer consumes it (critical for faster-than-real-time input).
    private static func convertToAnalyzerInput(
        samples: [Float],
        converter: AVAudioConverter?,
        reusableBuffer: AVAudioPCMBuffer?,
        bufferStartTime: CMTime
    ) -> (AnalyzerInput, AVAudioFrameCount)? {
        guard let pcmBuffer = createPCMBuffer(from: samples) else { return nil }

        if let converter, let reusableBuffer {
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: reusableBuffer.format,
                frameCapacity: reusableBuffer.frameCapacity
            )!
            outputBuffer.frameLength = 0
            var error: NSError?
            nonisolated(unsafe) var consumed = false
            nonisolated(unsafe) let capturedBuffer = pcmBuffer
            converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                if consumed { outStatus.pointee = .noDataNow; return nil }
                consumed = true; outStatus.pointee = .haveData; return capturedBuffer
            }
            guard error == nil, outputBuffer.frameLength > 0 else { return nil }
            return (AnalyzerInput(buffer: outputBuffer, bufferStartTime: bufferStartTime), outputBuffer.frameLength)
        } else {
            return (AnalyzerInput(buffer: pcmBuffer, bufferStartTime: bufferStartTime), pcmBuffer.frameLength)
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
