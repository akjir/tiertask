---
id: TEP-012
title: Interactive Task History Journal in Task Info Dialog and Task Editor
status: completed
type: feature
created: 2026-11-14
updated: 2026-11-16
---

# TEP-012: Interactive Task History Journal in Task Info Dialog and Task Editor

## Part 1: Concept & Proposal

### 1.1 Summary
This proposal specifies the interactive **Task History Journal** UI inside `TaskInfoDialog` (`lib/ui/widgets/task_info_dialog.dart`), `TierTaskPill` (`lib/ui/widgets/tier_task_subtasks_section.dart` and `lib/ui/widgets/tier_task_pill.dart`), and `EditTaskScreen` (`lib/ui/edit_task_screen.dart`) on top of **TierTask Data Format (`TDF`) `0.7.0`** (`spec/TDF_SPEC_0.7.0.md` and `TEP-006`). While `TEP-006` already implements the `history <YYYY-MM-DD> [<HH:MM[:SS]>] "<text>"` grammar (`0..500` entries per `task` via `maxTdfHistoryPerTask`, `maxTdfTextLength = 500`, `maxTdfStmtsPerBlock = 1024` at canonical directive position `14`), scanner/parser/serializer support, `TaskHistoryEntry` (`compareCanonical`, `normalizeList`), permanent retention across `repeat` rollovers, `Completed`, and `restoreTask`, occurrence-independent three-way set reconciliation, no-op revision protection, and `TaskNotifier` mutations (`addTaskHistoryEntry`, `updateTaskHistoryEntry`, `removeTaskHistoryEntry`, `addTask`, `updateTask`), this proposal delivers:
1. A passive `history_task_indicator` (`Icons.history_rounded`) on `TierTaskPill` whenever `task.history.isNotEmpty`, opening `TaskInfoDialog` with the History Journal card highlighted.
2. An always-available interactive `_TaskInfoHistoryCard` inside `TaskInfoDialog` (`ConsumerStatefulWidget`) displaying chronological local wall-clock entries (`configuration.toLocalWallClock(entry.timestampUtc)`), lazy `ListView.builder` virtualization (`> 5` entries inside a tight `SizedBox` compatible with `AlertDialog`), single-line quick append defaulting `timestampUtc` to `TaskItem.normalizeTimestamp(ref.read(clockProvider)().toUtc())`, inline `<text>` editing tracked by immutable `TaskHistoryEntry` value across live external syncs, and single-tap entry removal.
3. A dedicated `TaskEditorHistorySection` (`lib/ui/widgets/task_editor_history_section.dart`) and stateless `TaskHistoryInputValidator` inside `EditTaskScreen` supporting batch history creation, local wall-clock timestamp (`YYYY-MM-DD [HH:MM[:SS]]` with 24-hour date/time pickers) and `<text>` editing, untouched timestamp/text preservation across DST folds and calendar boundaries, deletion, and atomic pending-input validation on form submission.
4. A correctness fix in `TaskBoardUndo` (`lib/models/task_board_undo.dart`) so undoing `completeTask` or `downgradeTask` preserves live `currentTask.history` edits logged after the completion or downgrade snapshot was recorded, while `deleteTask` undo continues restoring `snapshotTask.history`.

### 1.2 Motivation
`TEP-006` (`spec/TDF_SPEC_0.7.0.md` Sections 2.8, 4.1.2, 6.4–6.7, and 7) separates standing task instructions (`note "<note>"`) from chronological progress logs (`history <timestamp> "<text>"`), ensuring that recurring meter readings, follow-up call outcomes, and waiting logs survive `repeat` completions and merge without conflict across offline devices. Four functional and state-integrity gaps remain before users can work with `history` entries in TierTask:
1. **No Fast In-Place Journaling During Execution:** When checking on a `Blocked` task or completing a step in `Focus`, opening `EditTaskScreen` and typing a timestamp manually just to record `"Left voicemail with support"` adds unnecessary friction. Users need a single-line quick-append input directly inside `TaskInfoDialog` that stamps the current UTC second automatically.
2. **No Batch or Backdated History Authoring in `EditTaskScreen`:** When creating a new task (`TaskNotifier.addTask`, which `EditTaskScreen._persistTask` currently invokes without `history`), backdating historical notes, or adjusting an existing entry's local date/time alongside other task edits before saving once, users need a structured `TaskEditorHistorySection` card inside `EditTaskScreen`.
3. **No Visual Indicator on `TierTaskPill`:** Tasks carrying recorded history entries show no indicator icon on `TierTaskPill`, requiring users to open every task to discover whether progress logs exist.
4. **Silent History Overwrite on Completion/Downgrade Undo (`TaskBoardUndo`):** Neither `completeTask` nor `downgradeTask` modifies `task.history` (`spec/TDF_SPEC_0.7.0.md` Sections 6.3 and 6.4), and non-undoable task edits (`addTaskHistoryEntry`, `updateTaskHistoryEntry`, `removeTaskHistoryEntry`, `updateTask`) intentionally preserve the in-memory undo stack. However, `TaskBoardUndo._applyComplete` (`lib/models/task_board_undo.dart:219`) and `TaskBoardUndo._applyDowngrade` (`lib/models/task_board_undo.dart:522, 558`) currently overwrite `currentTask.history` with `snapshotTask.history`, which would silently erase any history entries added or edited between completing/downgrading a task and triggering `Undo`.

