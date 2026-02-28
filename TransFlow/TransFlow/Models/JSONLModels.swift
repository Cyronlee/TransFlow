import Foundation

// MARK: - JSONL Line Types

/// Discriminator for JSONL line types.
enum JSONLLineType: String, Codable {
    case metadata
    case content
    case recordingStart = "recording_start"
    case recordingStop = "recording_stop"
}

/// A single JSONL line — metadata, content, or recording marker.
/// Uses a tagged union pattern for easy encode/decode.
enum JSONLLine: Codable {
    case metadata(JSONLMetadata)
    case content(JSONLContentEntry)
    case recordingStart(JSONLRecordingStart)
    case recordingStop(JSONLRecordingStop)

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(JSONLLineType.self, forKey: .type)
        switch type {
        case .metadata:
            self = .metadata(try JSONLMetadata(from: decoder))
        case .content:
            self = .content(try JSONLContentEntry(from: decoder))
        case .recordingStart:
            self = .recordingStart(try JSONLRecordingStart(from: decoder))
        case .recordingStop:
            self = .recordingStop(try JSONLRecordingStop(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .metadata(let m):
            try m.encode(to: encoder)
        case .content(let c):
            try c.encode(to: encoder)
        case .recordingStart(let r):
            try r.encode(to: encoder)
        case .recordingStop(let r):
            try r.encode(to: encoder)
        }
    }
}

// MARK: - Metadata

/// First line of every JSONL file — global session metadata.
struct JSONLMetadata: Codable {
    let type: JSONLLineType = .metadata
    let createTime: String
    let appVersion: String

    enum CodingKeys: String, CodingKey {
        case type
        case createTime = "create_time"
        case appVersion = "app_version"
    }

    init(createTime: Date = Date(), appVersion: String? = nil) {
        self.createTime = ISO8601DateFormatter().string(from: createTime)
        self.appVersion = appVersion
            ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3.0")
    }
}

// MARK: - Content Entry

/// A transcription + translation result line in the JSONL file.
struct JSONLContentEntry: Codable {
    let type: JSONLLineType = .content
    let startTime: String
    let endTime: String
    let originalText: String
    let translatedText: String?

    enum CodingKeys: String, CodingKey {
        case type
        case startTime = "start_time"
        case endTime = "end_time"
        case originalText = "original_text"
        case translatedText = "translated_text"
    }

    /// Convenience initializer from a `TranscriptionSentence`.
    init(sentence: TranscriptionSentence) {
        let formatter = ISO8601DateFormatter()
        self.startTime = formatter.string(from: sentence.startTimestamp)
        self.endTime = formatter.string(from: sentence.timestamp)
        self.originalText = sentence.text
        self.translatedText = sentence.translation
    }

    init(startTime: String, endTime: String, originalText: String, translatedText: String?) {
        self.startTime = startTime
        self.endTime = endTime
        self.originalText = originalText
        self.translatedText = translatedText
    }
}

// MARK: - Recording Markers

/// Marks the start of a recording segment in the JSONL file.
struct JSONLRecordingStart: Codable {
    let type: JSONLLineType = .recordingStart
    let recordingFile: String
    let timestamp: String

    enum CodingKeys: String, CodingKey {
        case type
        case recordingFile = "recording_file"
        case timestamp
    }

    init(recordingFile: String, timestamp: Date = Date()) {
        self.recordingFile = recordingFile
        self.timestamp = ISO8601DateFormatter().string(from: timestamp)
    }
}

/// Marks the end of a recording segment in the JSONL file.
struct JSONLRecordingStop: Codable {
    let type: JSONLLineType = .recordingStop
    let recordingFile: String
    let timestamp: String
    let durationMs: Int

    enum CodingKeys: String, CodingKey {
        case type
        case recordingFile = "recording_file"
        case timestamp
        case durationMs = "duration_ms"
    }

    init(recordingFile: String, timestamp: Date = Date(), durationMs: Int) {
        self.recordingFile = recordingFile
        self.timestamp = ISO8601DateFormatter().string(from: timestamp)
        self.durationMs = durationMs
    }
}
