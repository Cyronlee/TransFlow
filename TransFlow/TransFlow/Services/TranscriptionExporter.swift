import Foundation
import UniformTypeIdentifiers
import AppKit

/// Supported export formats for transcription data.
enum ExportFormat: String, CaseIterable, Identifiable {
    case srt
    case markdown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .srt: return "SRT"
        case .markdown: return "Markdown"
        }
    }

    var fileExtension: String {
        switch self {
        case .srt: return "srt"
        case .markdown: return "md"
        }
    }

    var utType: UTType {
        switch self {
        case .srt: return UTType(filenameExtension: "srt") ?? .plainText
        case .markdown: return UTType(filenameExtension: "md") ?? .plainText
        }
    }
}

/// Unified exporter that can generate SRT or Markdown from JSONL content entries.
enum TranscriptionExporter {

    // MARK: - Generate Content

    /// Generate export content from JSONL content entries.
    static func generate(entries: [JSONLContentEntry], format: ExportFormat, sessionName: String? = nil) -> String {
        switch format {
        case .srt:
            return generateSRT(from: entries)
        case .markdown:
            return generateMarkdown(from: entries, sessionName: sessionName)
        }
    }

    // MARK: - SRT

    private static func generateSRT(from entries: [JSONLContentEntry]) -> String {
        guard !entries.isEmpty else { return "" }

        let formatter = ISO8601DateFormatter()
        let baseDateOpt = formatter.date(from: entries[0].startTime)

        var lines: [String] = []
        for (index, entry) in entries.enumerated() {
            let startDate = formatter.date(from: entry.startTime)
            let endDate = formatter.date(from: entry.endTime)
            let startOffset: TimeInterval
            if let start = startDate, let base = baseDateOpt {
                startOffset = start.timeIntervalSince(base)
            } else {
                startOffset = 0
            }
            let endOffset: TimeInterval
            if let end = endDate, let base = baseDateOpt {
                endOffset = end.timeIntervalSince(base)
            } else {
                endOffset = startOffset + 3.0
            }

            lines.append("\(index + 1)")
            lines.append("\(formatSRTTime(startOffset)) --> \(formatSRTTime(endOffset))")
            lines.append(entry.originalText)
            if let translation = entry.translatedText, !translation.isEmpty {
                lines.append(translation)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Markdown

    private static func generateMarkdown(from entries: [JSONLContentEntry], sessionName: String?) -> String {
        guard !entries.isEmpty else { return "" }

        var lines: [String] = []

        // Title
        if let name = sessionName {
            lines.append("# \(name)")
        } else {
            lines.append("# Transcription")
        }
        lines.append("")

        let formatter = ISO8601DateFormatter()

        for entry in entries {
            // Timestamp
            let timeStr: String
            if let date = formatter.date(from: entry.startTime) {
                let displayFormatter = DateFormatter()
                displayFormatter.dateFormat = "HH:mm:ss"
                timeStr = displayFormatter.string(from: date)
            } else {
                timeStr = entry.startTime
            }

            lines.append("**[\(timeStr)]** \(entry.originalText)")
            if let translation = entry.translatedText, !translation.isEmpty {
                lines.append("")
                lines.append("> \(translation)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Export to File (Save Panel)

    /// Show save panel and export transcription entries to a file.
    @MainActor
    static func exportToFile(
        entries: [JSONLContentEntry],
        format: ExportFormat,
        sessionName: String? = nil
    ) async {
        let content = generate(entries: entries, format: format, sessionName: sessionName)
        guard !content.isEmpty else { return }

        let baseName = sessionName ?? "TransFlow_\(filenameDateString())"

        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        panel.nameFieldStringValue = "\(baseName).\(format.fileExtension)"
        panel.canCreateDirectories = true

        guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first else { return }
        let response = await panel.beginSheetModal(for: window)
        guard response == .OK, let url = panel.url else { return }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // Error writing file — silently ignored for now
        }
    }

    // MARK: - Helpers

    private static func formatSRTTime(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, interval)
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = Int(totalSeconds) % 60
        let milliseconds = Int((totalSeconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }

    private static func filenameDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }
}
