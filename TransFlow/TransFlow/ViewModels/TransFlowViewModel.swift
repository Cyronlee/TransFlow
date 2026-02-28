import SwiftUI
import Speech

/// Main ViewModel coordinating all services: audio capture, speech engine, translation, and recording.
@Observable
@MainActor
final class TransFlowViewModel {
    // MARK: - Published State

    /// Completed transcription sentences history
    var sentences: [TranscriptionSentence] = []
    /// Current volatile partial text
    var currentPartialText: String = ""
    /// Current listening state
    var listeningState: ListeningState = .idle
    /// Current audio level (0-1)
    var audioLevel: Float = 0
    /// Audio level waveform history
    var audioLevelHistory: [Float] = Array(repeating: 0, count: 30)
    /// Selected audio source
    var audioSource: AudioSourceType = .microphone
    /// Selected transcription language
    var selectedLanguage: Locale = Locale(identifier: "en-US")
    /// Available transcription languages
    var availableLanguages: [Locale] = []
    /// Available apps for audio capture
    var availableApps: [AppAudioTarget] = []
    /// Error message
    var errorMessage: String?
    /// Whether to show the "model not ready" alert prompting user to go to Settings.
    var showModelNotReadyAlert: Bool = false
    /// Microphone permission granted
    var micPermissionGranted: Bool = false

    /// Translation service (observed separately for SwiftUI binding)
    let translationService = TranslationService()

    /// Speech model manager for asset checking and downloading.
    let modelManager = SpeechModelManager.shared

    /// JSONL persistence store for the current session.
    let jsonlStore = JSONLStore()

    // MARK: - Private

    private let audioCaptureService = AudioCaptureService()
    private let audioRecordingService = AudioRecordingService()
    private var speechEngine: SpeechEngine?
    private var stopAudioCapture: (@Sendable () -> Void)?
    private var listeningTask: Task<Void, Never>?
    private var audioLevelTask: Task<Void, Never>?
    private var recordingTask: Task<Void, Never>?

    /// Current recording file name (set while recording is active).
    private var currentRecordingFileName: String?

    /// When the current partial utterance started (for flushing on stop).
    private var partialStartTimestamp: Date?

    // MARK: - Initialization

    init() {
        Task {
            await initialize()
        }
    }

    private func initialize() async {
        jsonlStore.createSession()
        micPermissionGranted = await AudioCaptureService.requestPermission()
        translationService.updateSourceLanguage(from: selectedLanguage)
        await loadSupportedLanguages()
        await refreshAvailableApps()
        await modelManager.checkCurrentStatus(for: selectedLanguage)
        if !modelManager.currentModelStatus.isReady {
            await modelManager.ensureModelReady(for: selectedLanguage)
        }
    }

    // MARK: - Language

    func loadSupportedLanguages() async {
        let locales = await SpeechTranscriber.supportedLocales
        availableLanguages = locales.map { Locale(identifier: $0.language.minimalIdentifier) }
            .sorted { $0.identifier < $1.identifier }
    }

    func switchLanguage(to locale: Locale) {
        let wasListening = listeningState == .active
        if wasListening {
            stopListening()
        }
        selectedLanguage = locale
        speechEngine = SpeechEngine(locale: locale)
        translationService.updateSourceLanguage(from: locale)

        Task {
            await modelManager.checkCurrentStatus(for: locale)
            if !modelManager.currentModelStatus.isReady {
                await modelManager.ensureModelReady(for: locale)
            }
        }

        if wasListening {
            startListening()
        }
    }

    // MARK: - App Audio

    func refreshAvailableApps() async {
        availableApps = await AppAudioCaptureService.availableApps()
    }

    // MARK: - Listening

