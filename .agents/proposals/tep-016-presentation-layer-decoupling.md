---
id: TEP-016
title: Phase 1 Presentation Layer Decoupling and Strict UI Boundary
status: completed
type: architecture
created: 2026-11-21
updated: 2026-11-21
---

# TEP-016: Phase 1 Presentation Layer Decoupling and Strict UI Boundary

## Part 1: Concept & Proposal

### 1.1 Summary
This proposal specifies **Phase 1** of the umbrella architecture roadmap in [`TEP-015`](tep-015-ui-architecture-and-design-system-roadmap.md). It introduces the Rank `6` presentation layer (`lib/presentation/`), relocates pure `.tdf` path and filename utilities into `lib/models/tdf_file_path.dart`, extracts board evaluation, wall-clock boundary timer coordination, Plus Code and geocoding resolution, `.tdf` preview export, screen/form controllers, presentation-layer diagnostic log view types, and redacted `LogTag.ui` telemetry out of `lib/ui/`, and updates `.agents/scripts/tiertask_dev.py` to enforce zero `lib/repositories/` or `lib/services/` coupling across `lib/ui/` with zero visual or behavioral regressions.

### 1.2 Motivation
An import and reference audit of `lib/ui/` confirms four structural violations that block safe component library extraction (Phase 2) and adaptive UI cutover (Phase 3):
1. **Direct Repository Imports (`10` UI files) and Transitive Repository Provider Calls:**
   - `lib/ui/settings_screen.dart` and `lib/ui/widgets/settings_local_storage_section.dart` import and instantiate `LocalFileRepository` directly; `settings_screen.dart` watches `supportsDirectoryPickerProvider`, and `settings_local_storage_section.dart` reads `localFileRepositoryProvider`, `directoryPickerProvider`, `filePickerProvider`, and `supportsDirectoryPickerProvider`.
   - `lib/ui/widgets/local_tdf_file_dialogs.dart`, `lib/ui/widgets/workspace_dialog.dart`, `lib/ui/widgets/workspace_row_card.dart`, `lib/ui/settings_screen.dart`, and `lib/ui/widgets/settings_local_storage_section.dart` depend on static filename and path utilities on `LocalFileRepository`.
   - `lib/ui/edit_labels_screen.dart`, `lib/ui/edit_task_screen.dart`, `lib/ui/widgets/label_hub_dialog.dart`, `lib/ui/widgets/tier_task_subtasks_section.dart`, and `lib/ui/widgets/tier_task_pill.dart` depend on `LinkLauncherRepository`, `LinkLaunchException`, or `linkLauncherRepositoryProvider`.
   - `lib/ui/widgets/home_drawer.dart` imports `AppVersionRepository` (`defaultFullVersion`) and invokes `tdfServiceProvider.serialize(board)`.
   - `lib/ui/home_screen.dart` reads `settingsRepositoryProvider.takeLastRecoveryNotice()` directly.
   - `lib/ui/edit_locations_screen.dart` invokes `locationRepositoryProvider.searchLocations(...)` directly.
2. **Direct Service Imports (`12` UI files; `17` distinct files combined with repository imports):**
   - `lib/ui/edit_locations_screen.dart` imports `PlusCodeService` and executes Open Location Code parsing, decoding, and nearest-locality recovery inside widget state.
   - `12` UI files (`edit_labels_screen.dart`, `edit_locations_screen.dart`, `edit_task_screen.dart`, `home_screen.dart`, `label_color_picker_dialog.dart`, `label_hub_dialog.dart`, `local_tdf_file_dialogs.dart`, `log_viewer_dialog.dart`, `settings_preference_cards.dart`, `task_info_dialog.dart`, `tier_task_subtasks_section.dart`, and `wipe_tdf_dialog.dart`) directly import `lib/services/app_logger.dart` for `AppLogger`, `LogLevel`, or `LogTag`.
3. **Domain Evaluation, Timers, and Form Logic Embedded in Stateful Widgets:**
   - `lib/ui/home_screen.dart` directly invokes `board.evaluateForContext(...)` with `clockProvider` and `configuration.toLocalWallClock(...)`, owns `HomeScreenBoundaryTimer`, and coordinates `AppLifecycleListener` timer pausing/resuming inside `_HomeScreenState`.
   - `lib/ui/edit_task_screen.dart`, `lib/ui/edit_labels_screen.dart`, `lib/ui/edit_locations_screen.dart`, `lib/ui/settings_screen.dart`, `lib/ui/widgets/task_info_dialog.dart`, and `lib/ui/widgets/log_viewer_dialog.dart` interleave form validation, UTC wall-clock conversion, persistence rejection mapping, and log filtering directly inside `State` classes.
4. **Incomplete Automated Layer Enforcement:**
   - `.agents/scripts/tiertask_dev.py` currently defines Ranks `0..7` with no `lib/presentation/` layer, allows `lib/ui/` to import any lower rank including `lib/repositories/` and `lib/services/`, and restricts `P-IO-ISOLATION` `dart:io` checks to three directories without checking `dart:ffi` or `lib/presentation/`.

### 1.3 Goals & Non-Goals
- **Goals:**
  - Create `lib/models/tdf_file_path.dart` (Rank `1`) for pure, platform-safe `.tdf` filename and path helpers and delegate matching methods in `lib/repositories/local_file_operations.dart` to it.
  - Create the Rank `6` `lib/presentation/` layer with cohesive, unit-tested controllers, derived providers, immutable ViewModels, diagnostic log presentation types, and redacted `LogTag.ui` telemetry helpers actively consumed by `lib/ui/` (zero dead code per `P-NO-DEAD-CODE`).
  - Eliminate `100%` of `lib/repositories/*` and `lib/services/*` imports AND `100%` of direct repository, service, and native-picker provider references (`*RepositoryProvider`, `tdfServiceProvider`, `directoryPickerProvider`, `filePickerProvider`, `supportsDirectoryPickerProvider`) across all files in `lib/ui/`.
  - Preserve `100%` existing visual appearance, `en`/`de` localization output, keyboard/accessibility behavior, structured `AppLogger` event names and redacted fields, and test compatibility across Linux, Android, and Windows.
  - Extend `.agents/scripts/tiertask_dev.py` (and its unit test suite `.agents/scripts/tests/test_tiertask_dev.py`) to enforce DAG Ranks `0..8`, extended `P-IO-ISOLATION` (`dart:io`, `dart:ffi`, `HttpClient` forbidden outside `lib/repositories/`), and the Phase 1 `P-UDF-ARCHITECTURE` `lib/ui/` presentation boundary.
  - Synchronize `ARCHITECTURE.md` and `AGENTS.md` to document the Rank `6` `lib/presentation/` layer and updated DAG order.
- **Non-Goals:**
  - Any modification to `spec/TDF_SPEC_0.8.0.md`, `.tdf` parsing/serialization/merge semantics, or `settings.json` / `TTS\x04` storage schemas.
  - Any visual redesign, theme palette migration (`Calm` / `Plum Umber`), ARB key additions/removals, or creation of `packages/tiertask_ui/` (deferred to Design Gate, Phase 2, and Phase 3 child TEPs).
  - Stripping `lib/models/*` or `lib/providers/*` (`taskNotifierProvider`, `webDavConfigProvider`, `activeWorkspaceProvider`, `syncStateProvider`, `locationStateProvider`, `taskUndoStateProvider`) imports from legacy `lib/ui/` screens that Phase 4 will delete.
  - Rewriting `lib/ui/app_theme.dart` or replacing `material_ui` widgets in legacy screens.

### 1.4 Description

#### Architectural Boundary Transition
Phase 1 establishes a clean separation between presentation logic (`lib/presentation/`, Rank `6`) and widget rendering (`lib/ui/`, Rank `7`) without breaking legacy screens:
- **Pure Path Helpers (`lib/models/tdf_file_path.dart`, Rank `1`):** Holds all pure string-based `.tdf` filename and path utilities (`combineDirectoryAndFileName`, `ensureTdfExtension`, `extractDirectoryFromPath`, `extractFileBaseName`, `extractFileNameFromPath`, `isAbsolutePath`, `isValidSingleFileName`, `trimTrailingSeparators`) with zero `dart:io` or `dart:ffi` imports. `LocalFileOperations` delegates these pure methods to `TdfFilePath`, while `LocalFileRepository` static forwarders remain intact so existing repository and provider code/tests remain backwards-compatible.
- **Presentation Layer (`lib/presentation/`, Rank `6`):** Owns all non-widget presentation logic:
  - Live `TaskBoard` evaluation (`evaluatedBoardProvider`)
  - Lifecycle-aware single-timer wall-clock boundary scheduling (`BoardBoundaryTimer`, `boardBoundaryTimerProvider`)
  - Application version presentation (`AppVersionViewModel`, `appVersionViewModelProvider`) and raw `.tdf` preview export (`TdfPreviewController`, `tdfPreviewControllerProvider`)
  - Link launch intent mediation (`LinkActionController`, `linkActionControllerProvider`)
  - Diagnostic log view types, filtering, statistics, and actions (`DiagnosticLogLevel`, `DiagnosticLogTag`, `DiagnosticLogSeverity`, `DiagnosticLogViewModel`, `activeLogFileNameProvider`, `LogViewerController`, `logViewerControllerProvider`)
  - Settings storage path inspection, native picker orchestration, log-level bridging, preference persistence, and one-shot startup recovery notice consumption (`SettingsController`, `settingsControllerProvider`)
  - Location source classification, offline Plus Code decoding/recovery, forward geocoding disambiguation state, GPS lookup, and location draft validation/CRUD (`LocationEditorController`, `locationEditorControllerProvider`)
  - Label draft validation, CRUD, and redacted save telemetry (`LabelEditorController`, `labelEditorControllerProvider`)
  - Task draft wall-clock resolution (`due`, `due.anchor`, `suspended`, `passive` auto-reset), validation, persistence error mapping, CRUD, and redacted telemetry (`TaskEditorController`, `taskEditorControllerProvider`)
  - Task Info live history journal validation, rollback-safe mutations, duration formatting, and redacted telemetry (`TaskInfoController`, `taskInfoControllerProvider`)
  - Redacted `LogTag.ui` navigation, dialog, clipboard, toggle, and undo telemetry (`UiTelemetry`)
