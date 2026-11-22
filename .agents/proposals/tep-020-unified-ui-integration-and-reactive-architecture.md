---
id: TEP-020
title: Unified UI Integration, Package Dissolution, and Direct Reactive State Architecture
status: completed
type: architecture
created: 2026-11-22
updated: 2026-11-22
---

# TEP-020: Unified UI Integration, Package Dissolution, and Direct Reactive State Architecture

## Part 1: Concept & Proposal

### 1.1 Summary
This proposal dissolves the standalone `packages/tiertask_ui/` package and retires the mandatory model-free `lib/presentation/` adapter wall introduced in `TEP-015` through `TEP-019`, integrating all 24 reusable design-system modules directly into `lib/ui/` and restoring the clean 8-rank bottom-up DAG (`0..7`) established through `v0.4.0`. Every visual token, layout, breakpoint, card interaction, keyboard shortcut, and accessibility contract defined in [`spec/UI_DESIGN_SYSTEM.md`](../../spec/UI_DESIGN_SYSTEM.md) remains 100% visually identical to the user, while eliminating systemic double-dipping, cascading rebuilds, shadow state races, non-`autoDispose` background work, and 15 redundant mirror enums across the codebase.

### 1.2 Motivation
Post-`v0.4.0` strict UI isolation (`packages/tiertask_ui/` + Rank `7` model-free `lib/ui/` whitelist + `lib/presentation/` DTO layer) created **21 files (`16,175` lines)** of projection and adapter code that introduced recurring stability, flicker, and performance defects absent in `v0.4.0`:

1. **Shadow State, Multi-Rebuild Flicker & Dropped Input:** `SettingsController` (`1,667` lines) mirrors persisted `WebDavConfig` across 16 mutable fields and watches 4 providers unscoped in `build()`. Auto-saved preference toggles caused mid-flight `build()` re-entries, busy-flag disabled flicker, silent dropping of rapid second clicks while disk writes were in flight, and per-keystroke `LocalFileRepository` allocation.
2. **Over-Broad Provider Subscriptions & "Double Dipping":**
   - `localFileRepositoryProvider` and `webDavRepositoryProvider` watch the entire `WebDavConfig`, destroying `WebDavRepository` (and wiping its `_cachedEtag` / `_cachedExists` cache) on dark-mode, palette, or diagnostics toggles.
   - `diagnosticsEnabledProvider` and `WebDavConfigNotifier._syncLoggerForConfig` trigger redundant log file rewrites on unrelated preference changes; `ActiveWorkspaceNotifier.updateActiveConfig` bumps `_workspaceListRevisionProvider` even when workspace name and local path are unchanged.
   - `TierTaskShellScreen` watches unscoped `appShellControllerProvider` (26 fields) and `boardChromeViewModelProvider`, rebuilding the entire shell on every search keystroke, sidebar filter keystroke, label picker keystroke, or card expand/collapse.
   - `tasksViewModelProvider` watches the entire `WebDavConfig` and projects all 47 fields of every visible `TaskCardViewModel` on unrelated config edits, banner dismissals, or search keystrokes.
   - `lib/main.dart` watches `diagnosticsEnabledProvider` and `localFileWatcherProvider` directly inside `TierTaskApp.build`, rebuilding `MaterialApp` and recreating `ThemeData` on non-visual changes.
3. **Non-`autoDispose` Background Recomputation Leaks:** Nine view-specific providers (`rawTdfViewModelProvider`, `tasksViewModelProvider`, `labelsManagerViewModelProvider`, `locationsManagerViewModelProvider`, `settingsControllerProvider`, `workspacesViewModelProvider`, `locationStatusViewModelProvider`, `conflictResolutionViewModelProvider`, `recoveryResolutionViewModelProvider`) stayed alive indefinitely after first visit. Most severely, `rawTdfViewModelProvider` re-serialized and UTF-8 encoded the entire `.tdf` document on every task mutation for the remainder of the session.
4. **Correctness Bugs Caused by Layer Indirection:**
   - `ConflictDecisionsNotifier` and `RecoveryDecisionsNotifier` watch `taskNotifierProvider` and `appLocaleProvider`, wiping user conflict choices back to defaults on background updates.
   - `TaskController` and `EntityController` inspect `syncStateProvider.errorMessage` after mutations, misclassifying locally committed edits in offline dual-storage mode (`StorageMode.both`) as failures and trapping inline editors open.
   - `TaskController.saveSubtasks` (auto-finish) and `createAndAssignLabel` execute two separate disk + WebDAV sync writes instead of one atomic mutation.
   - `CompactLabelPickerSheet` had no Riverpod access, copying stale snapshots and fabricating `_syntheticIds` on inline label creation.
   - `FloatingNoticeController` ran a side-effect inside `build()` and double-flipped undo notice state on final undo.
