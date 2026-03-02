import Foundation
import FluidAudio

/// Manages FluidAudio diarization model assets: checking status, downloading, and tracking progress.
@Observable
@MainActor
final class DiarizationModelManager {
    static let shared = DiarizationModelManager()

    var modelStatus: DiarizationModelStatus = .checking
    var downloadProgress: Double = 0
    var isDownloading: Bool = false

    /// HuggingFace mirror endpoint. Empty string = official HuggingFace.
    var hfEndpoint: String {
        get { UserDefaults.standard.string(forKey: "diarization_hf_endpoint") ?? "" }
        set {
            UserDefaults.standard.set(newValue, forKey: "diarization_hf_endpoint")
            applyHFEndpoint()
        }
    }

    private init() {
        applyHFEndpoint()
    }

    // MARK: - HF Endpoint

    private func applyHFEndpoint() {
        let endpoint = hfEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !endpoint.isEmpty {
            ModelRegistry.baseURL = endpoint
        }
    }

    // MARK: - Model Directory

    private var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("speaker-diarization-coreml", isDirectory: true)
    }

    private var segmentationModelURL: URL {
        modelsDirectory.appendingPathComponent("pyannote_segmentation.mlmodelc")
    }

    private var embeddingModelURL: URL {
        modelsDirectory.appendingPathComponent("wespeaker_v2.mlmodelc")
    }

    // MARK: - Status Check

    func checkStatus() {
        let fm = FileManager.default
        let segExists = fm.fileExists(atPath: segmentationModelURL.path)
        let embExists = fm.fileExists(atPath: embeddingModelURL.path)

        if segExists && embExists {
            modelStatus = .installed
        } else {
            modelStatus = .notDownloaded
        }
    }

    // MARK: - Download

    @discardableResult
    func downloadModels() async -> Bool {
        guard !isDownloading else { return false }

        isDownloading = true
        downloadProgress = 0
        modelStatus = .downloading(progress: 0)

        do {
            applyHFEndpoint()

            // DiarizerModels.downloadIfNeeded() handles caching internally
            _ = try await DiarizerModels.downloadIfNeeded()

            modelStatus = .installed
            downloadProgress = 1.0
            isDownloading = false
            return true
        } catch {
            ErrorLogger.shared.log(
                "Diarization model download failed: \(error.localizedDescription)",
                source: "DiarizationModel"
            )
            modelStatus = .failed(message: error.localizedDescription)
            isDownloading = false
            return false
        }
    }

    /// Load models from local cache (assumes already downloaded).
    func loadModels() async throws -> DiarizerModels {
        let fm = FileManager.default
        if fm.fileExists(atPath: segmentationModelURL.path),
           fm.fileExists(atPath: embeddingModelURL.path) {
            return try await DiarizerModels.load(
                localSegmentationModel: segmentationModelURL,
                localEmbeddingModel: embeddingModelURL
            )
        }
        return try await DiarizerModels.downloadIfNeeded()
    }

    /// Ensure models are ready, downloading if needed.
    @discardableResult
    func ensureModelsReady() async -> Bool {
        checkStatus()
        if modelStatus.isReady { return true }
        return await downloadModels()
    }
}
