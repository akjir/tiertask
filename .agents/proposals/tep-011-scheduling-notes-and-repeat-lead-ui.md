---
id: TEP-011
title: Deferral and Deadline Notes and Recurring Preparation Lead Editor UI
status: review
type: feature
created: 2026-11-14
updated: 2026-11-15
---

# TEP-011: Deferral and Deadline Notes and Recurring Preparation Lead Editor UI

## Part 1: Concept & Proposal

### 1.1 Summary
This proposal specifies the task-editor authoring controls and task-info inspection views for contextual scheduling notes (`suspendedNote` and `dueNote`) and recurring deadline preparation windows (`repeat ... lead <lead-count> days`) on top of **TierTask Data Format (`TDF`) `0.7.0`** (`spec/TDF_SPEC_0.7.0.md`, `TEP-006`, and `TEP-010`). While `TEP-006` delivers the `TDF 0.7.0` grammar (`suspended (<timestamp> | forever) ["<note>"]`, `due <timestamp> [passive] ["<note>"]`, `repeat <count> <days|weeks|months> [<repeat-time>] [lead <lead-count> days]`), scanner/parser/serializer support, `TaskItem` and `TaskRepeatRule` domain fields, automatic expired-deferral cleanup, Mode 2 deadline-anchored recurrence calculation (`targetDueLocalDate - leadDays`), three-way reconciliation, undo recovery, and lossless preservation of existing fields during task edits, this proposal adds `TaskEditorSchedulingNoteField` (`1..3` visible lines, `<= 2000` decoded Unicode scalar values via `maxTdfNoteLength`) and conditional `Preparation lead (days)` (`0..3650` via `TaskRepeatRule.maxRepeatCount`, visible when `isRepeating && hasDue`) to `TaskEditorSchedulingCard` and `TaskEditorRepeatField` (`lib/ui/widgets/task_editor_scheduling_card.dart`), wires full controller lifecycle, multi-field validation, untouched-note lossless preservation, atomic `TdfException` error handling, and redacted `AppLogger` telemetry in `EditTaskScreen` (`lib/ui/edit_task_screen.dart`), and renders live multi-line `SelectableText` scheduling notes and Mode 2 preparation lead summaries inside `TaskInfoDialog` (`lib/ui/widgets/task_info_dialog.dart`).

### 1.2 Motivation
`TEP-006` (`spec/TDF_SPEC_0.7.0.md` Sections 2.8, 4.1.2, 5.4, 6.4, 6.6, and 6.10.3) defines `.tdf` syntax and lifecycle invariants for ephemeral deferral notes, deadline notes, and recurring preparation lead offsets, and preserves those attributes when tasks authored in external `.tdf` tools are edited in TierTask. Without dedicated UI controls, three functional gaps remain:
1. **No In-App Authoring or Clearing of Deferral and Deadline Notes:** Users deferring a task (`Waiting on vendor quote #412`) or setting a deadline (`Submit signed PDF before 17:00 CET`) cannot enter, edit, or clear `TaskItem.suspendedNote` or `TaskItem.dueNote` in `EditTaskScreen`, forcing transient scheduling context into the standing `task.note` field where expired deferral reasons remain after the deferral clears.
2. **No In-App Authoring of Recurring Preparation Windows (`lead <lead-count> days`):** Mode 2 recurrence (`repeat` combined with `due` under `spec/TDF_SPEC_0.7.0.md` Sections 6.4 and 6.10.3) computes `targetSuspendedLocalDate = targetDueLocalDate - leadDays` on completion so recurring obligations stay in `Blocked` (`Tier 4`) until their preparation window opens `leadDays` calendar days before the next deadline. Without a numeric `Preparation lead (days)` field in `TaskEditorRepeatField`, users cannot configure or update `TaskRepeatRule.leadDays` (`0..3650`) inside `EditTaskScreen`.
3. **Hidden Scheduling Context in `TaskInfoDialog`:** Tapping `suspended_task_indicator_<id>`, `due_task_badge_<id>`, or `repeat_task_indicator_<id>` on `TierTaskPill` opens `TaskInfoDialog`, which currently renders deferral/deadline timestamps, deadline auto-priority details (`TEP-010`), and repeat intervals while omitting `task.suspendedNote`, `task.dueNote`, and active Mode 2 `repeatRule.leadDays`, and reads a static `widget.task` snapshot rather than resolving live updates from `taskNotifierProvider`.

### 1.3 Goals & Non-Goals
* **Goals:**
  1. Extend `TaskEditorSchedulingCard` (`lib/ui/widgets/task_editor_scheduling_card.dart`) and `EditTaskScreen` (`lib/ui/edit_task_screen.dart`) with clearable multi-line `TaskEditorSchedulingNoteField` inputs (`minLines: 1`, `maxLines: 3`, `showClearWhenUnfocused: true`, `keyboardType: TextInputType.multiline`, `textInputAction: TextInputAction.newline`) for:
     - `suspendedNote` (`ValueKey('task_editor_suspended_note_input')`, clear button `ValueKey('task_editor_suspended_note_clear_button')`, visible whenever `isSuspended == true`).
     - `dueNote` (`ValueKey('task_editor_due_note_input')`, clear button `ValueKey('task_editor_due_note_clear_button')`, visible whenever `hasDue == true`).
     Normalize user-edited CRLF/CR line breaks to LF (`\n`), preserve untouched existing notes verbatim, collapse empty or ASCII-whitespace-only (`0x20`, `\t`, `\n`, `\r`) input to `null` (preventing `TdfErrorKind.emptyText`), reject unpaired UTF-16 surrogates and forbidden control characters with `schedulingNoteErrorInvalid`, and enforce `<= 2000` decoded Unicode scalar values (`maxTdfNoteLength`) with `schedulingNoteErrorTooLong`.
  2. Extend `TaskEditorRepeatField` (`lib/ui/widgets/task_editor_scheduling_card.dart`) and `EditTaskScreen` with a conditional `Preparation lead (days)` numeric input (`ValueKey('task_editor_repeat_lead_days_input')`, clear button `ValueKey('task_editor_repeat_lead_days_clear_button')`, `showClearWhenUnfocused: true`), visible strictly when `isRepeating && hasDue`, validating unsigned whole numbers in `0..3650` (`TaskRepeatRule.maxRepeatCount`) independently from the repeat interval count (`1..3650`), normalizing blank or `'0'` input (and saves with `!hasDue`) to `leadDays = 0`, and preserving any existing `TaskRepeatRule.clock` (`TdfRepeatClock`).
  3. Update `TaskInfoDialog` (`lib/ui/widgets/task_info_dialog.dart`) to resolve the live task from `taskNotifierProvider` (`board.findTask(task.id) ?? task`), render multi-line `SelectableText` blocks for active `suspendedNote` (`ValueKey('task_info_suspended_note')`) and `dueNote` (`ValueKey('task_info_due_note')`), and append `taskInfoRepeatLeadDays` to the repeat card details when `repeatRule.leadDays > 0 && currentTask.dueAt != null`.
  4. Provide English (`lib/l10n/app_en.arb`) and German (`lib/l10n/app_de.arb`) localizations with full `@key` metadata parity and gated `AppLogger` telemetry (`AGENTS.md` Section 6) that never records raw note contents (`P-SECRET-HYGIENE`).
* **Non-Goals:**
  1. Changing the `TDF 0.7.0` lexical grammar, parser, serializer, block-reason cleanup, Mode 1/Mode 2 recurrence calculation, or three-way synchronization rules in `spec/TDF_SPEC_0.7.0.md` (`TEP-006`).
  2. Adding scheduling-note or preparation-lead controls to `QuickAddBar` (`lib/ui/widgets/quick_add_bar.dart`).
  3. Adding an interactive `<repeat-time>` (`HH:MM[:SS]`) clock selector to `TaskEditorRepeatField` (existing `TaskRepeatRule.clock` values parsed from `.tdf` files continue to be preserved losslessly on save).
  4. Adding separate indicator icons for `suspendedNote` or `dueNote` to `TierTaskPill` (`maxVisibleTaskIndicators = 3`).

### 1.4 Description