- **Legacy UI Adaptation (`lib/ui/`, Rank `7`):** Updates the `18` coupled UI files (plus `3` task editor widget leaves delegating shared pure helpers to `TaskEditorController` or removing superseded wrappers so Rank `6` never imports Rank `7`) to consume `lib/models/tdf_file_path.dart` and `lib/presentation/*` instead of `lib/repositories/*` or `lib/services/*`. Every existing widget key, `SnackBar`, dialog, `en`/`de` localized message, and user workflow across Linux, Android, and Windows remains unchanged.

#### Localization Resolution Across Production and Leaf Widget Tests
Controllers in `lib/presentation/` resolve `AppLocalizations` using `lookupAppLocalizations(locale ?? _ref.read(appLocaleProvider))`. In production (`TierTaskApp`), `appLocaleProvider` always matches the active `MaterialApp` locale (`en` or `de`). To keep isolated leaf widget tests (`pumpLeafWidget` in `test/ui/test_helpers.dart`) consistent when tests pass `locale: const Locale('de')` without setting `config.language`, `pumpLeafWidget` synchronizes `appLocaleProvider` with the effective test locale.

### 1.5 Alternatives
- **Move `LogLevel` and `LogTag` into `lib/models/` instead of defining presentation log types in `lib/presentation/`:** Rejected because `lib/services/app_logger.dart` sits at DAG Rank `0` (below Rank `1` `lib/models/`). Moving `LogLevel`/`LogTag` to Rank `1` would create a Rank `0 -> Rank 1` upward dependency or force `app_logger.dart` to rank above models, breaking `AppLogger` usage across `lib/models/`. Defining presentation-layer `DiagnosticLogLevel` and `DiagnosticLogTag` inside `lib/presentation/` preserves Rank `0` for `app_logger.dart` and keeps `lib/ui/` completely decoupled from `lib/services/`.
- **Build speculative Phase 3 screen ViewModels for every screen in Phase 1 before the HTML prototype gate completes:** Rejected under `P-NO-DEAD-CODE` and `TEP-015` Section 1.3. Every class, provider, and method created in Phase 1 MUST be wired into and exercised by `lib/ui/` in Phase 1; Phase 3 UI v2 screens can then consume these controllers directly and add view-specific projections once `.agents/prototypes/ui_v2/` is signed off.
- **Enforce the Phase 1 UI import ban via a custom Dart analyzer plugin instead of `tiertask_dev.py`:** Rejected under `P-STDLIB-FIRST` and `TEP-001`. `tiertask_dev.py` already runs Tarjan SCC detection, layer rank validation, and `P-IO-ISOLATION` in under `100 ms` with zero third-party dependencies.

## Part 2: Technical Design & Code Changes

### 2.1 Architecture & Affected Modules

#### Updated Acyclic DAG Layer Ranks (`P-ACYCLIC-DAG`)

| Rank | Path | Allowed Internal Dependencies | Phase 1 Static Rule |
| :--- | :--- | :--- | :--- |
| `0` | `lib/services/app_logger.dart` | None (zero `dart:io`, zero `dart:ffi`, zero `HttpClient`) | Unchanged |
| `1` | `lib/models/*` | Rank `0`..`1` (zero `dart:io`, zero `dart:ffi`, zero `HttpClient`) | Gains `tdf_file_path.dart` |
| `2` | `lib/l10n/*` | Rank `1`..`2` (zero `dart:io`, zero `dart:ffi`, zero `HttpClient`) | Extended `P-IO-ISOLATION` |
| `3` | `lib/services/*` | Rank `0`..`3` (zero `dart:io`, zero `dart:ffi`, zero `HttpClient`) | Extended `P-IO-ISOLATION` |
| `4` | `lib/repositories/*` | Rank `0`..`4` (sole layer permitted `dart:io`, `dart:ffi`, `HttpClient`) | Delegates pure path ops to `TdfFilePath` |
| `5` | `lib/providers/*` | Rank `0`..`5` (zero `dart:io`, zero `dart:ffi`, zero `HttpClient`) | Extended `P-IO-ISOLATION` |
| `6` | `lib/presentation/*` | Rank `0`..`6` (zero `dart:io`, zero `dart:ffi`, zero `HttpClient`) | New layer; owns controllers, derived providers, ViewModels, `UiTelemetry` |
| `7` | `lib/ui/*` | Rank `1`, `2`, `5`, `6`, acyclic `7` (zero `lib/repositories/*`, zero `lib/services/*`, zero `*RepositoryProvider`/`tdfServiceProvider`/`directoryPickerProvider`/`filePickerProvider`/`supportsDirectoryPickerProvider`, zero `dart:io`, zero `dart:ffi`, zero `HttpClient`) | Phase 1 `P-UDF-ARCHITECTURE` boundary enforced by `tiertask_dev.py` |
| `8` | `lib/main.dart` | Rank `0`..`7` (zero `dart:io`, zero `dart:ffi`, zero `HttpClient`) | Unchanged entry wiring |

#### New Production Files (`11` files)
- `lib/models/tdf_file_path.dart`: Stateless `TdfFilePath` pure `.tdf` filename and path utility subsystem.
- `lib/presentation/board_boundary_timer.dart`: Stateless `BoardBoundaryTimer` calculator and auto-disposed `BoardBoundaryTimerNotifier` (`boardBoundaryTimerProvider`).
- `lib/presentation/board_presentation_providers.dart`: `AppVersionViewModel` (`appVersionViewModelProvider`), `TdfPreviewResult` / `TdfPreviewController` (`tdfPreviewControllerProvider`), and `evaluatedBoardProvider`.
- `lib/presentation/label_editor_controller.dart`: `LabelValidationErrorKind`, `LabelValidationResult`, and `LabelEditorController` (`labelEditorControllerProvider`).
- `lib/presentation/link_action_controller.dart`: `LinkOpenOutcome` and `LinkActionController` (`linkActionControllerProvider`).
- `lib/presentation/location_editor_controller.dart`: `LocationValidationErrorKind`, `LocationSourceResolutionResult` (`LocationSourceNotNeeded`, `LocationSourceResolved`, `LocationSourceNeedsDisambiguation`, `LocationSourceResolutionError`), `ValidatedLocationDraft`, `LocationValidationResult`, and `LocationEditorController` (`locationEditorControllerProvider`).
- `lib/presentation/log_viewer_controller.dart`: `DiagnosticLogLevel`, `DiagnosticLogTag`, `DiagnosticLogSeverity`, `DiagnosticLogLineViewModel`, `DiagnosticLogViewModel`, `LogSyncResult`, `ActiveLogFileNameNotifier` (`activeLogFileNameProvider`), and `LogViewerController` (`logViewerControllerProvider`).
- `lib/presentation/settings_controller.dart`: `SettingsPreferenceSaveResult`, `supportsNativeDirectoryPickerProvider`, and `SettingsController` (`settingsControllerProvider`).
- `lib/presentation/task_editor_controller.dart`: Pure schedule/repeat/note/history/board helpers, `ResolvedDueDraft`, `ResolvedSuspendedDraft`, `TaskEditorDraftInput`, `TaskEditorFieldErrors`, `TaskEditorSubmitResult`, and `TaskEditorController` (`taskEditorControllerProvider`).
- `lib/presentation/task_info_controller.dart`: `TaskHistoryMutationResult` (`TaskHistoryMutationCommitted`, `TaskHistoryMutationUnchanged`, `TaskHistoryMutationNotApplied`, `TaskHistoryMutationFailed`) and `TaskInfoController` (`taskInfoControllerProvider`).
- `lib/presentation/ui_telemetry.dart`: Stateless `UiTelemetry` helper encapsulating redacted `AppLogger` (`LogTag.ui`) events.

