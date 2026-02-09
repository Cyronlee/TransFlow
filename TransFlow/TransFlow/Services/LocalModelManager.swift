import Foundation

/// Manages on-demand download, validation, and deletion of the local Parakeet TDT model
/// and the Silero VAD model used by `ParakeetSpeechEngine`.
@Observable
@MainActor
final class LocalModelManager {
    static let shared = LocalModelManager()

    // MARK: - Observable State

    /// Current status of the local Parakeet model.
    var status: LocalModelStatus = .notDownloaded

    /// Disk size of the downloaded model in bytes (0 when not downloaded).
    var diskSizeBytes: Int64 = 0

    // MARK: - Constants

    /// Base directory for all local models.
    private static let modelsRoot: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appending(path: "TransFlow/Models/ParakeetTDT0.6Bv2/int8", directoryHint: .isDirectory)
    }()

    /// Files that must be present for the model to be considered valid.
    private static let requiredFiles: [String: Int64] = [
        "encoder.int8.onnx": 100_000_000,   // ~622 MB
        "decoder.int8.onnx": 1_000_000,     // ~6.9 MB
        "joiner.int8.onnx":  500_000,       // ~1.7 MB
        "tokens.txt":        1_000,          // ~9.2 KB
    ]

    /// VAD model file.
    private static let vadFile = "silero_vad.onnx"
    private static let vadMinSize: Int64 = 500_000 // ~2 MB

    /// Download URLs.
    private static let modelTarURL = URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8.tar.bz2")!
    private static let vadURL = URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx")!

    // MARK: - Private

    private var downloadTask: Task<Void, Never>?

    private init() {
        checkStatus()
    }

    // MARK: - Public API

    /// The directory containing the model files (valid only when status is `.ready`).
    var modelDirectory: URL { Self.modelsRoot }

    /// Check whether all required model files are present and valid.
    func checkStatus() {
        let fm = FileManager.default

        // Check all required ASR model files
        for (file, minSize) in Self.requiredFiles {
            let url = Self.modelsRoot.appending(path: file)
            let filePath = url.path(percentEncoded: false)
            guard fm.fileExists(atPath: filePath),
                  let attrs = try? fm.attributesOfItem(atPath: filePath),
                  let size = attrs[.size] as? Int64,
                  size >= minSize
            else {
                status = .notDownloaded
                diskSizeBytes = 0
                return
            }
        }

        // Check VAD model
        let vadPath = Self.modelsRoot.appending(path: Self.vadFile)
        let vadFilePath = vadPath.path(percentEncoded: false)
        guard fm.fileExists(atPath: vadFilePath),
              let attrs = try? fm.attributesOfItem(atPath: vadFilePath),
              let size = attrs[.size] as? Int64,
              size >= Self.vadMinSize
        else {
            status = .notDownloaded
            diskSizeBytes = 0
            return
        }

        status = .ready
        diskSizeBytes = computeDiskSize()
    }

    /// Download the model (ASR tarball + VAD). No-op if already downloading.
    func download() {
        guard !status.isDownloading else { return }
        status = .downloading(progress: 0)

        downloadTask = Task {
            do {
                let fm = FileManager.default
                try fm.createDirectory(at: Self.modelsRoot, withIntermediateDirectories: true)

                // --- Download and extract the ASR model tarball (95% of progress) ---
                try await downloadAndExtractTarball(progressRange: 0.0 ..< 0.95)

                // --- Download the VAD model (5% of progress) ---
                try await downloadVAD(progressRange: 0.95 ..< 1.0)

                // Validate
                checkStatus()
                if !status.isReady {
                    status = .failed(message: String(localized: "settings.model.error.validation_failed"))
                    ErrorLogger.shared.log("Model validation failed after download", source: "LocalModel")
                }
            } catch is CancellationError {
                status = .notDownloaded
            } catch {
                let message = error.localizedDescription
                status = .failed(message: message)
                ErrorLogger.shared.log("Model download failed: \(message)", source: "LocalModel")
            }
        }
    }

    /// Delete all downloaded model files.
    func delete() {
        downloadTask?.cancel()
        downloadTask = nil

        let fm = FileManager.default
        try? fm.removeItem(at: Self.modelsRoot)
        status = .notDownloaded
        diskSizeBytes = 0
    }

    // MARK: - Download Helpers

    private func downloadAndExtractTarball(progressRange: Range<Double>) async throws {
        let (tempURL, _) = try await downloadFile(
            from: Self.modelTarURL,
            progressRange: progressRange
        )
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Extract tar.bz2 using /usr/bin/tar
        try await extractTarball(tempURL, to: Self.modelsRoot)
    }

    private func downloadVAD(progressRange: Range<Double>) async throws {
        let (tempURL, _) = try await downloadFile(
            from: Self.vadURL,
            progressRange: progressRange
        )

        let dest = Self.modelsRoot.appending(path: Self.vadFile)
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path(percentEncoded: false)) {
            try fm.removeItem(at: dest)
        }
        try fm.moveItem(at: tempURL, to: dest)
    }

    /// Download a file with progress reporting.
    /// Returns the temporary file URL and the HTTP response.
    private func downloadFile(
        from url: URL,
        progressRange: Range<Double>
    ) async throws -> (URL, URLResponse) {
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        let (asyncBytes, response) = try await session.bytes(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode)
        else {
            throw URLError(.badServerResponse)
        }

        let expectedLength = response.expectedContentLength
        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)

        FileManager.default.createFile(atPath: tempURL.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: tempURL)
        defer { try? handle.close() }

        var received: Int64 = 0
        var buffer = Data()
        let chunkSize = 256 * 1024 // 256 KB write chunks

        for try await byte in asyncBytes {
            try Task.checkCancellation()
            buffer.append(byte)

            if buffer.count >= chunkSize {
                handle.write(buffer)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)

                if expectedLength > 0 {
                    let fileFraction = Double(received) / Double(expectedLength)
                    let overall = progressRange.lowerBound
                        + fileFraction * (progressRange.upperBound - progressRange.lowerBound)
                    status = .downloading(progress: min(overall, progressRange.upperBound))
                }
            }
        }

        // Flush remaining
        if !buffer.isEmpty {
            handle.write(buffer)
        }

        return (tempURL, response)
    }

    /// Extract a `.tar.bz2` archive, moving the inner files into the destination directory.
    private func extractTarball(_ tarURL: URL, to destination: URL) async throws {
        // Extract to a temporary directory first
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["xjf", tarURL.path(percentEncoded: false), "-C", tempDir.path(percentEncoded: false)]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "LocalModelManager",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "tar extraction failed with status \(process.terminationStatus)"]
            )
        }

        // The tarball extracts into a subdirectory (e.g., sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/).
        // Move the contained files into the destination.
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)

        // Find the extracted subdirectory
        let extractedDir = contents.first { url in
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir) && isDir.boolValue
        } ?? tempDir

        let files = try fm.contentsOfDirectory(at: extractedDir, includingPropertiesForKeys: nil)
        for file in files {
            let destFile = destination.appending(path: file.lastPathComponent)
            if fm.fileExists(atPath: destFile.path(percentEncoded: false)) {
                try fm.removeItem(at: destFile)
            }
            try fm.moveItem(at: file, to: destFile)
        }
    }

    // MARK: - Disk Size

    private func computeDiskSize() -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: Self.modelsRoot,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
