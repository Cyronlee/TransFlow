# 007-JSONL Changelog

## Implementation Complete

### New Files
- `TransFlow/TransFlow/Models/JSONLModels.swift` — JSONL data models (metadata, content entry, tagged union line type)
- `TransFlow/TransFlow/Services/JSONLStore.swift` — JSONL file I/O service (create session, append entries, list/read sessions)
- `TransFlow/TransFlow/Views/SessionBarView.swift` — Top bar UI showing current session name + new session button

### Modified Files
- `TransFlow/TransFlow/ViewModels/TransFlowViewModel.swift` — Integrated JSONLStore; auto-creates session on launch; persists completed sentences to JSONL; added `createNewSession()` method
- `TransFlow/TransFlow/ContentView.swift` — Added SessionBarView at the top of the content area
- `TransFlow/TransFlow/Localizable.xcstrings` — Added i18n strings: `session.new_session`, `session.create`, `session.cancel`, `session.filename_placeholder`