#### Modified Production, Tooling, Test Helper, & Documentation Files
- **Repositories (`1` file):** `lib/repositories/local_file_operations.dart` (delegates pure path/filename helpers to `TdfFilePath`; `lib/repositories/local_file_repository.dart` remains API-compatible via `LocalFileOperations`).
- **UI Screens & Widgets (`21` files):**
  - `lib/ui/edit_labels_screen.dart`
  - `lib/ui/edit_locations_screen.dart`
  - `lib/ui/edit_task_screen.dart`
  - `lib/ui/home_screen.dart`
  - `lib/ui/settings_screen.dart`
  - `lib/ui/widgets/home_drawer.dart`
  - `lib/ui/widgets/label_color_picker_dialog.dart`
  - `lib/ui/widgets/label_hub_dialog.dart`
  - `lib/ui/widgets/local_tdf_file_dialogs.dart`
  - `lib/ui/widgets/log_viewer_dialog.dart`
  - `lib/ui/widgets/settings_local_storage_section.dart`
  - `lib/ui/widgets/settings_preference_cards.dart`
  - `lib/ui/widgets/task_editor_history_section.dart` (delegates `TaskHistoryInputValidator` pure logic to `TaskEditorController` helpers so Rank `6` never imports Rank `7`)
  - `lib/ui/widgets/task_editor_scheduling_card.dart` (delegates `TaskEditorRepeatField`, `TaskEditorSuspendedField`, and `TaskEditorSchedulingNoteField` pure helpers to `TaskEditorController` helpers)
  - `lib/ui/widgets/task_editor_subtasks_and_blockers.dart` (removes dead `TaskEditorBoardHelper.collectOrderedBlockedByIds`, `collectOrderedLabelIds`, and `validateTitle` helpers superseded by `TaskEditorController`)
  - `lib/ui/widgets/task_info_dialog.dart`
  - `lib/ui/widgets/tier_task_pill.dart`
  - `lib/ui/widgets/tier_task_subtasks_section.dart`
  - `lib/ui/widgets/wipe_tdf_dialog.dart`
  - `lib/ui/widgets/workspace_dialog.dart`
  - `lib/ui/widgets/workspace_row_card.dart`
- **Tooling & Test Harness (`3` files):**
  - `.agents/scripts/tiertask_dev.py`
  - `.agents/scripts/tests/test_tiertask_dev.py`
  - `test/ui/test_helpers.dart` (syncs `appLocaleProvider` with effective `locale` in `pumpLeafWidget`)
- **Documentation (`2` files):**
  - `ARCHITECTURE.md` (adds `Presentation` row in `## Architectural Layers`, new `## Presentation` table, and synced `## Directory Layout`)
  - `AGENTS.md` (updates Section 3 DAG rank order `0..8` and Phase 1 `lib/ui/` repository/service boundary rule)