5. **Mirror Enum & DTO Proliferation:** Fifteen domain/service enums (`TaskTier`, `QuickAddMode`, `AppThemePalette`, `AppThemeMode`, `AppLanguage`, `AppTimeZoneMode`, `DueLeadWindow`, `StorageMode`, `LocationStatus`, `LocationSourceType`, `RepeatUnit`, `LogLevel`, `LogTag`, `TdfDeletionResolution`, `TdfRecoveryResolution`) were duplicated 1:1 in `lib/presentation/` and mapped back through `UiIconMapper` and manual string parsers.
6. **Internal Component Library Friction:** Several widgets in `packages/tiertask_ui/` had internal rebuild or focus defects (`UiField` calling `setState` on every keystroke, `UiCard.expandable` rebuilding the entire expanded tree on mouse hover, `UiQuickComposer` scheduling overlay callbacks on every parent rebuild with stale closures, `UiPill.splitChip` dropping pointer taps when `onRemove == null`, `UiDialogFrame` leaking `CurvedAnimation` per frame, `UiSearchablePicker` swallowing `Escape` when `onRequestClose == null`, `UiSegmentedControl` calling `setState` during `didUpdateWidget`).

### 1.3 Goals & Non-Goals
- **Goals:**
  - Dissolve `packages/tiertask_ui/` completely (removing the subpackage, `example/` gallery, `pubspec.yaml` path dependency, and multi-package tooling complexity) and integrate its 24 design-system leaves into `lib/ui/{tokens,primitives,layout,components}/` with zero barrel `export` shims (`P-FILE-SIZE`).
  - Retire `lib/presentation/` and restore the clean 8-rank bottom-up DAG (`0: app_logger < 1: models < 2: l10n < 3: services < 4: repositories < 5: providers < 6: ui < 7: main.dart`), keeping `P-IO-ISOLATION` (`dart:io`, `dart:ffi`, `HttpClient` strictly in `lib/repositories/`) and forbidding direct `lib/repositories/` imports in `lib/ui/` while allowing `lib/ui/` direct access to `lib/models/`, `lib/l10n/`, `lib/providers/`, `lib/services/` pure helpers, and Riverpod.
  - Eliminate all 15 mirrored domain enums and redundant ViewModel DTO wrappers, using real domain models (`TaskItem`, `TaskTier`, `QuickAddMode`, `TdfLabel`, `TdfLocation`, `TaskLink`, `SubtaskItem`, `TaskCondition`, `WebDavConfig`, `WorkspaceSummary`, `LocationState`, `GeocodingCandidate`, `StorageFileReadReport`, `LogLevel`, `LogTag`, `TdfDeletionResolution`, `TdfRecoveryResolution`) end-to-end.
  - Fix every identified double-dipping, flicker, dropped-click, non-`autoDispose`, stale-state, double-write, and internal widget rebuild bug structurally.
  - Preserve **100% identical external visual appearance, tokens, WCAG AA contrast, breakpoints, `ValueKey`s, keyboard shortcuts, 9-layer `Escape` order, localization (`en`/`de`), and `v0.4.0` + `TDF 0.8.0` runtime functionality**.
- **Non-Goals:**
  - Visual redesign or changes to color tokens, spacing, radii, typography, layout breakpoints, or interaction flows.
  - Any modification to `spec/TDF_SPEC_0.8.0.md`, `.tdf` file format semantics, or `settings.json` / `TTS\x04` persistence formats.
  - Removing or weakening `P-IO-ISOLATION`, `P-ACYCLIC-DAG`, `P-FLATTEN-BUILD`, `P-TDD-FIRST`, `audit_l10n`, or `spec/UI_DESIGN_SYSTEM.md` visual/UX invariants.

