import SwiftUI
import Speech
import AVFoundation

/// Orchestrates the video transcription pipeline: file selection, audio extraction,
/// speech transcription, speaker diarization, translation, and persistence.
@Observable
@MainActor
final class VideoTranscriptionViewModel {

    // MARK: - State

    var state: VideoTranscriptionState = .idle
    var segments: [VideoTranscriptionSegment] = []
    var selectedFileURL: URL?
    var selectedFileName: String = ""
    var videoDuration: Double = 0

    /// Configuration
    var selectedLanguage: Locale = Locale(identifier: "en-US")
    var availableLanguages: [Locale] = []
    var enableDiarization: Bool = true
    var enableTranslation: Bool = false
    var targetLanguage: Locale.Language = Locale.Language(identifier: "zh-Hans")

    /// Progress
    var overallProgress: Double = 0
    var progressMessage: String = ""

    /// Video player for result preview
    var player: AVPlayer?
    var activeSegmentIndex: Int?
    var isVideoPlaying: Bool = false
    var currentPlaybackTime: Double = 0

    /// Error
    var errorMessage: String?

    // MARK: - Services

    let translationService = TranslationService()
    let modelManager = SpeechModelManager.shared
    let diarizationModelManager = DiarizationModelManager.shared
    let store = VideoJSONLStore()

    private let audioExtractor = AudioExtractorService()
    private let diarizationService = DiarizationService()
    private var processingTask: Task<Void, Never>?
    private var playbackTimer: Timer?

    // MARK: - Initialization

    init() {
        Task {
            await loadSupportedLanguages()
        }
    }

    private func loadSupportedLanguages() async {
        let locales = await SpeechTranscriber.supportedLocales
        availableLanguages = locales.map { Locale(identifier: $0.language.minimalIdentifier) }
            .sorted { $0.identifier < $1.identifier }
    }

    // MARK: - File Selection