### 2.2 TDF Schema, Localization & State Changes
- **`spec/TDF_SPEC_0.8.0.md`:** Zero changes.
- **Domain Models & Persistence:** Zero changes to `TaskBoard`, `WebDavConfig`, `SettingsCodec`, `LegacyTtwV2Converter`, or `WorkspaceSyncState` (`TTS\x04`) formats. `lib/models/tdf_file_path.dart` adds only pure path/filename validation and normalization helpers with zero serialized format changes.
- **ARB Localization (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`):** Zero key additions, removals, or wording changes.
- **State Transitions:**
  - `boardBoundaryTimerProvider` (`NotifierProvider.autoDispose<BoardBoundaryTimerNotifier, DateTime?>`) preserves exact `HomeScreenBoundaryTimer` semantics: single active timer clamped to `[25 ms, 7 days]`, pause/cancel on non-`resumed` `AppLifecycleState`, immediate `boundaryTickProvider.increment()` + re-sync on `AppLifecycleState.resumed`, and automatic cancellation on `ref.onDispose`.
  - `logViewerControllerProvider` (`NotifierProvider.autoDispose<LogViewerController, DiagnosticLogViewModel>`) subscribes to `AppLogger.revision` with `ref.onDispose` removal and preserves selected `DiagnosticLogLevel` and `DiagnosticLogTag?` filters across `webDavConfigProvider` updates.
  - `TaskInfoController` preserves rollback-safe post-mutation verification (`P-ATOMIC-STATE`): drafts are cleared and committed telemetry is logged only when post-mutation `taskNotifierProvider` state reflects the added, updated, or removed `TaskHistoryEntry`.

### 2.3 Implementation Details

#### 1. `lib/models/tdf_file_path.dart` (Rank `1`)
Stateless `const TdfFilePath._()` subsystem class importing only `package:flutter/foundation.dart`, `app_workspace.dart`, and `webdav_config.dart`:
- `static String combineDirectoryAndFileName(String directoryPath, String fileName, {String? separator})`
  - Normalizes `directoryPath` with `trimTrailingSeparators`, extracts trailing filename via `extractFileNameFromPath(fileName)`, and joins using `separator ?? (defaultTargetPlatform == TargetPlatform.windows ? r'\' : '/')` without duplicating trailing root slashes (`/` or `C:\`).
- `static String ensureTdfExtension(String rawName)`
  - Returns `WebDavConfig.defaultFileName` when trimmed input is empty, returns input unchanged when length `> 4` and lowercased suffix is `.tdf`, otherwise appends `.tdf`.
- `static String extractDirectoryFromPath(String rawPath)`
  - Preserves POSIX root `/` and Windows drive roots (`C:\`, `C:/`), returns `''` for bare filenames.
- `static String extractFileBaseName(String rawPath)`
  - Strips case-insensitive trailing `.tdf` from `extractFileNameFromPath(rawPath)` when filename length `> 4`.
- `static String extractFileNameFromPath(String rawPath)`
  - Extracts final non-empty segment across `/` and `\` separators, defaulting to `WebDavConfig.defaultFileName`.
- `static bool isAbsolutePath(String rawPath)`
  - Returns `true` for POSIX root `/` or Windows drive prefix (`^[a-zA-Z]:[\\/]`).
- `static bool isValidSingleFileName(String rawName)`
  - Rejects empty, `.`, `..`, `.tdf` (case-insensitive), `/`, `\`, `:`, and control/BiDi characters (`AppWorkspace.hasControlCharacters`).
- `static String trimTrailingSeparators(String path)`
  - Strips trailing `/` and `\` while preserving POSIX root `/` and 3-character Windows drive roots.
- `LocalFileOperations` delegates `combineDirectoryAndFileName` (passing `separator: Platform.pathSeparator`), `ensureTdfExtension`, `extractDirectoryFromPath`, `extractFileBaseName`, `extractFileNameFromPath`, `isAbsolutePath`, `isValidSingleFileName`, and `trimTrailingSeparators` to `TdfFilePath`.

#### 2. `lib/presentation/ui_telemetry.dart` (Rank `6`)
Stateless `const UiTelemetry._()` helper gating all structured `LogTag.ui` events behind `AppLogger.shouldLog(...)` (zero map or string allocations when diagnostics are disabled per `AGENTS.md` Section 6):
- Preserves verbatim event names, log messages, and redacted field keys asserted by existing tests and `tiertask_dev.py log`:
  - `logDialogOpened(String dialogName)` -> `AppLogger.event(LogLevel.info, LogTag.ui, 'ui.dialog.open', fields: {'dialog': dialogName})`
  - `logLabelColorPickerOpened(String? initialHex)` -> `AppLogger.info(LogTag.ui, 'Opened LabelColorPickerDialog initialHex=${initialHex ?? ''}')`
  - `logLabelColorSelected(String selectedHex)` -> `AppLogger.info(LogTag.ui, 'Selected custom label color hex=$selectedHex')`
  - `logLabelHubOpened(String labelId)` -> `ui.label_hub.open` (`id`)
  - `logLabelNoteCopied({required String labelId, required int length})` -> `label.note.copied` (`id`, `length`)
  - `logLocalTdfRenameConfirmed({required String fromFileName, required String toFileName})` / `logLocalTdfSelectConfirmed(String fileName)`
  - `logScreenOpened(String screenName, {String? entityKey, String? entityId})` -> `'Opened $screenName'` or `'Opened $screenName $entityKey=$entityId'` (covering `EditLabelsScreen`, `EditLocationsScreen`, `SettingsScreen`, `EditLabelScreen`, `EditLocationScreen`, and `EditTaskScreen`)
  - `logTaskDetailsToggled({required String taskId, required bool isExpanded})` (`LogLevel.debug`)
  - `logTaskIdCopied(String taskId)` -> `task.id.copied` (`task`)
  - `logTaskInfoDialogOpened({required String taskId, String? initialIndicatorKeyPrefix})` -> `'openTaskInfoDialog id=$taskId indicator=${initialIndicatorKeyPrefix ?? "summary"}'`
  - `logTaskNoteCopied(int length)` -> `task.note.copied` (`length`)
  - `logUndoShortcut({required int stackDepth})` -> `ui.undo.shortcut` (`depth`)
  - `logUndoSnackBarAction({required String taskId, required TaskUndoActionKind kind, required int sequence})` -> `ui.undo.snackbar_action` (`id`, `kind`, `seq`)
  - `logUndoSnackBarShown({required String taskId, required TaskUndoActionKind kind, required int sequence})` -> `ui.undo.snackbar_shown` (`id`, `kind`, `seq`)
  - `logWipeTdfConfirmed({required String targetName, required String fileName, required bool createBackup})`

#### 3. `lib/presentation/link_action_controller.dart` (Rank `6`)
- `enum LinkOpenOutcome { opened, failed }`
- `final linkActionControllerProvider = Provider<LinkActionController>((ref) => LinkActionController(ref.watch(linkLauncherRepositoryProvider)));`
- `class LinkActionController`:
  - `Future<LinkOpenOutcome> openLink(String uri) async`: calls `_repository.openLink(uri)`, returns `LinkOpenOutcome.opened` on success and catches `LinkLaunchException` to return `LinkOpenOutcome.failed`.
- `openTaskResourceLink(BuildContext context, LinkActionController controller, String uri)` in `lib/ui/widgets/tier_task_subtasks_section.dart` switches exhaustively on `LinkOpenOutcome` without importing `LinkLauncherRepository` or `LinkLaunchException`.

#### 4. `lib/presentation/log_viewer_controller.dart` (Rank `6`)
- Presentation enums and immutable view models:
  - `enum DiagnosticLogLevel { debug, info, warn, error, crash }` with `static const List<DiagnosticLogLevel> configurableLevels = [debug, info, warn, error]`, `final String label`, `static DiagnosticLogLevel fromLogLevel(LogLevel level)`, and `LogLevel toLogLevel()`.
  - `enum DiagnosticLogTag { lifecycle, tdf, domain, sync, storage, ui }` with `final String label` and `LogTag toLogTag()`.
  - `enum DiagnosticLogSeverity { normal, warn, error, crash }`
  - `@immutable class DiagnosticLogLineViewModel { const DiagnosticLogLineViewModel({required this.text, required this.severity}); ... }`
  - `@immutable class DiagnosticLogViewModel`: holds `canSyncWebDav`, `errorCount`, `filteredLines` (`List.unmodifiable`), `hasEntries`, `headerSummary` (`'${AppLogger.activeLogFileName} • v${metadata.appVersion} (${metadata.platform}) • ${metadata.workspaceId} • ${AppLogger.minimumLevel.label}'`), `minimumLevel`, `selectedTag`, `totalEntries`, and `warningCount` with value `==` and `hashCode`.
  - `sealed class LogSyncResult` (`LogSyncSucceeded()`, `LogSyncFailed(String message)`).
- `final activeLogFileNameProvider = NotifierProvider.autoDispose<ActiveLogFileNameNotifier, String>(ActiveLogFileNameNotifier.new);`
  - Watches `diagnosticsEnabledProvider`, listens to `AppLogger.revision` (coalescing state refreshes onto a disposal-guarded `scheduleMicrotask` to avoid Riverpod re-entrant provider mutation assertions when another provider logs during `build()`, with listener cleanup in `ref.onDispose`), and exposes `AppLogger.activeLogFileName` for `SettingsScreen` / `SettingsPreferenceCards`.
- `final logViewerControllerProvider = NotifierProvider.autoDispose<LogViewerController, DiagnosticLogViewModel>(LogViewerController.new);`
  - `build()` watches `webDavConfigProvider.select((c) => (c.asData?.value.logStorageMode.usesWebDav ?? false) && (c.asData?.value.isWebDavConfigured ?? false))`, attaches a listener to `AppLogger.revision` (coalescing updates onto a disposal-guarded `scheduleMicrotask`, with cleanup in `ref.onDispose`), and computes the initial `DiagnosticLogViewModel`. `clearLog()` refreshes `state` synchronously after `AppLogger.clear()`.
  - Methods: `void setMinimumLevel(DiagnosticLogLevel level)`, `void setSelectedTag(DiagnosticLogTag? tag)`, `void clearLog()`, `String readFullLogText()`, `Future<LogSyncResult> syncLogToWebDav()` (calls `webDavConfigProvider.notifier.syncLogToWebDavNow()`, returning `LogSyncSucceeded` or catching `Object error` into `LogSyncFailed(AppLogger.sanitize(error.toString()))` so `LogViewerDialog` switches exhaustively with redacted error text and without raw `catch`).
  - Single-pass $O(N)$ line filtering and statistics calculation (ignoring `===` and `@meta ` header lines for entry/warning/error counts and classifying `DiagnosticLogSeverity` per line).

#### 5. `lib/presentation/board_boundary_timer.dart` (Rank `6`)
- Stateless `const BoardBoundaryTimer._()` moving `maxTimerChunk` (`7 days`), `minTimerDelay` (`25 ms`), `clampTimerDelay(Duration rawDelay)`, and `nextBoundaryUtc({required Iterable<TaskItem> tasks, required DateTime nowUtc, required Duration? dueLeadWindow})` out of `lib/ui/home_screen.dart`.
- `final boardBoundaryTimerProvider = NotifierProvider.autoDispose<BoardBoundaryTimerNotifier, DateTime?>(BoardBoundaryTimerNotifier.new);`
  - `build()` registers `AppLifecycleListener(onStateChange: handleAppLifecycleState)`, registers `ref.listen` on `taskNotifierProvider`, `webDavConfigProvider.select((c) => c.asData?.value.dueLeadWindow)`, and `boundaryTickProvider`, registers `ref.onDispose(_disposeResources)`, and returns the initially scheduled UTC boundary after arming `_boundaryTimer` when applicable.
  - Resolves configuration via `ref.read(webDavConfigProvider).asData?.value ?? ref.read(activeWorkspaceProvider).asData?.value.config ?? const WebDavConfig()`, matching `HomeScreen` startup fallback behavior.
  - On timer callback, checks `final normalizedNow = TaskItem.normalizeTimestamp(rawUtcNow)`: when `_scheduledBoundaryUtc case final target? when normalizedNow.isBefore(target)`, re-arms `_boundaryTimer` with `BoardBoundaryTimer.clampTimerDelay(target.difference(rawUtcNow))` without incrementing `boundaryTickProvider`; otherwise clears `_scheduledBoundaryUtc`, emits redacted `ui.boundary_timer.fired`, and calls `ref.read(boundaryTickProvider.notifier).increment()`.
  - `handleAppLifecycleState(AppLifecycleState lifecycleState)`: cancels `_boundaryTimer` when non-`resumed`; sets `_isAppResumed = true`, calls `ref.read(boundaryTickProvider.notifier).increment()`, and re-syncs the timer when `resumed`.
  - Preserves exact redacted `AppLogger.event(LogLevel.debug, LogTag.ui, 'ui.boundary_timer.scheduled', ...)` and `'ui.boundary_timer.fired'` instrumentation.

#### 6. `lib/presentation/board_presentation_providers.dart` (Rank `6`)
- `@immutable class AppVersionViewModel { const AppVersionViewModel({required this.versionLabel, required this.buildSuffix}); factory AppVersionViewModel.fromRawVersion(String rawVersion); ... }`
- `final appVersionViewModelProvider = Provider<AppVersionViewModel>((ref) => AppVersionViewModel.fromRawVersion(ref.watch(appVersionProvider).asData?.value ?? AppVersionRepository.defaultFullVersion));`
- `sealed class TdfPreviewResult` (`TdfPreviewSuccess(String content)`, `TdfPreviewLimitExceeded(String localizedMessage)`).
- `final tdfPreviewControllerProvider = Provider<TdfPreviewController>((ref) => TdfPreviewController(ref));`
  - `TdfPreviewResult serializeBoard(TaskBoard board, {Locale? locale})`: calls `_ref.read(tdfServiceProvider).serialize(board)` and maps `TdfException` to `TdfPreviewLimitExceeded(lookupAppLocalizations(locale ?? _ref.read(appLocaleProvider)).errorLocalFileTooLarge)`.
- `final evaluatedBoardProvider = Provider.autoDispose.family<AsyncValue<TaskBoard>, String?>((ref, activeLabelId) { ... })`:
  - Watches `boundaryTickProvider`, `taskNotifierProvider`, `locationStateProvider.select((s) => s.status == LocationStatus.found ? s.fix : null)`, `webDavConfigProvider.select((c) => c.asData?.value ?? const WebDavConfig())`, and `clockProvider`, returning `boardAsync.whenData((board) => board.evaluateForContext(...))`, and automatically disposes unused `activeLabelId` family instances.

#### 7. `lib/presentation/settings_controller.dart` (Rank `6`)
- `sealed class SettingsPreferenceSaveResult` (`SettingsPreferenceSaved(WebDavConfig effectiveConfig)`, `SettingsPreferenceSaveFailed(String localizedMessage)`).
- `final supportsNativeDirectoryPickerProvider = Provider<bool>((ref) => ref.watch(supportsDirectoryPickerProvider));` (reactive wrapper so `SettingsScreen` watches directory-picker capability without referencing `supportsDirectoryPickerProvider` directly).
- `final settingsControllerProvider = Provider<SettingsController>((ref) => SettingsController(ref));`
- Methods on `SettingsController`:
  - `static DiagnosticLogLevel readLogLevel(WebDavConfig config) => DiagnosticLogLevel.fromLogLevel(config.logLevel);`
  - `static WebDavConfig withLogLevel(WebDavConfig config, DiagnosticLogLevel level) => config.copyWith(logLevel: level.toLogLevel());`
  - `bool get supportsNativeDirectoryPicker => _ref.read(supportsDirectoryPickerProvider);`
  - `String? consumeStartupRecoveryNotice({Locale? locale})`: reads `_ref.read(settingsRepositoryProvider).takeLastRecoveryNotice()` and returns the localized notice text for `SettingsRecoveryKind` via `lookupAppLocalizations`, or `null` when no notice is pending.
  - `String? resolvePreviewLocalPath(WebDavConfig config)`: resolves path via `LocalFileRepository(config: config, baseDirectoryPath: ..., buildProfile: ...).tryResolveFilePath()`.
  - `List<String> listLocalTdfFileNames()`: delegates to `_ref.read(localFileRepositoryProvider).listTdfFileNamesInDirectory()`.
  - `Future<String?> pickLocalDirectory(WebDavConfig config)`: resolves the current directory and filename internally via `LocalFileRepository`, opens `directoryPickerProvider`, and returns `LocalFileRepository.combineDirectoryAndFileName(selectedDirectory, currentFileName)` (delegating to `TdfFilePath` with `Platform.pathSeparator`) or `null` if cancelled/unchanged.
  - `Future<String?> pickNativeLocalFile(WebDavConfig config)`: resolves the current directory and filename internally via `LocalFileRepository` and opens `filePickerProvider`.
  - `String resolveChosenLocalFileName(WebDavConfig config, String chosenFileName)`: joins the internally resolved directory and `chosenFileName` via `LocalFileRepository.combineDirectoryAndFileName` (delegating to `TdfFilePath` with `Platform.pathSeparator`) when a directory separator or base storage directory exists, otherwise returns `chosenFileName`.
  - `Future<SettingsPreferenceSaveResult> savePreferenceChange({required WebDavConfig previous, required WebDavConfig next, Locale? locale})`: diffs `diagnosticsEnabled`, `dueLeadWindow`, `localWatchEnabled`, `logLevel`, and `logStorageMode`, routes to the specialized `WebDavConfigNotifier` mutation (`updateDiagnosticsEnabled`, `updateDueLeadWindow`, `updateLocalWatchEnabled`, `updateLogLevel`, `updateLogStorageMode`, or `updateConfig`), returns `SettingsPreferenceSaved(effectiveConfig)`, and maps `WorkspaceException` via `localizeWorkspaceError`.
- **Legacy Settings UI Adapter Updates:**
  - `SettingsScreen` watches `supportsNativeDirectoryPickerProvider` and `activeLogFileNameProvider`, passes `activeLogFileName` into `SettingsPreferenceCards`, and delegates `_handlePreferenceChanged` persistence diffing to `SettingsController.savePreferenceChange` (so `settings_screen.dart` never references `config.logLevel`).
  - `SettingsPreferenceCards` accepts `required String activeLogFileName` (and forwards it plus `SettingsController.readLogLevel(config)` / `SettingsController.withLogLevel(config, value)` into `DiagnosticsSelectionCard`), and `DiagnosticsSelectionCard` accepts `DiagnosticLogLevel selectedLogLevel`, `ValueChanged<DiagnosticLogLevel> onLogLevelChanged`, and `required String activeLogFileName`.
  - `LocalStorageSection.pickLocalFilePath` extracts `currentName` via `TdfFilePath.extractFileNameFromPath(config.localFilePath)` and delegates picker and path-resolution actions to `SettingsController`.

#### 8. `lib/presentation/location_editor_controller.dart` (Rank `6`)
- `enum LocationValidationErrorKind { emptyName, invalidCoordinates, invalidRadius }`
- `sealed class LocationSourceResolutionResult`:
  - `LocationSourceNotNeeded()` (returned immediately when `sourceType == LocationSourceType.gps`)
  - `LocationSourceResolved({required double latitude, required double longitude, required String normalizedSource, required LocationSourceType sourceType})`
  - `LocationSourceNeedsDisambiguation({required List<GeocodingCandidate> candidates, required LocationSourceType sourceType, String? shortPlusCode, String? localityQuery})`
  - `LocationSourceResolutionError(String localizedMessage)`
- `@immutable class ValidatedLocationDraft` and `@immutable class LocationValidationResult`.
- `final locationEditorControllerProvider = Provider<LocationEditorController>((ref) => LocationEditorController(ref));`
- Methods:
  - `LocationSourceType classifySource(String? rawSource)` (delegates to `PlusCodeService.classifySource`)
  - `String formatGpsCoordinate(double value)` / `bool isValidCoordinates(double latitude, double longitude)` / `bool isValidRadius(double radius)` / `double? parseRadiusInput(String rawRadius)`
  - `Future<LocationSourceResolutionResult> resolveSource({required LocationSourceType sourceType, required String rawSource, Locale? locale})`: returns `LocationSourceNotNeeded` for `LocationSourceType.gps`, enforces `PlusCodeService.maxInputLength` upfront (`P-BOUND-ALLOC`), handles `LocationSourceType.address` via `locationRepositoryProvider.searchLocations(...)`, and handles `LocationSourceType.plusCode` via exhaustive `switch (PlusCodeService.parseInput(...))` (decoding full Plus Codes offline and geocoding locality references for short Plus Codes).
  - `LocationSourceResolutionResult applyDisambiguatedCandidate({required GeocodingCandidate candidate, required LocationSourceType sourceType, String? shortPlusCode, String? localityQuery, Locale? locale})`: applies address candidate directly or runs `PlusCodeService.recoverNearest` + `PlusCodeService.decode` + `PlusCodeService.truncateToMaxTextLength` for short Plus Codes.
  - `Future<({double latitude, double longitude})?> resolveCurrentGpsPosition()`: reads `locationStateProvider.fix`, triggers `refreshLocation()` when coordinates are absent, and returns `(latitude, longitude)`.
  - `LocationValidationResult validateDraft(...)`
  - `Future<void> saveLocation({required String locationId, required ValidatedLocationDraft draft})`
  - `Future<void> createLocationFromCurrentFix(String rawName)`: ignores empty/whitespace-only names, reads current `locationStateProvider.fix`, rounds coordinates to 6 decimals via `TdfLocation.formatRoundedDouble` (defaulting to `0.0`), and delegates to `taskNotifierProvider.notifier.addLocation(trimmed, latitude: latitude, longitude: longitude, radiusMeters: 100.0)`.
  - `Future<void> deleteLocation(String locationId)`.

#### 9. `lib/presentation/label_editor_controller.dart` (Rank `6`)
- `enum LabelValidationErrorKind { emptyName, duplicateName, invalidColor }`
- `@immutable class LabelValidationResult`
- `final labelEditorControllerProvider = Provider<LabelEditorController>((ref) => LabelEditorController(ref));`
- Methods:
  - `LabelValidationResult validateLabel({required TaskBoard board, required String labelId, required String rawName, required String rawColor, Locale? locale})`: enforces non-empty name (`labelNameErrorEmpty`), case-insensitive uniqueness excluding `labelId` (`labelNameErrorDuplicate`), and optional `#RRGGBB` normalization via `TdfColor.normalizeHex` (`labelColorErrorInvalid`).
  - `Future<void> saveLabel(...)`: emits redacted `AppLogger.event(LogLevel.info, LogTag.ui, 'ui.label_editor.save', fields: {'id': labelId, 'links': links.length, 'scoped': isScoped})` and delegates to `taskNotifierProvider.notifier.updateLabel(...)`.
  - `Future<void> addLabel(String name)` and `Future<void> deleteLabel(String labelId)`.

#### 10. `lib/presentation/task_editor_controller.dart` (Rank `6`)
- Pure static helpers (reused via delegation by `lib/ui/widgets/task_editor_scheduling_card.dart`, `task_editor_history_section.dart`, and `task_editor_subtasks_and_blockers.dart` so Rank `6` never imports Rank `7`):
  - `formatLocalTimestamp(DateTime? instantUtc, WebDavConfig configuration)`
  - `formatInitialSuspendedText(DateTime? suspendedAtUtc, WebDavConfig configuration)`
  - `tryParseLocalDateTimeInput(String rawInput, WebDavConfig configuration)`
  - `parseRepeatCount({required bool isRepeating, required String rawCount})`
  - `parseLeadDays({required bool hasDue, required bool isRepeating, required String rawLeadDays})`
  - `parseRepeatRule({TdfRepeatClock existingClock, bool hasDue, required bool isRepeating, required String rawCount, String rawLeadDays, required RepeatUnit unit})`
  - `normalizeSchedulingNote(String rawText)` / `validateSchedulingNote(String? note, AppLocalizations localizations)`
  - `sanitizeHistoryText(String rawText)` / `resolveHistoryTimestampUtc(...)` / `validateHistoryText(String text, AppLocalizations localizations)`
  - `validateTaskTitle({required TaskBoard board, required String rawTitle, required String? excludingTaskId, required AppLocalizations localizations})`
  - `collectOrderedBlockedByIds(TaskBoard board, Set<String> selectedBlockedByIds)` / `collectOrderedLabelIds(TaskBoard board, Set<String> selectedLabelIds)`
- Immutable input/output value classes: `ResolvedDueDraft`, `ResolvedSuspendedDraft`, `TaskEditorDraftInput`, `TaskEditorFieldErrors`, and `sealed class TaskEditorSubmitResult`:
  - `TaskEditorSubmitted()`
  - `TaskEditorValidationFailed(TaskEditorFieldErrors errors)`
  - `TaskEditorPersistFailed({required TaskEditorFieldErrors errors, List<TaskHistoryEntry>? committedHistoryEntries, List<TaskLink>? committedLinks})` (returns normalized `committedHistoryEntries` and/or `committedLinks` when pending history or link drafts were folded in before persistence rejected, matching existing `EditTaskScreen` behavior).
- `TaskEditorDraftInput` accepts optional `pendingLinkTitle` and `pendingLinkUri` so `TaskEditorController.submitDraft` validates all primary fields before validating and folding any pending link input (preserving exact validation precedence without premature widget-state mutation).
- `final taskEditorControllerProvider = Provider<TaskEditorController>((ref) => TaskEditorController(ref));`
- Methods:
  - `DateTime currentLocalWallClock(WebDavConfig configuration)`
  - `ResolvedDueDraft resolveDueDraft(...)` and `bool shouldResetAutoPrioritizeDue(...)`
  - `ResolvedSuspendedDraft resolveSuspendedDraft(...)`
  - `({TaskHistoryEntry? candidate, String? error}) resolvePendingHistoryCandidate(...)` (accepts nullable `String? editingHistoryInitialTimestampText` matching `TaskEditorDraftInput.editingHistoryInitialTimestampText` and `EditTaskScreen`)
  - `Future<TaskEditorSubmitResult> submitDraft(TaskEditorDraftInput input, {Locale? locale})`: validates all fields against `maxTdfNoteLength`, `maxTdfTextLength` (history text), `maxTdfHistoryPerTask`, `TaskRepeatRule.maxRepeatCount`, and Mode 2 `leadDays` (`0..3650`), emits redacted `ui.edit_task.validation_failed` on validation failure, persists via `TaskNotifier.addTask`/`updateTask`, catches `TdfException` / `TdfContextException` / `FormatException` to emit redacted `ui.edit_task.persist_rejected` and return `TaskEditorPersistFailed`, or emits redacted `ui.edit_task.saved` and returns `TaskEditorSubmitted`.
  - `Future<void> deleteTask(String taskId)`: emits redacted `ui.delete_task.confirmed` and calls `TaskNotifier.deleteTask(taskId)`.

#### 11. `lib/presentation/task_info_controller.dart` (Rank `6`)
- `sealed class TaskHistoryMutationResult`:
  - `TaskHistoryMutationCommitted()` (post-mutation `taskNotifierProvider` state verified the added, updated, or removed entry)
  - `TaskHistoryMutationUnchanged()` (inline edit matched original text before or after single-line sanitization; caller exits inline edit mode cleanly)
  - `TaskHistoryMutationNotApplied()` (task no longer present on board, or persistence rolled back leaving prior history state intact; caller preserves draft input)
  - `TaskHistoryMutationFailed(String localizedMessage)` (validation or domain persistence error; caller displays inline error)
- `final taskInfoControllerProvider = Provider<TaskInfoController>((ref) => TaskInfoController(ref));`
- Methods:
  - `bool isTaskOnBoard(String taskId)`
  - `Future<TaskHistoryMutationResult> appendHistoryEntry({required TaskItem currentTask, required String rawText, Locale? locale})`: resolves the live board task via `_findTask(currentTask.id)`, sanitizes text, validates via `TaskEditorController.validateHistoryText`, verifies `TdfCalendar.isWithinTimestampBounds(timestampUtc)` and `!liveTask.history.contains(candidate) && liveTask.history.length >= maxTdfHistoryPerTask` pre-checks against live board state before mutating, checks post-mutation board state (`postTask.history.contains(candidate)`), and emits redacted telemetry (`ui.task_info.history_validation_failed` with reason codes `'unpaired_surrogate'`, `'control_char'`, `'empty_text'`, `'text_too_long'`, `'invalid_timestamp'`, `'max_exceeded'`; `ui.task_info.history_persist_rejected`; `ui.task_info.history_added`).
  - `Future<TaskHistoryMutationResult> updateHistoryEntry({required String taskId, required TaskHistoryEntry originalEntry, required String rawText, Locale? locale})`: returns `TaskHistoryMutationUnchanged` when raw or sanitized text equals `originalEntry.text`, preserves `originalEntry.timestampUtc`, verifies post-mutation commit (`postTask.history.contains(replacement)`), and emits `ui.task_info.history_updated` / validation / rejection telemetry.
  - `Future<TaskHistoryMutationResult> deleteHistoryEntry({required String taskId, required TaskHistoryEntry entry, Locale? locale})`: verifies post-mutation removal (`!postTask.history.contains(entry)`) and emits `ui.task_info.history_removed` / rejection telemetry.
  - Pure formatting helpers: `formatRemainingDuration(Duration difference, AppLocalizations localizations)` and `differsFromWallClock(TdfLocalDateTime anchor, DateTime localWallClock)`.

#### 12. Tooling Updates (`.agents/scripts/tiertask_dev.py`)
1. **`_lib_layer_rank(rel_path)`:** Update ranks to `0` (`lib/services/app_logger.dart`), `1` (`lib/models/`), `2` (`lib/l10n/`), `3` (`lib/services/`), `4` (`lib/repositories/`), `5` (`lib/providers/`), `6` (`lib/presentation/`), `7` (`lib/ui/`), `8` (`lib/main.dart`).
2. **`_check_acyclic_dag(root)`:**
   - Retain Tarjan SCC cycle detection (`0` SCCs) and `src_rank < dst_rank` upward import check.
   - Add Phase 1 UI boundary check (`P-UDF-ARCHITECTURE`): for every `src` starting with `lib/ui/`, reject any direct import `dst` starting with `lib/repositories/` or `lib/services/`.
3. **`run_static_checks(root, fix=False)`:**
   - Extend `P-IO-ISOLATION`: for every `rel` starting with `lib/` and NOT starting with `lib/repositories/`, reject both `dart:io` and `dart:ffi` imports.
   - Add Phase 1 transitive repository, service, and native-picker provider check (`P-UDF-ARCHITECTURE`): for every `rel` starting with `lib/ui/`, reject non-comment references to `appVersionRepositoryProvider`, `directoryPickerProvider`, `filePickerProvider`, `linkLauncherRepositoryProvider`, `localFileRepositoryProvider`, `locationRepositoryProvider`, `settingsRepositoryProvider`, `supportsDirectoryPickerProvider`, `tdfServiceProvider`, and `webDavRepositoryProvider`.
4. **`_layer_section_for_path(rel_path)`:** Map `lib/presentation/` to `## Presentation`.
5. **`_build_parser()` (`find --layer`):** Document `presentation` in `--layer` help string (`find_in_repo` already supports `lib/<layer>` and `test/<layer>`).
6. **`compute_dependencies` (`app_hubs`):** Add `lib/presentation/ui_telemetry.dart` to `app_hubs` so leaf dependency analysis stays focused while `test/presentation/ui_telemetry_test.dart` directly covers `ui_telemetry.dart`.

### 2.4 Testing Strategy
Follow strict Red-Green-Refactor TDD (`P-TDD-FIRST`) with new unit test suites mirroring every new `lib/` file plus Python CLI tests and full regression verification:

1. **`test/models/tdf_file_path_test.dart`** (`M-URI-PATH-EDGE-TESTS`, `M-DELIM-INJECT-TESTS`, `M-EXTREME-BOUND-TESTS`):
   - `ensureTdfExtension` (empty, whitespace, already `.tdf`, uppercase `.TDF`, `.tdf` bare name, multi-dot names).
   - `extractFileNameFromPath`, `extractFileBaseName`, `extractDirectoryFromPath`, `trimTrailingSeparators`, `isAbsolutePath`, and `combineDirectoryAndFileName` across POSIX roots (`/`), Windows drive roots (`C:\`, `C:/`), mixed `/` and `\` separators, repeated slashes, trailing slashes, and explicit separator overrides.
   - `isValidSingleFileName` rejecting empty, whitespace, `.`, `..`, `.tdf`, `/`, `\`, `:`, null bytes (`\x00`), C0/C1 control characters, and Unicode BiDi override characters (`\u202E`, `\u2066`).
2. **`test/presentation/board_boundary_timer_test.dart`** (`M-EXTREME-BOUND-TESTS`, `M-REAL-MECHANICS-TESTS`):
   - Initializes `TestWidgetsFlutterBinding.ensureInitialized()` for `AppLifecycleListener`.
   - `BoardBoundaryTimer.clampTimerDelay` (`<= 0`, `24 ms`, `25 ms`, `7 days`, `> 7 days`).
   - `BoardBoundaryTimer.nextBoundaryUtc` across completed tasks, `suspended forever`, past vs future `suspendedAt`, `dueAt` with active/passive lead windows, and `9999-12-31 23:59:59Z` far-future clamping.
   - `boardBoundaryTimerProvider` lifecycle pause/resume, `activeWorkspaceProvider` config fallback while `webDavConfigProvider` loads, `boundaryTickProvider` increment on firing and resume, intermediate chunk re-arming without spurious ticks, `ref.onDispose` timer cancellation, and redacted `ui.boundary_timer.*` log emission.
3. **`test/presentation/board_presentation_providers_test.dart`** (`M-EXHAUSTIVE-STATE-TESTS`, `M-EXTREME-BOUND-TESTS`):
   - `AppVersionViewModel.fromRawVersion` (with and without `v`/`V` prefix, with and without `+build`, fallback to `AppVersionRepository.defaultFullVersion`).
   - `TdfPreviewController.serializeBoard` covering both `TdfPreviewSuccess` and `TdfPreviewLimitExceeded` (`en` and `de` locales via `lookupAppLocalizations`).
   - `evaluatedBoardProvider` reacting to `activeLabelId`, `locationStateProvider` found vs unavailable fixes, `boundaryTickProvider`, `DueLeadWindow`, and `clockProvider`.
4. **`test/presentation/link_action_controller_test.dart`** (`M-EXHAUSTIVE-STATE-TESTS`, `M-URI-PATH-EDGE-TESTS`):
   - Exhaustive `LinkOpenOutcome` (`opened` for valid URI via `FakeLinkLauncherRepository`; `failed` on `LinkLaunchException` and invalid URIs).
5. **`test/presentation/log_viewer_controller_test.dart`** (`M-EXHAUSTIVE-STATE-TESTS`, `M-DELIM-INJECT-TESTS`, `M-REAL-MECHANICS-TESTS`):
   - Exhaustive `DiagnosticLogLevel` round-trip mappings to/from `LogLevel`, 1-to-1 `DiagnosticLogTag.toLogTag()` coverage against `LogTag.values`, exhaustive `DiagnosticLogSeverity` classification (`normal`, `warn`, `error`, `crash`, `RECOVERED UNCLEAN EXIT`), and exhaustive `LogSyncResult` (`LogSyncSucceeded`, `LogSyncFailed` with secret redaction via `AppLogger.sanitize`).
   - Live updates on `AppLogger.revision`, `headerSummary` formatting, stats counting excluding `===` and `@meta `, filter persistence across `webDavConfigProvider` updates, `clearLog`, `readFullLogText`, `canSyncWebDav` gating, `activeLogFileNameProvider` reactivity, and listener cleanup on container disposal.
6. **`test/presentation/settings_controller_test.dart`** (`M-EXHAUSTIVE-STATE-TESTS`, `M-URI-PATH-EDGE-TESTS`):
   - `readLogLevel`/`withLogLevel` round-trip for every configurable `DiagnosticLogLevel`, plus `supportsNativeDirectoryPickerProvider`.
   - `consumeStartupRecoveryNotice` for `null`, `SettingsRecoveryKind.recoveredFromBackup`, and `SettingsRecoveryKind.resetAfterQuarantine` in both `en` and `de`.
   - `resolvePreviewLocalPath`, `listLocalTdfFileNames`, `pickLocalDirectory`, `pickNativeLocalFile`, `resolveChosenLocalFileName`, and `savePreferenceChange` (`SettingsPreferenceSaved` and `SettingsPreferenceSaveFailed` on `WorkspaceException`).
7. **`test/presentation/location_editor_controller_test.dart`** (`M-EXHAUSTIVE-STATE-TESTS`, `M-EXTREME-BOUND-TESTS`):
   - Exhaustive `LocationSourceType` (`gps`, `address`, `plusCode`) and `LocationSourceResolutionResult` (`NotNeeded`, `Resolved`, `NeedsDisambiguation`, `Error`) coverage: full Plus Code offline decoding, short Plus Code geocoding + `recoverNearest` (single candidate and disambiguated multi-candidate), address forward geocoding (`0`, `1`, `N` candidates), `PlusCodeService.maxInputLength` boundary (`max`, `max + 1`), `parseRadiusInput` (`m`, `km`, `<= 0`, `> 100000`, `NaN`), coordinate bounds (`-90..90`, `-180..180`), GPS lookup refresh fallback, and `createLocationFromCurrentFix` 6-decimal rounding and `100.0` default radius.
8. **`test/presentation/label_editor_controller_test.dart`** (`M-EXHAUSTIVE-STATE-TESTS`):
   - Exhaustive `LabelValidationErrorKind` (`emptyName`, `duplicateName`, `invalidColor`), case-insensitive duplicate exclusion for self, `saveLabel` persistence + redacted `ui.label_editor.save` telemetry, `addLabel`, and `deleteLabel`.
9. **`test/presentation/task_editor_controller_test.dart`** (`M-EXHAUSTIVE-STATE-TESTS`, `M-EXTREME-BOUND-TESTS`, `M-DELIM-INJECT-TESTS`, `M-REAL-MECHANICS-TESTS`):
   - Due and suspended draft resolution (`due.anchor` preservation vs regeneration, `passive` auto-reset on edited due timestamp, `suspended forever`, invalid timestamps) and `parseRepeatCount`/`parseLeadDays`/`parseRepeatRule` helpers.
   - `maxTdfNoteLength`, `maxTdfTextLength` (history entry text), `maxTdfHistoryPerTask`, `TaskRepeatRule.maxRepeatCount`, and Mode 2 `leadDays` (`0..3650`) bounds; inline control-character / single-line history sanitization.
   - Exhaustive `TaskEditorSubmitResult` (`Submitted`, `ValidationFailed`, `PersistFailed` with `committedHistoryEntries` across `TdfException`, `TdfContextException`, and `FormatException`) plus redacted `ui.edit_task.*` and `ui.delete_task.confirmed` telemetry verification (asserting zero note or history text leakage).
10. **`test/presentation/task_info_controller_test.dart`** (`M-EXHAUSTIVE-STATE-TESTS`, `M-EXTREME-BOUND-TESTS`, `M-REAL-MECHANICS-TESTS`):
    - Append, inline update (preserving `timestampUtc`), and delete history entries covering all four `TaskHistoryMutationResult` variants (`Committed`, `Unchanged`, `NotApplied` on missing task or rollback, `Failed` across `emptyText`, `limitExceeded`, `unexpectedToken`, `invalid_timestamp`, `max_exceeded`, and `FormatException`), redacted `ui.task_info.history_*` telemetry with exact reason codes, and `formatRemainingDuration` / `differsFromWallClock` edge cases.
11. **`test/presentation/ui_telemetry_test.dart`** (`M-EXHAUSTIVE-STATE-TESTS`):
    - Verifies no-op invariant when `AppLogger.isEnabled == false` and verifies exact redacted event format and keys when enabled (asserting no sensitive text is logged).
12. **`.agents/scripts/tests/test_tiertask_dev.py`:**
    - Verifies `_lib_layer_rank` ordering (`0..8`), rejection of upward `presentation -> ui` and `providers -> presentation` imports, rejection of `lib/ui/* -> lib/repositories/*` and `lib/ui/* -> lib/services/*` (including `app_logger.dart`), rejection of forbidden repository/service/native-picker provider names in `lib/ui/*`, rejection of `dart:io` and `dart:ffi` in `lib/presentation/*` and `lib/providers/*`, `_layer_section_for_path` mapping `lib/presentation/` to `## Presentation`, and `find --layer presentation`.
13. **Existing Suite Regression & I/O Boundary (`M-IO-TESTS`):**
    - External I/O remains strictly inside `lib/repositories/` and covered by existing `test/repositories/` suites; all existing `test/models/`, `test/services/`, `test/repositories/`, `test/providers/`, and `test/ui/` suites must remain `100%` green via `python3 .agents/scripts/tiertask_dev.py verify --full --fix` and `python3 -m unittest discover -s .agents/scripts/tests`.

## Part 3: Implementation Record & Tasks

### 3.1 Task Breakdown
- [x] Run `python3 .agents/scripts/tiertask_dev.py verify --fast` and `python3 -m unittest discover -s .agents/scripts/tests` to confirm a clean baseline.
- [x] Write failing unit tests for `TdfFilePath` (`test/models/tdf_file_path_test.dart`), implement `lib/models/tdf_file_path.dart`, and delegate matching pure path helpers in `lib/repositories/local_file_operations.dart`.
- [x] Write failing unit tests and implement foundational presentation modules (`ui_telemetry.dart`, `link_action_controller.dart`, `log_viewer_controller.dart`, `board_boundary_timer.dart`, `board_presentation_providers.dart`).
- [x] Write failing unit tests and implement screen/dialog controllers (`settings_controller.dart`, `location_editor_controller.dart`, `label_editor_controller.dart`, `task_editor_controller.dart`, `task_info_controller.dart`).
- [x] Synchronize `appLocaleProvider` in `test/ui/test_helpers.dart` (`pumpLeafWidget`) and migrate all `21` affected `lib/ui/` files onto `lib/models/tdf_file_path.dart` and `lib/presentation/*` with zero visual or behavioral regressions.
- [x] Write failing Python unit tests in `.agents/scripts/tests/test_tiertask_dev.py` and update `.agents/scripts/tiertask_dev.py` (Ranks `0..8`, `P-IO-ISOLATION`, Phase 1 `P-UDF-ARCHITECTURE` `lib/ui/` boundary checks, `## Presentation`, `--layer presentation`, and `app_hubs`).
- [x] Update Parts 1 and 2 if implementation reveals any required signature adjustments.
- [x] Synchronize `ARCHITECTURE.md` (`## Architectural Layers`, `## Presentation`, `## Directory Layout`) and `AGENTS.md` (Section 3 DAG order and `lib/ui/` boundary rule) per **`update-documentation`**.
- [x] Run `python3 .agents/scripts/tiertask_dev.py verify --full --fix` and `python3 -m unittest discover -s .agents/scripts/tests` until all static checks, analyzer checks, Dart tests, and Python CLI tests pass with zero warnings.
- [x] Verify `CHANGELOG.md` requires no entry (internal architectural refactoring only, per **`changelog-updater`**).
- [x] Set `status: review`, update `BOARD.md`, and request user approval.
- [x] After user approval, set `status: completed`, update `BOARD.md`, mark Phase 1 complete in `TEP-015`, and list delivered artifacts in Part 3.3.

### 3.2 Work Log & Decisions
- **2026-11-21:** Audited all `lib/ui/` imports and provider references against `TEP-015` Phase 1 exit gates (`10` repository-importing UI files, `12` service-importing UI files, `17` distinct files plus transitive repository/service provider usages) and drafted `TEP-016`. Decided to keep `LogLevel`/`LogTag` in Rank `0` `app_logger.dart` while exposing `DiagnosticLogLevel`/`DiagnosticLogTag` in `lib/presentation/log_viewer_controller.dart`, to enforce both direct import and transitive repository/service provider bans in `tiertask_dev.py`, and to synchronize `appLocaleProvider` inside `pumpLeafWidget` so German leaf tests remain consistent.
- **2026-11-21:** Implemented all `11` new `lib/` modules (`lib/models/tdf_file_path.dart` and `10` Rank `6` `lib/presentation/*.dart` modules) with `11` mirroring Dart unit test suites, migrated all `21` affected `lib/ui/` files plus `lib/repositories/local_file_operations.dart` and `test/ui/test_helpers.dart`, enforced DAG Ranks `0..8`, extended `P-IO-ISOLATION` (`dart:io` and `dart:ffi` forbidden everywhere in `lib/` outside `lib/repositories/`), and Phase 1 `P-UDF-ARCHITECTURE` `lib/ui/` import/provider bans in `.agents/scripts/tiertask_dev.py` with Python tests in `.agents/scripts/tests/test_tiertask_dev.py`, and synchronized `ARCHITECTURE.md` and `AGENTS.md`. Resolved a Riverpod `3.5.0` re-entrancy failure in `ActiveLogFileNameNotifier` and `LogViewerController` (triggered when `diagnosticsEnabledProvider` or `evaluatedBoardProvider` logs synchronously inside `build()`) by coalescing `AppLogger.revision` listener updates onto a disposal-guarded `scheduleMicrotask` and codified a regression test in `test/presentation/log_viewer_controller_test.dart`. Aligned `.agents/scripts/tests/test_tiertask_dev.py` `sys.path` bootstrapping and mirror-test dependency expectations so `python3 -m unittest discover -s .agents/scripts/tests` runs cleanly from repository root. Verified `CHANGELOG.md` requires no entry (internal refactoring only). Passed `verify --full --fix` (`+513` Dart tests, `0` analyzer issues, `0` static/DAG/UI-boundary/L10N/ARCH issues) and `13/13` Python CLI tests; moved `TEP-016` to `review`.
- **2026-11-21:** Audited the `TEP-016` implementation against both `TEP-016` and `TEP-015` and fixed five real defects via Red-Green-Refactor TDD: (1) switched `SettingsController.pickLocalDirectory` and `resolveChosenLocalFileName` to `LocalFileRepository.combineDirectoryAndFileName` (delegating to `TdfFilePath` with `Platform.pathSeparator`) so Windows host test runners (`defaultTargetPlatform == TargetPlatform.android`) and runtimes never emit mismatched `/` separators; (2) converted `evaluatedBoardProvider` to `Provider.autoDispose.family` to eliminate unbounded caching and subscription retention for dynamic `activeLabelId` values; (3) moved pending link validation/folding into `TaskEditorController.submitDraft` (`pendingLinkTitle`/`pendingLinkUri` on `TaskEditorDraftInput`, `committedLinks` on `TaskEditorPersistFailed`) so primary field validation runs before pending link flushing without prematurely mutating `_links` in `EditTaskScreen`; (4) removed dead code (`DiagnosticLogTag.fromLogTag` in `log_viewer_controller.dart` and unused `TaskEditorBoardHelper` wrappers in `task_editor_subtasks_and_blockers.dart`) per `P-NO-DEAD-CODE`; (5) redacted `LogSyncFailed` messages via `AppLogger.sanitize` and verified `TaskInfoController.appendHistoryEntry` max-history bounds against live board state instead of caller snapshots. Finalized `TEP-016` as `completed`, updated `BOARD.md`, and marked Phase 1 complete in `TEP-015`.

### 3.3 Delivered Artifacts
- **Pure `.tdf` Path Subsystem (`lib/models/`):**
  - `lib/models/tdf_file_path.dart` (`TdfFilePath`)
  - `lib/repositories/local_file_operations.dart` (delegation of pure path/filename utilities to `TdfFilePath`)
- **Presentation Layer (`lib/presentation/`, Rank `6`):**
  - `lib/presentation/board_boundary_timer.dart` (`BoardBoundaryTimer`, `BoardBoundaryTimerNotifier`, `boardBoundaryTimerProvider`)
  - `lib/presentation/board_presentation_providers.dart` (`AppVersionViewModel`, `appVersionViewModelProvider`, `evaluatedBoardProvider`, `TdfPreviewController`, `TdfPreviewResult`, `tdfPreviewControllerProvider`)
  - `lib/presentation/label_editor_controller.dart` (`LabelEditorController`, `LabelValidationErrorKind`, `LabelValidationResult`, `labelEditorControllerProvider`)
  - `lib/presentation/link_action_controller.dart` (`LinkActionController`, `LinkOpenOutcome`, `linkActionControllerProvider`)
  - `lib/presentation/location_editor_controller.dart` (`LocationEditorController`, `LocationSourceResolutionResult`, `LocationValidationErrorKind`, `LocationValidationResult`, `ValidatedLocationDraft`, `locationEditorControllerProvider`)
  - `lib/presentation/log_viewer_controller.dart` (`LogViewerController`, `ActiveLogFileNameNotifier`, `DiagnosticLogLevel`, `DiagnosticLogTag`, `DiagnosticLogSeverity`, `DiagnosticLogLineViewModel`, `DiagnosticLogViewModel`, `LogSyncResult`, `activeLogFileNameProvider`, `logViewerControllerProvider`)
  - `lib/presentation/settings_controller.dart` (`SettingsController`, `SettingsPreferenceSaveResult`, `settingsControllerProvider`, `supportsNativeDirectoryPickerProvider`)
  - `lib/presentation/task_editor_controller.dart` (`TaskEditorController`, `TaskEditorDraftInput`, `TaskEditorFieldErrors`, `TaskEditorSubmitResult`, `ResolvedDueDraft`, `ResolvedSuspendedDraft`, `taskEditorControllerProvider`)
  - `lib/presentation/task_info_controller.dart` (`TaskInfoController`, `TaskHistoryMutationResult`, `taskInfoControllerProvider`)
  - `lib/presentation/ui_telemetry.dart` (`UiTelemetry`)
- **Decoupled UI Layer (`lib/ui/`, Rank `7`):**
  - Migrated `21` files across `lib/ui/` and `lib/ui/widgets/` (`edit_labels_screen.dart`, `edit_locations_screen.dart`, `edit_task_screen.dart`, `home_screen.dart`, `settings_screen.dart`, `home_drawer.dart`, `label_color_picker_dialog.dart`, `label_hub_dialog.dart`, `local_tdf_file_dialogs.dart`, `log_viewer_dialog.dart`, `settings_local_storage_section.dart`, `settings_preference_cards.dart`, `task_editor_history_section.dart`, `task_editor_scheduling_card.dart`, `task_editor_subtasks_and_blockers.dart`, `task_info_dialog.dart`, `tier_task_pill.dart`, `tier_task_subtasks_section.dart`, `wipe_tdf_dialog.dart`, `workspace_dialog.dart`, `workspace_row_card.dart`) with zero `lib/repositories/*` or `lib/services/*` imports and zero direct repository/service/native-picker provider references.
- **Automated Tooling, Tests, & Documentation:**
  - `.agents/scripts/tiertask_dev.py` & `.agents/scripts/tests/test_tiertask_dev.py` (DAG Ranks `0..8`, extended `P-IO-ISOLATION`, Phase 1 `P-UDF-ARCHITECTURE` `lib/ui/` import and provider bans, `## Presentation` section support, `find --layer presentation`, `app_hubs`)
  - `11` new mirrored Dart unit test suites under `test/models/tdf_file_path_test.dart` and `test/presentation/*_test.dart`, plus `test/ui/test_helpers.dart` (`appLocaleProvider` locale synchronization) and `test/ui/edit_task_screen_test.dart` regression coverage
  - Synchronized `ARCHITECTURE.md`, `AGENTS.md`, `.agents/proposals/BOARD.md`, and `.agents/proposals/tep-015-ui-architecture-and-design-system-roadmap.md`
