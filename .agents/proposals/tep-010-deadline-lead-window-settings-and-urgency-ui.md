---
id: TEP-010
title: Configurable Deadline Lead-Window Preferences, Live Boundary Timer, and Urgency Indicators
status: concept
type: feature
created: 2026-11-14
updated: 2026-11-14
---

# TEP-010: Configurable Deadline Lead-Window Preferences, Live Boundary Timer, and Urgency Indicators

## Part 1: Concept & Proposal

### 1.1 Summary
This proposal specifies the workspace preference persistence, task editor auto-priority toggle, live wall-clock boundary scheduler, and visual urgency indicators for deadline-driven effective priority on top of **TierTask Data Format (`TDF`) `0.7.0`** (`spec/TDF_SPEC_0.7.0.md` and `TEP-006` in `tep-006-tdf-spec-0-7-0.md`). While `TEP-006` implements the `due <YYYY-MM-DD> [<HH:MM[:SS]>] [passive] ["<note>"]` specification, parser/serializer, 24-hour normative default `due` lead-window evaluation (`TaskBoardEvaluator.defaultDueLeadWindow`), context-relative `downgradeTask` semantics (`Section 6.3`), three-way `(dueAt, isDuePassive, dueNote)` reconciliation, undo restoration, and lossless `isDuePassive` editor preservation, this proposal introduces the per-workspace `DueLeadWindow` preference (`off`, `atDue` = `0h`, `hours12` = `12h`, `hours24` = `24h` default, `hours48` = `48h`, `days7` = `168h`) persisted in `TTW\x02` workspace records (with `TTW\x01` backward compatibility), wires `DueLeadWindow` through `WebDavConfigNotifier`, `TaskNotifier`, and `SettingsScreen`, adds the deterministic `Auto-prioritize near deadline` (`!isDuePassive`) switch in `EditTaskScreen` / `TaskEditorSchedulingCard`, schedules a single live boundary `Timer` in `HomeScreen` across `suspendedAt`, `dueAt - W_due`, and exact `dueAt`, and renders lead-window warning and overdue (`colorScheme.error`) urgency indicators on `TierTaskPill` and `TaskInfoDialog`.

### 1.2 Motivation
`TEP-006` (`spec/TDF_SPEC_0.7.0.md` Sections 4.1.2, 5.5, and 6.3) establishes read-only effective priority when an open queued task's non-`passive` `due` timestamp enters `due <= now + W_due` (normatively defaulting to `24 hours`). To make deadline promotion controllable, predictable, and responsive in daily use across desktop and mobile workspaces, four application-layer capabilities are required:
1. **Workspace-Specific Lead Horizons:** A personal errands workspace often needs a `12h` or `24h` lead window, whereas a long-horizon engineering or tax workspace benefits from a `48h` or `7d` lead window (or `Off` / `At deadline (0h)` for strictly manual prioritization). Hardcoding `24h` across all workspaces prevents tailoring pull sensitivity per workspace.
2. **Explicit Editor Control Over `passive` Deadlines:** When creating an informational cutoff date or editing the deadline of a previously downgraded task (`due ... passive`), users need an explicit `Auto-prioritize near deadline` toggle in `EditTaskScreen` that automatically re-arms auto-promotion when `dueAt` changes to a new timestamp unless manually overridden.
3. **Live Threshold Transitions While Open:** Desktop (`Linux`, `Windows`) and foreground mobile (`Android`) sessions remain open across hours. In the current `HomeScreen` implementation (`_LandingContentSwitcher._evaluateBoard`), unfiltered global boards (`activeLabel == null && !hasCoordinates`) return `board` without re-evaluating against `clockProvider`, and no wall-clock timer wakes the UI when `suspendedAt`, `dueAt - W_due`, or exact `dueAt` is crossed.
4. **Immediate Visual Distinction Between Future, Urgent, and Overdue Deadlines:** `TierTaskPill` (`_TierTaskIndicators._buildDueBadge`) currently renders all `due_task_badge_<id>` labels in a single muted gray color regardless of whether the deadline is weeks away, inside the active lead window, or overdue.

