## Implementation Summary

### New File
- `TransFlow/TransFlow/Services/ErrorLogger.swift` — Lightweight error logger service

### Modified Files
- `TransFlow/TransFlow/TransFlowApp.swift` — Initialize ErrorLogger on app launch
- `TransFlow/TransFlow/ViewModels/TransFlowViewModel.swift` — Log audio capture & transcription errors
- `TransFlow/TransFlow/Services/SpeechEngine.swift` — Log speech engine errors
- `TransFlow/TransFlow/Services/TranslationService.swift` — Log translation errors
- `TransFlow/TransFlow/Services/AppAudioCaptureService.swift` — Log app audio capture errors
- `TransFlow/TransFlow/Services/SpeechModelManager.swift` — Log model download failures
- `TransFlow/TransFlow/Services/UpdateChecker.swift` — Log update check failures
- `TransFlow/TransFlow/Views/SettingsView.swift` — Add "Error Logs" button in feedback section
- `TransFlow/TransFlow/Localizable.xcstrings` — Add `settings.open_logs` and `settings.open_logs_description` strings (en + zh-Hans)
