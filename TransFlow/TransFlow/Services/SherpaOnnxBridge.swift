/// SherpaOnnxBridge.swift
/// Minimal Swift wrapper around the sherpa-onnx C API.
/// Adapted from https://github.com/k2-fsa/sherpa-onnx/blob/master/swift-api-examples/SherpaOnnx.swift
/// Only includes the APIs needed for offline recognition + VAD.

import Foundation

// MARK: - C String Helper

nonisolated private func toCPointer(_ s: String) -> UnsafePointer<CChar>! {
    (s as NSString).utf8String.map { UnsafePointer($0) }
}

// MARK: - Errors

enum SherpaOnnxBridgeError: LocalizedError {
    case recognizerCreationFailed
    case onlineRecognizerCreationFailed
    case onlineStreamCreationFailed
    case vadCreationFailed

    var errorDescription: String? {
        switch self {
        case .recognizerCreationFailed:
            "Failed to create SherpaOnnxOfflineRecognizer"
        case .onlineRecognizerCreationFailed:
            "Failed to create SherpaOnnxOnlineRecognizer"
        case .onlineStreamCreationFailed:
            "Failed to create SherpaOnnxOnlineStream"
        case .vadCreationFailed:
            "Failed to create SherpaOnnxVoiceActivityDetector"
        }
    }
}

// MARK: - Offline Recognizer

