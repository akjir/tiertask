---
id: TEP-011
title: Deferral and Deadline Notes and Recurring Preparation Lead Editor UI
status: concept
type: feature
created: 2026-11-14
updated: 2026-11-14
---

# TEP-011: Deferral and Deadline Notes and Recurring Preparation Lead Editor UI

## Part 1: Concept & Proposal

### 1.1 Summary
This proposal delivers the interactive editor inputs and task-info inspection views for contextual scheduling notes (`suspendedNote` and `dueNote`) and recurring deadline preparation windows (`repeat ... lead <lead-count> days`) on top of **TierTask Data Format (`TDF`) `0.7.0`** (`spec/TDF_SPEC_0.7.0.md` and `TEP-006` in `tep-006-tdf-spec-0-7-0.md`). While `TEP-006` implements the `TDF 0.7.0` grammar (`suspended (<timestamp> | forever) ["<note>"]`, `due <timestamp> [passive] ["<note>"]`, `repeat <count> <days|weeks|months> [<repeat-time>] [lead <lead-count> days]`), parser/serializer, `TaskItem` and `TaskRepeatRule` domain fields, automatic deferral-expiry cleanup, Mode 2 deadline-anchored recurrence arithmetic (`targetDueLocalDate - leadDays`), three-way reconciliation, undo restoration, and lossless preservation of existing fields during task edits, this proposal extends `TaskEditorSchedulingCard`, `TaskEditorRepeatField`, and `EditTaskScreen` (`lib/ui/widgets/task_editor_scheduling_card.dart`, `lib/ui/edit_task_screen.dart`) with clearable multi-line `suspendedNote` and `dueNote` inputs (`1..3` visible lines, `<= 2000` Unicode scalar values) plus a `Preparation lead (days)` numeric input (`0..3650`, visible when `isRepeating && hasDue`), and renders active `suspendedNote`, `dueNote`, and `leadDays` summaries inside `TaskInfoDialog` (`lib/ui/widgets/task_info_dialog.dart`).

### 1.2 Motivation
`TEP-006` (`spec/TDF_SPEC_0.7.0.md` Sections 4.1.2, 5.4, and 6.2) introduces first-class `.tdf` syntax and lifecycle rules for ephemeral deferral reasons, occurrence/deadline constraints, and recurring preparation windows, and preserves those attributes losslessly when tasks imported from external `.tdf` editors are modified in TierTask. Without dedicated UI controls, however, three practical workflow gaps remain:
1. **No In-App Authoring of Deferral or Deadline Reasons:** Users deferring a task (`Waiting for vendor reply #412`) or setting a deadline (`Hard filing cutoff at 17:00 CET`) currently have to mix transient scheduling notes into the permanent task `note` field inside `TaskEditorDetailsCard`, where expired deferral context lingers after the task unblocks.
2. **No In-App Authoring of Recurring Preparation Windows (`lead <N> days`):** Mode 2 recurrence (`repeat` + `due`) computes `suspended = targetDueLocalDate - leadDays` upon completion so a monthly bill or quarterly filing stays deferred in `Blocked` until its preparation window opens (`leadDays` days before the next deadline). Without a `Preparation lead (days)` input in `TaskEditorRepeatField`, users cannot configure or adjust `TaskRepeatRule.leadDays` (`0..3650`) inside `EditTaskScreen`.
3. **Invisible Scheduling Context in `TaskInfoDialog`:** Tapping `suspended_task_indicator_<id>`, `due_task_badge_<id>`, or `repeat_task_indicator_<id>` on `TierTaskPill` opens `TaskInfoDialog`, which currently displays only the formatted timestamps and repeat interval while omitting `task.suspendedNote`, `task.dueNote`, and `repeatRule.leadDays`.