#### 1.4.1 Contextual Deferral & Deadline Note Inputs in `EditTaskScreen`
Inside `TaskEditorSchedulingCard` (`ValueKey('task_editor_scheduling_card')`):
* **Deferral Note (`suspendedNote`):**
  - Rendered inside `_TaskEditorSuspendedSection` directly below `TaskEditorSuspendedField` (`task_editor_suspended_input`) whenever `isSuspended == true`, separated by `const SizedBox(height: 8)`.
  - Uses `TaskEditorSchedulingNoteField` wrapping `ClearableTextField` with `fieldKey: const ValueKey('task_editor_suspended_note_input')`, `clearButtonKey: const ValueKey('task_editor_suspended_note_clear_button')`, `showClearWhenUnfocused: true`, `minLines: 1`, `maxLines: 3`, `keyboardType: TextInputType.multiline`, `textInputAction: TextInputAction.newline`, and `focusedColor: appTheme.warningAccent`.
  - **Initialization & Expired-Deferral Hygiene:** In `_EditTaskScreenState.initState`, active deferral status is computed via `final hasActiveSuspension = task?.hasActiveSuspendedAt(nowUtc) ?? false;` (`lib/models/task_item.dart`), which is `true` strictly when `task.isSuspendedForever` or `task.suspendedAt > TaskItem.normalizeTimestamp(nowUtc)` (and always `false` on `Completed` tasks or open tasks whose finite `suspendedAt <= nowUtc` has already elapsed). `_initialSuspendedNote` (`String?`) initializes to `hasActiveSuspension ? task?.suspendedNote : null`, and `_suspendedNoteController` initializes to `_initialSuspendedNote ?? ''`. Consequently, opening an open task with an elapsed finite deferral leaves `Suspended` unchecked, `_initialSuspendedNote == null`, and its note controller empty: saving as-is clears both `suspendedAt` and `suspendedNote`, and re-enabling `Suspended` starts with a clean note field without resurrecting stale expired deferral text. The temporary placeholder field `_hadActiveInitialSuspension` in `_EditTaskScreenState` is removed (`P-NO-DEAD-CODE`).
  - **Ownership Cleanup:** Toggling `Suspended` off (`_isSuspended = false`) hides `_TaskEditorSuspendedSection` and clears `_suspendedErrorMessage` and `_suspendedNoteErrorMessage` (while retaining `_suspendedNoteController.text` in widget state during the open editor session in case the user toggles `Suspended` back on before saving). Saving with `!_isSuspended` passes `clearSuspendedAt: true` and `clearSuspendedNote: true`, removing both `suspended` and `suspendedNote` (`spec/TDF_SPEC_0.7.0.md` Sections 4.1.2 and 6.6). Clearing or emptying `task_editor_suspended_note_input` while keeping `_isSuspended == true` passes `suspendedNote: null` and `clearSuspendedNote: true`, stripping only `suspendedNote` and advancing `task.modified` once.
* **Deadline Note (`dueNote`):**
  - Rendered inside `_TaskEditorDueSection` whenever `hasDue == true` (and `dueController != null`), placed directly below `_TaskEditorDueAutoPrioritizeRow` (`task_editor_due_auto_prioritize_switch`, delivered in `TEP-010`) when `showAutoPrioritizeToggle` is `true`, or directly below `task_editor_due_input` when `showAutoPrioritizeToggle` is `false` (when editing a `Completed` task).
  - Uses `TaskEditorSchedulingNoteField` with `fieldKey: const ValueKey('task_editor_due_note_input')`, `clearButtonKey: const ValueKey('task_editor_due_note_clear_button')`, `showClearWhenUnfocused: true`, `minLines: 1`, `maxLines: 3`, `keyboardType: TextInputType.multiline`, `textInputAction: TextInputAction.newline`, and `focusedColor: appTheme.secondaryAccent`.
  - **Initialization & Ownership Lifecycle:** `_initialDueNote` (`String?`) initializes to `task?.dueAt != null ? task?.dueNote : null` (across upcoming deadlines, overdue open deadlines `dueAt <= nowUtc`, Mode 2 recurring tasks, and `Completed` tasks), and `_dueNoteController` initializes to `_initialDueNote ?? ''`. Toggling `Due` off (`_hasDue = false`) hides `_TaskEditorDueSection` and clears `_dueErrorMessage`, `_dueNoteErrorMessage`, and `_repeatLeadDaysErrorMessage`. Saving with `!_hasDue` passes `clearDueAt: true` and `clearDueNote: true`. Clearing `task_editor_due_note_input` while keeping `_hasDue == true` passes `dueNote: null` and `clearDueNote: true`, removing `dueNote` while preserving `dueAt` and `isDuePassive`.
* **Untouched Note Preservation, Multi-Line Normalization & Bounds Validation (`<= 2000` Scalar Values):**
  - **Lossless Untouched Preservation:** `spec/TDF_SPEC_0.7.0.md` Section 2.8 preserves decoded `\r` (`0x0D`) inside `<note>` values loaded from external `.tdf` files. When editing an existing task whose `_initialSuspendedNote != null && _suspendedNoteController.text == _initialSuspendedNote` (while `_isSuspended` is `true`) or `_initialDueNote != null && _dueNoteController.text == _initialDueNote` (while `_hasDue` is `true`), `_EditTaskScreenState` resolves `_initialSuspendedNote` or `_initialDueNote` verbatim before validation so saving an unedited note never mutates `\r` line endings or triggers a spurious `task.modified` revision bump.
  - **Normalization (`TaskEditorSchedulingNoteField.normalizeSchedulingNote`):** For newly entered or modified text, scans UTF-16 code units in a single $O(N)$ pass:
    1. Checks whether at least one code unit lies outside ASCII `<note>` whitespace (`{0x09, 0x0A, 0x0D, 0x20}`). If none exists (empty `""` or ASCII spaces/tabs/CR/LF only), returns `null` immediately with zero allocations so canonical serialization omits `"<note>"` rather than failing with `TdfErrorKind.emptyText`. Non-ASCII graphic whitespace such as `U+00A0` is retained as graphic content per `spec/TDF_SPEC_0.7.0.md` Section 2.8.
    2. If no `\r` (`0x0D`) code unit is present, returns `rawText` directly without copying (`P-ZERO-COPY`), preserving leading, internal, and trailing spaces, `\t`, and `\n` verbatim.
    3. If `\r` (`0x0D`) is present alongside graphic content (such as clipboard text pasted on Windows), converts `\r\n` (`0x0D 0x0A`) and standalone `\r` (`0x0D`) to `\n` (`0x0A`) in one linear `StringBuffer` pass.
  - **Validation (`TaskEditorSchedulingNoteField.validateSchedulingNote`):** Returns `null` when `normalizedNote == null`. Otherwise:
    1. Calls `TdfCalendar.countUnicodeScalars(normalizedNote)` (`lib/models/tdf_timezone.dart`) to count decoded Unicode scalar values in $O(N)$ without allocating a `Runes` iterator, returning `localizations.schedulingNoteErrorInvalid` if `null` (unpaired UTF-16 surrogate in `0xD800..0xDFFF`).
    2. Scans code units once and returns `localizations.schedulingNoteErrorInvalid` if any forbidden control character (`(unit <= 0x1F && unit != 0x09 && unit != 0x0A && unit != 0x0D) || unit == 0x7F`) is present.
    3. Returns `localizations.schedulingNoteErrorTooLong` when `scalarCount > maxTdfNoteLength` (`2000` in `lib/models/tdf_error.dart`), matching `TaskBoardMutator._validateScheduleNote` (`lib/models/task_board_mutator.dart`).

#### 1.4.2 Recurring Preparation Lead (`lead <lead-count> days`) in `TaskEditorRepeatField`
Inside `TaskEditorRepeatField` (`lib/ui/widgets/task_editor_scheduling_card.dart`):
* **Conditional Visibility (`isRepeating && hasDue`):** `_RepeatLeadDaysInput` (`fieldKey: const ValueKey('task_editor_repeat_lead_days_input')`, `clearButtonKey: const ValueKey('task_editor_repeat_lead_days_clear_button')`, `showClearWhenUnfocused: true`, `keyboardType: TextInputType.number`) is rendered `8` logical pixels below the `days` / `weeks` / `months` unit chip row **only when both `isRepeating == true` and `hasDue == true`**. When `!hasDue` (Mode 1 completion-relative recurrence), `spec/TDF_SPEC_0.7.0.md` Sections 6.4 and 6.10.3 ignore `leadDays`, so hiding the input prevents authoring an inert `lead` clause.
* **Initialization & Mode Transitions:**
  - In `_EditTaskScreenState.initState`, `final initialLeadDays = task?.repeatRule?.leadDays ?? 0;` initializes `_repeatLeadDaysController` to `initialLeadDays > 0 ? initialLeadDays.toString() : ''` regardless of whether `task?.dueAt` is currently present (so a Mode 2 recurring task restored via `TaskNotifier.restoreTask`, which strips `due` while retaining `repeat ... lead <N> days` per `spec/TDF_SPEC_0.7.0.md` Section 6.5, immediately reveals its saved `leadDays` if the user re-enables `Due` in `EditTaskScreen`).
  - If the user saves while `_isRepeating == true` and `_hasDue == false`, `parseLeadDays` resolves `0`, omitting `lead <lead-count> days` in canonical `.tdf` output.