### 1.4 Description
Externally, TierTask remains identical across Linux, Android, and Windows in both English (`en`) and German (`de`). Internally:
1. The 24 reusable design-system modules live in `lib/ui/{tokens,primitives,layout,components}/` as universal, domain-agnostic widgets obeying internal rank order `tokens < primitives < layout < components` (with zero imports from app `views/`, `dialogs/`, or `tier_task_shell_screen.dart`).
2. `lib/providers/` directly provides both core storage/domain state (`workspace_providers`, `config_providers`, `local_file_watch_providers`, `location_providers`, `sync_providers`, `task_providers`) and lean, domain-typed reactive UI coordination (`board_providers`, `shell_providers`, `floating_notice_providers`, `log_viewer_providers`, `task_schedule_helper`, `location_source_resolver`, `settings_draft_providers`, `board_actions_provider`, `ui_telemetry`).
3. Every `lib/ui/` screen, card, dialog, and chrome widget watches only its narrowest required Riverpod slice via `.select(...)` or `.autoDispose` providers, consuming domain models directly without intermediate ViewModel cloning.
4. `lib/main.dart` mounts background lifecycle/watcher/diagnostics subscriptions outside `MaterialApp` rebuilds and caches `ThemeData` per `(AppThemePalette, Brightness)`.

### 1.5 Alternatives
- **Patching individual bugs inside the existing `lib/presentation/` + `packages/tiertask_ui/` split:** Rejected because every fix requires touching 3 to 5 wrapper layers (provider -> controller -> ViewModel -> mapper -> widget), leaves 15 mirrored enums and 16,175 lines of adapter indirection in place, and invites recurring state-sync bugs.
- **Reverting to legacy `v0.4.0` Material screens:** Rejected because the new adaptive UI design system (`spec/UI_DESIGN_SYSTEM.md`) is visually finalized and must not change externally.

## Part 2: Technical Design & Code Changes

### 2.1 Architecture & Affected Modules
- **Deleted:**
  - `packages/tiertask_ui/**` (entire directory)
  - `lib/presentation/**` (all 21 files)
  - `test/presentation/**` (all 17 files, migrated to `test/providers/` and `test/ui/`)
- **Modified Root Config & Entrypoint:**
  - `pubspec.yaml`: remove `tiertask_ui` path dependency.
  - `analysis_options.yaml`: remove `- packages/**` exclusion.
  - `lib/main.dart`: watch `appThemePaletteProvider`, `appThemeModeProvider`, `appLocaleProvider`, `appBuildProfileProvider` directly; cache `ThemeData` per preset+brightness; host `diagnosticsEnabledProvider` and `localFileWatcherProvider` inside an isolated `_BackgroundServicesHost` child so they never trigger `MaterialApp` rebuilds.
