@preconcurrency import ScreenCaptureKit
@preconcurrency import AVFoundation
import AppKit
import CoreMedia

/// Captures audio from a specific application using ScreenCaptureKit.
final class AppAudioCaptureService: NSObject, Sendable {

    /// Target audio format: 16kHz mono Float32.
    static let targetSampleRate: Double = 16_000
    static let targetChannels: AVAudioChannelCount = 1

    /// Fetch available GUI applications that can be captured.
    @MainActor
    static func availableApps() async -> [AppAudioTarget] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false
            )
            let currentBundleID = Bundle.main.bundleIdentifier ?? ""

            // Build a lookup of regular, visible, non-terminated GUI apps
            var regularAppsLookup: [String: NSRunningApplication] = [:]
            for app in NSWorkspace.shared.runningApplications {
                guard !app.isTerminated,
                      app.activationPolicy == .regular,
                      !app.isHidden,
                      let bid = app.bundleIdentifier
                else { continue }
                regularAppsLookup[bid] = app
            }

            // Filter SC apps to only those in the regular-app set
            let filteredApps = content.applications.filter { app in
                !app.bundleIdentifier.isEmpty
                    && app.bundleIdentifier != currentBundleID
                    && !app.applicationName.isEmpty
                    && regularAppsLookup[app.bundleIdentifier] != nil
            }

            let apps: [AppAudioTarget] = filteredApps.map { app in
                // Retrieve the app icon from NSRunningApplication
                let iconData: Data? = {
                    guard let nsApp = regularAppsLookup[app.bundleIdentifier],
                          let icon = nsApp.icon else { return nil }
                    // Resize to 32x32 for efficiency
                    let size = NSSize(width: 32, height: 32)
                    let resized = NSImage(size: size)
                    resized.lockFocus()
                    icon.draw(in: NSRect(origin: .zero, size: size),
                              from: NSRect(origin: .zero, size: icon.size),
                              operation: .copy, fraction: 1.0)
                    resized.unlockFocus()
                    guard let tiff = resized.tiffRepresentation,
                          let rep = NSBitmapImageRep(data: tiff) else { return nil }
                    return rep.representation(using: .png, properties: [:])
                }()
                return AppAudioTarget(
                    id: app.processID,
                    name: app.applicationName,
                    bundleIdentifier: app.bundleIdentifier,
                    iconData: iconData
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            // Deduplicate by bundleIdentifier
            var seen = Set<String>()
            return apps.filter { app in
                guard let bid = app.bundleIdentifier else { return true }
                if seen.contains(bid) { return false }
                seen.insert(bid)
                return true
            }
        } catch {
            ErrorLogger.shared.log("Failed to fetch available apps: \(error.localizedDescription)", source: "AppAudioCapture")
            return []
        }
    }

    /// Start capturing audio from the specified app.
    /// Returns a stream of AudioChunks and a stop closure.
    static func startCapture(
        for target: AppAudioTarget
    ) async throws -> (stream: AsyncStream<AudioChunk>, stop: @Sendable () -> Void) {
        // Find the SCRunningApplication for this target
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        )

        guard let scApp = content.applications.first(where: {
            $0.processID == target.id
        }) else {
            throw CaptureError.appNotFound
        }

        // Use a display-based filter including only this app (captures all its audio)
        guard let display = content.displays.first else {
            throw CaptureError.appNotFound
        }

        let filter = SCContentFilter(
            display: display,
            including: [scApp],
            exceptingWindows: []
        )

        // Configure stream for audio capture
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000  // ScreenCaptureKit native rate
        config.channelCount = 1
        // Minimize video overhead since we only need audio
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 fps
        config.showsCursor = false

        let scStream = SCStream(filter: filter, configuration: config, delegate: nil)

        // Create audio output handler (handles 48kHz → 16kHz conversion)
        let handler = AudioStreamHandler(targetSampleRate: targetSampleRate)

        try scStream.addStreamOutput(
            handler,
            type: .audio,
            sampleHandlerQueue: DispatchQueue.global(qos: .userInteractive)
        )
        // Also register as screen output so ScreenCaptureKit doesn't log
        // "stream output NOT found. Dropping frame" errors for video frames.
        try scStream.addStreamOutput(
            handler,
            type: .screen,
            sampleHandlerQueue: nil
        )

        try await scStream.startCapture()

        nonisolated(unsafe) let capturedStream = scStream
        let stop: @Sendable () -> Void = {
            Task {
                try? await capturedStream.stopCapture()
            }
            handler.finish()
        }

        return (handler.audioStream, stop)
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

