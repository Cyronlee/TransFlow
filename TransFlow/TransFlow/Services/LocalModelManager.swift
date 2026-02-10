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
    private(set) var downloadDetailsByModel: [LocalTranscriptionModelKind: LocalModelDownloadDetail]

    // MARK: - Private

    private var downloadTasks: [LocalTranscriptionModelKind: Task<Void, Never>] = [:]
    private var lastProgressSampleTimeByRole: [String: Date] = [:]
    private var lastProgressSampleBytesByRole: [String: Int64] = [:]

    // MARK: - Constants

    /// Base directory for all app local models.
    private static let modelsRoot: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appending(path: "TransFlow/Models", directoryHint: .isDirectory)
    }()
    private static let resumeRootRelativePath = ".resume"
    private static let stagingRootRelativePath = ".staging"
    private static let maxDownloadRetries = 3

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
        downloadDetailsByModel = [:]
        checkAllStatuses()
    }

    // MARK: - Public API

    /// Backward-compatible convenience for currently selected local model.
    var status: LocalModelStatus { status(for: AppSettings.shared.selectedLocalModel) }
    var diskSizeBytes: Int64 { diskSizeBytes(for: AppSettings.shared.selectedLocalModel) }
    var modelDirectory: URL { modelDirectory(for: AppSettings.shared.selectedLocalModel) }
    func checkStatus() { checkStatus(for: AppSettings.shared.selectedLocalModel) }
    func download() { download(for: AppSettings.shared.selectedLocalModel) }
    func cancelDownload() { cancelDownload(for: AppSettings.shared.selectedLocalModel) }
    func delete() { delete(for: AppSettings.shared.selectedLocalModel) }

    func status(for kind: LocalTranscriptionModelKind) -> LocalModelStatus {
        statuses[kind] ?? .notDownloaded
    }

    func diskSizeBytes(for kind: LocalTranscriptionModelKind) -> Int64 {
        diskSizeBytesByModel[kind] ?? 0
    }

    func downloadDetail(for kind: LocalTranscriptionModelKind) -> LocalModelDownloadDetail? {
        downloadDetailsByModel[kind]
    }

    func hasResumeData(for kind: LocalTranscriptionModelKind) -> Bool {
        guard let spec = Self.specs[kind] else { return false }
        if FileManager.default.fileExists(atPath: resumeDataURL(for: kind, role: "archive").path(percentEncoded: false)) {
            return true
        }
        for item in spec.supplementalDownloads {
            if FileManager.default.fileExists(
                atPath: resumeDataURL(for: kind, role: "supplemental-\(item.fileName)").path(percentEncoded: false)
            ) {
                return true
            }
        }
        return false
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
            downloadDetailsByModel[kind] = nil
            return
        }

        // Keep active download state if currently downloading.
        if case .downloading = statuses[kind] {
            return
        }
        statuses[kind] = .notDownloaded
        diskSizeBytesByModel[kind] = 0
        downloadDetailsByModel[kind] = nil
    }

    /// Download model archive (+ supplemental files if configured). No-op if already downloading.
    func download(for kind: LocalTranscriptionModelKind) {
        guard let spec = Self.specs[kind] else { return }
        guard downloadTasks[kind] == nil else { return }
        statuses[kind] = .downloading(progress: 0)
        downloadDetailsByModel[kind] = nil

        downloadTasks[kind] = Task {
            defer { downloadTasks[kind] = nil }
            do {
                try await performDownloadWithRetries(spec: spec, kind: kind)
                checkStatus(for: kind)
                if !status(for: kind).isReady {
                    statuses[kind] = .failed(message: String(localized: "settings.model.error.validation_failed"))
                    ErrorLogger.shared.log("Model validation failed after download: \(kind.rawValue)", source: "LocalModel")
                }
            } catch is CancellationError {
                statuses[kind] = .notDownloaded
            } catch {
                let message: String
                if isTransientDownloadError(error) {
                    message = String(localized: "settings.model.error.retry_failed \(Self.maxDownloadRetries)")
                } else {
                    message = error.localizedDescription
                }
                statuses[kind] = .failed(message: message)
                ErrorLogger.shared.log("Model download failed (\(kind.rawValue)): \(message)", source: "LocalModel")
            }
            if !(status(for: kind).isReady) {
                downloadDetailsByModel[kind] = nil
            }
            cleanupProgressTracking(for: kind)
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
        clearAllResumeData(for: kind)
        clearStagingDirectories(for: kind)
        statuses[kind] = .notDownloaded
        diskSizeBytesByModel[kind] = 0
        downloadDetailsByModel[kind] = nil
        cleanupProgressTracking(for: kind)
    }

    func cancelDownload(for kind: LocalTranscriptionModelKind) {
        guard let task = downloadTasks[kind] else { return }
        task.cancel()
        statuses[kind] = .notDownloaded
        downloadDetailsByModel[kind] = nil
        cleanupProgressTracking(for: kind)
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

    private struct DownloadHTTPError: LocalizedError {
        let statusCode: Int
        var errorDescription: String? {
            "HTTP status \(statusCode)"
        }
    }

    private func performDownloadWithRetries(spec: LocalModelSpec, kind: LocalTranscriptionModelKind) async throws {
        var attempt = 1
        while true {
            do {
                try await performSingleDownloadAttempt(spec: spec, kind: kind)
                clearAllResumeData(for: kind)
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let retryable = isTransientDownloadError(error) && attempt < Self.maxDownloadRetries
                guard retryable else { throw error }
                let delaySeconds = pow(2.0, Double(attempt - 1))
                ErrorLogger.shared.log(
                    "Retrying model download (\(kind.rawValue)) attempt \(attempt + 1)/\(Self.maxDownloadRetries) after \(delaySeconds)s",
                    source: "LocalModel"
                )
                try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                attempt += 1
            }
        }
    }

    private func performSingleDownloadAttempt(spec: LocalModelSpec, kind: LocalTranscriptionModelKind) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: Self.modelsRoot, withIntermediateDirectories: true)
        clearStagingDirectories(for: kind)

        let stagingDir = try makeStagingDirectory(for: kind)
        var shouldCleanupStaging = true
        defer {
            if shouldCleanupStaging {
                try? fm.removeItem(at: stagingDir)
            }
        }

        let archiveUpperBound = spec.supplementalDownloads.isEmpty ? 1.0 : 0.9
        let archiveTempURL = try await downloadFile(
            from: spec.archiveURL,
            modelKind: kind,
            role: "archive",
            progressRange: 0.0 ..< archiveUpperBound,
            estimatedModelBytes: spec.estimatedSizeBytes
        )
        defer { try? fm.removeItem(at: archiveTempURL) }
        try await extractTarball(archiveTempURL, to: stagingDir)

        if !spec.supplementalDownloads.isEmpty {
            for (index, item) in spec.supplementalDownloads.enumerated() {
                let start = archiveUpperBound
                    + (Double(index) / Double(spec.supplementalDownloads.count)) * (1.0 - archiveUpperBound)
                let end = archiveUpperBound
                    + (Double(index + 1) / Double(spec.supplementalDownloads.count)) * (1.0 - archiveUpperBound)

                let tempURL = try await downloadFile(
                    from: item.url,
                    modelKind: kind,
                    role: "supplemental-\(item.fileName)",
                    progressRange: start ..< end,
                    estimatedModelBytes: spec.estimatedSizeBytes
                )
                defer { try? fm.removeItem(at: tempURL) }

                let dest = stagingDir.appending(path: item.fileName)
                if fm.fileExists(atPath: dest.path(percentEncoded: false)) {
                    try fm.removeItem(at: dest)
                }
                try fm.moveItem(at: tempURL, to: dest)
            }
        }

        guard isModelReady(at: stagingDir, spec: spec) else {
            throw NSError(
                domain: "LocalModelManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "settings.model.error.validation_failed")]
            )
        }

        let destination = primaryDirectory(for: kind)
        try installAtomically(stagingDir: stagingDir, to: destination)
        shouldCleanupStaging = false
        statuses[kind] = .downloading(progress: 1.0)
    }

    /// Download a single file with resume + progress reporting.
    /// Returns a temporary local file URL owned by this process.
    private func downloadFile(
        from url: URL,
        modelKind: LocalTranscriptionModelKind,
        role: String,
        progressRange: Range<Double>,
        estimatedModelBytes: Int64
    ) async throws -> URL {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 4 * 60 * 60

        let resumeData = loadResumeData(for: modelKind, role: role)
        let isResuming = resumeData != nil
        let resumeDataFileURL = resumeDataURL(for: modelKind, role: role)
        let progressRoleKey = "\(modelKind.rawValue)::\(role)"

        let delegate = ModelDownloadSessionDelegate(
            onProgress: { [weak self] _, totalBytesWritten, totalBytesExpected in
                Task { @MainActor [weak self] in
                    self?.updateDownloadProgress(
                        modelKind: modelKind,
                        roleKey: progressRoleKey,
                        progressRange: progressRange,
                        written: totalBytesWritten,
                        expected: totalBytesExpected,
                        estimatedModelBytes: estimatedModelBytes,
                        isResuming: isResuming
                    )
                }
            },
            onResumeData: { data in
                Self.writeResumeData(data, to: resumeDataFileURL)
            }
        )

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: queue)
        defer { session.finishTasksAndInvalidate() }

        let task: URLSessionDownloadTask
        if let resumeData {
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            task = session.downloadTask(with: url)
        }
        task.priority = URLSessionTask.highPriority
        task.resume()

        do {
            let completion = try await withTaskCancellationHandler {
                try await delegate.waitForCompletion()
            } onCancel: {
                task.cancel(byProducingResumeData: { data in
                    guard let data else { return }
                    Self.writeResumeData(data, to: resumeDataFileURL)
                })
            }
            clearResumeData(for: modelKind, role: role)

            if let httpResponse = completion.response as? HTTPURLResponse,
               !(200 ..< 300).contains(httpResponse.statusCode) {
                throw DownloadHTTPError(statusCode: httpResponse.statusCode)
            }

            return completion.tempFileURL
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw error
        }
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

    private func installAtomically(stagingDir: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path(percentEncoded: false)) {
            do {
                _ = try fm.replaceItemAt(destination, withItemAt: stagingDir, backupItemName: nil, options: [])
                return
            } catch {
                try fm.removeItem(at: destination)
                try fm.moveItem(at: stagingDir, to: destination)
                return
            }
        }
        try fm.moveItem(at: stagingDir, to: destination)
    }

    private func updateDownloadProgress(
        modelKind: LocalTranscriptionModelKind,
        roleKey: String,
        progressRange: Range<Double>,
        written: Int64,
        expected: Int64,
        estimatedModelBytes: Int64,
        isResuming: Bool
    ) {
        let now = Date()
        let previousTime = lastProgressSampleTimeByRole[roleKey]
        let previousBytes = lastProgressSampleBytesByRole[roleKey]
        lastProgressSampleTimeByRole[roleKey] = now
        lastProgressSampleBytesByRole[roleKey] = written

        let bytesPerSecond: Double?
        if let previousTime, let previousBytes {
            let elapsed = now.timeIntervalSince(previousTime)
            let deltaBytes = written - previousBytes
            if elapsed >= 0.25, deltaBytes > 0 {
                bytesPerSecond = Double(deltaBytes) / elapsed
            } else {
                bytesPerSecond = nil
            }
        } else {
            bytesPerSecond = nil
        }

        let clampedExpected = expected > 0 ? expected : nil
        let fileProgress: Double
        if let clampedExpected {
            fileProgress = min(max(Double(written) / Double(clampedExpected), 0), 1)
        } else {
            fileProgress = 0
        }

        let overallProgress = min(
            progressRange.upperBound,
            max(
                progressRange.lowerBound,
                progressRange.lowerBound + fileProgress * (progressRange.upperBound - progressRange.lowerBound)
            )
        )
        statuses[modelKind] = .downloading(progress: overallProgress)

        guard estimatedModelBytes > 0 else {
            downloadDetailsByModel[modelKind] = LocalModelDownloadDetail(
                downloadedBytes: written,
                totalBytes: clampedExpected,
                bytesPerSecond: bytesPerSecond,
                etaSeconds: nil,
                isResuming: isResuming
            )
            return
        }

        let overallDownloadedBytes = Int64(Double(estimatedModelBytes) * overallProgress)
        let speed = bytesPerSecond
        let eta: Double?
        if let speed, speed > 0 {
            eta = max(0, Double(estimatedModelBytes - overallDownloadedBytes) / speed)
        } else {
            eta = nil
        }
        downloadDetailsByModel[modelKind] = LocalModelDownloadDetail(
            downloadedBytes: overallDownloadedBytes,
            totalBytes: estimatedModelBytes,
            bytesPerSecond: speed,
            etaSeconds: eta,
            isResuming: isResuming
        )
    }

    private func isTransientDownloadError(_ error: Error) -> Bool {
        if let error = error as? DownloadHTTPError {
            switch error.statusCode {
            case 408, 425, 429, 500 ... 599:
                return true
            default:
                return false
            }
        }

        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return false
        }
        let code = URLError.Code(rawValue: nsError.code)
        switch code {
        case .timedOut,
             .networkConnectionLost,
             .notConnectedToInternet,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed,
             .resourceUnavailable,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    // MARK: - Resume Data / Staging

    private func resumeRootDirectory() -> URL {
        Self.modelsRoot.appending(path: Self.resumeRootRelativePath, directoryHint: .isDirectory)
    }

    private func stagingRootDirectory() -> URL {
        Self.modelsRoot.appending(path: Self.stagingRootRelativePath, directoryHint: .isDirectory)
    }

    private func resumeDataURL(for kind: LocalTranscriptionModelKind, role: String) -> URL {
        let safeRole = role.replacingOccurrences(of: "/", with: "_")
        return resumeRootDirectory()
            .appending(path: kind.rawValue, directoryHint: .isDirectory)
            .appending(path: "\(safeRole).resume")
    }

    private func loadResumeData(for kind: LocalTranscriptionModelKind, role: String) -> Data? {
        let url = resumeDataURL(for: kind, role: role)
        return try? Data(contentsOf: url)
    }

    private func saveResumeData(_ data: Data, for kind: LocalTranscriptionModelKind, role: String) {
        let url = resumeDataURL(for: kind, role: role)
        Self.writeResumeData(data, to: url)
    }

    private func clearResumeData(for kind: LocalTranscriptionModelKind, role: String) {
        let url = resumeDataURL(for: kind, role: role)
        try? FileManager.default.removeItem(at: url)
    }

    private func clearAllResumeData(for kind: LocalTranscriptionModelKind) {
        let dir = resumeRootDirectory().appending(path: kind.rawValue, directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeStagingDirectory(for kind: LocalTranscriptionModelKind) throws -> URL {
        let dir = stagingRootDirectory()
            .appending(path: "\(kind.rawValue)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func clearStagingDirectories(for kind: LocalTranscriptionModelKind) {
        let root = stagingRootDirectory()
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for item in contents where item.lastPathComponent.hasPrefix("\(kind.rawValue)-") {
            try? fm.removeItem(at: item)
        }
    }

    nonisolated private static func writeResumeData(_ data: Data, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func cleanupProgressTracking(for kind: LocalTranscriptionModelKind) {
        let prefix = "\(kind.rawValue)::"
        lastProgressSampleTimeByRole = lastProgressSampleTimeByRole.filter { !$0.key.hasPrefix(prefix) }
        lastProgressSampleBytesByRole = lastProgressSampleBytesByRole.filter { !$0.key.hasPrefix(prefix) }
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
