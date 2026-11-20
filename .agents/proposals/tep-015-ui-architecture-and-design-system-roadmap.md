---
id: TEP-015
title: Decoupled Presentation Architecture, Dedicated UI Component Library, and Adaptive Desktop/Mobile Redesign Roadmap
status: concept
type: architecture
created: 2026-11-21
updated: 2026-11-21
---

# TEP-015: Decoupled Presentation Architecture, Dedicated UI Component Library, and Adaptive Desktop/Mobile Redesign Roadmap

## Part 1: Concept & Proposal

### 1.1 Summary
This umbrella proposal defines the target architecture, strict layer boundaries, extensible theme token contract, and four-phase execution roadmap to separate TierTask's user interface from domain, service, and repository code, introduce a standalone Flutter UI component package (`packages/tiertask_ui/`), and migrate the application onto an adaptive desktop and mobile design. Each of the four execution phases MUST be specified, audited, and tracked in its own dedicated child TEP created only when that phase begins.

### 1.2 Motivation
TierTask's core layers (`lib/models/`, `lib/services/`, `lib/repositories/`) are already independent of Flutter UI code, but `lib/ui/` currently violates strict UI separation in five concrete ways:
1. **Direct Repository Imports (9 UI files):** `settings_screen.dart` and `settings_local_storage_section.dart` import and instantiate `LocalFileRepository`; `local_tdf_file_dialogs.dart`, `workspace_dialog.dart`, and `workspace_row_card.dart` depend on static filename/path utilities on `LocalFileRepository`; `edit_task_screen.dart`, `edit_labels_screen.dart`, `label_hub_dialog.dart`, and `tier_task_subtasks_section.dart` import `LinkLauncherRepository`; `home_drawer.dart` imports `AppVersionRepository`.
2. **Domain and Service Logic Inside Stateful Widgets:** `home_screen.dart` (`1,167` lines) invokes `TaskBoard.evaluate(...)`, owns `HomeScreenBoundaryTimer`, and coordinates lifecycle/workspace side effects; `edit_locations_screen.dart` (`1,604` lines) directly calls `PlusCodeService` and manages geocoding resolution; `edit_task_screen.dart` (`1,728` lines) and `task_info_dialog.dart` (`1,767` lines) perform wall-clock UTC conversions, validation, and mutations directly in widget state; `home_drawer.dart` invokes `TdfService.serialize(...)`.
3. **Riverpod Coupling in Leaf Widgets:** Eleven widget files (including `tier_task_pill.dart`, `quick_add_bar.dart`, `home_drawer.dart`, `task_info_dialog.dart`, `label_hub_dialog.dart`, and `workspace_dialog.dart`) watch or read Riverpod providers directly instead of accepting immutable view data and callbacks.
4. **Mixed Theme Tokens and State:** `lib/ui/app_theme.dart` mixes visual token definitions with `appThemeProvider` (`lib/providers/config_providers.dart` and `lib/models/webdav_config.dart`).
5. **Layout and Visual Scaling Limits:** The current mobile-first horizontal `PageView` and scattered Material styling do not adapt cleanly between wide desktop viewports (Linux, Windows) and narrow mobile viewports (Android), and lack a reusable component abstraction layer.

### 1.3 Goals & Non-Goals
- **Goals:**
  - Establish a strict, tooling-enforced presentation boundary (`lib/presentation/`) so feature UI (`lib/ui/`) imports only `package:tiertask_ui/tiertask_ui.dart`, `lib/presentation/*`, `lib/l10n/app_localizations.dart`, and Flutter/`material_ui` packages.
  - Eliminate all `lib/repositories/` and `lib/services/` imports from `lib/ui/` before starting any visual redesign.
  - Create a compiler-isolated local Flutter package (`packages/tiertask_ui/`) organized into four abstraction layers (Tokens, Primitives, Adaptive Layouts, Domain-Agnostic Organisms) with a runnable `example/` widget gallery.
  - Replace legacy `Slate` and `Navy` themes with an extensible `UiThemePreset` architecture shipping with two WCAG-AA verified palettes in Light and Dark modes: `Calm` (default) and `Plum Umber` (purple and brown).
  - Iterate and complete full production UX parity in an offline modular HTML prototype (`.agents/prototypes/ui_v2/`) between Phase 1 and Phase 2 before authoring Flutter UI components.
  - Execute a clean parallel shell cutover in Phase 3 followed by full removal of legacy UI code (`P-NO-DEAD-CODE`) in Phase 4.
  - Govern every phase through a dedicated child TEP created just-in-time at phase kickoff.
