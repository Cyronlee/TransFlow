import Foundation

/// A chunk of audio data in 16kHz mono Float32 format.
struct AudioChunk: Sendable {
    /// Raw Float32 audio samples at 16kHz mono
    let samples: [Float]
    /// Normalized audio level (0.0 - 1.0)
    let level: Float
    /// When this chunk was captured
    let timestamp: Date
}
