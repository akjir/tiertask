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
1. **Direct Repository Imports (10 UI files):** `settings_screen.dart` and `settings_local_storage_section.dart` import and instantiate `LocalFileRepository`; `local_tdf_file_dialogs.dart`, `workspace_dialog.dart`, and `workspace_row_card.dart` (as well as `settings_screen.dart`) depend on static filename/path utilities on `LocalFileRepository`; `edit_task_screen.dart`, `edit_labels_screen.dart`, `label_hub_dialog.dart`, and `tier_task_subtasks_section.dart` import `LinkLauncherRepository`; `home_drawer.dart` imports `AppVersionRepository`.
2. **Domain and Service Logic Inside Stateful Widgets (12 UI files importing `lib/services/`):** `home_screen.dart` (`1,167` lines) invokes `board.evaluateForContext(...)`, owns `HomeScreenBoundaryTimer`, and coordinates lifecycle/workspace side effects; `edit_locations_screen.dart` (`1,604` lines) directly imports `PlusCodeService` and manages geocoding resolution; `edit_task_screen.dart` (`1,728` lines) and `task_info_dialog.dart` (`1,767` lines) perform wall-clock UTC conversions, validation, and mutations directly in widget state; `home_drawer.dart` invokes `ref.read(tdfServiceProvider).serialize(board)`; and 12 files in `lib/ui/` directly import `lib/services/app_logger.dart` (including `LogLevel`/`LogTag` types in `log_viewer_dialog.dart` and `settings_preference_cards.dart`).
3. **Riverpod Coupling in Leaf Widgets:** Nine widget files under `lib/ui/widgets/` (`home_drawer.dart`, `label_hub_dialog.dart`, `location_status_dialog.dart`, `log_viewer_dialog.dart`, `quick_add_bar.dart`, `settings_local_storage_section.dart`, `task_info_dialog.dart`, `tier_task_pill.dart`, and `workspace_dialog.dart`; 15 files across all of `lib/ui/` including screens and `app_theme.dart`) watch or read Riverpod providers directly instead of accepting immutable view data and callbacks.
4. **Mixed Theme Tokens and State:** `lib/ui/app_theme.dart` mixes visual token definitions with `appThemeProvider` (`lib/providers/config_providers.dart` and `lib/models/webdav_config.dart`).
5. **Layout and Visual Scaling Limits:** The current mobile-first horizontal `PageView` and scattered Material styling do not adapt cleanly between wide desktop viewports (Linux, Windows) and narrow mobile viewports (Android), and lack a reusable component abstraction layer.

