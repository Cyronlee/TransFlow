import Foundation
import Speech
import Observation
import AppKit

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
    private var lifecycleObserver: (any NSObjectProtocol)?

    private init() {
        setupLifecycleObserver()
    }

    // MARK: - App Lifecycle

    private func setupLifecycleObserver() {
        lifecycleObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.handleAppBecameActive()
            }
        }
    }

    /// Re-validate model statuses when the app returns to foreground.
    /// AssetInventory's internal cache can go stale after prolonged inactivity,
    /// causing reservedLocales and status queries to return incorrect results.
    private func handleAppBecameActive() async {
        guard !isDownloading else { return }

        let trackedCount = localeStatuses.count
        ErrorLogger.shared.log(
            "App became active — re-validating \(trackedCount) tracked locale(s)",
            source: "SpeechModel"
        )

        for (identifier, oldStatus) in localeStatuses {
            let locale = Locale(identifier: identifier)
            let freshStatus = await checkStatus(for: locale)

            if oldStatus.isReady && !freshStatus.isReady {
                ErrorLogger.shared.log(
                    "Stale cache detected for \(identifier): was installed, now \(freshStatus.displayKey) — attempting re-reserve",
                    source: "SpeechModel"
                )
                await attemptReReserve(for: locale)
            }
        }
    }

    /// Force re-reserve a locale to kick AssetInventory out of a stale state.
    private func attemptReReserve(for locale: Locale) async {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            ErrorLogger.shared.log(
                "Re-reserve skipped — no supported locale equivalent for \(locale.identifier)",
                source: "SpeechModel"
            )
            return
        }
        do {
            try await AssetInventory.reserve(locale: supported)
            ErrorLogger.shared.log(
                "Re-reserve succeeded for \(locale.identifier)",
                source: "SpeechModel"
            )
        } catch {
            ErrorLogger.shared.log(
                "Re-reserve failed for \(locale.identifier): \(error.localizedDescription)",
                source: "SpeechModel"
            )
        }
        let refreshed = await checkStatus(for: locale)
        ErrorLogger.shared.log(
            "Post re-reserve status for \(locale.identifier): \(refreshed.displayKey)",
            source: "SpeechModel"
        )
        if refreshed.isReady {
            currentModelStatus = refreshed
        }
    }

    // MARK: - Reservation Management

    /// Ensure there is at least one free reservation slot by releasing unused reservations.
    ///
    /// Apple limits each app to `maximumReservedLocales` (typically 5) reserved locales.
    /// Since we only need one locale at a time for transcription, we free up old
    /// reservations before downloading a new model. Downloaded models persist as
    /// system-managed resources even after their reservation is released.
    private func ensureReservationSlotAvailable(excluding locale: Locale) async {
        let reserved = await AssetInventory.reservedLocales
        guard reserved.count >= AssetInventory.maximumReservedLocales else { return }

        // Release reservations that are not currently being downloaded
        for reservedLocale in reserved {
            // Don't release the locale we're about to reserve
            if reservedLocale.identifier == locale.identifier { continue }
            // Don't release a locale that is currently downloading
            if let downloading = downloadingLocale, downloading.identifier == reservedLocale.identifier { continue }

            await AssetInventory.release(reservedLocale: reservedLocale)
            // One slot freed is enough
            break
        }
    }

    // MARK: - Check Status

    /// Check the model status for a specific locale.
    func checkStatus(for locale: Locale) async -> SpeechModelStatus {
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            let status = SpeechModelStatus.unsupported
            localeStatuses[locale.identifier] = status
            ErrorLogger.shared.log(
                "checkStatus(\(locale.identifier)): unsupported (no equivalent locale)",
                source: "SpeechModel"
            )
            return status
        }

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

        let prev = localeStatuses[locale.identifier]
        localeStatuses[locale.identifier] = modelStatus

        if let prev, prev != modelStatus {
            ErrorLogger.shared.log(
                "checkStatus(\(locale.identifier)): \(prev.displayKey) → \(modelStatus.displayKey)",
                source: "SpeechModel"
            )
        }

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
    ///
    /// When AssetInventory's cache is stale, the first status check may report
    /// a previously-installed model as `notDownloaded`. A re-reserve + re-check
    /// cycle often restores the correct state without a full re-download.
    @discardableResult
    func ensureModelReady(for locale: Locale) async -> Bool {
        ErrorLogger.shared.log(
            "ensureModelReady(\(locale.identifier)): checking status",
            source: "SpeechModel"
        )
        var status = await checkStatus(for: locale)

        if case .notDownloaded = status {
            ErrorLogger.shared.log(
                "ensureModelReady(\(locale.identifier)): status=notDownloaded, attempting re-reserve to recover stale cache",
                source: "SpeechModel"
            )
            await attemptReReserve(for: locale)
            status = await checkStatus(for: locale)
        }

        switch status {
        case .installed:
            ErrorLogger.shared.log(
                "ensureModelReady(\(locale.identifier)): ready",
                source: "SpeechModel"
            )
            currentModelStatus = .installed
            return true

        case .notDownloaded, .failed:
            ErrorLogger.shared.log(
                "ensureModelReady(\(locale.identifier)): status=\(status.displayKey), starting download",
                source: "SpeechModel"
            )
            return await downloadModel(for: locale)

        case .downloading:
            ErrorLogger.shared.log(
                "ensureModelReady(\(locale.identifier)): already downloading",
                source: "SpeechModel"
            )
            return false

        case .unsupported:
            ErrorLogger.shared.log(
                "ensureModelReady(\(locale.identifier)): unsupported",
                source: "SpeechModel"
            )
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
            ErrorLogger.shared.log(
                "downloadModel(\(locale.identifier)): no supported locale equivalent — aborting",
                source: "SpeechModel"
            )
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

        ErrorLogger.shared.log(
            "downloadModel(\(locale.identifier)): starting download (supported: \(supportedLocale.identifier))",
            source: "SpeechModel"
        )

        isDownloading = true
        downloadingLocale = locale
        downloadProgress = 0
        currentModelStatus = .downloading(progress: 0)
        localeStatuses[locale.identifier] = .downloading(progress: 0)

        do {
            await ensureReservationSlotAvailable(excluding: supportedLocale)
            try await AssetInventory.reserve(locale: supportedLocale)

            if let installRequest = try await AssetInventory.assetInstallationRequest(
                supporting: [transcriber]
            ) {
                let progress = installRequest.progress
                startObservingProgress(progress, locale: locale)
                try await installRequest.downloadAndInstall()
                stopObservingProgress()
            }

            let finalStatus = await checkStatus(for: locale)
            currentModelStatus = finalStatus
            localeStatuses[locale.identifier] = finalStatus
            isDownloading = false
            downloadingLocale = nil

            ErrorLogger.shared.log(
                "downloadModel(\(locale.identifier)): completed — final status: \(finalStatus.displayKey)",
                source: "SpeechModel"
            )

            return finalStatus.isReady

        } catch {
            ErrorLogger.shared.log(
                "downloadModel(\(locale.identifier)): failed — \(error.localizedDescription)",
                source: "SpeechModel"
            )
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
    /// The downloaded model may still be installed after release — the system manages model lifecycle.
    func releaseLocale(_ locale: Locale) async {
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            return
        }
        await AssetInventory.release(reservedLocale: supportedLocale)

        // Refresh to get accurate status (model may still be installed)
        let _ = await checkStatus(for: locale)
    }

    /// The maximum number of locales the app can reserve.
    var maximumReservedLocales: Int {
        AssetInventory.maximumReservedLocales
    }
}