### 1.3 Goals & Non-Goals
* **Goals:**
  1. Introduce `DueLeadWindow` (`off`, `atDue` = `0h`, `hours12` = `12h`, `hours24` = `24h` default, `hours48` = `48h`, `days7` = `168h`) on `WebDavConfig` (`lib/models/webdav_config.dart`) and persist it per workspace in `AppWorkspace` (`lib/models/app_workspace.dart`) using a `TTW\x02` binary envelope (`1` trailing byte per workspace record) while decoding legacy `TTW\x01` payloads seamlessly with `DueLeadWindow.hours24`.
  2. Wire `configuration.dueLeadWindow.duration` through `WebDavConfigNotifier` (`lib/providers/config_providers.dart`), `TaskSyncPipeline` (`lib/providers/sync_providers.dart`), `TaskNotifier` (`lib/providers/task_providers.dart` across `build`, `downgradeTask`, `scheduleTask`, `blockTask`, `moveTaskInQueue`, `restoreTask`, `undoLastAction`, and task/entity mutations), and `SettingsScreen` (`lib/ui/settings_screen.dart`, `lib/ui/widgets/settings_preference_cards.dart`).
  3. Add the `Auto-prioritize near deadline` (`!isDuePassive`) toggle to `TaskEditorSchedulingCard` and `EditTaskScreen`, implementing deterministic `_didUserToggleAutoPrioritizeDue` reset to `true` (`isDuePassive = false`) whenever `dueAt` changes to a different timestamp without manual switch interaction.
  4. Implement single-timer wall-clock boundary scheduling in `HomeScreen` (`lib/ui/home_screen.dart`) across open tasks' finite `suspendedAt > now`, lead-window entry `dueAt - W_due > now`, and exact `dueAt > now`, with `AppLifecycleState` background cancellation, `resumed` catch-up re-evaluation, and a `>= 25 ms` sub-second early-wakeup guard matching `TaskItem.normalizeTimestamp` second truncation.
  5. Render lead-window warning (`AppTheme.warningAccent`) and overdue (`due <= now`, `colorScheme.error`) urgency colors on `TierTaskPill` (`due_task_badge_<id>`) for open tasks and display active auto-priority / `passive` status details inside `TaskInfoDialog`.
* **Non-Goals:**
  1. Persisting `DueLeadWindow` inside the `.tdf` file (`spec/TDF_SPEC_0.7.0.md` keeps `W_due` as an evaluation parameter with normative `86,400`-second default so viewing or changing lead-window preferences never mutates `.tdf` storage or triggers WebDAV uploads).
  2. Delivering OS background push notifications or alarm manager wakeups while the application process is suspended or terminated.
  3. Sorting `Focus` or `Ready` by ascending `due` timestamp instead of `spec/TDF_SPEC_0.7.0.md` Section 5.5's stable two-bucket `queue` partition.

### 1.4 Description

#### 1.4.1 Per-Workspace `DueLeadWindow` Preference & `TTW\x02` Persistence
Each isolated workspace (`AppWorkspace`) stores its own `DueLeadWindow` option inside `WebDavConfig`:
* **`DueLeadWindow.off` (`id: 0`, `duration: null`):** Deadlines remain informational and never grant derived effective priority (`isDueUrgent` is always `false`). Overdue badges (`due <= now`) still highlight in `colorScheme.error`.
* **`DueLeadWindow.atDue` (`id: 1`, `duration: Duration.zero`):** Tasks gain effective priority at exact deadline arrival (`due <= now`, `0h` lead).
* **`DueLeadWindow.hours12` (`id: 2`, `duration: Duration(hours: 12)`):** Tasks gain effective priority `12 hours` (`43,200` seconds) before `due`.
* **`DueLeadWindow.hours24` (`id: 3`, `duration: Duration(hours: 24)`, Default):** Tasks gain effective priority `24 hours` (`86,400` seconds) before `due`, matching `DEFAULT_DUE_LEAD_SECONDS` in `spec/TDF_SPEC_0.7.0.md` Section 5.5.
* **`DueLeadWindow.hours48` (`id: 4`, `duration: Duration(hours: 48)`):** Tasks gain effective priority `48 hours` (`172,800` seconds) before `due`.
* **`DueLeadWindow.days7` (`id: 5`, `duration: Duration(days: 7)`):** Tasks gain effective priority `7 days` (`168 hours` / `604,800` seconds) before `due`.

In `SettingsScreen` (`SettingsPreferenceCards`), a new `DueLeadWindowSelectionCard` presents a `DropdownButtonFormField<DueLeadWindow>` (`ValueKey('settings_due_lead_window_dropdown')`). Selecting a new option persists immediately to `SettingsRepository` (`TTW\x02`) and re-evaluates the in-memory `TaskBoard` tiers without modifying `.tdf` files on disk or WebDAV.