### 1.3 Goals & Non-Goals
- **Goals:**
  - Establish a strict, tooling-enforced presentation boundary (`lib/presentation/`) so feature UI (`lib/ui/`) imports only `package:tiertask_ui/tiertask_ui.dart`, `lib/presentation/*`, acyclic intra-layer `lib/ui/*`, `lib/l10n/app_localizations.dart`, `package:flutter_riverpod/flutter_riverpod.dart`, Flutter/`material_ui` packages, and non-I/O Dart SDK utilities (such as `dart:async` for `unawaited`).
  - Eliminate all `lib/repositories/` and `lib/services/` imports from `lib/ui/` before starting any visual redesign.
  - Create a compiler-isolated local Flutter package (`packages/tiertask_ui/`) organized into four abstraction layers (Tokens, Primitives, Adaptive Layouts, Domain-Agnostic Composites) with a runnable `example/` widget gallery, maximizing widget reuse while keeping the total widget catalog as small as possible.
  - Replace legacy `Slate` and `Navy` themes with an extensible `UiThemePreset` architecture shipping with two WCAG-AA verified palettes in Light and Dark modes: `Calm` (default) and `Plum Umber` (purple and brown).
  - Iterate and complete full production UX parity in an offline modular HTML prototype (`.agents/prototypes/ui_v2/`) between Phase 1 and Phase 2, then match the `ui_v2` prototype's visual appearance and interaction model as closely as possible in the initial Flutter implementation (later post-cutover iterations in the real app may refine or diverge from the HTML prototype).
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
| **Phase 1: Presentation Decoupling** | Yes (dedicated child TEP) | Remove all `repositories/` and `services/` imports from legacy `lib/ui/`; move pure filename/path validation helpers into `lib/models/`; extract domain evaluation, timers, geocoding/Plus Code flows, `.tdf` preview export, `AppLogger` (`LogTag.ui`) telemetry and diagnostic log view types, and immutable ViewModels/Controllers into the new `lib/presentation/` layer; update `tiertask_dev.py` DAG rules. | Zero `lib/repositories/` or `lib/services/` imports in `lib/ui/`; `lib/presentation/` unit-tested; all existing tests and `verify --full` green with zero visual regressions. |
| **Design Gate: HTML Prototype Completion** | No (tracked in `.agents/prototypes/ui_v2/`) | Expand the unwrapped offline prototype in `.agents/prototypes/ui_v2/` to full production feature parity (Search, Task Downgrade, Task Info, Label Hub, Workspaces, Settings, Location Status, Sync/Conflict/Recovery banners, Log Viewer, and mobile gesture decisions) across Desktop/Mobile and `Calm`/`Plum Umber` Light/Dark themes. | User sign-off on `.agents/prototypes/ui_v2/` covering all TierTask `0.8.0` workflows and both themes. |
| **Phase 2: Dedicated UI Library (`packages/tiertask_ui/`)** | Yes (dedicated child TEP) | Build the compiler-isolated local Flutter package (`tokens/`, `primitives/`, `layout/`, `components/` + `example/` gallery app) mirroring the signed-off prototype, with `tiertask_dev.py` multi-package verification and isolated widget tests across Desktop/Mobile viewports and Light/Dark themes. | `packages/tiertask_ui/` compiles with zero dependency on `tiertask` or `flutter_riverpod`; all widget tests and `example/` gallery pass; `tiertask_dev.py verify --full` covers the package. |
| **Phase 3: Adaptive UI Shell & Feature Cutover** | Yes (dedicated child TEP) | Build the new feature screens (`lib/ui_v2/` during development) as thin adapters connecting `lib/presentation/` ViewModels and `lib/l10n/app_localizations.dart` to `packages/tiertask_ui/`, achieving 100% feature and localization (`en`/`de`) parity across Linux, Android, and Windows; switch `lib/main.dart` to the new shell upon parity completion. | Strict ViewModel contract (zero `models/`, `services/`, `repositories/`, `providers/` imports) verified on all new UI files; full parity and `M-REAL-MECHANICS-TESTS` passing. |
| **Phase 4: Legacy Retirement & Architecture Finalization** | Yes (dedicated child TEP) | Delete all retired legacy screens, widgets, and tests (`P-NO-DEAD-CODE`), move new screens into `lib/ui/`, enforce the strict `lib/ui/` import whitelist globally in `tiertask_dev.py`, and synchronize `ARCHITECTURE.md`, `AGENTS.md`, `README.md`, and `CHANGELOG.md`. | Zero legacy UI files remain; global strict DAG gate green; `verify --full --fix` passes cleanly. |

