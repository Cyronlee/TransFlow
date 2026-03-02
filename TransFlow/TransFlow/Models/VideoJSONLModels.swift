import Foundation

// MARK: - Video JSONL Line Types

enum VideoJSONLLineType: String, Codable {
    case videoMetadata = "video_metadata"
    case content
}

/// A single line in a video transcription JSONL file.
enum VideoJSONLLine: Codable {
    case videoMetadata(VideoJSONLMetadata)
    case content(VideoJSONLContentEntry)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(VideoJSONLLineType.self, forKey: .type)
        switch type {
        case .videoMetadata:
            self = .videoMetadata(try VideoJSONLMetadata(from: decoder))
        case .content:
            self = .content(try VideoJSONLContentEntry(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .videoMetadata(let m):
            try m.encode(to: encoder)
        case .content(let c):
            try c.encode(to: encoder)
        }
    }
}

// MARK: - Video Metadata

/// First line of a video transcription JSONL file.
struct VideoJSONLMetadata: Codable {
    let type: VideoJSONLLineType = .videoMetadata
    let videoFile: String
    let originalFilePath: String?
    let durationSeconds: Double
    let sourceLanguage: String
    let targetLanguage: String?
    let diarizationEnabled: Bool
    let createTime: String
    let appVersion: String

    enum CodingKeys: String, CodingKey {
        case type
        case videoFile = "video_file"
        case originalFilePath = "original_file_path"
        case durationSeconds = "duration_seconds"
        case sourceLanguage = "source_language"
        case targetLanguage = "target_language"
        case diarizationEnabled = "diarization_enabled"
        case createTime = "create_time"
        case appVersion = "app_version"
    }

    init(
        videoFile: String,
        originalFilePath: String? = nil,
        durationSeconds: Double,
        sourceLanguage: String,
        targetLanguage: String?,
        diarizationEnabled: Bool,
        createTime: Date = Date(),
        appVersion: String? = nil
    ) {
        self.videoFile = videoFile
        self.originalFilePath = originalFilePath
        self.durationSeconds = durationSeconds
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.diarizationEnabled = diarizationEnabled
        self.createTime = ISO8601DateFormatter().string(from: createTime)
        self.appVersion = appVersion
            ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3.0")
    }
}

// MARK: - Video Content Entry

/// A transcription segment line with time offsets in seconds and optional speaker ID.
struct VideoJSONLContentEntry: Codable {
    let type: VideoJSONLLineType = .content
    let startTime: Double
    let endTime: Double
    let originalText: String
    let translatedText: String?
    let speakerId: String?

    enum CodingKeys: String, CodingKey {
        case type
        case startTime = "start_time"
        case endTime = "end_time"
        case originalText = "original_text"
        case translatedText = "translated_text"
        case speakerId = "speaker_id"
    }

    init(segment: VideoTranscriptionSegment) {
        self.startTime = segment.startTime
        self.endTime = segment.endTime
        self.originalText = segment.text
        self.translatedText = segment.translation
        self.speakerId = segment.speakerId
    }

    init(
        startTime: Double,
        endTime: Double,
        originalText: String,
        translatedText: String?,
        speakerId: String?
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.originalText = originalText
        self.translatedText = translatedText
        self.speakerId = speakerId
    }
}
