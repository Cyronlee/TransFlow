import SwiftUI

/// Which speech-to-text backend to use.
enum TranscriptionEngineKind: String, CaseIterable, Identifiable, Sendable {
    case apple = "apple"
    case local = "local"

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .apple: "settings.engine.apple"
        case .local: "settings.engine.local"
        }
    }
}

/// Which local ASR model to use when the local engine is selected.
enum LocalTranscriptionModelKind: String, CaseIterable, Identifiable, Sendable {
    case parakeetOfflineInt8 = "parakeetOfflineInt8"
    case nemotronStreamingInt8 = "nemotronStreamingInt8"

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .parakeetOfflineInt8: "settings.local_model.parakeet"
        case .nemotronStreamingInt8: "settings.local_model.nemotron"
        }
    }

    var licenseNoticeKey: LocalizedStringKey {
        switch self {
        case .parakeetOfflineInt8:
            "settings.model.license_notice.parakeet"
        case .nemotronStreamingInt8:
            "settings.model.license_notice.nemotron"
        }
    }
}

/// Status of the locally-downloaded Parakeet model.
enum LocalModelStatus: Equatable, Sendable {
    /// Model files have not been downloaded yet.
    case notDownloaded
    /// Download is in progress.
    case downloading(progress: Double)
    /// Model is validated and ready to use.
    case ready
    /// Download or validation failed.
    case failed(message: String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}

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
