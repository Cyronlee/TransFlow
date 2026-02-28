# 019 Recordings — Changelog

## v2 (multi-segment, UI refinements)

### Changed
- **Recording filename** now uses timestamp: `rec_<yyyy-MM-dd_HH-mm-ss>.m4a` — each start/stop creates a new uniquely-named file instead of overwriting `rec_<sessionName>.m4a`
- **Removed `audio_offset_ms` / `audio_end_offset_ms`** from `JSONLContentEntry` — subtitle offsets are computed at runtime by comparing each content entry's `start_time` against its enclosing `recording_start` timestamp
- **Multi-segment playback** — `SessionAudioPlayer` now loads all recording segments from a session, merges them into a single continuous timeline, and automatically advances between segments
- **Click-to-seek** restricted to timestamp badge only — clicking the time label on each subtitle row seeks the audio; clicking the text itself no longer triggers seek (allows text selection)
- **Recording badge → duration** — "有录音" badge replaced with actual recording duration (e.g. `3:42`) in both the session list row and the detail toolbar
- **Duration placement** — recording duration shown before the entry count badge, not after the filename
- **Player bar layout** — play/pause and stop buttons grouped on the left side; bar height increased with `padding(.vertical, 10)`
- **Segment markers** — orange vertical lines on the seek slider mark the start of each additional recording segment

### Removed
- `history.has_recording` i18n key (no longer used)
- `audioOffsetMs` / `audioEndOffsetMs` properties and coding keys from `JSONLContentEntry`
- `computeAudioOffsetMs()` helper from `TransFlowViewModel`
- `recordingStartTime` property from `TransFlowViewModel`
- `cursor` helper View extension (timestamp cursor now handled inline)

### Files Modified
- `Models/JSONLModels.swift` — removed `audioOffsetMs`/`audioEndOffsetMs` from `JSONLContentEntry`, simplified initializers
- `Services/AudioRecordingService.swift` — `startRecording()` no longer takes `sessionName`; generates `rec_<timestamp>.m4a` filename
- `Services/JSONLStore.swift` — removed offset params from `appendEntry`; `SessionFile` now has `RecordingSegment` struct with `durationMs`, `totalRecordingDurationMs` computed property
- `Services/SessionAudioPlayer.swift` — complete rewrite for multi-segment: `load(allLines:)` builds merged timeline, computes entry offsets from recording timestamps, manages segment transitions
- `ViewModels/TransFlowViewModel.swift` — simplified recording lifecycle (no offset computation), calls `startRecording()` without session name
- `Views/AudioPlayerBarView.swift` — play+stop on left, taller bar, GeometryReader overlay for segment markers
- `Views/HistoryView.swift` — `EntryRowView` click-to-seek only on timestamp, `SessionRowView` shows duration before entry count, detail toolbar shows duration badge, `loadSession()` passes all lines to player
- `Localizable.xcstrings` — removed `history.has_recording` key

---

## v1 (initial)

### Added
- **Simultaneous recording** — audio is automatically recorded to M4A files during transcription, using the same AudioChunk stream as speech recognition
- **New JSONL line types**: `recording_start` and `recording_stop` markers bracket each recording segment, storing the file name, ISO8601 timestamp, and total duration
- **Audio player bar** in history session detail — play/pause, seek slider, time labels, and stop button for recording playback
- **Subtitle highlight** — during playback the currently active transcription entry is highlighted with accent color and auto-scrolled into view
- **Click-to-seek** — clicking a transcription entry in rich preview jumps the audio to that entry's offset and starts playback
- **Recording badge** — sessions with recordings show a waveform icon in both the session list and the detail toolbar

### Architecture
- `AudioRecordingService` writes 16kHz mono Float32 AudioChunks to M4A via `AVAudioFile` with AAC encoding
- `SessionAudioPlayer` wraps `AVAudioPlayer` as an `@Observable` class with 50ms timer updates for smooth slider tracking
- Recording stream is forked from the existing audio pipeline alongside engine and level streams, requiring no extra permissions or audio taps
- `JSONLStore` extended with `appendRecordingStart/Stop`, `readAllLines`, `readRecordingFiles`, and recording-aware session deletion

### Files Created
- `Services/AudioRecordingService.swift` — M4A file writer for AudioChunk streams
- `Services/SessionAudioPlayer.swift` — observable AVAudioPlayer wrapper for history playback
- `Views/AudioPlayerBarView.swift` — compact audio player bar UI component
