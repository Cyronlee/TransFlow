import Foundation

/// Manages on-demand download, validation, and deletion of local ASR models.
@Observable
@MainActor
final class LocalModelManager {
    static let shared = LocalModelManager()

    struct SupplementalDownload: Sendable {
        let fileName: String
        let url: URL
        let minSize: Int64
    }

    struct LocalModelSpec: Sendable {
        let kind: LocalTranscriptionModelKind
        let directoryPath: String
        let legacyDirectoryPaths: [String]
        let archiveURL: URL
        let requiredFiles: [String: Int64]
        let supplementalDownloads: [SupplementalDownload]
        let estimatedSizeBytes: Int64
    }

    // MARK: - Observable State

    private(set) var statuses: [LocalTranscriptionModelKind: LocalModelStatus]
    private(set) var diskSizeBytesByModel: [LocalTranscriptionModelKind: Int64]

    // MARK: - Private

    private var downloadTasks: [LocalTranscriptionModelKind: Task<Void, Never>] = [:]

    // MARK: - Constants

    /// Base directory for all app local models.
    private static let modelsRoot: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appending(path: "TransFlow/Models", directoryHint: .isDirectory)
    }()

    private static let specs: [LocalTranscriptionModelKind: LocalModelSpec] = [
        .parakeetOfflineInt8: LocalModelSpec(
            kind: .parakeetOfflineInt8,
            directoryPath: "Local/parakeet-tdt-0.6b-v2-int8",
            // Backward compatibility with the previous path.
            legacyDirectoryPaths: ["ParakeetTDT0.6Bv2/int8"],
            archiveURL: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8.tar.bz2")!,
            requiredFiles: [
                "encoder.int8.onnx": 100_000_000,
                "decoder.int8.onnx": 1_000_000,
                "joiner.int8.onnx": 500_000,
                "tokens.txt": 1_000,
                "silero_vad.onnx": 500_000,
            ],
            supplementalDownloads: [
                SupplementalDownload(
                    fileName: "silero_vad.onnx",
                    url: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx")!,
                    minSize: 500_000
                ),
            ],
            estimatedSizeBytes: 631_000_000
        ),
        .nemotronStreamingInt8: LocalModelSpec(
            kind: .nemotronStreamingInt8,
            directoryPath: "Local/nemotron-speech-streaming-en-0.6b-int8-2026-01-14",
            legacyDirectoryPaths: [],
            archiveURL: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemotron-speech-streaming-en-0.6b-int8-2026-01-14.tar.bz2")!,
            requiredFiles: [
                "encoder.int8.onnx": 100_000_000,
                "decoder.int8.onnx": 1_000_000,
                "joiner.int8.onnx": 500_000,
                "tokens.txt": 1_000,
            ],
            supplementalDownloads: [],
            estimatedSizeBytes: 663_000_000
        ),
    ]

    private init() {
        statuses = Dictionary(
            uniqueKeysWithValues: LocalTranscriptionModelKind.allCases.map { ($0, .notDownloaded) }
        )
        diskSizeBytesByModel = Dictionary(
            uniqueKeysWithValues: LocalTranscriptionModelKind.allCases.map { ($0, Int64(0)) }
        )
        checkAllStatuses()
    }

    // MARK: - Public API

    /// Backward-compatible convenience for currently selected local model.
    var status: LocalModelStatus { status(for: AppSettings.shared.selectedLocalModel) }
    var diskSizeBytes: Int64 { diskSizeBytes(for: AppSettings.shared.selectedLocalModel) }
    var modelDirectory: URL { modelDirectory(for: AppSettings.shared.selectedLocalModel) }
    func checkStatus() { checkStatus(for: AppSettings.shared.selectedLocalModel) }
    func download() { download(for: AppSettings.shared.selectedLocalModel) }
    func delete() { delete(for: AppSettings.shared.selectedLocalModel) }

    func status(for kind: LocalTranscriptionModelKind) -> LocalModelStatus {
        statuses[kind] ?? .notDownloaded
    }

    func diskSizeBytes(for kind: LocalTranscriptionModelKind) -> Int64 {
        diskSizeBytesByModel[kind] ?? 0
    }

    /// Directory to use for loading the specified model.
    /// If legacy assets are present and valid, they are preferred.
    func modelDirectory(for kind: LocalTranscriptionModelKind) -> URL {
        if let readyDir = resolvedReadyDirectory(for: kind) {
            return readyDir
        }
        return primaryDirectory(for: kind)
    }

    func checkAllStatuses() {
        for kind in LocalTranscriptionModelKind.allCases {
            checkStatus(for: kind)
        }
    }

    /// Check whether all required model files are present and valid.
    func checkStatus(for kind: LocalTranscriptionModelKind) {
        if let readyDir = resolvedReadyDirectory(for: kind) {
            statuses[kind] = .ready
            diskSizeBytesByModel[kind] = computeDiskSize(at: readyDir)
            return
        }

        // Keep active download state if currently downloading.
        if case .downloading = statuses[kind] {
            return
        }
        statuses[kind] = .notDownloaded
        diskSizeBytesByModel[kind] = 0
    }

    /// Download model archive (+ supplemental files if configured). No-op if already downloading.
    func download(for kind: LocalTranscriptionModelKind) {
        guard let spec = Self.specs[kind] else { return }
        guard downloadTasks[kind] == nil else { return }
        statuses[kind] = .downloading(progress: 0)

        downloadTasks[kind] = Task {
            defer { downloadTasks[kind] = nil }
            do {
                let fm = FileManager.default
                let destination = primaryDirectory(for: kind)
                try fm.createDirectory(at: destination, withIntermediateDirectories: true)

                let archiveUpperBound = spec.supplementalDownloads.isEmpty ? 1.0 : 0.9
                try await downloadAndExtractArchive(
                    spec.archiveURL,
                    to: destination,
                    modelKind: kind,
                    progressRange: 0.0 ..< archiveUpperBound
                )

                if !spec.supplementalDownloads.isEmpty {
                    for (index, item) in spec.supplementalDownloads.enumerated() {
                        let start = archiveUpperBound
                            + (Double(index) / Double(spec.supplementalDownloads.count)) * (1.0 - archiveUpperBound)
                        let end = archiveUpperBound
                            + (Double(index + 1) / Double(spec.supplementalDownloads.count)) * (1.0 - archiveUpperBound)
                        try await downloadSupplemental(
                            item,
                            to: destination,
                            modelKind: kind,
                            progressRange: start ..< end
                        )
                    }
                }

                checkStatus(for: kind)
                if !status(for: kind).isReady {
                    statuses[kind] = .failed(message: String(localized: "settings.model.error.validation_failed"))
                    ErrorLogger.shared.log("Model validation failed after download: \(kind.rawValue)", source: "LocalModel")
                }
            } catch is CancellationError {
                statuses[kind] = .notDownloaded
            } catch {
                let message = error.localizedDescription
                statuses[kind] = .failed(message: message)
                ErrorLogger.shared.log("Model download failed (\(kind.rawValue)): \(message)", source: "LocalModel")
            }
        }
    }

    /// Delete downloaded files for the specified model (primary + legacy paths).
    func delete(for kind: LocalTranscriptionModelKind) {
        downloadTasks[kind]?.cancel()
        downloadTasks[kind] = nil

        let fm = FileManager.default
        for dir in candidateDirectories(for: kind) {
            try? fm.removeItem(at: dir)
        }
        statuses[kind] = .notDownloaded
        diskSizeBytesByModel[kind] = 0
    }

    // MARK: - Directory Helpers

    private func primaryDirectory(for kind: LocalTranscriptionModelKind) -> URL {
        guard let spec = Self.specs[kind] else { return Self.modelsRoot }
        return Self.modelsRoot.appending(path: spec.directoryPath, directoryHint: .isDirectory)
    }

    private func candidateDirectories(for kind: LocalTranscriptionModelKind) -> [URL] {
        guard let spec = Self.specs[kind] else { return [] }
        var dirs: [URL] = [primaryDirectory(for: kind)]
        dirs.append(contentsOf: spec.legacyDirectoryPaths.map { relativePath in
            Self.modelsRoot.appending(path: relativePath, directoryHint: .isDirectory)
        })
        return dirs
    }

    private func resolvedReadyDirectory(for kind: LocalTranscriptionModelKind) -> URL? {
        guard let spec = Self.specs[kind] else { return nil }
        for dir in candidateDirectories(for: kind) {
            if isModelReady(at: dir, spec: spec) {
                return dir
            }
        }
        return nil
    }

    private func isModelReady(at directory: URL, spec: LocalModelSpec) -> Bool {
        let fm = FileManager.default
        for (file, minSize) in spec.requiredFiles {
            let url = directory.appending(path: file)
            let filePath = url.path(percentEncoded: false)
            guard fm.fileExists(atPath: filePath),
                  let attrs = try? fm.attributesOfItem(atPath: filePath),
                  let size = attrs[.size] as? Int64,
                  size >= minSize
            else {
                return false
            }
        }
        return true
    }

    // MARK: - Download Helpers

    private func downloadAndExtractArchive(
        _ archiveURL: URL,
        to destination: URL,
        modelKind: LocalTranscriptionModelKind,
        progressRange: Range<Double>
    ) async throws {
        let (tempURL, _) = try await downloadFile(
            from: archiveURL,
            modelKind: modelKind,
            progressRange: progressRange
        )
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try await extractTarball(tempURL, to: destination)
    }

    private func downloadSupplemental(
        _ item: SupplementalDownload,
        to destination: URL,
        modelKind: LocalTranscriptionModelKind,
        progressRange: Range<Double>
    ) async throws {
        let (tempURL, _) = try await downloadFile(
            from: item.url,
            modelKind: modelKind,
            progressRange: progressRange
        )

        let dest = destination.appending(path: item.fileName)
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
        modelKind: LocalTranscriptionModelKind,
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
                    statuses[modelKind] = .downloading(progress: min(overall, progressRange.upperBound))
                }
            }
        }

        // Flush remaining
        if !buffer.isEmpty {
            handle.write(buffer)
        }

        return (tempURL, response)
    }

    /// Extract a `.tar.bz2` archive, moving inner files into the destination directory.
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

        // The tarball extracts into a subdirectory; move the contained files into destination.
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)

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

    private func computeDiskSize(at directory: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
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
