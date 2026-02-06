@preconcurrency import ScreenCaptureKit
@preconcurrency import AVFoundation
import AppKit
import CoreMedia

/// Captures audio from a specific application using ScreenCaptureKit.
final class AppAudioCaptureService: NSObject, @unchecked Sendable, SCStreamOutput {

    private let continuation: AsyncStream<AudioChunk>.Continuation

    private init(continuation: AsyncStream<AudioChunk>.Continuation) {
        self.continuation = continuation
        super.init()
    }

    /// Fetch available GUI applications that can be captured.
    static func availableApps() async -> [AppAudioTarget] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false
            )
            let currentPID = ProcessInfo.processInfo.processIdentifier
            let runningApps = NSWorkspace.shared.runningApplications

            return content.applications.compactMap { app -> AppAudioTarget? in
                // Exclude self and hidden apps
                guard app.processID != currentPID else { return nil }

                // Cross-validate with NSWorkspace running applications
                guard let runningApp = runningApps.first(where: {
                    $0.processIdentifier == app.processID
                }) else { return nil }

                // Only include apps with a UI (not background daemons)
                guard runningApp.activationPolicy == .regular else { return nil }

                let name = app.applicationName
                guard !name.isEmpty else { return nil }

                return AppAudioTarget(
                    id: app.processID,
                    name: name,
                    bundleIdentifier: app.bundleIdentifier
                )
            }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            return []
        }
    }

    /// Start capturing audio from the specified app.
    /// Returns a stream of AudioChunks and a stop closure.
    static func startCapture(
        for target: AppAudioTarget
    ) async throws -> (stream: AsyncStream<AudioChunk>, stop: @Sendable () -> Void) {
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream(
            bufferingPolicy: .bufferingNewest(256)
        )

        // Find the SCRunningApplication for this target
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        )

        guard let scApp = content.applications.first(where: {
            $0.processID == target.id
        }) else {
            continuation.finish()
            throw CaptureError.appNotFound
        }

        // Create content filter for this app's audio
        // Use all windows of the app, or a display-based filter
        let filter: SCContentFilter
        let appWindows = content.windows.filter { $0.owningApplication?.processID == target.id }
        if !appWindows.isEmpty {
            filter = SCContentFilter(desktopIndependentWindow: appWindows[0])
        } else {
            // Fallback: use a display filter including only this app
            guard let display = content.displays.first else {
                continuation.finish()
                throw CaptureError.appNotFound
            }
            filter = SCContentFilter(display: display, including: [scApp], exceptingWindows: [])
        }

        // Configure stream
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.channelCount = 1
        config.sampleRate = 16_000
        // Minimize video overhead
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 fps

        let scStream = SCStream(filter: filter, configuration: config, delegate: nil)

        let service = AppAudioCaptureService(continuation: continuation)

        try scStream.addStreamOutput(
            service,
            type: SCStreamOutputType.audio,
            sampleHandlerQueue: DispatchQueue.global(qos: .userInteractive)
        )

        try await scStream.startCapture()

        let stop: @Sendable () -> Void = {
            Task {
                try? await scStream.stopCapture()
                continuation.finish()
            }
        }

        return (stream, stop)
    }

    // MARK: - SCStreamOutput

    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio else { return }
        guard let blockBuffer = sampleBuffer.dataBuffer else { return }

        let length = CMBlockBufferGetDataLength(blockBuffer)
        var data = Data(count: length)
        data.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: baseAddress)
        }

        // Convert to Float32 samples
        let formatDesc = sampleBuffer.formatDescription
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc!)?.pointee

        let samples: [Float]
        if let asbd, asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            // Already float
            samples = data.withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Float.self))
            }
        } else {
            // Int16 → Float32
            let int16Samples = data.withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Int16.self))
            }
            samples = int16Samples.map { Float($0) / 32768.0 }
        }

        guard !samples.isEmpty else { return }

        // Calculate level
        let sumOfSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        let rms = sqrt(sumOfSquares / Float(samples.count))
        let db = rms > 0 ? 20 * log10(rms) : -60
        let level = max(0, min(1, (db + 60) / 60))

        let chunk = AudioChunk(
            samples: samples,
            level: level,
            timestamp: Date()
        )
        continuation.yield(chunk)
    }

    enum CaptureError: Error, LocalizedError {
        case appNotFound

        var errorDescription: String? {
            switch self {
            case .appNotFound:
                "Target application not found"
            }
        }
    }
}
