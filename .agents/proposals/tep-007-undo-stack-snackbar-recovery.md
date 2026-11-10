---
id: TEP-007
title: In-Memory Undo Stack with SnackBar and Desktop Shortcut Recovery
status: review
type: feature
created: 2026-11-10
updated: 2026-11-10
---

# TEP-007: In-Memory Undo Stack with SnackBar and Desktop Shortcut Recovery

## Part 1: Concept & Proposal

### 1.1 Summary
This proposal introduces a bounded in-memory Last-In-First-Out (LIFO) undo stack (`maxUndoEntries = 10`) in `TaskNotifier` (`lib/providers/task_providers.dart`) backed by a pure domain reversal engine (`TaskBoardUndo` in `lib/models/task_board_undo.dart`), paired with a localized floating Undo `SnackBar` on `HomeScreen` (`lib/ui/home_screen.dart`), a `Ctrl+Z` desktop keyboard shortcut on Linux and Windows, and a streamlined task deletion confirmation dialog in `EditTaskScreen` (`lib/ui/edit_task_screen.dart`). Users can immediately reverse accidental task completions (both direct checkbox completion and `subtasks auto-finish` completion in `TierTaskPill`), task downgrades in `TierTaskPill`, and task deletions in `EditTaskScreen` while preserving full `spec/TDF_SPEC_0.6.0.md` monotonic `completions`, `deleted.generation`, and two-stage synchronization invariants.

### 1.2 Motivation
In the current implementation, one-tap task transitions in `TierTaskPill` (`lib/ui/widgets/tier_task_pill.dart`) and task deletions in `EditTaskScreen` (`lib/ui/edit_task_screen.dart`) immediately mutate `TaskBoard` and execute `TaskSyncPipeline` across local `.tdf` storage and WebDAV without an undo mechanism:
1. **Irreversible Accidental Task Deletions:** Deleting a task in `EditTaskScreen` removes the live `task` block, removes its `queue` entry, and records a `deleted` tombstone. Previously, `_DeleteTaskConfirmDialog` relied on a 3-second countdown lock (`Delete (3s)`) because no post-deletion recovery existed.
2. **Lossy Manual Recovery After Accidental Completion:** Tapping the completion square (or checking the final subtask when `subtasks auto-finish` is enabled) either moves a standard task to `Completed` or reschedules a recurring task to its next occurrence in `Blocked`/`Focus`. Manually tapping `restoreTask` in `Completed` (`spec/TDF_SPEC_0.6.0.md` Section 6.5) clears `due` and `suspended`, resets all checklist steps to `false`, loses the task's prior `Focus`/`Ready`/`Someday` placement and exact `queue` slot, and cannot revert a recurring task whose `due` and `suspended` dates already advanced.
3. **Tedious Manual Recovery After Accidental Downgrade:** Tapping the right-chevron downgrade button in `TierTaskPill` strips `priority` (when applicable) and moves the task to the end of `Ready`, the end of `queue` (`Planned`), or out of `queue` (`Someday`). Restoring the task's exact prior `priority` flag and `queue` position manually requires opening `EditTaskScreen` and reordering neighboring tasks.

### 1.3 Goals & Non-Goals
* **Goals:**
  1. Maintain a bounded in-memory LIFO undo stack (`maxUndoEntries = 10`, backed by `dart:collection` `ListQueue<TaskUndoEntry>`) in `TaskNotifier` for four user actions:
     - Direct task completion in `TierTaskPill` (`TaskNotifier.completeTask`),
     - Auto-finish subtask completion in `TierTaskPill` (`TaskNotifier.toggleSubtask` when toggling the step completes or reschedules the open task),
     - Task downgrade in `TierTaskPill` (`TaskNotifier.downgradeTask`),
     - Task deletion in `EditTaskScreen` (`TaskNotifier.deleteTask`).
  2. Implement targeted per-entity and relative-queue reversal in `lib/models/task_board_undo.dart` so undoing an earlier action across up to `10` stack entries preserves unrelated tasks, labels, locations, and metadata edits made in the interim while complying with all `spec/TDF_SPEC_0.6.0.md` invariants (monotonic `completions`, `decisionRevision` and `deleted.generation` advancement via `TdfDeletionResolution.undelete`, prerequisite re-arming for previously blocked dependents, and live `label` / `location` reference sanitization).
  3. Present a localized floating Undo `SnackBar` on `HomeScreen` (`5`-second display duration, `persist: false`, replacing any prior `SnackBar` immediately) via `MaterialApp`'s root `ScaffoldMessenger` while isolating `EditTaskScreen` in its own `ScaffoldMessenger` so active `HomeScreen` `SnackBar`s never cover `EditTaskScreen` controls, popping `EditTaskScreen` after task deletion keeps `HomeScreen`'s `SnackBar` visible, and `TierPageIndicator` remains unobstructed.
  4. Support `Ctrl+Z` (`KeyDownEvent` only, without `Shift`, `Alt`, or `Meta`) on Linux and Windows (`defaultTargetPlatform == TargetPlatform.linux || defaultTargetPlatform == TargetPlatform.windows`) when `HomeScreen` is the current modal route and no `EditableText` input holds focus, stepping back through all retained stack entries even after the `SnackBar` has auto-dismissed.
  5. Remove the 3-second countdown timer from `_DeleteTaskConfirmDialog` in `EditTaskScreen` so the `Delete` confirmation button is immediately enabled, and update `deleteTaskConfirmMessage` in `app_en.arb` and `app_de.arb` to reflect in-memory Undo availability.
  6. Clear the in-memory undo stack deterministically on workspace switch/unload (`prepareForWorkspaceUnload`, `activeWorkspaceProvider` ID change in `build`, `selectLocalFile`), TDF import (`importLegacyTdf`), and local or remote file wipe (`wipeLocalFile`, `wipeRemoteFile`) while preserving the stack across same-workspace preference updates (`updateLanguage`, `updateThemeMode`, `updateDiagnosticsEnabled`), and preserve atomic state rollback (`P-ATOMIC-STATE`) when local persistence fails.