/// Swift wrapper for `SherpaOnnxOfflineRecognizer` (non-streaming ASR).
nonisolated final class SherpaOnnxOfflineRecognizerBridge: @unchecked Sendable {
    private let recognizer: OpaquePointer

    /// Create an offline recognizer for the NeMo Parakeet TDT transducer model.
    ///
    /// - Parameters:
    ///   - encoderPath: Path to encoder.int8.onnx
    ///   - decoderPath: Path to decoder.int8.onnx
    ///   - joinerPath: Path to joiner.int8.onnx
    ///   - tokensPath: Path to tokens.txt
    ///   - numThreads: Number of CPU threads (default: 2)
    init(
        encoderPath: String,
        decoderPath: String,
        joinerPath: String,
        tokensPath: String,
        numThreads: Int = 2
    ) throws {
        let transducer = SherpaOnnxOfflineTransducerModelConfig(
            encoder: toCPointer(encoderPath),
            decoder: toCPointer(decoderPath),
            joiner: toCPointer(joinerPath)
        )

        let modelConfig = SherpaOnnxOfflineModelConfig(
            transducer: transducer,
            paraformer: SherpaOnnxOfflineParaformerModelConfig(model: toCPointer("")),
            nemo_ctc: SherpaOnnxOfflineNemoEncDecCtcModelConfig(model: toCPointer("")),
            whisper: SherpaOnnxOfflineWhisperModelConfig(
                encoder: toCPointer(""), decoder: toCPointer(""),
                language: toCPointer(""), task: toCPointer("transcribe"),
                tail_paddings: -1
            ),
            tdnn: SherpaOnnxOfflineTdnnModelConfig(model: toCPointer("")),
            tokens: toCPointer(tokensPath),
            num_threads: Int32(numThreads),
            debug: 0,
            provider: toCPointer("cpu"),
            model_type: toCPointer("nemo_transducer"),
            modeling_unit: toCPointer("cjkchar"),
            bpe_vocab: toCPointer(""),
            telespeech_ctc: toCPointer(""),
            sense_voice: SherpaOnnxOfflineSenseVoiceModelConfig(
                model: toCPointer(""), language: toCPointer(""), use_itn: 0
            ),
            moonshine: SherpaOnnxOfflineMoonshineModelConfig(
                preprocessor: toCPointer(""), encoder: toCPointer(""),
                uncached_decoder: toCPointer(""), cached_decoder: toCPointer("")
            ),
            fire_red_asr: SherpaOnnxOfflineFireRedAsrModelConfig(
                encoder: toCPointer(""), decoder: toCPointer("")
            ),
            dolphin: SherpaOnnxOfflineDolphinModelConfig(model: toCPointer("")),
            zipformer_ctc: SherpaOnnxOfflineZipformerCtcModelConfig(model: toCPointer("")),
            canary: SherpaOnnxOfflineCanaryModelConfig(
                encoder: toCPointer(""), decoder: toCPointer(""),
                src_lang: toCPointer("en"), tgt_lang: toCPointer("en"), use_pnc: 1
            ),
            wenet_ctc: SherpaOnnxOfflineWenetCtcModelConfig(model: toCPointer("")),
            omnilingual: SherpaOnnxOfflineOmnilingualAsrCtcModelConfig(model: toCPointer("")),
            medasr: SherpaOnnxOfflineMedAsrCtcModelConfig(model: toCPointer("")),
            funasr_nano: SherpaOnnxOfflineFunASRNanoModelConfig(
                encoder_adaptor: toCPointer(""), llm: toCPointer(""),
                embedding: toCPointer(""), tokenizer: toCPointer(""),
                system_prompt: toCPointer(""), user_prompt: toCPointer(""),
                max_new_tokens: 512, temperature: 1e-6, top_p: 0.8, seed: 42
            )
        )

        let featConfig = SherpaOnnxFeatureConfig(sample_rate: 16000, feature_dim: 80)
        let lmConfig = SherpaOnnxOfflineLMConfig(model: toCPointer(""), scale: 0.5)
        let hr = SherpaOnnxHomophoneReplacerConfig(
            dict_dir: toCPointer(""), lexicon: toCPointer(""), rule_fsts: toCPointer("")
        )

        var config = SherpaOnnxOfflineRecognizerConfig(
            feat_config: featConfig,
            model_config: modelConfig,
            lm_config: lmConfig,
            decoding_method: toCPointer("greedy_search"),
            max_active_paths: 4,
            hotwords_file: toCPointer(""),
            hotwords_score: 1.5,
            rule_fsts: toCPointer(""),
            rule_fars: toCPointer(""),
            blank_penalty: 0,
            hr: hr
        )

        guard let ptr = SherpaOnnxCreateOfflineRecognizer(&config) else {
            throw SherpaOnnxBridgeError.recognizerCreationFailed
        }
        self.recognizer = ptr
    }

    deinit {
        SherpaOnnxDestroyOfflineRecognizer(recognizer)
    }

    /// Decode a batch of audio samples and return the transcription text.
    ///
    /// - Parameters:
    ///   - samples: Audio samples normalized to [-1, 1], 16 kHz mono.
    /// - Returns: The recognized text (trimmed).
    func decode(samples: [Float]) -> String {
        guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else {
            return ""
        }
        defer { SherpaOnnxDestroyOfflineStream(stream) }

        SherpaOnnxAcceptWaveformOffline(stream, 16000, samples, Int32(samples.count))
        SherpaOnnxDecodeOfflineStream(recognizer, stream)

        guard let resultPtr = SherpaOnnxGetOfflineStreamResult(stream) else {
            return ""
        }
        defer { SherpaOnnxDestroyOfflineRecognizerResult(resultPtr) }

        guard let cstr = resultPtr.pointee.text else { return "" }
        return String(cString: cstr).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Online Recognizer

/// Swift wrapper for `SherpaOnnxOnlineRecognizer` (streaming ASR).
nonisolated final class SherpaOnnxOnlineRecognizerBridge: @unchecked Sendable {
    private let recognizer: OpaquePointer
    private let stream: OpaquePointer

    init(
        encoderPath: String,
        decoderPath: String,
        joinerPath: String,
        tokensPath: String,
        numThreads: Int = 2,
        modelType: String = "nemo_transducer",
        modelingUnit: String = "bpe"
    ) throws {
        let transducer = SherpaOnnxOnlineTransducerModelConfig(
            encoder: toCPointer(encoderPath),
            decoder: toCPointer(decoderPath),
            joiner: toCPointer(joinerPath)
        )
        let usesBPE = modelingUnit.caseInsensitiveCompare("bpe") == .orderedSame
        // For bpe modeling units, sherpa-onnx expects bpe_vocab to be a valid file path.
        // Nemotron int8 packages provide tokens.txt, which is the correct vocab source.
        let bpeVocabPath = usesBPE ? tokensPath : ""

        let modelConfig = SherpaOnnxOnlineModelConfig(
            transducer: transducer,
            paraformer: SherpaOnnxOnlineParaformerModelConfig(
                encoder: toCPointer(""),
                decoder: toCPointer("")
            ),
            zipformer2_ctc: SherpaOnnxOnlineZipformer2CtcModelConfig(model: toCPointer("")),
            tokens: toCPointer(tokensPath),
            num_threads: Int32(numThreads),
            provider: toCPointer("cpu"),
            debug: 0,
            model_type: toCPointer(modelType),
            modeling_unit: toCPointer(modelingUnit),
            bpe_vocab: toCPointer(bpeVocabPath),
            tokens_buf: nil,
            tokens_buf_size: 0,
            nemo_ctc: SherpaOnnxOnlineNemoCtcModelConfig(model: toCPointer("")),
            t_one_ctc: SherpaOnnxOnlineToneCtcModelConfig(model: toCPointer(""))
        )

        let featConfig = SherpaOnnxFeatureConfig(sample_rate: 16000, feature_dim: 80)
        let ctcFstConfig = SherpaOnnxOnlineCtcFstDecoderConfig(
            graph: toCPointer(""),
            max_active: 3000
        )
        let hr = SherpaOnnxHomophoneReplacerConfig(
            dict_dir: toCPointer(""),
            lexicon: toCPointer(""),
            rule_fsts: toCPointer("")
        )

        var config = SherpaOnnxOnlineRecognizerConfig(
            feat_config: featConfig,
            model_config: modelConfig,
            decoding_method: toCPointer("greedy_search"),
            max_active_paths: 4,
            enable_endpoint: 1,
            rule1_min_trailing_silence: 2.4,
            rule2_min_trailing_silence: 1.2,
            rule3_min_utterance_length: 20,
            hotwords_file: toCPointer(""),
            hotwords_score: 1.5,
            ctc_fst_decoder_config: ctcFstConfig,
            rule_fsts: toCPointer(""),
            rule_fars: toCPointer(""),
            blank_penalty: 0,
            hotwords_buf: nil,
            hotwords_buf_size: 0,
            hr: hr
        )

        guard let recognizer = SherpaOnnxCreateOnlineRecognizer(&config) else {
            throw SherpaOnnxBridgeError.onlineRecognizerCreationFailed
        }
        guard let stream = SherpaOnnxCreateOnlineStream(recognizer) else {
            SherpaOnnxDestroyOnlineRecognizer(recognizer)
            throw SherpaOnnxBridgeError.onlineStreamCreationFailed
        }

        self.recognizer = recognizer
        self.stream = stream
    }

    deinit {
        SherpaOnnxDestroyOnlineStream(stream)
        SherpaOnnxDestroyOnlineRecognizer(recognizer)
    }

    func acceptWaveform(samples: [Float]) {
        SherpaOnnxOnlineStreamAcceptWaveform(stream, 16000, samples, Int32(samples.count))
    }

    func decodeWhileReady() {
        while SherpaOnnxIsOnlineStreamReady(recognizer, stream) == 1 {
            SherpaOnnxDecodeOnlineStream(recognizer, stream)
        }
    }

    func currentText() -> String {
        guard let result = SherpaOnnxGetOnlineStreamResult(recognizer, stream) else {
            return ""
        }
        defer { SherpaOnnxDestroyOnlineRecognizerResult(result) }

        guard let cstr = result.pointee.text else { return "" }
        return String(cString: cstr).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func inputFinished() {
        SherpaOnnxOnlineStreamInputFinished(stream)
    }

    func isEndpoint() -> Bool {
        SherpaOnnxOnlineStreamIsEndpoint(recognizer, stream) != 0
    }

    func reset() {
        SherpaOnnxOnlineStreamReset(recognizer, stream)
    }
}

// MARK: - Voice Activity Detector

/// Swift wrapper for `SherpaOnnxVoiceActivityDetector` (Silero VAD).
nonisolated final class SherpaOnnxVADBridge: @unchecked Sendable {
    private let vad: OpaquePointer

    /// Create a VAD using the Silero model.
    ///
    /// - Parameters:
    ///   - modelPath: Path to silero_vad.onnx
    ///   - threshold: Speech detection threshold (default: 0.5)
    ///   - minSilenceDuration: Minimum silence to end a speech segment (seconds)
    ///   - minSpeechDuration: Minimum speech segment duration (seconds)
    ///   - maxSpeechDuration: Maximum speech segment before forced split (seconds)
    ///   - windowSize: Window size in samples (default: 512 for 16kHz)
    ///   - bufferSizeInSeconds: Circular buffer size (seconds)
    init(
        modelPath: String,
        threshold: Float = 0.5,
        minSilenceDuration: Float = 0.25,
        minSpeechDuration: Float = 0.25,
        maxSpeechDuration: Float = 30.0,
        windowSize: Int = 512,
        bufferSizeInSeconds: Float = 60.0
    ) throws {
        let sileroConfig = SherpaOnnxSileroVadModelConfig(
            model: toCPointer(modelPath),
            threshold: threshold,
            min_silence_duration: minSilenceDuration,
            min_speech_duration: minSpeechDuration,
            window_size: Int32(windowSize),
            max_speech_duration: maxSpeechDuration
        )

        let tenVadConfig = SherpaOnnxTenVadModelConfig(
            model: toCPointer(""),
            threshold: 0.5,
            min_silence_duration: 0.25,
            min_speech_duration: 0.5,
            window_size: 256,
            max_speech_duration: 5.0
        )

        var vadConfig = SherpaOnnxVadModelConfig(
            silero_vad: sileroConfig,
            sample_rate: 16000,
            num_threads: 1,
            provider: toCPointer("cpu"),
            debug: 0,
            ten_vad: tenVadConfig
        )

        guard let ptr = SherpaOnnxCreateVoiceActivityDetector(&vadConfig, bufferSizeInSeconds) else {
            throw SherpaOnnxBridgeError.vadCreationFailed
        }
        self.vad = ptr
    }

    deinit {
        SherpaOnnxDestroyVoiceActivityDetector(vad)
    }

    /// Feed audio samples into the VAD.
    func acceptWaveform(samples: [Float]) {
        SherpaOnnxVoiceActivityDetectorAcceptWaveform(vad, samples, Int32(samples.count))
    }

    /// Whether there are detected speech segments available.
    var hasSegment: Bool {
        SherpaOnnxVoiceActivityDetectorEmpty(vad) == 0
    }

    /// Whether speech is currently being detected.
    var isSpeechDetected: Bool {
        SherpaOnnxVoiceActivityDetectorDetected(vad) != 0
    }

    /// Pop the front speech segment. Returns the audio samples of that segment.
    func popFrontSamples() -> [Float] {
        guard let p = SherpaOnnxVoiceActivityDetectorFront(vad) else {
            return []
        }
        defer { SherpaOnnxDestroySpeechSegment(p) }

        let n = Int(p.pointee.n)
        guard n > 0, let samplesPtr = p.pointee.samples else { return [] }
        let samples = Array(UnsafeBufferPointer(start: samplesPtr, count: n))

        SherpaOnnxVoiceActivityDetectorPop(vad)
        return samples
    }

    /// Flush remaining audio through the VAD (call at end of stream).
    func flush() {
        SherpaOnnxVoiceActivityDetectorFlush(vad)
    }

    /// Reset the VAD state.
    func reset() {
        SherpaOnnxVoiceActivityDetectorReset(vad)
    }
}