#### Production Parity Inventory (Prototype Gate Scope)
The initial draft in `.agents/prototypes/tiertask_ui_prototype.html` established the baseline adaptive shell (top chrome bar, persistent `220px` desktop sidebar / mobile slide-over drawer, mobile tier selector, and bordered task cards). The finalized modular blueprint in `.agents/prototypes/ui_v2/` replaces the legacy 3-tab Task Editor, separate Label/Location editors, `TaskInfoDialog`, and `LabelHubDialog` with **Unified Expandable Entity Cards** featuring inline section editing, and covers full production TierTask `0.8.0` parity:
- Inline/global task search across all six tiers, preserving active label context with an explicit active-label filter bar (`Clear filter`) and restoring Search/Tier context when navigating back from linked labels or locations
- Task downgrade (`>`), Priority/Queue/Someday placement switching (deterministic ordering without manual drag-and-drop queue reordering), automatic priority escalation badge (`due.auto`), bounded secondary badge overflow (`+N more`), and full Undo recovery across `complete`, `downgrade`, and `delete` actions via a floating bottom notice overlay (with dismiss, auto-hide, and desktop `Ctrl+Z` shortcut)
- Unified expandable entity cards for Tasks, Labels, and Locations with inline section editing (plus read-only completed task panels keeping Restore, Copy, Links, live History journal, and Delete): live checklists with auto-finish, `due.anchor`, remaining countdowns, scheduling notes, clickable links, searchable Label Picker (desktop popover and mobile bottom sheet with scope filters and inline creation), interactive task history journal (`N / 200`, optional timestamp override on add and inline edit, duplicate protection, canonical sorting per `TEP-012`), custom HSV color wheel picker alongside presets, repeatable ordered reference links, inherited/custom weekday/time/location conditions, and forward-geocoding multi-candidate disambiguation
- Uncommitted inline entity draft cards (`Open as draft`) for creating detailed Tasks, Labels, and Locations without committing premature records on cancel
- Docked bottom Quick-Add composer (Tasks) and docked view action footers (Settings Save/Test Sync with dirty indicator, Conflict/Recovery Apply) outside the main scroll viewport so floating notices sit cleanly above the dock without layout jitter
- Workspace switcher and management (`create`, `rename`, `delete`, `switch`)
- Settings view distinguishing immediately persisted preferences (`Auto-saved` badge) from explicit WebDAV credentials save/test validation (`Unsaved changes` badge, inline validation for HTTP(S) scheme, userinfo, path traversal, and credentials, and compact-viewport desktop-only Move guard) and Diagnostic Log Viewer
- Foreground location status button and dialog
- Initial loading state, sync status, startup settings recovery notice (`recoveredFromBackup`, `resetAfterQuarantine`), readability diagnostics (`StorageFileReadReport`), deletion conflict (`TDF-DEL-003`) and recovery (`TDF-REC-002`) resolution across tasks, labels, and locations, and raw `.tdf` preview including the `maxTdfFileBytes` limit-exceeded state
- Application branding and build chrome (palette-themed `AppLogo`, inline `DEV` build pill in the chrome bar via `AppBuildProfile.isDev`, and SemVer build footer in the sidebar via `AppVersionRepository`)
- Keyboard accessibility and desktop shortcuts: thin `1px` single-ring `:focus-visible` outlines (`--focus-ring-width`, `--focus-ring-offset`), modal/sheet `Tab` focus trapping with focus restoration on close, `Enter` form/modal confirmation, `Escape` dismissal, `/` and `Ctrl/Cmd+F` search focus, `n` quick-add focus, `Ctrl/Cmd+Z` undo, and `ArrowLeft`/`ArrowRight` tier switching
- Mobile tier navigation (drawer + compact tier selector baseline, docked collapsible quick-add bar, mobile label picker bottom sheet, and evaluation of optional horizontal swipe gestures)

### 1.5 Alternatives
- **Internal `lib/design_system/` module instead of `packages/tiertask_ui/`:** Rejected because linter-only enforcement is weaker than Dart package-level compiler isolation, and a separate package enables an independent `example/` gallery app and zero accidental Riverpod or domain imports.
- **Rewriting all legacy `lib/ui/` files to strip `lib/models/` imports in Phase 1:** Rejected because Phase 4 deletes legacy screens after parallel cutover; doing a double rewrite of ~24,000 lines of legacy UI code (`24,271` total lines across 35 files) adds cost and regression risk without architectural payoff.
- **Pure `package:flutter/widgets.dart` UI library without `material_ui`:** Rejected because re-implementing platform text editing, IME, focus traversal, scrolling physics, overlays, date/time pickers, and accessibility semantics across Linux, Android, and Windows adds high maintenance risk. Building on `material_ui` primitives styled 100% via `UiThemeTokens` delivers custom visuals with reliable platform input behavior.
- **In-place incremental screen replacement without parallel cutover:** Rejected because it would produce a mixed legacy/new visual state across screens during development and complicate rollback.

## Part 2: Technical Design & Code Changes

### 2.1 Architecture & Affected Modules

#### Target Acyclic Layer Rank Order (`P-ACYCLIC-DAG`)
Phase 1 introduces `lib/presentation/` and Phase 2 adds the external local package `packages/tiertask_ui/`. All layers outside `lib/repositories/` (`packages/tiertask_ui/`, `lib/models/*`, `lib/l10n/*`, `lib/services/*`, `lib/providers/*`, `lib/presentation/*`, `lib/ui/*`, `lib/ui_v2/*`) uphold `P-IO-ISOLATION` (zero `dart:io`, zero `dart:ffi`, zero `HttpClient`). Target rank order after Phase 4:

