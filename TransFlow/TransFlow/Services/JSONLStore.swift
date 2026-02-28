import Foundation

/// Manages JSONL file persistence in the app's internal `transcriptions` directory.
@MainActor
@Observable
final class JSONLStore {

    // MARK: - State

    /// The filename (without extension) of the current active session.
    private(set) var currentSessionName: String = ""

    /// Full URL of the current session file.
    private(set) var currentFileURL: URL?

    // MARK: - Private

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var transcriptionsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.transflow"
        return appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("transcriptions", isDirectory: true)
    }

    private var recordingsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.transflow"
        return appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("recordings", isDirectory: true)
    }

    // MARK: - Initialization

    init() {
        ensureDirectoryExists()
    }

    // MARK: - Session Management

    @discardableResult
    func createSession(name: String? = nil) -> String {
        let sessionName = name ?? Self.generateDefaultName()
        let fileURL = transcriptionsDirectory.appendingPathComponent("\(sessionName).jsonl")

        let metadata = JSONLMetadata()
        if let line = encodeLine(.metadata(metadata)) {
            try? line.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        currentSessionName = sessionName
        currentFileURL = fileURL
        return sessionName
    }

    // MARK: - Appending

    func appendEntry(sentence: TranscriptionSentence, endTime: Date? = nil) {
        guard let fileURL = currentFileURL else { return }
        let entry = JSONLContentEntry(sentence: sentence, endTime: endTime)
        guard let line = encodeLine(.content(entry)) else { return }
        appendRaw(line, to: fileURL)
    }

    func appendRecordingStart(fileName: String, timestamp: Date = Date()) {
        guard let fileURL = currentFileURL else { return }
        let marker = JSONLRecordingStart(recordingFile: fileName, timestamp: timestamp)
        guard let line = encodeLine(.recordingStart(marker)) else { return }
        appendRaw(line, to: fileURL)
    }

    func appendRecordingStop(fileName: String, timestamp: Date = Date(), durationMs: Int) {
        guard let fileURL = currentFileURL else { return }
        let marker = JSONLRecordingStop(recordingFile: fileName, timestamp: timestamp, durationMs: durationMs)
        guard let line = encodeLine(.recordingStop(marker)) else { return }
        appendRaw(line, to: fileURL)
    }

    // MARK: - History / Reading

    func listSessions() -> [SessionFile] {
        ensureDirectoryExists()
        do {
            let files = try fileManager.contentsOfDirectory(
                at: transcriptionsDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )
            return files
                .filter { $0.pathExtension == "jsonl" }
                .compactMap { url -> SessionFile? in
                    let name = url.deletingPathExtension().lastPathComponent
                    let allLines = readAllLines(from: url)
                    let metadata = allLines.compactMap { if case .metadata(let m) = $0 { return m } else { return nil } }.first
                    let entryCount = allLines.filter { if case .content = $0 { return true } else { return false } }.count

                    var recordings: [SessionFile.RecordingSegment] = []
                    for line in allLines {
                        if case .recordingStart(let r) = line {
                            recordings.append(.init(fileName: r.recordingFile, timestamp: r.timestamp, durationMs: 0))
                        } else if case .recordingStop(let r) = line {
                            if let idx = recordings.lastIndex(where: { $0.fileName == r.recordingFile }) {
                                recordings[idx] = .init(fileName: r.recordingFile, timestamp: recordings[idx].timestamp, durationMs: r.durationMs)
                            }
                        }
                    }

                    let createdAt: Date
                    if let timeStr = metadata?.createTime,
                       let date = ISO8601DateFormatter().date(from: timeStr) {
                        createdAt = date
                    } else {
                        let attrs = try? fileManager.attributesOfItem(atPath: url.path)
                        createdAt = attrs?[.creationDate] as? Date ?? Date.distantPast
                    }
                    return SessionFile(
                        name: name,
                        url: url,
                        createdAt: createdAt,
                        entryCount: entryCount,
                        appVersion: metadata?.appVersion,
                        recordings: recordings
                    )
                }
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            return []
        }
    }

    func readEntries(from url: URL) -> [JSONLContentEntry] {
        readAllLines(from: url).compactMap {
            if case .content(let entry) = $0 { return entry } else { return nil }
        }
    }

    func readAllLines(from url: URL) -> [JSONLLine] {
        guard let data = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let lines = data.components(separatedBy: .newlines)
        var result: [JSONLLine] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let lineData = trimmed.data(using: .utf8) else { continue }
            if let decoded = try? decoder.decode(JSONLLine.self, from: lineData) {
                result.append(decoded)
            }
        }
        return result
    }

    func readRecordingFiles(from url: URL) -> [String] {
        readAllLines(from: url).compactMap {
            if case .recordingStart(let r) = $0 { return r.recordingFile } else { return nil }
        }
    }

    func readMetadata(from url: URL) -> JSONLMetadata? {
        guard let data = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = data.components(separatedBy: .newlines)
        guard let firstLine = lines.first,
              !firstLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let lineData = firstLine.data(using: .utf8),
              let decoded = try? decoder.decode(JSONLLine.self, from: lineData),
              case .metadata(let meta) = decoded else {
            return nil
        }
        return meta
    }

    // MARK: - File Management

    @discardableResult
    func renameSession(from oldName: String, to newName: String) -> Bool {
        let oldURL = transcriptionsDirectory.appendingPathComponent("\(oldName).jsonl")
        let newURL = transcriptionsDirectory.appendingPathComponent("\(newName).jsonl")
        guard fileManager.fileExists(atPath: oldURL.path),
              !fileManager.fileExists(atPath: newURL.path) else { return false }
        do {
            try fileManager.moveItem(at: oldURL, to: newURL)
            if currentSessionName == oldName {
                currentSessionName = newName
                currentFileURL = newURL
            }
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func deleteSession(name: String) -> Bool {
        let url = transcriptionsDirectory.appendingPathComponent("\(name).jsonl")
        let recordingFiles = readRecordingFiles(from: url)
        for recFile in recordingFiles {
            let recURL = recordingsDirectory.appendingPathComponent(recFile)
            try? fileManager.removeItem(at: recURL)
        }
        do {
            try fileManager.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func deleteAllSessions() -> Int {
        ensureDirectoryExists()
        var deleted = 0
        do {
            let files = try fileManager.contentsOfDirectory(
                at: transcriptionsDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for file in files where file.pathExtension == "jsonl" {
                if file == currentFileURL { continue }
                let recordingFiles = readRecordingFiles(from: file)
                for recFile in recordingFiles {
                    let recURL = recordingsDirectory.appendingPathComponent(recFile)
                    try? fileManager.removeItem(at: recURL)
                }
                if (try? fileManager.removeItem(at: file)) != nil {
                    deleted += 1
                }
            }
        } catch {}
        return deleted
    }

    // MARK: - Helpers

    static func generateDefaultName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }

    private func encodeLine(_ line: JSONLLine) -> String? {
        encoder.outputFormatting = []
        guard let data = try? encoder.encode(line) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func appendRaw(_ line: String, to fileURL: URL) {
        let data = Data(("\n" + line).utf8)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    }

    private func ensureDirectoryExists() {
        if !fileManager.fileExists(atPath: transcriptionsDirectory.path) {
            try? fileManager.createDirectory(at: transcriptionsDirectory, withIntermediateDirectories: true)
        }
    }
}

// MARK: - Supporting Types

struct SessionFile: Identifiable {
    struct RecordingSegment {
        let fileName: String
        let timestamp: String
        let durationMs: Int
    }

    let name: String
    let url: URL
    let createdAt: Date
    let entryCount: Int
    let appVersion: String?
    let recordings: [RecordingSegment]

    var hasRecording: Bool { !recordings.isEmpty }
    var totalRecordingDurationMs: Int { recordings.reduce(0) { $0 + $1.durationMs } }

    var recordingFiles: [String] { recordings.map(\.fileName) }

    var id: String { name }
}
