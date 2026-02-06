import Foundation

/// A completed transcription sentence with timestamp and optional translation.
struct TranscriptionSentence: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let text: String
    var translation: String?
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
    case appAudio(AppAudioTarget?)
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