#### 1.4.2 Deterministic `Auto-prioritize near deadline` Toggle in `EditTaskScreen`
Whenever `Due` is enabled (`_hasDue == true`) in `EditTaskScreen` (`TaskEditorSchedulingCard`), an inline toggle row (`ValueKey('task_editor_due_auto_prioritize_switch')`) is displayed below the `due` timestamp input:
* **Initial State:** `_initialDueAt = widget.initialTask?.dueAt`, `_initialDueText = _dueController.text.trim()`, `_autoPrioritizeDue = !(widget.initialTask?.isDuePassive ?? false)`, and `_didUserToggleAutoPrioritizeDue = false`.
* **Manual Override:** Toggling `task_editor_due_auto_prioritize_switch` flips `_autoPrioritizeDue` and sets `_didUserToggleAutoPrioritizeDue = true`.
* **Automatic Reset on Deadline Change:** Whenever the user edits `_dueController` (via text input, clear button, date picker, or time picker) such that the resolved `dueAt` differs from `_initialDueAt` while `!_didUserToggleAutoPrioritizeDue`, `_autoPrioritizeDue` automatically resets to `true` (`isDuePassive = false`). Thus, rescheduling a previously downgraded task (`due ... passive`) to a new future deadline restores auto-promotion by default without requiring the user to remember a hidden passive flag, while still allowing the user to explicitly turn `Auto-prioritize near deadline` off for the new date.
* **Clearing `Due`:** Toggling `_hasDue` off (`_hasDue = false`) resets `_autoPrioritizeDue = true` and `_didUserToggleAutoPrioritizeDue = false` (and `clearDueAt: true` clears `isDuePassive` on the persisted `TaskItem`).

#### 1.4.3 Live Boundary `Timer` & Lifecycle Handling in `HomeScreen`
`HomeScreen` (`lib/ui/home_screen.dart`) ensures that tier placements and deadline urgency badges stay accurate in real time without polling:
1. **Unconditional Context Evaluation:** `_LandingContentSwitcher._evaluateBoard` always calls `board.evaluateForContext(...)` with `evaluationTime` (`clockProvider().toUtc()`), `localEvaluationTime`, and `dueLeadWindow: configuration.dueLeadWindow.duration`, including in the unfiltered global view (`activeLabel == null && !hasCoordinates`).
2. **Single Earliest-Boundary `Timer`:** `_HomeScreenState` computes the earliest strictly future UTC threshold `targetBoundary > now` (`now = TaskItem.normalizeTimestamp(rawUtcNow)`) across all open tasks (`!isCompleted && completedAt == null`):
   - Finite deferral expiry: `suspendedAt > now` (`!isSuspendedForever && suspendedAt != TaskItem.defaultSuspendedAt`).
   - Lead-window entry: `dueAt.subtract(W_due) > now` when `W_due != null && !isDuePassive`.
   - Exact deadline overdue transition: `dueAt > now` (evaluated for every open task with `dueAt != null`, even if already inside `W_due`, marked `passive`, or under `DueLeadWindow.off`, so `due_task_badge_<id>` transitions live to `colorScheme.error` at `dueAt`).
   At most one `Timer` is active at any time; if no open task has a future threshold, zero timers run.
3. **Sub-Second Early-Wakeup Guard (`>= 25 ms`):** Because `TaskItem.normalizeTimestamp` truncates sub-second milliseconds/microseconds (for example, `16:59:59.994Z -> 16:59:59Z`), an OS timer scheduled via `targetBoundary.difference(rawUtcNow)` can fire a few milliseconds before the truncated UTC second ticks over. When `_onBoundaryTimerFired` observes `TaskItem.normalizeTimestamp(rawUtcNow).isBefore(targetBoundary)`, it re-arms `_boundaryTimer` for `max(targetBoundary.difference(rawUtcNow), const Duration(milliseconds: 25))` instead of rebuilding early or spinning.
4. **Lifecycle Conservation (`AppLifecycleState`):** `_HomeScreenState` cancels `_boundaryTimer` in `dispose()` and whenever `AppLifecycleState` leaves `resumed` (`inactive`, `hidden`, `paused`, `detached`). Upon `AppLifecycleState.resumed`, `_HomeScreenState` immediately increments its evaluation tick to catch up on any thresholds crossed while backgrounded and schedules the next upcoming boundary.

#### 1.4.4 Urgency Badges on `TierTaskPill` & `TaskInfoDialog`
* **`TierTaskPill` (`due_task_badge_<id>`):**
  - On **open** tasks (`!task.isCompleted && task.completedAt == null`):
    - **Overdue (`!dueAt.isAfter(nowUtc)`, i.e. `dueAt <= nowUtc`):** Styled in `Theme.of(context).colorScheme.error` (applies to both active and `passive` deadlines).
    - **Urgent Lead Window (`dueAt.isAfter(nowUtc)` and `task.isWithinDueLeadWindow(nowUtc, dueLeadWindow)`):** Styled in `AppTheme.of(context).warningAccent`.
    - **Future Outside Lead Window (or `isDuePassive` before `dueAt`):** Styled in the standard muted indicator color (`colorScheme.onSurfaceVariant.withValues(alpha: 0.55)`).
  - On **`Completed`** tasks: Always styled in the muted indicator color so historical deadlines do not appear as active errors.