- **Non-Goals:**
  - Any modification to `spec/TDF_SPEC_0.8.0.md` lexical grammar, block directives, 6-tier derivation rules, or three-way synchronization semantics.
  - Adding unsupported platforms (iOS, macOS, Web) or non-WebDAV storage backends.
  - Creating the four child TEPs upfront before preceding phases and prototype validation are complete.
  - Rewriting soon-to-be-deleted legacy Material screens in Phase 1 solely to strip `lib/models/` imports.

### 1.4 Description

#### Phased Governance Model (Mandatory Child TEPs)
This umbrella proposal sets non-negotiable architectural invariants and phase gates. Implementation work MUST NOT start directly under `TEP-015`. Instead, each phase requires its own dedicated child TEP (`TEP-016` onward, assigned sequentially from `BOARD.md` when that phase begins):

| Stage | Child TEP Required | Objective | Primary Exit Gate |
| :--- | :--- | :--- | :--- |
| **Phase 1: Presentation Decoupling** | Yes (dedicated child TEP) | Remove all `repositories/` and `services/` imports from legacy `lib/ui/`; extract domain evaluation, timers, geocoding/Plus Code flows, `.tdf` preview export, path validation, `AppLogger` (`LogTag.ui`), and immutable ViewModels/Controllers into the new `lib/presentation/` layer; update `tiertask_dev.py` DAG rules. | Zero `lib/repositories/` or `lib/services/` imports in `lib/ui/`; `lib/presentation/` unit-tested; all existing tests and `verify --full` green with zero visual regressions. |
| **Design Gate: HTML Prototype Completion** | No (tracked in `.agents/prototypes/ui_v2/`) | Expand the unwrapped offline prototype in `.agents/prototypes/ui_v2/` to full production feature parity (Search, Task Downgrade, Task Info, Label Hub, Workspaces, Settings, Location Status, Sync/Conflict/Recovery banners, Log Viewer, and mobile gesture decisions) across Desktop/Mobile and `Calm`/`Plum Umber` Light/Dark themes. | User sign-off on `.agents/prototypes/ui_v2/` covering all TierTask `0.8.0` workflows and both themes. |
| **Phase 2: Dedicated UI Library (`packages/tiertask_ui/`)** | Yes (dedicated child TEP) | Build the compiler-isolated local Flutter package (`tokens/`, `primitives/`, `layout/`, `components/` + `example/` gallery app) mirroring the signed-off prototype, with `tiertask_dev.py` multi-package verification and isolated widget tests across Desktop/Mobile viewports and Light/Dark themes. | `packages/tiertask_ui/` compiles with zero dependency on `tiertask` or `flutter_riverpod`; all widget tests and `example/` gallery pass; `tiertask_dev.py verify --full` covers the package. |
| **Phase 3: Adaptive UI Shell & Feature Cutover** | Yes (dedicated child TEP) | Build the new feature screens (`lib/ui_v2/` during development) as thin adapters connecting `lib/presentation/` ViewModels and `lib/l10n/app_localizations.dart` to `packages/tiertask_ui/`, achieving 100% feature and localization (`en`/`de`) parity across Linux, Android, and Windows; switch `lib/main.dart` to the new shell upon parity completion. | Strict ViewModel contract (zero `models/`, `services/`, `repositories/`, `providers/` imports) verified on all new UI files; full parity and `M-REAL-MECHANICS-TESTS` passing. |
| **Phase 4: Legacy Retirement & Architecture Finalization** | Yes (dedicated child TEP) | Delete all retired legacy screens, widgets, and tests (`P-NO-DEAD-CODE`), move new screens into `lib/ui/`, enforce the strict `lib/ui/` import whitelist globally in `tiertask_dev.py`, and synchronize `ARCHITECTURE.md`, `AGENTS.md`, `README.md`, and `CHANGELOG.md`. | Zero legacy UI files remain; global strict DAG gate green; `verify --full --fix` passes cleanly. |