* **Independent Count & Lead-Day Validation (`0..3650`):**
  - `TaskEditorRepeatField.parseRepeatCount` validates `rawCount` (`1..TaskRepeatRule.maxRepeatCount` = `3650`) separately from `TaskEditorRepeatField.parseLeadDays` (`0..TaskRepeatRule.maxRepeatCount` = `3650`). An invalid `Preparation lead (days)` entry therefore surfaces `localizations.repeatLeadDaysErrorInvalid` exclusively on `task_editor_repeat_lead_days_input` without falsely marking a valid `task_editor_repeat_count_input` invalid.
  - Blank trimmed input (`''`) or unsigned `'0'` (including `'00'`) resolves to `leadDays = 0`. Unsigned ASCII decimal integers in `1..3650` resolve to `leadDays = parsedValue`, emitted as `repeat <count> <unit> [<repeat-time>] lead <leadDays> days`.
  - Signed strings (`'-1'`, `'-0'`, `'+5'`), fractional/non-digit strings (`'14.5'`, `'abc'`), or values exceeding `maxTdfNumberLength` (`24` ASCII chars, checked before integer accumulation per `P-BOUND-ALLOC`) or `TaskRepeatRule.maxRepeatCount` (`3650`, such as `'3651'`) return `null` from `parseLeadDays` and block submission with `localizations.repeatLeadDaysErrorInvalid`.
  - Existing `TaskRepeatRule.clock` (`widget.initialTask?.repeatRule?.clock ?? TdfRepeatClock.midnight`) is preserved losslessly when constructing the saved `TaskRepeatRule`.

#### 1.4.3 Display & Live Reactivity in `TaskInfoDialog`
`TaskInfoDialog` (`lib/ui/widgets/task_info_dialog.dart`) resolves `final currentTask = board.findTask(task.id) ?? task;` from `taskNotifierProvider` so open dialogs update live on external `Directory.watch` `.tdf` reconciliations, label edits, and `boundaryTickProvider` ticks while preserving fallback rendering when `widget.task` is mounted against an empty or detached `TaskBoard` in isolated widget tests:
1. **Suspended Section (`task_info_section_suspended_task_indicator`):**
   - Rendered strictly when `currentTask.hasActiveSuspendedAt(nowUtc)` (`isSuspendedForever` or `suspendedAt > TaskItem.normalizeTimestamp(nowUtc)`). Once a finite deferral reaches `suspendedAt <= normalizedNow`, the entire suspended card (including `task_info_suspended_note`) hides automatically on the `boundaryTickProvider` tick.
   - When `currentTask.suspendedNote` is non-null and non-empty, `_TaskInfoSectionCard` renders `_TaskInfoNoteBody` containing `SelectableText(note, key: const ValueKey('task_info_suspended_note'), style: Theme.of(context).textTheme.bodySmall)` `6` logical pixels beneath the section header/details.
2. **Due Section (`task_info_section_due_task_badge`):**
   - Rendered whenever `currentTask.dueAt != null` (upcoming deadlines, overdue deadlines `dueAt <= normalizedNow`, and `Completed` tasks).
   - Renders the local wall-clock deadline (`taskInfoDueAt` or `taskInfoDueOverdue`) and any open-task auto-priority status detail line (`_buildDueStatusDetails`), followed by `_TaskInfoNoteBody` with `SelectableText(note, key: const ValueKey('task_info_due_note'), style: Theme.of(context).textTheme.bodySmall)` when `currentTask.dueNote` is non-null and non-empty.
3. **Repeat Section (`task_info_section_repeat_task_indicator`):**
   - Rendered whenever `currentTask.repeatRule != null`.
   - Appends `localizations.taskInfoRepeatLeadDays(repeatRule.leadDays.toString())` to `_TaskInfoSectionData.details` (after `taskInfoRepeatCompletions` if `currentTask.completions > 0`) strictly when `repeatRule.leadDays > 0 && currentTask.dueAt != null`.

#### 1.4.4 Platform Ergonomics & Localization (`Linux`, `Android`, `Windows`; `en`, `de`)
* **Desktop & Mobile Input Ergonomics:** Setting `keyboardType: TextInputType.multiline` and `textInputAction: TextInputAction.newline` on `TaskEditorSchedulingNoteField` ensures pressing `Enter` on Linux/Windows hardware keyboards or the Android soft-keyboard newline key inserts `\n` inside the `1..3`-line field rather than submitting the form, while `SingleChildScrollView` in `EditTaskScreen` and `TaskInfoDialog` (`ConstrainedBox(maxWidth: 420)`) prevents vertical viewport overflow when multiple 3-line notes and virtual keyboards are visible simultaneously. `SelectableText` inside `TaskInfoDialog` supports click-and-drag copy on Linux/Windows and long-press selection handles on Android.
* **Bilingual Localization (`en` & `de`):** All labels, hints, validation errors, and dialog summaries are externalized in `lib/l10n/app_en.arb` and `lib/l10n/app_de.arb` and verified via `tiertask_dev.py verify` (`audit_l10n`).

### 1.5 Alternatives
1. **Single-Line Text Fields for `suspendedNote` and `dueNote`:** Rejected because `spec/TDF_SPEC_0.7.0.md` Sections 2.8 and 4.1.2 define both scheduling `<note>` arguments using the multi-line `<note>` primitive (`\n`, `\r`, `\t`, `\"`, `\\`, `1..2000` Unicode scalar values). Single-line `TextField` widgets strip or flatten line breaks when editing multi-line notes created in external `.tdf` editors.
2. **Display `Preparation lead (days)` When `hasDue == false`:** Rejected because `spec/TDF_SPEC_0.7.0.md` Sections 6.4 and 6.10.3 apply `lead <lead-count> days` exclusively in Mode 2 (`due` present) and ignore `lead` in Mode 1 (`due` omitted). Hiding the input when `!hasDue` and resolving `leadDays = 0` on save prevents users from configuring an inactive parameter while preserving `initialLeadDays` in `_repeatLeadDaysController` during the edit session if `Due` is toggled back on.
3. **Add Dedicated Pill Icons for `suspendedNote` and `dueNote` on `TierTaskPill`:** Rejected because `TierTaskPill` limits inline indicators to `maxVisibleTaskIndicators = 3` before collapsing into `summary_task_indicator`, and ownership invariants guarantee that `suspendedNote` only exists alongside `suspended` (`suspended_task_indicator_<id>`) and `dueNote` only exists alongside `due` (`due_task_badge_<id>`).
4. **Combined `parseRepeatRule` Returning Only `TaskRepeatRule?` Without Separate Count/Lead Parsers:** Rejected because returning `null` for both invalid `count` and invalid `leadDays` cannot distinguish which text field failed validation, causing `EditTaskScreen` to display `repeatErrorInvalid` on `task_editor_repeat_count_input` when only `task_editor_repeat_lead_days_input` is invalid. Providing dedicated `parseRepeatCount` and `parseLeadDays` helpers keeps field-level error attribution exact.

## Part 2: Technical Design & Code Changes

### 2.1 Architecture & Affected Modules

All modifications preserve the acyclic bottom-up layer DAG (`P-ACYCLIC-DAG`: `lib/ui/*` at Rank `6` imports only Rank `0` `lib/services/app_logger.dart`, Rank `1` `lib/models/*`, Rank `2` `lib/l10n/*`, and existing Rank `4` repositories and Rank `5` providers in `edit_task_screen.dart`) and keep `lib/ui/` completely free of `dart:io` imports (`P-IO-ISOLATION`).