| Rank | Layer / Package | Allowed Dependencies | Responsibility |
| :--- | :--- | :--- | :--- |
| External | `packages/tiertask_ui/` | Flutter SDK and `material_ui` only (zero `tiertask`, zero `flutter_riverpod`, zero `dart:io`, zero `dart:ffi`) | Pure design tokens, theme presets, atomic primitives, adaptive shell/grid layouts, and domain-agnostic composite components. |
| `0` | `lib/services/app_logger.dart` | Zero internal `lib/` imports (Dart SDK and Flutter `foundation`/`AppLifecycleState` only; zero `dart:io`, zero `dart:ffi`) | Structured opt-in diagnostic logging (`AppLogger`, `AppLogSink`). |
| `1` | `lib/models/*` | Rank `0`, `1` | Immutable domain aggregates, TDF 0.8.0 evaluator/mutator/sync/undo, settings codec, and pure filename/path validation helpers. |
| `2` | `lib/l10n/*` | Rank `1`, `2` | Generated `AppLocalizations` (`en`, `de`) and domain localization extensions. |
| `3` | `lib/services/*` | Rank `0`..`3` | Pure-Dart TDF scanner/parser/serializer, SHA-256, Base64, Plus Code decoding. |
| `4` | `lib/repositories/*` | Rank `0`..`4` | All external I/O (`dart:io`, `dart:ffi`, `HttpClient`, `MethodChannel`, `FlutterSecureStorage`). |
| `5` | `lib/providers/*` | Rank `0`..`5` | Core application state, workspace lifecycle, file watching, location polling, sync pipeline, and repository wiring. |
| `6` | `lib/presentation/*` | Rank `0`..`6` (zero `dart:io`, zero `dart:ffi`, zero `HttpClient`) | Immutable presentation ViewModels, derived selectors (`evaluatedBoardProvider`), wall-clock boundary timer coordination, screen/form/diagnostic-log controllers (`TaskEditorController`, `LabelEditorController`, `LocationEditorController`, `SettingsController`, `LogViewerController`), `AppLogger` (`LogTag.ui`) telemetry, and domain-derived localized strings (`lookupAppLocalizations`). |
| `7` | `lib/ui/*` (and `lib/ui_v2/*` in Phase 3) | `packages/tiertask_ui/`, Rank `6` (`lib/presentation/*`), acyclic intra-layer Rank `7` (`lib/ui/*` after Phase 4; `lib/ui_v2/*` only during Phase 3, never `lib/ui_v2/*` -> legacy `lib/ui/*`), `lib/l10n/app_localizations.dart`, `flutter_riverpod`, Flutter/`material_ui`, and non-I/O Dart SDK utilities (`dart:async`, `dart:ui`) ONLY | Thin stateless/consumer adapters mapping presentation ViewModels and static `AppLocalizations.of(context)` labels onto `packages/tiertask_ui/` widgets and forwarding typed user intents to controllers. |
| `8` | `lib/main.dart` | Rank `0`..`7`, `packages/tiertask_ui/` | Entry point, global error boundaries, `ProviderScope`, and root theme/shell wiring. |

#### Scoped Package Entrypoint Exception
`AGENTS.md` forbids barrel `export` shims in hand-written application `lib/` and `test/`. For `packages/tiertask_ui/` only, one idiomatic Dart package entrypoint (`packages/tiertask_ui/lib/tiertask_ui.dart`) exports the curated public API whose implementation resides in `packages/tiertask_ui/lib/src/{tokens,primitives,layout,components}/`. Nested internal barrels inside `lib/src/` and barrels inside application `lib/` remain forbidden.