#### Production Parity Inventory (Prototype Gate Scope)
The initial draft in `.agents/prototypes/tiertask_ui_prototype.html` defines the core adaptive shell (top chrome bar, persistent `220px` desktop sidebar / mobile slide-over drawer, mobile tier selector, bordered task cards with inline expansion, bottom quick-add composer, 3-tab full task editor, and label/location managers and editors). Before Phase 2 begins, `.agents/prototypes/ui_v2/` must incorporate all remaining production TierTask workflows:
- Inline/global task search across all six tiers
- Task downgrade (`>`) action and priority queue reordering
- Read-only `Task Info` view (including `due.anchor`, remaining countdowns, clickable links, read-only history) and `Label Hub` view (note copy, links, inherited conditions)
- Workspace switcher and management (`create`, `rename`, `delete`, `switch`)
- Settings view (language, theme mode, palette preset, timezone, due lead window, foreground location, diagnostic logging, local `.tdf` file actions, WebDAV configuration and wipe) and Diagnostic Log Viewer
- Foreground location status button and dialog
- Sync status, readability diagnostics (`StorageFileReadReport`), deletion conflict (`TDF-DEL-003`), recovery (`TDF-REC-002`), and raw `.tdf` preview views
- Mobile tier navigation review (keeping the drawer + compact tier selector baseline and evaluating optional horizontal swipe gestures)

### 1.5 Alternatives
- **Internal `lib/design_system/` module instead of `packages/tiertask_ui/`:** Rejected because linter-only enforcement is weaker than Dart package-level compiler isolation, and a separate package enables an independent `example/` gallery app and zero accidental Riverpod or domain imports.
- **Rewriting all legacy `lib/ui/` files to strip `lib/models/` imports in Phase 1:** Rejected because Phase 4 deletes legacy screens after parallel cutover; doing a double rewrite of ~10,000 lines of legacy UI code adds cost and regression risk without architectural payoff.
- **Pure `package:flutter/widgets.dart` UI library without `material_ui`:** Rejected because re-implementing platform text editing, IME, focus traversal, scrolling physics, overlays, date/time pickers, and accessibility semantics across Linux, Android, and Windows adds high maintenance risk. Building on `material_ui` primitives styled 100% via `UiThemeTokens` delivers custom visuals with reliable platform input behavior.
- **In-place incremental screen replacement without parallel cutover:** Rejected because it would produce a mixed legacy/new visual state across screens during development and complicate rollback.

## Part 2: Technical Design & Code Changes

### 2.1 Architecture & Affected Modules

#### Target Acyclic Layer Rank Order (`P-ACYCLIC-DAG`)
Phase 1 introduces `lib/presentation/` and Phase 2 adds the external local package `packages/tiertask_ui/`. Target rank order after Phase 4:

