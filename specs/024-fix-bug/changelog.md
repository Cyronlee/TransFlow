# 024 Fix Speech Model Stale Cache Bug – Changelog

## Summary

Fix "model not ready" error after app idle — caused by macOS 26 AssetInventory stale cache. Added lifecycle observers to re-validate and recover model state on app activation, plus comprehensive logging and AI agent documentation.

## Changes

### Bug Fixes

- **SpeechModelManager**: Add `NSApplication.didBecomeActiveNotification` observer; on activation, re-validate all tracked locale statuses and `attemptReReserve()` for any model that was previously installed but now reports otherwise (stale cache recovery)
- **SpeechModelManager**: Add re-reserve + re-check cycle in `ensureModelReady()` when first status check returns `notDownloaded`, preventing unnecessary re-downloads when cache is stale
- **TransFlowViewModel**: Add `didBecomeActiveNotification` observer to re-check current selected language model status when idle
- **SettingsView**: Add `.onAppear` refresh for subsequent visits (not just first load), so model list reflects current state after returning from idle

### Logging

- **SpeechModelManager** (`source: "SpeechModel"`): Log status transitions in `checkStatus()`, every step of `ensureModelReady()`, download start/complete/fail, stale cache detection, re-reserve success/fail
- **TransFlowViewModel** (`source: "Transcription"`): Log `startListening` params, model-not-ready alerts, `stopListening` state, app activation with listeningState
- **SpeechEngine** (`source: "SpeechEngine"`): Log processStream init, analyzer preparation (with format), finalization

### Documentation

- **`docs/speech-model-lifecycle.md`**: Full AI agent reference doc covering architecture, 5 critical invariants, file dependency map, logging guide, common mistakes
- **`.cursor/rules/speech-model-lifecycle.mdc`**: File-scoped rule for 5 related Swift files with must-not-break rules and new feature checklist
- **`.cursor/rules/global-rules.mdc`**: Added reference to speech model lifecycle doc

## Files Changed

| File | Summary |
|------|---------|
| `Services/SpeechModelManager.swift` | Add `AppKit` import, lifecycle observer, `handleAppBecameActive()`, `attemptReReserve()`, re-reserve in `ensureModelReady()`, logging throughout |
| `ViewModels/TransFlowViewModel.swift` | Add lifecycle observer, logging in `startListening`/`stopListening`/activation |
| `Services/SpeechEngine.swift` | Add logging in `processStream()` init/prepare/finalize |
| `Views/SettingsView.swift` | Add `.onAppear` refresh for subsequent visits |
| `docs/speech-model-lifecycle.md` | New: AI agent reference doc |
| `.cursor/rules/speech-model-lifecycle.mdc` | New: file-scoped cursor rule |
| `.cursor/rules/global-rules.mdc` | Add doc reference |