    func selectFile(_ url: URL) async {
        selectedFileURL = url
        selectedFileName = url.lastPathComponent

        do {
            videoDuration = try await audioExtractor.mediaDuration(for: url)
            player = AVPlayer(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearFile() {
        selectedFileURL = nil
        selectedFileName = ""
        videoDuration = 0
        player = nil
        segments = []
        state = .idle
        activeSegmentIndex = nil
        stopPlaybackTimer()
    }

    // MARK: - Start Processing

    func startTranscription() {
        guard let fileURL = selectedFileURL else { return }
        guard !state.isProcessing else { return }

        segments = []
        errorMessage = nil

        processingTask = Task {
            do {
                // Step 1: Ensure speech model is ready
                let speechReady = await modelManager.ensureModelReady(for: selectedLanguage)
                guard speechReady else {
                    state = .failed(message: String(localized: "video.error.speech_model_not_ready"))
                    return
                }

                // Step 2: Extract audio
                state = .extractingAudio(progress: 0)
                progressMessage = String(localized: "video.progress.extracting_audio")
                overallProgress = 0.05

                let audioSamples = try await audioExtractor.extractAudio(from: fileURL)

                guard !Task.isCancelled else { return }
                overallProgress = 0.2
                state = .extractingAudio(progress: 1.0)

                // Step 3: Transcription (Apple Speech)
                state = .transcribing(progress: 0)
                progressMessage = String(localized: "video.progress.transcribing")

                let transcriptionSentences = try await transcribeAudio(
                    samples: audioSamples,
                    locale: selectedLanguage
                )

                guard !Task.isCancelled else { return }
                overallProgress = 0.5

                // Step 4: Diarization (if enabled)
                var diarizationSegments: [DiarizationService.SpeakerSegment] = []
                if enableDiarization {
                    state = .diarizing
                    progressMessage = String(localized: "video.progress.diarizing")

                    diarizationSegments = try await diarizationService.performDiarization(audio: audioSamples)
                    overallProgress = 0.7
                }

                guard !Task.isCancelled else { return }

                // Step 5: Merge transcription + diarization
                state = .merging
                progressMessage = String(localized: "video.progress.merging")

                var mergedSegments = mergeResults(
                    sentences: transcriptionSentences,
                    diarization: diarizationSegments,
                    sessionStart: Date()
                )

                overallProgress = 0.8

                // Step 6: Translation (if enabled)
                if enableTranslation {
                    state = .translating(progress: 0)
                    progressMessage = String(localized: "video.progress.translating")

                    mergedSegments = await translateSegments(mergedSegments)
                    overallProgress = 0.95
                }

                guard !Task.isCancelled else { return }

                // Step 7: Save to JSONL
                let metadata = VideoJSONLMetadata(
                    videoFile: fileURL.lastPathComponent,
                    durationSeconds: videoDuration,
                    sourceLanguage: selectedLanguage.identifier,
                    targetLanguage: enableTranslation ? targetLanguage.minimalIdentifier : nil,
                    diarizationEnabled: enableDiarization
                )
                store.createSession(metadata: metadata)
                store.appendSegments(mergedSegments)

                // Done
                segments = mergedSegments
                overallProgress = 1.0
                state = .completed
                progressMessage = String(localized: "video.progress.completed")

            } catch {
                if !Task.isCancelled {
                    state = .failed(message: error.localizedDescription)
                    errorMessage = error.localizedDescription
                    ErrorLogger.shared.log(
                        "Video transcription failed: \(error.localizedDescription)",
                        source: "VideoTranscription"
                    )
                }
            }
        }
    }

    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        state = .idle
        progressMessage = ""
        overallProgress = 0
    }

    // MARK: - Transcription

    private func transcribeAudio(
        samples: [Float],
        locale: Locale
    ) async throws -> [TranscriptionSentence] {
        let engine = SpeechEngine(locale: locale)

        // Use 200ms chunks to match SpeechEngine's internal accumulator.
        // Pace delivery with a small sleep to prevent SpeechAnalyzer timestamp overlap errors.
        let chunkSize = 16_000 / 5 // 200ms = 3200 samples
        let totalSamples = samples.count

        // SpeechAnalyzer errors with "timestamp overlaps" when flooded with audio
        // faster than it can process. For file-based transcription we pace delivery:
        // yield one 200ms chunk, then sleep briefly to let the analyzer keep up.
        let stream = AsyncStream<AudioChunk> { continuation in
            Task.detached {
                var offset = 0
                let sessionStart = Date()
                while offset < totalSamples {
                    let end = min(offset + chunkSize, totalSamples)
                    let slice = Array(samples[offset..<end])
                    let level = slice.reduce(Float(0)) { max($0, abs($1)) }
                    let timestamp = sessionStart.addingTimeInterval(Double(offset) / 16_000)

                    continuation.yield(AudioChunk(
                        samples: slice,
                        level: min(level, 1.0),
                        timestamp: timestamp
                    ))
                    offset = end

                    // Small yield to prevent starving the SpeechEngine consumer task
                    try? await Task.sleep(for: .milliseconds(5))
                }
                continuation.finish()
            }
        }

        var sentences: [TranscriptionSentence] = []
        let events = engine.processStream(stream)

        let estimatedSentences = max(Double(totalSamples) / 16_000 / 5, 1)
        for await event in events {
            switch event {
            case .sentenceComplete(let sentence):
                sentences.append(sentence)
                let progress = Double(sentences.count) / estimatedSentences
                state = .transcribing(progress: min(progress, 1.0))
            case .partial:
                break
            case .error(let message):
                ErrorLogger.shared.log("Transcription error: \(message)", source: "VideoTranscription")
            }
        }

        return sentences
    }

    // MARK: - Merge

    /// Merge transcription sentences with diarization segments.
    /// Converts absolute Date timestamps to seconds-from-start offsets.
    private func mergeResults(
        sentences: [TranscriptionSentence],
        diarization: [DiarizationService.SpeakerSegment],
        sessionStart: Date
    ) -> [VideoTranscriptionSegment] {
        guard let firstSentence = sentences.first else { return [] }
        let baseDate = firstSentence.startTimestamp

        return sentences.map { sentence in
            let startSec = sentence.startTimestamp.timeIntervalSince(baseDate)
            let endSec = sentence.timestamp.timeIntervalSince(baseDate)

            let speakerId: String?
            if !diarization.isEmpty {
                speakerId = DiarizationService.assignSpeaker(
                    sentenceStart: startSec,
                    sentenceEnd: endSec,
                    diarizationSegments: diarization
                )
            } else {
                speakerId = nil
            }

            return VideoTranscriptionSegment(
                startTime: max(0, startSec),
                endTime: max(0, endSec),
                text: sentence.text,
                translation: sentence.translation,
                speakerId: speakerId
            )
        }
    }

    // MARK: - Translation

    private func translateSegments(_ segments: [VideoTranscriptionSegment]) async -> [VideoTranscriptionSegment] {
        var result = segments
        let total = Double(segments.count)

        for i in result.indices {
            if Task.isCancelled { break }

            if let translation = await translationService.translateSentence(result[i].text) {
                result[i].translation = translation
            }

            let progress = Double(i + 1) / total
            state = .translating(progress: progress)
        }

        return result
    }

    // MARK: - Video Playback

    func seekToSegment(at index: Int) {
        guard index >= 0, index < segments.count else { return }
        let segment = segments[index]
        let time = CMTime(seconds: segment.startTime, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        activeSegmentIndex = index
    }

    func togglePlayback() {
        guard let player else { return }
        if isVideoPlaying {
            player.pause()
            isVideoPlaying = false
            stopPlaybackTimer()
        } else {
            player.play()
            isVideoPlaying = true
            startPlaybackTimer()
        }
    }

    private func startPlaybackTimer() {
        stopPlaybackTimer()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePlaybackState()
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func updatePlaybackState() {
        guard let player, let currentItem = player.currentItem else { return }
        let time = CMTimeGetSeconds(player.currentTime())
        currentPlaybackTime = time

        if player.rate == 0 && isVideoPlaying {
            let duration = CMTimeGetSeconds(currentItem.duration)
            if time >= duration - 0.1 {
                isVideoPlaying = false
                stopPlaybackTimer()
            }
        }

        // Update active segment
        var best: Int?
        for (i, seg) in segments.enumerated() {
            if time >= seg.startTime && time < seg.endTime {
                best = i
                break
            }
        }
        if activeSegmentIndex != best {
            activeSegmentIndex = best
        }
    }

    // MARK: - Load from History

    func loadSession(from sessionFile: VideoSessionFile) async {
        let entries = store.readEntries(from: sessionFile.url)
        let metadata = store.readMetadata(from: sessionFile.url)

        segments = entries.map { entry in
            VideoTranscriptionSegment(
                startTime: entry.startTime,
                endTime: entry.endTime,
                text: entry.originalText,
                translation: entry.translatedText,
                speakerId: entry.speakerId
            )
        }

        if let videoFile = metadata?.videoFile {
            selectedFileName = videoFile
        }
        if let duration = metadata?.durationSeconds {
            videoDuration = duration
        }

        state = .completed
    }
}