* **`TaskInfoDialog` (`_buildDueSection`):** Displays a concise secondary detail line below the formatted local due timestamp indicating whether the task is currently prioritized by the lead window, scheduled to auto-prioritize `{window}` before the deadline, marked `passive` (`Informational deadline`), or operating with workspace lead-window auto-priority turned `Off`.

### 1.5 Alternatives
1. **Periodic `1`-Second Polling `Timer.periodic` in `HomeScreen`:** Rejected because waking the UI isolate every second across idle desktop and mobile sessions wastes CPU/battery and triggers 86,400 checks per day when zero boundaries are crossed. Scheduling a single one-shot `Timer` for the exact next UTC threshold performs $O(1)$ wakeups per actual task transition.
2. **Pack `DueLeadWindow` into Remaining Bits of `flags` or `tzWord` in `TTW\x01`:** Rejected because all 8 bits of `flags` and all 16 bits of `tzWord` in `AppWorkspace` (`lib/models/app_workspace.dart` lines 230–265) are already allocated (`storageMode`, `language`, `themeMode`, `localWatchEnabled`, `themePalette`, `remoteLogFlag`, `timeZoneMode`, `locationEnabled`, `diagnosticsEnabled`, `logLevel`, and 11-bit `offsetField`). Bumping the envelope header from `TTW\x01` to `TTW\x02` and appending `1` clean enum byte per workspace record keeps bit-packing readable while preserving lossless `TTW\x01` decoding.
3. **Keep `Auto-prioritize near deadline` Disabled After Editing `dueAt` on a Downgraded Task:** Rejected because `downgradeTask` (`Section 6.3`) sets occurrence-scoped `passive` solely to prevent bounce-back on the current deadline; if a user later postpones `dueAt` to next month, silently retaining `passive` would suppress lead-window promotion on the new deadline unexpectedly.

## Part 2: Technical Design & Code Changes

### 2.1 Architecture & Affected Modules

| Layer | File | Change Type | Responsibility |
| :--- | :--- | :--- | :--- |
| Models (`Rank 1`) | `lib/models/webdav_config.dart` | Modify | Add `DueLeadWindow` enum (`off`, `atDue`, `hours12`, `hours24`, `hours48`, `days7`) with `id` and `Duration? duration`, and add `dueLeadWindow` field (`DueLeadWindow.hours24` default) to `WebDavConfig`. |
| Models (`Rank 1`) | `lib/models/app_workspace.dart` | Modify | Bump binary format to `TTW\x02` appending `1` `dueLeadWindow` byte (`0..5`) per workspace record while decoding legacy `TTW\x01` records with `DueLeadWindow.hours24`. |
| Localization (`Rank 2`) | `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb` | Modify | Add English and German localization keys for `DueLeadWindow` settings card/options, `EditTaskScreen` auto-prioritize switch, and `TaskInfoDialog` auto-priority status lines. |
| Providers (`Rank 5`) | `lib/providers/config_providers.dart`, `lib/providers/sync_providers.dart`, `lib/providers/task_providers.dart` | Modify | Add `updateDueLeadWindow` on `WebDavConfigNotifier` (re-evaluating loaded board in memory without `.tdf` I/O) and forward `config.dueLeadWindow.duration` across `TaskSyncPipeline._parseTdf` and `TaskNotifier` mutations (`downgradeTask`, `scheduleTask`, `blockTask`, `moveTaskInQueue`, `restoreTask`, `addTask`, `updateTask`, `completeTask`, `deleteTask`, `deleteLocation`, `toggleSubtask`, `undoLastAction`). |
| UI (`Rank 6`) | `lib/ui/settings_screen.dart`, `lib/ui/widgets/settings_preference_cards.dart` | Modify | Add `DueLeadWindowSelectionCard` (`settings_due_lead_window_dropdown`) and wire `_handlePreferenceChanged` to `updateDueLeadWindow`. |
| UI (`Rank 6`) | `lib/ui/edit_task_screen.dart`, `lib/ui/widgets/task_editor_scheduling_card.dart` | Modify | Add `task_editor_due_auto_prioritize_switch` when `hasDue` is active and implement deterministic `_didUserToggleAutoPrioritizeDue` reset when `dueAt` changes. |
| UI (`Rank 6`) | `lib/ui/home_screen.dart` | Modify | Always evaluate `evaluateForContext` with `dueLeadWindow` in `_LandingContentSwitcher._evaluateBoard`; schedule single live boundary `Timer` in `_HomeScreenState` with `AppLifecycleListener` pause/resume and `>= 25 ms` sub-second guard. |
| UI (`Rank 6`) | `lib/ui/widgets/tier_task_pill.dart`, `lib/ui/widgets/task_info_dialog.dart` | Modify | Style `due_task_badge_<id>` with `warningAccent` (in lead window) and `colorScheme.error` (`due <= now`) on open tasks, and render deadline auto-priority status details in `TaskInfoDialog._buildDueSection`. |
| Tests | `test/models/app_workspace_test.dart`, `test/models/tdf_v050_primitives_test.dart`, `test/providers/config_providers_test.dart`, `test/providers/task_providers_test.dart`, `test/ui/settings_screen_test.dart`, `test/ui/edit_task_screen_test.dart`, `test/ui/home_screen_test.dart`, `test/ui/widgets/tier_task_pill_test.dart`, `test/ui/widgets/task_info_dialog_test.dart` | Modify | Unit and widget tests covering `TTW\x01`/`TTW\x02` binary encoding, provider forwarding, settings dropdown, toggle reset mechanics, live timer boundaries/lifecycle/sub-second guards, and urgency badge colors. |