### 1.3 Goals & Non-Goals
* **Goals:**
  1. Extend `TaskEditorSchedulingCard` (`lib/ui/widgets/task_editor_scheduling_card.dart`) and `EditTaskScreen` (`lib/ui/edit_task_screen.dart`) with clearable multi-line inputs for:
     - `suspendedNote` (`ValueKey('task_editor_suspended_note_input')`, clear button `ValueKey('task_editor_suspended_note_clear_button')`, visible whenever `isSuspended == true`).
     - `dueNote` (`ValueKey('task_editor_due_note_input')`, clear button `ValueKey('task_editor_due_note_clear_button')`, visible whenever `hasDue == true`).
     Both inputs render `1..3` visible lines (`minLines: 1`, `maxLines: 3`), preserve internal `\n` and `\t` characters verbatim, normalize empty or ASCII-whitespace-only (`0x20`, `\t`, `\n`, `\r`) text to `null` (preventing `TdfErrorKind.emptyText`), and enforce `<= 2000` decoded Unicode scalar values (`TaskItem.maxNoteLength`) with inline validation errors.
  2. Extend `TaskEditorRepeatField` (`lib/ui/widgets/task_editor_scheduling_card.dart`) and `EditTaskScreen` with a `Preparation lead (days)` numeric input (`ValueKey('task_editor_repeat_lead_days_input')`, clear button `ValueKey('task_editor_repeat_lead_days_clear_button')`), visible whenever `isRepeating && hasDue`, validating `0..3650` (`TaskRepeatRule.maxLeadDays`), treating blank or `'0'` input as `leadDays = 0` (omitting `lead` in canonical `.tdf` output), resetting `leadDays = 0` when `hasDue` is disabled, and preserving any existing `TaskRepeatRule.clock` (`<repeat-time>`).
  3. Render active `suspendedNote` (`ValueKey('task_info_suspended_note')` as multi-line `SelectableText`), `dueNote` (`ValueKey('task_info_due_note')` as multi-line `SelectableText`), and recurring preparation lead summaries (`taskInfoRepeatLeadDays` when `repeatRule.leadDays > 0 && task.dueAt != null`) inside `TaskInfoDialog` (`lib/ui/widgets/task_info_dialog.dart`).
  4. Provide complete English (`en`) and German (`de`) ARB translations (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`) and `AppLogger` diagnostic metadata with strict note redaction (`P-SECRET-HYGIENE`).
* **Non-Goals:**
  1. Modifying the `TDF 0.7.0` grammar, parser, serializer, automatic block cleanup, Mode 2 recurrence arithmetic, or three-way merge semantics already delivered in `TEP-006` (`spec/TDF_SPEC_0.7.0.md`).
  2. Adding scheduling-note or lead-day inputs to the compact single-line `QuickAddBar` on `HomeScreen` (kept focused on fast title + mode entry).
  3. Exposing an explicit `<repeat-time>` (`HH:MM[:SS]`) clock picker for Mode 1 recurrence in `TaskEditorRepeatField` (existing `TaskRepeatRule.clock` values from `.tdf` files are preserved losslessly on save).

### 1.4 Description

#### 1.4.1 Contextual Deferral & Deadline Note Inputs in `EditTaskScreen`
Inside `TaskEditorSchedulingCard` (`ValueKey('task_editor_scheduling_card')`):
* **Deferral Note (`suspendedNote`):**
  - Displayed directly beneath the `suspended` timestamp field whenever `isSuspended == true`.
  - Uses `ClearableTextField` with `fieldKey: const ValueKey('task_editor_suspended_note_input')`, `clearButtonKey: const ValueKey('task_editor_suspended_note_clear_button')`, `minLines: 1`, `maxLines: 3`, and `keyboardType: TextInputType.multiline`.
  - **Initialization on Edit:** When opening `EditTaskScreen` for an existing task, `_isSuspended` is `true` only if `task.isSuspendedForever || (task.suspendedAt != null && (isCompletedTask || task.suspendedAt.isAfter(nowUtc)))` (matching `TEP-006` Topic 3 so editing an open task whose finite `suspendedAt <= nowUtc` has already elapsed does not resurrect an expired deferral or its stale `suspendedNote`). When `_isSuspended` initializes to `true`, `_suspendedNoteController` initializes to `task.suspendedNote ?? ''`; otherwise it initializes to `''`.
  - **Ownership Cleanup:** If the user toggles `Suspended` off (`_isSuspended = false`) and saves, `clearSuspendedAt: true` clears both `suspendedAt` / `isSuspendedForever` and `suspendedNote` on the persisted `TaskItem` (`spec/TDF_SPEC_0.7.0.md` Section 4.1.2).
* **Deadline Note (`dueNote`):**
  - Displayed directly beneath the `due` timestamp field (and below `task_editor_due_auto_prioritize_switch` when combined with `TEP-010`) whenever `hasDue == true`.
  - Uses `ClearableTextField` with `fieldKey: const ValueKey('task_editor_due_note_input')`, `clearButtonKey: const ValueKey('task_editor_due_note_clear_button')`, `minLines: 1`, `maxLines: 3`, and `keyboardType: TextInputType.multiline`.
  - **Initialization & Lifecycle:** Initializes to `task?.dueNote ?? ''` whenever `task?.dueAt != null` (including overdue open tasks and `Completed` tasks, since `spec/TDF_SPEC_0.7.0.md` retains `due` and `dueNote` across overdue states, Mode 2 recurrence rollovers, and `Completed`). Toggling `Due` off (`_hasDue = false`) and saving passes `clearDueAt: true`, clearing both `dueAt` and `dueNote`.
* **Multi-Line Normalization & Bounds Validation (`<= 2000` Unicode Scalar Values):**
  - `TaskEditorSchedulingNoteField.normalizeSchedulingNote(String rawText)`:
    1. Converts CRLF (`\r\n`) and lone `\r` line endings pasted from external clipboards to canonical LF (`\n`).
    2. Checks whether every code unit in the normalized string is ASCII whitespace (`0x20`, `\t`, `\n`); if empty or whitespace-only, returns `null` so canonical serialization omits `"<note>"` rather than emitting an invalid whitespace-only token (`TdfErrorKind.emptyText`).
    3. Preserves leading, internal, and multi-line `\n` and `\t` formatting verbatim on non-empty notes.
  - `TaskEditorSchedulingNoteField.validateSchedulingNote(String? normalizedNote, AppLocalizations localizations)` verifies `normalizedNote.runes.length <= TaskItem.maxNoteLength` (`2000` decoded Unicode scalar values) and absence of forbidden control characters (`0x00..0x08`, `0x0B..0x1F`, `0x7F`) or lone UTF-16 surrogates, surfacing `localizations.schedulingNoteErrorTooLong` inline on `suspendedNoteErrorMessage` or `dueNoteErrorMessage` when violated.

#### 1.4.2 Recurring Preparation Lead (`lead <N> days`) in `TaskEditorRepeatField`
Inside `TaskEditorRepeatField` (`lib/ui/widgets/task_editor_scheduling_card.dart`):
* **Conditional Visibility:** The `Preparation lead (days)` input (`ValueKey('task_editor_repeat_lead_days_input')`, clear button `ValueKey('task_editor_repeat_lead_days_clear_button')`) is rendered below the `days` / `weeks` / `months` unit chips **only when both `isRepeating == true` and `hasDue == true`**. In Mode 1 recurrence (`isRepeating && !hasDue`), `spec/TDF_SPEC_0.7.0.md` Section 6.2 anchors the next occurrence directly from completion date + interval without a deadline lead window, so hiding the field prevents configuring an inert `lead` clause.
* **Initialization & Reset:**
  - When `task?.repeatRule != null`, `_repeatLeadDaysController` initializes to `task.repeatRule.leadDays > 0 ? task.repeatRule.leadDays.toString() : ''`.
  - If the user disables `Due` (`_hasDue = false`) while keeping `Repeat` enabled (`_isRepeating = true`), saving resolves `leadDays = 0` so `.tdf` output omits `lead <N> days`.
* **Validation (`0..3650`):**
  - Blank input (`''`) or `'0'` resolves to `leadDays = 0` (immediate active recurrence without post-rollover deferral).
  - Integer input in `1..3650` (`TaskRepeatRule.maxLeadDays`) resolves to `leadDays = parsedLeadDays`, serialized as `repeat <count> <unit> [<repeat-time>] lead <leadDays> days`.
  - Non-integer input, negative values, or integers `> 3650` fail form validation on `Save` and display `localizations.repeatLeadDaysErrorInvalid` inline on `repeatLeadDaysErrorMessage`.
  - Existing `TaskRepeatRule.clock` (`widget.initialTask?.repeatRule?.clock ?? TdfRepeatClock.midnight`) is preserved losslessly when constructing the updated `TaskRepeatRule`.

#### 1.4.3 Display in `TaskInfoDialog` Across Linux, Android, and Windows
`TaskInfoDialog` (`lib/ui/widgets/task_info_dialog.dart`) surfaces scheduling notes and preparation lead metadata inside existing indicator cards without adding visual clutter to collapsed `TierTaskPill` rows:
1. **Suspended Section (`task_info_section_suspended_task_indicator`):**
   - Rendered when `task.isSuspendedForever || (task.suspendedAt != null && (task.isCompleted || task.completedAt != null || task.suspendedAt.isAfter(nowUtc)))`.
   - When `task.suspendedNote` is non-null and non-empty, renders a dedicated multi-line `SelectableText` block (`ValueKey('task_info_suspended_note')`) beneath the primary deferral status (`Suspended indefinitely` or `Until <timestamp> (<remaining>)`), preserving `\n` line breaks and supporting text selection/copy across Linux, Android, and Windows.
2. **Due Section (`task_info_section_due_task_badge`):**
   - Rendered whenever `task.dueAt != null` (upcoming, overdue, and `Completed` tasks).
   - When `task.dueNote` is non-null and non-empty, renders a dedicated multi-line `SelectableText` block (`ValueKey('task_info_due_note')`) beneath the formatted local deadline and any auto-priority detail lines.
3. **Repeat Section (`task_info_section_repeat_task_indicator`):**
   - Rendered whenever `task.repeatRule != null`.
   - When `repeatRule.leadDays > 0 && task.dueAt != null`, appends `localizations.taskInfoRepeatLeadDays(repeatRule.leadDays.toString())` (for example, `"Preparation window opens 14 day(s) before due date"` / `"Vorbereitungsfenster öffnet 14 Tag(e) vor Fälligkeit"`) to `_TaskInfoSectionData.details`.

### 1.5 Alternatives
1. **Single-Line Inputs for `suspendedNote` and `dueNote`:** Rejected because `spec/TDF_SPEC_0.7.0.md` Section 4.1.2 defines both `<note>` tokens with the same multi-line escape grammar (`\n`, `\t`, `\"`, `\\`) and `2,000`-scalar bound as task/label/location `note` directives. Restricting the UI to a single line would flatten or corrupt multi-line scheduling notes authored externally.
2. **Show `Preparation lead (days)` Even When `hasDue == false`:** Rejected because `spec/TDF_SPEC_0.7.0.md` Section 6.2 applies `lead <lead-count> days` exclusively to Mode 2 (`repeat` + `due`) rollover (`targetDueLocalDate - leadDays`) and ignores `lead` in Mode 1 (`repeat` without `due`). Hiding the input when `!hasDue` and normalizing `leadDays = 0` on save keeps the UI and serialized `.tdf` strictly aligned with actual runtime behavior.
3. **Add Dedicated Pill Icons for `suspendedNote` and `dueNote` on `TierTaskPill`:** Rejected because `TierTaskPill` caps visible indicators at `maxVisibleTaskIndicators = 3` before collapsing into `summary_task_indicator`, and every task with `suspendedNote` or `dueNote` already displays `suspended_task_indicator_<id>` or `due_task_badge_<id>`. Surfacing the notes inside the corresponding `TaskInfoDialog` cards keeps task pills scannable.

## Part 2: Technical Design & Code Changes

### 2.1 Architecture & Affected Modules

| Layer | File | Change Type | Responsibility |
| :--- | :--- | :--- | :--- |
| Localization (`Rank 2`) | `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb` | Modify | Add English and German localization keys for `suspendedNote`, `dueNote`, note length/character validation errors, `Preparation lead (days)` input/validation, and `TaskInfoDialog` repeat lead summary. |
| UI (`Rank 6`) | `lib/ui/widgets/task_editor_scheduling_card.dart` | Modify | Add `TaskEditorSchedulingNoteField` (`1..3` lines, `normalizeSchedulingNote`, `validateSchedulingNote`), extend `TaskEditorRepeatField` and `parseRepeatRule` with conditional `leadDays` (`0..3650`) support and lossless `clock` preservation, and wire optional controllers/errors into `TaskEditorSchedulingCard`. |
| UI (`Rank 6`) | `lib/ui/edit_task_screen.dart` | Modify | Manage `_suspendedNoteController`, `_dueNoteController`, `_repeatLeadDaysController`, and their error messages in `_EditTaskScreenState`; validate notes and lead days in `_submit`; forward `suspendedNote`, `dueNote`, and `repeatRule` through `_ValidatedTaskDraft` and `_persistTask` to `TaskNotifier.addTask` / `updateTask`. |
| UI (`Rank 6`) | `lib/ui/widgets/task_info_dialog.dart` | Modify | Add optional `noteBody` + `noteKey` on `_TaskInfoSectionData` to render multi-line `SelectableText` for `task_info_suspended_note` and `task_info_due_note`, and append `taskInfoRepeatLeadDays` to `_buildRepeatSection` when `repeatRule.leadDays > 0 && task.dueAt != null`. |
| Tests | `test/ui/edit_task_screen_test.dart`, `test/ui/widgets/task_info_dialog_test.dart` | Modify | Red-Green-Refactor unit and widget tests covering multi-line note normalization, `2000`-scalar bounds, `0..3650` lead-day bounds, conditional visibility, Mode 1/Mode 2 transitions, `clock` preservation, and `TaskInfoDialog` rendering. |

### 2.2 TDF Schema, Localization & State Changes

#### 2.2.1 TDF `0.7.0` Schema Reliance (`TEP-006`)
No schema or parser changes beyond `TEP-006` (`spec/TDF_SPEC_0.7.0.md` Sections 4.1.2, 5.4, 6.2, and 8.1) are required:
* `TaskItem` (`lib/models/task_item.dart`) exposes `final String? suspendedNote;`, `final String? dueNote;`, and `static const int maxNoteLength = 2000;`.
* `TaskRepeatRule` (`lib/models/task_item.dart`) exposes `final int leadDays;` (`0` default), `final TdfRepeatClock clock;`, and `static const int maxLeadDays = 3650;`.
* `TaskNotifier.addTask` and `TaskNotifier.updateTask` (`lib/providers/task_providers.dart`, delivered in `TEP-006`) accept `String? suspendedNote`, `bool clearSuspendedNote = false`, `String? dueNote`, `bool clearDueNote = false`, and `TaskRepeatRule? repeatRule`, enforcing ownership invariants (`!isSuspended -> suspendedNote == null`, `!hasDue -> dueNote == null`).

#### 2.2.2 Localization Keys (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`)

| Key | English (`app_en.arb`) | German (`app_de.arb`) |
| :--- | :--- | :--- |
| `taskSuspendedNoteLabel` | `"Deferral note (optional)"` | `"Zurückstellungsnotiz (optional)"` |
| `taskSuspendedNoteHint` | `"Why is this task deferred?"` | `"Warum ist diese Aufgabe zurückgestellt?"` |
| `taskDueNoteLabel` | `"Deadline note (optional)"` | `"Fälligkeitsnotiz (optional)"` |
| `taskDueNoteHint` | `"Cutoff details or submission requirements"` | `"Fristdetails oder Abgabebedingungen"` |
| `schedulingNoteErrorTooLong` | `"Note must not exceed 2,000 characters."` | `"Notiz darf maximal 2.000 Zeichen lang sein."` |
| `repeatLeadDaysLabel` | `"Preparation lead (days, optional)"` | `"Vorbereitungszeit (Tage, optional)"` |
| `repeatLeadDaysHint` | `"0 (activate immediately after rollover)"` | `"0 (sofort nach Wiederholung aktivieren)"` |
| `repeatLeadDaysErrorInvalid` | `"Enter a whole number between 0 and 3650 days."` | `"Ganze Zahl zwischen 0 und 3650 Tagen eingeben."` |
| `taskInfoRepeatLeadDays` | `"Preparation window opens {days} day(s) before due date"` (`placeholders: {"days": {"type": "String"}}`) | `"Vorbereitungsfenster öffnet {days} Tag(e) vor Fälligkeit"` |

### 2.3 Implementation Details

#### 2.3.1 `TaskEditorSchedulingNoteField` & `TaskEditorRepeatField` (`lib/ui/widgets/task_editor_scheduling_card.dart`)
* Introduce `TaskEditorSchedulingNoteField` (`StatelessWidget` keeping `build()` `< 40` lines per `P-FLATTEN-BUILD`):
  ```dart
  class TaskEditorSchedulingNoteField extends StatelessWidget {
    const TaskEditorSchedulingNoteField({
      super.key,
      required this.clearButtonKey,
      required this.controller,
      this.errorMessage,
      required this.fieldKey,
      required this.hintText,
      required this.labelText,
    });
    // ...
    static String? normalizeSchedulingNote(String rawText);
    static String? validateSchedulingNote(
      String? normalizedNote,
      AppLocalizations localizations,
    );
  }
  ```
  - `normalizeSchedulingNote` performs a single $O(N)$ pass (`P-ZERO-COPY`, `P-NO-QUADRATIC`) over `rawText` code units: if all code units are in `{0x09, 0x0A, 0x0D, 0x20}`, returns `null`; if `\r` (`0x0D`) is absent, returns `rawText` directly without allocating a copy; otherwise writes LF-normalized text via `StringBuffer` and re-checks for non-whitespace content.
  - `validateSchedulingNote` returns `null` when `normalizedNote == null`; otherwise iterates `normalizedNote.runes` once (`P-BOUND-ALLOC`), counting Unicode scalar values and rejecting `count > TaskItem.maxNoteLength` (`2000`), lone UTF-16 surrogates (`0xD800..0xDFFF`), or forbidden control characters (`codePoint < 0x20 && codePoint != 0x09 && codePoint != 0x0A`, or `codePoint == 0x7F`) with `localizations.schedulingNoteErrorTooLong`.
* Extend `TaskEditorRepeatField`:
  - Add optional parameters:
    - `final bool showLeadDays;` (set to `hasDue` by `TaskEditorSchedulingCard`)
    - `final TextEditingController? leadDaysController;`
    - `final String? leadDaysErrorMessage;`
  - Extract `_RepeatLeadDaysInput` (`StatelessWidget`) rendering `ClearableTextField` (`fieldKey: const ValueKey('task_editor_repeat_lead_days_input')`, `clearButtonKey: const ValueKey('task_editor_repeat_lead_days_clear_button')`, `keyboardType: TextInputType.number`) when `showLeadDays && leadDaysController != null` so `TaskEditorRepeatField.build` stays `< 40` lines (`P-FLATTEN-BUILD`).
  - Add static parsing helpers:
    ```dart
    static int? parseLeadDays({
      required bool hasDue,
      required bool isRepeating,
      required String rawLeadDays,
    });

    static TaskRepeatRule? parseRepeatRule({
      TdfRepeatClock existingClock = TdfRepeatClock.midnight,
      bool hasDue = false,
      required bool isRepeating,
      String rawLeadDays = '',
      required String rawCount,
      required RepeatUnit unit,
    });
    ```
    When `!isRepeating`, `parseLeadDays` returns `0` and `parseRepeatRule` returns `null`. When `isRepeating && !hasDue`, `parseLeadDays` returns `0` regardless of `rawLeadDays`. When `isRepeating && hasDue`, trimmed `rawLeadDays.isEmpty` returns `0`, integer `0..TaskRepeatRule.maxLeadDays` (`3650`) returns that integer, and any other string returns `null` (causing `_submit` to surface `localizations.repeatLeadDaysErrorInvalid`).

#### 2.3.2 `EditTaskScreen` Integration & Resource Lifecycle (`lib/ui/edit_task_screen.dart`)
* Add controllers and error fields in `_EditTaskScreenState`:
  - `late final TextEditingController _dueNoteController;`
  - `String? _dueNoteErrorMessage;`
  - `late final TextEditingController _repeatLeadDaysController;`
  - `String? _repeatLeadDaysErrorMessage;`
  - `late final TextEditingController _suspendedNoteController;`
  - `String? _suspendedNoteErrorMessage;`
* **Initialization (`initState`) & Disposal (`dispose`):**
  - Determine active suspension state using `nowUtc = TaskItem.normalizeTimestamp(ref.read(clockProvider)().toUtc())`:
    `final hasActiveSuspension = task != null && (task.isSuspendedForever || (task.suspendedAt != null && (_isCompletedTask || task.suspendedAt.isAfter(nowUtc))));`
  - Initialize `_isSuspended = hasActiveSuspension`, `_suspendedNoteController = TextEditingController(text: hasActiveSuspension ? (task.suspendedNote ?? '') : '')..addListener(_handleSuspendedNoteChanged)`, `_dueNoteController = TextEditingController(text: task?.dueNote ?? '')..addListener(_handleDueNoteChanged)`, and `final initialLeadDays = task?.repeatRule?.leadDays ?? 0; _repeatLeadDaysController = TextEditingController(text: initialLeadDays > 0 ? initialLeadDays.toString() : '')..addListener(_handleRepeatLeadDaysChanged)` (`P-NULL-SAFE`).
  - Dispose `_suspendedNoteController`, `_dueNoteController`, and `_repeatLeadDaysController` in `dispose()` (`P-DISPOSE-RESOURCES`).
* **Validation & Persistence (`_submit`, `_buildDraft`, `_persistTask`):**
  - When `_isSuspended`, normalize and validate `_suspendedNoteController.text`; otherwise `normalizedSuspendedNote = null`.
  - When `_hasDue`, normalize and validate `_dueNoteController.text`; otherwise `normalizedDueNote = null`.
  - Validate `leadDays = TaskEditorRepeatField.parseLeadDays(hasDue: _hasDue, isRepeating: _isRepeating, rawLeadDays: _repeatLeadDaysController.text)` and pass `existingClock: widget.initialTask?.repeatRule?.clock ?? TdfRepeatClock.midnight` to `TaskEditorRepeatField.parseRepeatRule(...)`.
  - Extend `_ValidatedTaskDraft` with `String? dueNote` and `String? suspendedNote`, forwarding `dueNote: draft.dueNote`, `clearDueNote: !_hasDue || draft.dueNote == null`, `suspendedNote: draft.suspendedNote`, and `clearSuspendedNote: !_isSuspended || draft.suspendedNote == null` to `notifier.updateTask(...)`, and `dueNote: draft.dueNote`, `suspendedNote: draft.suspendedNote` to `notifier.addTask(...)`.
* **Diagnostic Privacy (`AppLogger`, `P-SECRET-HYGIENE`):**
  - Log boolean presence flags (`has_suspended_note`, `has_due_note`, `lead_days`) on task save events; **never** log raw `suspendedNote` or `dueNote` text.

#### 2.3.3 `TaskInfoDialog` Section Rendering (`lib/ui/widgets/task_info_dialog.dart`)
* Extend `_TaskInfoSectionData` with:
  - `final String? noteBody;`
  - `final Key? noteKey;`
* In `_TaskInfoSectionCard.build`, when `if (data.noteBody case final note? when note.isNotEmpty)`, render a padded `SelectableText(note, key: data.noteKey, style: Theme.of(context).textTheme.bodySmall)` block beneath the header/details so multi-line deferral and deadline notes can be selected and copied cleanly without overflowing narrow mobile viewports.
* In `TaskInfoDialog._buildSuspendedSection`:
  - Return `null` when `!task.isSuspendedForever && (suspendedAt == null || (!isCompleted && !suspendedAt.isAfter(nowUtc)))` (`TEP-006` Topic 3).
  - Pass `noteBody: task.suspendedNote` and `noteKey: const ValueKey('task_info_suspended_note')`.
* In `TaskInfoDialog._buildDueSection`:
  - Pass `noteBody: task.dueNote` and `noteKey: const ValueKey('task_info_due_note')`.
* In `TaskInfoDialog._buildRepeatSection`:
  - Include `if (repeatRule.leadDays > 0 && task.dueAt != null) localizations.taskInfoRepeatLeadDays(repeatRule.leadDays.toString())` in `details`.

### 2.4 Testing Strategy
All features follow strict Red-Green-Refactor TDD (`P-TDD-FIRST`) using the isolated `pumpLeafWidget` (`FakeTaskNotifier`) harness in `test/ui/test_helpers.dart`:
* **`M-EXHAUSTIVE-STATE-TESTS`:**
  - Verify `task_editor_suspended_note_input` appears if and only if `isSuspended` is active, and `task_editor_due_note_input` appears if and only if `hasDue` is active.
  - Verify `task_editor_repeat_lead_days_input` appears only when `isRepeating && hasDue`, hides immediately when either `Due` or `Repeat` is toggled off, and resets `leadDays` to `0` if `Due` is disabled before saving.
  - Verify `TaskInfoDialog` renders `task_info_suspended_note` for `suspended forever` and future `suspended <timestamp>` tasks, hides the entire suspended card when finite `suspendedAt <= nowUtc` on an open task, renders `task_info_due_note` on upcoming, overdue, and `Completed` tasks, and renders `taskInfoRepeatLeadDays` in both English (`en`) and German (`de`) locales when `leadDays > 0 && dueAt != null` (omitting it in Mode 1 when `dueAt == null` or when `leadDays == 0`).
* **`M-EXTREME-BOUND-TESTS`:**
  - Test `suspendedNote` and `dueNote` scalar-count boundaries: `0` chars (`null`), `1` char, `2000` ASCII chars (accepted), `2000` astral-plane Unicode scalar values such as `U+1F4CB` (`4000` UTF-16 code units, accepted because `runes.length == 2000`), and `2001` Unicode scalar values (rejected with `schedulingNoteErrorTooLong` without closing `EditTaskScreen`).
  - Test `Preparation lead (days)` boundaries: `''` (`0`), `'0'` (`0`), `'1'` (`1`), `'3650'` (`3650`), `'3651'` (rejected with `repeatLeadDaysErrorInvalid`), `'-1'` (rejected), and `'14.5'` / `'abc'` (rejected).
* **`M-DELIM-INJECT-TESTS`:**
  - Enter multi-line `suspendedNote` and `dueNote` payloads containing `\n`, `\t`, `"`, `\`, `# comment`, and `{ block }` delimiters in `EditTaskScreen`, save to `.tdf`, reload, and verify exact byte-preserving round-trip in both `EditTaskScreen` and `TaskInfoDialog`.
  - Enter whitespace-only strings (`"   "`, `"\n\t\r\n  "`) into `task_editor_suspended_note_input` and `task_editor_due_note_input` and verify both normalize to `null` (omitting trailing `"<note>"` tokens in `.tdf`).
  - Verify CRLF (`"Line 1\r\nLine 2"`) pasted into either note field normalizes cleanly to `"Line 1\nLine 2"`.
* **`M-REAL-MECHANICS-TESTS`:**
  - Create a task in `EditTaskScreen` with `due`, `dueNote`, `repeat 1 months`, and `leadDays = 7`, complete the task via `TaskNotifier.completeTask`, and verify end-to-end that the rolled-over task advances `dueAt` by 1 month, sets `suspendedAt` to `targetDueLocalDate - 7 days`, clears any prior `suspendedNote`, preserves `dueNote` and `leadDays = 7`, and displays the updated deadline note and preparation window in `TaskInfoDialog`.
  - Edit a task loaded with a custom Mode 1 `repeat 1 days 08:30` rule (`TdfRepeatClock(hour: 8, minute: 30, second: 0)`) in `EditTaskScreen` and verify saving preserves `08:30` losslessly.

## Part 3: Implementation Record & Tasks

### 3.1 Task Breakdown
- [ ] Run `flutter analyze --fatal-infos --fatal-warnings` and `flutter test` to confirm a clean baseline on top of `TEP-006`.
- [ ] Add English (`lib/l10n/app_en.arb`) and German (`lib/l10n/app_de.arb`) localization keys and run `flutter gen-l10n`.
- [ ] Write failing unit and widget tests first in `test/ui/edit_task_screen_test.dart` and `test/ui/widgets/task_info_dialog_test.dart` covering multi-line note bounds, whitespace normalization, `0..3650` lead-day validation, Mode 2 completion rollover, and `TaskInfoDialog` rendering (TDD Red Phase — `P-TDD-FIRST`).
- [ ] Implement `TaskEditorSchedulingNoteField` and `TaskEditorRepeatField` lead-day support in `lib/ui/widgets/task_editor_scheduling_card.dart` (TDD Green Phase).
- [ ] Wire `_suspendedNoteController`, `_dueNoteController`, and `_repeatLeadDaysController` in `lib/ui/edit_task_screen.dart` with controller disposal and redacted `AppLogger` telemetry (TDD Green Phase).
- [ ] Render `task_info_suspended_note`, `task_info_due_note`, and `taskInfoRepeatLeadDays` in `lib/ui/widgets/task_info_dialog.dart` (TDD Green & Refactor Phase).
- [ ] Update Parts 1 and 2 if implementation details evolve during TDD.
- [ ] Run `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze --fatal-infos --fatal-warnings`, and `flutter test`.
- [ ] Follow **`update-documentation`** to synchronize `README.md`, `ARCHITECTURE.md`, and `AGENTS.md` as applicable.
- [ ] Follow **`changelog-updater`** to add a `CHANGELOG.md` entry under `## [Unreleased]`.
- [ ] Set `status: review`, update `BOARD.md`, and request user approval.
- [ ] After user approval, set `status: completed`, update `BOARD.md`, and list delivered artifacts in Part 3.3.

### 3.2 Work Log & Decisions
* **2026-11-14:** Drafted initial `TEP-011` feature concept and technical design specifying `suspendedNote`, `dueNote`, and `repeat ... lead <N> days` authoring in `EditTaskScreen` / `TaskEditorSchedulingCard` and inspection in `TaskInfoDialog` on top of `TEP-006` (`TDF 0.7.0`).

### 3.3 Delivered Artifacts
*(Complete upon approval)*