#### Four-Layer Design System Abstraction (`packages/tiertask_ui/lib/src/`)
Follow a strict **maximum-reuse, minimum-widget-count** design rule: introduce a new widget only when an existing primitive or layout cannot express the pattern cleanly through composition or semantic variants, while matching `.agents/prototypes/ui_v2/` as closely as possible for initial cutover.
1. **`tokens/`:** `UiThemeTokens` (`ThemeExtension`), `UiColorTokens` (including palette-themed `AppLogo` colors), `UiTypographyTokens`, `UiSpacingTokens`, `UiRadiusTokens`, `UiFocusTokens` (`1px` focus ring width and offset), `UiBreakpoints` (non-overlapping partition matching `.agents/prototypes/ui_v2/tokens.css` and `components.css`: `compact <= 720`, `medium > 720 && <= 820`, `expanded > 820`), and extensible `UiThemePreset` definitions (`Calm` and `Plum Umber`, Light and Dark).
2. **`primitives/` (8 core primitives):**
   - `UiAppLogo` (palette-themed TierTask logo mark)
   - `UiButton` (`primary`, `secondary`, `text`, `danger`, `icon`, optional compact density)
   - `UiPill` (unified badge, count pill, `DEV` build pill, color-dotted label chip, removable/selectable chip, and weekday pill via semantic tone and interactivity slots)
   - `UiSegmentedControl` (placement modes, scope switch, settings preferences, conflict/recovery choices)
   - `UiCard` (unified bordered surface covering static info/settings section cards with header slots, expandable entity cards for tasks/labels/locations, and uncommitted draft/inline-edit containers)
   - `UiField` (unified labeled text, multiline, password, select, and date/time field wrapper with `1px` focus styling, helper hint, and inline validation error)
   - `UiToggleRow` (checkbox or switch row with label and description)
   - `UiBanner` (unified status banner, floating bottom toast/Undo overlay, inline confirmation bar, and empty/loading state surface)
3. **`layout/` (4 adaptive layout primitives):**
   - `UiAdaptiveAppShell` (top chrome bar, persistent desktop sidebar / mobile drawer, scrollable body, floating overlay slot, and docked bottom action/composer slot)
   - `UiSidebarSection` (collapsible, optionally filterable navigation group and nav item rows)
   - `UiPageHeader` (optional back button, heading/subtitle, trailing actions, and optional active-filter bar)
   - `UiResponsiveGrid` (adaptive 2-column desktop / 1-column compact form and settings grid)
4. **`components/` (5 reusable domain-agnostic composites):**
   - `UiDialogFrame` (focus-trapped modal dialog and mobile bottom-sheet container reused across all dialogs and sheets)
   - `UiQuickComposer` (docked quick-add / quick-create bar with compact mobile collapsed toggle)
   - `UiSearchablePicker` (searchable list with optional scope filter, keyboard navigation, and inline create; reused for Label Picker popover/sheet, Prerequisite Picker, and Local File Picker)
   - `UiOrderedItemList` (repeatable item rows with add bar, inline edit, reorder up/down, and delete; reused for Subtasks, Reference Links, Time Windows, and History Journal)
   - `UiColorWheel` (custom-painted HSV color wheel, brightness slider, and preset swatch selector)

### 2.2 TDF Schema, Localization & State Changes
- **`spec/TDF_SPEC_0.8.0.md`:** Zero changes. All TDF `0.8.0` parsing, serialization, evaluation, mutation, locking, and sync contracts remain unchanged.
- **Settings & Palettes (`lib/models/webdav_config.dart`, `lib/models/settings_codec.dart`, `lib/models/legacy_ttw_v2_converter.dart`):**
  - Replace `AppThemePalette` values (`slate`, `navy`) with extensible theme preset keys (`calm` default, `plumUmber`) during Phase 3 (exact enum/serialization migration specified in the Phase 3 child TEP).
  - Preserve resilient `SettingsCodec` and `LegacyTtwV2Converter` decoding: `AppThemePalette.tryParseJson` explicitly maps legacy `"slate"` and `"navy"` JSON tokens to `calm` without emitting spurious `SettingsDecodeWarning` entries, file quarantine, or data loss, and `LegacyTtwV2Converter` (if still retained in Phase 3) maps legacy `TTW\x02` palette IDs `0` and `1` to `calm`.
  - Maintain compilation and green `verify --full` across the Phase 3 parallel cutover: any retained legacy `lib/ui/` references to `AppThemePalette` (`lib/ui/app_theme.dart`, `lib/ui/widgets/settings_preference_cards.dart`) MUST either be minimally adapted to the migrated enum or retired at cutover so legacy tests compile until Phase 4 removes them.
