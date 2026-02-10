---
name: build-dmg
description: Build and package TransFlow.app into a DMG installer using create-dmg. Use when the user asks to build DMG, package the app, create an installer, or distribute the application.
---

# Build DMG

Package TransFlow.app into a DMG installer image.

## Quick Start

```bash
# Standard build + DMG
./scripts/build-dmg.sh

# Clean build + DMG
./scripts/build-dmg.sh --clean

# Skip Xcode build, use existing .app
./scripts/build-dmg.sh --skip-build

# Open DMG after creation
./scripts/build-dmg.sh --open

# With ad-hoc signing (auto-detect or fallback to ad-hoc)
./scripts/build-dmg.sh --sign

# With specific certificate signing
./scripts/build-dmg.sh --sign "Developer ID Application: Your Name"

# Legacy codesign parameter (still supported)
./scripts/build-dmg.sh --codesign "Developer ID Application: Your Name"
```

Output: `build/TransFlow-{version}.dmg`

## Prerequisites

```bash
brew install create-dmg
```

## Workflow

```
Task Progress:
- [ ] Step 1: Build the app (or --skip-build)
- [ ] Step 2: Create DMG
- [ ] Step 3: Verify output
```

**Step 1**: The script runs `xcodebuild` with Release configuration automatically.

**Step 2**: `create-dmg` creates the DMG with background image, app icon, and Applications drop link.

**Step 3**: Verify the DMG exists at `build/TransFlow-{version}.dmg`. Use `--open` to inspect visually.

## Configuration

Edit variables at the top of `scripts/build-dmg.sh`:

| Variable | Default | Purpose |
|----------|---------|---------|
| `DMG_WINDOW_WIDTH/HEIGHT` | 600x400 | DMG window size |
| `DMG_ICON_SIZE` | 100 | App icon size in DMG |
| `DMG_APP_ICON_X/Y` | 170, 190 | App icon position |
| `DMG_APP_DROP_LINK_X/Y` | 430, 190 | Applications link position |

## Customizable Assets

| File | Purpose | Notes |
|------|---------|-------|
| `scripts/dmg/background.png` | DMG background | 600x400 px recommended |
| `scripts/dmg/volume-icon.icns` | DMG volume icon | Optional, auto-detected |

## Troubleshooting

**"create-dmg 未安装"**: Run `brew install create-dmg`.

**Exit code 2**: DMG was created but some Finder beautification failed (e.g., in headless/CI environments). Usually safe to ignore — the DMG is functional.

**"资源忙" / unmount failure**: The script auto-retries with `--hdiutil-retries 15` and falls back to manual `hdiutil convert` if needed.
