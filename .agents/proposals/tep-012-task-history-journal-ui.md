---
id: TEP-012
title: Interactive Task History Journal in Task Info Dialog and Task Editor
status: concept
type: feature
created: 2026-11-14
updated: 2026-11-14
---

# TEP-012: Interactive Task History Journal in Task Info Dialog and Task Editor

## Part 1: Concept & Proposal

### 1.1 Summary
This proposal delivers the interactive **Task History Journal** UI inside `TaskInfoDialog` and `EditTaskScreen` on top of **TierTask Data Format (`TDF`) `0.7.0`** (`spec/TDF_SPEC_0.7.0.md` and `TEP-006` in `tep-006-tdf-spec-0-7-0.md`). While `TEP-006` implements the `history <timestamp> "<text>"` specification (`0..500` entries per `task` at canonical position `14`, `MAX_STMTS_PER_BLOCK = 1024`), parser/serializer, `TaskHistoryEntry` domain model, permanent retention across `repeat` rollovers, `Completed`, and `restoreTask`, occurrence-independent three-way set merge, no-op revision protection, undo snapshots, and lossless editor preservation, this proposal renders chronological `TaskItem.history` entries in local wall-clock time inside `TaskInfoDialog` (`lib/ui/widgets/task_info_dialog.dart`) with quick inline append (defaulting timestamp to `DateTime.now().toUtc()` via `clockProvider`), edit (`updateTaskHistoryEntry`), and delete (`removeTaskHistoryEntry`) controls wired to `TaskNotifier`, adds the `history_task_indicator` icon to `TierTaskPill`, and introduces `TaskEditorHistorySection` (`lib/ui/widgets/task_editor_history_section.dart`) inside `EditTaskScreen` (`lib/ui/edit_task_screen.dart`) for batch adding, timestamp/text editing, and deleting of history entries prior to form submission.

### 1.2 Motivation
`TEP-006` (`spec/TDF_SPEC_0.7.0.md` Sections 4.1.2, 6.4–6.7, and 7) separates standing task instructions (`note "<note>"`) from chronological progress and status updates (`history <YYYY-MM-DD HH:MM:SS> "<text>"`), ensuring that recurring meter readings, follow-up call outcomes, and waiting logs survive `repeat` completions and merge without conflict across offline devices. Without dedicated UI surfaces, however, three usability gaps remain:
1. **No Fast In-Place Journaling During Execution:** When checking on a `Blocked` task or completing a step in `Focus`, opening a full-screen editor (`EditTaskScreen`) and manually typing a timestamp just to record `"Left voicemail with support"` adds unnecessary friction. Users need a single-line quick-append input right inside `TaskInfoDialog` that stamps `DateTime.now().toUtc()` automatically.
2. **No Batch or Backdated History Editing in `EditTaskScreen`:** When creating a task from historical notes, correcting a typo in a logged entry, or adjusting an entry's local date/time (`YYYY-MM-DD [HH:MM[:SS]]`) alongside other task edits before saving once, users need a structured `TaskEditorHistorySection` card inside `EditTaskScreen`.
3. **No Visual Indicator on `TierTaskPill`:** Tasks carrying recorded history entries currently show no passive indicator icon on `TierTaskPill`, requiring users to open every task to discover whether progress logs exist.

