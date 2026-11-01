---
name: update-documentation
description: >-
  Maintain and update README.md, ARCHITECTURE.md, and AGENTS.md for TierTask. Activate whenever editing documentation or when supported platforms, task tier rules, Markdown file schemas, local file or WebDAV synchronization, architecture layers, or system requirements change.
---

# Updating Documentation

## 1. Strict Separation of Concerns (Single Source of Truth)
* **`README.md` (Project Entry Point):** Keep under 130 lines. Do NOT copy detailed per-file class inventories or internal test matrices into `README.md`. Update `README.md` ONLY when top-level features, supported platforms (`Linux`, `Android`, `Windows`), tier definitions, Markdown format rules, system requirements, build/run steps, or repository document links change.
* **`ARCHITECTURE.md` (Architecture & File Structure):** Single Source of Truth for the architectural layers (`models`, `services`, `repositories`, `providers`, `ui`), directory tree, file responsibilities, and local file / WebDAV synchronization flow.
* **`AGENTS.md` (AI Engineering & TDD Rules):** Single Source of Truth for TDD workflow (`P-TDD-FIRST`), language rules (`P-LANG-RULES`), deterministic `.dart` file layout, static analysis rules, and mandatory `M-*` test categories.

## 2. `README.md` Structure (<130 Lines)
Omit a Table of Contents. Maintain this exact section order:
1. **`# TierTask`:** `> [!IMPORTANT]` private project disclaimer callout at the top, followed by a 1-sentence factual summary of `TierTask`, its supported platforms (`Linux`, `Android`, `Windows`), its 6 numbered tiers (`[1]`–`[6]`), and its single-file Markdown architecture (local file or any WebDAV server).
2. **`## Overview`:** Short intro + bullet list of core architectural traits (supported platforms: `Linux`, `Android`, `Windows` only; English default and German localization via external ARB files `lib/l10n/app_en.arb` and `lib/l10n/app_de.arb` with `System`, `English`, and `Deutsch` selection; 6 numbered priority/status tiers `[1]`–`[6]` where the parser ignores heading names and creates missing tiers automatically; deterministic auto-pull cascade with soft WIP limits; 30-day completed task pruning; anti-ping-pong downgrade; local Markdown file persistence via `dart:io` `File` and native `dart:io` `HttpClient` WebDAV synchronization across any WebDAV server; encrypted credentials via `flutter_secure_storage`).
3. **`## Requirements`:** 2-column table (`Component | Requirement`).
4. **`## Installation & Build`:** Copy-paste ready `git clone`, `flutter pub get`, `flutter gen-l10n`, and `flutter run` / obfuscated `flutter build --release --obfuscate --split-debug-info=build/symbols` commands for `linux`, `apk`, and `windows`.
5. **`## Quick Start`:** Self-contained numbered steps for selecting the display language, configuring either a local Markdown file (`tiertask.md`) or any WebDAV server endpoint, adding tasks, and synchronizing the board.
6. **`## Tier System & Markdown Format`:** Summary table of the 6 numbered tiers (`Tier | English Heading (en) | German Heading (de) | Soft Limit | Auto-Pull Behavior`), canonical `tiertask.md` example (`# [1] Focus` .. `# [6] Completed`), and links to `[ARCHITECTURE.md](ARCHITECTURE.md)` and `[CHANGELOG.md](CHANGELOG.md)`.
7. **`## Development`:** Self-contained `flutter gen-l10n`, `flutter test`, `flutter analyze --fatal-infos --fatal-warnings`, and `dart format --output=none --set-exit-if-changed lib test` commands.
8. **`## Disclaimer & License`:** 2-sentence warranty disclaimer and GPL-3.0 link to `[LICENSE](LICENSE)`.

## 3. `ARCHITECTURE.md` Structure
Maintain this exact section order:
1. **`# TierTask Architecture and File Structure`** + update callout referencing `AGENTS.md`.
2. **`## Architectural Layers`:** Table of layers (`Localization`, `Models`, `Services`, `Repositories`, `Providers`, `UI`) with paths and responsibilities, plus `P-IO-ISOLATION` note.
3. **`## Directory Layout`:** ASCII tree of the repository structure (`android/`, `linux/`, `windows/`, `lib/`, `test/`).
4. **Layer Sections (`## Root Files`, `## Localization`, `## Domain Models`, `## Services`, `## Repositories`, `## State Providers`, `## User Interface`):** 2-column tables (`File | Function`) describing each file concisely.
5. **`## Execution & Synchronization Flow`:** Numbered end-to-end flow from app startup, configuration loading, and `AppLanguage` locale resolution to local Markdown file read/write or WebDAV `GET`/`PUT`, numbered `[1]`–`[6]` Markdown parsing/serialization, auto-pull cascade, and 30-day pruning.

## 4. Style, Tone & Formatting Enforcement (`P-LANG-RULES`)
* **Language & Tone:** Write all documentation in concise, factual English following ASD-STE100 (80%). Never use emojis, marketing adjectives ("powerful", "seamless", "intuitive"), greetings, concluding summary paragraphs, or redundant explanations.
* **No Horizontal Rules:** Never use `---` section dividers in Markdown body content; rely strictly on `##`, `###`, and `####` headings.
* **Tables & Callouts:** Format tables cleanly with `:---` alignment markers and escape pipes (`\|`) inside cells. Use GitHub alerts (`> [!NOTE]`, `> [!IMPORTANT]`) instead of bold blockquotes.
* **Code & Backticks:** Wrap all file names, class names, commands, flags, tier headings, and configuration keys in backticks. Ensure all shell snippets are directly copy-paste executable.
* **Generic Examples:** Use generic placeholders (`https://cloud.example.com`, `example-user`, `tiertask.md`); never use real personal credentials or third-party brand names.