| Layer | File | Change Type | Responsibility |
| :--- | :--- | :--- | :--- |
| Localization (`Rank 2`) | `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb` | Modify | Add 10 English and German ARB entries (with `@key` descriptions and `{days}` placeholder metadata) for deferral/deadline note labels and hints, note length and control-character errors, preparation lead label/hint/error, and `TaskInfoDialog` repeat lead summary; regenerate `lib/l10n/app_localizations*.dart` via `flutter gen-l10n`. |
| UI (`Rank 6`) | `lib/ui/widgets/task_editor_scheduling_card.dart` | Modify | Add `TaskEditorSchedulingNoteField` (`normalizeSchedulingNote`, `validateSchedulingNote`) and shared file-private `_buildSchedulingInputDecoration`, extend `TaskEditorRepeatField` with `_RepeatLeadDaysInput`, `parseRepeatCount`, `parseLeadDays`, and optional `existingClock`/`hasDue`/`rawLeadDays` parameters on `parseRepeatRule`, extract `_TaskEditorSuspendedSection`, and wire note and lead-day controllers/errors through `TaskEditorSchedulingCard` and `_TaskEditorDueSection` with all `build()` methods `< 40` lines (`P-FLATTEN-BUILD`). |
| UI (`Rank 6`) | `lib/ui/edit_task_screen.dart` | Modify | Replace obsolete `_hadActiveInitialSuspension` with `_suspendedNoteController`, `_dueNoteController`, `_repeatLeadDaysController`, `_initialSuspendedNote`, `_initialDueNote`, and per-field error messages; extract `_EditTaskBlockedBySection`, `_validateAndBuildDraft`, `_handlePersistFailure`, and `_logTaskSaved` so all `build()` methods and `_submit` stay `< 40` lines; pass explicit `isSuspendedForever` in `_persistTask`; guard `_persistTask` against synchronous `TdfException` / `FormatException` bounds (`P-ATOMIC-STATE`); emit redacted `AppLogger` events (`P-SECRET-HYGIENE`). |
| UI (`Rank 6`) | `lib/ui/widgets/task_info_dialog.dart` | Modify | Resolve `board.findTask(task.id) ?? task` in `TaskInfoDialog.build` and forward `currentTask` to `_buildDialogTitle` and `_buildSections`; add `noteBody` and `noteKey` to `_TaskInfoSectionData` and private `_TaskInfoNoteBody` (`SelectableText`) in `_TaskInfoSectionCard`; wire `task_info_suspended_note`, `task_info_due_note`, and conditional `taskInfoRepeatLeadDays` detail line. |
| Documentation | `ARCHITECTURE.md`, `CHANGELOG.md` | Modify | Update UI module table rows (`<= 65` words per row) for `edit_task_screen.dart`, `task_editor_scheduling_card.dart`, and `task_info_dialog.dart`, verify directory tree sync via `tiertask_dev.py arch --sync-tree`, and add user-facing `CHANGELOG.md` entry under `## [Unreleased]`. |
| Tests | `test/ui/edit_task_screen_test.dart`, `test/ui/widgets/task_info_dialog_test.dart` | Modify | Add Red-Green-Refactor unit and widget tests covering `M-EXHAUSTIVE-STATE-TESTS`, `M-EXTREME-BOUND-TESTS`, `M-DELIM-INJECT-TESTS`, and `M-REAL-MECHANICS-TESTS`. |

### 2.2 TDF Schema, Localization & State Changes

#### 2.2.1 TDF `0.7.0` Schema & Domain Reliance (`TEP-006` & `TEP-010`)
No changes to `spec/TDF_SPEC_0.7.0.md`, `lib/models/`, `lib/services/`, `lib/repositories/`, or `lib/providers/` are required; `TEP-011` consumes these already-implemented primitives directly:
* `lib/models/tdf_error.dart`: `const int maxTdfNoteLength = 2000;`, `const int maxTdfNumberLength = 24;`, `TdfException`, and `TdfErrorKind` (`spec/TDF_SPEC_0.7.0.md` Sections 7 and 8).
* `lib/models/tdf_timezone.dart`: `TdfCalendar.countUnicodeScalars(String value)` (returns `null` on unpaired UTF-16 surrogates `0xD800..0xDFFF`, else exact Unicode scalar count) and `TdfRepeatClock` (`TdfRepeatClock.midnight`).
* `lib/models/task_item.dart`: `TaskItem.suspendedNote`, `TaskItem.dueNote`, `TaskItem.hasActiveSuspendedAt(DateTime nowUtc)`, `TaskRepeatRule.leadDays`, `TaskRepeatRule.clock`, and `TaskRepeatRule.maxRepeatCount = 3650`.
* `lib/providers/task_providers.dart`: `TaskNotifier.addTask` (`dueNote`, `isSuspendedForever`, `suspendedAt`, `suspendedNote`, `repeatRule`) and `TaskNotifier.updateTask` (`dueNote`, `clearDueNote`, `isSuspendedForever`, `suspendedAt`, `suspendedNote`, `clearSuspendedAt`, `clearSuspendedNote`, `repeatRule`, `clearRepeatRule`), backed by `TaskBoardMutator._validateScheduleNote` and `TaskBoardMutator._validateRepeatRule` (`lib/models/task_board_mutator.dart`).

#### 2.2.2 Localization Keys (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`)

Every key in `lib/l10n/app_en.arb` includes a matching `@<key>` metadata block with `"description"` (and `"placeholders"` for parameterized strings) to satisfy `tiertask_dev.py verify` (`audit_l10n`):

| Key | English (`app_en.arb`) | German (`app_de.arb`) | `@key` Metadata (`app_en.arb`) |
| :--- | :--- | :--- | :--- |
| `taskSuspendedNoteLabel` | `"Deferral note (optional)"` | `"Zurückstellungsnotiz (optional)"` | `description`: `"Input label for the optional deferral note field shown when Suspended is enabled."` |
| `taskSuspendedNoteHint` | `"Why is this task deferred?"` | `"Warum ist diese Aufgabe zurückgestellt?"` | `description`: `"Placeholder hint for the optional deferral note input field."` |
| `taskDueNoteLabel` | `"Deadline note (optional)"` | `"Fälligkeitsnotiz (optional)"` | `description`: `"Input label for the optional deadline note field shown when Due is enabled."` |
| `taskDueNoteHint` | `"Cutoff details or submission requirements"` | `"Fristdetails oder Abgabebedingungen"` | `description`: `"Placeholder hint for the optional deadline note input field."` |
| `schedulingNoteErrorTooLong` | `"Note must not exceed 2,000 characters."` | `"Notiz darf maximal 2.000 Zeichen lang sein."` | `description`: `"Validation error shown when a deferral or deadline note exceeds 2,000 Unicode scalar values."` |
| `schedulingNoteErrorInvalid` | `"Note contains unsupported control characters."` | `"Notiz enthält nicht unterstützte Steuerzeichen."` | `description`: `"Validation error shown when a deferral or deadline note contains disallowed control characters or unpaired surrogates."` |
| `repeatLeadDaysLabel` | `"Preparation lead (days, optional)"` | `"Vorbereitungszeit (Tage, optional)"` | `description`: `"Input label for the recurring preparation lead window in days when both Repeat and Due are enabled."` |
| `repeatLeadDaysHint` | `"0 (activate immediately after rollover)"` | `"0 (sofort nach Wiederholung aktivieren)"` | `description`: `"Placeholder hint for the optional recurring preparation lead days input field."` |
| `repeatLeadDaysErrorInvalid` | `"Enter a whole number between 0 and 3650 days."` | `"Ganze Zahl zwischen 0 und 3650 Tagen eingeben."` | `description`: `"Validation error shown when the recurring preparation lead input is not an integer in 0..3650."` |
| `taskInfoRepeatLeadDays` | `"Preparation window opens {days} day(s) before due date"` | `"Vorbereitungsfenster öffnet {days} Tag(e) vor Fälligkeit"` | `description`: `"Detail line in TaskInfoDialog describing the Mode 2 recurring preparation lead offset."`, `placeholders`: `{"days": {"type": "String"}}` |

### 2.3 Implementation Details

