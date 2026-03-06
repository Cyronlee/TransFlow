# Speech Model Lifecycle — AI Agent Reference

> **Audience**: AI coding agents. This document describes critical design constraints
> and invariants for the speech transcription pipeline. Violating these will cause
> hard-to-reproduce runtime bugs (model-not-ready after idle, silent failures,
> stale UI).

## Architecture Overview

```
TransFlowViewModel / VideoTranscriptionViewModel
        │
        ▼
  SpeechModelManager.shared  (singleton, @MainActor)
        │  ensureModelReady() / checkStatus()
        ▼
  AssetInventory + SpeechTranscriber  (Apple system frameworks)
        │
        ▼
  SpeechEngine  (per-session, Sendable)
        │  processStream() → AsyncStream<TranscriptionEvent>
        ▼
  SpeechAnalyzer + SpeechTranscriber  (Apple system frameworks)
```

## Critical Invariants — DO NOT BREAK

### 1. AssetInventory Stale Cache Workaround

**Problem**: macOS 26 `AssetInventory` has a known issue where its internal cache
goes stale after the app is idle for 30+ minutes. `reservedLocales` returns empty
and `status(forModules:)` reports installed models as `supported` (not downloaded).

**Solution (implemented)**:
- `SpeechModelManager` listens for `NSApplication.didBecomeActiveNotification`
- On activation, it re-validates all tracked `localeStatuses`
- If a previously-installed model now reports as not-installed, it calls
  `attemptReReserve()` which does `AssetInventory.reserve()` to kick the system
  out of the stale state, then re-checks
- `ensureModelReady()` also does a re-reserve + re-check before falling through
  to download when status is `notDownloaded`

**If you modify `SpeechModelManager`**:
- NEVER remove the `didBecomeActiveNotification` observer
- NEVER remove the re-reserve logic from `ensureModelReady()`
- NEVER cache `checkStatus()` results without a freshness mechanism
- ALWAYS call `checkStatus()` before trusting `localeStatuses` dict values
  in any code path that leads to transcription

### 2. Model Readiness Must Be Checked Before Every Transcription Start

Both `TransFlowViewModel.startListening()` and `VideoTranscriptionViewModel.startTranscription()`
MUST call `ensureModelReady()` and gate on its return value before creating a `SpeechEngine`.

`SpeechEngine.processStream()` assumes models are already installed. If called
with an uninstalled model, `SpeechAnalyzer.prepareToAnalyze()` will throw an opaque
error or silently produce no results.

**If you add a new transcription entry point**: ALWAYS include a
`modelManager.ensureModelReady(for: locale)` guard.

### 3. Lifecycle Observer Coordination

There are TWO lifecycle observers for `didBecomeActiveNotification`:

| Observer | Location | Responsibility |
|---|---|---|
| `SpeechModelManager.lifecycleObserver` | `SpeechModelManager.swift` | Re-validate ALL tracked locale statuses, re-reserve stale ones |
| `TransFlowViewModel.lifecycleObserver` | `TransFlowViewModel.swift` | Re-check current selected language status (only when idle) |

Both are required. The SpeechModelManager one handles the systemic cache refresh.
The ViewModel one ensures the current language UI indicator stays accurate.

**If you add another ViewModel** that uses speech models: add a similar lifecycle
observer that re-checks its selected locale on activation.

### 4. SettingsView Must Refresh On Every Appearance

`SettingsView` has a `hasLoadedModels` flag to avoid redundant first-load work.
However, it ALSO has an `.onAppear` block that calls `refreshAllStatuses()` on
subsequent visits to ensure the model list reflects current state.

**If you refactor SettingsView**: NEVER guard `refreshAllStatuses()` behind a
"load once" flag for subsequent appearances. The whole point is to re-query
AssetInventory each time the user opens Settings.

### 5. SpeechModelManager is @MainActor Singleton

- Access ONLY via `SpeechModelManager.shared`
- All state mutations happen on MainActor
- The `lifecycleObserver` callback dispatches to `@MainActor` via `Task`
- `isDownloading` acts as a guard to prevent lifecycle refresh during downloads

**If you add new public methods**: ensure they are called from MainActor context
or are explicitly `nonisolated`.

## File Dependency Map

When modifying any of these files, check the others for impact:

| File | Depends On | Depended By |
|---|---|---|
| `SpeechModelManager.swift` | `AssetInventory`, `SpeechTranscriber`, `ErrorLogger` | `TransFlowViewModel`, `VideoTranscriptionViewModel`, `SettingsView` |
| `SpeechEngine.swift` | `SpeechAnalyzer`, `SpeechTranscriber` | `TransFlowViewModel`, `VideoTranscriptionViewModel` |
| `TransFlowViewModel.swift` | `SpeechModelManager`, `SpeechEngine`, `AudioCaptureService` | `ContentView`, `BottomPanelView`, `TransFlowApp` |
| `VideoTranscriptionViewModel.swift` | `SpeechModelManager`, `SpeechEngine`, `AudioExtractorService` | `VideoTranscriptionView` |
| `SettingsView.swift` | `SpeechModelManager` | (UI only) |

## Logging

All lifecycle-critical operations log to `ErrorLogger.shared` with these sources:

- `SpeechModel` — model status checks, downloads, re-reserve attempts, stale cache detection
- `SpeechEngine` — engine initialization, analyzer preparation, finalization
- `Transcription` — listening start/stop, app activation, model-not-ready alerts

Logs are written to `~/Library/Application Support/<bundle-id>/logs/`.
When debugging model issues, look for `SpeechModel` source entries showing
status transitions (e.g., `installed → not_downloaded` indicates stale cache).

## Common Mistakes to Avoid

1. **Removing lifecycle observers** — The stale cache bug will return immediately
2. **Caching model status without re-query** — Status can change at any time due to system deallocation
3. **Starting SpeechEngine without ensureModelReady** — Will cause opaque crashes or silent failures
4. **Making SettingsView refresh one-shot** — Users won't see updated model states after idle
5. **Adding a new transcription path without model check** — Will hit "model not ready" after idle
6. **Removing re-reserve from ensureModelReady** — First-check-after-idle will fail, triggering unnecessary downloads
