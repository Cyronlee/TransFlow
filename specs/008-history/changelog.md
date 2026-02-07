# 008-History Changelog

## Implementation Complete

### New Files
- `TransFlow/TransFlow/Services/TranscriptionExporter.swift` — Unified export utility supporting SRT and Markdown formats, working with `[JSONLContentEntry]` data from JSONL files. Includes `ExportFormat` enum, content generation, and NSSavePanel integration.

### Modified Files

#### `TransFlow/TransFlow/Views/HistoryView.swift` (rewritten)
- Replaced placeholder empty state with a full-featured history browser
- **Left panel**: Session list with `HSplitView` layout
  - Displays session filename, creation time (from JSONL metadata), and entry count
  - Right-click context menu: Rename (inline text field) and Delete (with confirmation alert)
  - Count badge and header with session total
- **Right panel**: Content preview
  - Fixed toolbar area at the top with session info and export menu button
  - Export dropdown supporting SRT and Markdown formats via `TranscriptionExporter`
  - Scrollable entry list mirroring the main `TranscriptionView` / `SentenceRow` design (timestamp badge + original text + translation)
  - Empty states for no selection and no entries

#### `TransFlow/TransFlow/Services/JSONLStore.swift`
- Added `renameSession(from:to:)` — renames a JSONL file, updates current session reference if needed
- Added `deleteSession(name:)` — removes a JSONL file from the transcriptions directory
- Enriched `SessionFile` model with `entryCount` and `appVersion` fields
- `listSessions()` now reads metadata to get `createTime` from JSONL first line and counts entries per file

#### `TransFlow/TransFlow/Localizable.xcstrings`
- Added 9 new i18n keys (en + zh-Hans):
  - `history.sessions` — "Sessions" / "会话列表"
  - `history.rename` — "Rename" / "重命名"
  - `history.delete` — "Delete" / "删除"
  - `history.delete_confirm_title` — "Delete Session" / "删除会话"
  - `history.delete_confirm_message %@` — parametrized delete confirmation
  - `history.select_session` — "Select a session to preview" / "选择一个会话来预览"
  - `history.no_entries` — "No transcription entries" / "暂无转录条目"
  - `history.export` — "Export" / "导出"
  - `history.export_format %@` — parametrized "Export as %@" / "导出为 %@"
