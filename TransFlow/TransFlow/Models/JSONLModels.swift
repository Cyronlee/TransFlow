import Foundation

// MARK: - JSONL Line Types

/// Discriminator for JSONL line types.
enum JSONLLineType: String, Codable {
    case metadata
    case content
}

/// A single JSONL line — either metadata or a content entry.
/// Uses a tagged union pattern for easy encode/decode.
enum JSONLLine: Codable {
    case metadata(JSONLMetadata)
    case content(JSONLContentEntry)

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
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .metadata(let m):
            try m.encode(to: encoder)
        case .content(let c):
            try c.encode(to: encoder)
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
            ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.0")
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
    init(sentence: TranscriptionSentence, endTime: Date? = nil) {
        let formatter = ISO8601DateFormatter()
        self.startTime = formatter.string(from: sentence.timestamp)
        self.endTime = formatter.string(from: endTime ?? Date())
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
