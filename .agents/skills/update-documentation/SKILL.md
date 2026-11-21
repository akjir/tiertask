---
name: update-documentation
description: Maintains README.md, ARCHITECTURE.md, AGENTS.md, spec/TDF_SPEC_0.8.0.md, and spec/UI_DESIGN_SYSTEM.md. Activate when editing docs or when platforms, tiers, TDF schemas, UI design guidelines, sync flows, architecture, or requirements change.
---

# Updating Documentation

## 1. Single Source of Truth Boundaries
- **`README.md` (Entry Point):** Keep `< 130` lines. Update ONLY for top-level features, supported platforms (`Linux`, `Android`, `Windows`), tier definitions, `.tdf` overview, requirements, build/install commands, or doc links. Never copy Dart class/method inventories, `lib/` paths, widget keys, full TDF grammar/error tables, or test matrices into `README.md`.
- **`spec/TDF_SPEC_0.8.0.md` (Format Spec):** Authoritative standalone `.tdf` format, grammar, bounds, 6-tier derivation, mutation, and sync spec. Never add Dart/Flutter paths or `AGENTS.md` rule IDs (see **`tdf-spec-workflow`**).
- **`spec/UI_DESIGN_SYSTEM.md` (UI Design System Spec):** Authoritative visual tokens, surface hierarchy, breakpoints, 17-widget catalog contract, expandable entity cards, interaction flows, keyboard shortcuts, and accessibility guidelines (`P-UI-DESIGN-SYSTEM`, **`ui-design-system`**). Keep synchronized whenever UI tokens, component contracts, or UX guidelines evolve.
- **`ARCHITECTURE.md` (Architecture & Inventory):** Authoritative layer table, DAG/UDF note, directory tree, public per-file responsibilities, and end-to-end execution/sync flow.
- **`AGENTS.md` (Agent Rules):** Authoritative engineering, TDD, layout, logging, and testing (`P-*`, `M-*`) rules. Keep well below `24,000` bytes (per-file rule cap) so Antigravity never truncates always-on rules.

## 2. `README.md` Structure (`< 130` Lines)
Omit a Table of Contents and maintain this exact section order:
1. **`# TierTask`:** Top `> [!IMPORTANT]` private-project disclaimer + 1-sentence factual summary (platforms, 6 derived tiers, `.tdf` format link).
2. **`## Overview`:** 1-sentence intro + concise 1-sentence feature bullets (pull system, scoped queues/conditions, three-way sync, workspaces/security, diagnostic logging) free of internal Dart symbols or widget keys.
3. **`## Requirements`:** 2-column table (`Component | Requirement`).
4. **`## Installation & Build`:** Copy-paste ready clone/setup/run commands plus `./install.sh` and obfuscated `flutter build <linux|apk|windows> --release --obfuscate --split-debug-info=build/symbols` commands.
5. **`## Quick Start`:** Short numbered steps for Settings, storage mode (`Local`, `WebDAV`, `Both`), adding tasks, and switching queues/labels.
6. **`## Tier System & Documentation`:** 6-tier table (`Tier | English (en) | German (de) | Soft Limit | Derivation Rule`), canonical `tdf 0.8.0` example (`tasks.tdf`), and links to `spec/TDF_SPEC_0.8.0.md`, `ARCHITECTURE.md`, `AGENTS.md`, and `CHANGELOG.md`.
7. **`## Development`:** Self-contained `flutter gen-l10n`, `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze --fatal-infos --fatal-warnings`, and `flutter test` commands.
8. **`## Disclaimer & License`:** 2-sentence warranty disclaimer and GPL-3.0 link (`LICENSE`).

## 3. `ARCHITECTURE.md` Structure & CLI Sync
Maintain this exact order and sync via `python3 .agents/scripts/tiertask_dev.py arch --sync-tree [--set <rel_path> "<desc>"] --audit`:
1. **`# TierTask Architecture and File Structure`** + sync callout referencing `AGENTS.md` and `spec/TDF_SPEC_0.8.0.md`.
2. **`## Architectural Layers`:** Layer table (`Localization`, `Models`, `Services`, `Repositories`, `Providers`, `UI`) + `P-UDF-ARCHITECTURE` / `P-ACYCLIC-DAG` / `P-IO-ISOLATION` callout.
3. **`## Directory Layout`:** Auto-synced ASCII tree (`arch --sync-tree`).
4. **Layer Tables (`## Root Files`, `## Localization`, `## Domain Models`, `## Services`, `## Repositories`, `## State Providers`, `## User Interface`):** 2-column (`File | Function`) concise 1-sentence rows (`<= 65` words) listing public classes/functions and core responsibilities only; never list private `_Widget` names, icons, or widget test keys.
5. **`## Execution & Synchronization Flow`:** Numbered end-to-end startup, workspace switching, multi-stage three-way `.tdf` sync, evaluation, 30-day pruning, and diagnostic logging flow.

## 4. Markdown Formatting Rules (`P-LANG-RULES`)
- Rely strictly on `##`/`###`/`####` headings; never use `---` body dividers, emojis, marketing adjectives, greetings, or closing summaries. Avoid em dashes (`—`) except in rare, clearly justified cases.
- Align tables with `:---`, escape `\|` inside cells, and use GitHub alerts (`> [!NOTE]`, `> [!IMPORTANT]`).
- Wrap filenames, symbols, commands, flags, tier names, and TDF directives in backticks; keep shell blocks directly copy-paste executable.
- Use generic placeholders (`https://cloud.example.com`, `example-user`, `tasks.tdf`); never use real credentials or third-party brand names.