- **Built-in Verified Theme Presets (WCAG AA >= 4.5:1 text contrast verified):**
  - **`Calm` (default):** Light (`bg #f0f4f7`, `panel #ffffff`, `ink #202c33`, `muted #53646f`, `line #d8e2e8`, `accent #00648b`, `soft #e0eff7`, `onAccent #ffffff`, `danger #a12a2a`); Dark (`bg #19262d`, `panel #243239`, `ink #edf2f5`, `muted #b5c4cc`, `line #3e505a`, `accent #9ac7e9`, `soft #1c4255`, `onAccent #132a36`, `danger #ffc0c0`).
  - **`Plum Umber` (purple and brown):** Light (`bg #f6f2ef`, `panel #fffdfb`, `ink #2c2220`, `muted #63534f`, `line #e2d7d2`, `accent #6b3fa0`, `soft #f0e7f8`, `onAccent #ffffff`, `danger #a12a2a`); Dark (`bg #1f1918`, `panel #2b2322`, `ink #f3ecea`, `muted #c3b4b0`, `line #473a38`, `accent #c5a3f5`, `soft #362945`, `onAccent #1e1429`, `danger #ffb8b8`).
- **Localization (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`):**
  - `lib/presentation/` controllers format all domain-derived strings (tier names/subtitles, countdowns, error diagnostics, undo notices) using `lookupAppLocalizations(appLocale)`.
  - `lib/ui/` uses `AppLocalizations.of(context)` exclusively for static view chrome and form labels, never importing `tier_localization_extension.dart` or `storage_file_read_localization_extension.dart`.
  - New ARB keys for `Calm`, `Plum Umber`, and new view headings/tabs will be specified in the Phase 3 child TEP; retired legacy ARB keys (such as `themePaletteSlate` and `themePaletteNavy`) are removed in Phase 4 (`P-NO-DEAD-CODE`).

### 2.3 Implementation Details
- **Unidirectional Data Flow (`P-UDF-ARCHITECTURE`) & Strict Isolation:**
  - `lib/ui/` widgets MUST NOT hold business logic, mutate `TaskBoard`, invoke `clockProvider`, open links directly, serialize `.tdf`, decode Plus Codes, or instantiate repositories.
  - All mutations, validation, async guards, diagnostic log projection, and `AppLogger.event(..., tag: LogTag.ui)` telemetry execute inside `lib/presentation/` controllers and `lib/providers/` notifiers.
- **Widget Minimalism, Reuse & Prototype Fidelity Policy:**
  - Favor the smallest viable set of highly reusable widgets in `packages/tiertask_ui/` and compose feature views in `lib/ui_v2/` (`lib/ui/`) from those shared building blocks instead of duplicating bespoke one-off widgets across Tasks, Labels, Locations, Settings, Conflicts, and Modals.
  - Initial Flutter implementation (Phases 2 and 3) MUST match the visual design, layout proportions, token values, and interaction flows of `.agents/prototypes/ui_v2/` as closely as possible.
  - Once cutover parity is reached, future iterations of the real Flutter app MAY refine, extend, or diverge from `.agents/prototypes/ui_v2/` without requiring backports to the HTML prototype.
- **Pragmatic Phase 1 Enforcement, Phase 3 Cutover Window, & Phase 4 Global Lock:**
  - In Phase 1, `tiertask_dev.py` immediately enforces zero `lib/repositories/` and zero `lib/services/` imports across all of `lib/ui/` (exposing presentation-layer diagnostic log view types so `log_viewer_dialog.dart` and `settings_preference_cards.dart` drop `lib/services/app_logger.dart`), while allowing legacy `lib/ui/` files to retain `lib/models/` and `lib/providers/` imports temporarily until deleted in Phase 4.
  - In Phase 3, `tiertask_dev.py` enforces the full strict Rank `7` UI whitelist (`packages/tiertask_ui/`, `lib/presentation/`, acyclic `lib/ui_v2/`, `lib/l10n/app_localizations.dart`, `flutter_riverpod`, Flutter/`material_ui`, and non-I/O Dart SDK utilities; forbidding `lib/ui_v2/*` -> legacy `lib/ui/*`) on all new UI files (`lib/ui_v2/`). Between the Phase 3 `lib/main.dart` switchover and Phase 4 retirement, legacy `lib/ui/` files are explicitly retained under a bounded cutover-window exception to `P-NO-DEAD-CODE` for safe rollback.
  - In Phase 4, once legacy UI files are deleted and `lib/ui_v2/` becomes `lib/ui/`, the full strict whitelist becomes mandatory globally across `lib/ui/` with zero dead-code exceptions remaining.
- **Tooling Integration (`.agents/scripts/tiertask_dev.py`):**
  - **Phase 1 child TEP:** Extend `_lib_layer_rank` (inserting Rank `6` `lib/presentation/`, shifting `lib/ui/` to Rank `7` and `lib/main.dart` to Rank `8`), update `_layer_section_for_path` (`## Presentation`), add `--layer presentation` to `find`, extend `P-IO-ISOLATION` (`dart:io`, `dart:ffi`, `HttpClient`) to `lib/presentation/`, and enforce zero `lib/repositories/` or `lib/services/` imports in `lib/ui/`.
  - **Phase 2 child TEP:** Extend `format`, `analyze`, `test`, `arch`, `compute_code_digest` (so cached verification stamps invalidate on UI package edits), and license/lint checks to cover `packages/tiertask_ui/` and its `test/` and `example/` targets, carving out ONLY `packages/tiertask_ui/lib/tiertask_ui.dart` from the forbidden `export` directive check (`P-FILE-SIZE`).
  - **Phase 3 child TEP:** Assign `lib/ui_v2/*` to Rank `7`, enforce `P-IO-ISOLATION` (`dart:io`, `dart:ffi`) and the full strict UI whitelist on `lib/ui_v2/*`, and forbid `lib/ui_v2/*` -> legacy `lib/ui/*` imports.
  - **Phase 4 child TEP:** Remove temporary `lib/ui_v2/` branch rules after moving screens into `lib/ui/` and lock the strict UI import whitelist globally on `lib/ui/*`.
- **Prototype Repository Layout:**
  - `.agents/prototypes/tiertask_ui_prototype.html` retains the original exported reference draft.
  - `.agents/prototypes/ui_v2/` (`index.html`, `tokens.css`, `components.css`, `icons.js`, `i18n.js`, `tdf_engine.js`, `views_core.js`, `views_secondary.js`, `app.js`) serves as the active, offline, unescaped blueprint mirroring `packages/tiertask_ui/` layers and themes (`Calm` and `Plum Umber`, Light and Dark, Desktop and Mobile).

### 2.4 Testing Strategy
Each child TEP MUST define Red-Green-Refactor TDD test cases (`P-TDD-FIRST`) covering all applicable mandatory categories (`AGENTS.md` Section 5):
- **Phase 1 Child TEP:** Unit tests under `test/presentation/` and `test/models/` verifying ViewModel projection, boundary timer scheduling, Plus Code/geocoding controller flows, form draft validation (`M-EXTREME-BOUND-TESTS` for `maxTdf*` limits), moved pure filename/path validation helpers (`M-URI-PATH-EDGE-TESTS`, `M-DELIM-INJECT-TESTS`), presentation state enums (`M-EXHAUSTIVE-STATE-TESTS`), `AppLogger` telemetry emission, and static DAG/import checks proving zero `repositories/` or `services/` imports in `lib/ui/`.
- **Phase 2 Child TEP:** Isolated widget tests under `packages/tiertask_ui/test/` verifying every token preset (`Calm`, `Plum Umber`, Light/Dark) and primitive variant (`M-EXHAUSTIVE-STATE-TESTS`), primitive interaction, focus/keyboard accessibility, breakpoint boundary transitions (`390px`, `720px`, `721px`, `760px`, `820px`, `821px`, `1280px`; `M-EXTREME-BOUND-TESTS`), and composite component callbacks with zero Riverpod or domain setup.
- **Phase 3 Child TEP:** Model, widget, and integration tests covering `AppThemePalette` / `SettingsCodec` / `LegacyTtwV2Converter` migration (`"slate"`, `"navy"`, `TTW\x02` IDs `0`/`1`, and unknown fallback -> `calm` with zero spurious decode warnings for legacy values; `M-EXHAUSTIVE-STATE-TESTS`), full feature parity across Linux/Android/Windows, `en`/`de` localization, and `M-REAL-MECHANICS-TESTS` (mid-flight async saves via `Completer`, workspace switches across `await` boundaries, live undo and conflict/recovery banners, external local file watch updates).
- **Phase 4 Child TEP:** Full regression verification (`python3 .agents/scripts/tiertask_dev.py verify --full --fix`), global strict `lib/ui/` import-whitelist verification, and orphan-code/legacy-ARB checks (`P-NO-DEAD-CODE`).

## Part 3: Implementation Record & Tasks

### 3.1 Task Breakdown
- [ ] Review and finalize `TEP-015` (optionally via `/verify-spec .agents/proposals/tep-015-ui-architecture-and-design-system-roadmap.md`) and advance status from `concept` to `planned`.
- [x] Author and complete **Phase 1 Child TEP** ([`TEP-016`](tep-016-presentation-layer-decoupling.md): Presentation Layer Decoupling & Strict `repositories/`/`services/` Boundary).
- [ ] Complete **Design Gate** in `.agents/prototypes/ui_v2/` covering all production TierTask `0.8.0` parity views and mobile/desktop interactions.
- [ ] Author and complete **Phase 2 Child TEP** (`packages/tiertask_ui/` Component Library, Themes, Gallery App, and Tooling Integration).
- [ ] Author and complete **Phase 3 Child TEP** (Adaptive Shell & Feature Screens Cutover under Strict ViewModel Contract).
- [ ] Author and complete **Phase 4 Child TEP** (Legacy UI Retirement, Global Strict DAG Lock, and Documentation Synchronization).
- [ ] After all four child TEPs reach `completed`, set `TEP-015` to `review`, update `BOARD.md`, and request final approval.

### 3.2 Work Log & Decisions
- **2026-11-21:** Completed interactive architecture interview (`/grill-me`) and drafted umbrella `TEP-015`. Locked in: standalone `packages/tiertask_ui/` package with `example/` gallery, dedicated `lib/presentation/` DAG layer, strict ViewModel contract for new `lib/ui/`, pragmatic Phase 1 transition avoiding throwaway legacy rewrites, `Calm` (default) + `Plum Umber` extensible themes with verified WCAG AA contrast, modular offline prototype under `.agents/prototypes/ui_v2/`, and mandatory per-phase child TEPs created just-in-time.
- **2026-11-21:** Completed Phase 1 child proposal [`TEP-016`](tep-016-presentation-layer-decoupling.md) (`status: completed`): Rank `6` `lib/presentation/` layer delivered, `lib/models/tdf_file_path.dart` extracted, all `lib/ui/` repository/service imports and transitive repository/service/native-picker provider references eliminated and statically enforced in `.agents/scripts/tiertask_dev.py`.
- **2026-11-21:** Finalized Design Gate prototype parity in `.agents/prototypes/ui_v2/`: unified expandable entity cards with inline section editing (replacing the legacy 3-tab task editor and separate info/hub dialogs), read-only completed task panels, uncommitted inline entity draft cards, docked Quick-Add composer and view action footers, floating bottom notice/Undo overlay, active-label filter bar and search back-navigation, thin `1px` single-ring `:focus-visible` tokens, palette-themed `AppLogo` + inline `DEV` build pill, full History journal timestamp/cap/dedup rules, Settings auto-save vs. WebDAV dirty/validation split, full task/label/location conflict and recovery handling, initial loading and raw-TDF limit-exceeded states, modal/sheet `Tab` focus trapping, and desktop keyboard shortcuts (`/`, `Ctrl/Cmd+F`, `n`, `Ctrl/Cmd+Z`). Confirmed deterministic priority/downgrade ordering without manual drag-and-drop queue reordering.
- **2026-11-21:** Locked in the **maximum-reuse, minimum-widget-count** design rule for `packages/tiertask_ui/` and `lib/ui/`: consolidated the planned UI library to 17 orthogonal widgets (`8` primitives, `4` layouts, `5` composites) that reproduce `.agents/prototypes/ui_v2/` as closely as possible for the initial Flutter cutover, with explicit allowance to refine or diverge from the HTML prototype in later app iterations.

### 3.3 Delivered Artifacts
*(Complete upon approval)*
