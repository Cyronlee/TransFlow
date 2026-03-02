import Testing
import Foundation
@testable import TransFlow

/// Integration tests for the video transcription pipeline.
/// Uses `public/panel-discussion-example.mp4` which contains at least 3 speakers.
struct VideoTranscriptionTests {

    /// Path to the test video relative to the project root.
    private var testVideoURL: URL {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // TransFlowTests/
            .deletingLastPathComponent() // TransFlow/
            .deletingLastPathComponent() // TransFlow project root
        return projectRoot
            .appendingPathComponent("public")
            .appendingPathComponent("panel-discussion-example.mp4")
    }

    // MARK: - Audio Extraction

    @Test func audioExtractionProducesSamples() async throws {
        let extractor = AudioExtractorService()
        let url = testVideoURL

        let samples = try await extractor.extractAudio(from: url)

        #expect(samples.count > 16_000, "Expected at least 1 second of audio at 16kHz")
        #expect(samples.allSatisfy { $0.isFinite }, "All samples should be finite")
    }

    @Test func audioExtractionStreamDeliversChunks() async throws {
        let extractor = AudioExtractorService()
        let url = testVideoURL

        let (stream, duration) = try await extractor.extractAudioStream(from: url)

        #expect(duration > 0, "Duration should be positive")

        var chunkCount = 0
        for await chunk in stream {
            #expect(!chunk.samples.isEmpty, "Chunk should have samples")
            chunkCount += 1
        }

        #expect(chunkCount > 0, "Should receive at least one chunk")
    }

    @Test func mediaDurationIsPositive() async throws {
        let extractor = AudioExtractorService()
        let url = testVideoURL

        let duration = try await extractor.mediaDuration(for: url)

        #expect(duration > 1.0, "Video should be longer than 1 second")
    }

    // MARK: - Diarization (requires model download)

    @Test(.disabled("Requires diarization model download — enable manually"))
    func diarizationIdentifiesMultipleSpeakers() async throws {
        let extractor = AudioExtractorService()
        let diarizationService = DiarizationService()
        let url = testVideoURL

        let samples = try await extractor.extractAudio(from: url)
        let segments = try await diarizationService.performDiarization(audio: samples)

        #expect(!segments.isEmpty, "Diarization should produce segments")

        let uniqueSpeakers = Set(segments.map(\.speakerId))
        #expect(uniqueSpeakers.count >= 3, "Expected at least 3 different speakers, got \(uniqueSpeakers.count): \(uniqueSpeakers)")

        for segment in segments {
            #expect(segment.startTime >= 0, "Start time should be non-negative")
            #expect(segment.endTime > segment.startTime, "End time should be after start time")
            #expect(!segment.speakerId.isEmpty, "Speaker ID should not be empty")
        }
    }

    // MARK: - Speaker Assignment

    @Test func speakerAssignmentMatchesByOverlap() {
        let diarizationSegments: [DiarizationService.SpeakerSegment] = [
            .init(speakerId: "Speaker_1", startTime: 0.0, endTime: 5.0),
            .init(speakerId: "Speaker_2", startTime: 5.0, endTime: 10.0),
            .init(speakerId: "Speaker_3", startTime: 10.0, endTime: 15.0),
        ]

        let speaker1 = DiarizationService.assignSpeaker(
            sentenceStart: 1.0, sentenceEnd: 4.0,
            diarizationSegments: diarizationSegments
        )
        #expect(speaker1 == "Speaker_1")

        let speaker2 = DiarizationService.assignSpeaker(
            sentenceStart: 6.0, sentenceEnd: 9.0,
            diarizationSegments: diarizationSegments
        )
        #expect(speaker2 == "Speaker_2")

        let speaker3 = DiarizationService.assignSpeaker(
            sentenceStart: 11.0, sentenceEnd: 14.0,
            diarizationSegments: diarizationSegments
        )
        #expect(speaker3 == "Speaker_3")

        // Overlapping boundary: mostly in Speaker_1 range
        let boundarySpk = DiarizationService.assignSpeaker(
            sentenceStart: 3.0, sentenceEnd: 6.0,
            diarizationSegments: diarizationSegments
        )
        #expect(boundarySpk == "Speaker_1")
    }

    @Test func speakerAssignmentReturnsNilForNoSegments() {
        let result = DiarizationService.assignSpeaker(
            sentenceStart: 1.0, sentenceEnd: 2.0,
            diarizationSegments: []
        )
        #expect(result == nil)
    }

    // MARK: - Video JSONL Models

    @Test func videoJSONLRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let metadata = VideoJSONLMetadata(
            videoFile: "test.mp4",
            durationSeconds: 120.5,
            sourceLanguage: "en-US",
            targetLanguage: "zh-Hans",
            diarizationEnabled: true
        )

        let metadataLine = VideoJSONLLine.videoMetadata(metadata)
        let metadataData = try encoder.encode(metadataLine)
        let decodedMetadata = try decoder.decode(VideoJSONLLine.self, from: metadataData)

        if case .videoMetadata(let m) = decodedMetadata {
            #expect(m.videoFile == "test.mp4")
            #expect(m.durationSeconds == 120.5)
            #expect(m.sourceLanguage == "en-US")
            #expect(m.diarizationEnabled == true)
        } else {
            #expect(Bool(false), "Expected videoMetadata line type")
        }

        let entry = VideoJSONLContentEntry(
            startTime: 1.5,
            endTime: 3.2,
            originalText: "Hello world",
            translatedText: "你好世界",
            speakerId: "Speaker_1"
        )

        let entryLine = VideoJSONLLine.content(entry)
        let entryData = try encoder.encode(entryLine)
        let decodedEntry = try decoder.decode(VideoJSONLLine.self, from: entryData)

        if case .content(let e) = decodedEntry {
            #expect(e.startTime == 1.5)
            #expect(e.endTime == 3.2)
            #expect(e.originalText == "Hello world")
            #expect(e.translatedText == "你好世界")
            #expect(e.speakerId == "Speaker_1")
        } else {
            #expect(Bool(false), "Expected content line type")
        }
    }

    // MARK: - Speaker Color

    @Test func speakerColorConsistency() {
        let color1 = SpeakerColor.color(for: "Speaker_1")
        let color2 = SpeakerColor.color(for: "Speaker_1")
        #expect(color1 == color2, "Same speaker should get same color")

        let color3 = SpeakerColor.color(for: "Speaker_2")
        #expect(!SpeakerColor.palette.isEmpty)
        #expect(SpeakerColor.palette.contains(color3))
    }
}
