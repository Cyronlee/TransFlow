---
name: github-release
description: Publish a new GitHub Release for TransFlow with version bump, release notes, DMG build, and gh CLI. Use when the user asks to release a version, publish a release, create a GitHub release, or mentions "发布 vX.Y.Z".
---

# GitHub Release

Publish a new TransFlow version to GitHub Releases with DMG attachment.

## Prerequisites

- `gh` CLI installed and authenticated (`gh auth status`)
- `create-dmg` installed (`brew install create-dmg`)
- Xcode Command Line Tools
- Working directory clean (no uncommitted changes unrelated to release)

## Workflow

Parse the target version from the user's request (e.g. "发布 v1.2.0" → `1.2.0`). Strip the `v` prefix for version strings used in code; keep `v` prefix for git tags.

```
Task Progress:
- [ ] Step 1: Pre-flight checks
- [ ] Step 2: Update version numbers
- [ ] Step 3: Generate release notes
- [ ] Step 4: Commit, tag, push
- [ ] Step 5: Build DMG locally
- [ ] Step 6: Create GitHub Release with DMG
- [ ] Step 7: Verify release
```

### Step 1: Pre-flight checks

Run in parallel:
- `gh auth status` — confirm GitHub CLI is authenticated
- `git status` — confirm working directory is clean (or only has expected changes)
- `git log --oneline -20` — review recent commits for release notes

### Step 2: Update version numbers

Update `MARKETING_VERSION` in **all 6 locations** inside `project.pbxproj`:

```bash
# File: TransFlow/TransFlow.xcodeproj/project.pbxproj
# Replace all occurrences:
MARKETING_VERSION = <old>;  →  MARKETING_VERSION = <new>;
```

Update fallback version strings in Swift source:

| File | What to change |
|------|----------------|
| `TransFlow/TransFlow/Models/JSONLModels.swift` | `?? "X.Y.Z"` fallback in `init` |
| `TransFlow/TransFlow/Views/SettingsView.swift` | `?? "X.Y.Z"` fallback in `appVersionString` |

### Step 3: Generate release notes

Create `release-notes/vX.Y.Z.md` based on `git log` since the last tag (or all commits if first release).

> **Convention**: All release notes live in the `release-notes/` directory at the repo root, named `v<version>.md` (e.g. `release-notes/v1.0.0.md`).

Release notes template:

```markdown
# TransFlow vX.Y.Z

[One-line summary of this release]

## What's New
- Feature 1
- Feature 2

## Improvements
- Improvement 1

## Bug Fixes
- Fix 1 (if any)

## System Requirements
- macOS 15.0 or later
- Apple Silicon (arm64) or Intel (x86_64)
```

If there is a previous tag, use `git log <prev-tag>..HEAD --oneline` to scope changes.

### Step 4: Commit, tag, push

```bash
git add -A
git commit -m "release: bump version to vX.Y.Z"
git tag -a vX.Y.Z -m "TransFlow vX.Y.Z"
git push origin main --tags
```

### Step 5: Build DMG locally

```bash
./scripts/build-dmg.sh --clean --sign
```

- `--sign` will auto-detect signing identity and auto-load project entitlements (microphone, etc.)
- Set `block_until_ms` to 300000 (5 min) — build + DMG takes time
- Output: `build/TransFlow-X.Y.Z.dmg`
- Verify the DMG file exists and is non-empty before proceeding

### Step 6: Create GitHub Release

```bash
gh release create vX.Y.Z \
  --title "TransFlow vX.Y.Z" \
  --notes-file release-notes/vX.Y.Z.md \
  ./build/TransFlow-X.Y.Z.dmg
```

### Step 7: Verify release

```bash
gh release view vX.Y.Z
```

Confirm:
- Title and tag are correct
- `draft: false`, `prerelease: false`
- DMG asset is listed with non-zero size
- Release notes render correctly

Report the release URL to the user.

## Error Handling

| Error | Action |
|-------|--------|
| `gh auth` fails | Ask user to run `gh auth login` |
| `xcodebuild` fails | Check build errors, fix, retry |
| `create-dmg` exit code ≠ 0 and ≠ 2 | Check script output for details |
| `gh release create` fails | Check if tag already has a release; use `gh release delete vX.Y.Z` then retry |
| DMG file missing after build | Check `build/` directory; re-run build script |