### 2.2 TDF Schema, Localization & State Changes

#### 2.2.1 TDF `0.7.0` Schema & Binary Workspace Envelope (`TTW\x02`)
* **`.tdf` Format (`TEP-006`):** Unchanged (`due <YYYY-MM-DD HH:MM:SS> [passive] ["<note>"]` in `spec/TDF_SPEC_0.7.0.md` Section 4.1.2; `DEFAULT_DUE_LEAD_SECONDS = 86400` in Section 5.5).
* **Workspace Binary Format (`AppWorkspace`):**
  - Header (`6` bytes): `[0x54, 0x54, 0x57, version, workspaceCount, activeIndex]`, where `encodePersistedState` writes `version = 0x02` (`TTW\x02`) and `_validateBinaryHeader` accepts `version == 0x01` (`TTW\x01`) or `version == 0x02` (`TTW\x02`).
  - Per-workspace record in `TTW\x02`: `[flags (1B), 7 length-prefixed UTF-8 strings, tzWord (2B), dueLeadWindow (1B in 0..5)]`.
  - Legacy `TTW\x01` records omit the trailing byte and decode with `dueLeadWindow: DueLeadWindow.hours24`. In `TTW\x02`, a truncated trailing byte or an out-of-range byte (`> 5`) throws `WorkspaceException(WorkspaceErrorKind.corruptPayload, ...)`.

#### 2.2.2 Localization Keys (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`)

| Key | English (`app_en.arb`) | German (`app_de.arb`) |
| :--- | :--- | :--- |
| `dueLeadWindowSectionTitle` | `"Deadline Auto-Priority"` | `"Fälligkeits-Priorisierung"` |
| `dueLeadWindowSectionDescription` | `"Automatically prioritize scheduled open tasks into Focus and Ready when their due date approaches."` | `"Geplante offene Aufgaben bei nahender Fälligkeit automatisch für Fokus und Bereit priorisieren."` |
| `dueLeadWindowLabel` | `"Lead Window"` | `"Vorlaufzeit"` |
| `dueLeadWindowOff` | `"Off (never auto-prioritize)"` | `"Aus (nie automatisch priorisieren)"` |
| `dueLeadWindowAtDue` | `"At deadline (0 hours)"` | `"Bei Fälligkeit (0 Stunden)"` |
| `dueLeadWindow12Hours` | `"12 hours before deadline"` | `"12 Stunden vor Fälligkeit"` |
| `dueLeadWindow24Hours` | `"24 hours before deadline (Default)"` | `"24 Stunden vor Fälligkeit (Standard)"` |
| `dueLeadWindow48Hours` | `"48 hours before deadline"` | `"48 Stunden vor Fälligkeit"` |
| `dueLeadWindow7Days` | `"7 days before deadline"` | `"7 Tage vor Fälligkeit"` |
| `taskDueAutoPrioritizeLabel` | `"Auto-prioritize near deadline"` | `"Bei nahender Fälligkeit priorisieren"` |
| `taskDueAutoPrioritizeSubtitle` | `"Pull ahead of regular queued tasks once the lead window opens."` | `"Ab Beginn der Vorlaufzeit vor reguläre Aufgaben ziehen."` |
| `taskInfoDueAutoPromotedActive` | `"Prioritized by deadline lead window"` | `"Durch Fälligkeits-Vorlaufzeit priorisiert"` |
| `taskInfoDueAutoPromoteScheduled` | `"Auto-prioritizes {window} before deadline"` | `"Automatische Priorisierung {window} vor Fälligkeit"` |
| `taskInfoDuePassiveHint` | `"Informational deadline (auto-priority off)"` | `"Informativer Termin (Auto-Priorität aus)"` |
| `taskInfoDueLeadWindowOffHint` | `"Deadline auto-priority disabled in settings"` | `"Fälligkeits-Priorisierung in Einstellungen deaktiviert"` |

### 2.3 Implementation Details