#### 2.3.1 `TaskEditorSchedulingNoteField`, `TaskEditorRepeatField` & `TaskEditorSchedulingCard` (`lib/ui/widgets/task_editor_scheduling_card.dart`)
* **Imports (`P-DIRECTIVES-ORDER`):** Add relative imports `../../models/tdf_error.dart` and `../../models/tdf_timezone.dart` in strict ASCII order among the `lib/` relative imports (`app_localizations.dart`, `tier_localization_extension.dart`, `task_item.dart`, `task_tier.dart`, `tdf_error.dart`, `tdf_timezone.dart`, `../app_theme.dart`, `clearable_text_field.dart`, `task_editor_sections.dart`).
* **`TaskEditorSchedulingNoteField` (`StatelessWidget`, `build()` `< 40` lines):**
  ```dart
  class TaskEditorSchedulingNoteField extends StatelessWidget {
    const TaskEditorSchedulingNoteField({
      super.key,
      required this.clearButtonKey,
      required this.controller,
      this.errorMessage,
      required this.fieldKey,
      required this.focusedColor,
      required this.hintText,
      required this.labelText,
    });

    final Key clearButtonKey;
    final TextEditingController controller;
    final String? errorMessage;
    final Key fieldKey;
    final Color focusedColor;
    final String hintText;
    final String labelText;

    @override
    Widget build(BuildContext context);

    static String? normalizeSchedulingNote(String rawText);

    static String? validateSchedulingNote(
      String? normalizedNote,
      AppLocalizations localizations,
    );
  }
  ```
  - `build` renders `ClearableTextField` with `fieldKey: fieldKey`, `clearButtonKey: clearButtonKey`, `clearIconColor: appTheme.mutedTextColor`, `showClearWhenUnfocused: true`, `controller: controller`, `cursorColor: focusedColor`, `keyboardType: TextInputType.multiline`, `textInputAction: TextInputAction.newline`, `minLines: 1`, `maxLines: 3`, `style: TextStyle(color: appTheme.primaryTextColor, fontSize: 14)`, and a new file-private top-level helper `_buildSchedulingInputDecoration(...)` (`appTheme: appTheme`, `errorText: errorMessage`, `focusedColor: focusedColor`, `hintText: hintText`, `labelText: labelText`) placed in the file's top-level functions section (`AGENTS.md` Section 2) and shared with `TaskEditorRepeatField` and `_RepeatLeadDaysInput`.
  - `normalizeSchedulingNote(String rawText)`:
    - Scans `rawText` code units once (`0..rawText.length - 1`) recording `hasGraphic = false` (`unit != 0x09 && unit != 0x0A && unit != 0x0D && unit != 0x20`) and `firstCrIndex = -1` (first index where `unit == 0x0D`).
    - If `!hasGraphic`, returns `null` (handles `""` and any combination of spaces, `\t`, `\r`, `\n` without allocation).
    - If `firstCrIndex < 0`, returns `rawText` directly (`P-ZERO-COPY`).
    - Otherwise delegates to `_collapseCrLineEndings(rawText, firstCrIndex)`, which seeds a `StringBuffer(rawText.substring(0, firstCrIndex))` and iterates from `firstCrIndex` to `rawText.length - 1`, writing `'\n'` for each `0x0D` (advancing an extra index when followed by `0x0A`) and `writeCharCode(unit)` for all other units (`<= 3` indentation levels per `P-FLAT-CONTROL-FLOW`, single-level loop `< 25` lines per `P-LOOP-MODULARITY`).
  - `validateSchedulingNote(String? normalizedNote, AppLocalizations localizations)`:
    - Returns `null` when `normalizedNote == null`.
    - Computes `final scalarCount = TdfCalendar.countUnicodeScalars(normalizedNote);`; if `scalarCount == null` or `_containsIllegalNoteControlChar(normalizedNote)`, returns `localizations.schedulingNoteErrorInvalid`.
    - If `scalarCount > maxTdfNoteLength`, returns `localizations.schedulingNoteErrorTooLong`.
    - Otherwise returns `null`.
* **`TaskEditorRepeatField` & `_RepeatLeadDaysInput` (`build()` `< 40` lines):**
  - Add optional fields to `TaskEditorRepeatField`:
    - `final TextEditingController? leadDaysController;`
    - `final String? leadDaysErrorMessage;`
    - `final bool showLeadDays;` (defaults to `false`; set to `hasDue` by `TaskEditorSchedulingCard`)
  - Extract private `_RepeatLeadDaysInput` (`StatelessWidget`) rendering `ClearableTextField` (`fieldKey: const ValueKey('task_editor_repeat_lead_days_input')`, `clearButtonKey: const ValueKey('task_editor_repeat_lead_days_clear_button')`, `showClearWhenUnfocused: true`, `keyboardType: TextInputType.number`, `cursorColor: appTheme.tertiaryAccent`, `labelText: localizations.repeatLeadDaysLabel`, `hintText: localizations.repeatLeadDaysHint`, `errorText: leadDaysErrorMessage`). In `TaskEditorRepeatField.build`, append `if (showLeadDays && leadDaysController != null) ...[const SizedBox(height: 8), _RepeatLeadDaysInput(controller: activeLeadController, errorMessage: leadDaysErrorMessage)]` using local variable promotion `if (leadDaysController case final activeLeadController? when showLeadDays)` (`P-NULL-SAFE`).
  - Static parsing helpers on `TaskEditorRepeatField`:
    ```dart
    static int? parseLeadDays({
      required bool hasDue,
      required bool isRepeating,
      required String rawLeadDays,
    });

    static int? parseRepeatCount({
      required bool isRepeating,
      required String rawCount,
    });

    static TaskRepeatRule? parseRepeatRule({
      TdfRepeatClock existingClock = TdfRepeatClock.midnight,
      bool hasDue = false,
      required bool isRepeating,
      required String rawCount,
      String rawLeadDays = '',
      required RepeatUnit unit,
    });
    ```
    - Both `parseRepeatCount` and `parseLeadDays` use a shared file-private `_tryParseBoundedUnsignedInt(String trimmed, {required int min, required int max})` helper that rejects `trimmed.isEmpty` or `trimmed.length > maxTdfNumberLength` (`24`, `P-BOUND-ALLOC`) upfront, scans ASCII digits `0x30..0x39` (rejecting signs `'-'`/`'+'`, decimals, spaces, and letters), and checks `value > max` inside the loop before overflow so arbitrarily long digit strings never overflow 64-bit integers.
    - When `!isRepeating || !hasDue`, `parseLeadDays` returns `0`. When `isRepeating && hasDue`, `trimmed.isEmpty` returns `0`; otherwise `_tryParseBoundedUnsignedInt(trimmed, min: 0, max: TaskRepeatRule.maxRepeatCount)` returns `0..3650` or `null`.
    - `parseRepeatCount` returns `null` when `!isRepeating`, else `_tryParseBoundedUnsignedInt(rawCount.trim(), min: 1, max: TaskRepeatRule.maxRepeatCount)`.
    - `parseRepeatRule` returns `null` when `!isRepeating`, combines `parseRepeatCount` and `parseLeadDays`, and returns `TaskRepeatRule(count: count, unit: unit, clock: existingClock, leadDays: leadDays)` when both are non-null (or `null` otherwise).
* **`TaskEditorSchedulingCard`, `_TaskEditorSuspendedSection`, & `_TaskEditorDueSection` (`build()` `< 40` lines):**
  - Add optional fields on `TaskEditorSchedulingCard`:
    - `final TextEditingController? dueNoteController;`
    - `final String? dueNoteErrorMessage;`
    - `final TextEditingController? repeatLeadDaysController;`
    - `final String? repeatLeadDaysErrorMessage;`
    - `final TextEditingController? suspendedNoteController;`
    - `final String? suspendedNoteErrorMessage;`
  - Extract `_TaskEditorSuspendedSection` (`StatelessWidget`) rendering `TaskEditorSuspendedField` and, when `noteController != null`, `TaskEditorSchedulingNoteField` (`fieldKey: const ValueKey('task_editor_suspended_note_input')`, `clearButtonKey: const ValueKey('task_editor_suspended_note_clear_button')`, `focusedColor: appTheme.warningAccent`, `labelText: localizations.taskSuspendedNoteLabel`, `hintText: localizations.taskSuspendedNoteHint`, `errorMessage: noteErrorMessage`). Extracting `_TaskEditorSuspendedSection` reduces `TaskEditorSchedulingCard.build` from `56` lines to `< 40` lines (`P-FLATTEN-BUILD`).
  - Extend `_TaskEditorDueSection` with `noteController` and `noteErrorMessage` (extracting `_TaskEditorDueTimestampField` as a private `StatelessWidget` so `_TaskEditorDueSection.build` remains `< 35` lines) to render `TaskEditorSchedulingNoteField` (`fieldKey: const ValueKey('task_editor_due_note_input')`, `clearButtonKey: const ValueKey('task_editor_due_note_clear_button')`, `focusedColor: appTheme.secondaryAccent`, `labelText: localizations.taskDueNoteLabel`, `hintText: localizations.taskDueNoteHint`, `errorMessage: noteErrorMessage`) below `_TaskEditorDueAutoPrioritizeRow` (or directly below `_TaskEditorDueTimestampField` when `!showAutoPrioritizeToggle`).

