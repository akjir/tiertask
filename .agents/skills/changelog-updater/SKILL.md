---
name: changelog-updater
description: Updates and maintains CHANGELOG.md adhering to Keep a Changelog under [Unreleased].
---
# Changelog Updater
**Goal:** Maintain `CHANGELOG.md` per Keep a Changelog 1.1.0 and SemVer 2.0.0.

## USE WHEN
- Implementing, changing, or removing user-facing features or options (task tiers, auto-pull cascade, WIP limits, 30-day pruning, Markdown task schema, WebDAV synchronization, UI screens/interactions, settings).
- Fixing user-facing bugs.

## RULES
- **Section:** ONLY under `## [Unreleased]`. Never commit or leave an empty `[Unreleased]` section.
- **Allowed Categories:** `### Added`, `### Changed`, `### Deprecated`, `### Removed`, `### Fixed`, `### Security`. Only include non-empty categories.
- **Scope (User-Facing ONLY):**
  - **INCLUDE:** Visible UI features, task management rules (tiers, soft limits, retention pruning, downgrade/block/restore actions), Markdown file format changes, WebDAV sync and authentication behavior, user bugfixes.
  - **BANNED:** Internal refactors, test additions or modifications (`M-*` rules), internal analyzer/build configurations (`analysis_options.yaml`), internal agent directives/skills, toolchain adjustments without user impact.
- **Entry Format (`P-LANG-RULES`):**
  - 1-line concise bullet.
  - Action verb (e.g. `Added ...`, `Fixed ...`, `Updated ...`, `Removed ...`).
  - Strict English (ASD-STE100 80%), zero emojis, no Markdown horizontal rules (`---`). Reference issue/PR if applicable (`(#123)`).

## WORKFLOW
1. Verify user-facing impact. Skip if internal, refactor, or test-only.
2. Locate `## [Unreleased]` in `CHANGELOG.md` (create `CHANGELOG.md` with standard header if missing).
3. Add entry under matching category (`### Added`, `### Fixed`, etc.). Create category header if missing.