// MARK: - Audio Stream Handler

/// SCStreamOutput delegate that receives audio sample buffers and converts them to AudioChunks.
/// Uses @unchecked Sendable because the delegate callback runs on a specific serial queue.
private final class AudioStreamHandler: NSObject, SCStreamOutput, @unchecked Sendable {

    private let targetSampleRate: Double
    private let continuation: AsyncStream<AudioChunk>.Continuation
    let audioStream: AsyncStream<AudioChunk>
    nonisolated(unsafe) private var converter: AVAudioConverter?
    nonisolated(unsafe) private var converterInputFormat: AVAudioFormat?

    init(targetSampleRate: Double) {
        self.targetSampleRate = targetSampleRate

        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        self.audioStream = stream
        self.continuation = continuation

        super.init()
    }

    nonisolated func finish() {
        continuation.finish()
    }

    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        // Ignore video frames (we registered for .screen to suppress log warnings)
        guard type == .audio else { return }
        guard sampleBuffer.isValid, sampleBuffer.numSamples > 0 else { return }
        guard let formatDescription = sampleBuffer.formatDescription else { return }

        let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        guard let asbd = asbdPtr?.pointee else { return }

        // ScreenCaptureKit delivers Float32 audio. Build a matching AVAudioFormat.
        guard let sourceFormat = AVAudioFormat(
            standardFormatWithSampleRate: asbd.mSampleRate,
            channels: AVAudioChannelCount(asbd.mChannelsPerFrame)
        ) else { return }

        // Lazily create / recreate the converter when the source format changes
        if converter == nil || converterInputFormat != sourceFormat {
            guard let targetFormat = AVAudioFormat(
                standardFormatWithSampleRate: targetSampleRate,
                channels: 1
            ) else { return }
            converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
            converterInputFormat = sourceFormat
        }

        guard let converter = converter else { return }

        // Create AVAudioPCMBuffer from CMSampleBuffer
        let numSamples = sampleBuffer.numSamples
        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(numSamples)
        ) else { return }
        inputBuffer.frameLength = AVAudioFrameCount(numSamples)

        // Copy sample data into the PCM buffer using block buffer (more reliable)
        guard let blockBuffer = sampleBuffer.dataBuffer else { return }
        let dataLength = CMBlockBufferGetDataLength(blockBuffer)
        guard let channelData = inputBuffer.floatChannelData else { return }

        var data = Data(count: dataLength)
        data.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: dataLength, destination: baseAddress)
        }

        // Copy Float32 data to input buffer
        data.withUnsafeBytes { rawBuffer in
            guard let srcBase = rawBuffer.baseAddress else { return }
            let sampleCount = min(numSamples, dataLength / MemoryLayout<Float>.size)
            memcpy(channelData[0], srcBase, sampleCount * MemoryLayout<Float>.size)
        }

        // Convert to 16kHz mono
        let ratio = targetSampleRate / asbd.mSampleRate
        let outputFrameCount = AVAudioFrameCount(Double(numSamples) * ratio)
        guard outputFrameCount > 0 else { return }

        guard let targetFmt = AVAudioFormat(
            standardFormatWithSampleRate: targetSampleRate, channels: 1
        ),
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFmt,
                frameCapacity: outputFrameCount + 16
            )
        else { return }

        var conversionError: NSError?
        nonisolated(unsafe) var inputConsumed = false

        converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        guard conversionError == nil, outputBuffer.frameLength > 0 else { return }

        // Extract Float32 samples
        guard let outChannelData = outputBuffer.floatChannelData else { return }
        let frameCount = Int(outputBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: outChannelData[0], count: frameCount))

        // Calculate normalized audio level (RMS → dB → 0-1)
        let rms = Self.calculateRMS(samples)
        let db = 20 * log10(max(rms, 1e-10))
        let normalizedLevel = max(0, min(1, (db + 60) / 60))

        let chunk = AudioChunk(
            samples: samples,
            level: normalizedLevel,
            timestamp: Date()
        )

        continuation.yield(chunk)
    }

    nonisolated private static func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }
}