- **Core & Coordination Providers (`lib/providers/` — Rank `5`):**
  - `workspace_providers.dart`: bump `_workspaceListRevisionProvider` in `updateActiveConfig` only when workspace summary fields (`name` or `localFilePath`) changed.
  - `config_providers.dart`:
    - Narrow `localFileRepositoryProvider` to `.select((localFilePath, language, storageMode))` and `webDavRepositoryProvider` to `.select((serverUrl, username, password, filePath, language, storageMode))` so UI preference changes never destroy `WebDavRepository` ETag/existence cache.
    - Narrow `diagnosticsEnabledProvider` to logger-affecting fields and eliminate duplicate `AppLogger.setEnabled` disk rewrites on unrelated preferences.
    - Serialize preference writes sequentially in `WebDavConfigNotifier` with immediate optimistic state updates and clean rollback on `WorkspaceException` failure so rapid toggles never drop clicks or flicker.
    - Expose `openExternalLink` / `windowControl` provider helpers cleanly without separate presentation wrapper files.
  - `location_providers.dart`: scope `locationEnabledProvider` with `.select(...)`.
  - `sync_providers.dart`: add `.autoDispose` `conflictDecisionsProvider` and `recoveryDecisionsProvider` keyed solely on `syncStateProvider.select((s) => s.syncOutcome)` using real `TdfDeletionResolution` / `TdfRecoveryResolution`, plus `syncActionProvider` for manual sync, retry, and conflict/recovery resolution dispatch.
  - `task_providers.dart`: add atomic single-commit `updateTaskAndComplete(...)` and `createLabelAndAssignToTask(...)` mutations eliminating double disk + WebDAV sync writes.
  - `ui_telemetry.dart`: redacted `LogTag.ui` event emitters.
  - `board_providers.dart`: `.autoDispose.family` `evaluatedBoardProvider` and `taskPrerequisiteCandidatesProvider`; `.autoDispose` `rawTdfPreviewProvider`; `BoardBoundaryTimer` and `boardBoundaryTimerProvider` (removing duplicate resume `_syncFromProviders` call).
  - `shell_providers.dart`: `ShellState` / `ShellNotifier` (`shellProvider`) using real `TaskTier` and `QuickAddMode`; dedicated high-frequency text query providers (`searchQueryProvider`, `labelPickerQueryProvider`, `sidebarLabelsFilterQueryProvider`, `sidebarLocationsFilterQueryProvider`); shell navigation/section/result types (`ShellView`, `EntityKind`, `EntityDraftKind`, `TaskSectionKind`, `LabelSectionKind`, `LocationSectionKind`, `ConditionDimensionMode`, `ShellDismissOutcome`, `EntityRef`, `InlineEditTarget`, `ReturnContext`, `ActionResult`).
  - `floating_notice_providers.dart`: `FloatingNotice`, `FloatingNoticeTone`, `FloatingNoticeNotifier`, `floatingNoticeProvider` (removing `build()` side-effect, preventing undo completion toast double-flip, platform-gating `Ctrl+Z` shortcut hint, guarding `AsyncLoading` workspace transitions).
  - `log_viewer_providers.dart`: `.autoDispose` `activeLogFileNameProvider` and `logViewerProvider` using real `LogLevel` and `LogTag`.
  - `task_schedule_helper.dart`: stateless `TaskScheduleHelper` (all static), `ResolvedDueDraft`, `ResolvedSuspendedDraft`, `ConditionDraft`, `TimeWindowDraft`, `canonicalLabelPresetHexColors`.
  - `location_source_resolver.dart`: `locationSourceResolverProvider` and `LocationSourceResolutionResult` using real `GeocodingCandidate` and `LocationSourceType`.
  - `settings_draft_providers.dart`: `.autoDispose` `settingsDraftProvider` holding only transient WebDAV draft inputs, validation errors, status banner, blocking WebDAV/storage busy flags, and capability-gated local file / wipe / WebDAV Save & Test+Sync actions (zero shadowing of persisted preferences).
  - `board_actions_provider.dart`: unified domain-typed task/label/location action coordinator (`boardActionsProvider`) with shared validation helpers, pre-generated IDs, `evaluatedBoardProvider` reads, accurate offline dual-storage commit detection, and atomic subtask auto-finish / label create-and-assign calls.
- **Unified User Interface (`lib/ui/` — Rank `6`):**
  - `lib/ui/tokens/` (7 files), `lib/ui/primitives/` (8 files), `lib/ui/layout/` (4 files), `lib/ui/components/` (5 files): integrated design-system leaves with internal focus/hover/keystroke/overlay/dispose fixes and zero visual changes.
  - `lib/ui/ui_domain_mappers.dart`: concise stateless mapper from real domain enums (`TaskTier`, `AppThemePalette`, `AppThemeMode`, `LocationStatus`, `SyncStatusKind`, `FloatingNoticeTone`) to `UiThemePreset`, `ThemeMode`, `IconData`, `UiBannerTone`, `UiButtonTone`.
  - `lib/ui/tier_task_shell_screen.dart`: granular `.select(...)` subscriptions on every chrome control, sidebar section, search bar, notice host, and route slot.
  - `lib/ui/widgets/` (6 files): domain-direct `EntityCardMetaBar`, `EntityConditionsSection`, `EntityHybridDateTimeField`/`EntityHybridTimeField`, `EntitySearchableLabelPicker`, `EntityLinksSection`, `EntityNoteSection` (removing `KeyedSubtree(ValueKey<bool>)` button remount hacks).
  - `lib/ui/dialogs/` (6 files): live Riverpod-backed `CompactLabelPickerSheet` (eliminating `_syntheticIds`), domain-direct `GeocodingCandidatesModal`, `LocalFileModals`, `LocationStatusModal`, `WipeTdfModal`, and `WorkspacesModal` (isolating create-input keystrokes via `ValueListenableBuilder`).
  - `lib/ui/views/` (13 files): domain-direct `TasksView` (pruned `_ownedCardKeys`, decoupled `TasksQuickAddDock` and status banners), `TaskCard` (lazy expanded section computation, real `TaskItem`), `TaskScheduleEditors`, `TaskDetailEditors`, `TaskDraftCard`, `LabelsView`, `LabelCard`, `LocationsView`, `LocationCard`, `SettingsView` (direct `webDavConfigProvider.select` auto-saved cards + `.autoDispose` `settingsDraftProvider` WebDAV card/dock), `LogViewerView`, `RawTdfView`, `ResolutionViews` (per-card `.select` decisions).
