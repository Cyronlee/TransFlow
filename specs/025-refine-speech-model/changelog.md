# 025 Refine Speech Model Language Management - Changelog

## Summary

Refine transcription language management across Settings, live transcription, and video transcription. Language pickers now only expose installed speech languages, while full language operations are moved into a dedicated management entry.

## Changes

### Settings

- Speech model list now shows **installed languages only**
- Added limit hint: app can activate up to `AssetInventory.maximumReservedLocales` languages at once
- Added bottom actions: **Refresh** and **Manage Languages**
- Added management sheet with full supported language list, allowing **Add** (reserve/download) and **Remove** (release reservation)
- Added **Done** action; closing sheet refreshes the outer list automatically

### Live Transcription (Home)

- Language dropdown now shows **installed languages only**
- Added empty-state warning when no installed speech language exists
- Added trailing **Manage Languages…** menu action to jump to Settings
- Added refresh-on-appearance for installed language list

### Video Transcription

- Source language dropdown now shows **installed languages only**
- Empty state now displays **None / 无**
- Added trailing **Manage Languages…** menu action to jump to Settings
- Start button is disabled when no installed speech language is available
- Added explicit error message when starting without any installed speech language

### ViewModel / Data Flow

- `TransFlowViewModel`: switched available language source from all supported locales to installed-ready locales
- `VideoTranscriptionViewModel`: switched available language source to installed-ready locales and added source-language selection helper
- Both flows continue to guard transcription start with `ensureModelReady()`

### i18n

- Added new String Catalog keys (both `en` and `zh-Hans`) for:
  - no-language warnings
  - manage-language actions
  - settings speech-model hint / refresh / manage / done
  - video no-language text and error messaging
