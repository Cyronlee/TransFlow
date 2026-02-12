import Foundation

/// Delegate bridge for URLSessionDownloadTask that exposes async completion
/// while reporting progress and resume data callbacks.
final class ModelDownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    struct Completion: Sendable {
        let tempFileURL: URL
        let response: URLResponse
    }

    private let onProgress: @Sendable (_ bytesWritten: Int64, _ totalBytesWritten: Int64, _ totalBytesExpected: Int64) -> Void
    private let onResumeData: @Sendable (Data) -> Void

    private let lock = NSLock()
    private var continuation: CheckedContinuation<Completion, Error>?
    private var pendingResult: Result<Completion, Error>?
    private var finishedLocation: URL?
    private var finishedResponse: URLResponse?
    private var finishedError: Error?

    init(
        onProgress: @escaping @Sendable (_ bytesWritten: Int64, _ totalBytesWritten: Int64, _ totalBytesExpected: Int64) -> Void,
        onResumeData: @escaping @Sendable (Data) -> Void
    ) {
        self.onProgress = onProgress
        self.onResumeData = onResumeData
    }

    func waitForCompletion() async throws -> Completion {
        try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<Completion, Error>) in
            guard let self else {
                continuation.resume(throwing: URLError(.cancelled))
                return
            }
            lock.lock()
            if let pendingResult {
                lock.unlock()
                continuation.resume(with: pendingResult)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    private func complete(with result: Result<Completion, Error>) {
        lock.lock()
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(with: result)
            return
        }
        pendingResult = result
        lock.unlock()
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(bytesWritten, totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let fm = FileManager.default
        let ownedTempURL = fm.temporaryDirectory
            .appending(path: "transflow-model-\(UUID().uuidString)")
        do {
            if fm.fileExists(atPath: ownedTempURL.path(percentEncoded: false)) {
                try fm.removeItem(at: ownedTempURL)
            }
            // The system-owned download location is only guaranteed during this callback.
            try fm.moveItem(at: location, to: ownedTempURL)
            lock.lock()
            finishedLocation = ownedTempURL
            finishedResponse = downloadTask.response
            lock.unlock()
        } catch {
            lock.lock()
            finishedError = error
            lock.unlock()
        }
    }

    // MARK: - URLSessionTaskDelegate

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            if let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                onResumeData(resumeData)
            }
            complete(with: .failure(error))
            return
        }

        lock.lock()
        let location = finishedLocation
        let response = finishedResponse ?? task.response
        let storedError = finishedError
        lock.unlock()

        if let storedError {
            complete(with: .failure(storedError))
            return
        }

        guard let location, let response else {
            complete(with: .failure(URLError(.unknown)))
            return
        }
        complete(with: .success(Completion(tempFileURL: location, response: response)))
    }
}
