---
name: changelog-updater
description: Updates and maintains CHANGELOG.md adhering to Keep a Changelog under [Unreleased].
---
# Changelog Updater
**Goal:** Maintain `CHANGELOG.md` per Keep a Changelog 1.1.0 & SemVer 2.0.0 with concise, strictly end-user-relevant entries.

## USE WHEN
- Adding, changing, or removing features, settings, or file format capabilities that directly affect end-user behavior.
- Fixing bugs or improving performance in ways observable by the user.

## RULES
- **Section:** Place new entries ONLY under `## [Unreleased]`. If `## [Unreleased]` does not exist (for example, right after a release), insert `## [Unreleased]` directly above the latest `## [X.Y.Z] - YYYY-MM-DD` section. Never commit or leave an empty `## [Unreleased]` section.
- **Allowed Categories:** `### Added`, `### Changed`, `### Deprecated`, `### Removed`, `### Fixed`, `### Security`. Include only non-empty categories, separated by a blank line after each heading.
- **Scope (End-User Behavior ONLY):**
  - **INCLUDE:** New user-facing features, observable behavior changes, workflow or UI improvements, `.tdf` format capabilities, synchronization changes, and user-facing bug or performance fixes.
  - **BANNED (Internal Changes):** Internal formatting, code restructuring, modularization, refactoring, architecture adjustments, build/analyzer configuration, agent skills/rules, or test changes (`M-*` rules) that do not alter observable program behavior.
  - **BANNED (Code-Specific Details):** Source file paths (`lib/...`), class, method, function, or widget identifiers (`TaskBoard`, `PageView`, `TierPageIndicator`), internal state/storage representations (`Base64Service`, binary encodings, `step true`), algorithm complexity notation (`O(N)`), and widget keys.
- **Outcome-Focused & Concise Wording (`P-LANG-RULES`):**
  - Describe the effect for the user, never the code mechanism. Write `Reduced startup time when loading large task boards.` instead of `Added XAdapterSubscriber function to accelerate execution time.`.
  - Keep every bullet brief (1 concise sentence, typically 8–20 words).
  - Start with an action verb matching the category (`Added ...`, `Changed ...`, `Deprecated ...`, `Removed ...`, `Fixed ...`, `Reduced ...`).
  - Use factual English (ASD-STE100 80%) with zero emojis and no Markdown horizontal rules (`---`).
  - Consolidate or update existing `## [Unreleased]` bullets when an unreleased change is modified or superseded before release.

## WORKFLOW
1. Verify observable end-user impact. Skip immediately if the change is internal, structural, or test-only.
2. Locate or create `## [Unreleased]` at the top of `CHANGELOG.md`.
3. Add or update a concise, code-free entry under the matching category (`### Added`, `### Changed`, `### Fixed`, `### Removed`, etc.).
