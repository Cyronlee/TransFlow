---
name: build-dmg
description: Build and package TransFlow.app into a DMG installer using create-dmg. Use when the user asks to build DMG, package the app, create an installer, or distribute the application.
---

# Build DMG

Package TransFlow.app into a DMG installer image.

## Quick Start

```bash
# Standard build + DMG (unsigned)
./scripts/build-dmg.sh

# Clean build + DMG with code signing (recommended for distribution)
./scripts/build-dmg.sh --clean --sign

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
- [ ] Step 2: Code sign (if --sign)
- [ ] Step 3: Create DMG
- [ ] Step 4: Verify output
```

**Step 1**: The script runs `xcodebuild` with Release configuration. When `--sign` is used, the build disables Xcode signing (`CODE_SIGN_IDENTITY="-"`, `CODE_SIGNING_REQUIRED=NO`, `CODE_SIGNING_ALLOWED=NO`) so the script handles signing separately.

**Step 2**: With `--sign`, the script auto-detects your signing identity (priority: `Developer ID Application` > `Apple Development` > any valid cert > ad-hoc `-`). It signs components inside-out: embedded frameworks, helper executables, then the main .app bundle with entitlements (`TransFlow.entitlements`). Verification uses `codesign --verify --strict`.

**Step 3**: `create-dmg` creates the DMG with background image, app icon, and Applications drop link. If using a real certificate (not ad-hoc), the DMG itself is also signed.

**Step 4**: Verify the DMG exists at `build/TransFlow-{version}.dmg`. Use `--open` to inspect visually.

## Signing Architecture

The script separates Xcode build from signing (following FluidVoice best practice):

1. **xcodebuild** runs with signing disabled — no developer-specific identity baked in during build
2. **codesign_app** re-signs the .app with proper identity and entitlements:
   - Inner components (Frameworks, helpers): signed without entitlements
   - Main .app bundle: signed with `--entitlements`, `--options runtime` (Hardened Runtime), `--timestamp`
3. **create-dmg** optionally signs the DMG itself with the same identity

Current signing identity: `5JNN9A6Z6X`, TeamIdentifier: `8RQVLSP2SC`

## Configuration

Edit variables at the top of `scripts/build-dmg.sh`:

| Variable | Default | Purpose |
|----------|---------|---------|
| `DMG_WINDOW_WIDTH/HEIGHT` | 800x600 | DMG window size |
| `DMG_ICON_SIZE` | 140 | App icon size in DMG |
| `DMG_APP_ICON_X/Y` | 245, 290 | App icon position |
| `DMG_APP_DROP_LINK_X/Y` | 555, 290 | Applications link position |

## Customizable Assets

| File | Purpose | Notes |
|------|---------|-------|
| `scripts/dmg/background.png` | DMG background | 800x600 px recommended |
| `scripts/dmg/volume-icon.icns` | DMG volume icon | Optional, auto-detected |

## Troubleshooting

**"create-dmg 未安装"**: Run `brew install create-dmg`.

**Exit code 2**: DMG was created but some Finder beautification failed (e.g., in headless/CI environments). Usually safe to ignore — the DMG is functional.

**"资源忙" / unmount failure**: The script auto-retries with `--hdiutil-retries 15` and falls back to manual `hdiutil convert` if needed.

**Signing verification fails**: Check that your certificate is valid (`security find-identity -v -p codesigning`). Ensure `TransFlow.entitlements` exists at the expected path.
