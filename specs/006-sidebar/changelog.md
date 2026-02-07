# 006 - Sidebar & Internationalization Changelog

## Summary

Added a macOS NavigationSplitView sidebar with three navigation destinations (Transcription, History, Settings), a Settings page, and full i18n support for English and Simplified Chinese.

## Changes

### New Files

| File | Description |
|------|-------------|
| `Views/MainView.swift` | Root view with `NavigationSplitView`, sidebar starts collapsed (`detailOnly`), balanced split style |
| `Views/SidebarView.swift` | Sidebar list with `SidebarDestination` enum (transcription, history, settings), Apple system icons |
| `Views/SettingsView.swift` | Settings page with three sections: General (language picker), Feedback (link to GitHub Issues), About (version/build) |
| `Views/HistoryView.swift` | Placeholder history view with empty state design |
| `Models/AppSettings.swift` | `@Observable` singleton managing app language preference, persists via `UserDefaults`, supports system/English/Chinese |
| `Localizable.xcstrings` | String Catalog with 30+ keys, fully translated for `en` and `zh-Hans` |

### Modified Files

| File | Changes |
|------|---------|
| `TransFlowApp.swift` | Swapped `ContentView()` for `MainView()`, injected `settings.locale` into environment, localized menu bar commands |
| `ContentView.swift` | Replaced hardcoded strings ("Press Start to begin transcription", "Microphone permission is required", "Listening...") with localized keys |
| `Views/ControlBarView.swift` | Replaced all hardcoded UI strings and help/accessibility texts with localized keys. Changed `recordButtonHelpText` and `recordButtonAccessibilityLabel` from `String` to `LocalizedStringKey` |
| `project.pbxproj` | Added `zh-Hans` to `knownRegions` |

### Iteration 2 — Appearance Mode

Added manual appearance (dark/light mode) switching to Settings, below the language picker.

| File | Changes |
|------|---------|
| `Models/AppSettings.swift` | Added `AppAppearance` enum (system/light/dark) with `colorScheme` computed property; added `appAppearance` property persisted via `UserDefaults` |
| `Views/SettingsView.swift` | Added `appearanceRow` with purple half-circle icon and menu picker, separated from language row by a divider |
| `TransFlowApp.swift` | Applied `.preferredColorScheme(settings.appAppearance.colorScheme)` on root view |
| `Localizable.xcstrings` | Added 4 keys: `appearance.system` / `appearance.light` / `appearance.dark` / `settings.appearance` (en + zh-Hans) |
| `.cursor/rules/global-rules.mdc` | Added concise rules for i18n and appearance mode |

## Architecture Decisions

- **NavigationSplitView** over TabView: Better fit for macOS desktop apps with collapsible sidebar; starts hidden (`detailOnly`) per spec requirement, toggle via system sidebar button
- **NavigationSplitViewVisibility.detailOnly**: Sidebar is collapsed by default, users can open it to access History and Settings
- **.balanced style**: Equal prominence for sidebar and detail when sidebar is visible
- **String Catalog (.xcstrings)**: Modern Xcode localization format, source language `en`, manually extracted keys for full control
- **AppSettings singleton**: `@Observable` with `UserDefaults` persistence, sets `AppleLanguages` override and SwiftUI `.locale` environment for immediate language switching without app restart
- **Feedback via GitHub Issues**: Opens external browser link; can be replaced with in-app form later

## Localization

- Source language: English (`en`)
- Supported: Simplified Chinese (`zh-Hans`)
- 30+ localized string keys covering: sidebar labels, settings UI, control bar, empty states, menu commands
- Language display names shown in native script (English / 简体中文)
