# 023 Minor Fixes – Changelog

## Changes

### Bug Fixes

- **HistoryView**: Replace SwiftUI `VideoPlayer` with `AVPlayerViewRepresentable` (NSViewRepresentable + AVPlayerView) to fix crash in release/DMG builds caused by `_AVKit_SwiftUI` metadata resolution failure
- **MainView / ContentView / TranslationService**: Move `.translationTask` from `ContentView` to `MainView` so the `TranslationSession` survives tab switches; fixes crash when navigating to History while live transcription + translation is active
- **SessionBarView**: Fix "Create" button being disabled when new session name is pre-filled; add `.onAppear` fallback and extract `trimmedName` computed property

### UI Improvements

- **HistoryView (AVPlayerViewRepresentable)**: Use `controlsStyle = .inline`, hide sharing service button and fullscreen toggle button for a cleaner video player
- **FloatingPreviewView**: Reorganize control buttons to horizontal layout (font size → pin → close), float above text instead of reserving right padding; replace font increase/decrease buttons with a single dropdown menu (12–72 pt); add border hover zone with resize cursor
- **TranscriptionView**: Add auto-scroll toggle button (chevron.down.2) at bottom-right corner, enabled by default; auto-scroll only triggers when toggle is on

### Logging

- **VideoHistoryPlayerModel**: Add error logs for player setup, cleanup, and view representable lifecycle
- **TranslationService**: Add error logs for session received, ready, prepare failure

### i18n

- Added keys: `floating_preview.font_size`, `transcription.auto_scroll_on`, `transcription.auto_scroll_off` (en + zh-Hans)
- Removed unused keys: `floating_preview.decrease_font`, `floating_preview.increase_font`

## Files Changed

| File | Summary |
|------|---------|
| `Views/HistoryView.swift` | AVPlayerViewRepresentable: inline controls, hide sharing/fullscreen buttons |
| `Views/MainView.swift` | Add `import Translation`, move `.translationTask` here from ContentView |
| `ContentView.swift` | Remove `.translationTask`, `import Translation`, and lifecycle hooks |
| `Services/TranslationService.swift` | Add logging to `handleSession`; remove unused suspend/resume methods |
| `Views/FloatingPreviewView.swift` | Rewrite control overlay (horizontal, floating); font size dropdown menu; border hover cursor; add `BorderHoverShape` |
| `Views/SessionBarView.swift` | Fix disabled button bug with `.onAppear` and `trimmedName` |
| `Views/TranscriptionView.swift` | Add `autoScroll` state and toggle button |
| `Models/AppSettings.swift` | Widen font size range to 12–72 |
| `Localizable.xcstrings` | Add new keys, replace old font keys with `floating_preview.font_size` |