### 1.3 Goals & Non-Goals
* **Goals:**
  1. Append `history_task_indicator` (`Icons.history_rounded`) to `resolveTaskIndicatorSpecs` (`lib/ui/widgets/tier_task_subtasks_section.dart`) immediately after `links_task_indicator` and before `subtasks_task_indicator` whenever `task.history.isNotEmpty`, opening `TaskInfoDialog` with `initialIndicatorKeyPrefix: 'history_task_indicator'`.
  2. Convert `TaskInfoDialog` (`lib/ui/widgets/task_info_dialog.dart`) to `ConsumerStatefulWidget` with deterministic `TextEditingController` disposal (`P-DISPOSE-RESOURCES`), tight horizontal sizing (`SizedBox(width: 420)`) compatible with `AlertDialog` intrinsic queries and lazy `ListView.builder` virtualization (`> 5` entries per `P-LAZY-LISTS`), live `taskNotifierProvider` reactivity, quick inline append (`clockProvider`), inline `<text>` editing, single-tap deletion, and atomic `TdfException` / `FormatException` error handling (`P-ATOMIC-STATE`).
  3. Implement `TaskEditorHistorySection` and `TaskHistoryInputValidator` (`lib/ui/widgets/task_editor_history_section.dart`) and integrate them into `EditTaskScreen` (`lib/ui/edit_task_screen.dart`) for batch history creation, local wall-clock timestamp (`YYYY-MM-DD [HH:MM[:SS]]`) and `<text>` (`1..500` Unicode scalar values) editing, untouched entry preservation, pending-input validation in `_validateAndBuildDraft`, and persistence through both `TaskNotifier.addTask` and `TaskNotifier.updateTask`.
  4. Preserve `currentTask.history` in `TaskBoardUndo._applyComplete` and `TaskBoardUndo._applyDowngrade` (`lib/models/task_board_undo.dart`), matching `currentTask.title`, `note`, `links`, and `origin`.
  5. Enforce strict passive-text rendering (`SelectableText` only; never passed to `LinkLauncherRepository`), redacted `AppLogger` telemetry (`id`, `history_count`, `reason`, `kind`, and boolean field flags only; never logging `entry.text` per `P-SECRET-HYGIENE`), and complete English (`en`) and German (`de`) localization (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`).
* **Non-Goals:**
  1. Modifying the `TDF 0.7.0` `history` grammar, canonical sort/deduplication rules, occurrence-independent set merge, or `maxTdfHistoryPerTask = 500` / `maxTdfStmtsPerBlock = 1024` bounds delivered in `TEP-006` (`spec/TDF_SPEC_0.7.0.md`).
  2. Changing `TaskNotifier` method signatures in `lib/providers/task_providers.dart` (which already expose `addTaskHistoryEntry`, `updateTaskHistoryEntry`, `removeTaskHistoryEntry`, and `Iterable<TaskHistoryEntry>? history` on `addTask` and `updateTask`).
  3. Supporting multi-line paragraphs, Markdown formatting, or clickable hyperlink auto-detection inside `history` `<text>` (`spec/TDF_SPEC_0.7.0.md` Section 2.8 restricts `<text>` to single-line `1..500` Unicode scalar values; actionable URIs use `link "<title>" "<uri>"`).
  4. Automatic system-generated history entries on tier moves, completions, or subtask toggles (all `history` entries are explicit user-authored journal records).

### 1.4 Description

#### 1.4.1 Task Pill Indicator (`history_task_indicator`)
In `resolveTaskIndicatorSpecs` (`lib/ui/widgets/tier_task_subtasks_section.dart`):
* Whenever `task.history.isNotEmpty`, emit `(icon: Icons.history_rounded, keyPrefix: 'history_task_indicator', tooltip: localizations.tooltipIndicatorHistory)` directly after `links_task_indicator` and before `subtasks_task_indicator` (mirroring canonical `task` directive order `13: link`, `14: history`, `16: subtasks` in `spec/TDF_SPEC_0.7.0.md` Section 4.1.2).
* When `<= 3` indicators (`maxVisibleTaskIndicators`) are active on `TierTaskPill`, `history_task_indicator_<taskId>` renders directly and opens `showTaskInfoDialog(context, task: task, initialIndicatorKeyPrefix: 'history_task_indicator')`. When `> 3` indicators are active, `TierTaskPill` collapses them into `summary_task_indicator_<taskId>` as usual.

#### 1.4.2 Interactive History Journal in `TaskInfoDialog`
`TaskInfoDialog` (`lib/ui/widgets/task_info_dialog.dart`) becomes a `ConsumerStatefulWidget` (`_TaskInfoDialogState`) watching `boundaryTickProvider`, `taskNotifierProvider`, `webDavConfigProvider`, and `clockProvider`:
* **Live Task & Board-Managed Guard:**
  - Resolves `final liveBoardTask = board.findTask(widget.task.id);`, `final isBoardManaged = liveBoardTask != null;`, `final currentTask = liveBoardTask ?? widget.task;`, and `final canMutateHistory = isBoardManaged && !_isMutatingHistory;`.
  - When `TaskInfoDialog` is mounted against a populated `TaskBoard` in production (or `pumpLeafWidget` tests seeding `board`), `isBoardManaged` is `true` and inline mutations persist through `TaskNotifier`. When `widget.task` is mounted standalone against `TaskBoard.empty()` or deleted externally while the dialog is open (`liveBoardTask == null`), `currentTask` still renders cleanly while history inputs and mutation buttons are disabled (`canMutateHistory == false`).
  - If `didUpdateWidget` observes `oldWidget.task.id != widget.task.id`, `_TaskInfoDialogState` resets `_appendController`, `_editController`, `_editingEntry`, `_historyErrorMessage`, and `_isMutatingHistory`.
* **Tight Dialog Width & Virtualized List Layout (`P-LAZY-LISTS`):**
  - Material `AlertDialog` queries intrinsic widths on `content`, which throws a Flutter layout exception if an unbounded `ListView.builder` (`RenderViewport`) sits inside `ConstrainedBox(maxWidth: 420)`.
  - `_buildDialogContent` wraps the scrollable column in a tight `SizedBox(width: 420, child: SingleChildScrollView(...))` (matching `SelectLocalTdfDialog` in `lib/ui/widgets/local_tdf_file_dialogs.dart` and `EditLocationsScreen` dialogs).
  - `_TaskInfoHistoryCard` (`ValueKey('task_info_section_history_task_indicator')`) is always rendered as the final card in the dialog stack (even when `currentTask.history.isEmpty`, displaying `Text(localizations.historyEmptyHint, key: const ValueKey('task_info_history_empty_hint'))`) and highlighted when `widget.initialIndicatorKeyPrefix == 'history_task_indicator'`.
  - When `1 <= currentTask.history.length <= 5`, rows render inside a `Column`. When `currentTask.history.length > 5`, rows render inside `SizedBox(height: 220, child: ListView.builder(key: const ValueKey('task_info_history_list'), itemCount: entries.length, itemBuilder: ...))` without `shrinkWrap: true`, preserving $O(1)$-visible-window lazy virtualization up to `500` entries.
* **Chronological Local-Time Rows:**
  - Entries in `currentTask.history` (normalized in ascending UTC second + unsigned UTF-8 `<text>` byte order) render in chronological order (`0 .. entries.length - 1`).
  - Each display row (`ValueKey('task_info_history_row_$index')`) renders `TaskItem.formatTdfTimestamp(configuration.toLocalWallClock(entry.timestampUtc))` (`ValueKey('task_info_history_timestamp_$index')`) above passive `SelectableText(entry.text, key: ValueKey('task_info_history_text_$index'))`, paired with compact edit (`ValueKey('task_info_history_edit_$index')`, enabled when `canMutateHistory`) and delete (`ValueKey('task_info_history_delete_$index')`, enabled when `canMutateHistory`) icon buttons.
* **Quick Inline Append (`clockProvider` UTC Default):**
  - Below the entry list, `_TaskInfoHistoryAppendRow` renders a single-line `ClearableTextField` (`fieldKey: const ValueKey('task_info_history_input')`, `clearButtonKey: const ValueKey('task_info_history_clear_button')`, `showClearWhenUnfocused: true`, `enabled: canMutateHistory`) and an add `IconButton` (`ValueKey('task_info_history_add_button')`, enabled when `canMutateHistory && currentTask.history.length < maxTdfHistoryPerTask`).
  - Submitting via `Enter` (`onSubmitted`) or `task_info_history_add_button`:
    1. Returns immediately if `!canMutateHistory`.
    2. Sanitizes `_appendController.text` via `TaskHistoryInputValidator.sanitizeSingleLineText` and validates it via `TaskHistoryInputValidator.validateText`; on failure, sets `_historyErrorMessage` (`ValueKey('task_info_history_error_text')`) and logs `ui.task_info.history_validation_failed`.
    3. Computes `timestampUtc = TaskItem.normalizeTimestamp(ref.read(clockProvider)().toUtc())`; if `!TdfCalendar.isWithinTimestampBounds(timestampUtc)`, sets `_historyErrorMessage = localizations.historyErrorTimestampInvalid`.
    4. Constructs `candidate = TaskHistoryEntry(timestampUtc: timestampUtc, text: sanitizedText)` and checks whether `candidate` is already present in `currentTask.history`: if absent and `currentTask.history.length >= maxTdfHistoryPerTask` (`500`), sets `_historyErrorMessage = localizations.historyErrorMaxExceeded` without calling `TaskNotifier`.
    5. Otherwise sets `_isMutatingHistory = true` and awaits `ref.read(taskNotifierProvider.notifier).addTaskHistoryEntry(currentTask.id, timestampUtc: timestampUtc, text: sanitizedText)`. Duplicate `(timestampUtc, text)` pairs short-circuit as a pure no-op inside `TaskNotifier` (`updatedBoard == boardBefore`) without advancing `task.modified` or writing to storage. After `await` (`if (!mounted) return;`), `_appendController` clears (and `ui.task_info.history_added` is logged) strictly when the post-`await` live task on `taskNotifierProvider` contains `candidate` (`P-ATOMIC-STATE`, preserving user-typed text if local `.tdf` persistence rolled back).
* **Inline Row `<text>` Edit & Delete Across Live Syncs:**
  - `_TaskInfoDialogState` tracks `TaskHistoryEntry? _editingEntry` by immutable value rather than raw list index, resolving `activeEditingIndex = switch (_editingEntry) { final target? when isBoardManaged => currentTask.history.indexOf(target), _ => -1 }` (`P-NULL-SAFE`). If an external `Directory.watch` reconciliation inserts an earlier history entry while the user is editing a row, `indexOf` shifts `activeEditingIndex` to the entry's updated position without losing `_editController.text`; if the edited entry or task is externally removed/replaced, `ref.listen(taskNotifierProvider, ...)` clears `_editingEntry` and `_editController` cleanly.
  - Tapping `task_info_history_edit_$index` sets `_editingEntry = entry`, seeds `_editController.text = entry.text`, and clears `_historyErrorMessage`, switching that row to `_TaskInfoHistoryInlineEditor` (`fieldKey: ValueKey('task_info_history_edit_input_$index')`, `clearButtonKey: ValueKey('task_info_history_edit_clear_$index')`, `enabled: canMutateHistory`, save `ValueKey('task_info_history_edit_save_$index')`, cancel `ValueKey('task_info_history_edit_cancel_$index')`).
  - Saving an inline edit preserves `entry.timestampUtc` (full timestamp + text editing is provided in `EditTaskScreen`):
    - If `_editController.text == entry.text` (untouched text, including any external leading/trailing `0x20` spaces), exits edit mode immediately without calling `TaskNotifier`.
    - Otherwise sanitizes and validates `_editController.text`, constructs `replacement = TaskHistoryEntry(timestampUtc: entry.timestampUtc, text: sanitizedText)`, and awaits `TaskNotifier.updateTaskHistoryEntry(currentTask.id, oldTimestampUtc: entry.timestampUtc, oldText: entry.text, newTimestampUtc: entry.timestampUtc, newText: sanitizedText)`, clearing `_editingEntry` and `_editController` after `await` strictly when the post-`await` live task contains `replacement` (`P-ATOMIC-STATE`).
  - Tapping `task_info_history_delete_$index` clears `_editingEntry` if `entry == _editingEntry` and awaits `TaskNotifier.removeTaskHistoryEntry(currentTask.id, timestampUtc: entry.timestampUtc, text: entry.text)`.
  - Any synchronous `TdfException` or `FormatException` (such as `9999-12-31 23:59:59` UTC `modifiedAt` overflow) is caught, resets `_isMutatingHistory = false` in `finally`, preserves user input, and surfaces a localized inline `_historyErrorMessage`.

#### 1.4.3 Batch & Timestamp-Editable `TaskEditorHistorySection` in `EditTaskScreen`
`TaskEditorHistorySection` (`lib/ui/widgets/task_editor_history_section.dart`, `cardKey: const ValueKey('task_editor_history_card')`) is rendered inside `_EditTaskFormColumn` in `EditTaskScreen` (`lib/ui/edit_task_screen.dart`) directly below `_EditTaskSubtasksAndLinksSection` and above `_EditTaskBlockedBySection`:
* **Draft State & Canonical Normalization:**
  - `_EditTaskScreenState` initializes `late List<TaskHistoryEntry> _historyEntries` from `List<TaskHistoryEntry>.of(task?.history ?? const <TaskHistoryEntry>[])` (already canonically ordered).
  - Adding or updating a draft entry normalizes `_historyEntries` via `TaskHistoryEntry.normalizeList(...)` (`lib/models/task_item.dart:120`) so the editor list immediately reflects canonical chronological + UTF-8 byte order and exact `(timestampUtc, text)` deduplication.
* **Local Wall-Clock Timestamp & `<text>` Authoring:**
  - `TaskEditorHistorySection` provides:
    1. Optional local wall-clock timestamp field (`ValueKey('editor_history_timestamp_input')`, clear button `ValueKey('editor_history_timestamp_clear_button')`, date picker `ValueKey('editor_history_date_picker_button')`, 24-hour time picker `ValueKey('editor_history_time_picker_button')`) accepting `YYYY-MM-DD`, `YYYY-MM-DD HH:MM`, or `YYYY-MM-DD HH:MM:SS` in workspace local time (`WebDavConfig.localWallClockToUtc`). When left blank during add or edit, the timestamp defaults to `TaskItem.normalizeTimestamp(ref.read(clockProvider)().toUtc())`.
    2. Single-line `<text>` field (`ValueKey('editor_history_text_input')`, clear button `ValueKey('editor_history_text_clear_button')`) with add/update `IconButton` (`ValueKey('editor_add_history_button')`, `Icons.add_rounded` when adding, `Icons.check_rounded` when editing) and conditional cancel-edit `IconButton` (`ValueKey('editor_cancel_edit_history_button')`, shown when `editingIndex != null`).
  - Existing draft entries render in a `Column` when `1 <= entries.length <= 5` and inside `SizedBox(height: 240, child: ListView.builder(key: const ValueKey('editor_history_list'), ...))` when `entries.length > 5` (`P-LAZY-LISTS`). Each row (`ValueKey('editor_history_item_${entry.timestampUtc.millisecondsSinceEpoch}_$index')`) displays `TaskItem.formatTdfTimestamp(configuration.toLocalWallClock(entry.timestampUtc))` and passive `SelectableText(entry.text)` alongside edit (`ValueKey('editor_edit_history_$index')`) and remove (`ValueKey('editor_remove_history_$index')`) buttons.
  - **Untouched Timestamp & Text Fidelity:** Tapping `editor_edit_history_$index` records `_editingHistoryIndex = index`, `_editingHistoryOriginalEntry = entry`, and `_editingHistoryInitialTimestampText = formattedLocalTimestamp`, populating both controllers. If the user saves the edited row without modifying `_historyTimestampController.text.trim()`, `TaskHistoryInputValidator.resolveEntryTimestampUtc` preserves `entry.timestampUtc` verbatim (avoiding OS DST fall-back fold drift and `0001`/`9999` local-offset round-trip shifts); if neither timestamp text nor `_historyTextController.text` changed, `entry` is retained verbatim.
  - **Index Coherence on Cancel & Row Removal:** Tapping `editor_cancel_edit_history_button` (`_cancelEditHistoryEntry`) resets `_editingHistoryIndex = null`, `_editingHistoryOriginalEntry = null`, `_editingHistoryInitialTimestampText = null`, and `_historyErrorMessage = null`, and clears both `_historyTimestampController` and `_historyTextController` so canceled edits never remain as pending form input. Removing row `index` similarly cancels the active edit and clears the history inputs when `index == _editingHistoryIndex`, decrements `_editingHistoryIndex` by `1` when `index < _editingHistoryIndex`, and leaves `_editingHistoryIndex` unchanged when `index > _editingHistoryIndex`.
* **Atomic Pending Input Guard on Form `Save`:**
  - When `_editingHistoryIndex != null || _historyTimestampController.text.trim().isNotEmpty || _historyTextController.text.isNotEmpty`, `_validateAndBuildDraft` validates the pending history input alongside all other form fields: if invalid (malformed/out-of-bounds timestamp, empty/whitespace-only text, control characters/unpaired surrogates, `> 500` Unicode scalar values, or `> 500` normalized entries), submission aborts atomically in the same `setState` pass, displaying `ValueKey('editor_history_error_text')` without mutating `_historyEntries` or board state.
  - When valid, `_ValidatedTaskDraft.history` carries the normalized `List<TaskHistoryEntry>` into `_persistTask`, which passes `history: draft.history` to **both** `TaskNotifier.updateTask` and `TaskNotifier.addTask`.

#### 1.4.4 Undo History Preservation in `TaskBoardUndo`
In `lib/models/task_board_undo.dart`:
* **`_applyComplete`:** Omit `history: snapshotTask.history` from `currentTask.copyWith(...)` so `currentTask.history` (including any entries appended, edited, or deleted after completing a one-off or recurring task) is preserved unchanged when completion is undone.
* **`_applyDowngrade`:** Remove `!listEquals(currentTask.history, snapshotTask.history)` from `taskChanged` and omit `history: snapshotTask.history` from `currentTask.copyWith(...)` so `currentTask.history` is preserved unchanged when a tier downgrade is undone (and logging a history entry on an already-restored task does not falsely make `taskChanged == true`).
* **`_applyDelete`:** Retain `history: snapshotTask.history` on `snapshotTask.copyWith(...)` because a deleted task has no live `currentTask` on `currentBoard` and `Undelete` restores its pre-deletion history journal.

#### 1.4.5 Security, Telemetry Redaction & Platform Ergonomics
* **Passive Plain-Text Security:** Every rendered history entry in `TaskInfoDialog` and `TaskEditorHistorySection` uses `SelectableText` with zero gesture recognizers, `LinkLauncherRepository` calls, or filesystem path resolution (`spec/TDF_SPEC_0.7.0.md` Section 4.1.2).
* **Diagnostic Telemetry Redaction (`P-SECRET-HYGIENE`, `AGENTS.md` Section 6):** `TaskBoardMutator` and `TaskBoardEvaluator` already emit `LogTag.domain` events `task.history_add`, `task.history_update`, and `task.history_remove` with `id` and `historyCount` only. `TaskInfoDialog` and `EditTaskScreen` emit `AppLogger.shouldLog(...)`-gated `LogTag.ui` events recording only `id`, `history_count`, `reason`, `kind`, and boolean field flags (`history: hasHistoryError`), never logging `entry.text` or raw user input.
* **Platform Ergonomics (`Linux`, `Android`, `Windows`):** Single-line history inputs use `TextInputAction.done` so pressing `Enter` on Linux/Windows hardware keyboards or the Android IME action button commits the entry immediately, while `SelectableText` supports desktop click-drag copy and Android selection handles.

### 1.5 Alternatives
1. **Allow Editing History Only in `EditTaskScreen` (Read-Only `TaskInfoDialog`):** Rejected because `TEP-006` targets low-friction progress logging on `Blocked` and active tasks directly from `TaskInfoDialog` without opening the full task editor. Supporting quick single-line append/edit/delete in `TaskInfoDialog` alongside full timestamp + batch editing in `EditTaskScreen` serves both fast daily capture and structured backdated maintenance.
2. **Track Active Inline Row Edit in `TaskInfoDialog` by Raw `int? _editingIndex`:** Rejected because an external `Directory.watch` `.tdf` synchronization can insert an older chronological entry at index `0` while the user is editing row `0`, shifting the target entry to index `1` and causing raw-index tracking to overwrite the wrong entry on save. Tracking `TaskHistoryEntry? _editingEntry` by immutable value resolves the current index dynamically via `indexOf` and cleanly cancels if the target entry was externally removed or modified.
3. **Keep `ConstrainedBox(maxWidth: 420)` Around `ListView.builder` in `TaskInfoDialog`:** Rejected because Flutter's `AlertDialog` wraps `content` in `IntrinsicWidth`, causing `RenderViewport` inside `ListView.builder` (without `shrinkWrap: true`) to throw an intrinsic-dimension layout exception. Using a tight `SizedBox(width: 420)` for the dialog content root and a tight `SizedBox(height: 220)` when `entries.length > 5` satisfies both `AlertDialog` layout invariants and `P-LAZY-LISTS`.
4. **Auto-Linkify `https://` Substrings Inside `history` `<text>`:** Rejected because `spec/TDF_SPEC_0.7.0.md` Section 4.1.2 mandates that `history` `<text>` remain strictly passive plain text; clickable URIs belong in scheme-validated `link "<title>" "<uri>"` directives.
5. **Store Per-Entry Local Timezone Offsets in `.tdf`:** Rejected because `spec/TDF_SPEC_0.7.0.md` Sections 4.1.2 and 7.1 store all `history` timestamps in normalized UTC (`YYYY-MM-DD HH:MM:SS`), converting to/from workspace local time via `WebDavConfig.toLocalWallClock` and `WebDavConfig.localWallClockToUtc` at the UI boundary.

## Part 2: Technical Design & Code Changes

### 2.1 Architecture & Affected Modules

All changes preserve the acyclic bottom-up import DAG (`P-ACYCLIC-DAG`: `0` SCCs; `lib/models/task_board_undo.dart` at Rank `1`; `lib/l10n/*` at Rank `2`; `lib/ui/*` at Rank `6` importing only Ranks `0`, `1`, `2`, `4`, and `5` without peer cycles) and keep `lib/models/` and `lib/ui/` free of `dart:io` imports (`P-IO-ISOLATION`).

| Layer | File | Change Type | Responsibility |
| :--- | :--- | :--- | :--- |
| Models (`Rank 1`) | `lib/models/task_board_undo.dart` | Modify | Preserve live `currentTask.history` in `_applyComplete` and `_applyDowngrade` while retaining `snapshotTask.history` in `_applyDelete`. |
| Localization (`Rank 2`) | `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb` | Modify | Add 17 English and German ARB keys (with full `@key` metadata blocks) for the History Journal section, pill indicator tooltip, inputs, tooltips, and validation errors; regenerate `lib/l10n/app_localizations*.dart` via `flutter gen-l10n`. |
| UI (`Rank 6`) | `lib/ui/widgets/tier_task_subtasks_section.dart` | Modify | Append `history_task_indicator` (`Icons.history_rounded`) to `resolveTaskIndicatorSpecs` after `links_task_indicator` when `task.history.isNotEmpty`. |
| UI (`Rank 6`) | `lib/ui/widgets/task_info_dialog.dart` | Modify | Upgrade `TaskInfoDialog` to `ConsumerStatefulWidget`, switch dialog root to tight `SizedBox(width: 420)`, and add `_TaskInfoHistoryCard` + decomposed row/append/edit leaf widgets with `ListView.builder` (`> 5` entries), value-tracked `_editingEntry`, `TdfException`/`FormatException` handling, and redacted `LogTag.ui` telemetry. |
| UI (`Rank 6`) | `lib/ui/widgets/task_editor_history_section.dart` | New | Define `TaskHistoryInputValidator` (`sanitizeSingleLineText`, `validateText`, `resolveEntryTimestampUtc`) and `TaskEditorHistorySection` (`pickHistoryDate`, `pickHistoryTime`, and decomposed private list/row/input widgets keeping every `build()` `< 40` lines). |
| UI (`Rank 6`) | `lib/ui/edit_task_screen.dart` | Modify | Manage `_historyEntries`, `_historyTimestampController`, `_historyTextController`, `_editingHistoryIndex`, `_editingHistoryOriginalEntry`, `_editingHistoryInitialTimestampText`, and `_historyErrorMessage`; watch `webDavConfigProvider`; embed `_EditTaskHistorySection`; validate pending history input in `_validateAndBuildDraft`; forward `history: draft.history` to both `addTask` and `updateTask`; route `limitExceeded` history persistence errors; include redacted history fields in `LogTag.ui` telemetry. |
| Tooling | `.agents/scripts/tiertask_dev.py` | Modify | Register `"lib/ui/widgets/task_editor_history_section.dart"` in `_SUBSYSTEM_TEST_MAP` mapping to `["test/ui/widgets/task_editor_history_section_test.dart", "test/ui/edit_task_screen_test.dart"]` (`P-TEST-MIRROR`). |
| Documentation | `ARCHITECTURE.md`, `CHANGELOG.md` | Modify | Add `lib/ui/widgets/task_editor_history_section.dart` and update `task_board_undo.dart`, `edit_task_screen.dart`, `task_info_dialog.dart`, and `tier_task_pill.dart` rows (`<= 65` words per row), sync the ASCII directory tree (`tiertask_dev.py arch --sync-tree`), and add a `CHANGELOG.md` entry under `## [Unreleased]`. |
| Tests | `test/models/task_board_undo_test.dart`, `test/providers/task_providers_test.dart`, `test/ui/widgets/tier_task_subtasks_test.dart`, `test/ui/widgets/tier_task_pill_test.dart`, `test/ui/widgets/task_info_dialog_test.dart`, `test/ui/widgets/task_editor_history_section_test.dart`, `test/ui/edit_task_screen_test.dart` | Modify / New | Red-Green-Refactor unit and widget tests covering all `M-*` categories (`M-EXHAUSTIVE-STATE-TESTS`, `M-EXTREME-BOUND-TESTS`, `M-DELIM-INJECT-TESTS`, `M-URI-PATH-EDGE-TESTS`, `M-IO-TESTS`, `M-REAL-MECHANICS-TESTS`). |

### 2.2 TDF Schema, Localization & State Changes

#### 2.2.1 TDF `0.7.0` Schema & Existing Runtime Primitives (`TEP-006`)
No changes to `spec/TDF_SPEC_0.7.0.md`, `lib/services/`, `lib/repositories/`, or `lib/providers/task_providers.dart` are required; `TEP-012` builds directly on these implemented APIs:
* `lib/models/tdf_error.dart`: `const int maxTdfHistoryPerTask = 500;`, `const int maxTdfTextLength = 500;`, `const int maxTdfStmtsPerBlock = 1024;`, `TdfException`, and `TdfErrorKind`.
* `lib/models/tdf_timezone.dart`: `TdfCalendar.countUnicodeScalars(String value)` (single-pass $O(N)$ Unicode scalar counter returning `null` on unpaired UTF-16 surrogates `0xD800..0xDFFF`) and `TdfCalendar.isWithinTimestampBounds(DateTime instant)` (`0001-01-01 00:00:00..9999-12-31 23:59:59` UTC).
* `lib/models/task_item.dart`: `TaskHistoryEntry({required DateTime timestampUtc, required String text})`, `TaskHistoryEntry.compareCanonical(TaskHistoryEntry a, TaskHistoryEntry b)`, `TaskHistoryEntry.normalizeList(Iterable<TaskHistoryEntry> entries)`, `TaskItem.normalizeTimestamp(DateTime timestamp)`, `TaskItem.formatTdfTimestamp(DateTime timestamp)`, and `TaskItem.tryParseTdfTimestampInput(String rawInput)`.
* `lib/models/webdav_config.dart`: `WebDavConfig.toLocalWallClock(DateTime instant)` and `WebDavConfig.localWallClockToUtc(DateTime localWallClock)`.
* `lib/providers/task_providers.dart` (`TaskNotifier`):
  - `Future<void> addTaskHistoryEntry(String taskId, {required DateTime timestampUtc, required String text, DateTime? currentDate})`
  - `Future<void> updateTaskHistoryEntry(String taskId, {required DateTime oldTimestampUtc, required String oldText, required DateTime newTimestampUtc, required String newText, DateTime? currentDate})`
  - `Future<void> removeTaskHistoryEntry(String taskId, {required DateTime timestampUtc, required String text, DateTime? currentDate})`
  - `Future<void> addTask(..., Iterable<TaskHistoryEntry>? history, ...)` and `Future<void> updateTask(..., Iterable<TaskHistoryEntry>? history, ...)`
  All three `TaskNotifier.*TaskHistoryEntry` methods already short-circuit before `_commitMutation` when `updatedBoard == boardBefore`, and `TaskBoardMutator` / `TaskBoardEvaluator` already emit redacted `LogTag.domain` events `task.history_add`, `task.history_update`, and `task.history_remove` (`id` and `historyCount` only). `FakeTaskNotifier` (`test/ui/test_helpers.dart`) inherits `TaskNotifier` directly and overrides `pushToRemote` in memory, so all history mutations work out of the box in zero-I/O leaf widget tests.

#### 2.2.2 Localization Keys (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`)

Every key in `lib/l10n/app_en.arb` includes a matching `@<key>` metadata block with `"description"` to satisfy `tiertask_dev.py verify` (`audit_l10n`):

| Key | English (`app_en.arb`) | German (`app_de.arb`) | `@key` Metadata (`app_en.arb`) |
| :--- | :--- | :--- | :--- |
| `historySectionTitle` | `"History"` | `"Verlauf"` | `description`: `"Section title for the task history journal card in TaskInfoDialog and EditTaskScreen."` |
| `tooltipIndicatorHistory` | `"Has history entries"` | `"Enthält Verlaufseinträge"` | `description`: `"Tooltip shown on the history indicator icon on a task pill."` |
| `historyEmptyHint` | `"No history entries recorded yet."` | `"Noch keine Verlaufseinträge vorhanden."` | `description`: `"Empty-state hint shown inside the history section of TaskInfoDialog when no history entries exist."` |
| `historyEntryTextLabel` | `"History entry"` | `"Verlaufseintrag"` | `description`: `"Input label for the single-line history entry text field."` |
| `historyEntryTextHint` | `"Add progress update or note"` | `"Fortschritt oder Notiz erfassen"` | `description`: `"Placeholder hint for the single-line history entry text field."` |
| `historyTimestampLabel` | `"Timestamp (optional, defaults to now)"` | `"Zeitstempel (optional, Standard: jetzt)"` | `description`: `"Input label for the optional local wall-clock history timestamp field in EditTaskScreen."` |
| `historyTimestampHint` | `"YYYY-MM-DD HH:MM"` | `"JJJJ-MM-TT Std:Min"` | `description`: `"Placeholder hint for the optional local wall-clock history timestamp field."` |
| `tooltipAddHistoryEntry` | `"Add history entry"` | `"Verlaufseintrag hinzufügen"` | `description`: `"Tooltip for the button that appends a history entry."` |
| `tooltipEditHistoryEntry` | `"Edit history entry"` | `"Verlaufseintrag bearbeiten"` | `description`: `"Tooltip for starting an edit of an existing history entry row."` |
| `tooltipSaveHistoryEntry` | `"Update history entry"` | `"Verlaufseintrag aktualisieren"` | `description`: `"Tooltip for confirming an edit to an existing history entry."` |
| `tooltipCancelEditHistoryEntry` | `"Cancel history edit"` | `"Bearbeitung abbrechen"` | `description`: `"Tooltip for canceling an active edit of a history entry."` |
| `tooltipDeleteHistoryEntry` | `"Delete history entry"` | `"Verlaufseintrag löschen"` | `description`: `"Tooltip for deleting a history entry row."` |
| `historyErrorTextEmpty` | `"Enter a history text."` | `"Bitte einen Verlaufstext eingeben."` | `description`: `"Validation error shown when a history entry text is empty or spaces-only."` |
| `historyErrorTextTooLong` | `"History entry must not exceed 500 characters."` | `"Verlaufseintrag darf maximal 500 Zeichen lang sein."` | `description`: `"Validation error shown when a history entry exceeds 500 Unicode scalar values."` |
| `historyErrorTextInvalid` | `"History entry contains unsupported control characters."` | `"Verlaufseintrag enthält nicht unterstützte Steuerzeichen."` | `description`: `"Validation error shown when a history entry contains disallowed control characters or unpaired UTF-16 surrogates."` |
| `historyErrorTimestampInvalid` | `"Enter a valid date (YYYY-MM-DD) and optional time (HH:MM)."` | `"Gültiges Datum (JJJJ-MM-TT) und optionale Uhrzeit (Std:Min) eingeben."` | `description`: `"Validation error shown when a history timestamp is malformed or outside 0001..9999 UTC."` |
| `historyErrorMaxExceeded` | `"Maximum of 500 history entries per task reached."` | `"Maximal 500 Verlaufseinträge pro Aufgabe erreicht."` | `description`: `"Validation error shown when adding a distinct entry would exceed 500 history entries on a task."` |

### 2.3 Implementation Details

#### 2.3.1 Undo Live-History Preservation (`lib/models/task_board_undo.dart`)
* In `TaskBoardUndo._applyComplete` (`lib/models/task_board_undo.dart:196-223`), remove `history: snapshotTask.history,` from `currentTask.copyWith(...)` so `restoredTask.history` inherits `currentTask.history`.
* In `TaskBoardUndo._applyDowngrade` (`lib/models/task_board_undo.dart:514-560`), remove `!listEquals(currentTask.history, snapshotTask.history) ||` from `taskChanged` and remove `history: snapshotTask.history,` from `currentTask.copyWith(...)` so `replacementTask.history` inherits `currentTask.history`.
* Keep `history: snapshotTask.history,` in `TaskBoardUndo._applyDelete` (`lib/models/task_board_undo.dart:384`).

#### 2.3.2 Task Pill Indicator (`lib/ui/widgets/tier_task_subtasks_section.dart`)
* In `resolveTaskIndicatorSpecs(TaskItem task, AppLocalizations localizations)` (`lib/ui/widgets/tier_task_subtasks_section.dart:610-665`), insert directly after `if (task.links.isNotEmpty) ...` and before `if (task.subtasks.isNotEmpty) ...`:
  ```dart
  if (task.history.isNotEmpty)
    (
      icon: Icons.history_rounded,
      keyPrefix: 'history_task_indicator',
      tooltip: localizations.tooltipIndicatorHistory,
    ),
  ```

#### 2.3.3 Single-Line Validation & `TaskEditorHistorySection` (`lib/ui/widgets/task_editor_history_section.dart`)
* **Imports (`P-DIRECTIVES-ORDER`, `P-IO-ISOLATION`):**
  - `package:material_ui/material_ui.dart`
  - `../../l10n/app_localizations.dart`, `../../models/task_item.dart`, `../../models/tdf_error.dart`, `../../models/tdf_timezone.dart`, `../../models/webdav_config.dart`, `../app_theme.dart`, `clearable_text_field.dart`, `task_editor_sections.dart` (strictly ASCII-ordered, zero `dart:io` imports).
* **Stateless Validator `TaskHistoryInputValidator` (`const TaskHistoryInputValidator._()`):**
  ```dart
  class TaskHistoryInputValidator {
    const TaskHistoryInputValidator._();

    static DateTime? resolveEntryTimestampUtc({
      required WebDavConfig configuration,
      required DateTime fallbackNowUtc,
      String? preservedTimestampText,
      DateTime? preservedTimestampUtc,
      required String rawTimestamp,
    });

    static String sanitizeSingleLineText(String rawText);

    static String? validateText(
      String sanitizedText,
      AppLocalizations localizations,
    );
  }
  ```
  - `sanitizeSingleLineText(String rawText)`:
    1. Scans `rawText` once (`0..rawText.length - 1`) to locate `firstKeep` and `lastKeep` (outermost indices whose code unit is not in ASCII trim whitespace `{0x09, 0x0A, 0x0D, 0x20}`) and checks whether any code unit inside `firstKeep..lastKeep` is `0x09`, `0x0A`, or `0x0D`. Non-ASCII graphic whitespace such as `U+00A0` is NOT treated as trim whitespace (`spec/TDF_SPEC_0.7.0.md` Section 2.8).
    2. If `firstKeep < 0`, returns `''` with zero allocations.
    3. If no internal `\t`/`\n`/`\r` exists inside `firstKeep..lastKeep`, returns `rawText` directly when `firstKeep == 0 && lastKeep == rawText.length - 1`, or `rawText.substring(firstKeep, lastKeep + 1)` (`P-ZERO-COPY`).
    4. Otherwise delegates to file-private `_replaceInternalBreaksWithSpaces(rawText, firstKeep, lastKeep)`, which runs one flat `for` loop (`< 25` lines per `P-LOOP-MODULARITY`) writing `' '` (`0x20`) for `\r\n` (`0x0D` followed by `0x0A`, advancing `i` by `1`), standalone `\r` (`0x0D`), standalone `\n` (`0x0A`), and `\t` (`0x09`), and `writeCharCode(unit)` for all other units (preserving internal `0x20` runs).
  - `validateText(String sanitizedText, AppLocalizations localizations)`:
    1. Calls `final scalarCount = TdfCalendar.countUnicodeScalars(sanitizedText);`; if `scalarCount == null` (unpaired UTF-16 surrogate in `0xD800..0xDFFF`), returns `localizations.historyErrorTextInvalid`.
    2. Scans `sanitizedText` once (`0..sanitizedText.length - 1`): if `unit <= 0x1F || unit == 0x7F`, returns `localizations.historyErrorTextInvalid` (checked before emptiness, matching `TaskBoardMutator._validateSingleLineText`); records `hasGraphic = true` whenever `unit != 0x20`.
    3. If `!hasGraphic` (`sanitizedText.isEmpty` or spaces-only `"   "`), returns `localizations.historyErrorTextEmpty`.
    4. If `scalarCount > maxTdfTextLength` (`500`), returns `localizations.historyErrorTextTooLong`.
    5. Returns `null`.
  - `resolveEntryTimestampUtc(...)`:
    1. Computes `final trimmed = rawTimestamp.trim();`.
    2. If `trimmed.isEmpty`: computes `final normalizedFallback = TaskItem.normalizeTimestamp(fallbackNowUtc);` and returns `TdfCalendar.isWithinTimestampBounds(normalizedFallback) ? normalizedFallback : null`.
    3. If `preservedTimestampUtc != null && preservedTimestampText != null && trimmed == preservedTimestampText`: computes `final normalizedPreserved = TaskItem.normalizeTimestamp(preservedTimestampUtc);` and returns `TdfCalendar.isWithinTimestampBounds(normalizedPreserved) ? normalizedPreserved : null`.
    4. Otherwise parses `final parsedLocal = TaskItem.tryParseTdfTimestampInput(trimmed);` (returning `null` if malformed), converts `final convertedUtc = TaskItem.normalizeTimestamp(configuration.localWallClockToUtc(parsedLocal));`, and returns `TdfCalendar.isWithinTimestampBounds(convertedUtc) ? convertedUtc : null` (rejecting local-to-UTC offset shifts into year `0000` or `10000` before `TaskBoardMutator` throws).
* **`TaskEditorHistorySection` (`StatelessWidget`) & Decomposed Private Widgets (`P-FLATTEN-BUILD`, `P-LAZY-LISTS`):**
  ```dart
  class TaskEditorHistorySection extends StatelessWidget {
    const TaskEditorHistorySection({
      super.key,
      required this.configuration,
      this.editingIndex,
      required this.entries,
      this.errorMessage,
      required this.onAddOrSaveEntry,
      required this.onCancelEdit,
      required this.onClearTimestamp,
      required this.onEditEntry,
      required this.onPickDate,
      required this.onPickTime,
      required this.onRemoveEntry,
      required this.textController,
      required this.timestampController,
    });
    ...
    static Future<String?> pickHistoryDate({
      required BuildContext context,
      required String currentText,
      required DateTime fallbackLocal,
    });

    static Future<String?> pickHistoryTime({
      required BuildContext context,
      required String currentText,
      required DateTime fallbackLocal,
    });
  }
  ```
  - `pickHistoryDate`: Resolves an initial date from `currentText`'s `YYYY-MM-DD` prefix (when in `2000..2100`) or clamps `fallbackLocal` into `2000-01-01..2100-12-31` so `showDatePicker` never asserts on out-of-range test clocks; preserves any valid existing `HH:MM` or `HH:MM:SS` suffix (`2026-11-15 14:30:45` -> `2026-11-16 14:30:45`).
  - `pickHistoryTime`: Seeds a 24-hour `showTimePicker` (`alwaysUse24HourFormat: true`) from any existing `HH:MM[:SS]` suffix or `TimeOfDay(hour: fallbackLocal.hour, minute: fallbackLocal.minute)`, and formats `'$datePart $hhMm'` using `currentText`'s `YYYY-MM-DD` prefix or `TaskItem.formatIsoDate(fallbackLocal)`.
  - Private widget decomposition (all `build()` methods `< 40` lines):
    - `TaskEditorHistorySection` (`TaskEditorSectionCard` with `cardKey: const ValueKey('task_editor_history_card')`, `icon: Icons.history_rounded`, `title: localizations.historySectionTitle`).
    - `_TaskEditorHistoryList`: Renders a `Column` when `entries.length <= 5` and `SizedBox(height: 240, child: ListView.builder(key: const ValueKey('editor_history_list'), itemCount: entries.length, itemBuilder: ...))` when `entries.length > 5`.
    - `_TaskEditorHistoryRow`: Keyed by `ValueKey('editor_history_item_${entry.timestampUtc.millisecondsSinceEpoch}_$index')`, highlighting the row when `editingIndex == index`, rendering formatted local timestamp + passive `SelectableText(entry.text)` + edit (`ValueKey('editor_edit_history_$index')`) and remove (`ValueKey('editor_remove_history_$index')`) icon buttons.
    - `_TaskEditorHistoryTimestampField`: `ClearableTextField` (`fieldKey: const ValueKey('editor_history_timestamp_input')`, `clearButtonKey: const ValueKey('editor_history_timestamp_clear_button')`, `clearTooltip: localizations.tooltipClearDate`, `showClearWhenUnfocused: true`, `onCleared: onClearTimestamp`) with trailing `editor_history_date_picker_button` and `editor_history_time_picker_button`.
    - `_TaskEditorHistoryTextActionRow`: `ClearableTextField` (`fieldKey: const ValueKey('editor_history_text_input')`, `clearButtonKey: const ValueKey('editor_history_text_clear_button')`, `showClearWhenUnfocused: true`, `textInputAction: TextInputAction.done`, `onSubmitted: (_) => onAddOrSaveEntry()`) paired with `editor_add_history_button` (`Icons.check_rounded` / `tooltipSaveHistoryEntry` when `isEditing`, else `Icons.add_rounded` / `tooltipAddHistoryEntry`) and conditional `editor_cancel_edit_history_button` (`Icons.close_rounded` / `tooltipCancelEditHistoryEntry`).
    - `_TaskEditorHistoryErrorText`: Renders `errorMessage` with `ValueKey('editor_history_error_text')`.

#### 2.3.4 `TaskInfoDialog` Stateful Conversion, Layout & Live Sync (`lib/ui/widgets/task_info_dialog.dart`)
* **Imports (`P-DIRECTIVES-ORDER`):** Add `../../models/tdf_error.dart`, `../../models/tdf_timezone.dart`, `clearable_text_field.dart`, and `task_editor_history_section.dart` in strict ASCII order.
* **`TaskInfoDialog` (`ConsumerStatefulWidget`) & `_TaskInfoDialogState`:**
  - Fields (ordered per `AGENTS.md` Section 2):
    - `final TextEditingController _appendController = TextEditingController();`
    - `final TextEditingController _editController = TextEditingController();`
    - `TaskHistoryEntry? _editingEntry;`
    - `String? _historyErrorMessage;`
    - `bool _isMutatingHistory = false;`
  - Lifecycle:
    - `initState()`: Attaches `_clearHistoryError` listener to `_appendController` and `_editController`.
    - `didUpdateWidget(TaskInfoDialog oldWidget)`: When `oldWidget.task.id != widget.task.id`, clears `_appendController` and `_editController` and resets `_editingEntry = null`, `_historyErrorMessage = null`, and `_isMutatingHistory = false`.
    - `dispose()`: Disposes `_appendController` and `_editController` (`P-DISPOSE-RESOURCES`).
    - `build(BuildContext context)` (`< 40` lines):
      - Registers `ref.listen<AsyncValue<TaskBoard>>(taskNotifierProvider, _handleBoardChanged)` so external board updates that delete `widget.task.id` or remove/replace `_editingEntry` clear stale inline edit state via `setState` outside layout.
      - Watches `boundaryTickProvider`, `taskNotifierProvider`, `webDavConfigProvider`, and `clockProvider`.
      - Resolves `liveBoardTask = board.findTask(widget.task.id)`, `isBoardManaged = liveBoardTask != null`, `currentTask = liveBoardTask ?? widget.task`, `canMutateHistory = isBoardManaged && !_isMutatingHistory`, and `activeEditingIndex = switch (_editingEntry) { final target? when isBoardManaged => currentTask.history.indexOf(target), _ => -1 }`.
      - Passes `sections` plus `_TaskInfoHistoryCard` into `_buildDialogContent` (`SizedBox(width: 420, child: SingleChildScrollView(...))`).
  - Decomposed private leaf widgets (`build()` `< 40` lines each):
    - `_TaskInfoHistoryCard`: Container with `ValueKey('task_info_section_history_task_indicator')`, highlighted border/fill when `widget.initialIndicatorKeyPrefix == 'history_task_indicator'`, header (`Icons.history_rounded`, `localizations.historySectionTitle`), empty hint (`ValueKey('task_info_history_empty_hint')`) or `_TaskInfoHistoryList`, `_TaskInfoHistoryAppendRow`, and optional `_TaskInfoHistoryErrorText` (`ValueKey('task_info_history_error_text')`).
    - `_TaskInfoHistoryList`: `Column` for `<= 5` entries; `SizedBox(height: 220, child: ListView.builder(key: const ValueKey('task_info_history_list'), ...))` for `> 5` entries.
    - `_TaskInfoHistoryRow` & `_TaskInfoHistoryInlineEditor`: Renders display (`task_info_history_row_$index`, `task_info_history_timestamp_$index`, `task_info_history_text_$index`, `task_info_history_edit_$index`, `task_info_history_delete_$index`) or inline `<text>` edit (`task_info_history_edit_input_$index`, `task_info_history_edit_clear_$index`, `task_info_history_edit_save_$index`, `task_info_history_edit_cancel_$index`).
    - `_TaskInfoHistoryAppendRow`: Renders `ClearableTextField` (`task_info_history_input`, `task_info_history_clear_button`) and `IconButton` (`task_info_history_add_button`).
  - Redacted `LogTag.ui` telemetry (`AppLogger.shouldLog(...)` gated):
    - `ui.task_info.history_added`, `ui.task_info.history_updated`, `ui.task_info.history_removed`: `LogLevel.info`, `fields: <String, Object?>{'id': currentTask.id, 'history_count': updatedCount}` (never logging `text`).
    - `ui.task_info.history_validation_failed`: `LogLevel.warn`, `fields: <String, Object?>{'id': currentTask.id, 'reason': reasonCode}`.
    - `ui.task_info.history_persist_rejected`: `LogLevel.warn`, `fields: <String, Object?>{'id': currentTask.id, 'kind': kindLabel}`.

#### 2.3.5 `EditTaskScreen` Integration, Validation & Telemetry (`lib/ui/edit_task_screen.dart`)
* **Imports (`P-DIRECTIVES-ORDER`):** Add `widgets/task_editor_history_section.dart` in strict ASCII order.
* **State & Controller Lifecycle (`_EditTaskScreenState`, `P-DISPOSE-RESOURCES`):**
  - Add fields:
    - `int? _editingHistoryIndex;`
    - `String? _editingHistoryInitialTimestampText;`
    - `TaskHistoryEntry? _editingHistoryOriginalEntry;`
    - `late List<TaskHistoryEntry> _historyEntries;`
    - `String? _historyErrorMessage;`
    - `final TextEditingController _historyTextController = TextEditingController();`
    - `final TextEditingController _historyTimestampController = TextEditingController();`
  - Initialize `_historyEntries = List<TaskHistoryEntry>.of(task?.history ?? const <TaskHistoryEntry>[])` and attach `_handleHistoryInputChanged` listeners in `initState()`; dispose `_historyTextController` and `_historyTimestampController` in `dispose()`.
  - Watch `final configuration = ref.watch(webDavConfigProvider.select((asyncConfig) => asyncConfig.asData?.value ?? const WebDavConfig()));` in `_EditTaskScreenState.build` (`P-SELECT-REBUILDS`), forwarding `configuration` through `_EditTaskScaffoldBody` and `_EditTaskFormColumn` to private `_EditTaskHistorySection` (`< 35` lines).
* **Draft Validation & Persistence:**
  - Extend `_ValidatedTaskDraft` with `List<TaskHistoryEntry> history`.
  - Add `_tryResolvePendingHistoryEntries(WebDavConfig configuration, AppLocalizations localizations)` returning `({List<TaskHistoryEntry> entries, String? error, bool hasPending})`:
    - `hasPending` is `true` whenever `_editingHistoryIndex != null || _historyTimestampController.text.trim().isNotEmpty || _historyTextController.text.isNotEmpty`.
    - When `!hasPending`, returns `(entries: List<TaskHistoryEntry>.unmodifiable(_historyEntries), error: null, hasPending: false)`.
    - When `hasPending`:
      1. If `_editingHistoryIndex case final activeIndex?` and `_editingHistoryOriginalEntry case final original?` where `_historyTimestampController.text.trim() == _editingHistoryInitialTimestampText && _historyTextController.text == original.text`, preserves `original` verbatim.
      2. Otherwise resolves `timestampUtc` via `TaskHistoryInputValidator.resolveEntryTimestampUtc` (returning `localizations.historyErrorTimestampInvalid` if `null`) and validates `sanitizedText = TaskHistoryInputValidator.sanitizeSingleLineText(_historyTextController.text)` via `TaskHistoryInputValidator.validateText` (returning that error if non-null).
      3. Computes `nextEntries = TaskHistoryEntry.normalizeList([for (var i = 0; i < _historyEntries.length; i++) if (i != _editingHistoryIndex) _historyEntries[i], candidate])`. If `nextEntries.length > maxTdfHistoryPerTask` (`500`), returns `(entries: _historyEntries, error: localizations.historyErrorMaxExceeded, hasPending: true)`.
      4. Returns `(entries: nextEntries, error: null, hasPending: true)`.
  - Wire `_addOrSaveHistoryEntry()` to invoke `_tryResolvePendingHistoryEntries` (when `hasPending` is `false`, sets `_historyErrorMessage = localizations.historyErrorTextEmpty` so tapping `+` on blank inputs gives explicit feedback) and update `_historyEntries` + clear inputs/edit state on success, and wire `_cancelEditHistoryEntry()` to reset `_editingHistoryIndex`, `_editingHistoryOriginalEntry`, `_editingHistoryInitialTimestampText`, and `_historyErrorMessage` to `null` and clear `_historyTimestampController` and `_historyTextController`.
  - Extract a small helper or structure `_validateAndBuildDraft` (`<= 3` indentation levels) so `historyResolution.error` participates in the unified form validation check (setting `_historyErrorMessage = historyResolution.error` on failure and logging `'history': historyResolution.error != null` in `ui.edit_task.validation_failed`), and on valid draft assembly (when `historyResolution.hasPending` is `true`) updates `_historyEntries = List<TaskHistoryEntry>.of(historyResolution.entries)`, resets `_editingHistoryIndex`, `_editingHistoryOriginalEntry`, `_editingHistoryInitialTimestampText`, and `_historyErrorMessage` to `null`, clears `_historyTimestampController` and `_historyTextController`, and sets `draft.history = historyResolution.entries` (`P-ATOMIC-STATE`, preserving the committed entry inside `_historyEntries` if `_persistTask` fails synchronously).
  - In `_persistTask(_ValidatedTaskDraft draft)`: pass `history: draft.history` to **both** `notifier.updateTask(...)` and `notifier.addTask(...)`.
  - In `_handlePersistFailure`: if `kind == TdfErrorKind.limitExceeded && _historyEntries.length >= maxTdfHistoryPerTask`, set `_historyErrorMessage = localizations.historyErrorMaxExceeded`; include `'history_count': draft.history.length` in `_logTaskSaved(draft)`.

### 2.4 Testing Strategy
All changes follow strict Red-Green-Refactor TDD (`P-TDD-FIRST`):
* **`M-EXHAUSTIVE-STATE-TESTS`:**
  - `test/models/task_board_undo_test.dart`: Verify `completeTask` (both one-off and `repeat` rollover) and `downgradeTask` followed by `addTaskHistoryEntry`, `updateTaskHistoryEntry`, and `removeTaskHistoryEntry` preserve live `currentTask.history` on `TaskBoardUndo.apply`, whereas `deleteTask` followed by `TaskBoardUndo.apply` restores `snapshotTask.history`.
  - `test/ui/widgets/tier_task_subtasks_test.dart` & `test/ui/widgets/tier_task_pill_test.dart`: Verify `resolveTaskIndicatorSpecs` omits `history_task_indicator` when `task.history.isEmpty`, emits `history_task_indicator` between `links_task_indicator` and `subtasks_task_indicator` when `task.history.isNotEmpty`, opens `TaskInfoDialog` with `task_info_section_history_task_indicator` highlighted on tap, and collapses into `summary_task_indicator` when total active indicators exceed `maxVisibleTaskIndicators` (`3`).
  - `test/ui/widgets/task_info_dialog_test.dart`: Verify `TaskInfoDialog` renders `historyEmptyHint` when `history.isEmpty`, formats entries in workspace local wall-clock time (`AppTimeZoneMode.manual` positive/negative offsets), appends entries via `+` and `Enter` using `clockProvider`, edits `<text>` in place, leaves untouched inline edits as pure no-ops, cancels edits, deletes entries, resets state in `didUpdateWidget` when `widget.task.id` changes, disables mutation controls when `widget.task` is absent from `board`, and renders localized strings in both English (`en`) and German (`de`).
  - `test/ui/widgets/task_editor_history_section_test.dart` & `test/ui/edit_task_screen_test.dart`: Verify creating a new task with multiple history entries (`TaskNotifier.addTask`), editing an existing task's history (`TaskNotifier.updateTask`), date/time picker selection (preserving `:SS` on date changes), blank-timestamp fallback to `clockProvider`, untouched timestamp/text preservation across local offsets, canonical sorting and deduplication in the draft preview, row removal while another or the same row is being edited, and atomic pending-input commit/rejection when `Save` is tapped (including simultaneous `title` + `history` validation errors).
* **`M-EXTREME-BOUND-TESTS`:**
  - `<text>` bounds in `TaskHistoryInputValidator`, `TaskInfoDialog`, and `TaskEditorHistorySection`: `0` chars `""` and ASCII spaces/tabs/newlines `"  \r\n\t "` rejected with `historyErrorTextEmpty`; `1` graphic char and `"\u00A0"` accepted; `500` decoded Unicode scalar values including 4-byte UTF-8 surrogate pairs such as `U+1F4DD` (`1000` UTF-16 code units, `countUnicodeScalars == 500`) accepted; `501` Unicode scalar values rejected with `historyErrorTextTooLong`.
  - Entry count & viewport virtualization bounds: `<= 5` entries render without `ListView`, `6` and `500` entries render inside tight `SizedBox` + `ListView.builder` inside `AlertDialog` (`showTaskInfoDialog`) and `EditTaskScreen` without `IntrinsicWidth` layout exceptions; `499 -> 500` accepted; `501`st distinct entry rejected with `historyErrorMaxExceeded` (`task_info_history_add_button` disabled at `500` while inline edit and delete remain enabled).
  - Proleptic Gregorian timestamp bounds: `0001-01-01 00:00` in `UTC+02:00` (`0000-12-31 22:00:00` UTC) and `9999-12-31 23:00` in `UTC-02:00` (`10000-01-01 01:00:00` UTC) rejected with `historyErrorTimestampInvalid`; editing `<text>` only on an existing `0001-01-01 00:00:00` UTC entry in `UTC-02:00` succeeds via untouched timestamp preservation; `9999-12-31 23:59:59` UTC `modifiedAt` overflow caught cleanly without crashing or closing the UI.
* **`M-DELIM-INJECT-TESTS` & `M-URI-PATH-EDGE-TESTS`:**
  - Author history entries containing `"`, `\`, `'`, `# inline comment`, `{ }`, multi-line clipboard pastes (`"Line 1\r\nLine 2\nLine 3\tTabbed"` -> sanitized to `"Line 1 Line 2 Line 3 Tabbed"`), C0/DEL control chars (`\x00`, `\x07`, `\x7F` -> rejected with `historyErrorTextInvalid`), and unpaired UTF-16 surrogates (`\uD800`, `\uDC00` -> rejected with `historyErrorTextInvalid`); round-trip valid entries through `TdfService.serialize` and `TdfService.parse`.
  - Render history entries containing `https://example.com`, `javascript:alert(1)`, `file:///etc/passwd`, and `../../secret.tdf` in `TaskInfoDialog` and `EditTaskScreen`, tap the rendered text, and assert `FakeLinkLauncherRepository.launchedUris` remains empty.
* **`M-IO-TESTS`:**
  - `test/providers/task_providers_test.dart`: Verify `addTaskHistoryEntry`, `updateTaskHistoryEntry`, and `removeTaskHistoryEntry` persist canonical `.tdf` updates across local and loopback `HttpServer` WebDAV repositories (`HttpOverrides.global = null` in `setUp()`), whereas adding an exact duplicate `(timestampUtc, text)` pair, saving an unchanged inline edit, or removing a non-existent pair performs zero file writes / HTTP `PUT` requests and leaves `task.modified` unchanged.
  - Capture `AppLogger` sink events across `LogTag.domain` and `LogTag.ui` during history add, update, delete, and validation failures, asserting secret/text hygiene (no substring of `entry.text` appears in any log line).
* **`M-REAL-MECHANICS-TESTS`:**
  - Suspend `pushToRemote` with a `Completer<void>` while adding/editing/deleting a history entry in `TaskInfoDialog`: pump mid-flight frames to verify `_isMutatingHistory` disables concurrent mutation taps, verify closing the dialog before `Completer.complete()` disposes controllers without post-unmount `setState` errors, and verify board consistency once persistence completes.
  - While `TaskInfoDialog` is open with an active inline row edit (`_editingEntry`) on task `T`, trigger a real external `.tdf` file reconciliation (`reconcileExternalLocalChanges` / `Directory.watch`) that inserts an earlier chronological history entry and completes a `repeat` occurrence on `T`: verify `TaskInfoDialog` shifts the active inline edit to the entry's new chronological index while preserving `_editController.text`, and cancels the active edit cleanly if a subsequent external sync deletes `_editingEntry` or `T`.
  - Execute a full `completeTask` (and `downgradeTask`) -> `TaskInfoDialog` quick history append -> `undoLastAction()` cycle in `task_providers_test.dart`, verifying the undone open task retains the newly appended history entry on both in-memory `TaskBoard` and serialized `.tdf` storage.

## Part 3: Implementation Record & Tasks

### 3.1 Task Breakdown
- [x] Run `python3 .agents/scripts/tiertask_dev.py verify --fast` to confirm a clean baseline on top of `TEP-006`.
- [x] Add the 17 English and German ARB keys (with `@key` descriptions) to `lib/l10n/app_en.arb` and `lib/l10n/app_de.arb`, run `flutter gen-l10n`, and register `"lib/ui/widgets/task_editor_history_section.dart"` in `.agents/scripts/tiertask_dev.py` `_SUBSYSTEM_TEST_MAP`.
- [x] Write failing unit and widget tests first in `test/models/task_board_undo_test.dart`, `test/providers/task_providers_test.dart`, `test/ui/widgets/tier_task_subtasks_test.dart`, `test/ui/widgets/tier_task_pill_test.dart`, `test/ui/widgets/task_info_dialog_test.dart`, `test/ui/widgets/task_editor_history_section_test.dart`, and `test/ui/edit_task_screen_test.dart` (TDD Red Phase — `P-TDD-FIRST`).
- [x] Update `lib/models/task_board_undo.dart` (`_applyComplete` and `_applyDowngrade`) to preserve live `currentTask.history` (TDD Green Phase).
- [x] Add `history_task_indicator` in `lib/ui/widgets/tier_task_subtasks_section.dart` and implement `lib/ui/widgets/task_editor_history_section.dart` (`TaskHistoryInputValidator` and `TaskEditorHistorySection`) (TDD Green Phase).
- [x] Upgrade `lib/ui/widgets/task_info_dialog.dart` to `ConsumerStatefulWidget` with tight `SizedBox(width: 420)`, `_TaskInfoHistoryCard`, value-tracked `_editingEntry`, and redacted `AppLogger` telemetry (TDD Green Phase).
- [x] Integrate `TaskEditorHistorySection` and pending-history validation/persistence into `lib/ui/edit_task_screen.dart` (TDD Green & Refactor Phase).
- [x] Update Parts 1 and 2 if implementation details evolve during TDD.
- [x] Follow **`update-documentation`** and **`changelog-updater`** to update `ARCHITECTURE.md` (`tiertask_dev.py arch --sync-tree`) and `CHANGELOG.md` under `## [Unreleased]`.
- [x] Run `python3 .agents/scripts/tiertask_dev.py verify --full --fix` (`0` analyzer infos/warnings, `100%` tests passing).
- [x] Set `status: review`, update `BOARD.md`, and request user approval.
- [x] After user approval, set `status: completed`, update `BOARD.md`, and list delivered artifacts in Part 3.3.

### 3.2 Work Log & Decisions
* **2026-11-14:** Drafted initial `TEP-012` feature concept specifying interactive `TaskHistoryEntry` journaling in `TaskInfoDialog`, `history_task_indicator` on `TierTaskPill`, and batch timestamp/text editing via `TaskEditorHistorySection` in `EditTaskScreen` on top of `TEP-006` (`TDF 0.7.0`).
* **2026-11-15:** Elaborated `TEP-012` to `planned`: aligned all domain and provider signatures with `TEP-006` (`TaskHistoryEntry.normalizeList`, `maxTdfHistoryPerTask`, `maxTdfTextLength`, `TdfCalendar.countUnicodeScalars`, `TdfCalendar.isWithinTimestampBounds`, and existing `TaskNotifier.*TaskHistoryEntry` methods), added `TaskBoardUndo` live-history preservation on completion/downgrade undo, specified tight `SizedBox` layout bounds for `ListView.builder` inside `AlertDialog`, switched `TaskInfoDialog` inline edit tracking to immutable `TaskHistoryEntry` values for external sync safety, added `historyErrorTextInvalid` with full ARB `@key` metadata, and detailed `M-*` TDD test suites.
* **2026-11-15:** Implemented `TEP-012` via Red-Green-Refactor TDD across `TaskBoardUndo`, `resolveTaskIndicatorSpecs`, `TaskEditorHistorySection` / `TaskHistoryInputValidator`, `TaskInfoDialog`, `EditTaskScreen`, `en`/`de` ARB bundles, `ARCHITECTURE.md`, and `CHANGELOG.md`; aligned `resolveTaskIndicatorSpecs` signature in Section 2.3.2, verified full test and analyzer suites (`verify --full --fix`), and advanced `TEP-012` to `review`.
* **2026-11-16:** Approved by user and marked `completed`.

### 3.3 Delivered Artifacts
* **Domain Models (`lib/models/`):** [`lib/models/task_board_undo.dart`](../../lib/models/task_board_undo.dart).
* **Localization & UI (`lib/l10n/`, `lib/ui/`):** [`lib/l10n/app_en.arb`](../../lib/l10n/app_en.arb), [`lib/l10n/app_de.arb`](../../lib/l10n/app_de.arb), [`lib/ui/edit_task_screen.dart`](../../lib/ui/edit_task_screen.dart), [`lib/ui/widgets/task_editor_history_section.dart`](../../lib/ui/widgets/task_editor_history_section.dart), [`lib/ui/widgets/task_info_dialog.dart`](../../lib/ui/widgets/task_info_dialog.dart), [`lib/ui/widgets/tier_task_subtasks_section.dart`](../../lib/ui/widgets/tier_task_subtasks_section.dart).
* **Tests & Tooling (`test/`, `.agents/scripts/`):** [`test/models/task_board_undo_test.dart`](../../test/models/task_board_undo_test.dart), [`test/providers/task_providers_test.dart`](../../test/providers/task_providers_test.dart), [`test/ui/edit_task_screen_test.dart`](../../test/ui/edit_task_screen_test.dart), [`test/ui/widgets/task_editor_history_section_test.dart`](../../test/ui/widgets/task_editor_history_section_test.dart), [`test/ui/widgets/task_info_dialog_test.dart`](../../test/ui/widgets/task_info_dialog_test.dart), [`test/ui/widgets/tier_task_pill_test.dart`](../../test/ui/widgets/tier_task_pill_test.dart), [`test/ui/widgets/tier_task_subtasks_test.dart`](../../test/ui/widgets/tier_task_subtasks_test.dart), [`.agents/scripts/tiertask_dev.py`](../scripts/tiertask_dev.py).
* **Documentation:** [`ARCHITECTURE.md`](../../ARCHITECTURE.md), [`CHANGELOG.md`](../../CHANGELOG.md).
