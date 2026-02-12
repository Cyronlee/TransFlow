## Implementation Plan: Local Parakeet TDT via sherpa-onnx

### Goals
- Add a selectable local STT backend based on sherpa-onnx + Parakeet TDT 0.6B v2.
- Keep the app bundle free of model assets; users download models on demand.
- Preserve current Apple Speech backend as the default option.
- Provide live captions with partial text and finalized sentences.

### Non-Goals
- No cloud inference.
- No model fine-tuning or custom vocabulary training.
- No multilingual support beyond what the chosen model provides.

### Dependencies and Constraints
- sherpa-onnx native core (C++ + ONNX Runtime) embedded in the app bundle.
- User-downloaded model assets stored in Application Support.
- Model files: encoder.onnx, decoder.onnx, joiner.onnx, tokens.txt.
- macOS app code signing and notarization must include native libraries.
- Model license: Parakeet TDT 0.6B v2 is CC-BY-4.0 (attribution required).
- Download source must be official sherpa-onnx pre-converted artifacts.

### High-Level Architecture
- Add a new transcription backend that mirrors the existing `SpeechEngine` interface:
  - `processStream(_:) -> AsyncStream<TranscriptionEvent>`
- Route audio capture output (16kHz mono Float32) into the sherpa-onnx recognizer.
- Introduce a model manager for local model status and downloads.
- Add a settings UI section to choose engine and manage the model.
- Keep Apple Speech engine fully intact as the default and fallback.

### Data Model Additions
- `TranscriptionEngineKind`: `apple` | `parakeetLocal`
- `LocalModelVariant`: `int8` | `fp16` | `fp32`
- `LocalModelStatus`: `notDownloaded` | `downloading(progress)` | `ready` | `failed(message)`
- `LocalModelInfo`: `variant`, `status`, `path`, `sizeBytes`

### Storage Layout
- Model root directory:
  - `~/Library/Application Support/TransFlow/Models/ParakeetTDT0.6Bv2/`
- Variant subfolders (optional):
  - `int8/`, `fp16/`, `fp32/`
- Each variant folder contains the 4 required files.

### Download and Validation Flow
- Add a "Download Model" action in Settings:
  - Choose variant (default: int8).
  - Download official sherpa-onnx tarball and extract.
  - Validate required files before marking ready.
- Add "Delete Model" to remove local files.
- On app start and engine switch:
  - Validate model availability and update status.
- If a download is interrupted, resume if possible or clean up partial files.
- Store a local manifest (variant, version, file sizes, hash optional) for verification.

### Transcription Pipeline (Parakeet)
- Instantiate a sherpa-onnx recognizer using:
  - `model_type = "nemo_transducer"`
  - Paths from the user-downloaded model directory.
- Feed audio chunks continuously.
- For live captions:
  - Emit `.partial` text on periodic decode (e.g., every N ms).
  - Emit `.sentenceComplete` when end-of-speech is detected (VAD) or on stream stop.
- On engine stop, flush any remaining partial text into a final sentence.
- Ensure thread-safe access to the recognizer and background decoding.
- Normalize audio to the expected range and sample rate (already 16kHz mono).

### UI/UX Changes
- Settings: add a "Speech Recognition Engine" section:
  - Engine picker: Apple / Parakeet (Local)
  - Model status label: Not downloaded / Downloading / Ready / Error
  - Download + Delete buttons
  - Model location display
- Transcription UI behavior:
  - If Parakeet is selected but model is missing, show an inline prompt.
  - Fall back to Apple only if explicitly selected by the user.
- Show disk usage and estimated download size.
- Provide a simple error explanation if model validation fails.

### Localization
- Add string keys to `Localizable.xcstrings`:
  - `settings.engine`, `settings.engine.apple`, `settings.engine.parakeet`
  - `settings.model.download`, `settings.model.delete`
  - `settings.model.status.*` for all states
  - `settings.model.size`, `settings.model.location`, `settings.model.error`
  - `settings.model.license_notice`

### Implementation Steps
1. Add new engine selection state to app settings and view model.
2. Create a local model manager:
   - Download, extract, validate, delete, and report status.
3. Integrate sherpa-onnx native library and define a Swift wrapper.
4. Implement `ParakeetSpeechEngine` using sherpa-onnx APIs.
5. Update settings UI to manage engine and model status.
6. Wire engine selection in `TransFlowViewModel.startListening()`.
7. Add user messaging for missing model or download failures.
8. Add tests and a manual verification checklist.
9. Add license attribution surface for CC-BY-4.0.

### Milestones
1. **Backend selection + settings scaffolding**
   - Add engine selection to settings and persisted app state.
   - Basic model status UI (not downloaded / ready / error).
2. **Model manager + download flow**
   - Download/extract tarball, validate files, and delete flow.
   - Progress reporting and error handling.
3. **Native sherpa wrapper**
   - Build and embed sherpa-onnx + ONNX Runtime.
   - Swift API surface for init, feed audio, decode, reset, dispose.
4. **Parakeet engine integration**
   - Implement `ParakeetSpeechEngine` and wire into view model.
   - Partial text updates and final sentence emission.
5. **QA + performance tuning**
   - Validate live captions on representative Macs.
   - Tune chunk size, decode cadence, and VAD thresholds.
6. **Release hardening**
   - Verify code signing, notarization, and first-run download behavior.
   - Document the model download flow and attribution in README/Settings.

### Proposed API Surface (Swift)
- `protocol TranscriptionEngine`:
  - `func processStream(_ audioStream: AsyncStream<AudioChunk>) -> AsyncStream<TranscriptionEvent>`
  - `func stop()`
- `final class ParakeetSpeechEngine: TranscriptionEngine`
  - `init(modelDirectory: URL, decodeIntervalMs: Int, vadEnabled: Bool)`
  - Emits `.partial` for incremental text and `.sentenceComplete` on VAD end or stop.
- `final class LocalModelManager`
  - `var status: LocalModelStatus`
  - `var selectedVariant: LocalModelVariant`
  - `func checkStatus()`
  - `func download(variant: LocalModelVariant)`
  - `func delete(variant: LocalModelVariant)`
  - `func modelDirectory(variant: LocalModelVariant) -> URL`
- `final class ParakeetModelValidator`
  - `func validate(directory: URL) -> LocalModelStatus`
  - Checks presence, minimum sizes, and optional hash verification.

### Testing Plan
- Unit tests:
  - Model path validation and status transitions.
  - Download error handling and cleanup.
- Manual tests:
  - Download int8 model and run live captions.
  - Switch engines while idle and while listening.
  - Stop/start listening and ensure partial text flushes correctly.
  - Delete model and confirm UI updates.
  - Disconnect network mid-download and verify resume/cleanup.
  - Run on Intel and Apple Silicon hardware.

### Risks and Mitigations
- Large model size: offer int8 default and show disk usage.
- Latency on older Macs: allow tuning of decode interval.
- Native library integration issues: isolate with a wrapper and minimal Swift API surface.
- License compliance: show attribution in Settings/About.
- Model corruption: validate on startup and on selection.