#### 2.3.2 `EditTaskScreen` Integration, Error Handling & Telemetry (`lib/ui/edit_task_screen.dart`)
* **Imports (`P-DIRECTIVES-ORDER`):** Add `../models/tdf_error.dart` and `../models/tdf_timezone.dart` in strict ASCII order (`../models/task_board.dart`, `../models/task_item.dart`, `../models/task_tier.dart`, `../models/tdf_error.dart`, `../models/tdf_metadata.dart`, `../models/tdf_timezone.dart`, `../models/webdav_config.dart`).
* **Layout Flattening (`P-FLATTEN-BUILD`):** Extract the prerequisite blocker subtree (`TaskEditorBoardHelper.collectCandidateBlockerTasks` + `ValueListenableBuilder` wrapping `TaskEditorBlockedBySection`) from `_EditTaskFormColumn.build` into a private `_EditTaskBlockedBySection` `StatelessWidget` (`30` lines), place `TaskEditorDetailsCard` directly in `_EditTaskFormColumn.build` (`25` lines) above `_EditTaskSchedulingSection(state: state)`, and delegate callbacks in `_EditTaskSchedulingSection` (`35` lines) to named methods on `_EditTaskScreenState` (`_pickDueDate`, `_pickDueTime`, `_pickSuspendedDate`, `_pickSuspendedTime`, `_selectRepeatUnit`, `_toggleRepeat`, `_toggleSuspended`) so `_EditTaskFormColumn.build`, `_EditTaskBlockedBySection.build`, and `_EditTaskSchedulingSection.build` all remain strictly `< 40` lines.
* **Controller Lifecycle & Untouched-Note State (`P-DISPOSE-RESOURCES`, `P-NO-DEAD-CODE`, `P-NULL-SAFE`):**
  - Remove `late final bool _hadActiveInitialSuspension;`.
  - Add fields to `_EditTaskScreenState`:
    - `late final TextEditingController _dueNoteController;`
    - `String? _dueNoteErrorMessage;`
    - `late final String? _initialDueNote;`
    - `late final String? _initialSuspendedNote;`
    - `late final TextEditingController _repeatLeadDaysController;`
    - `String? _repeatLeadDaysErrorMessage;`
    - `late final TextEditingController _suspendedNoteController;`
    - `String? _suspendedNoteErrorMessage;`
  - In `initState()`:
    - `final hasActiveSuspension = task?.hasActiveSuspendedAt(nowUtc) ?? false;`
    - `_initialSuspendedNote = hasActiveSuspension ? task?.suspendedNote : null;`
    - `_suspendedNoteController = TextEditingController(text: _initialSuspendedNote ?? '')..addListener(_handleSuspendedNoteChanged);`
    - `_initialDueNote = task?.dueAt != null ? task?.dueNote : null;`
    - `_dueNoteController = TextEditingController(text: _initialDueNote ?? '')..addListener(_handleDueNoteChanged);`
    - `final initialLeadDays = task?.repeatRule?.leadDays ?? 0;`
    - `_repeatLeadDaysController = TextEditingController(text: initialLeadDays > 0 ? initialLeadDays.toString() : '')..addListener(_handleRepeatLeadDaysChanged);`
  - Dispose `_suspendedNoteController`, `_dueNoteController`, and `_repeatLeadDaysController` in `dispose()`.
  - Add listeners `_handleDueNoteChanged`, `_handleRepeatLeadDaysChanged`, and `_handleSuspendedNoteChanged` clearing their respective error messages on edit, and update `_toggleSuspended`, `_toggleDue`, and `_toggleRepeat` to clear stale field errors when disabled.
* **Validation, Atomic Persistence & `_ValidatedTaskDraft` (`_submit`, `_validateAndBuildDraft`, `_persistTask`):**
  - Extend `_ValidatedTaskDraft`:
    ```dart
    typedef _ValidatedTaskDraft = ({
      List<String> blockedByIds,
      DateTime? dueAt,
      String? dueNote,
      List<String> labelIds,
      List<TaskLink> links,
      TaskRepeatRule? repeatRule,
      List<SubtaskItem> subtasks,
      DateTime? suspendedAt,
      String? suspendedNote,
    });
    ```
  - Add helper `_resolveSchedulingNote({required bool isEnabled, required String rawText, required String? initialNote})`: returns `null` when `!isEnabled`; returns `initialNote` verbatim when `initialNote != null && rawText == initialNote`; otherwise returns `TaskEditorSchedulingNoteField.normalizeSchedulingNote(rawText)`.
  - Extract `_validateAndBuildDraft(TaskBoard board, AppLocalizations localizations)` (`< 40` lines, `<= 3` indentation levels):
    - Validates `titleError`, `suspendedAt`, `suspendedNote` (`suspendedNoteError`), `dueAt`, `dueNote` (`dueNoteError`), `repeatCount` (`TaskEditorRepeatField.parseRepeatCount`), and `leadDays` (`TaskEditorRepeatField.parseLeadDays`).
    - If any field is invalid, updates `_errorMessage`, `_suspendedErrorMessage`, `_suspendedNoteErrorMessage`, `_dueErrorMessage`, `_dueNoteErrorMessage`, `_repeatErrorMessage`, and `_repeatLeadDaysErrorMessage` in a single `setState`, emits a gated `LogLevel.warn` `ui.edit_task.validation_failed` `AppLogger.event` with boolean field flags, and returns `null`.
    - Otherwise constructs `repeatRule` (`TaskRepeatRule(count: repeatCount, unit: _repeatUnit, clock: widget.initialTask?.repeatRule?.clock ?? TdfRepeatClock.midnight, leadDays: leadDays ?? 0)` when `_isRepeating`, else `null`) and delegates to `_buildDraft(...)`.
  - In `_submit()` (`< 35` lines):
    - Calls `_validateAndBuildDraft(board, localizations)`; returns early if `null`.
    - Wraps `await _persistTask(draft)` in `try { ... } on TdfException catch (error) { _handlePersistFailure(error.kind.name, error.kind, localizations); return; } on FormatException { _handlePersistFailure('FormatException', null, localizations); return; }` (`P-ATOMIC-STATE`): if a synchronous `TaskBoardMutator` domain bound (`0001..9999` UTC proleptic calendar horizon check in `nextScheduleAnchoredOccurrence` / `_nextMutationModifiedAt` during recurring `subtasks auto-finish` rollover, `maxTdfStmtsPerBlock` in `_ensureTaskStatementBound`, or `TdfTaskDependency.maxCompletions` `FormatException`) rejects the mutation before `TaskNotifier._executePushToRemote` runs, `_handlePersistFailure` keeps `EditTaskScreen` open, logs `ui.edit_task.persist_rejected` (`LogLevel.warn`, `kind` only), and routes a localized inline error to a guaranteed-visible field (`_repeatLeadDaysErrorMessage = localizations.repeatLeadDaysErrorInvalid` on `TdfErrorKind.invalidTimestamp` when `_isRepeating && _hasDue`, else `_suspendedErrorMessage = localizations.taskSuspendedErrorInvalid` when `_isSuspended`, else `_dueErrorMessage = localizations.taskSuspendedErrorInvalid` when `_hasDue`, else `_errorMessage = localizations.taskSuspendedErrorInvalid` on `invalidTimestamp` or `_errorMessage = localizations.schedulingNoteErrorTooLong` on `TdfErrorKind.limitExceeded` / `FormatException`) without mutating board state. (Downstream serialization/storage failures inside `TaskSyncPipeline.synchronize`, such as `MAX_FILE_BYTES` / `MAX_LINE_COUNT`, continue to be caught, rolled back to `fallbackBoard`, and surfaced on `syncStateProvider` by `TaskNotifier._executePushToRemote`.)
    - On success, invokes `_logTaskSaved(draft)` to emit gated `LogLevel.info` `LogTag.ui` event `'ui.edit_task.saved'` with fields `{'id': widget.initialTask?.id ?? 'new', 'is_suspended': _isSuspended, 'has_suspended_note': draft.suspendedNote != null, 'has_due': _hasDue, 'has_due_note': draft.dueNote != null, 'is_repeating': _isRepeating, 'lead_days': draft.repeatRule?.leadDays ?? 0}` (`P-SECRET-HYGIENE`), checks `if (!mounted) return;`, pops the route, and invokes `widget.onSubmitted?.call()`.
  - In `_persistTask(_ValidatedTaskDraft draft)`:
    - Computes `final isIndefiniteSuspension = _isSuspended && _suspendedController.text.trim().isEmpty;` and `final effectiveSuspendedAt = isIndefiniteSuspension ? null : draft.suspendedAt;` so blank deferral input persists `isSuspendedForever: true` (`suspended forever ["<note>"]`) rather than a finite `TaskItem.defaultSuspendedAt` (`9999-12-31 23:59`) across both `addTask` (where `TaskNotifier.addTask` defaults `isSuspendedForever = false`) and `updateTask`, while preserving an explicitly typed `9999-12-31 23:59` as a finite timestamp.
    - `updateTask` branch passes `targetTier: (!_isCompletedTask && _mode == _initialEditorMode) ? null : _mode.targetTier` (preventing spurious `task.modified` bumps on no-op saves of open `Focus`/`Ready`/`Blocked` tasks), `dueNote: draft.dueNote`, `clearDueNote: !_hasDue || draft.dueNote == null`, `suspendedAt: effectiveSuspendedAt`, `isSuspendedForever: _isSuspended ? isIndefiniteSuspension : false`, `suspendedNote: draft.suspendedNote`, `clearSuspendedAt: !_isSuspended`, and `clearSuspendedNote: !_isSuspended || draft.suspendedNote == null`.
    - `addTask` branch passes `dueNote: draft.dueNote`, `suspendedAt: effectiveSuspendedAt`, `isSuspendedForever: isIndefiniteSuspension`, and `suspendedNote: draft.suspendedNote`.