| Rank | Layer / Package | Allowed Internal Dependencies | Responsibility |
| :--- | :--- | :--- | :--- |
| External | `packages/tiertask_ui/` | Flutter SDK and `material_ui` only (zero `tiertask`, zero `flutter_riverpod`, zero `dart:io`) | Pure design tokens, theme presets, atomic primitives, adaptive shell/grid layouts, and domain-agnostic composite components. |
| `0` | `lib/services/app_logger.dart` | Dart SDK only | Structured opt-in diagnostic logging (`AppLogger`, `AppLogSink`). |
| `1` | `lib/models/*` | Rank `0`, `1` | Immutable domain aggregates, TDF 0.8.0 evaluator/mutator/sync/undo, settings codec, and pure filename/path validation helpers. |
| `2` | `lib/l10n/*` | Rank `1`, `2` | Generated `AppLocalizations` (`en`, `de`) and domain localization extensions. |
| `3` | `lib/services/*` | Rank `0`..`3` | Pure-Dart TDF scanner/parser/serializer, SHA-256, Base64, Plus Code decoding. |
| `4` | `lib/repositories/*` | Rank `0`..`4` | All external I/O (`dart:io`, `dart:ffi`, `HttpClient`, `MethodChannel`, `FlutterSecureStorage`). |
| `5` | `lib/providers/*` | Rank `0`..`5` | Core application state, workspace lifecycle, file watching, location polling, sync pipeline, and repository wiring. |
| `6` | `lib/presentation/*` | Rank `0`..`6` | Immutable presentation ViewModels, derived selectors (`evaluatedBoardProvider`), wall-clock boundary timer coordination, screen/form controllers (`TaskEditorController`, `LabelEditorController`, `LocationEditorController`, `SettingsController`), `AppLogger` (`LogTag.ui`) telemetry, and domain-derived localized strings (`lookupAppLocalizations`). |
| `7` | `lib/ui/*` | `packages/tiertask_ui/`, Rank `6` (`lib/presentation/*`), `lib/l10n/app_localizations.dart` ONLY | Thin stateless/consumer adapters mapping presentation ViewModels and static `AppLocalizations.of(context)` labels onto `packages/tiertask_ui/` widgets and forwarding typed user intents to controllers. |
| `8` | `lib/main.dart` | Rank `0`..`8`, `packages/tiertask_ui/` | Entry point, global error boundaries, `ProviderScope`, and root theme/shell wiring. |

#### Scoped Package Entrypoint Exception
`AGENTS.md` forbids barrel `export` shims in hand-written application `lib/` and `test/`. For `packages/tiertask_ui/` only, one idiomatic Dart package entrypoint (`packages/tiertask_ui/lib/tiertask_ui.dart`) exports the curated public API whose implementation resides in `packages/tiertask_ui/lib/src/{tokens,primitives,layout,components}/`. Nested internal barrels inside `lib/src/` and barrels inside application `lib/` remain forbidden.

#### Four-Layer Design System Abstraction (`packages/tiertask_ui/lib/src/`)
1. **`tokens/`:** `UiThemeTokens` (`ThemeExtension`), `UiColorTokens`, `UiTypographyTokens`, `UiSpacingTokens`, `UiRadiusTokens`, `UiBreakpoints` (`compact < 720`, `medium 720..820`, `expanded >= 820`), and extensible `UiThemePreset` definitions (`Calm` and `Plum Umber`, Light and Dark).
2. **`primitives/`:** `UiButton` (`primary`, `secondary`, `text`, `danger`, `icon`), `UiSurfaceCard`, `UiBadge`, `UiCountPill`, `UiColorDot`, `UiSelectChip`, `UiDayPillGroup`, `UiTextField`, `UiDropdownField`, `UiCheckboxRow`, `UiDisclosureSection`, `UiTabBar`, `UiInlineNotice`, `UiInlineConfirmation`.
3. **`layout/`:** `UiAdaptiveAppShell`, `UiSidebarNavSection`, `UiSidebarNavItem`, `UiPageHeader`, `UiResponsiveFormGrid`, `UiManagerListRow`.
4. **`components/`:** `UiTaskCard`, `UiQuickComposer`, `UiEditableRecordList`, `UiSearchableCheckList`, and future parity composites defined during the HTML prototype gate.

