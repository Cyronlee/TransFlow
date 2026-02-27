# 017 Hotkeys & UI Optimization — Changelog

## v1.3.0 (round 4)

### Changed
- **Global hotkeys now use CGEvent tap** — replaced previous `NSEvent.addGlobalMonitorForEvents` + `addLocalMonitorForEvents` dual monitor approach with a true system-level `CGEvent.tapCreate` event tap
- This fixes the issue where hotkeys did not work when the app was not focused, because `NSEvent.addGlobalMonitorForEvents` can only observe (not intercept) events and is unreliable without accessibility permission
- CGEvent tap runs at the session level (`cgSessionEventTap`) and can both intercept and consume matched key events
- Thread-safe `cachedBindings` static array ensures the C callback can read hotkey bindings without main-actor isolation issues

### Added
- **`GlobalHotkeyManager`** service (`Services/GlobalHotkeyManager.swift`) — singleton `@Observable` class managing:
  - CGEvent tap creation with retry logic (up to 5 attempts)
  - Periodic health check (every 30s) to re-enable/recreate tap if macOS disables it
  - Accessibility permission request via `AXIsProcessTrustedWithOptions` with polling (up to 60s)
  - `refreshCachedBindings()` called on every hotkey change from `AppSettings.didSet`
  - `configure()` accepts action closures; `dispatchAction()` routes from C callback to main actor
- Dynamic accessibility status in Settings UI:
  - Green shield + "granted" message when `isAccessibilityGranted` is true
  - Orange shield + "Grant Access" button + "Open Settings" link when not granted
- `NSAccessibilityUsageDescription` added to `Info.plist`
- Localization keys: `settings.hotkey.accessibility_granted`, `settings.hotkey.grant_access`

### Removed
- Inline hotkey monitoring code from `TransFlowApp.swift` (`installHotkeyMonitor`, `handleHotkeyEvent`)

### Files Modified
- `TransFlowApp.swift` — replaced `installHotkeyMonitor()` with `configureGlobalHotkeys()` using `GlobalHotkeyManager`
- `AppSettings.swift` — each hotkey `didSet` now calls `GlobalHotkeyManager.shared.refreshCachedBindings()`
- `SettingsView.swift` — added `hotkeyManager` state; redesigned `hotkeyAccessibilityHint` to show dynamic granted/not-granted status
- `Info.plist` — added `NSAccessibilityUsageDescription`
- `Localizable.xcstrings` — added `settings.hotkey.accessibility_granted`, `settings.hotkey.grant_access`
- **NEW** `Services/GlobalHotkeyManager.swift`

---

## v1.3.0 (round 3)

### Changed
- **Hotkeys upgraded to global hotkeys** — now work even when the app is not in the foreground
- Replaced single `NSEvent.addLocalMonitorForEvents` with dual monitors:
  - `addGlobalMonitorForEvents` for background key events (app inactive)
  - `addLocalMonitorForEvents` for foreground key events (app active, can swallow events)
- Extracted shared hotkey dispatch logic into `handleHotkeyEvent(_:)` for both monitors

### Added
- Accessibility permission hint below the Hotkeys settings section with a link to open System Settings → Privacy → Accessibility
- `settings.hotkey.accessibility_hint` localization key (en: "Global hotkeys require Accessibility permission.", zh-Hans: "全局快捷键需要辅助功能权限。")
- `settings.hotkey.open_accessibility` localization key (en: "Open Settings", zh-Hans: "打开设置")

### Files Modified
- `TransFlowApp.swift` — replaced single local monitor with global + local dual monitors; extracted `handleHotkeyEvent(_:)`
- `SettingsView.swift` — added `hotkeyAccessibilityHint` view below hotkeys section
- `Localizable.xcstrings` — added `settings.hotkey.accessibility_hint`, `settings.hotkey.open_accessibility`

---

## v1.3.0 (round 2)

### Fixed
- **Hotkey recorder now reliably captures key presses** — replaced SwiftUI `.onKeyPress` (which failed to receive events in many contexts) with `NSEvent.addLocalMonitorForEvents`, which intercepts key events at the AppKit level
- Pressing **ESC** during recording cancels without setting a binding
- Clicking the recorder button again while recording also cancels
- Event monitor is properly removed on cancel / view disappear to avoid leaks

### Changed
- Floating preview button icon changed from `arrow.up.left.and.arrow.down.right` to `rectangle.dock`
- Speech models section now has a **fixed max height (200pt)** with internal scrolling, preventing it from stretching the settings page
- Model action button text changed from "Download" → **"Select"** (`model_action.select`)
- "Ready" badge redesigned: now shows `✓ Ready` in a green pill-shaped badge (`checkmark` icon + green tinted background)
- Fixed compiler warning in `toggleMainWindow()` — removed redundant `is NSWindow` check

### Added
- `model_action.select` localization key (en: "Select", zh-Hans: "选择")

### Files Modified
- `SettingsView.swift` — rewrote `HotkeyRecorderView` with NSEvent monitor; speech models fixed-height scroll + Select button + Ready badge
- `ControlBarView.swift` — changed preview button icon to `rectangle.dock`
- `TransFlowApp.swift` — fixed `toggleMainWindow` warning
- `Localizable.xcstrings` — added `model_action.select`

---

## v1.3.0 (round 1)

### Removed
- Removed "Export SRT" button from the home page control bar (functionality remains available in History page)
- Removed Export SRT menu command (⌘⇧E) and associated notification infrastructure

### Changed
- Floating preview button now uses toggle interaction: click to open, click again to close
- Toggle button shows active state (accent color fill + white icon) when the floating preview is visible
- `FloatingPreviewPanelManager` now exposes `isVisible` and `toggle()` for open/close toggling

### Added
- **Hotkeys settings section** in Settings page with configurable keyboard shortcuts for:
  - Start / Stop Transcription
  - Enable / Disable Translation
  - Open / Close Floating Preview
  - Hide / Show Main Window
- `HotkeyBinding` model with keyCode + modifiers persistence via UserDefaults (JSON encoded)
- `HotkeyRecorderView` — click-to-record keyboard shortcut control with clear button
- In-app local key event monitor (`NSEvent.addLocalMonitorForEvents`) that dispatches hotkey actions
- Localization strings (en + zh-Hans) for all new UI elements

### Files Modified
- `ControlBarView.swift` — removed export button, changed preview button to toggle
- `ContentView.swift` — removed `.exportSRT` notification handler
- `TransFlowApp.swift` — removed export SRT menu command, added hotkey monitor
- `FloatingPreviewPanelManager.swift` — added `isVisible`, `toggle()`
- `AppSettings.swift` — added `HotkeyBinding` model and four hotkey binding properties
- `SettingsView.swift` — added Hotkeys section with `HotkeyRecorderView`
- `Localizable.xcstrings` — added `control.close_preview`, `settings.hotkeys`, `settings.hotkey.*` keys