#### 2.3.3 `TaskInfoDialog` Live Resolution & Section Rendering (`lib/ui/widgets/task_info_dialog.dart`)
* **Live `TaskBoard` Resolution:** In `TaskInfoDialog.build` (`< 35` lines), resolve `final currentTask = board.findTask(task.id) ?? task;` and pass `currentTask` to `_buildDialogTitle(context, localizations, currentTask)` and `_buildSections(board: board, configuration: configuration, currentTask: currentTask, localizations: localizations, nowUtc: nowUtc)` (forwarding `currentTask` rather than `this.task` to all 10 `_build*Section` helpers) so live edits and external `Directory.watch` `.tdf` updates reflect immediately in an open `TaskInfoDialog`.
* **View Model & Card Subtree (`P-FLATTEN-BUILD`):**
  - Extend `_TaskInfoSectionData` with `final String? noteBody;` and `final Key? noteKey;`.
  - Add private `_TaskInfoNoteBody` (`StatelessWidget`) rendering `Padding(padding: const EdgeInsets.only(top: 6), child: SelectableText(note, key: noteKey, style: Theme.of(context).textTheme.bodySmall))` and mount `if (data.noteBody case final note? when note.isNotEmpty) _TaskInfoNoteBody(note: note, noteKey: data.noteKey)` at the bottom of `_TaskInfoSectionCard.build` (`31` lines total, `< 40` lines).
* **Section Builders:**
  - `_buildSuspendedSection`: continues gating on `if (!task.hasActiveSuspendedAt(nowUtc)) return null;`, and passes `noteBody: task.suspendedNote` and `noteKey: const ValueKey('task_info_suspended_note')` on both the `isSuspendedForever` and finite `suspendedAt > normalizedNow` return paths.
  - `_buildDueSection`: passes `noteBody: task.dueNote` and `noteKey: const ValueKey('task_info_due_note')` alongside existing `_buildDueStatusDetails(...)`.
  - `_buildRepeatSection`: builds `details` as:
    ```dart
    final details = <String>[
      if (task.completions > 0)
        localizations.taskInfoRepeatCompletions(task.completions.toString()),
      if (repeatRule.leadDays > 0 && task.dueAt != null)
        localizations.taskInfoRepeatLeadDays(repeatRule.leadDays.toString()),
    ];
    ```

### 2.4 Testing Strategy
All tests are written first (`P-TDD-FIRST`) in `test/ui/edit_task_screen_test.dart` and `test/ui/widgets/task_info_dialog_test.dart` using `pumpLeafWidget` (`FakeTaskNotifier`) and `ProviderContainer` harnesses without external network access:
* **`M-EXHAUSTIVE-STATE-TESTS`:**
  - Verify `task_editor_suspended_note_input` appears if and only if `Suspended` is active (both new/existing indefinite `suspended forever` and finite future `suspendedAt > nowUtc`), hides when `Suspended` is unchecked (including open tasks initialized with an expired finite `suspendedAt <= nowUtc`), renders `task_editor_suspended_note_clear_button` whenever focused or populated (`showClearWhenUnfocused: true`), persists `isSuspendedForever == true` (`suspended forever "<note>"`) when creating a new task with blank deferral timestamp and a deferral note, and clears only `suspendedNote` when `task_editor_suspended_note_clear_button` is tapped while keeping `Suspended` enabled.
  - Verify `task_editor_due_note_input` appears if and only if `Due` is active (across new tasks, open upcoming/overdue tasks alongside `task_editor_due_auto_prioritize_switch`, and `Completed` tasks where `task_editor_due_auto_prioritize_switch` is hidden), renders `task_editor_due_note_clear_button` whenever focused or populated (`showClearWhenUnfocused: true`), and clears only `dueNote` when `task_editor_due_note_clear_button` is tapped while keeping `Due` and `isDuePassive` intact.
  - Verify `task_editor_repeat_lead_days_input` appears strictly when `isRepeating && hasDue`, hides when either `Due` or `Repeat` is toggled off, retains draft controller text if `Due` is toggled off and back on before `Save`, resets persisted `leadDays` to `0` when saved with `!hasDue`, and attributes validation errors independently between `task_editor_repeat_count_input` (`repeatErrorInvalid`) and `task_editor_repeat_lead_days_input` (`repeatLeadDaysErrorInvalid`).
  - Verify `TaskInfoDialog` in both English (`en`) and German (`de`) locales: renders `task_info_suspended_note` (`SelectableText`) for `suspended forever` and future `suspendedAt > nowUtc`, omits `task_info_suspended_note` when `suspendedNote == null`, hides the entire suspended section when `suspendedAt <= nowUtc`, renders `task_info_due_note` (`SelectableText`) across upcoming, overdue, passive, and `Completed` tasks, and renders `taskInfoRepeatLeadDays` strictly when `repeatRule.leadDays > 0 && task.dueAt != null` (omitting it when `leadDays == 0` or `dueAt == null`).
* **`M-EXTREME-BOUND-TESTS`:**
  - Test `suspendedNote` and `dueNote` scalar boundaries: `0` chars (`null`), `1` char (accepted), `2000` ASCII chars (accepted), `2000` astral-plane Unicode scalar values `U+1F4CB` (`4000` UTF-16 code units, `countUnicodeScalars == 2000`, accepted), and `2001` Unicode scalar values (rejected inline with `schedulingNoteErrorTooLong`, keeping `EditTaskScreen` open and `TaskBoard` unchanged).
  - Test `Preparation lead (days)` boundaries: `''` (`0`), `'0'` (`0`), `'00'` (`0`), `'1'` (`1`), `'3650'` (`3650`), `'3651'` (rejected with `repeatLeadDaysErrorInvalid`), `'-1'` and `'-0'` (rejected), `'+5'` (rejected), `'14.5'` / `'abc'` (rejected), and `25`-digit `'0000000000000000000000001'` (`> maxTdfNumberLength = 24`, rejected before integer parsing).
  - Test calendar horizon overflow protection (`0001-01-03` `due` + `repeat 1 days` + `leadDays = 10` + `subtasks auto-finish` all steps checked at `0001-01-02` UTC) catching `TdfException(kind: TdfErrorKind.invalidTimestamp)` in `EditTaskScreen._submit` without crashing or mutating `TaskBoard`.
