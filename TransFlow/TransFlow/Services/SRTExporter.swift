import Foundation
import UniformTypeIdentifiers
import AppKit

/// Exports transcription history to SRT subtitle format.
enum SRTExporter {

    /// Generate SRT content from transcription sentences.
    /// Uses relative timestamps based on the first sentence.
    static func generateSRT(from sentences: [TranscriptionSentence]) -> String {
        guard !sentences.isEmpty else { return "" }

        let baseTime = sentences[0].timestamp
        var lines: [String] = []

        for (index, sentence) in sentences.enumerated() {
            let startOffset = sentence.timestamp.timeIntervalSince(baseTime)
            // Each subtitle displays for 3 seconds or until the next sentence starts
            let endOffset: TimeInterval
            if index + 1 < sentences.count {
                endOffset = sentences[index + 1].timestamp.timeIntervalSince(baseTime)
            } else {
                endOffset = startOffset + 3.0
            }

            let sequenceNumber = index + 1
            let startTimestamp = formatSRTTime(startOffset)
            let endTimestamp = formatSRTTime(endOffset)

            lines.append("\(sequenceNumber)")
            lines.append("\(startTimestamp) --> \(endTimestamp)")
            lines.append(sentence.text)
            if let translation = sentence.translation, !translation.isEmpty {
                lines.append(translation)
            }
            lines.append("") // blank line separator
        }

        return lines.joined(separator: "\n")
    }

    /// Show save panel and export SRT file.
    @MainActor
    static func exportToFile(sentences: [TranscriptionSentence]) async {
        let content = generateSRT(from: sentences)
        guard !content.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        panel.nameFieldStringValue = "TransFlow_\(Self.filenameDateString()).srt"
        panel.canCreateDirectories = true

        guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first else { return }
        let response = await panel.beginSheetModal(for: window)
        guard response == .OK, let url = panel.url else { return }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // Error writing SRT file
        }
    }

    // MARK: - Helpers

    /// Format a time interval as SRT timestamp: HH:MM:SS,mmm
    private static func formatSRTTime(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, interval)
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = Int(totalSeconds) % 60
        let milliseconds = Int((totalSeconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }

    /// Generate a date string for filename.
    private static func filenameDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}
