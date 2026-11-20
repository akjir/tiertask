---
name: changelog-updater
description: Updates CHANGELOG.md under [Unreleased] per Keep a Changelog for end-user-visible changes only. Skip internal refactors and fixes to unreleased code.
---

# Changelog Updater

Maintain `CHANGELOG.md` per Keep a Changelog 1.1.0 and SemVer 2.0.0 with concise, end-user-relevant entries.

## When to Use / Skip
- **Include:** New user-facing features, observable behavior/UI/workflow/sync/`.tdf` changes, and bug or performance fixes affecting an already-released version.
- **Skip (Fixes to Unreleased Code):** Never modify `CHANGELOG.md` or add `### Fixed` entries when fixing bugs, audit findings, or spec discrepancies in code introduced under `## [Unreleased]`.
- **Skip (Internal Changes):** Formatting, refactoring, modularization, build/analyzer config, agent rules/skills, or tests without observable user impact.

## Rules
- **Placement:** Put new entries ONLY under `## [Unreleased]`. If absent (e.g., right after a release), insert `## [Unreleased]` directly above the latest `## [X.Y.Z] - YYYY-MM-DD`. Never commit or leave an empty `## [Unreleased]` section.
- **Categories:** Use only non-empty headings from `### Added`, `### Changed`, `### Deprecated`, `### Removed`, `### Fixed`, `### Security`, each followed by a blank line.
- **No Code Internals:** Never mention file paths (`lib/...`), class/method/widget identifiers (`TaskBoard`, `PageView`), storage encodings (`Base64Service`, `step true`), complexity (`O(N)`), or widget keys.
- **Wording (`P-LANG-RULES`):**
  - Describe user outcome, not code mechanism (e.g., `Reduced startup time when loading large task boards.` instead of `Added XAdapterSubscriber to accelerate execution.`).
  - One concise sentence (8–20 words), starting with an action verb matching the category (`Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Reduced`).
  - Consolidate or update existing `## [Unreleased]` bullets when an unreleased change is modified or superseded before release.

## Steps
1. Verify observable end-user impact relative to the latest release tag; stop immediately without editing `CHANGELOG.md` if none.
2. Locate or insert `## [Unreleased]` at the top of `CHANGELOG.md`.
3. Add or consolidate a concise, code-free bullet under the matching category.