* **`M-DELIM-INJECT-TESTS`:**
  - Author multi-line `suspendedNote` and `dueNote` values containing `\n`, `\t`, `"`, `\`, `# inline comment`, `{ block }`, and non-breaking space `\u00A0` in `EditTaskScreen`, persist through `TdfService.serialize` / `TdfService.parse`, and verify exact character-for-character round-trip in both `EditTaskScreen` and `TaskInfoDialog`.
  - Verify ASCII-whitespace-only strings (`"   "`, `"\n\t\r\n  "`) normalize to `null` (omitting `"<note>"` in `.tdf`), whereas `"\u00A0"` is preserved as graphic content (`spec/TDF_SPEC_0.7.0.md` Section 2.8).
  - Verify pasted CRLF/CR text (`"Line 1\r\nLine 2\rLine 3"`) normalizes to `"Line 1\nLine 2\nLine 3"`, while an untouched existing note loaded from `.tdf` containing `\r\n` is preserved verbatim without advancing `task.modified` on a no-op save.
  - Verify forbidden control characters (`"Wait\x00now"`, `"Due\x07bell"`, `"Del\x7Fchar"`) and unpaired UTF-16 surrogates (`"\uD800"`) fail inline with `schedulingNoteErrorInvalid` rather than reaching `TaskBoardMutator` as an uncaught exception.
* **`M-REAL-MECHANICS-TESTS`:**
  - End-to-end Mode 2 lifecycle + Undo (`TEP-007`): create a task in `EditTaskScreen` with `due`, multi-line `dueNote`, one-off `suspended` + `suspendedNote`, `repeat 1 months`, and `leadDays = 7`; complete it via `TaskNotifier.completeTask` and verify `dueAt` advances by `1` month, `suspendedAt` resolves to `targetDueLocalDate - 7 days`, one-off `suspendedNote` is cleared, `dueNote` and `leadDays = 7` remain intact, and `TaskInfoDialog` displays the preserved `dueNote` and `7`-day preparation lead; then invoke `TaskNotifier.undoLastAction` and verify the pre-completion `dueAt`, `suspendedAt`, and one-off `suspendedNote` restore cleanly.
  - Edit a task loaded with a custom `<repeat-time>` (`repeat 2 weeks 08:30 lead 5 days`) in `EditTaskScreen` to change `leadDays` to `10`, and verify `TdfRepeatClock(hour: 8, minute: 30)` is preserved losslessly in `.tdf` output (`repeat 2 weeks 08:30 lead 10 days`).
  - Restore a `Completed` task carrying `repeat 1 months 09:00 lead 5 days` via `TaskNotifier.restoreTask`, open `EditTaskScreen`, toggle `Due` on, and verify `task_editor_repeat_lead_days_input` reveals `'5'`.
  - Live `Directory.watch` + `boundaryTickProvider` mechanics + `Completer` mid-flight persistence: verify an open `TaskInfoDialog` reactively updates `task_info_suspended_note`, `task_info_due_note`, and `taskInfoRepeatLeadDays` when the underlying local `.tdf` file is modified externally on disk (`Directory.watch`), hides `task_info_suspended_note` when `clockProvider` advances to `suspendedAt` and `boundaryTickProvider` ticks, holds mid-flight `EditTaskScreen` save frames cleanly across a suspended repository write `Completer`, and never leaks raw `suspendedNote` or `dueNote` substrings into `AppLogger` entries when `diagnosticsEnabled: true` (`P-SECRET-HYGIENE`).

## Part 3: Implementation Record & Tasks

### 3.1 Task Breakdown
- [x] Run `python3 .agents/scripts/tiertask_dev.py verify --fast` to confirm a clean baseline on top of `TEP-006`, `TEP-008`, and `TEP-010`.
- [x] Add the 10 English (`lib/l10n/app_en.arb`) and German (`lib/l10n/app_de.arb`) localization keys with `@key` metadata and run `flutter gen-l10n`.
- [x] Write failing unit and widget tests first in `test/ui/edit_task_screen_test.dart` and `test/ui/widgets/task_info_dialog_test.dart` covering `M-EXHAUSTIVE-STATE-TESTS`, `M-EXTREME-BOUND-TESTS`, `M-DELIM-INJECT-TESTS`, and `M-REAL-MECHANICS-TESTS` (TDD Red Phase — `P-TDD-FIRST`).
- [x] Implement `TaskEditorSchedulingNoteField`, `_RepeatLeadDaysInput`, `parseRepeatCount`, `parseLeadDays`, `_TaskEditorSuspendedSection`, `_TaskEditorDueSection`, and `_TaskEditorRepeatSection` updates in `lib/ui/widgets/task_editor_scheduling_card.dart` keeping all `build()` methods `< 40` lines (TDD Green Phase).
- [x] Wire `_suspendedNoteController`, `_dueNoteController`, `_repeatLeadDaysController`, untouched-note preservation, `_initialEditorMode` no-op save preservation, `_validateAndBuildDraft`, `TdfException`/`FormatException` persistence boundary handling, controller disposal, and redacted `AppLogger` telemetry in `lib/ui/edit_task_screen.dart`, removing obsolete `_hadActiveInitialSuspension` (TDD Green Phase).
- [x] Implement live `board.findTask(task.id) ?? task` resolution, `_TaskInfoNoteBody` (`SelectableText`), `task_info_suspended_note`, `task_info_due_note`, and `taskInfoRepeatLeadDays` rendering in `lib/ui/widgets/task_info_dialog.dart` (TDD Green & Refactor Phase).
- [x] Update Parts 1 and 2 if implementation details evolve during TDD.
- [x] Follow **`update-documentation`** to update `ARCHITECTURE.md` (`edit_task_screen.dart`, `task_editor_scheduling_card.dart`, `task_info_dialog.dart` within `<= 65` words per row) and run `python3 .agents/scripts/tiertask_dev.py arch --sync-tree`.
- [x] Run `python3 .agents/scripts/tiertask_dev.py verify --full --fix` (`dart format --output=none --set-exit-if-changed lib test`, `flutter analyze --fatal-infos --fatal-warnings`, static `AGENTS.md` / `P-ACYCLIC-DAG` / `audit_l10n` checks, and `flutter test`).
- [x] Follow **`changelog-updater`** to add a concise user-facing `CHANGELOG.md` entry under `## [Unreleased]`.
- [x] Set `status: review`, update `BOARD.md`, and request user approval.
- [ ] After user approval, set `status: completed`, update `BOARD.md`, and record delivered artifacts in Part 3.3.

### 3.2 Work Log & Decisions
* **2026-11-14:** Drafted initial `TEP-011` feature concept proposing `suspendedNote`, `dueNote`, and `repeat ... lead <N> days` authoring in `EditTaskScreen` / `TaskEditorSchedulingCard` and inspection in `TaskInfoDialog` on top of `TEP-006` (`TDF 0.7.0`).
* **2026-11-15:** Elaborated `TEP-011` to `status: planned` against the implemented `TEP-006` and `TEP-010` codebase (`TaskItem.hasActiveSuspendedAt`, `maxTdfNoteLength`, `maxTdfNumberLength`, `TaskRepeatRule.maxRepeatCount`, `TdfCalendar.countUnicodeScalars`, `TdfRepeatClock`, `_TaskEditorDueAutoPrioritizeRow`), added separate `schedulingNoteErrorInvalid` and `parseRepeatCount`/`parseLeadDays` validation, untouched-note `\r` preservation, `TdfException` submit guard, live `board.findTask(task.id) ?? task` lookup in `TaskInfoDialog`, `< 40`-line widget decompositions (`P-FLATTEN-BUILD`), and removal of obsolete `_hadActiveInitialSuspension` (`P-NO-DEAD-CODE`).
* **2026-11-15:** Implemented `TEP-011` end-to-end via Red-Green-Refactor TDD across `lib/l10n/`, `lib/ui/widgets/task_editor_scheduling_card.dart`, `lib/ui/edit_task_screen.dart`, and `lib/ui/widgets/task_info_dialog.dart`. Added `_initialEditorMode` tracking in `EditTaskScreen` so saving an open task without switching its Priority/Someday mode passes `targetTier: null` to `TaskBoardMutator.updateTask`, preserving `task.modifiedAt` on no-op saves of tasks currently evaluated into `Focus`, `Ready`, or `Blocked`. Extracted `_TaskEditorRepeatSection` alongside `_TaskEditorSuspendedSection` and `_TaskEditorDueSection` so `TaskEditorSchedulingCard.build` remains `< 40` lines (`P-FLATTEN-BUILD`). Synchronized `ARCHITECTURE.md` and `CHANGELOG.md`, verified full workspace gates, and advanced `TEP-011` to `status: review`.

### 3.3 Delivered Artifacts
*(Complete upon approval)*
