import Foundation
import AppKit

/// Lightweight error logger that writes to the app's `logs/` directory.
///
/// - One log file per app launch, named `yyyy-MM-dd_HH-mm-ss.log`.
/// - Only records error-level messages to keep file sizes small.
/// - Thread-safe via a serial DispatchQueue; all I/O is async and non-blocking.
/// - Automatically cleans up old log files (keeps the most recent 20).
final class ErrorLogger: Sendable {
    static let shared = ErrorLogger()

    /// Maximum number of log files to keep.
    private let maxLogFiles = 20

    /// The serial queue for all file I/O.
    private let queue = DispatchQueue(label: "com.transflow.errorlogger", qos: .utility)

    /// The file handle for the current session's log file (wrapped for Sendable).
    private let state: LoggerState

    /// The URL of the `logs/` directory.
    let logsDirectory: URL

    // MARK: - Init

    private init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.transflow"
        let logsDir = appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
        self.logsDirectory = logsDir

        // Ensure directory exists
        try? fm.createDirectory(at: logsDir, withIntermediateDirectories: true)

        // Create log file for this session
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "\(formatter.string(from: Date())).log"
        let fileURL = logsDir.appendingPathComponent(filename)

        // Write header
        let header = Self.buildHeader()
        try? header.write(to: fileURL, atomically: true, encoding: .utf8)

        // Open file handle for appending
        let handle = try? FileHandle(forWritingTo: fileURL)
        handle?.seekToEndOfFile()
        self.state = LoggerState(handle: handle)

        // Clean up old logs asynchronously
        queue.async { [logsDir, maxLogFiles] in
            Self.cleanupOldLogs(in: logsDir, keeping: maxLogFiles)
        }
    }

    deinit {
        state.handle?.closeFile()
    }

    // MARK: - Public API

    /// Log an error message with the source module/context.
    func log(_ message: String, source: String, file: String = #fileID, line: Int = #line) {
        let timestamp = Self.timestampFormatter.string(from: Date())
        let entry = "[\(timestamp)] [\(source)] \(message)  (\(file):\(line))\n"

        queue.async { [state] in
            guard let handle = state.handle,
                  let data = entry.data(using: .utf8) else { return }
            handle.write(data)
        }
    }

    /// Open the logs directory in Finder.
    @MainActor
    func openLogsFolder() {
        NSWorkspace.shared.open(logsDirectory)
    }

    // MARK: - Private Helpers

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private static func buildHeader() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        return """
        ──────────────────────────────────────
        TransFlow Error Log
        Version: \(version) (\(build))
        macOS: \(os)
        Launch: \(Date())
        ──────────────────────────────────────

        """
    }

    /// Remove old log files, keeping only the `keeping` most recent ones.
    private nonisolated static func cleanupOldLogs(in directory: URL, keeping maxFiles: Int) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let logFiles = files
            .filter { $0.pathExtension == "log" }
            .sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return dateA > dateB // newest first
            }

        if logFiles.count > maxFiles {
            for file in logFiles.dropFirst(maxFiles) {
                try? fm.removeItem(at: file)
            }
        }
    }
}

// MARK: - Thread-safe State Wrapper

/// Wraps the mutable file handle so `ErrorLogger` can be `Sendable`.
private final class LoggerState: @unchecked Sendable {
    let handle: FileHandle?

    init(handle: FileHandle?) {
        self.handle = handle
    }
}