### 2.2 TDF Schema, Localization & State Changes
- **`spec/TDF_SPEC_0.8.0.md`:** Zero changes. All TDF `0.8.0` parsing, serialization, evaluation, mutation, locking, and sync contracts remain unchanged.
- **Settings & Palettes (`lib/models/webdav_config.dart`, `lib/models/settings_codec.dart`):**
  - Replace `AppThemePalette` values (`slate`, `navy`) with extensible theme preset keys (`calm` default, `plumUmber`) during Phase 3 (exact enum/serialization migration specified in the Phase 3 child TEP).
  - Preserve resilient `SettingsCodec` decoding: legacy `"slate"` and `"navy"` values in persisted `settings.json` decode cleanly to `calm` without triggering file quarantine or data loss.
- **Built-in Verified Theme Presets (WCAG AA >= 4.5:1 text contrast verified):**
  - **`Calm` (default):** Light (`bg #f0f4f7`, `panel #ffffff`, `ink #202c33`, `muted #53646f`, `line #d8e2e8`, `accent #00648b`, `soft #e0eff7`, `onAccent #ffffff`, `danger #a12a2a`); Dark (`bg #19262d`, `panel #243239`, `ink #edf2f5`, `muted #b5c4cc`, `line #3e505a`, `accent #9ac7e9`, `soft #1c4255`, `onAccent #132a36`, `danger #ffc0c0`).
  - **`Plum Umber` (purple and brown):** Light (`bg #f6f2ef`, `panel #fffdfb`, `ink #2c2220`, `muted #63534f`, `line #e2d7d2`, `accent #6b3fa0`, `soft #f0e7f8`, `onAccent #ffffff`, `danger #a12a2a`); Dark (`bg #1f1918`, `panel #2b2322`, `ink #f3ecea`, `muted #c3b4b0`, `line #473a38`, `accent #c5a3f5`, `soft #362945`, `onAccent #1e1429`, `danger #ffb8b8`).