- **Tooling, Docs & Skills:**
  - `.agents/scripts/tiertask_dev.py` & `.agents/scripts/tests/test_tiertask_dev.py`: restore 8-rank DAG (`0..7`), internal design-system rank check (`tokens < primitives < layout < components`, no imports from `views/`/`dialogs/`/`tier_task_shell_screen.dart`), forbid direct `lib/repositories/` imports in `lib/ui/`, keep `P-IO-ISOLATION` across all non-repository `lib/`, unconditionally ban `export`/`part`/`part of`, ban retired dirs (`packages/tiertask_ui/`, `lib/presentation/`, `test/presentation/`, `lib/ui_v2/`, `test/ui_v2/`), remove multi-package tooling.
  - Update `AGENTS.md`, `ARCHITECTURE.md`, `spec/UI_DESIGN_SYSTEM.md`, `README.md`, `.agents/skills/{ui-design-system,update-documentation,red-team-audit}/SKILL.md`, and superseding notes on `TEP-015`..`TEP-019`.

### 2.2 TDF Schema, Localization & State Changes
- **TDF Schema (`spec/TDF_SPEC_0.8.0.md`):** Zero changes.
- **Settings / Sync Persistence (`settings.json`, `TTS\x04`):** Zero changes.
- **ARB Localization (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`):** Zero key additions, removals, or wording changes; `tiertask_dev.py l10n --audit` remains completely clean.
- **Reactive State Contract:**
  - Single source of truth for persisted config: `webDavConfigProvider`.
  - Single source of truth for persisted board: `taskNotifierProvider`; evaluated projection: `evaluatedBoardProvider(activeLabelId)`.
  - High-frequency text queries (`searchQueryProvider`, `labelPickerQueryProvider`, `sidebarLabelsFilterQueryProvider`, `sidebarLocationsFilterQueryProvider`) decoupled from `shellProvider`.
  - View-scoped projections (`rawTdfPreviewProvider`, `settingsDraftProvider`, `logViewerProvider`, `activeLogFileNameProvider`, `conflictDecisionsProvider`, `recoveryDecisionsProvider`, `taskPrerequisiteCandidatesProvider`, `evaluatedBoardProvider`) strictly `.autoDispose`.

### 2.3 Implementation Details
- **Layer & Dependency Invariants (`P-UDF-ARCHITECTURE`, `P-ACYCLIC-DAG`, `P-IO-ISOLATION`):**
  - Root DAG ranks: `0: lib/services/app_logger.dart < 1: lib/models/* < 2: lib/l10n/* < 3: lib/services/* < 4: lib/repositories/* < 5: lib/providers/* < 6: lib/ui/* < 7: lib/main.dart`.
  - Internal design-system ranks inside `lib/ui/`: `tokens (0) < primitives (1) < layout (2) < components (3)`; none of those 4 subdirectories may import `lib/ui/{widgets,dialogs,views}/`, `lib/ui/tier_task_shell_screen.dart`, `lib/ui/ui_domain_mappers.dart`, `lib/providers/`, `lib/repositories/`, `lib/services/`, or `lib/models/` (preserving universal widget reusability).
  - `lib/ui/` MUST NOT import `lib/repositories/`, `dart:io`, or `dart:ffi` (`P-IO-ISOLATION`), and may freely import `lib/models/`, `lib/l10n/`, pure `lib/services/`, `lib/providers/`, and `package:flutter_riverpod/flutter_riverpod.dart`.
  - Zero `export`, `part`, or `part of` directives anywhere in `lib/` or `test/`.
- **Atomic Persistence & Single-Pass Evaluation:**
  - `TaskNotifier.updateTaskAndComplete` builds the updated subtasks board and immediately applies `completeTask` on the resulting board in one `_commitMutation` call (recording the pre-mutation `TaskBoardUndo` snapshot for `TaskUndoActionKind.complete`).
  - `TaskNotifier.createLabelAndAssignToTask` adds the new `TdfLabel` with pre-generated ID and attaches it to the target task in one `_commitMutation` call.
  - `WebDavConfigNotifier` serializes concurrent updates via an internal `_pendingWrite` chain while applying optimistic `AsyncData` transitions immediately and rolling back on `WorkspaceException`.
- **Diagnostic Logging (`AGENTS.md` Section 6):**
  - Preserve all 20 redacted `UiTelemetry` `LogTag.ui` events (`lib/providers/ui_telemetry.dart`), `config.update`, `domain.lead_window.reevaluated`, `sync.*`, and `ui.boundary_timer.*` events with zero allocations when `AppLogger.shouldLog` is false.

### 2.4 Testing Strategy
Execute Red-Green-Refactor TDD (`P-TDD-FIRST`, `P-TEST-MIRROR`) across all mandatory categories:
- **`M-EXHAUSTIVE-STATE-TESTS`:**
  - All 20 integrated design-system test suites under `test/ui/{tokens,primitives,layout,components}/` covering all 4 theme presets (`Calm`, `Plum Umber`, Light/Dark, 68 WCAG AA pairs), every primitive variant/tone/density, and `UiDomainMappers` exhaustiveness across all domain enums.
  - `.agents/scripts/tests/test_tiertask_dev.py` verifying 8-rank DAG (`0..7`), internal design-system ranks, `lib/ui/ -> lib/repositories/` ban, `P-IO-ISOLATION`, unconditional `export`/`part` ban, retired directory bans, and `audit_l10n`.
- **`M-EXTREME-BOUND-TESTS`:**
  - Breakpoint boundaries `390 / 720 / 721 / 760 / 820 / 821 / 1280`, `TaskScheduleHelper` and `LocationSourceResolver` `maxTdf*` / `maxInputLength` bounds, and `rawTdfPreviewProvider` `1 MiB` / `16,384`-line limit-exceeded state.
- **`M-DELIM-INJECT-TESTS` & `M-URI-PATH-EDGE-TESTS`:**
  - Preserved across `board_actions_provider_test.dart`, `settings_draft_providers_test.dart`, and `task_schedule_helper_test.dart`.
- **`M-IO-TESTS`:**
  - Hermetic in-memory and `Directory.systemTemp` tests verifying `WebDavRepository` ETag cache preservation across UI preference toggles, single log-file rewrite behavior, local file move/rename/select/wipe flows, and offline dual-storage local commits.
- **`M-REAL-MECHANICS-TESTS` (`test/ui/real_mechanics_test.dart`):**
  - Preserve all 12 existing end-to-end mechanics scenarios and add permanent regression tests for:
    1. Rapid sequential preference toggles (`Palette` -> `ThemeMode` -> `Language`) suspended on a `Completer` apply monotonically without dropping clicks, disabling controls, bouncing `AsyncLoading`, resyncing `TaskNotifier`, wiping `WebDavRepository` ETag cache, or double-writing logs.
    2. Leaving `RawTdfView` disposes `rawTdfPreviewProvider` so subsequent task mutations perform zero background `.tdf` serialization.
    3. Toggling `DeletionConflict` / `GenerationRecovery` decisions survives background board or locale updates without resetting user selections.
    4. Offline `StorageMode.both` inline edits succeed locally and close the inline editor instead of returning false persistence failure.
    5. `saveSubtasks` auto-finish and `createAndAssignLabel` execute in a single atomic persistence commit.
    6. Compact mobile label picker sheet reactively updates when creating a real label without synthetic IDs.

## Part 3: Implementation Record & Tasks

### 3.1 Task Breakdown
- [x] Confirm clean baseline (`python3 .agents/scripts/tiertask_dev.py verify --fast` and Python tooling tests).
- [x] **Wave 1 (Package Dissolution & Integrated Design System):**
  - [x] Move all 24 design-system files into `lib/ui/{tokens,primitives,layout,components}/` with relative imports and zero barrel exports; fix internal widget defects (`UiField`, `UiCard`, `UiQuickComposer`, `UiPill`, `UiDialogFrame`, `UiSearchablePicker`, `UiSidebarSection`, `UiSegmentedControl`) while preserving 100% visual parity.
  - [x] Move all 20 design-system test suites into `test/ui/{tokens,primitives,layout,components}/`, merge `pumpUiWidget` into `test/ui/test_helpers.dart`, delete `packages/tiertask_ui/`, update `pubspec.yaml` and `analysis_options.yaml`, and run `flutter pub get`.
- [x] **Wave 2 (Core Provider Hardening & Domain-Direct Coordination Providers, Rank `5`):**
  - [x] Harden `workspace_providers.dart`, `config_providers.dart`, `location_providers.dart`, `sync_providers.dart`, `task_providers.dart`, and `app_logger.dart` with TDD tests (`test/providers/`).
  - [x] Implement `ui_telemetry.dart`, `board_providers.dart`, `shell_providers.dart`, `floating_notice_providers.dart`, `log_viewer_providers.dart`, `task_schedule_helper.dart`, `location_source_resolver.dart`, `settings_draft_providers.dart`, `board_actions_provider.dart`, and `entity_actions_provider.dart` with comprehensive unit tests under `test/providers/`.
- [x] **Wave 3 (Unified Domain-Direct `lib/ui/` & `lib/main.dart` Cutover, Ranks `6` to `7`):**
  - [x] Update `lib/main.dart`, `lib/ui/ui_domain_mappers.dart`, `lib/ui/tier_task_shell_screen.dart`, `lib/ui/widgets/*`, `lib/ui/dialogs/*`, and `lib/ui/views/*` to consume integrated design-system widgets, domain models, and granular `.select(...)` Riverpod providers directly.
  - [x] Delete `lib/presentation/`, `test/presentation/`, and `lib/ui/ui_icon_mapper.dart`; update all `test/ui/` suites and add all 6 new `M-REAL-MECHANICS-TESTS` regression scenarios.
- [x] **Wave 4 (Tooling, Documentation, Skills & Full Verification Gate):**
  - [x] Update `.agents/scripts/tests/test_tiertask_dev.py` and `.agents/scripts/tiertask_dev.py` for the 8-rank DAG, integrated design-system layer checks, and retired directory bans.
  - [x] Synchronize `AGENTS.md`, `ARCHITECTURE.md`, `spec/UI_DESIGN_SYSTEM.md`, `README.md`, `.agents/skills/{ui-design-system,update-documentation,red-team-audit}/SKILL.md`, and superseding notes on `TEP-015`..`TEP-019`.
  - [x] Run `python3 -m unittest discover -s .agents/scripts/tests -p 'test_*.py'` and `python3 .agents/scripts/tiertask_dev.py verify --full --fix` until completely green.
  - [x] Set `status: review`, update `BOARD.md`, and report results to user for approval.
  - [x] After user approval, set `status: completed`, update `BOARD.md`, and finalize delivered artifacts in Part 3.3.

### 3.2 Work Log & Decisions
- **2026-11-22:** Completed forensic audit of `lib/presentation/` (`21` files, `16,175` lines), `lib/ui/` (`27` files, `30,520` lines), `packages/tiertask_ui/` (`25` files, `13,474` lines), `lib/providers/` (`6` files), and `.agents/scripts/tiertask_dev.py`. Drafted `TEP-020` (`status: in-progress`).
- **2026-11-22 (Wave 1):** Integrated all 24 design-system leaves into `lib/ui/{tokens,primitives,layout,components}/` and all 20 design-system tests into `test/ui/{tokens,primitives,layout,components}/`; removed `packages/tiertask_ui/`; fixed 8 internal design-system focus/hover/keystroke/overlay/animation defects.
- **2026-11-22 (Wave 2):** Hardened core providers (narrowed `.select(...)` on repositories/locale/theme/location/diagnostics, optimistic FIFO `WebDavConfigNotifier` with `_initialBuildPending` build-race fix and rollback, atomic `createLabelAndAssignToTask` and `updateTaskAndComplete` single-commit mutations, `TaskNotifier.lastMutationCommitted` commit tracking, `.autoDispose` conflict/recovery decision notifiers, removed circular `webDavRepositoryProvider` read inside `WebDavConfigNotifier`). Split task actions (`board_actions_provider.dart`) and label/location/sync/workspace actions (`entity_actions_provider.dart`) cleanly onto shared `TaskScheduleHelper` validators and real domain models (`222/222` provider and logger tests passing).
- **2026-11-22 (Wave 3):** Promoted `TaskBoardEvaluator.areTaskConditionsSatisfied` for single-source condition evaluation; replaced `ui_icon_mapper.dart` with `ui_domain_mappers.dart`; refactored all 27 app UI files and `lib/main.dart` (cached `ThemeData`, `_BackgroundServicesHost`, live Riverpod `CompactLabelPickerSheet`, decoupled text-query providers, granular `.select(...)` cards/chrome, zero `KeyedSubtree` remount hacks); deleted `lib/presentation/` and `test/presentation/`; migrated all `test/ui/` suites and added all 6 permanent `M-REAL-MECHANICS-TESTS` regression scenarios.
- **2026-11-22 (Wave 4):** Updated `.agents/scripts/tiertask_dev.py` and `test_tiertask_dev.py` (`15/15` passing) for the 8-rank DAG (`0..7`), universal internal Design System sub-ranks (`tokens < primitives < layout < components`), `lib/ui/ -> lib/repositories/` ban, unconditional `export`/`part` ban, and retired directory bans. Synchronized `AGENTS.md` (`20,149` bytes), `ARCHITECTURE.md`, `spec/UI_DESIGN_SYSTEM.md`, skills, and `TEP-015`..`TEP-019` superseding notes. Verified `verify --full --fix --force` (`0` analyzer/static/L10N/ARCH issues, `707/707` Flutter tests passing). Advanced status to `review`.
- **2026-11-22:** User approved and closed proposal (`status: completed`).

### 3.3 Delivered Artifacts
- **Removed:** `packages/tiertask_ui/**`, `lib/presentation/**`, `test/presentation/**`, `lib/ui/ui_icon_mapper.dart`, `test/ui/ui_icon_mapper_test.dart`.
- **Integrated Design System (`lib/ui/{tokens,primitives,layout,components}/` + `test/ui/{tokens,primitives,layout,components}/`):** 24 universal design-system modules and 20 test suites with internal rebuild/focus/overlay/animation fixes and zero visual changes.
- **Hardened & Unified Providers (`lib/providers/` + `test/providers/`):** `config_providers.dart`, `workspace_providers.dart`, `location_providers.dart`, `sync_providers.dart`, `task_providers.dart`, `ui_telemetry.dart`, `board_providers.dart`, `shell_providers.dart`, `floating_notice_providers.dart`, `log_viewer_providers.dart`, `location_source_resolver.dart`, `task_schedule_helper.dart`, `settings_draft_providers.dart`, `board_actions_provider.dart`, `entity_actions_provider.dart`.
- **Domain-Direct UI & Entrypoint (`lib/main.dart`, `lib/ui/` + `test/ui/`):** `ui_domain_mappers.dart`, `tier_task_shell_screen.dart`, 6 shared widgets, 6 modals/sheets, 13 views/cards/editors, and 10 updated UI test suites including `18/18` `M-REAL-MECHANICS-TESTS` scenarios.
- **Tooling & Documentation:** `.agents/scripts/tiertask_dev.py`, `.agents/scripts/tests/test_tiertask_dev.py`, `AGENTS.md`, `ARCHITECTURE.md`, `spec/UI_DESIGN_SYSTEM.md`, `.agents/skills/{ui-design-system,update-documentation,red-team-audit}/SKILL.md`, and superseding notes on `TEP-015`..`TEP-019`.
