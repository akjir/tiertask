---
name: release
description: Executes the official TierTask release workflow (verification gate, version alignment, concise user-facing CHANGELOG.md finalization, git commit, annotated vX.Y.Z tag, and push to origin). Triggered when the user types `/release <version>`, `/release v<version>`, or asks to release a version.
---

# TierTask Release Workflow (`/release`)

Execute this workflow when instructed to release a version (for example, `/release 0.1.0` or `Release version 0.2.0`). Every verification check must pass before committing, tagging, and pushing.

## 1. Pre-Flight Validation
1. **Normalize Version & Tag:** Strip any leading `v` to obtain `<VERSION>` (`X.Y.Z`) and verify that it matches strict SemVer (`^\d+\.\d+\.\d+$`). Set `<TAG>` to `v<VERSION>` (for example, `0.1.0` -> `v0.1.0`).
2. **Verify Branch:** Confirm `git branch --show-current` is `main` (or the target release branch).
3. **Verify Tag Availability:** Run `git rev-parse -q --verify "refs/tags/v<VERSION>"`. Abort immediately if the tag already exists.
4. **Pre-Release Verification Gate:** Run `python3 .agents/scripts/tiertask_dev.py verify --full`. Abort if any static check, formatter check, analyzer check, or test fails.

## 2. Version Alignment
When bumping to a new `<VERSION>` (`X.Y.Z`), ensure all version-bearing files match `<VERSION>`:
1. **`pubspec.yaml`:** Set `version: <VERSION>+<BUILD_NUMBER>` (incrementing `+<BUILD_NUMBER>` when bumping `<VERSION>`).
2. **`lib/repositories/app_version_repository.dart`:** Set `static const String packageVersion = '<VERSION>';` and align version doc comments.
3. **`linux/runner/CMakeLists.txt` & `linux/runner/generate_version.cmake`:** Set `PACKAGE_VERSION` to `<VERSION>`.
4. **`windows/runner/CMakeLists.txt` & `windows/runner/generate_version.cmake`:** Set `PACKAGE_VERSION` to `<VERSION>`.
5. **`android/app/build.gradle.kts`:** Update the fallback version string in `resolveFullAppVersion(..., flutter.versionName ?: "<VERSION>")`.
6. **Tests:** Update `packageVersion` expectations in `test/repositories/app_version_repository_test.dart` if `<VERSION>` changed.

## 3. Changelog Finalization (`CHANGELOG.md`)
1. Review all bullets under `## [Unreleased]` against `changelog-updater` rules:
   - Keep only changes relevant to end users that affect observable program behavior.
   - Remove internal formatting, code structuring, or refactoring notes.
   - Rewrite any code-specific wording into concise, user-focused statements without class, function, or file names.
2. Replace `## [Unreleased]` with `## [<VERSION>] - <YYYY-MM-DD>` using the current local date.
3. Do **not** insert or leave an empty `## [Unreleased]` section.

## 4. Post-Update Verification Gate
1. Run `python3 .agents/scripts/tiertask_dev.py verify --full` to confirm all tests, static analysis, formatting, and Markdown rules pass.
2. If any check fails, stop and fix or roll back before committing.

## 5. Commit, Annotated Git Tag (`v<VERSION>`) & Push to Origin
1. Stage all release changes (`git add -A`) and inspect `git status --short` and `git diff --cached --stat`.
2. Create the release commit and annotated tag:
   ```bash
   git commit -m "Release v<VERSION>"
   git tag -a "v<VERSION>" -m "Release v<VERSION>"
   ```
3. Verify that `git status --porcelain` is empty so compile-time Git version metadata resolves to `v<VERSION>+<count>.<hash>` without `.dev`.
4. Push the release commit and annotated tag to `origin`:
   ```bash
   git push origin HEAD
   git push origin "v<VERSION>"
   ```
5. Verify the commit, tag, and remote synchronization with `git log -1 --stat`, `git tag -n -l "v<VERSION>"`, and `git status -sb`.
