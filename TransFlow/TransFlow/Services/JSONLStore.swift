import Foundation

/// Manages JSONL file persistence in the app's internal `transcriptions` directory.
///
/// Responsibilities:
/// - Create new session files with metadata
/// - Append content entries (transcription results)
/// - List existing session files for history browsing
/// - Read entries from a session file
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

    /// The `transcriptions` directory inside Application Support.
    private var transcriptionsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.transflow"
        return appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("transcriptions", isDirectory: true)
    }

    // MARK: - Initialization

    init() {
        ensureDirectoryExists()
    }

    // MARK: - Session Management

    /// Start a new session, creating a JSONL file with the given name.
    /// If `name` is nil, a default timestamp-based name is generated.
    @discardableResult
    func createSession(name: String? = nil) -> String {
        let sessionName = name ?? Self.generateDefaultName()
        let fileURL = transcriptionsDirectory.appendingPathComponent("\(sessionName).jsonl")

        // Write metadata as the first line
        let metadata = JSONLMetadata()
        if let line = encodeLine(.metadata(metadata)) {
            try? line.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        currentSessionName = sessionName
        currentFileURL = fileURL
        return sessionName
    }

    /// Append a completed transcription sentence to the current session file.
    func appendEntry(sentence: TranscriptionSentence, endTime: Date? = nil) {
        guard let fileURL = currentFileURL else { return }

        let entry = JSONLContentEntry(sentence: sentence, endTime: endTime)
        guard let line = encodeLine(.content(entry)) else { return }

        // Append with leading newline
        let data = Data(("\n" + line).utf8)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    }

    // MARK: - History / Reading

    /// List all session files sorted by creation date (newest first).
    /// Reads metadata and counts entries for each file.
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
                    let metadata = readMetadata(from: url)
                    let entryCount = readEntries(from: url).count
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
                        appVersion: metadata?.appVersion
                    )
                }
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            return []
        }
    }

    /// Read all content entries from a session file.
    func readEntries(from url: URL) -> [JSONLContentEntry] {
        guard let data = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let lines = data.components(separatedBy: .newlines)
        var entries: [JSONLContentEntry] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let lineData = trimmed.data(using: .utf8) else { continue }
            // Ignore invalid lines (error handling per spec)
            if let decoded = try? decoder.decode(JSONLLine.self, from: lineData) {
                if case .content(let entry) = decoded {
                    entries.append(entry)
                }
            }
        }
        return entries
    }

    /// Read metadata from a session file.
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

    /// Rename a session file. Returns the updated SessionFile on success.
    @discardableResult
    func renameSession(from oldName: String, to newName: String) -> Bool {
        let oldURL = transcriptionsDirectory.appendingPathComponent("\(oldName).jsonl")
        let newURL = transcriptionsDirectory.appendingPathComponent("\(newName).jsonl")
        guard fileManager.fileExists(atPath: oldURL.path),
              !fileManager.fileExists(atPath: newURL.path) else { return false }
        do {
            try fileManager.moveItem(at: oldURL, to: newURL)
            // If the renamed file is the current session, update the reference
            if currentSessionName == oldName {
                currentSessionName = newName
                currentFileURL = newURL
            }
            return true
        } catch {
            return false
        }
    }

    /// Delete a session file.
    @discardableResult
    func deleteSession(name: String) -> Bool {
        let url = transcriptionsDirectory.appendingPathComponent("\(name).jsonl")
        do {
            try fileManager.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }

    /// Delete all session files in the transcriptions directory.
    /// Returns the number of files successfully deleted.
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
                // Skip the current active session file
                if file == currentFileURL { continue }
                if (try? fileManager.removeItem(at: file)) != nil {
                    deleted += 1
                }
            }
        } catch {}
        return deleted
    }

    // MARK: - Helpers

    /// Generate a default session name based on current timestamp: yyyy-MM-dd_HH-mm-ss
    static func generateDefaultName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }

    /// Encode a JSONL line to a single-line JSON string.
    private func encodeLine(_ line: JSONLLine) -> String? {
        encoder.outputFormatting = [] // compact, no pretty print
        guard let data = try? encoder.encode(line) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Ensure the transcriptions directory exists.
    private func ensureDirectoryExists() {
        if !fileManager.fileExists(atPath: transcriptionsDirectory.path) {
            try? fileManager.createDirectory(at: transcriptionsDirectory, withIntermediateDirectories: true)
        }
    }
}

// MARK: - Supporting Types

/// Represents a session file in the transcriptions directory.
struct SessionFile: Identifiable {
    let name: String
    let url: URL
    let createdAt: Date
    let entryCount: Int
    let appVersion: String?

    var id: String { name }
}