- **Localization (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`):**
  - `lib/presentation/` controllers format all domain-derived strings (tier names/subtitles, countdowns, error diagnostics, undo notices) using `lookupAppLocalizations(appLocale)`.
  - `lib/ui/` uses `AppLocalizations.of(context)` exclusively for static view chrome and form labels, never importing `tier_localization_extension.dart` or `storage_file_read_localization_extension.dart`.
  - New ARB keys for `Calm`, `Plum Umber`, and new view headings/tabs will be specified in the Phase 3 child TEP.

### 2.3 Implementation Details
- **Unidirectional Data Flow (`P-UDF-ARCHITECTURE`) & Strict Isolation:**
  - `lib/ui/` widgets MUST NOT hold business logic, mutate `TaskBoard`, invoke `clockProvider`, open links directly, serialize `.tdf`, decode Plus Codes, or instantiate repositories.
  - All mutations, validation, async guards, and `AppLogger.event(..., tag: LogTag.ui)` diagnostics execute inside `lib/presentation/` controllers and `lib/providers/` notifiers.
- **Pragmatic Phase 1 Enforcement vs. Phase 4 Global Lock:**
  - In Phase 1, `tiertask_dev.py` immediately enforces zero `lib/repositories/` and zero `lib/services/` imports across all of `lib/ui/`, while allowing legacy `lib/ui/` files to retain `lib/models/` and `lib/providers/` imports temporarily until deleted in Phase 4.
  - In Phase 3, `tiertask_dev.py` enforces the full strict whitelist (`packages/tiertask_ui/`, `lib/presentation/`, `lib/l10n/app_localizations.dart` only) on all new UI files (`lib/ui_v2/`).
  - In Phase 4, once legacy UI files are deleted and `lib/ui_v2/` becomes `lib/ui/`, the full strict whitelist becomes mandatory globally across `lib/ui/`.
- **Tooling Integration (`.agents/scripts/tiertask_dev.py`):**
  - Phase 1 child TEP extends `_lib_layer_rank` and DAG checks for `lib/presentation/` and zero `repositories/`/`services/` in `lib/ui/`.
  - Phase 2 child TEP extends `format`, `analyze`, `test`, `arch`, and license/lint checks to cover `packages/tiertask_ui/` and its `test/` and `example/` targets.
- **Prototype Repository Layout:**
  - `.agents/prototypes/tiertask_ui_prototype.html` retains the original exported reference draft.
  - `.agents/prototypes/ui_v2/` (`index.html`, `tokens.css`, `components.css`, `app.js`) serves as the active, offline, unescaped blueprint mirroring `packages/tiertask_ui/` layers and themes (`Calm` and `Plum Umber`, Light and Dark, Desktop and Mobile).

### 2.4 Testing Strategy
Each child TEP MUST define Red-Green-Refactor TDD test cases (`P-TDD-FIRST`) tailored to its scope:
- **Phase 1 Child TEP:** Unit tests under `test/presentation/` verifying ViewModel projection, boundary timer scheduling, Plus Code/geocoding controller flows, form draft validation, `AppLogger` telemetry emission, and static DAG/import tests proving zero `repositories/` or `services/` imports in `lib/ui/`.
- **Phase 2 Child TEP:** Isolated widget tests under `packages/tiertask_ui/test/` verifying every token preset (`Calm`, `Plum Umber`, Light/Dark), primitive interaction, focus/keyboard accessibility, breakpoint transitions (`390px`, `760px`, `1280px`), and composite component callbacks with zero Riverpod or domain setup.
- **Phase 3 Child TEP:** Widget and integration tests covering full feature parity, `en`/`de` localization, and `M-REAL-MECHANICS-TESTS` (mid-flight async saves via `Completer`, workspace switches across `await` boundaries, live undo and conflict/recovery banners, external local file watch updates).
- **Phase 4 Child TEP:** Full regression verification (`python3 .agents/scripts/tiertask_dev.py verify --full --fix`), orphan-code checks (`P-NO-DEAD-CODE`), and `SettingsCodec` legacy palette decode tests (`slate`/`navy` -> `calm`).

## Part 3: Implementation Record & Tasks

### 3.1 Task Breakdown
- [ ] Review and finalize `TEP-015` (optionally via `/verify-spec .agents/proposals/tep-015-ui-architecture-and-design-system-roadmap.md`) and advance status from `concept` to `planned`.
- [ ] Author and complete **Phase 1 Child TEP** (Presentation Layer Decoupling & Strict `repositories/`/`services/` Boundary).
- [ ] Complete **Design Gate** in `.agents/prototypes/ui_v2/` covering all production TierTask `0.8.0` parity views and mobile/desktop interactions.
- [ ] Author and complete **Phase 2 Child TEP** (`packages/tiertask_ui/` Component Library, Themes, Gallery App, and Tooling Integration).
- [ ] Author and complete **Phase 3 Child TEP** (Adaptive Shell & Feature Screens Cutover under Strict ViewModel Contract).
- [ ] Author and complete **Phase 4 Child TEP** (Legacy UI Retirement, Global Strict DAG Lock, and Documentation Synchronization).
- [ ] After all four child TEPs reach `completed`, set `TEP-015` to `review`, update `BOARD.md`, and request final approval.

### 3.2 Work Log & Decisions
- **2026-11-21:** Completed interactive architecture interview (`/grill-me`) and drafted umbrella `TEP-015`. Locked in: standalone `packages/tiertask_ui/` package with `example/` gallery, dedicated `lib/presentation/` DAG layer, strict ViewModel contract for new `lib/ui/`, pragmatic Phase 1 transition avoiding throwaway legacy rewrites, `Calm` (default) + `Plum Umber` extensible themes with verified WCAG AA contrast, modular offline prototype under `.agents/prototypes/ui_v2/`, and mandatory per-phase child TEPs created just-in-time.

### 3.3 Delivered Artifacts
*(Complete upon approval)*
