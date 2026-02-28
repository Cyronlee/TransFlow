@preconcurrency import AVFoundation
import os

/// Records AudioChunk streams to M4A files in the app's `recordings` directory.
///
/// All methods are nonisolated and thread-safe (protected by NSLock).
/// This class is designed to be called from both @MainActor and detached Task contexts.
final class AudioRecordingService: @unchecked Sendable {

    struct RecordingInfo: Sendable {
        let fileName: String
        let fileURL: URL
        let startTime: Date
        let durationMs: Int
    }

    nonisolated(unsafe) private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.transflow", category: "Recording")

    private let lock = NSLock()

    // All mutable state is protected by `lock`
    nonisolated(unsafe) private var _audioFile: AVAudioFile?
    nonisolated(unsafe) private var _inputFormat: AVAudioFormat?
    nonisolated(unsafe) private var _recordingStartTime: Date?
    nonisolated(unsafe) private var _currentFileName: String?
    nonisolated(unsafe) private var _currentFileURL: URL?

    private static var recordingsDirectory: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.transflow"
        return appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("recordings", isDirectory: true)
    }

    init() {
        Self.ensureDirectoryExists()
    }

    /// Begin recording to a new M4A file. Each call creates a uniquely-named file.
    @discardableResult
    func startRecording() -> (fileName: String, startTime: Date) {
        Self.ensureDirectoryExists()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let fileName = "rec_\(formatter.string(from: Date())).m4a"
        let fileURL = Self.recordingsDirectory.appendingPathComponent(fileName)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1) else {
            return (fileName, Date())
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let file = try AVAudioFile(
                forWriting: fileURL,
                settings: settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            lock.lock()
            _audioFile = file
            _inputFormat = format
            _currentFileName = fileName
            _currentFileURL = fileURL
            let now = Date()
            _recordingStartTime = now
            lock.unlock()
            return (fileName, now)
        } catch {
            Self.logger.error("Failed to create recording file: \(error.localizedDescription)")
            return (fileName, Date())
        }
    }

    /// Write a single AudioChunk to the recording file. Safe to call from any thread.
    nonisolated func writeChunk(_ chunk: AudioChunk) {
        lock.lock()
        guard let audioFile = _audioFile, let inputFormat = _inputFormat else {
            lock.unlock()
            return
        }
        lock.unlock()

        let frameCount = AVAudioFrameCount(chunk.samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        if let channelData = buffer.floatChannelData {
            memcpy(channelData[0], chunk.samples, chunk.samples.count * MemoryLayout<Float>.size)
        }

        do {
            try audioFile.write(from: buffer)
        } catch {
            Self.logger.error("Failed to write audio chunk: \(error.localizedDescription)")
        }
    }

    /// Finalize the recording and return info about the completed file.
    func stopRecording() -> RecordingInfo? {
        lock.lock()
        guard let fileName = _currentFileName,
              let fileURL = _currentFileURL,
              let startTime = _recordingStartTime else {
            lock.unlock()
            return nil
        }

        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

        _audioFile = nil
        _inputFormat = nil
        _currentFileName = nil
        _currentFileURL = nil
        _recordingStartTime = nil
        lock.unlock()

        return RecordingInfo(fileName: fileName, fileURL: fileURL, startTime: startTime, durationMs: durationMs)
    }

    /// URL for a recording file by name.
    static func recordingURL(for fileName: String) -> URL {
        recordingsDirectory.appendingPathComponent(fileName)
    }

    /// Delete a recording file.
    @discardableResult
    static func deleteRecording(named fileName: String) -> Bool {
        let url = recordingsDirectory.appendingPathComponent(fileName)
        return (try? FileManager.default.removeItem(at: url)) != nil
    }

    /// Check if a recording file exists.
    static func recordingExists(named fileName: String) -> Bool {
        let url = recordingsDirectory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path)
    }

    private static func ensureDirectoryExists() {
        let dir = recordingsDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
