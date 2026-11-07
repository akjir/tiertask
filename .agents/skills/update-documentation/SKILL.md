---
name: update-documentation
description: >-
  Maintain and update README.md, ARCHITECTURE.md, AGENTS.md, and TDF_SPEC.md for TierTask. Activate whenever editing documentation or when supported platforms, task tier rules, TDF (.tdf) file schemas, local file or WebDAV synchronization, architecture layers, or system requirements change.
---

# Updating Documentation

## 1. Strict Separation of Concerns (Single Source of Truth)
* **`README.md` (Project Entry Point):** Keep under 130 lines. Do NOT copy detailed Dart class/method inventories, file paths (`lib/...`), widget test keys, full TDF grammar/error tables, or internal test matrices into `README.md`. Update `README.md` ONLY when top-level features, supported platforms (`Linux`, `Android`, `Windows`), tier definitions, `.tdf` format overview, system requirements, installation/build steps, or repository document links change.
* **`TDF_SPEC.md` (Format Specification):** Single Source of Truth for the TierTask Data Format (`TDF`) lexical rules, root-block grammar (`queue`, `deleted`, `label`, `task`), parser resource bounds, dynamic 6-tier derivation pipeline, and state mutation/synchronization semantics used in `*.tdf`. Never add project-specific implementation paths or rule IDs into `TDF_SPEC.md` (see **`tdf-spec-workflow`**).
* **`ARCHITECTURE.md` (Architecture & File Structure):** Single Source of Truth for the architectural layers (`Localization`, `Models`, `Services`, `Repositories`, `Providers`, `UI`), directory tree, per-file class responsibilities, and local file / WebDAV execution and synchronization flow.
* **`AGENTS.md` (AI Engineering & TDD Rules):** Single Source of Truth for TDD workflow (`P-TDD-FIRST`), language rules (`P-LANG-RULES`), deterministic `.dart` file layout, static analysis rules, diagnostic logging policy, and mandatory `M-*` test categories.

## 2. `README.md` Structure (<130 Lines)
Omit a Table of Contents. Maintain this exact section order:
1. **`# TierTask`:** `> [!IMPORTANT]` private project disclaimer callout at the top, followed by a 1-sentence factual summary of `TierTask`, its supported platforms (`Linux`, `Android`, `Windows`), its 6 dynamically derived tiers (`Focus`, `Ready`, `Planned`, `Blocked`, `Someday`, `Completed`), and the block-based TierTask Data Format (`TDF`).
2. **`## Overview`:** Short 1-sentence intro + concise 1-sentence bullet list of core architectural traits (`Cross-Platform Desktop & Mobile`, `Unified Block DSL (TDF)`, `Deterministic 6-Tier Derivation`, `Context-Aware Conditions & Recurrence`, `Two-Stage Three-Way Synchronization`, `Multi-Workspace & Encrypted Settings`, `Opt-In Diagnostic Logging`) free of internal Dart class names, method signatures, or widget test keys.
3. **`## Requirements`:** 2-column table (`Component | Requirement`).
4. **`## Installation & Build`:** Copy-paste ready `git clone`, `flutter pub get`, `flutter gen-l10n`, debug `flutter run`, and obfuscated `flutter build <target> --release --obfuscate --split-debug-info=build/symbols` commands (`linux`, `apk`, `windows`) separated into short descriptive blocks.
5. **`## Quick Start`:** Self-contained numbered steps for configuring display language/theme, configuring `Local` / `WebDAV` / `Both` storage (`tasks.tdf`), creating tasks with `Priority`, `Someday`, or `Labels`, and synchronizing the board.
6. **`## Tier System & Documentation`:** Summary table of the 6 tiers (`Tier | English (en) | German (de) | Soft Limit | Derivation Rule`), canonical `tasks.tdf` example (`tdf 0.5.1`), and a bullet list of links to `[TDF_SPEC.md](TDF_SPEC.md)`, `[ARCHITECTURE.md](ARCHITECTURE.md)`, `[AGENTS.md](AGENTS.md)`, and `[CHANGELOG.md](CHANGELOG.md)`.
7. **`## Development`:** Self-contained `flutter gen-l10n`, `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze --fatal-infos --fatal-warnings`, and `flutter test` commands.
8. **`## Disclaimer & License`:** 2-sentence warranty disclaimer and GPL-3.0 link to `[LICENSE](LICENSE)`.

## 3. `ARCHITECTURE.md` Structure & Automation (`tiertask_dev.py arch`)
Maintain this exact section order and use `python3 .agents/scripts/tiertask_dev.py arch --sync-tree [--set <rel_path> "<description>"] --audit` to keep the directory tree and tables synchronized:
1. **`# TierTask Architecture and File Structure`** + update callout referencing `AGENTS.md` and `TDF_SPEC.md`.
2. **`## Architectural Layers`:** Table of layers (`Localization`, `Models`, `Services`, `Repositories`, `Providers`, `UI`) with paths and responsibilities, plus `P-UDF-ARCHITECTURE` / `P-IO-ISOLATION` note.
3. **`## Directory Layout`:** ASCII tree of the repository structure (`android/`, `assets/`, `linux/`, `windows/`, `lib/`, `test/`), auto-synced via `tiertask_dev.py arch --sync-tree`.
4. **Layer Sections (`## Root Files`, `## Localization`, `## Domain Models`, `## Services`, `## Repositories`, `## State Providers`, `## User Interface`):** 2-column tables (`File | Function`) where each row is a concise 1-sentence summary (`<= 65` words) listing only public classes/functions and core responsibilities. Never list private `_Widget` names, icon identifiers, or widget test keys in `ARCHITECTURE.md`.
5. **`## Execution & Synchronization Flow`:** Numbered end-to-end flow from app startup, active workspace loading, and locale/theme resolution to two-stage three-way `.tdf` synchronization (`In-Memory <-> Local File <-> WebDAV`), single-pass $O(N)$ `tdf 0.5.1` parsing/serialization, dynamic 6-tier evaluation, 30-day completed task and tombstone pruning, and opt-in diagnostic logging.

## 4. Style, Tone & Formatting Enforcement (`P-LANG-RULES`)
* **Language & Tone:** Write all documentation in concise, factual English following ASD-STE100 (80%). Never use emojis, marketing adjectives ("powerful", "seamless", "intuitive"), greetings, concluding summary paragraphs, or redundant explanations.
* **No Horizontal Rules:** Never use `---` section dividers in Markdown body content; rely strictly on `##`, `###`, and `####` headings.
* **Tables & Callouts:** Format tables cleanly with `:---` alignment markers and escape pipes (`\|`) inside cells. Use GitHub alerts (`> [!NOTE]`, `> [!IMPORTANT]`) instead of bold blockquotes.
* **Code & Backticks:** Wrap all file names, class names, commands, flags, tier names, and TDF directives/blocks in backticks. Ensure all shell snippets are directly copy-paste executable.
* **Generic Examples:** Use generic placeholders (`https://cloud.example.com`, `example-user`, `tasks.tdf`); never use real personal credentials or third-party brand names.