* **Non-Goals:**
  1. **Persistent Cross-Restart or Synchronized Undo History:** Undo history is strictly ephemeral in-memory session state for the active workspace and is never serialized into `.tdf` files or `flutter_secure_storage`.
  2. **Redo Stack (`Ctrl+Y` / `Ctrl+Shift+Z`):** Redo is excluded to keep state transitions minimal and unambiguous.
  3. **Undo for Form Edits, Creation, Tier 6 Restoration, or Label/Location CRUD:** Explicit multi-field form saves (`addTask`, `updateTask`), `QuickAddBar` creation, Tier 6 `restoreTask`, manual `moveTaskInQueue`, and `label`/`location` CRUD are outside scope.
  4. **Changes to `spec/TDF_SPEC_0.6.0.md`:** All undo mutations map onto valid `TDF 0.6.0` entity revisions, queue mutations, monotonic `completions` rules, and `TdfDeletionResolution.undelete` reconciliation.

### 1.4 Description

#### 1.4.1 Undoable Actions & Stack Lifecycle
1. **Recording Undo Entries:**
   - **`completeTask`:** Records a `TaskUndoActionKind.complete` entry if and only if the target task existed on `boardBefore` and `taskAfter.completions > taskBefore.completions` (ignoring no-op calls on missing, already-completed, or mismatched-`expectedCompletions` tasks).
   - **`toggleSubtask`:** Records a `TaskUndoActionKind.complete` entry if and only if `taskBefore` was open (`!taskBefore.isCompleted && taskBefore.completedAt == null`) and `taskAfter.completions > taskBefore.completions` (indicating `subtasks auto-finish` completed a standard task or rescheduled a recurring task). Ordinary single-step subtask toggles do not record an undo entry.
   - **`downgradeTask`:** Records a `TaskUndoActionKind.downgrade` entry if and only if `taskBefore` existed and either `taskAfter != taskBefore` or `!listEquals(updatedBoard.queueBlock.taskIds, boardBefore.queueBlock.taskIds)` (ignoring Section 6.3 no-op downgrades).
   - **`deleteTask`:** Records a `TaskUndoActionKind.delete` entry if and only if `taskBefore` existed on `boardBefore` and `updatedBoard.findTask(taskId) == null`.
2. **Bounded LIFO Capacity (`maxUndoEntries = 10`):**
   - `TaskNotifier` stores entries in a `ListQueue<TaskUndoEntry>` (`dart:collection`). Before appending a new entry with `addLast`, if `_undoStack.length >= TaskBoardUndo.maxUndoEntries` (`10`), the oldest entry is evicted in $O(1)$ time via `removeFirst()`.
   - Each recorded entry receives a monotonically increasing session `int sequence` identifier and publishes a `TaskUndoNotice` through `taskUndoStateProvider`.
3. **Retention & Clearing Rules:**
   - Non-undoable board mutations (`addTask`, `updateTask`, `scheduleTask`, `blockTask`, `restoreTask`, `moveTaskInQueue`, non-completing `toggleSubtask`, `addLabel`, `updateLabel`, `deleteLabel`, `addLocation`, `updateLocation`, `deleteLocation`, and `syncFromRemote`) do **not** clear `_undoStack`, allowing `Ctrl+Z` to reverse earlier completions, downgrades, or deletions without losing intermediate unrelated edits.
   - `_undoStack` is cleared and `taskUndoStateProvider` is reset to `TaskUndoState.empty` (`latestNotice: null`) whenever:
     1. The active workspace ID changes (`TaskUndoStateNotifier.build()` reactively watches `activeWorkspaceProvider.select((workspace) => workspace.asData?.value.id)`, and `TaskNotifier.build()` clears `_undoStack` when `_undoWorkspaceId != workspaceId` without mutating other providers during `build()`, preserving `_undoStack` across same-workspace `webDavConfigProvider` preference updates such as language or theme changes),
     2. `TaskNotifier.prepareForWorkspaceUnload()` runs before a workspace switch,
     3. `TaskNotifier.selectLocalFile(...)` switches the active local `.tdf` file,
     4. `TaskNotifier.importLegacyTdf(...)` imports and migrates a `.tdf` document, or
     5. `TaskNotifier._executeWipe(...)` wipes the local or remote `.tdf` file.

