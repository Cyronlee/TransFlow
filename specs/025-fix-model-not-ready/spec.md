# 025 Model Downloaded but "Model Not Ready" Alert Still Appears

## Problem

Users download the speech recognition model in Settings, use the app normally for a while, then press the record button again and are shown a "Model Not Ready" alert claiming the model has not been downloaded.

## Root Cause

### 1. `ensureModelReady` returns `false` immediately on `.downloading` status

`SpeechModelManager.ensureModelReady` queries `AssetInventory.status`. When the system reports `.downloading` (background model update, a download triggered by `initialize()` still in progress, etc.), the code returns `false` immediately — despite the comment saying "wait for it":

```swift
case .downloading:
    // Already downloading, wait for it
    return false  // ← does not actually wait
```

This `false` propagates back to `startListening()`, which shows the error alert:

```swift
let modelReady = await modelManager.ensureModelReady(for: selectedLanguage)
guard modelReady else {
    showModelNotReadyAlert = true  // ← false alarm
    ...
}
```

### 2. Race condition in `switchLanguage`

`switchLanguage` spawns a `Task` to download the model asynchronously, but calls `startListening()` synchronously **outside** the Task, so they race:

```swift
Task {
    await modelManager.ensureModelReady(for: locale)  // async download
}
if wasListening {
    startListening()  // runs immediately, races with the Task above
}
```

### 3. `downloadModel` is not reentrant-safe

Multiple callers (`initialize`, `switchLanguage`, `startListening`, Settings UI) can invoke `downloadModel` for the same locale concurrently, producing duplicate downloads.

## Proposed Fix

### A. `ensureModelReady`: await the download instead of returning `false`

In the `.downloading` branch:
- If there is a tracked in-app download task for this locale, `await` its result.
- Otherwise (system-initiated download), poll `checkStatus` until the status resolves to a terminal state (`.installed` / `.failed` / `.unsupported`), with a 5-minute timeout.

### B. `downloadModel`: make it reentrant-safe

Track in-flight downloads in a `downloadTasks: [String: Task<Bool, Never>]` dictionary keyed by locale identifier. If a download for the same locale is already in progress, return the existing task's result instead of starting a duplicate.

### C. `switchLanguage`: eliminate the race

Move `startListening()` inside the `Task` block so it runs **after** `ensureModelReady` completes.

## Scope

| File | Change |
|------|--------|
| `Services/SpeechModelManager.swift` | A + B: modify `ensureModelReady` and `downloadModel`, add `pollUntilReady` helper and `downloadTasks` property |
| `ViewModels/TransFlowViewModel.swift` | C: modify `switchLanguage` |
| `ViewModels/VideoTranscriptionViewModel.swift` | No changes needed — automatically benefits from A |

## UX Impact

The record button stays in `.starting` state (existing spinner + disabled) while waiting for the model download to finish, then starts recording automatically. The "Model Not Ready" alert only appears when the model is genuinely unavailable (unsupported locale, download failure, or timeout).
