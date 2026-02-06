# 001-init Changelog

## Implemented

### Project Structure
- Organized source files into `Models/`, `Services/`, `ViewModels/`, and `Views/` directories
- Xcode project uses `PBXFileSystemSynchronizedRootGroup` for automatic file discovery
- Swift 6.0 with strict concurrency safety (`SWIFT_STRICT_CONCURRENCY = complete`)
- macOS 26.0+ deployment target

### Models (`Models/`)
- **AudioChunk**: 16kHz mono Float32 audio data with normalized level and timestamp
- **TranscriptionSentence**: Completed sentence with timestamp, text, and optional translation
- **TranscriptionEvent**: Enum for partial/sentenceComplete/error events
- **ListeningState**: idle/starting/active/stopping state machine
- **AudioSourceType**: Microphone or app audio selection
- **AppAudioTarget**: Identifiable running application for ScreenCaptureKit capture

### Services (`Services/`)
- **SpeechEngine**: Core transcription engine using `SpeechAnalyzer` + `SpeechTranscriber` + `AssetInventory` (macOS 26.0 Speech framework). Accepts `AsyncStream<AudioChunk>`, outputs `AsyncStream<TranscriptionEvent>`. Handles format conversion, asset installation, batch audio accumulation (~200ms), and volatile/final result streaming.
- **AudioCaptureService**: Microphone capture via `AVAudioEngine` with `installTap`. Converts to 16kHz mono Float32, outputs ~100ms AudioChunks with RMS→dB→normalized level. Includes permission request via `AVAudioApplication.requestRecordPermission()`.
- **AppAudioCaptureService**: App audio capture via ScreenCaptureKit. Enumerates GUI apps via `SCShareableContent` cross-validated with `NSWorkspace`. Uses `SCStream` + `SCContentFilter` with `capturesAudio=true`, minimal video (2x2px, 1fps). Implements `SCStreamOutput` for `CMSampleBuffer` → Float32 conversion.
- **TranslationService**: Translation via Apple Translation framework. Session obtained through SwiftUI `.translationTask` modifier. Supports sentence translation, ~300ms debounced partial translation, and batch translation. Configuration invalidation for language changes.
- **SRTExporter**: SRT subtitle file export with relative timestamps, save panel integration, and optional translation lines.

### ViewModel (`ViewModels/`)
- **TransFlowViewModel**: `@Observable @MainActor` coordinator. Manages audio capture lifecycle, SpeechEngine creation, stream forking (engine + UI level), transcription event consumption, translation integration, language switching, and history management.

### Views (`Views/`)
- **ContentView**: Main view combining TranscriptionView + ControlBarView + translation task modifier + menu command handlers
- **TranscriptionView**: ScrollView with LazyVStack showing completed sentences (timestamp + text + translation) and volatile partial preview (gray/italic). Auto-scrolls to bottom.
- **ControlBarView**: Bottom toolbar with start/stop button, audio source picker (mic/app), language picker, translation toggle + target language, waveform visualization, export button, and error indicator.
- **AudioLevelView**: Small waveform bar visualization from audio level history

### App Configuration
- **TransFlowApp**: WindowGroup with default size 720x520, menu commands for Clear History (Cmd+K) and Export SRT (Cmd+Shift+E)
- **Entitlements**: App Sandbox, audio input, user-selected read-write files
- **Info.plist**: Microphone usage description

### Build
- Xcode build passes with zero code errors and zero code warnings
