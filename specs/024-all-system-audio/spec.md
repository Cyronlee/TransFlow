# 024 — All System Audio Capture

## Background

Currently, users must select a specific app from the list to capture system audio. This adds an "All System Audio" option (similar to Apple Live Captions' "Computer Audio") that captures audio from all applications at once without needing to pick one.

---

## Model

- [ ] Add `.systemAudio` case to `AudioSourceType`

```swift
enum AudioSourceType: Sendable, Equatable, Hashable {
    case microphone
    case systemAudio
    case appAudio(AppAudioTarget?)
}
```

## Service

- [ ] Add `startSystemCapture()` to `AppAudioCaptureService`
  - Use `SCContentFilter` with the primary display and all applications included
  - Exclude TransFlow itself via `excludesCurrentProcessAudio = true`
  - Reuse the existing `AudioStreamHandler` for 48kHz → 16kHz conversion
  - Return type matches `startCapture(for:)`: `(stream: AsyncStream<AudioChunk>, stop: @Sendable () -> Void)`

## ViewModel

- [ ] Add `.systemAudio` branch in `TransFlowViewModel.startListening()` switch, calling `AppAudioCaptureService.startSystemCapture()`

## UI

- [ ] Add "System Audio" option in `ControlBarView.audioSourcePicker` menu, between Microphone and the app list divider
  - Icon: `speaker.wave.2.fill`
  - Sets `viewModel.audioSource = .systemAudio`
  - Checkmark logic same as existing items
- [ ] Update `audioSourceIconView` and `audioSourceName` to handle `.systemAudio`

## i18n

- [ ] Add key `control.system_audio` — en: "System Audio" / zh-Hans: "系统音频"

---

## Out of scope

- Hot-swapping audio sources while transcription is active (stop/start still required)
- Auto-detection of audio activity to switch between system audio and microphone
- Persisting audio source selection across launches
