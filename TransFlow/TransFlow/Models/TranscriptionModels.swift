import Foundation

/// Identifies the audio pipeline that produced a transcription result.
enum TranscriptionSource: String, Sendable, Equatable, Hashable {
    case microphone
    case systemAudio
}

/// A completed transcription sentence with timestamp and optional translation.
struct TranscriptionSentence: Identifiable, Sendable {
    let id: UUID
    /// When the utterance started (first partial text appeared)
    let startTimestamp: Date
    /// When the sentence was finalized
    let timestamp: Date
    let text: String
    var translation: String?
    /// Assigned speaker (e.g. "speaker_0"), nil if diarization disabled or pending
    var speakerId: String?
    /// Which capture pipeline produced this sentence; nil for legacy single-source sessions.
    var source: TranscriptionSource?

    init(
        id: UUID = UUID(),
        startTimestamp: Date,
        timestamp: Date,
        text: String,
        translation: String? = nil,
        speakerId: String? = nil,
        source: TranscriptionSource? = nil
    ) {
        self.id = id
        self.startTimestamp = startTimestamp
        self.timestamp = timestamp
        self.text = text
        self.translation = translation
        self.speakerId = speakerId
        self.source = source
    }
}

/// Events emitted by the SpeechEngine during transcription.
enum TranscriptionEvent: Sendable {
    /// A volatile (in-progress) partial transcription
    case partial(String)
    /// A finalized complete sentence
    case sentenceComplete(TranscriptionSentence)
    /// An error occurred
    case error(String)
}

/// The current state of the listening session.
enum ListeningState: Sendable, Equatable {
    case idle
    case starting
    case active
    case stopping
}

/// Audio source type selection.
enum AudioSourceType: Sendable, Equatable, Hashable {
    case microphone
    case systemAudio
    case appAudio(AppAudioTarget?)
    case microphoneAndSystemAudio

    var isDualCapture: Bool {
        if case .microphoneAndSystemAudio = self { return true }
        return false
    }
}

/// Represents a running application that can be captured for audio.
struct AppAudioTarget: Identifiable, Sendable, Equatable, Hashable {
    let id: Int32 // process ID
    let name: String
    let bundleIdentifier: String?
    /// PNG icon data for the app (Sendable-safe representation of NSImage)
    let iconData: Data?

    static func == (lhs: AppAudioTarget, rhs: AppAudioTarget) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
