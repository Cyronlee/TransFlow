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

    /// Configuration — identifiers used as Picker tags to avoid Locale equality issues
    var selectedLanguageId: String = AppSettings.shared.videoSourceLanguage
    var availableLanguages: [(id: String, locale: Locale)] = []
    var enableDiarization: Bool = AppSettings.shared.videoEnableDiarization
    var diarizationSensitivity: Double = AppSettings.shared.diarizationSensitivity
    var enableTranslation: Bool = AppSettings.shared.videoEnableTranslation
    var targetLanguage: Locale.Language = Locale.Language(identifier: AppSettings.shared.videoTargetLanguage)

    /// Progress
    var overallProgress: Double = 0
    var progressMessage: String = ""

    /// Video player for result preview
    var player: AVPlayer?
    var activeSegmentIndex: Int?
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
    private var timeObserverToken: Any?

    // MARK: - Initialization

    init() {
        Task {
            await loadSupportedLanguages()
        }
    }

    private func loadSupportedLanguages() async {
        let locales = await SpeechTranscriber.supportedLocales
        availableLanguages = locales.map { locale -> (id: String, locale: Locale) in
            let id = locale.language.minimalIdentifier
            return (id: id, locale: Locale(identifier: id))
        }.sorted { $0.id < $1.id }

        if !availableLanguages.contains(where: { $0.id == selectedLanguageId }),
           let first = availableLanguages.first {
            selectedLanguageId = first.id
        }
    }

    /// Resolved Locale for the currently selected language identifier.
    var selectedLocale: Locale {
        Locale(identifier: selectedLanguageId)
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
        stopPlaybackObservation()
        selectedFileURL = nil
        selectedFileName = ""
        videoDuration = 0
        player = nil
        segments = []
        state = .idle
        activeSegmentIndex = nil
    }

    private func saveConfigToSettings() {
        let settings = AppSettings.shared
        settings.videoSourceLanguage = selectedLanguageId
        settings.videoEnableTranslation = enableTranslation
        settings.videoTargetLanguage = targetLanguage.minimalIdentifier
        settings.videoEnableDiarization = enableDiarization
        settings.diarizationSensitivity = diarizationSensitivity
    }

    // MARK: - Start Processing

    func startTranscription() {
        guard let fileURL = selectedFileURL else { return }
        guard !state.isProcessing else { return }

        segments = []
        errorMessage = nil
        saveConfigToSettings()

        processingTask = Task {
            do {
                // Step 1: Ensure speech model is ready
                let speechReady = await modelManager.ensureModelReady(for: selectedLocale)
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
                    locale: selectedLocale
                )

                guard !Task.isCancelled else { return }
                overallProgress = 0.5

                // Step 4: Diarization (if enabled)
                var diarizationSegments: [DiarizationService.SpeakerSegment] = []
                if enableDiarization {
                    state = .diarizing
                    progressMessage = String(localized: "video.progress.diarizing")

                    AppSettings.shared.diarizationSensitivity = diarizationSensitivity
                    diarizationSegments = try await diarizationService.performDiarization(
                        audio: audioSamples,
                        clusteringThreshold: diarizationSensitivity
                    )
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
                    originalFilePath: fileURL.path,
                    durationSeconds: videoDuration,
                    sourceLanguage: selectedLanguageId,
                    targetLanguage: enableTranslation ? targetLanguage.minimalIdentifier : nil,
                    diarizationEnabled: enableDiarization
                )
                let sessionName = store.createSession(metadata: metadata)
                store.appendSegments(mergedSegments)

                // Done — navigate to history page
                segments = mergedSegments
                overallProgress = 1.0
                state = .completed
                progressMessage = String(localized: "video.progress.completed")

                NotificationCenter.default.post(
                    name: .navigateToHistory,
                    object: nil,
                    userInfo: ["sessionID": "video_\(sessionName)"]
                )

                // Reset after a short delay so the page is ready for next use
                try? await Task.sleep(for: .milliseconds(300))
                clearFile()

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
    /// When a sentence spans multiple speaker segments, split it at speaker boundaries
    /// so each output segment belongs to a single speaker.
    private func mergeResults(
        sentences: [TranscriptionSentence],
        diarization: [DiarizationService.SpeakerSegment],
        sessionStart: Date
    ) -> [VideoTranscriptionSegment] {
        guard let firstSentence = sentences.first else { return [] }
        let baseDate = firstSentence.startTimestamp

        if diarization.isEmpty {
            return sentences.map { sentence in
                VideoTranscriptionSegment(
                    startTime: max(0, sentence.startTimestamp.timeIntervalSince(baseDate)),
                    endTime: max(0, sentence.timestamp.timeIntervalSince(baseDate)),
                    text: sentence.text,
                    translation: sentence.translation,
                    speakerId: nil
                )
            }
        }

        var result: [VideoTranscriptionSegment] = []

        for sentence in sentences {
            let sentStart = sentence.startTimestamp.timeIntervalSince(baseDate)
            let sentEnd = sentence.timestamp.timeIntervalSince(baseDate)
            let sentDuration = sentEnd - sentStart

            let overlapping = diarization.filter { seg in
                seg.startTime < sentEnd && seg.endTime > sentStart
            }

            if overlapping.count <= 1 {
                let speakerId = DiarizationService.assignSpeaker(
                    sentenceStart: sentStart,
                    sentenceEnd: sentEnd,
                    diarizationSegments: diarization
                )
                result.append(VideoTranscriptionSegment(
                    startTime: max(0, sentStart),
                    endTime: max(0, sentEnd),
                    text: sentence.text,
                    translation: sentence.translation,
                    speakerId: speakerId
                ))
                continue
            }

            let speakerRuns = buildSpeakerRuns(sentStart: sentStart, sentEnd: sentEnd, segments: overlapping)
            guard speakerRuns.count > 1 else {
                result.append(VideoTranscriptionSegment(
                    startTime: max(0, sentStart),
                    endTime: max(0, sentEnd),
                    text: sentence.text,
                    translation: sentence.translation,
                    speakerId: speakerRuns.first?.speakerId
                ))
                continue
            }

            let textSlices = splitTextAtPunctuationBoundaries(
                text: sentence.text,
                speakerRuns: speakerRuns,
                sentStart: sentStart,
                sentDuration: sentDuration
            )
            let translationSlices: [String?]
            if let trans = sentence.translation, !trans.isEmpty {
                translationSlices = splitTextAtPunctuationBoundaries(
                    text: trans,
                    speakerRuns: speakerRuns,
                    sentStart: sentStart,
                    sentDuration: sentDuration
                )
            } else {
                translationSlices = Array(repeating: nil, count: speakerRuns.count)
            }

            for (i, run) in speakerRuns.enumerated() {
                let text = i < textSlices.count ? textSlices[i] : ""
                guard !text.isEmpty else { continue }
                result.append(VideoTranscriptionSegment(
                    startTime: max(0, run.startTime),
                    endTime: max(0, run.endTime),
                    text: text,
                    translation: i < translationSlices.count ? translationSlices[i] : nil,
                    speakerId: run.speakerId
                ))
            }
        }

        return result
    }

    /// Build contiguous speaker runs within a sentence's time range from overlapping diarization segments.
    private func buildSpeakerRuns(
        sentStart: Double,
        sentEnd: Double,
        segments: [DiarizationService.SpeakerSegment]
    ) -> [(speakerId: String, startTime: Double, endTime: Double)] {
        struct TimePoint: Comparable {
            let time: Double
            let speakerId: String?
            let isStart: Bool
            static func < (lhs: TimePoint, rhs: TimePoint) -> Bool { lhs.time < rhs.time }
        }

        var timeline: [(speakerId: String, startTime: Double, endTime: Double)] = []
        let sorted = segments.sorted { $0.startTime < $1.startTime }

        var cursor = sentStart
        for seg in sorted {
            let segStart = max(seg.startTime, sentStart)
            let segEnd = min(seg.endTime, sentEnd)
            guard segStart < segEnd else { continue }

            if segStart > cursor {
                if let last = timeline.last {
                    timeline[timeline.count - 1] = (last.speakerId, last.startTime, segStart)
                }
            }
            cursor = segEnd

            if let last = timeline.last, last.speakerId == seg.speakerId {
                timeline[timeline.count - 1] = (last.speakerId, last.startTime, segEnd)
            } else {
                timeline.append((seg.speakerId, segStart, segEnd))
            }
        }

        if let last = timeline.last, last.endTime < sentEnd {
            timeline[timeline.count - 1] = (last.speakerId, last.startTime, sentEnd)
        }

        return timeline
    }

    /// Split text into N slices corresponding to speaker runs, snapping to punctuation boundaries.
    ///
    /// 1. Compute the ideal split position (character index) for each boundary based on time proportion.
    /// 2. Search nearby for a punctuation character (. , ! ? ; : 。，！？；：) within a window.
    /// 3. Prefer the nearest punctuation after the ideal point; fall back to before; fall back to a
    ///    word boundary (space); and finally fall back to the raw proportional position.
    private func splitTextAtPunctuationBoundaries(
        text: String,
        speakerRuns: [(speakerId: String, startTime: Double, endTime: Double)],
        sentStart: Double,
        sentDuration: Double
    ) -> [String] {
        guard speakerRuns.count > 1, !text.isEmpty else {
            return [text]
        }

        let chars = Array(text)
        let totalChars = chars.count

        let punctuationSet = CharacterSet(charactersIn: ".,!?;:。，！？；：、）)」】》")
        let searchRadius = max(totalChars / 6, 8)

        var splitIndices: [Int] = []
        var cumulativeTime = 0.0
        for i in 0..<(speakerRuns.count - 1) {
            let runDuration = speakerRuns[i].endTime - speakerRuns[i].startTime
            cumulativeTime += runDuration
            let idealFraction = sentDuration > 0 ? cumulativeTime / sentDuration : Double(i + 1) / Double(speakerRuns.count)
            let idealIdx = Int(round(idealFraction * Double(totalChars)))

            let splitIdx = findBestSplitPoint(
                chars: chars,
                idealIndex: idealIdx,
                searchRadius: searchRadius,
                punctuationSet: punctuationSet
            )
            splitIndices.append(splitIdx)
        }

        for i in 1..<splitIndices.count {
            if splitIndices[i] <= splitIndices[i - 1] {
                splitIndices[i] = min(splitIndices[i - 1] + 1, totalChars)
            }
        }

        var slices: [String] = []
        var cursor = 0
        for splitIdx in splitIndices {
            let end = min(max(splitIdx, cursor), totalChars)
            let slice = String(chars[cursor..<end]).trimmingCharacters(in: .whitespaces)
            slices.append(slice)
            cursor = end
        }
        let lastSlice = String(chars[cursor..<totalChars]).trimmingCharacters(in: .whitespaces)
        slices.append(lastSlice)

        return slices
    }

    /// Find the best character index to split text near `idealIndex`, preferring punctuation boundaries.
    private func findBestSplitPoint(
        chars: [Character],
        idealIndex: Int,
        searchRadius: Int,
        punctuationSet: CharacterSet
    ) -> Int {
        let totalChars = chars.count
        let clampedIdeal = min(max(idealIndex, 0), totalChars)

        let searchStart = max(0, clampedIdeal - searchRadius)
        let searchEnd = min(totalChars, clampedIdeal + searchRadius)

        var bestPunctAfter: Int? = nil
        for i in clampedIdeal..<searchEnd {
            if i < totalChars && chars[i].unicodeScalars.allSatisfy({ punctuationSet.contains($0) }) {
                bestPunctAfter = i + 1
                break
            }
        }

        var bestPunctBefore: Int? = nil
        for i in stride(from: clampedIdeal - 1, through: searchStart, by: -1) {
            if i >= 0 && i < totalChars && chars[i].unicodeScalars.allSatisfy({ punctuationSet.contains($0) }) {
                bestPunctBefore = i + 1
                break
            }
        }

        if let after = bestPunctAfter, let before = bestPunctBefore {
            let distAfter = after - clampedIdeal
            let distBefore = clampedIdeal - before
            return distAfter <= distBefore ? after : before
        }
        if let after = bestPunctAfter { return after }
        if let before = bestPunctBefore { return before }

        var bestSpace: Int? = nil
        var bestSpaceDist = Int.max
        for i in searchStart..<searchEnd {
            if i < totalChars && chars[i] == " " {
                let dist = abs(i - clampedIdeal)
                if dist < bestSpaceDist {
                    bestSpaceDist = dist
                    bestSpace = i
                }
            }
        }
        if let space = bestSpace { return space }

        return clampedIdeal
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
        player?.play()
        activeSegmentIndex = index
    }

    func startPlaybackObservation() {
        guard let player, timeObserverToken == nil else { return }
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] cmTime in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let time = CMTimeGetSeconds(cmTime)
                self.currentPlaybackTime = time

                var best: Int?
                for (i, seg) in self.segments.enumerated() {
                    if time >= seg.startTime && time < seg.endTime {
                        best = i
                        break
                    }
                }
                if self.activeSegmentIndex != best {
                    self.activeSegmentIndex = best
                }
            }
        }
    }

    private func stopPlaybackObservation() {
        if let token = timeObserverToken, let player {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil
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
