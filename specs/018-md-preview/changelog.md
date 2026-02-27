# 018 Markdown Preview — Changelog

## v1 (initial)

### Added
- **Markdown preview mode** in history session detail — a segmented toggle in the toolbar switches between "Preview" (rich) and "Markdown" (plain text) views
- **Markdown options bar** with toggle chips for:
  - **Timestamps** — show/hide `**[HH:mm:ss]**` prefix per entry
  - **Translation** — show/hide `> translated text` blockquotes
- **Copy All button** — copies the full generated markdown to clipboard with animated checkmark feedback (1.5s)
- Markdown text is displayed in a monospaced font with text selection enabled, suitable for direct copy-paste into editors
- Markdown generation reuses the same format as `TranscriptionExporter` (title, bold timestamps, blockquote translations)

### UI Design
- Segmented toggle uses a pill-style `HStack` with rounded background, matching Apple's native segmented control aesthetics
- Option chips use subtle bordered/filled states with smooth animations
- Copy button shows a green checkmark + "Copied" feedback with `contentTransition(.symbolEffect(.replace))`
- All controls use `.buttonStyle(.plain)` to avoid default button chrome

### Localization
- Added 6 new keys to `Localizable.xcstrings` (en + zh-Hans):
  - `history.mode.rich` — "Preview" / "预览"
  - `history.mode.markdown` — "Markdown" / "Markdown"
  - `history.md.show_time` — "Timestamps" / "时间戳"
  - `history.md.show_translation` — "Translation" / "翻译"
  - `history.md.copy_all` — "Copy All" / "复制全部"
  - `history.md.copied` — "Copied" / "已复制"

### Files Modified
- `Views/HistoryView.swift` — added `PreviewMode` enum; extended `SessionDetailView` with markdown preview, options bar, mode toggle, and copy functionality
- `Localizable.xcstrings` — added 6 i18n entries for the markdown preview feature
