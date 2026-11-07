---
name: changelog-updater
description: Updates and maintains CHANGELOG.md adhering to Keep a Changelog under [Unreleased].
---
# Changelog Updater
**Goal:** Maintain `CHANGELOG.md` per Keep a Changelog 1.1.0 & SemVer 2.0.0.

## USE WHEN
- Implementing, changing, or removing user-facing features or options (supported platforms, dynamic 6-tier derivation, soft WIP limits, 30-day retention pruning, `.tdf` blocks and directives, recurrence, activation conditions, workspaces, local `.tdf` persistence, WebDAV synchronization, UI screens/interactions, settings, diagnostic logging).
- Fixing user-facing bugs.

## RULES
- **Section:** ONLY under `## [Unreleased]`. Never commit or leave an empty `[Unreleased]` section.
- **Allowed Categories:** `### Added`, `### Changed`, `### Deprecated`, `### Removed`, `### Fixed`, `### Security`. Only include non-empty categories, separated by a blank line after each heading.
- **Scope (User-Facing ONLY):**
  - **INCLUDE:** Visible UI features, task management rules (tiers, soft limits, retention pruning, downgrade/complete/restore actions, recurring tasks, activation conditions, links, notes, subtasks), `.tdf` format capabilities and version migrations, workspace management, local `.tdf` file and WebDAV synchronization behavior, settings, and user-facing bugfixes.
  - **BANNED:** Internal refactors, internal codecs/helpers without standalone user impact (`Base64Service`, binary storage encoding), test additions or modifications (`M-*` rules), internal build/analyzer configurations (`analysis_options.yaml`), internal agent directives/skills, toolchain adjustments without user impact, and **internal source file paths (`lib/...`), Dart class/method inventories (`TaskBoard.completeTask`, `_LandingDrawer`), or widget test keys (`drawer_label_tile_<id>`)** (class and file inventories belong exclusively in `ARCHITECTURE.md`).
- **Entry Format (`P-LANG-RULES`):**
  - 1-line concise user-facing bullet (typically 15–35 words; never multi-clause file or class inventories).
  - Action verb matching the category (e.g., `Added ...`, `Changed ...`, `Deprecated ...`, `Removed ...`, `Fixed ...`).
  - Strict factual English (ASD-STE100 80%), zero emojis, no Markdown horizontal rules (`---`). Reference issue/PR if applicable (`(#123)`).
  - Consolidate or update existing `## [Unreleased]` entries when an unreleased feature is modified, renamed, or superseded before release so `## [Unreleased]` never contains contradictory intermediate steps.

## WORKFLOW
1. Verify user-facing impact. Skip if internal, refactor, or test-only.
2. Locate `## [Unreleased]` in `CHANGELOG.md` (create `CHANGELOG.md` with standard header if missing).
3. Add or update the entry under the matching category (`### Added`, `### Changed`, `### Fixed`, `### Removed`, etc.). Create the category header if missing.
