import Foundation

/// A transcription segment from a video file, with optional speaker identification.
struct VideoTranscriptionSegment: Identifiable, Sendable {
    let id = UUID()
    /// Offset from video start in seconds
    let startTime: Double
    /// Offset from video start in seconds
    let endTime: Double
    let text: String
    var translation: String?
    /// Assigned speaker (e.g. "Speaker_1"), nil if diarization disabled
    var speakerId: String?
}

/// Processing state for the video transcription pipeline.
enum VideoTranscriptionState: Sendable, Equatable {
    case idle
    case selectingFile
    case extractingAudio(progress: Double)
    case transcribing(progress: Double)
    case diarizing
    case translating(progress: Double)
    case merging
    case completed
    case failed(message: String)

    var isProcessing: Bool {
        switch self {
        case .extractingAudio, .transcribing, .diarizing, .translating, .merging:
            return true
        default:
            return false
        }
    }
}

/// Status of the diarization model on disk.
enum DiarizationModelStatus: Sendable, Equatable {
    case installed
    case notDownloaded
    case downloading(progress: Double)
    case failed(message: String)
    case checking

    var isReady: Bool {
        if case .installed = self { return true }
        return false
    }

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}

/// Speaker color assignment for UI display.
struct SpeakerColor: Sendable {
    static let palette: [String] = [
        "#4A90D9", "#E5534B", "#57AB5A", "#DAAA3F",
        "#986EE2", "#E5734B", "#39B5AC", "#DB6D99"
    ]

    static func color(for speakerId: String) -> String {
        let index = abs(speakerId.hashValue) % palette.count
        return palette[index]
    }
}

/// Converts a raw speaker ID (e.g. "speaker_0") to a localized display name.
/// If the ID has already been customized (doesn't match the raw pattern), returns it as-is.
enum SpeakerDisplayName {
    static func displayName(for rawId: String) -> String {
        let lowered = rawId.lowercased()
        let prefixes = ["speaker_", "speaker "]
        for prefix in prefixes {
            if lowered.hasPrefix(prefix) {
                let numPart = rawId.dropFirst(prefix.count)
                if let number = Int(numPart) {
                    let localizedPrefix = String(localized: "speaker.label_prefix")
                    return "\(localizedPrefix) \(number + 1)"
                }
            }
        }
        return rawId
    }
}
