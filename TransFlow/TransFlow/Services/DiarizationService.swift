import Foundation
import os
import FluidAudio

/// Wraps FluidAudio's OfflineDiarizerManager for batch speaker diarization.
final class DiarizationService: Sendable {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.transflow",
        category: "Diarization"
    )

    /// Result of diarization: a list of speaker segments with time ranges.
    struct SpeakerSegment: Sendable {
        let speakerId: String
        let startTime: Double
        let endTime: Double
    }

    /// Perform offline diarization on pre-extracted 16kHz mono Float32 audio.
    /// - Parameter clusteringThreshold: Speaker separation sensitivity (0.5–0.95). Higher = more speakers detected.
    func performDiarization(audio: [Float], clusteringThreshold: Double = 0.8) async throws -> [SpeakerSegment] {
        var config = OfflineDiarizerConfig()
        config.clusteringThreshold = clusteringThreshold
        let manager = OfflineDiarizerManager(config: config)
        try await manager.prepareModels()

        Self.logger.info("Starting diarization on \(audio.count) samples (\(Double(audio.count) / 16000, format: .fixed(precision: 1))s)")

        let result = try await manager.process(audio: audio)

        let segments = result.segments.map { segment in
            SpeakerSegment(
                speakerId: segment.speakerId,
                startTime: Double(segment.startTimeSeconds),
                endTime: Double(segment.endTimeSeconds)
            )
        }.sorted { $0.startTime < $1.startTime }

        let uniqueSpeakers = Set(segments.map(\.speakerId))
        Self.logger.info("Diarization complete: \(segments.count) segments, \(uniqueSpeakers.count) unique speakers: \(uniqueSpeakers.sorted().joined(separator: ", "))")
        for seg in segments {
            Self.logger.debug("  [\(seg.startTime, format: .fixed(precision: 2))s - \(seg.endTime, format: .fixed(precision: 2))s] \(seg.speakerId)")
        }

        return segments
    }

    /// Assign a speaker ID to a transcription segment by finding the best-matching
    /// diarization segment based on time overlap.
    static func assignSpeaker(
        sentenceStart: Double,
        sentenceEnd: Double,
        diarizationSegments: [SpeakerSegment]
    ) -> String? {
        var bestSpeaker: String?
        var bestOverlap: Double = 0

        for segment in diarizationSegments {
            let overlapStart = max(sentenceStart, segment.startTime)
            let overlapEnd = min(sentenceEnd, segment.endTime)
            let overlap = max(0, overlapEnd - overlapStart)

            if overlap > bestOverlap {
                bestOverlap = overlap
                bestSpeaker = segment.speakerId
            }
        }

        return bestSpeaker
    }
}