#### 2.3.1 `DueLeadWindow` Enum (`lib/models/webdav_config.dart`)
```dart
enum DueLeadWindow {
  off(id: 0, duration: null),
  atDue(id: 1, duration: Duration.zero),
  hours12(id: 2, duration: Duration(hours: 12)),
  hours24(id: 3, duration: Duration(hours: 24)),
  hours48(id: 4, duration: Duration(hours: 48)),
  days7(id: 5, duration: Duration(days: 7));

  const DueLeadWindow({required this.id, required this.duration});

  final Duration? duration;
  final int id;

  static DueLeadWindow fromId(int rawId) {
    return switch (rawId) {
      0 => DueLeadWindow.off,
      1 => DueLeadWindow.atDue,
      2 => DueLeadWindow.hours12,
      3 => DueLeadWindow.hours24,
      4 => DueLeadWindow.hours48,
      5 => DueLeadWindow.days7,
      _ => DueLeadWindow.hours24,
    };
  }
}
```

#### 2.3.2 Provider Wiring (`WebDavConfigNotifier` & `TaskNotifier`)
* `WebDavConfigNotifier.updateDueLeadWindow(DueLeadWindow dueLeadWindow)`:
  - Persists `current.copyWith(dueLeadWindow: dueLeadWindow)` via `updateConfig(...)` and notifies `TaskNotifier.reevaluateForLeadWindow(dueLeadWindow.duration)` so `taskNotifierProvider`'s `AsyncData<TaskBoard>` updates its in-memory tier slices immediately (keeping `downgradeTask` and tier counts aligned) without touching disk or WebDAV.
* `TaskNotifier`:
  - Helper `Duration? get _currentDueLeadWindow => resolveCurrentConfig(ref).dueLeadWindow.duration;`.
  - Pass `dueLeadWindow: _currentDueLeadWindow` into `_currentBoard.downgradeTask(...)`, `scheduleTask(...)`, `blockTask(...)`, `moveTaskInQueue(...)`, `restoreTask(...)`, `addTask(...)`, `updateTask(...)`, `completeTask(...)`, `deleteTask(...)`, `deleteLocation(...)`, `toggleSubtask(...)`, and `TaskBoardUndo.apply(...)`.

#### 2.3.3 `EditTaskScreen` Toggle Reset State Machine (`lib/ui/edit_task_screen.dart`)
* Fields on `_EditTaskScreenState`:
  - `late bool _autoPrioritizeDue;`
  - `bool _didUserToggleAutoPrioritizeDue = false;`
  - `late final DateTime? _initialDueAt;`
  - `late final String _initialDueText;`
* Initialization in `initState()`:
  - `_initialDueAt = task?.dueAt;`
  - `_initialDueText = _dueController.text.trim();`
  - `_autoPrioritizeDue = !(task?.isDuePassive ?? false);`
