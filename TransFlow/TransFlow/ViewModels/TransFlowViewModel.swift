import SwiftUI
import Speech

/// Main ViewModel coordinating all services: audio capture, speech engine, and translation.
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

    /// Apple Speech model manager for asset checking and downloading.
    let modelManager = SpeechModelManager.shared

    /// Local Parakeet model manager for download/validation.
    let localModelManager = LocalModelManager.shared

    /// JSONL persistence store for the current session.
    let jsonlStore = JSONLStore()

    // MARK: - Private

    private let audioCaptureService = AudioCaptureService()
    private var speechEngine: (any TranscriptionEngine)?
    private var stopAudioCapture: (@Sendable () -> Void)?
    private var listeningTask: Task<Void, Never>?
    private var audioLevelTask: Task<Void, Never>?

    // MARK: - Initialization

    init() {
        Task {
            await initialize()
        }
    }

    private func initialize() async {
        // Create initial JSONL session for this app launch
        jsonlStore.createSession()

        // Request microphone permission
        micPermissionGranted = await AudioCaptureService.requestPermission()

        // Sync initial transcription language to translation service
        translationService.updateSourceLanguage(from: selectedLanguage)

        // Load supported languages
        await loadSupportedLanguages()

        // Load available apps
        await refreshAvailableApps()

        // Engine-specific initialization
        let engine = AppSettings.shared.selectedEngine
        if engine == .apple {
            // Check model status for the default transcription language
            await modelManager.checkCurrentStatus(for: selectedLanguage)
            if !modelManager.currentModelStatus.isReady {
                await modelManager.ensureModelReady(for: selectedLanguage)
            }
        } else {
            // Parakeet: check local model status
            localModelManager.checkStatus()
        }
    }

    // MARK: - Language

    func loadSupportedLanguages() async {
        if AppSettings.shared.selectedEngine == .apple {
            let locales = await SpeechTranscriber.supportedLocales
            availableLanguages = locales.map { Locale(identifier: $0.language.minimalIdentifier) }
                .sorted { $0.identifier < $1.identifier }
        } else {
            // Parakeet TDT 0.6B v2 supports English only
            availableLanguages = [Locale(identifier: "en-US")]
            selectedLanguage = Locale(identifier: "en-US")
        }
    }

    func switchLanguage(to locale: Locale) {
        // Language switching only applies to Apple engine
        guard AppSettings.shared.selectedEngine == .apple else { return }

        let wasListening = listeningState == .active
        if wasListening {
            stopListening()
        }
        selectedLanguage = locale
        speechEngine = AppleSpeechEngine(locale: locale)

        // Sync transcription language to translation source language
        translationService.updateSourceLanguage(from: locale)

        // Check and download model for the new language
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
                // Create the appropriate engine based on settings
                let selectedEngineKind = AppSettings.shared.selectedEngine
                let engine: any TranscriptionEngine

                switch selectedEngineKind {
                case .apple:
                    // Ensure Apple Speech model is ready
                    let modelReady = await modelManager.ensureModelReady(for: selectedLanguage)
                    guard modelReady else {
                        showModelNotReadyAlert = true
                        listeningState = .idle
                        return
                    }
                    engine = AppleSpeechEngine(locale: selectedLanguage)

                case .parakeetLocal:
                    // Ensure Parakeet model is downloaded and ready
                    localModelManager.checkStatus()
                    guard localModelManager.status.isReady else {
                        showModelNotReadyAlert = true
                        listeningState = .idle
                        return
                    }
                    engine = ParakeetSpeechEngine(modelDirectory: localModelManager.modelDirectory)
                }

                self.speechEngine = engine

                // Start audio capture based on source
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

                // Fork audio stream: one for engine, one for UI level
                let (engineStream, engineContinuation) = AsyncStream<AudioChunk>.makeStream(
                    bufferingPolicy: .bufferingNewest(256)
                )
                let (levelStream, levelContinuation) = AsyncStream<AudioChunk>.makeStream(
                    bufferingPolicy: .bufferingNewest(64)
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

                // Fork task
                let forkTask = Task.detached {
                    for await chunk in audioStream {
                        engineContinuation.yield(chunk)
                        levelContinuation.yield(chunk)
                    }
                    engineContinuation.finish()
                    levelContinuation.finish()
                }

                listeningState = .active
                errorMessage = nil

                // Process transcription events
                let events = engine.processStream(engineStream)
                for await event in events {
                    switch event {
                    case .partial(let text):
                        currentPartialText = text
                        translationService.translatePartial(text)

                    case .sentenceComplete(var sentence):
                        // Translate complete sentence
                        if let translation = await translationService.translateSentence(sentence.text) {
                            sentence.translation = translation
                        }
                        sentences.append(sentence)
                        // Persist to JSONL
                        jsonlStore.appendEntry(sentence: sentence)
                        currentPartialText = ""
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
                let sentence = TranscriptionSentence(timestamp: Date(), text: trimmed)
                sentences.append(sentence)
                // Persist to JSONL
                jsonlStore.appendEntry(sentence: sentence)
            }
            currentPartialText = ""
        }

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

    /// Create a new session, clearing in-memory data and starting a fresh JSONL file.
    func createNewSession(name: String? = nil) {
        // Stop listening if active
        if listeningState != .idle {
            stopListening()
        }
        // Clear in-memory state
        sentences.removeAll()
        currentPartialText = ""
        translationService.currentPartialTranslation = ""
        // Create new JSONL file
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