#### 1.4.2 UI Behavior: Undo `SnackBar`, `Ctrl+Z` Shortcut & Delete Confirmation
1. **Undo `SnackBar` on `HomeScreen`:**
   - `HomeScreen` presents Undo `SnackBar`s on `MaterialApp`'s root `ScaffoldMessenger` (`ScaffoldMessenger.maybeOf(context)`), preserving root `Scaffold` registration for overlay dialogs (`LogViewerDialog`), while `EditTaskScreen` wraps its `Scaffold` in a local `ScaffoldMessenger` so active `HomeScreen` `SnackBar`s do not bleed over `EditTaskScreen`'s bottom action row and popping `EditTaskScreen` after task deletion leaves `HomeScreen`'s Undo `SnackBar` intact.
   - When `taskUndoStateProvider` emits a new `TaskUndoNotice`, `HomeScreen` calls `messenger..hideCurrentSnackBar()..showSnackBar(...)` with:
     - `behavior: SnackBarBehavior.floating`,
     - `persist: false` (overriding Material 3's persistent default when `SnackBarAction` is attached),
     - `margin: _isQuickAddOpen ? const EdgeInsets.fromLTRB(16, 0, 16, 60) : null` (positioning the floating `SnackBar` above `FloatingActionButton` when closed and above the `48 px` `TierPageIndicator` when `QuickAddBar` is open so `TierPageIndicator` taps are never blocked),
     - `duration: const Duration(seconds: 5)`,
     - Localized message (`taskCompletedUndoSnackBar`, `taskDowngradedUndoSnackBar`, or `taskDeletedUndoSnackBar`) and `SnackBarAction` (`actionUndo`) invoking `undoLastAction(expectedSequence: notice.sequence)`.
   - Binding the `SnackBarAction` to `expectedSequence: notice.sequence` prevents a double-trigger (for example, pressing `Ctrl+Z` and clicking `Undo` in the same frame) from popping a second, older stack entry.
   - When `latestNotice` transitions to `null` (via `Ctrl+Z`, `SnackBar` action, stack clear, or local persistence rollback), `HomeScreen` calls `ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar()`.
2. **Desktop `Ctrl+Z` Shortcut (Linux & Windows):**
   - `_HomeScreenState` registers `HardwareKeyboard.instance.addHandler(_handleUndoKeyEvent)` in `initState()` and removes it in `dispose()`.
   - `_handleUndoKeyEvent` triggers `undoLastAction()` and returns `true` only when all of the following hold:
     - `mounted` is `true` and `event is KeyDownEvent` (`KeyRepeatEvent` and `KeyUpEvent` are ignored so holding `Ctrl+Z` never drains multiple entries unintentionally),
     - `defaultTargetPlatform == TargetPlatform.linux || defaultTargetPlatform == TargetPlatform.windows` (pure `package:flutter/foundation.dart`, preserving `P-IO-ISOLATION` with zero `dart:io` imports in `lib/ui/`),
     - `event.logicalKey == LogicalKeyboardKey.keyZ` with `isControlPressed == true` and `isShiftPressed == false`, `isAltPressed == false`, `isMetaPressed == false`,
     - `ModalRoute.of(context)?.isCurrent ?? true` is `true` (inactive while any dialog or pushed editor/settings route is open),
     - No `EditableText` widget holds `FocusManager.instance.primaryFocus` (preserving native text-field undo inside `QuickAddBar` and the top search bar), and
     - `ref.read(taskUndoStateProvider).canUndo` is `true`.
   - Pressing `Ctrl+Z` works both while the Undo `SnackBar` is visible and after the `5`-second `SnackBar` has auto-dismissed, popping up to `10` retained entries in LIFO order.
3. **Streamlined `_DeleteTaskConfirmDialog` in `EditTaskScreen`:**
   - `_DeleteTaskConfirmDialog` becomes a `StatelessWidget` without a `Timer` or 3-second countdown; `delete_task_confirm_button` (`actionDelete`) is enabled immediately upon opening the dialog.
   - `deleteTaskConfirmMessage` in English (`en`) and German (`de`) informs the user that the deletion can be undone while the workspace remains open.

### 1.5 Alternatives
1. **Whole-Board Snapshot Replacement (`TaskBoard` Before-Image Overwrite):** Rejected for two reasons:
   - Across a 10-entry undo stack, replacing `TaskBoard` with a full board snapshot captured minutes earlier would overwrite intermediate task additions, task edits, label/location changes, and remote WebDAV merges.
   - Restoring a pre-completion `TaskItem` with a lower `completions` counter (`c < c + 1`) violates `spec/TDF_SPEC_0.6.0.md` Section 6.9.1 and triggers `TdfSyncOutcomeKind.recoveryRequired` in `TaskBoardReconciler.verifyGenerationsAndCompletionHistory` (`lib/models/task_board_reconciler.dart`), and restoring a deleted task without advancing `deleted.generation` and passing `TdfDeletionResolution.undelete` triggers `TdfSyncOutcomeKind.deletionConflict` during two-stage synchronization.
2. **Delaying Mutation & Persistence Until the 5-Second `SnackBar` Closes:** Rejected because holding pending completions, downgrades, or deletions out of `TaskBoard` for 5 seconds breaks deterministic Auto-Pull Cascade slot refilling, leaves stale tasks on screen or out of sync on workspace/app close, and prevents multi-step `Ctrl+Z` history after the `SnackBar` closes.
3. **Wrapping `HomeScreen`'s `Scaffold` in a Nested `ScaffoldMessenger`:** Rejected because detaching `HomeScreen`'s `Scaffold` from `MaterialApp`'s root `ScaffoldMessenger` leaves root overlay dialogs (`LogViewerDialog`) with zero registered `Scaffold`s on `ScaffoldMessenger.of(context)`. Instead, `HomeScreen` uses `MaterialApp`'s root `ScaffoldMessenger` while `EditTaskScreen` wraps its own `Scaffold` in a dedicated `ScaffoldMessenger`.

## Part 2: Technical Design & Code Changes

### 2.1 Architecture & Affected Modules
* **Localization (`lib/l10n/` — Layer Rank `2`):**
  - `lib/l10n/app_en.arb` & `lib/l10n/app_de.arb`: Update `deleteTaskConfirmMessage` and add `actionUndo`, `taskCompletedUndoSnackBar`, `taskDowngradedUndoSnackBar`, and `taskDeletedUndoSnackBar` (regenerated via `flutter gen-l10n`).
* **Domain Models (`lib/models/` — Layer Rank `1`):**
  - `lib/models/task_board_undo.dart` *(new leaf file)*: Defines `TaskUndoActionKind`, `TaskUndoEntry`, `TaskUndoOutcome`, and stateless helper `TaskBoardUndo` (`const TaskBoardUndo._()`) implementing capture metadata extraction and TDF-compliant reversal for `complete`, `downgrade`, and `delete`. Imports only `dart:math`, `package:flutter/foundation.dart`, `../services/app_logger.dart`, and lower/peer `lib/models/*.dart` files (`task_board.dart`, `task_board_evaluator.dart`, `task_item.dart`, `tdf_error.dart`, `tdf_location.dart`, `tdf_metadata.dart`, `tdf_sync_metadata.dart`, `tdf_timezone.dart`), preserving `0` circular import SCCs (`P-ACYCLIC-DAG`).
* **Providers (`lib/providers/` — Layer Rank `5`):**
  - `lib/providers/task_providers.dart`: Adds `taskUndoStateProvider` (`NotifierProvider<TaskUndoStateNotifier, TaskUndoState>`), `TaskUndoNotice`, `TaskUndoState`, `TaskUndoStateNotifier` (watching `activeWorkspaceProvider` ID in `build()`), bounded `_undoStack` (`ListQueue<TaskUndoEntry>`) with `_undoWorkspaceId` tracking, monotonic `_mutationEpoch` UI-flicker guard and per-epoch `_rolledBackEpochs` rollback tracking in `TaskNotifier`, `taskConflictResolutions` forwarding on `pushToRemote` / `_executePushToRemote`, undo capture in `completeTask` / `toggleSubtask` / `downgradeTask` / `deleteTask`, `Future<bool> undoLastAction({int? expectedSequence, DateTime? currentDate})`, and stack clearing on workspace ID change in `build` plus imperative resets in `prepareForWorkspaceUnload` / `selectLocalFile` / `importLegacyTdf` / `_executeWipe`.
* **UI (`lib/ui/` — Layer Rank `6`):**
  - `lib/ui/app_theme.dart`: Sets `actionTextColor: primaryAccent` on `SnackBarThemeData` in `AppTheme.toThemeData()` for accessible `Undo` / `Rückgängig` button contrast across all 4 `AppTheme` variants.
  - `lib/ui/edit_task_screen.dart`: Simplifies `_DeleteTaskConfirmDialog` to a `StatelessWidget` with an immediately enabled `delete_task_confirm_button` (removing `_DeleteTaskConfirmDialogState`, `confirmDelaySeconds`, `tickInterval`, and unused `dart:async` import) and wraps `EditTaskScreen`'s `Scaffold` in a dedicated `ScaffoldMessenger(key: _scaffoldMessengerKey, ...)`.
  - `lib/ui/home_screen.dart`: Listens to `taskUndoStateProvider.select((state) => state.latestNotice)` to present or dismiss the floating Undo `SnackBar` (`persist: false`) via `ScaffoldMessenger.maybeOf(context)`, and registers the desktop `Ctrl+Z` `HardwareKeyboard` handler with route-current and `EditableText`-focus guards.
* **Tests (`test/` — `P-TEST-MIRROR`):**
  - `test/models/task_board_undo_test.dart` *(new mirror suite for `lib/models/task_board_undo.dart`)*: Exhaustive unit tests for `TaskBoardUndo` across all action kinds, TDF `0.6.0` invariants, bounds, and sanitization edge cases.
  - `test/providers/task_providers_test.dart`: Unit and integration tests for `TaskNotifier` undo stack bounds (`9`, `10`, `11`), two-stage Local + WebDAV sync with `TdfDeletionResolution.undelete` and monotonic `completions`, rollback atomicity, and workspace/import/wipe stack clearing.
  - `test/ui/test_helpers.dart`: Updates `FakeTaskNotifier.pushToRemote` optional parameters (`taskConflictResolutions`, `mutationEpoch`) to match `TaskNotifier.pushToRemote`.
  - `test/ui/edit_task_screen_test.dart`: Updates `_DeleteTaskConfirmDialog` expectations for immediate confirmation and tests end-to-end Delete -> `HomeScreen` Undo `SnackBar` recovery in `en` and `de`.
  - `test/ui/home_screen_test.dart`: Widget tests for Undo `SnackBar` presentation/replacement, `TierPageIndicator` non-obstruction, `Ctrl+Z` on Linux and Windows, Android `Ctrl+Z` exclusion, and `EditableText` / non-current-route focus guards.

### 2.2 TDF Schema, Localization & State Changes
* **`spec/TDF_SPEC_0.6.0.md` Impact:** None. All `.tdf` lexical, structural, evaluation, revision, monotonic `completions`, `deleted.generation`, and `queue` rules remain unchanged.
* **Binary Persistence (`TTW\x01`, `TTS\x01`):** Unchanged. Undo state is strictly in-memory.
* **ARB Localization Changes (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`):**

| Key | English (`app_en.arb`) | German (`app_de.arb`) |
| :--- | :--- | :--- |
| `actionUndo` | `"Undo"` | `"Rückgängig"` |
| `taskCompletedUndoSnackBar` | `"Completed \"{title}\"."` | `"„{title}“ abgeschlossen."` |
| `taskDowngradedUndoSnackBar` | `"Downgraded \"{title}\"."` | `"„{title}“ herabgestuft."` |
| `taskDeletedUndoSnackBar` | `"Deleted \"{title}\"."` | `"„{title}“ gelöscht."` |
| `deleteTaskConfirmMessage` *(updated)* | `"Delete task \"{title}\"? This action can be undone while the workspace remains open."` | `"Aufgabe „{title}“ löschen? Diese Aktion kann rückgängig gemacht werden, solange der Arbeitsbereich geöffnet bleibt."` |

### 2.3 Implementation Details

#### 2.3.1 Domain Undo Model & Reversal Engine (`lib/models/task_board_undo.dart`)
```dart
/// Classifies an undoable user task action.
enum TaskUndoActionKind {
  /// Direct task completion or `subtasks auto-finish` completion.
  complete,

  /// Active task step-down downgrade (`Focus -> Ready`, `Ready -> Planned`, `Planned -> Someday`).
  downgrade,

  /// Task deletion with tombstone creation.
  delete,
}

/// Immutable snapshot of a single undoable task mutation.
@immutable
class TaskUndoEntry {
  /// Creates a [TaskUndoEntry].
  const TaskUndoEntry({
    required this.sequence,
    required this.kind,
    required this.snapshotTask,
    required this.wasQueued,
    required this.queueOrderSnapshot,
    required this.hadOnlyScopedLabels,
    this.previouslyBlockedDependentIds = const <String>{},
  });

  /// Whether [snapshotTask] was restricted from the global view by scoped-only labels before the mutation.
  final bool hadOnlyScopedLabels;

  /// Action category recorded by this entry.
  final TaskUndoActionKind kind;

  /// Task IDs whose dependency on `snapshotTask.id` was unsatisfied (`snapshotTask.completions < requiredCompletion`) immediately before completion.
  final Set<String> previouslyBlockedDependentIds;

  /// Unmodifiable `queueBlock.taskIds` order from the board immediately before the mutation.
  final List<String> queueOrderSnapshot;

  /// Monotonically increasing session sequence number identifying this entry.
  final int sequence;

  /// Immutable pre-mutation [TaskItem] snapshot.
  final TaskItem snapshotTask;

  /// Whether `snapshotTask.id` was present in `queueBlock.taskIds` before the mutation.
  final bool wasQueued;
}

/// Result of applying a [TaskUndoEntry] onto the current [TaskBoard].
@immutable
class TaskUndoOutcome {
  /// Creates a [TaskUndoOutcome].
  const TaskUndoOutcome({
    required this.board,
    this.taskConflictResolutions = const <String, TdfDeletionResolution>{},
  });

  /// Re-evaluated [TaskBoard] produced by the undo transition.
  final TaskBoard board;

  /// Per-task deletion conflict resolutions (`TdfDeletionResolution.undelete` when undoing a deletion) forwarded to `TaskSyncPipeline.synchronize`.
  final Map<String, TdfDeletionResolution> taskConflictResolutions;
}
```

`TaskBoardUndo` (`const TaskBoardUndo._()`, `static const int maxUndoEntries = 10`) provides:
1. **`static TaskUndoEntry capture({required int sequence, required TaskUndoActionKind kind, required TaskBoard boardBefore, required TaskItem taskBefore})`:**
   - Computes `wasQueued = boardBefore.queueBlock.taskIds.contains(taskBefore.id)` and references `boardBefore.queueBlock.taskIds` directly as `queueOrderSnapshot` (zero copy since `TdfQueueBlock.taskIds` is already unmodifiable).
   - Computes `hadOnlyScopedLabels` via `TaskBoardEvaluator.isRestrictedFromGlobalView` over `boardBefore.labels`.
   - When `kind == TaskUndoActionKind.complete`, collects `previouslyBlockedDependentIds` in a single $O(N)$ pass over `boardBefore.allTasks`: every task `other` (`other.id != taskBefore.id`) that has a `TdfTaskDependency` with `dep.taskId == taskBefore.id && taskBefore.completions < dep.requiredCompletion`.
2. **`static TaskUndoOutcome? apply(TaskBoard currentBoard, TaskUndoEntry entry, {required DateTime utcNow, DateTime? localEvaluationTime, TdfTimeZoneContext? timeZone})`:**
   - Normalizes `now = TaskItem.normalizeTimestamp(utcNow)`.
   - Dispatches exhaustively over `entry.kind` in declaration order (`complete`, `downgrade`, `delete`):
     - **`TaskUndoActionKind.complete`:**
       - Looks up `currentTask = currentBoard.findTask(taskId)`. Returns `null` (logging `task.undo.skipped` with `reason=task_missing`) if `currentTask == null`.
       - Computes `restoredCompletions = math.max(snapshotTask.completions, currentTask.completions)` so `completions` never decreases (`spec/TDF_SPEC_0.6.0.md` Section 6.9.1).
       - Sanitizes `currentTask.labelIds` and `currentTask.conditions` against live `currentBoard.labels` and `currentBoard.locations`; sets `evictedByScopedDeletion = entry.hadOnlyScopedLabels && retainedLabels.isEmpty`.
       - Restores open occurrence fields from `snapshotTask` (`isCompleted: false`, `clearCompletedAt: true`, `completions: restoredCompletions`, `isPriority: evictedByScopedDeletion ? false : snapshotTask.isPriority`, `suspendedAt: snapshotTask.suspendedAt`, `clearSuspendedAt: snapshotTask.suspendedAt == null`, `isSuspendedForever: snapshotTask.isSuspendedForever`, `dueAt: snapshotTask.dueAt`, `clearDueAt: snapshotTask.dueAt == null`, `repeatRule: snapshotTask.repeatRule`, `clearRepeatRule: snapshotTask.repeatRule == null`, `dependencies: snapshotTask.dependencies`, `subtasksAutoFinish: snapshotTask.subtasksAutoFinish`, `subtasks: snapshotTask.subtasks`) while preserving `currentTask.title`, `currentTask.note`, `currentTask.origin`, `currentTask.links`, and advancing `modifiedAt = TaskItem.nextModifiedTimestamp(now, max(currentTask.effectiveModifiedAt, snapshotTask.effectiveModifiedAt))`.
       - Re-arms any live task `other` in `previouslyBlockedDependentIds` whose dependency on `taskId` has `dep.requiredCompletion <= restoredCompletions` (when `restoredCompletions < TdfTaskDependency.maxCompletions`) to `requiredCompletion: restoredCompletions + 1` with `other.modifiedAt` advanced.
       - Verifies dependency graph acyclicity (`reason=dependency_cycle` on failure) and restores queue membership via `_restoreQueueMembership` (`reason=queue_limit_exceeded` if adding exceeds `TdfQueueBlock.maxQueueEntries`).
     - **`TaskUndoActionKind.downgrade`:**
       - Looks up `currentTask = currentBoard.findTask(taskId)`. Returns `null` (`reason=task_not_open`) if `currentTask == null || currentTask.isCompleted || currentTask.completedAt != null`.
       - Sanitizes `currentTask.labelIds` (`evictedByScopedDeletion` check) and restores `isPriority` (`evictedByScopedDeletion ? false : snapshotTask.isPriority`), `suspendedAt`, and `isSuspendedForever` onto `currentTask` (advancing `modifiedAt` only if any task attribute changed) plus queue membership via `_restoreQueueMembership`. Returns `null` (`reason=already_at_target_state`) if neither task attributes nor `queueBlock.taskIds` changed.
     - **`TaskUndoActionKind.delete`:**
       - Verifies `currentBoard.findTask(taskId) == null` (`reason=task_already_live`), verifies `deletedRecord == null || currentBoard.deletedBlock.generation < TdfDeletedBlock.maxGeneration` (`reason=generation_limit_exceeded`), and sanitizes `snapshotTask.labelIds` and `snapshotTask.conditions` against `currentBoard.labels` and `currentBoard.locations` (applying Section 6.8.1 scoped flood protection and `GroupResetTaskCondition(targetGroup: ConditionGroup.location)` inheritance-trap protection when an assigned live label still defines a `location` rule).
       - Computes `restoredCompletions = math.max(snapshotTask.completions, deletedRecord?.completionsCheckpoint ?? 0)` and `decisionRevision = max(now, max(snapshotTask.effectiveModifiedAt, deletedRecord?.deletedAt) + 1 second)` per `spec/TDF_SPEC_0.6.0.md` Section 6.8.2.
       - Verifies both the merge root-block bound (`currentBoard.allTasks.length + 1 + currentBoard.labels.length + currentBoard.locations.length + 2 <= maxTdfBlocksPerDoc`) and total serialized `{ ... }` block count (including `deleted`, `queue`, non-empty `subtasks`, and multi-rule `condition` sub-blocks `<= maxTdfBlocksPerDoc`, failing with `reason=block_limit_exceeded`), and verifies dependency graph acyclicity (`reason=dependency_cycle` on failure).
       - Removes `taskId` from `currentBoard.deletedBlock.tasks` and increments `deletedBlock.generation` by `1` when `deletedRecord != null`.
       - Restores queue membership via `_restoreQueueMembership` when `!restoredTask.isCompleted && restoredTask.completedAt == null`, evaluates via `TaskBoard.evaluate(..., pruneExpiredCompleted: false)`, and returns `TaskUndoOutcome` with `taskConflictResolutions: {taskId: TdfDeletionResolution.undelete}`.
3. **Relative Queue Slot Reconstruction (`_restoreQueueMembership`):**
   - When `!entry.wasQueued || evictedByScopedDeletion` (or task is completed), removes `taskId` from `currentQueue` (advancing `queue.modifiedAt` only when removed).
   - When `entry.wasQueued && !evictedByScopedDeletion`: removes any existing `taskId` occurrence to form `withoutTask`, finds `snapshotIndex = entry.queueOrderSnapshot.indexOf(taskId)`, inserts `taskId` immediately after the nearest predecessor `entry.queueOrderSnapshot[i]` (`i < snapshotIndex`) present in `withoutTask`, or else immediately before the nearest successor `entry.queueOrderSnapshot[i]` (`i > snapshotIndex`) present in `withoutTask`, or else at index `0` when `snapshotIndex == 0` (otherwise at the end), advancing `queue.modifiedAt` via `TaskItem.nextModifiedTimestamp(now, currentQueue.modifiedAt)` when `taskIds` changed.

#### 2.3.2 Provider State, Concurrency Guard & Rollback Atomicity (`lib/providers/task_providers.dart`)
* **`TaskUndoNotice`, `TaskUndoState` & `TaskUndoStateNotifier` (`taskUndoStateProvider`):**
  - `TaskUndoNotice({required int sequence, required TaskUndoActionKind kind, required String taskId, required String taskTitle})` (`@immutable`, value equality and `hashCode`).
  - `TaskUndoState({this.stackDepth = 0, this.latestNotice})` with `bool get canUndo => stackDepth > 0;` and `static const TaskUndoState empty = TaskUndoState();`.
  - `TaskUndoStateNotifier.build()` watches `activeWorkspaceProvider.select((workspace) => workspace.asData?.value.id)` and returns `TaskUndoState.empty` so workspace switches reset UI undo state reactively without cross-provider mutation during `TaskNotifier.build()`.
* **Mutation Epoch, Workspace Tracking & Rollback Handling in `TaskNotifier`:**
  - `int _mutationEpoch = 0;`, `int _nextUndoSequence = 0;`, `bool _lastPushRolledBack = false;`, `String? _undoWorkspaceId;`, and `final ListQueue<TaskUndoEntry> _undoStack = ListQueue<TaskUndoEntry>();` (`TaskNotifier.build()` clears `_undoStack` only when `_undoWorkspaceId != workspaceId`).
  - `_commitMutation(TaskBoard updatedBoard, {TaskUndoEntry? undoEntry, Map<String, TdfDeletionResolution> taskConflictResolutions = const {}})`:
    - Increments `final epoch = ++_mutationEpoch;`, records `previousBoard = _currentBoard`, sets `state = AsyncData(updatedBoard)` synchronously, and if `undoEntry != null`, records `final evictedEntry = _undoStack.length >= TaskBoardUndo.maxUndoEntries ? _undoStack.removeFirst() : null;`, pushes `undoEntry` onto `_undoStack`, and publishes `TaskUndoNotice` to `taskUndoStateProvider` immediately before `await pushToRemote(..., mutationEpoch: epoch)` so the Undo `SnackBar` appears without waiting on network latency.
    - Inside `_executePushToRemote`, `onLocalStageMerged`, post-remote `state = AsyncData(converged)`, and the `!localStageSucceeded` `fallbackBoard` rollback branch all check `final isCurrentEpoch = mutationEpoch == null || mutationEpoch == _mutationEpoch;` before mutating `state`, preventing an earlier slow or failed push from overwriting a newer mutation's state.
    - If `_lastPushRolledBack` is `true` and `epoch == _mutationEpoch` (local stage threw `LocalFileException` and rolled `state` back to `previousBoard`):
      - For a forward undoable mutation (`undoEntry != null`), removes `undoEntry` from `_undoStack`, restores `evictedEntry` via `_undoStack.addFirst(evictedEntry)` if non-null and `_undoStack.length < TaskBoardUndo.maxUndoEntries`, clears `latestNotice` if its `sequence` matches, and logs `task.undo.rollback`.
      - For `undoLastAction()`, re-inserts the popped `TaskUndoEntry` at the top of `_undoStack` (if `_undoStack.length < TaskBoardUndo.maxUndoEntries`), updates `taskUndoStateProvider`, and logs `task.undo.rollback`.
* **`Future<bool> undoLastAction({int? expectedSequence, DateTime? currentDate})`:**
  - Returns `false` immediately if `_undoStack.isEmpty` or `(expectedSequence != null && _undoStack.last.sequence != expectedSequence)`.
  - Pops `final entry = _undoStack.removeLast();`, clears `latestNotice` on `taskUndoStateProvider` (updating `stackDepth: _undoStack.length`), and runs `TaskBoardUndo.apply(_currentBoard, entry, utcNow: utcNow, localEvaluationTime: localNow)`.
  - If `outcome == null`, returns `false`.
  - Otherwise logs `task.undo.apply`, awaits `_commitMutation(outcome.board, taskConflictResolutions: outcome.taskConflictResolutions)` (restoring `entry` to `_undoStack` if `_lastPushRolledBack` is `true`), and returns `!_lastPushRolledBack`.

#### 2.3.3 Diagnostic Instrumentation (`AGENTS.md` Section 6)
All events use `AppLogger.event(...)` gated behind `AppLogger.shouldLog` without logging task titles, notes, or coordinates:
* `LogTag.domain` (`LogLevel.info`):
  - `task.undo.push` (`id`, `kind`, `seq`, `depth`)
  - `task.undo.apply` (`id`, `kind`, `seq`, `remaining`)
  - `task.undo.skipped` (`id`, `kind`, `seq`, `reason`)
  - `task.undo.clear` (`reason`, `cleared`)
* `LogTag.domain` (`LogLevel.warn`):
  - `task.undo.rollback` (`id`, `kind`, `seq`, `direction`: `'forward'` or `'undo'`)
* `LogTag.ui` (`LogLevel.info`):
  - `ui.undo.snackbar_shown` (`id`, `kind`, `seq`)
  - `ui.undo.snackbar_action` (`id`, `kind`, `seq`)
  - `ui.undo.shortcut` (`depth`)

### 2.4 Testing Strategy
Follow strict Red-Green-Refactor TDD (`P-TDD-FIRST`, `P-TEST-MIRROR`):
1. **`M-EXHAUSTIVE-STATE-TESTS` (`test/models/task_board_undo_test.dart`, `test/providers/task_providers_test.dart`):**
   - Test every `TaskUndoActionKind` variant (`complete` on standard task, `complete` on recurring task with `due` and `suspended`, `complete` via `subtasks auto-finish` `toggleSubtask`, `downgrade` across `Focus -> Ready`, `Ready -> Planned`, and `Planned -> Someday` with and without `activeLabelId`, and `delete` on open queued, `Someday`, and `Completed` tasks).
   - Verify no-op mutations (already completed task, non-completing `toggleSubtask`, Section 6.3 no-op downgrade, deleting missing task ID) push zero undo entries.
   - Verify every skip branch in `TaskBoardUndo.apply` (`task_missing`, `task_not_open`, `already_at_target_state`, `task_already_live`, `dependency_cycle`, `block_limit_exceeded`, `queue_limit_exceeded`, `generation_limit_exceeded`).
2. **`M-EXTREME-BOUND-TESTS` (`test/models/task_board_undo_test.dart`, `test/providers/task_providers_test.dart`):**
   - Test undo stack capacity boundaries at $N - 1 = 9$, $N = 10$, and $N + 1 = 11$ consecutive undoable mutations (verifying oldest FIFO eviction at `11` and full 10-step LIFO reversal down to `0`).
   - Test `maxTdfBlocksPerDoc` (`4096`), `TdfQueueBlock.maxQueueEntries` (`4096`), `TdfDeletedBlock.maxGeneration` (`9007199254740991`), and `TdfTaskDependency.maxCompletions` (`9007199254740991`) bounds during `TaskBoardUndo.apply`.
   - Verify multi-delete and out-of-order relative queue slot restoration (`[A, B, C, D]` deleting first/middle/last elements and undoing in LIFO order while preserving newly added task `E`).
   - Verify deleted `label` (including `scoped`-only flood protection to `Someday`) and deleted `location` (including `GroupResetTaskCondition` `location any` override preservation) sanitization when a referenced label or location is deleted between capture and undo.
3. **`M-IO-TESTS` (`test/providers/task_providers_test.dart`):**
   - Test end-to-end two-stage persistence (`LocalFileRepository` + `FakeWebDavRepository` / loopback `HttpServer` with `HttpOverrides.global = null` in `setUp()`) across `StorageMode.local`, `StorageMode.webdav`, and `StorageMode.both`:
     - Complete -> Sync -> Undo -> Sync: verify `completions` stays monotonic (`c + 1`) without throwing `TdfSyncOutcomeKind.recoveryRequired` and previously blocked dependents re-arm to `c + 2`.
     - Delete -> Sync -> Undo -> Sync: verify `TdfDeletionResolution.undelete` retires the `.tdf` tombstone and increments `deleted.generation` by `1` without throwing `TdfSyncOutcomeKind.deletionConflict`.
     - Slow WebDAV in-flight `PUT` + immediate `undoLastAction()`: verify `_mutationEpoch` prevents UI state flicker and converges cleanly.
     - Local file write failure (`LocalFileException`): verify forward rollback removes the optimistic undo entry and undo rollback restores the popped `TaskUndoEntry` (`P-ATOMIC-STATE`).
   - Verify stack retention across same-workspace preference updates (`updateLanguage`, `updateThemeMode`) and stack clearing across workspace switch (`prepareForWorkspaceUnload` / `activeWorkspaceProvider` ID change), `selectLocalFile`, `importLegacyTdf`, `wipeLocalFile`, and `wipeRemoteFile`.
4. **UI, Localization & Shortcut Widget Tests (`test/ui/home_screen_test.dart`, `test/ui/edit_task_screen_test.dart`):**
   - Verify `_DeleteTaskConfirmDialog` opens with `delete_task_confirm_button` immediately enabled (no 3-second countdown), displays updated English and German `deleteTaskConfirmMessage`, pops `EditTaskScreen` on confirm, and shows the localized Undo `SnackBar` on `HomeScreen` without premature dismissal.
   - Verify tapping `Undo` / `Rückgängig` on the `SnackBar` reverses direct completion, `subtasks auto-finish` completion, downgrade, and deletion, and verify `expectedSequence` ignores duplicate taps.
   - Verify `TierPageIndicator` taps (`tier_indicator_item_*`) succeed immediately while an Undo `SnackBar` is visible.
   - Verify `Ctrl+Z` (`debugDefaultTargetPlatformOverride = TargetPlatform.linux` and `TargetPlatform.windows`) reverses multiple stacked actions even after the 5-second `SnackBar` auto-dismisses, does **not** trigger on `TargetPlatform.android`, `KeyRepeatEvent`, `Ctrl+Shift+Z`, when `EditTaskScreen` or a dialog is open, or when `QuickAddBar` or the search `TextField` holds focus.

## Part 3: Implementation Record & Tasks

### 3.1 Task Breakdown
- [x] Run `python3 .agents/scripts/tiertask_dev.py verify --fast` to confirm a clean baseline.
- [x] Update `lib/l10n/app_en.arb` and `lib/l10n/app_de.arb` and run `flutter gen-l10n`.
- [x] Write failing unit tests in `test/models/task_board_undo_test.dart` and `test/providers/task_providers_test.dart` and failing widget tests in `test/ui/edit_task_screen_test.dart` and `test/ui/home_screen_test.dart` (TDD Red Phase — `P-TDD-FIRST`).
- [x] Implement `lib/models/task_board_undo.dart`, `lib/providers/task_providers.dart`, `lib/ui/app_theme.dart`, `lib/ui/edit_task_screen.dart`, `lib/ui/home_screen.dart`, and `test/ui/test_helpers.dart` with `AppLogger` instrumentation (TDD Green & Refactor Phase).
- [x] Update Parts 1 and 2 if implementation details evolve.
- [x] Run `python3 .agents/scripts/tiertask_dev.py arch --sync-tree` and `python3 .agents/scripts/tiertask_dev.py verify --full --fix`.
- [x] Synchronize `README.md`, `ARCHITECTURE.md`, and `AGENTS.md` per **`update-documentation`**.
- [x] Add a user-facing `CHANGELOG.md` entry under `## [Unreleased]` per **`changelog-updater`**.
- [x] Set `status: review`, update `BOARD.md`, and request user approval.
- [ ] After user approval, set `status: completed`, update `BOARD.md`, and record delivered artifacts in Part 3.3.

### 3.2 Work Log & Decisions
* **2026-11-10:** Created `TEP-007` in `planned` status incorporating user decisions on bounded 10-entry LIFO stack retention (`Ctrl+Z` across session until workspace switch, import, or wipe), immediate delete confirmation dialog without the 3-second countdown lock, and undo scope covering direct completion, `subtasks auto-finish` completion, and downgrade in `TierTaskPill` plus task deletion in `EditTaskScreen`.
* **2026-11-10:** Implemented `TEP-007` via strict Red-Green-Refactor TDD across `lib/models/task_board_undo.dart`, `lib/providers/task_providers.dart` (using per-epoch `_rolledBackEpochs` tracking for concurrency-safe rollback atomicity), `lib/ui/app_theme.dart`, `lib/ui/edit_task_screen.dart`, and `lib/ui/home_screen.dart` (setting `persist: false` on Material 3 `SnackBar` with `SnackBarAction` so the 5-second auto-dismiss timer fires reliably). Synchronized `ARCHITECTURE.md` and `CHANGELOG.md`, verified full suite via `tiertask_dev.py verify --full --fix`, and moved `TEP-007` to `review`.

### 3.3 Delivered Artifacts
*(Complete upon approval)*