* Resolution helper `_resolveCurrentEditorDueAt()`:
  - If `!_hasDue`, returns `null`.
  - If `_dueController.text.trim() == _initialDueText && _initialDueAt != null`, returns `_initialDueAt` (preserving sub-minute `:SS` seconds losslessly when untouched).
  - Otherwise returns `TaskItem.tryParseTdfTimestampInput(_dueController.text.trim())` (converted via `config.localWallClockToUtc` or matching the editor's timestamp convention).
* In `_handleDueChanged()` (invoked on manual typing, clear button, date picker, and time picker updates):
  - Clears `_dueErrorMessage` if non-null.
  - Resolves `candidateDueAt = _resolveCurrentEditorDueAt()`. If `!_didUserToggleAutoPrioritizeDue && candidateDueAt != null && candidateDueAt != _initialDueAt && !_autoPrioritizeDue`, updates `setState(() => _autoPrioritizeDue = true)`.
* When toggling `Due` chip (`onToggleDue`):
  - Flipping `_hasDue` to `false` sets `_autoPrioritizeDue = true` and `_didUserToggleAutoPrioritizeDue = false`.
* When toggling `task_editor_due_auto_prioritize_switch`:
  - Sets `_autoPrioritizeDue = value` and `_didUserToggleAutoPrioritizeDue = true`.

#### 2.3.4 `HomeScreen` Single Boundary Timer (`lib/ui/home_screen.dart`)
* Pure static helper `HomeScreenBoundaryTimer.nextBoundaryUtc({required Iterable<TaskItem> tasks, required DateTime nowUtc, required Duration? dueLeadWindow})`:
  - Computes `now = TaskItem.normalizeTimestamp(nowUtc)` and iterates flatly (`P-NO-NESTED-LOOPS`, `P-ZERO-ALLOC`) over `tasks`, updating `DateTime? earliest`:
    1. If `!task.isCompleted && task.completedAt == null`:
       - Check finite `suspendedAt`: if `!task.isSuspendedForever`, `suspendedAt != null`, `suspendedAt != TaskItem.defaultSuspendedAt`, and `suspendedAt.isAfter(now)`, update `earliest`.
       - Check `dueAt`: if `dueAt != null`:
         - If `dueLeadWindow != null && !task.isDuePassive`: compute `leadStart = dueAt.subtract(dueLeadWindow)`; if `leadStart.isAfter(now)`, update `earliest`.
         - If `dueAt.isAfter(now)`: update `earliest`.
  - Returns `earliest`.
* In `_HomeScreenState`:
  - Fields: `Timer? _boundaryTimer;`, `int _boundaryTick = 0;`, `bool _isAppResumed = true;`, `AppLifecycleListener? _lifecycleListener;`, `DateTime? _scheduledBoundaryUtc;`.
  - `_syncBoundaryTimer(TaskBoard board, WebDavConfig config)`:
    - If `!_isAppResumed`, cancels `_boundaryTimer` and sets `_scheduledBoundaryUtc = null`.
    - Computes `rawUtcNow = ref.read(clockProvider)().toUtc()` and `nextBoundary = nextBoundaryUtc(tasks: board.allTasks, nowUtc: rawUtcNow, dueLeadWindow: config.dueLeadWindow.duration)`.
    - If `nextBoundary == _scheduledBoundaryUtc && (_boundaryTimer?.isActive ?? false)`, returns without reallocating `Timer`.
    - Cancels `_boundaryTimer`, records `_scheduledBoundaryUtc = nextBoundary`, and if `nextBoundary != null`, computes `rawDiff = nextBoundary.difference(rawUtcNow)` and arms `Timer(rawDiff > const Duration(milliseconds: 25) ? rawDiff : const Duration(milliseconds: 25), _handleBoundaryTimerFired)`.
  - `_handleBoundaryTimerFired()`:
    - If `!mounted || !_isAppResumed`, returns.
    - Reads `rawUtcNow = ref.read(clockProvider)().toUtc()` and `normalizedNow = TaskItem.normalizeTimestamp(rawUtcNow)`.
    - If `_scheduledBoundaryUtc case final target? when normalizedNow.isBefore(target)` (sub-second early wakeup due to `normalizeTimestamp` truncation), re-arms `_boundaryTimer` for `max(target.difference(rawUtcNow), const Duration(milliseconds: 25))` and returns without calling `setState`.
    - Clears `_scheduledBoundaryUtc = null`, logs `AppLogger.event(LogLevel.debug, LogTag.ui, 'ui.boundary_timer.fired')`, and calls `setState(() => _boundaryTick++)`.
  - `_LandingContentSwitcher` and `_TierTaskIndicators` watch/receive the current evaluation instant so crossing `dueAt - W_due` or `dueAt` updates both tier placement and `due_task_badge_<id>` styling in the same frame.

### 2.4 Testing Strategy
1. **`test/models/app_workspace_test.dart` & `test/models/tdf_v050_primitives_test.dart` (`M-EXHAUSTIVE-STATE-TESTS`, `M-EXTREME-BOUND-TESTS`):**
   - Round-trip every `DueLeadWindow` variant (`off`, `atDue`, `hours12`, `hours24`, `hours48`, `days7`) through `AppWorkspace.encodePersistedState` (`TTW\x02`) and `AppWorkspace.decodePersistedState` across single and multi-workspace (`32` max) payloads.
   - Construct genuine legacy `TTW\x01` byte payloads (`version == 0x01`, without the trailing `dueLeadWindow` byte) and verify backward-compatible decoding to `DueLeadWindow.hours24`.
   - Verify `WorkspaceErrorKind.corruptPayload` on truncated `TTW\x02` records, trailing garbage bytes, unsupported version `0x03`, and out-of-range `dueLeadWindow` enum byte `0x06` / `0xFF`.
2. **`test/providers/config_providers_test.dart` & `test/providers/task_providers_test.dart` (`M-EXHAUSTIVE-STATE-TESTS`, `M-IO-TESTS`, `M-REAL-MECHANICS-TESTS`):**
   - Verify `updateDueLeadWindow` persists across workspace switches, updates `TaskNotifier`'s in-memory tier slices immediately without writing `.tdf` to `LocalFileRepository` or `WebDavRepository`, and forwards non-default `DueLeadWindow` values (`off`, `atDue`, `hours48`, `days7`) into `downgradeTask`, `scheduleTask`, `moveTaskInQueue`, and `restoreTask`.
   - Verify workspace switching across `await` boundaries (`M-REAL-MECHANICS-TESTS`) where Workspace A uses `DueLeadWindow.off` and Workspace B uses `DueLeadWindow.days7`.
3. **`test/ui/settings_screen_test.dart` & `test/ui/edit_task_screen_test.dart` (`M-EXHAUSTIVE-STATE-TESTS`):**
   - Verify selecting each `DueLeadWindow` option in `settings_due_lead_window_dropdown` in both `en` and `de` locales.
   - Verify `task_editor_due_auto_prioritize_switch` visibility when `hasDue` toggles on/off, initial `false` state when editing a `due ... passive` task, automatic reset to `true` (`isDuePassive == false`) when `dueAt` is edited without touching the switch, preservation of `isDuePassive == true` when the user manually toggles the switch off for the new `dueAt`, and lossless `:SS` preservation when `due` is untouched.
4. **`test/ui/home_screen_test.dart`, `test/ui/widgets/tier_task_pill_test.dart` & `test/ui/widgets/task_info_dialog_test.dart` (`M-EXTREME-BOUND-TESTS`, `M-REAL-MECHANICS-TESTS`):**
   - Controlled fake clock + `tester.pump(duration)` tests verifying live single-timer transitions in `HomeScreen`:
     1. Open task in `Planned` automatically pulls into `Focus` and `due_task_badge_<id>` switches to `warningAccent` at exact `dueAt - W_due`.
     2. Open task (including `passive` and `DueLeadWindow.off` tasks) transitions `due_task_badge_<id>` live to `colorScheme.error` at exact `dueAt`.
     3. Deferred task in `Blocked` wakes into `Focus`/`Ready` at exact `suspendedAt`.
     4. Sub-second early wakeup (`rawUtcNow = 16:59:59.990Z` for `targetBoundary = 17:00:00Z`) re-arms for `>= 25 ms` without premature promotion at `16:59:59Z` and promotes cleanly once clock reaches `17:00:00.015Z`.
     5. `AppLifecycleState.paused` cancels the active `Timer`, and `AppLifecycleState.resumed` immediately catches up and schedules the next boundary.
   - Verify `Completed` tasks keep muted `due_task_badge_<id>` styling even when `dueAt <= nowUtc`, and verify all four `TaskInfoDialog` auto-priority status strings.

## Part 3: Implementation Record & Tasks

### 3.1 Task Breakdown
- [ ] Run `python3 .agents/scripts/tiertask_dev.py verify --fast` to confirm a clean baseline after `TEP-006`.
- [ ] Add English and German localization keys to `lib/l10n/app_en.arb` and `lib/l10n/app_de.arb` via `tiertask_dev.py l10n --set` and run `flutter gen-l10n`.
- [ ] Write failing unit and widget tests in `test/models/app_workspace_test.dart`, `test/models/tdf_v050_primitives_test.dart`, `test/providers/config_providers_test.dart`, `test/providers/task_providers_test.dart`, `test/ui/settings_screen_test.dart`, `test/ui/edit_task_screen_test.dart`, `test/ui/home_screen_test.dart`, `test/ui/widgets/tier_task_pill_test.dart`, and `test/ui/widgets/task_info_dialog_test.dart` (TDD Red Phase — `P-TDD-FIRST`).
- [ ] Implement `DueLeadWindow` in `lib/models/webdav_config.dart`, `TTW\x02` persistence in `lib/models/app_workspace.dart`, provider forwarding in `lib/providers/`, `DueLeadWindowSelectionCard` in `lib/ui/widgets/settings_preference_cards.dart` and `lib/ui/settings_screen.dart`, `Auto-prioritize near deadline` toggle in `lib/ui/widgets/task_editor_scheduling_card.dart` and `lib/ui/edit_task_screen.dart`, single-timer boundary scheduling in `lib/ui/home_screen.dart`, and urgency badges/status in `lib/ui/widgets/tier_task_pill.dart` and `lib/ui/widgets/task_info_dialog.dart` (TDD Green & Refactor Phase).
- [ ] Update Parts 1 and 2 if implementation details evolve during development.
- [ ] Synchronize `ARCHITECTURE.md`, `README.md`, and `AGENTS.md` per **`update-documentation`**.
- [ ] Update `CHANGELOG.md` under `## [Unreleased]` per **`changelog-updater`**.
- [ ] Run `python3 .agents/scripts/tiertask_dev.py verify --full --fix`.
- [ ] Set `status: review`, update `BOARD.md`, and request user approval.
- [ ] After user approval, set `status: completed`, update `BOARD.md`, and list delivered artifacts in Part 3.3.

### 3.2 Work Log & Decisions
* **2026-11-14:** Drafted initial concept (`status: concept`) for configurable `DueLeadWindow` preferences (`TTW\x02`), deterministic `Auto-prioritize near deadline` editor toggle, `HomeScreen` live boundary timer, and deadline urgency indicators on top of `TEP-006` (`spec/TDF_SPEC_0.7.0.md` Topic 2).

### 3.3 Delivered Artifacts
*(Pending — proposal is in `concept` stage)*