    func startListening() {
        guard listeningState == .idle else { return }
        listeningState = .starting

        listeningTask = Task {
            do {
                let modelReady = await modelManager.ensureModelReady(for: selectedLanguage)
                guard modelReady else {
                    showModelNotReadyAlert = true
                    listeningState = .idle
                    return
                }

                let engine = SpeechEngine(locale: selectedLanguage)
                self.speechEngine = engine

                let audioStream: AsyncStream<AudioChunk>
                let stop: @Sendable () -> Void

                switch audioSource {
                case .microphone:
                    guard micPermissionGranted else {
                        errorMessage = "Microphone permission not granted"
                        ErrorLogger.shared.log("Microphone permission not granted", source: "AudioCapture")
                        listeningState = .idle
                        return
                    }
                    let capture = audioCaptureService.startCapture()
                    audioStream = capture.stream
                    stop = capture.stop

                case .appAudio(let target):
                    guard let target else {
                        errorMessage = "No app selected"
                        ErrorLogger.shared.log("No app selected for audio capture", source: "AudioCapture")
                        listeningState = .idle
                        return
                    }
                    let capture = try await AppAudioCaptureService.startCapture(for: target)
                    audioStream = capture.stream
                    stop = capture.stop
                }

                self.stopAudioCapture = stop

                // Fork audio stream: engine, UI level, and recording
                let (engineStream, engineContinuation) = AsyncStream<AudioChunk>.makeStream(
                    bufferingPolicy: .bufferingNewest(256)
                )
                let (levelStream, levelContinuation) = AsyncStream<AudioChunk>.makeStream(
                    bufferingPolicy: .bufferingNewest(64)
                )
                let (recordingStream, recordingContinuation) = AsyncStream<AudioChunk>.makeStream(
                    bufferingPolicy: .bufferingNewest(256)
                )

                // Audio level update task
                audioLevelTask = Task {
                    for await chunk in levelStream {
                        self.audioLevel = chunk.level
                        self.audioLevelHistory.append(chunk.level)
                        if self.audioLevelHistory.count > 30 {
                            self.audioLevelHistory.removeFirst()
                        }
                    }
                }

                // Start recording — each start creates a new uniquely-named file
                let (recFileName, recStartTime) = audioRecordingService.startRecording()
                self.currentRecordingFileName = recFileName
                jsonlStore.appendRecordingStart(fileName: recFileName, timestamp: recStartTime)

                nonisolated(unsafe) let recorder = audioRecordingService
                recordingTask = Task.detached {
                    for await chunk in recordingStream {
                        recorder.writeChunk(chunk)
                    }
                }

                // Fork task — fan out audio to all three consumers
                let forkTask = Task.detached {
                    for await chunk in audioStream {
                        engineContinuation.yield(chunk)
                        levelContinuation.yield(chunk)
                        recordingContinuation.yield(chunk)
                    }
                    engineContinuation.finish()
                    levelContinuation.finish()
                    recordingContinuation.finish()
                }

                listeningState = .active
                errorMessage = nil

                let events = engine.processStream(engineStream)
                for await event in events {
                    switch event {
                    case .partial(let text):
                        if partialStartTimestamp == nil && !text.isEmpty {
                            partialStartTimestamp = Date()
                        }
                        currentPartialText = text
                        translationService.translatePartial(text)

                    case .sentenceComplete(var sentence):
                        if let translation = await translationService.translateSentence(sentence.text) {
                            sentence.translation = translation
                        }
                        sentences.append(sentence)
                        jsonlStore.appendEntry(sentence: sentence)
                        currentPartialText = ""
                        partialStartTimestamp = nil
                        translationService.currentPartialTranslation = ""

                    case .error(let message):
                        errorMessage = message
                        ErrorLogger.shared.log(message, source: "Transcription")
                    }
                }


                forkTask.cancel()

            } catch {
                errorMessage = error.localizedDescription
                ErrorLogger.shared.log("Listening failed: \(error.localizedDescription)", source: "AudioCapture")
            }

            listeningState = .idle
            audioLevel = 0
        }
    }

    func stopListening() {
        guard listeningState == .active || listeningState == .starting else { return }
        listeningState = .stopping

        // Flush remaining partial text as a final sentence
        if !currentPartialText.isEmpty {
            let trimmed = currentPartialText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let sentence = TranscriptionSentence(
                    startTimestamp: partialStartTimestamp ?? Date(),
                    timestamp: Date(),
                    text: trimmed
                )
                sentences.append(sentence)
                jsonlStore.appendEntry(sentence: sentence)
            }
            currentPartialText = ""
            partialStartTimestamp = nil
        }

        // Stop recording and write marker
        if let info = audioRecordingService.stopRecording(), let recFileName = currentRecordingFileName {
            jsonlStore.appendRecordingStop(fileName: recFileName, durationMs: info.durationMs)
        }
        recordingTask?.cancel()
        recordingTask = nil
        currentRecordingFileName = nil

        stopAudioCapture?()
        stopAudioCapture = nil
        audioLevelTask?.cancel()
        audioLevelTask = nil
        listeningTask?.cancel()
        listeningTask = nil

        listeningState = .idle
        audioLevel = 0
        translationService.currentPartialTranslation = ""
    }

    func toggleListening() {
        if listeningState == .idle {
            startListening()
        } else {
            stopListening()
        }
    }

    // MARK: - Session

    func createNewSession(name: String? = nil) {
        if listeningState != .idle {
            stopListening()
        }
        sentences.removeAll()
        currentPartialText = ""
        translationService.currentPartialTranslation = ""
        jsonlStore.createSession(name: name)
    }

    // MARK: - History

    func clearHistory() {
        sentences.removeAll()
        currentPartialText = ""
        translationService.currentPartialTranslation = ""
    }

    // MARK: - Export

    func exportSRT() async {
        await SRTExporter.exportToFile(sentences: sentences)
    }
}
