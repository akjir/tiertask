---
name: release
description: Executes the official TierTask release workflow (pre-flight verify, version alignment, CHANGELOG.md finalization, commit, annotated vX.Y.Z tag, and push). Triggered by /release <version> or release requests.
---

# TierTask Release Workflow (`/release`)

Run every verification gate before committing, tagging, and pushing.

## 1. Pre-Flight
1. **Normalize Version:** Strip any leading `v` to get `<VERSION>` (`^\d+\.\d+\.\d+$`); set `<TAG>` = `v<VERSION>`. Abort if invalid.
2. **Check Branch & Tree:** Confirm `git branch --show-current` is `main` (or the target release branch) and inspect `git status --short` so no unintended dirty or untracked files are swept into the release.
3. **Check Tag:** Run `git rev-parse -q --verify "refs/tags/v<VERSION>"`; abort if the tag already exists.
4. **Verify Baseline:** Run `python3 .agents/scripts/tiertask_dev.py verify --full`; abort on failure.

## 2. Version Alignment
Align all version-bearing files to `<VERSION>` (`X.Y.Z`):
1. `pubspec.yaml`: `version: <VERSION>+<BUILD_NUMBER>` (increment `<BUILD_NUMBER>` when bumping `<VERSION>`).
2. `lib/repositories/app_version_repository.dart`: `static const String packageVersion = '<VERSION>';` and matching version doc comments.
3. `linux/runner/CMakeLists.txt` & `linux/runner/generate_version.cmake`: `PACKAGE_VERSION` = `<VERSION>`.
4. `windows/runner/CMakeLists.txt` & `windows/runner/generate_version.cmake`: `PACKAGE_VERSION` = `<VERSION>`.
5. `android/app/build.gradle.kts`: fallback string in `resolveFullAppVersion(..., flutter.versionName ?: "<VERSION>")`.
6. `test/repositories/app_version_repository_test.dart`: update `packageVersion` expectations if `<VERSION>` changed.

## 3. Changelog Finalization (`CHANGELOG.md`)
1. Confirm `## [Unreleased]` exists and has entries; if missing or empty, stop and ask the user before proceeding.
2. Audit `## [Unreleased]` per **`changelog-updater`** (end-user observable changes only; remove internal/refactoring notes and code identifiers).
3. Replace `## [Unreleased]` with `## [<VERSION>] - <YYYY-MM-DD>` (current local date). Do not leave an empty `## [Unreleased]` heading.

## 4. Post-Update Verification
Run `python3 .agents/scripts/tiertask_dev.py verify --full`. Abort and fix or roll back on any failure.

## 5. Commit, Tag & Push
1. Run `git add -A` and inspect `git status --short` and `git diff --cached --stat`.
2. Commit and create the annotated tag:
   ```bash
   git commit -m "Release v<VERSION>"
   git tag -a "v<VERSION>" -m "Release v<VERSION>"
   ```
3. Confirm `git status --porcelain` is empty so compile-time Git version metadata resolves to `v<VERSION>+<count>.<hash>` without `.dev`.
4. Push commit and tag:
   ```bash
   git push origin HEAD
   git push origin "v<VERSION>"
   ```
5. Verify with `git log -1 --stat`, `git tag -n -l "v<VERSION>"`, and `git status -sb`.
