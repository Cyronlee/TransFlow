import Foundation
import Speech
import Observation

/// Represents the download/install status of a speech model for a specific locale.
enum SpeechModelStatus: Equatable {
    /// Model is already installed and ready to use.
    case installed
    /// Model is supported but not yet downloaded.
    case notDownloaded
    /// Model is currently being downloaded.
    case downloading(progress: Double)
    /// Model download/install failed.
    case failed(message: String)
    /// The locale is not supported on this device.
    case unsupported
    /// Status is being checked.
    case checking

    var isReady: Bool {
        if case .installed = self { return true }
        return false
    }

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }

    /// Localized display text for the status.
    var displayKey: String {
        switch self {
        case .installed: "model_status.installed"
        case .notDownloaded: "model_status.not_downloaded"
        case .downloading: "model_status.downloading"
        case .failed: "model_status.failed"
        case .unsupported: "model_status.unsupported"
        case .checking: "model_status.checking"
        }
    }
}

/// Manages Apple Speech model assets: checking status, downloading, and tracking progress.
///
/// Uses the macOS 26.0 `AssetInventory` API to manage on-device speech-to-text models.
/// Models are shared system resources — once downloaded, they persist across app launches
/// and are shared with other apps.
@Observable
@MainActor
final class SpeechModelManager {
    static let shared = SpeechModelManager()

    /// Status of the currently selected transcription language model.
    var currentModelStatus: SpeechModelStatus = .checking

    /// Per-locale model statuses (for settings display).
    var localeStatuses: [String: SpeechModelStatus] = [:]

    /// Whether a download is actively in progress.
    var isDownloading: Bool = false

    /// Download progress (0.0 – 1.0) for the active download.
    var downloadProgress: Double = 0

    /// The locale currently being downloaded (if any).
    var downloadingLocale: Locale?

    /// All supported locales from SpeechTranscriber.
    var supportedLocales: [Locale] = []

    private var progressObservation: (any NSObjectProtocol)?

    private init() {}

    // MARK: - Check Status

    /// Check the model status for a specific locale.
    func checkStatus(for locale: Locale) async -> SpeechModelStatus {
        // 1. Check if locale is supported
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            let status = SpeechModelStatus.unsupported
            localeStatuses[locale.identifier] = status
            return status
        }

        // 2. Create a temporary transcriber to check status
        let transcriber = SpeechTranscriber(
            locale: supportedLocale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        let assetStatus = await AssetInventory.status(forModules: [transcriber])

        let modelStatus: SpeechModelStatus
        switch assetStatus {
        case .installed:
            modelStatus = .installed
        case .downloading:
            modelStatus = .downloading(progress: downloadProgress)
        case .supported:
            modelStatus = .notDownloaded
        case .unsupported:
            modelStatus = .unsupported
        @unknown default:
            modelStatus = .notDownloaded
        }

        localeStatuses[locale.identifier] = modelStatus
        return modelStatus
    }

    /// Check and update the status for the current transcription locale.
    func checkCurrentStatus(for locale: Locale) async {
        currentModelStatus = .checking
        currentModelStatus = await checkStatus(for: locale)
    }

    /// Refresh statuses for all supported locales (for settings display).
    func refreshAllStatuses() async {
        let locales = await SpeechTranscriber.supportedLocales
        supportedLocales = locales.sorted { $0.identifier < $1.identifier }

        for locale in supportedLocales {
            let status = await checkStatus(for: locale)
            localeStatuses[locale.identifier] = status
        }
    }

    // MARK: - Download

    /// Ensure the model for a given locale is installed, downloading if necessary.
    /// Returns `true` if the model is ready after this call.
    @discardableResult
    func ensureModelReady(for locale: Locale) async -> Bool {
        let status = await checkStatus(for: locale)

        switch status {
        case .installed:
            currentModelStatus = .installed
            return true

        case .notDownloaded, .failed:
            return await downloadModel(for: locale)

        case .downloading:
            // Already downloading, wait for it
            return false

        case .unsupported:
            currentModelStatus = .unsupported
            return false

        case .checking:
            return false
        }
    }

    /// Download and install the speech model for a specific locale.
    /// Returns `true` on success.
    func downloadModel(for locale: Locale) async -> Bool {
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            currentModelStatus = .unsupported
            localeStatuses[locale.identifier] = .unsupported
            return false
        }

        let transcriber = SpeechTranscriber(
            locale: supportedLocale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        isDownloading = true
        downloadingLocale = locale
        downloadProgress = 0
        currentModelStatus = .downloading(progress: 0)
        localeStatuses[locale.identifier] = .downloading(progress: 0)

        do {
            // Reserve the locale for our app
            try await AssetInventory.reserve(locale: supportedLocale)

            // Request asset installation
            if let installRequest = try await AssetInventory.assetInstallationRequest(
                supporting: [transcriber]
            ) {
                // Observe download progress
                let progress = installRequest.progress
                startObservingProgress(progress, locale: locale)

                // Perform download and install (blocking)
                try await installRequest.downloadAndInstall()

                stopObservingProgress()
            }

            // Verify installation
            let finalStatus = await checkStatus(for: locale)
            currentModelStatus = finalStatus
            localeStatuses[locale.identifier] = finalStatus
            isDownloading = false
            downloadingLocale = nil

            return finalStatus.isReady

        } catch {
            ErrorLogger.shared.log("Model download failed for \(locale.identifier): \(error.localizedDescription)", source: "SpeechModel")
            let failedStatus = SpeechModelStatus.failed(message: error.localizedDescription)
            currentModelStatus = failedStatus
            localeStatuses[locale.identifier] = failedStatus
            isDownloading = false
            downloadingLocale = nil
            stopObservingProgress()
            return false
        }
    }

    // MARK: - Progress Observation

    private func startObservingProgress(_ progress: Progress, locale: Locale) {
        stopObservingProgress()

        progressObservation = progress.observe(
            \.fractionCompleted,
            options: [.new]
        ) { [weak self] progress, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let fraction = progress.fractionCompleted
                self.downloadProgress = fraction
                self.currentModelStatus = .downloading(progress: fraction)
                self.localeStatuses[locale.identifier] = .downloading(progress: fraction)
            }
        }
    }

    private func stopObservingProgress() {
        if let observation = progressObservation as? NSKeyValueObservation {
            observation.invalidate()
        }
        progressObservation = nil
    }

    // MARK: - Release

    /// Release reserved locale to free up a reservation slot.
    func releaseLocale(_ locale: Locale) async {
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            return
        }
        await AssetInventory.release(reservedLocale: supportedLocale)
        localeStatuses[locale.identifier] = .notDownloaded

        // Refresh to get accurate status
        let _ = await checkStatus(for: locale)
    }

    /// The maximum number of locales the app can reserve.
    var maximumReservedLocales: Int {
        AssetInventory.maximumReservedLocales
    }
}