### 1.3 Goals & Non-Goals
* **Goals:**
  1. Render chronological `TaskItem.history` (`TaskHistoryEntry`) entries formatted in workspace local wall-clock time (`configuration.toLocalWallClock(entry.timestampUtc)`) inside `TaskInfoDialog` (`lib/ui/widgets/task_info_dialog.dart`), supporting:
     - Quick inline append (`ValueKey('task_info_history_input')` and `ValueKey('task_info_history_add_button')`) defaulting `timestampUtc` to `TaskItem.normalizeTimestamp(ref.read(clockProvider)().toUtc())` (`DateTime.now().toUtc()` in production) and validating single-line `<text>` (`1..500` decoded Unicode scalar values, `MAX_HISTORY_PER_TASK = 500`).
     - Inline text editing (`ValueKey('task_info_history_edit_$index')`, `updateTaskHistoryEntry`) and single-tap entry removal (`ValueKey('task_info_history_delete_$index')`, `removeTaskHistoryEntry`) wired to `TaskNotifier` (`lib/providers/task_providers.dart`), respecting `MAX_HISTORY_PER_TASK = 500` and no-op revision protection.
  2. Add `history_task_indicator` (`Icons.history_rounded`) to `resolveTaskIndicatorSpecs` (`lib/ui/widgets/tier_task_subtasks_section.dart`) when `task.history.isNotEmpty` so tapping the indicator opens `TaskInfoDialog` with the History Journal card highlighted (`initialIndicatorKeyPrefix == 'history_task_indicator'`).
  3. Introduce `TaskEditorHistorySection` (`lib/ui/widgets/task_editor_history_section.dart`, `ValueKey('task_editor_history_card')`) inside `EditTaskScreen` (`lib/ui/edit_task_screen.dart`) for batch adding, local wall-clock timestamp (`YYYY-MM-DD [HH:MM[:SS]]` with date/time pickers) and `<text>` editing, and deleting of `TaskHistoryEntry` items before form submission.
  4. Enforce strict passive-text treatment (`history` `<text>` is rendered exclusively as non-executable text and never launched via `LinkLauncherRepository` or dereferenced as a path) and `AppLogger` redaction (`<task-id>` and `history_count` only, `P-SECRET-HYGIENE`), with complete English (`en`) and German (`de`) localization (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`).
* **Non-Goals:**
  1. Modifying the `TDF 0.7.0` `history` grammar, canonical sort/deduplication rules, occurrence-independent set merge, or `MAX_HISTORY_PER_TASK = 500` / `MAX_STMTS_PER_BLOCK = 1024` bounds delivered in `TEP-006` (`spec/TDF_SPEC_0.7.0.md`).
  2. Supporting multi-line paragraphs, rich Markdown formatting, or clickable hyperlink auto-detection inside `history` `<text>` (`spec/TDF_SPEC_0.7.0.md` Section 2.8 restricts `<text>` to single-line `1..500` Unicode scalar values; clickable URIs belong in `link "<title>" "<uri>"`).
  3. Automatic system-generated history entries on every tier move or subtask toggle (all `history` entries are explicit user-authored domain journal records).

### 1.4 Description

#### 1.4.1 Task Pill Indicator (`history_task_indicator`)
In `resolveTaskIndicatorSpecs` (`lib/ui/widgets/tier_task_subtasks_section.dart`):
* Whenever `task.history.isNotEmpty`, include `(icon: Icons.history_rounded, keyPrefix: 'history_task_indicator', tooltip: localizations.tooltipIndicatorHistory)` immediately after `links_task_indicator` and before `subtasks_task_indicator` (mirroring canonical `.tdf` directive order `13: link`, `14: history`, `16: subtasks`).
* Tapping `history_task_indicator_<id>` (or `summary_task_indicator_<id>` when `> 3` indicators are active) opens `showTaskInfoDialog(context, task: task, initialIndicatorKeyPrefix: 'history_task_indicator')`.

#### 1.4.2 Interactive History Journal in `TaskInfoDialog`
`TaskInfoDialog` (`lib/ui/widgets/task_info_dialog.dart`) is upgraded from `ConsumerWidget` to `ConsumerStatefulWidget` so inline `TextEditingController` instances are deterministically owned and disposed (`P-DISPOSE-RESOURCES`) while watching the live task snapshot (`board.findTask(widget.task.id) ?? widget.task`):
* **Always-Available Journal Card (`ValueKey('task_info_section_history_task_indicator')`):**
  - Rendered at the bottom of the `TaskInfoDialog` card stack even when `liveTask.history.isEmpty`, allowing users to append the very first history entry directly from `TaskInfoDialog` without navigating to `EditTaskScreen`.
  - Highlighted when `widget.initialIndicatorKeyPrefix == 'history_task_indicator'`.
* **Chronological Local-Time Display:**
  - Entries in `liveTask.history` (already normalized in ascending UTC chronological + unsigned UTF-8 byte order) are rendered in chronological order (`0 .. history.length - 1`), with a bounded scrollable region (`ConstrainedBox(maxHeight: 220)` + `ListView.builder` when `history.length > 5` per `P-LAZY-LISTS`).
  - Each row (`ValueKey('task_info_history_row_$index')`) displays `TaskItem.formatTdfTimestamp(configuration.toLocalWallClock(entry.timestampUtc))` in a compact monospace/tabular caption above `SelectableText(entry.text)` (strictly passive plain text), paired with compact edit (`ValueKey('task_info_history_edit_$index')`) and delete (`ValueKey('task_info_history_delete_$index')`) icon buttons.
* **Quick Inline Append (`DateTime.now().toUtc()` Default):**
  - Below the entry list, a single-line `ClearableTextField` (`fieldKey: const ValueKey('task_info_history_input')`, `clearButtonKey: const ValueKey('task_info_history_clear_button')`) and add `IconButton` (`ValueKey('task_info_history_add_button')`, disabled while persistence is in flight or `liveTask.history.length >= TaskHistoryEntry.maxHistoryPerTask`) accept a new journal entry.
  - Submitting via Enter or `+` sanitizes single-line `<text>` (collapsing pasted `\r\n`, `\r`, or `\t` into single ASCII spaces `0x20` and trimming outer ASCII spaces), validates `1..500` decoded Unicode scalar values (`TaskItem.maxTitleLength`) and `liveTask.history.length < 500`, stamps `timestampUtc = TaskItem.normalizeTimestamp(ref.read(clockProvider)().toUtc())` (`DateTime.now().toUtc()`), and calls `TaskNotifier.addTaskHistoryEntry(liveTask.id, entry: TaskHistoryEntry(timestampUtc: timestampUtc, text: sanitizedText))`.
  - If an identical `(timestampUtc, text)` pair already exists on `liveTask`, `TaskBoard` / `TaskNotifier` treats the mutation as a pure no-op without advancing `task.modified` or writing to storage, and clears the input field cleanly.
* **Inline Row Edit & Delete:**
  - Tapping `task_info_history_edit_$index` switches row `index` into an inline edit bar (`ValueKey('task_info_history_edit_input_$index')`, save `ValueKey('task_info_history_edit_save_$index')`, cancel `ValueKey('task_info_history_edit_cancel_$index')`) preserving `entry.timestampUtc` while editing `<text>` (full timestamp + text editing is available in `EditTaskScreen`). Saving calls `TaskNotifier.updateTaskHistoryEntry(liveTask.id, previousEntry: entry, updatedEntry: TaskHistoryEntry(timestampUtc: entry.timestampUtc, text: updatedText))`.
  - Tapping `task_info_history_delete_$index` calls `TaskNotifier.removeTaskHistoryEntry(liveTask.id, entry: entry)`.

#### 1.4.3 Batch & Timestamp-Editable `TaskEditorHistorySection` in `EditTaskScreen`
`TaskEditorHistorySection` (`lib/ui/widgets/task_editor_history_section.dart`, `cardKey: const ValueKey('task_editor_history_card')`) is embedded inside `_EditTaskFormColumn` in `EditTaskScreen` (`lib/ui/edit_task_screen.dart`) immediately after `_EditTaskSubtasksAndLinksSection`:
* **Draft State & Canonical Normalization:** `_EditTaskScreenState` maintains `late List<TaskHistoryEntry> _historyEntries` initialized from `widget.initialTask?.history ?? const <TaskHistoryEntry>[]`. Whenever an entry is added, updated, or deleted in the form, `_historyEntries` is canonically sorted and deduplicated via `TaskHistoryEntry.normalizeEntries(_historyEntries)` so the editor preview matches `.tdf` order immediately.
* **Adding & Editing Timestamp + Text:**
  - Provides:
    1. An optional local wall-clock timestamp field (`ValueKey('editor_history_timestamp_input')`, clear button `ValueKey('editor_history_timestamp_clear_button')`, date picker `ValueKey('editor_history_date_picker_button')`, time picker `ValueKey('editor_history_time_picker_button')`) accepting `YYYY-MM-DD`, `YYYY-MM-DD HH:MM`, or `YYYY-MM-DD HH:MM:SS` in workspace local time (`configuration.localWallClockToUtc(...)`). When left blank during add, the timestamp defaults to `TaskItem.normalizeTimestamp(ref.read(clockProvider)().toUtc())`.
    2. A single-line `<text>` input (`ValueKey('editor_history_text_input')`, clear button `ValueKey('editor_history_text_clear_button')`) with submit/update button (`ValueKey('editor_add_history_button')`) and optional cancel-edit button (`ValueKey('editor_cancel_edit_history_button')`).
  - Existing draft entries render in a bounded list (`ConstrainedBox(maxHeight: 240)` + `ListView.builder` when `entries.length > 5`) with per-row edit (`ValueKey('editor_edit_history_$index')`, loading both local timestamp text and `entry.text` into the inputs) and remove (`ValueKey('editor_remove_history_$index')`) buttons.
* **Pending Input Guard on Form `Save`:**
  - Matching `_buildDraft`'s pending-link validation in `EditTaskScreen`, clicking `Save` when `editor_history_text_input` or `editor_history_timestamp_input` is non-empty validates and commits the pending history entry into `_historyEntries` first (aborting form submission and displaying inline `editor_history_error_text` if `<text>` is empty/invalid, the timestamp is malformed, or `_historyEntries.length >= 500` when adding a distinct entry).
  - `_persistTask` passes `history: _historyEntries` to `TaskNotifier.addTask` or `TaskNotifier.updateTask`.

### 1.5 Alternatives
1. **Allow Editing History Only in `EditTaskScreen` (Read-Only `TaskInfoDialog`):** Rejected because `TEP-006` Section 1.4.5 explicitly targets quick progress logging on `Blocked` and active tasks from `TaskInfoDialog` without opening the full task editor. Supporting quick single-line append/edit/delete in `TaskInfoDialog` alongside full timestamp + batch editing in `EditTaskScreen` serves both fast daily capture and structured maintenance.
2. **Auto-Linkify `https://` Substrings Inside `history` `<text>`:** Rejected because `spec/TDF_SPEC_0.7.0.md` Section 4.1.2 and `TEP-006` Topic 5 mandate that `history` `<text>` remain strictly passive plain text and never be dereferenced as URIs or filesystem paths; actionable reference links already have dedicated, scheme-validated `link "<title>" "<uri>"` directives.
3. **Store Local Wall-Clock Offsets Per History Entry:** Rejected because `spec/TDF_SPEC_0.7.0.md` Section 4.1.2 and Section 7.1 store all `history` timestamps in normalized UTC (`YYYY-MM-DD HH:MM:SS`), converting to/from workspace local time via `WebDavConfig.toLocalWallClock` and `WebDavConfig.localWallClockToUtc` at the UI boundary.

## Part 2: Technical Design & Code Changes

### 2.1 Architecture & Affected Modules

| Layer | File | Change Type | Responsibility |
| :--- | :--- | :--- | :--- |
| Localization (`Rank 2`) | `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb` | Modify | Add English and German localization keys for the History Journal section, pill indicator tooltip, input hints, edit/delete tooltips, and validation error messages. |
| Providers (`Rank 5`) | `lib/providers/task_providers.dart` | Modify | Ensure `TaskNotifier` exposes `addTaskHistoryEntry`, `updateTaskHistoryEntry`, and `removeTaskHistoryEntry` (plus `List<TaskHistoryEntry>? history` on `addTask` and `updateTask`), skipping persistence on pure no-op updates and logging only `<task-id>` and `history_count`. |
| UI (`Rank 6`) | `lib/ui/widgets/tier_task_subtasks_section.dart` | Modify | Append `history_task_indicator` (`Icons.history_rounded`) to `resolveTaskIndicatorSpecs` when `task.history.isNotEmpty`. |
| UI (`Rank 6`) | `lib/ui/widgets/task_info_dialog.dart` | Modify | Convert `TaskInfoDialog` to `ConsumerStatefulWidget`, watch live `TaskItem` from `taskNotifierProvider`, and render `_TaskInfoHistoryCard` with local-time entries, `ListView.builder` virtualization (`> 5` items), inline append (`clockProvider`), inline `<text>` edit, and delete actions. |
| UI (`Rank 6`) | `lib/ui/widgets/task_editor_history_section.dart` | New | Implement `TaskEditorHistorySection` and `TaskHistoryInputValidator` (`sanitizeSingleLineText`, `validateText`, `resolveEntryTimestampUtc`) for batch history authoring, local timestamp picking/editing, and deletion. |
| UI (`Rank 6`) | `lib/ui/edit_task_screen.dart` | Modify | Manage `_historyEntries`, `_historyTimestampController`, `_historyTextController`, `_editingHistoryIndex`, and `_historyErrorMessage`; embed `TaskEditorHistorySection`; validate pending input in `_buildDraft`; forward `history` to `TaskNotifier`. |
| Tests | `test/providers/task_providers_test.dart`, `test/ui/widgets/task_info_dialog_test.dart`, `test/ui/widgets/task_editor_history_section_test.dart`, `test/ui/edit_task_screen_test.dart`, `test/ui/widgets/tier_task_pill_test.dart` | Modify / New | Red-Green-Refactor unit and widget tests covering `TaskNotifier` history mutations, no-op protection, `TaskInfoDialog` live append/edit/delete, `TaskEditorHistorySection` batch CRUD and local-to-UTC conversion, `500`-entry / `500`-char bounds, passive-text security, and `AppLogger` redaction. |

### 2.2 TDF Schema, Localization & State Changes

#### 2.2.1 TDF `0.7.0` Schema Reliance (`TEP-006`)
No changes to `spec/TDF_SPEC_0.7.0.md` are required beyond `TEP-006` Topic 5:
* `TaskHistoryEntry` (`lib/models/task_item.dart`) defines `static const int maxHistoryPerTask = 500;`, `static const int maxHistoryTextLength = 500;`, `final DateTime timestampUtc;`, `final String text;`, and `static List<TaskHistoryEntry> normalizeEntries(Iterable<TaskHistoryEntry> entries)`.
* Canonical serialization emits `history YYYY-MM-DD HH:MM:SS "<text>"` at `task` directive position `14` (`MAX_STMTS_PER_BLOCK = 1024`).

#### 2.2.2 Localization Keys (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`)

| Key | English (`app_en.arb`) | German (`app_de.arb`) |
| :--- | :--- | :--- |
| `historySectionTitle` | `"History"` | `"Verlauf"` |
| `tooltipIndicatorHistory` | `"Has history entries"` | `"Enthält Verlaufseinträge"` |
| `historyEmptyHint` | `"No history entries recorded yet."` | `"Noch keine Verlaufseinträge vorhanden."` |
| `historyEntryTextLabel` | `"History entry"` | `"Verlaufseintrag"` |
| `historyEntryTextHint` | `"Add progress update or note"` | `"Fortschritt oder Notiz erfassen"` |
| `historyTimestampLabel` | `"Timestamp (optional, defaults to now)"` | `"Zeitstempel (optional, Standard: jetzt)"` |
| `historyTimestampHint` | `"YYYY-MM-DD HH:MM"` | `"JJJJ-MM-TT Std:Min"` |
| `tooltipAddHistoryEntry` | `"Add history entry"` | `"Verlaufseintrag hinzufügen"` |
| `tooltipEditHistoryEntry` | `"Edit history entry"` | `"Verlaufseintrag bearbeiten"` |
| `tooltipSaveHistoryEntry` | `"Update history entry"` | `"Verlaufseintrag aktualisieren"` |
| `tooltipCancelEditHistoryEntry` | `"Cancel history edit"` | `"Bearbeitung abbrechen"` |
| `tooltipDeleteHistoryEntry` | `"Delete history entry"` | `"Verlaufseintrag löschen"` |
| `historyErrorTextEmpty` | `"Enter a history text."` | `"Bitte einen Verlaufstext eingeben."` |
| `historyErrorTextTooLong` | `"History entry must not exceed 500 characters."` | `"Verlaufseintrag darf maximal 500 Zeichen lang sein."` |
| `historyErrorTimestampInvalid` | `"Enter a valid date (YYYY-MM-DD) and optional time (HH:MM)."` | `"Gültiges Datum (JJJJ-MM-TT) und optionale Uhrzeit (Std:Min) eingeben."` |
| `historyErrorMaxExceeded` | `"Maximum of 500 history entries per task reached."` | `"Maximal 500 Verlaufseinträge pro Aufgabe erreicht."` |

### 2.3 Implementation Details

#### 2.3.1 `TaskNotifier` History Actions (`lib/providers/task_providers.dart`)
Expose three focused mutation methods on `TaskNotifier` alongside `List<TaskHistoryEntry>? history` on `addTask` and `updateTask`:
```dart
Future<void> addTaskHistoryEntry(
  String taskId, {
  required TaskHistoryEntry entry,
  DateTime? currentDate,
});

Future<void> updateTaskHistoryEntry(
  String taskId, {
  required TaskHistoryEntry previousEntry,
  required TaskHistoryEntry updatedEntry,
  DateTime? currentDate,
});

Future<void> removeTaskHistoryEntry(
  String taskId, {
  required TaskHistoryEntry entry,
  DateTime? currentDate,
});
```
* **No-Op Revision & I/O Short-Circuit:** Before calling `_commitMutation`, compare `updatedBoard = _currentBoard.addTaskHistoryEntry(...)` (or `updateTaskHistoryEntry` / `removeTaskHistoryEntry`) with `_currentBoard`: if `identical(updatedBoard, _currentBoard)` or `updatedBoard.findTask(taskId) == _currentBoard.findTask(taskId)` (for example, adding a duplicate `(timestampUtc, text)` pair or saving an unchanged inline edit), return immediately without advancing `_mutationEpoch`, mutating `task.modified`, or writing to disk/WebDAV.
* **Diagnostic Redaction (`AppLogger`, `P-SECRET-HYGIENE`):** Emit `AppLogger.event(LogLevel.info, LogTag.domain, 'task.history.mutated', fields: <String, Object?>{'id': taskId, 'action': actionName, 'history_count': updatedTask.history.length})`, never logging `entry.text`.

#### 2.3.2 Single-Line Validation & `TaskEditorHistorySection` (`lib/ui/widgets/task_editor_history_section.dart`)
* Implement pure stateless helper `TaskHistoryInputValidator` (`const TaskHistoryInputValidator._()`):
  - `static String sanitizeSingleLineText(String rawText)`: Single $O(N)$ pass replacing `\r\n`, `\r`, and `\t` (`0x09`, `0x0A`, `0x0D`) with `' '` (`0x20`) and trimming leading/trailing ASCII spaces (`0x20`) while preserving non-ASCII graphic whitespace such as `U+00A0` (`spec/TDF_SPEC_0.7.0.md` Section 2.8).
  - `static String? validateText(String sanitizedText, AppLocalizations localizations)`:
    - Returns `localizations.historyErrorTextEmpty` when `sanitizedText.isEmpty`.
    - Iterates `sanitizedText.runes` once (`P-BOUND-ALLOC`): rejects `count > TaskHistoryEntry.maxHistoryTextLength` (`500`) with `localizations.historyErrorTextTooLong`, and rejects forbidden C0/DEL control characters or lone UTF-16 surrogates.
  - `static DateTime? resolveEntryTimestampUtc({required String rawTimestamp, required WebDavConfig configuration, required DateTime fallbackNowUtc})`:
    - When `rawTimestamp.trim().isEmpty`, returns `TaskItem.normalizeTimestamp(fallbackNowUtc)`.
    - Otherwise parses `TaskItem.tryParseTdfTimestampInput(rawTimestamp.trim())` as a local wall-clock timestamp and converts it via `TaskItem.normalizeTimestamp(configuration.localWallClockToUtc(parsedLocal))` (returning `null` on malformed input so `localizations.historyErrorTimestampInvalid` is shown).
* Implement `TaskEditorHistorySection` (`StatelessWidget`) with decomposed private widgets (`_TaskEditorHistoryList`, `_TaskEditorHistoryRow`, `_TaskEditorHistoryInputColumn`) so every `build()` method remains `< 40` lines (`P-FLATTEN-BUILD`) and lists with `> 5` entries use `ListView.builder` with `ValueKey('editor_history_item_${entry.timestampUtc.millisecondsSinceEpoch}_$index')` (`P-LAZY-LISTS`).

#### 2.3.3 `TaskInfoDialog` Stateful Conversion & Live Synchronization (`lib/ui/widgets/task_info_dialog.dart`)
* Convert `TaskInfoDialog` to `ConsumerStatefulWidget` (`_TaskInfoDialogState`):
  - Owns `_appendController = TextEditingController()`, `_editController = TextEditingController()`, `int? _editingIndex`, `String? _historyErrorMessage`, and `bool _isMutatingHistory = false`.
  - Disposes both `TextEditingController` instances in `dispose()` (`P-DISPOSE-RESOURCES`).
  - Resolves `final liveTask = board.findTask(widget.task.id) ?? widget.task;` in `build()`. If an external sync updates `liveTask.history` while `_editingIndex case final activeIndex?` and `activeIndex >= liveTask.history.length` (`P-NULL-SAFE`), resets `_editingIndex = null`.
  - Awaits `ref.read(taskNotifierProvider.notifier).addTaskHistoryEntry(...)` / `updateTaskHistoryEntry(...)` / `removeTaskHistoryEntry(...)` with `if (!mounted) return;` guards across `await` boundaries (`use_build_context_synchronously`).
* Extend `FakeTaskNotifier` in `test/ui/test_helpers.dart` (during TDD implementation) to implement `addTaskHistoryEntry`, `updateTaskHistoryEntry`, and `removeTaskHistoryEntry` in memory so leaf widget tests run with zero filesystem/network I/O (`P-TEST-MIRROR`).

### 2.4 Testing Strategy
All changes follow strict Red-Green-Refactor TDD (`P-TDD-FIRST`):
* **`M-EXHAUSTIVE-STATE-TESTS`:**
  - Verify `resolveTaskIndicatorSpecs` omits `history_task_indicator` when `task.history.isEmpty` and includes `history_task_indicator` when `task.history.isNotEmpty`, collapsing into `summary_task_indicator` when total indicators exceed `maxVisibleTaskIndicators` (`3`).
  - Verify `TaskInfoDialog` renders `historyEmptyHint` when `history.isEmpty`, appends a new entry using `clockProvider`'s UTC instant converted to `configuration` local wall-clock time for display, edits an entry's text in place, cancels an in-progress edit, and deletes an entry in both English (`en`) and German (`de`) locales.
  - Verify `TaskEditorHistorySection` inside `EditTaskScreen` supports creating a new task with multiple history entries (defaulting blank timestamp to `clockProvider` and converting explicit local timestamps via `WebDavConfig` fixed/system timezone), editing both timestamp and text of existing entries, deleting entries, and committing pending input when `Save` is tapped.
* **`M-EXTREME-BOUND-TESTS`:**
  - Test `<text>` length boundaries in both `TaskInfoDialog` and `TaskEditorHistorySection`: `0` chars / spaces-only `"   "` (rejected with `historyErrorTextEmpty`), `1` char (accepted), `500` decoded Unicode scalar values including 4-byte UTF-8 / surrogate-pair code points such as `U+1F4DD` (`1000` UTF-16 code units, accepted because `runes.length == 500`), and `501` Unicode scalar values (rejected with `historyErrorTextTooLong`).
  - Test entry count boundaries: `499 -> 500` entries accepted; attempting to add a `501`st distinct entry rejected with `historyErrorMaxExceeded` (and `task_info_history_add_button` disabled at `500` while still permitting editing an existing entry in place without exceeding `500` or deleting entries).
* **`M-DELIM-INJECT-TESTS` & `M-URI-PATH-EDGE-TESTS`:**
  - Author history entries containing `"`, `\`, `'`, `# inline comment`, `{ }`, and multi-line clipboard pastes (`"Line 1\r\nLine 2\tTabbed"` -> sanitized to single-line `"Line 1 Line 2 Tabbed"`), save to `.tdf`, re-parse, and verify lossless round-trip without `UnexpectedToken` or `InvalidEscapeSequence`.
  - Render history entries containing `https://example.com`, `javascript:alert(1)`, and `file:///etc/passwd` in `TaskInfoDialog` and `EditTaskScreen`, tap the rendered history text, and assert `FakeLinkLauncherRepository.launchedUris` remains empty (proving strictly passive rendering).
* **`M-IO-TESTS`:**
  - Verify adding an exact duplicate `(timestampUtc, text)` pair or saving an unchanged edit in `TaskInfoDialog` performs zero `.tdf` file writes / WebDAV `PUT` requests and leaves `task.modified` unchanged.
  - Capture `AppLogger` sink events during `addTaskHistoryEntry`, `updateTaskHistoryEntry`, and `removeTaskHistoryEntry` and assert secret/text hygiene (no substring of `entry.text` appears in any log message or structured field).
* **`M-REAL-MECHANICS-TESTS`:**
  - Suspend persistence with a `Completer<void>` inside `TaskNotifier` while adding a history entry from `TaskInfoDialog`, pump mid-flight frames to verify duplicate submit taps are guarded and controllers stay coherent if the dialog is closed mid-flight, then complete persistence and verify board consistency.
  - While `TaskInfoDialog` is open on task `T`, simulate an external `.tdf` file watch synchronization that merges a remote `history` entry and completes a `repeat` occurrence on `T`, verifying `TaskInfoDialog` updates live to display both local and remote history entries in chronological order without losing state.

## Part 3: Implementation Record & Tasks

### 3.1 Task Breakdown
- [ ] Run `flutter analyze --fatal-infos --fatal-warnings` and `flutter test` to confirm a clean baseline on top of `TEP-006`.
- [ ] Add English (`lib/l10n/app_en.arb`) and German (`lib/l10n/app_de.arb`) localization keys and run `flutter gen-l10n`.
- [ ] Write failing unit and widget tests first in `test/providers/task_providers_test.dart`, `test/ui/widgets/tier_task_pill_test.dart`, `test/ui/widgets/task_info_dialog_test.dart`, `test/ui/widgets/task_editor_history_section_test.dart`, and `test/ui/edit_task_screen_test.dart` (TDD Red Phase — `P-TDD-FIRST`).
- [ ] Wire `addTaskHistoryEntry`, `updateTaskHistoryEntry`, and `removeTaskHistoryEntry` (with no-op short-circuiting and redacted `AppLogger` telemetry) in `lib/providers/task_providers.dart` and `FakeTaskNotifier` in `test/ui/test_helpers.dart` (TDD Green Phase).
- [ ] Add `history_task_indicator` in `lib/ui/widgets/tier_task_subtasks_section.dart` and implement interactive `_TaskInfoHistoryCard` inside `lib/ui/widgets/task_info_dialog.dart` (TDD Green Phase).
- [ ] Implement `lib/ui/widgets/task_editor_history_section.dart` and integrate it into `lib/ui/edit_task_screen.dart` (TDD Green & Refactor Phase).
- [ ] Update Parts 1 and 2 if implementation details evolve during TDD.
- [ ] Run `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze --fatal-infos --fatal-warnings`, and `flutter test`.
- [ ] Follow **`update-documentation`** to synchronize `README.md`, `ARCHITECTURE.md`, and `AGENTS.md` as applicable.
- [ ] Follow **`changelog-updater`** to add a `CHANGELOG.md` entry under `## [Unreleased]`.
- [ ] Set `status: review`, update `BOARD.md`, and request user approval.
- [ ] After user approval, set `status: completed`, update `BOARD.md`, and list delivered artifacts in Part 3.3.

### 3.2 Work Log & Decisions
* **2026-11-14:** Drafted initial `TEP-012` feature concept and technical design specifying interactive `TaskHistoryEntry` journaling in `TaskInfoDialog`, `history_task_indicator` on `TierTaskPill`, and batch timestamp/text editing via `TaskEditorHistorySection` in `EditTaskScreen` on top of `TEP-006` (`TDF 0.7.0`).

### 3.3 Delivered Artifacts
*(Complete upon approval)*
