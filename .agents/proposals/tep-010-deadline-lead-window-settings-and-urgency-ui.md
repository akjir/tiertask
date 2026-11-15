---
id: TEP-010
title: Configurable Deadline Lead-Window Preferences, Live Boundary Timer, and Urgency Indicators
status: completed
type: feature
created: 2026-11-14
updated: 2026-11-16
---

# TEP-010: Configurable Deadline Lead-Window Preferences, Live Boundary Timer, and Urgency Indicators

## Part 1: Concept & Proposal

### 1.1 Summary
This proposal specifies the per-workspace deadline lead-window preference, task editor auto-priority control, live wall-clock boundary scheduler, and deadline urgency indicators on top of **TierTask Data Format (`TDF`) `0.7.0`** (`spec/TDF_SPEC_0.7.0.md` and `TEP-006` in `tep-006-tdf-spec-0-7-0.md`). While `TEP-006` delivers the `due <YYYY-MM-DD> [<HH:MM[:SS]>] [passive] ["<note>"]` grammar, parser/serializer, normative 24-hour default `due` lead-window evaluation (`TaskBoardEvaluator.defaultDueLeadWindow`), context-relative `downgradeTask` semantics (`Section 6.3`), three-way `(dueAt, isDuePassive, dueNote)` reconciliation, undo restoration, and lossless `isDuePassive` editor preservation, this proposal introduces:
1. The per-workspace `DueLeadWindow` preference (`off`, `atDue` = `0h`, `hours12` = `12h`, `hours24` = `24h` default, `hours48` = `48h`, `days7` = `168h`) persisted in `TTW\x02` workspace binary records with lossless `TTW\x01` backward compatibility.
2. Acyclic provider wiring (`P-ACYCLIC-DAG`) across `WebDavConfigNotifier`, `BoundaryTickNotifier`, `TaskSyncPipeline`, `TaskNotifier`, and `SettingsScreen`, re-evaluating loaded boards in memory without `.tdf` file or WebDAV I/O when `DueLeadWindow` changes.
3. Explicit `priority` promotion `isDuePassive` reset alignment (`spec/TDF_SPEC_0.7.0.md` Sections 6.2 and 6.6) in `TaskBoardQueueMutator.scheduleTask` and `TaskBoardMutator.updateTask`, plus the deterministic `Auto-prioritize near deadline` (`!isDuePassive`) switch in `EditTaskScreen` and `TaskEditorSchedulingCard`.
4. Single-timer wall-clock boundary scheduling in `HomeScreen` across open tasks' finite `suspendedAt`, lead-window entry `dueAt - W_due`, and exact `dueAt`, coordinated through `boundaryTickProvider` with `AppLifecycleState` pause/resume, a `25 ms` sub-second early-wakeup floor, and a `7-day` per-chunk timer cap for far-future timestamps (`<= 9999-12-31`).
5. Lead-window warning (`AppTheme.warningAccent`) and overdue (`colorScheme.error`) urgency colors on `TierTaskPill` (`due_task_badge_<id>`) and exhaustive deadline auto-priority status lines in `TaskInfoDialog`.

### 1.2 Motivation
`TEP-006` (`spec/TDF_SPEC_0.7.0.md` Sections 4.1.2, 5.5, and 6.3) defines read-only effective priority when an open queued task's non-`passive` `due` timestamp enters `due <= now + W_due` (normatively defaulting to `24 hours` / `86,400` seconds). Four application-layer capabilities are required to complete user control and real-time visibility across desktop and mobile sessions:
1. **Workspace-Specific Lead Horizons:** A personal errands workspace typically uses a `12h` or `24h` lead window, whereas a long-horizon engineering or tax workspace benefits from a `48h` or `7d` lead window (or `Off` / `At deadline (0 hours)` for strictly manual prioritization). Hardcoding `24h` across all workspaces prevents configuring pull sensitivity per workspace.
2. **Explicit Editor Control Over `passive` Deadlines:** When creating an informational cutoff date or editing a task previously downgraded via `Section 6.3` (`due ... passive`), users require an explicit `Auto-prioritize near deadline` switch in `EditTaskScreen` that automatically re-enables auto-promotion when `dueAt` changes to a different timestamp or when `Priority` is explicitly enabled, unless manually overridden by the user during the edit session.
3. **Live Threshold Transitions While Open:** Desktop (`Linux`, `Windows`) and foreground mobile (`Android`) sessions remain open across hours. Currently, `_LandingContentSwitcher._evaluateBoard` (`lib/ui/home_screen.dart`) calls `board.evaluateForContext(...)` without forwarding `configuration.dueLeadWindow.duration` and reads `clockProvider` only during widget rebuilds; no wall-clock timer wakes the UI when `suspendedAt`, `dueAt - W_due`, or exact `dueAt` is crossed while idle.
4. **Immediate Visual Distinction Between Future, Urgent, and Overdue Deadlines:** `TierTaskPill` (`_TierTaskIndicators._buildDueBadge` in `lib/ui/widgets/tier_task_pill.dart`) currently renders every `due_task_badge_<id>` in a single muted gray color regardless of whether the deadline is weeks away, inside the active lead window, or overdue, and formats UTC `dueAt` directly instead of the workspace's configured local wall clock.

### 1.3 Goals & Non-Goals
* **Goals:**
  1. Define `DueLeadWindow` (`off`, `atDue` = `0h`, `hours12` = `12h`, `hours24` = `24h` default, `hours48` = `48h`, `days7` = `168h`) in `lib/models/webdav_config.dart` and persist it per workspace in `lib/models/app_workspace.dart` via a `TTW\x02` binary envelope (`1` trailing byte per workspace record) while decoding legacy `TTW\x01` payloads with `DueLeadWindow.hours24`.
  2. Forward `configuration.dueLeadWindow.duration` across `WebDavConfigNotifier` (`lib/providers/config_providers.dart`), every board evaluation/merge/stamp entry point in `TaskSyncPipeline` (`lib/providers/sync_providers.dart`), every board mutation/undo/re-evaluation entry point in `TaskNotifier` (`lib/providers/task_providers.dart`), and `SettingsScreen` (`lib/ui/settings_screen.dart`, `lib/ui/widgets/settings_preference_cards.dart`) while preserving `0` circular import SCCs (`P-ACYCLIC-DAG`) and zero `.tdf` I/O on preference updates.
  3. Align `TaskBoardQueueMutator.scheduleTask` and `TaskBoardMutator.updateTask` with `spec/TDF_SPEC_0.7.0.md` Sections 6.2 and 6.6 so explicit `priority` promotion resets `isDuePassive` to `false` unless `isDuePassive` is explicitly supplied, and add the `Auto-prioritize near deadline` (`!isDuePassive`) switch to `TaskEditorSchedulingCard` and `EditTaskScreen` (`addTask` and `updateTask`).
  4. Schedule at most one active wall-clock `Timer` in `HomeScreen` (`lib/ui/home_screen.dart`) across open tasks' finite `suspendedAt > now`, lead-window entry `dueAt - W_due > now`, and exact `dueAt > now`, propagating boundary ticks via `boundaryTickProvider` to `HomeScreen`, `TierTaskPill`, and open `TaskInfoDialog` routes with `AppLifecycleState` background cancellation, `resumed` catch-up, a `25 ms` sub-second early-wakeup guard, and a `7-day` maximum timer chunk clamp.
  5. Render lead-window warning (`AppTheme.of(context).warningAccent`) and overdue (`Theme.of(context).colorScheme.error`) urgency colors on `TierTaskPill` (`due_task_badge_<id>`) for open tasks (suppressing urgency colors on `Completed` tasks and during completion exit animations) and display deterministic auto-priority status lines in `TaskInfoDialog._buildDueSection`.
* **Non-Goals:**
  1. Persisting `DueLeadWindow` inside `.tdf` documents (`spec/TDF_SPEC_0.7.0.md` defines `W_due` as a client evaluation parameter with normative `86,400`-second default so viewing or changing lead-window preferences never mutates `.tdf` files or triggers WebDAV writes).
  2. Delivering OS background push notifications or alarm manager wakeups while the application process is suspended or terminated.
  3. Sorting `Focus` or `Ready` by ascending `due` timestamp instead of `spec/TDF_SPEC_0.7.0.md` Section 5.5's stable two-bucket `queue` partition.
  4. Adding task editor inputs for `suspendedNote`, `dueNote`, or recurring `lead <N> days` (`TEP-011` in `tep-011-scheduling-notes-and-repeat-lead-ui.md` owns those editor controls; `EditTaskScreen` continues preserving `dueNote`, `suspendedNote`, `repeatRule.leadDays`, `origin`, and `history` losslessly as implemented in `TEP-006`).

### 1.4 Description

#### 1.4.1 Per-Workspace `DueLeadWindow` Preference & `TTW\x02` Persistence
Each isolated workspace (`AppWorkspace`) stores its own `DueLeadWindow` setting inside `WebDavConfig`:
* **`DueLeadWindow.off` (`id: 0`, `duration: null`):** Deadlines remain informational and never grant derived effective priority (`isDueUrgent` is always `false`). Overdue badges (`due <= now`) still highlight in `colorScheme.error` on open tasks.
* **`DueLeadWindow.atDue` (`id: 1`, `duration: Duration.zero`):** Open non-`passive` queued tasks gain effective priority at exact deadline arrival (`due <= now`, `0` seconds lead).
* **`DueLeadWindow.hours12` (`id: 2`, `duration: Duration(hours: 12)`):** Open non-`passive` queued tasks gain effective priority `12 hours` (`43,200` seconds) before `due`.
* **`DueLeadWindow.hours24` (`id: 3`, `duration: Duration(hours: 24)`, Default):** Open non-`passive` queued tasks gain effective priority `24 hours` (`86,400` seconds) before `due`, matching `DEFAULT_DUE_LEAD_SECONDS` in `spec/TDF_SPEC_0.7.0.md` Section 5.5.
* **`DueLeadWindow.hours48` (`id: 4`, `duration: Duration(hours: 48)`):** Open non-`passive` queued tasks gain effective priority `48 hours` (`172,800` seconds) before `due`.
* **`DueLeadWindow.days7` (`id: 5`, `duration: Duration(days: 7)`):** Open non-`passive` queued tasks gain effective priority `7 days` (`168 hours` / `604,800` seconds) before `due`.

In `SettingsScreen` (`SettingsPreferenceCards`), `DueLeadWindowSelectionCard` renders immediately below `TimeZoneSelectionCard` with a `DropdownButtonFormField<DueLeadWindow>` (`ValueKey('settings_due_lead_window_dropdown')`). Selecting an option persists the updated `WebDavConfig` to `SettingsRepository` (`TTW\x02`) and triggers in-memory `TaskBoard` re-evaluation in `TaskNotifier` via `ref.listen` without triggering `TaskNotifier.build()` (`AsyncLoading`), `.tdf` disk writes, or WebDAV requests.

#### 1.4.2 Deterministic `Auto-prioritize near deadline` Switch & Section 6.2/6.6 Alignment
Whenever `Due` is enabled (`_hasDue == true`) on an open or newly created task in `EditTaskScreen` (`TaskEditorSchedulingCard`), an inline switch row (`ValueKey('task_editor_due_auto_prioritize_switch')`) is rendered directly below `task_editor_due_input`:
* **Completed Tasks:** When editing a `Completed` task (`_isCompletedTask == true`), `task_editor_due_auto_prioritize_switch` is omitted because completed tasks do not participate in Section 5.5 pull evaluation, and untouched `existingTask.isDuePassive` continues to be preserved on save when `dueAt` is unchanged.
* **Initial State (New or Open Task):** `_initialDueAt = task?.dueAt`, `_initialDueText = _dueController.text.trim()`, `_autoPrioritizeDue = !(task?.isDuePassive ?? false)`, and `_didUserToggleAutoPrioritizeDue = false`. Initial `_dueController` formatting uses `TaskItem.formatTdfTimestamp(dueAt)` directly when `task?.dueAt != null` rather than `TaskEditorSuspendedField.formatInitialText` so a valid maximum `due` timestamp of `9999-12-31 23:59:59` (`TaskItem.defaultSuspendedAt`) is never blanked out.
* **Manual Switch Override:** Toggling `task_editor_due_auto_prioritize_switch` sets `_autoPrioritizeDue = value` and locks `_didUserToggleAutoPrioritizeDue = true` for the remainder of the active `Due` attachment.
* **Automatic Reset on Deadline Change:** Whenever `_dueController` changes (via typing, clear button, date picker, or time picker) such that the parsed `candidateDueAt` is non-null and `!_isSameDueTimestamp(candidateDueAt, _initialDueAt)` while `!_didUserToggleAutoPrioritizeDue` and `!_autoPrioritizeDue`, `_autoPrioritizeDue` resets to `true` (`isDuePassive = false`). Once auto-reset to `true`, it stays `true` unless the user manually toggles the switch off.
* **Automatic Reset on Explicit `Priority` Selection:** In accordance with `spec/TDF_SPEC_0.7.0.md` Section 6.6 (`explicitly setting priority to true also resets passive to omitted (false)`), selecting `QuickAddMode.priority` (`_toggleMode(QuickAddMode.priority)` transitioning `_mode` to `QuickAddMode.priority`) while `!_didUserToggleAutoPrioritizeDue` and `!_autoPrioritizeDue` also resets `_autoPrioritizeDue = true`. At the domain layer, `TaskBoardQueueMutator.scheduleTask(..., isPriority: true)` (`Section 6.2`) and `TaskBoardMutator.updateTask` when promoting `nextPriority` via explicit `isPriority == true` or `targetTier == TaskTier.focus` with `isDuePassive == null` (`Section 6.6`) likewise reset `isDuePassive` to `false`.
* **Toggling `Due` Off:** Disabling `Due` (`_hasDue = false`) resets `_autoPrioritizeDue = true` and `_didUserToggleAutoPrioritizeDue = false`; saving with `_hasDue == false` passes `clearDueAt: true` (`isDuePassive: false`).
* **Persisting (`addTask` and `updateTask`):** Both `notifier.addTask(...)` and `notifier.updateTask(...)` receive `isDuePassive: _hasDue && !_autoPrioritizeDue` (preserving untouched `existingTask.isDuePassive` on `_isCompletedTask` when `_isSameDueTimestamp(draft.dueAt, existingTask.dueAt)`).

#### 1.4.3 Live Boundary `Timer`, `boundaryTickProvider`, & Lifecycle Handling
`HomeScreen` (`lib/ui/home_screen.dart`) keeps derived tiers, pill urgency indicators, and open `TaskInfoDialog` sheets synchronized with wall-clock transitions without periodic polling:
1. **Shared Reactive Boundary Tick (`boundaryTickProvider`):** `lib/providers/config_providers.dart` exposes `boundaryTickProvider` (`NotifierProvider<BoundaryTickNotifier, int>`), an in-memory monotonic counter initialized to `0`. `_LandingContentSwitcher._evaluateBoard`, `_TierTaskIndicators.build`, and `TaskInfoDialog.build` all watch `boundaryTickProvider` alongside `clockProvider`, ensuring that `const _TierTaskIndicators` leaf widgets and separate `DialogRoute` trees (`TaskInfoDialog`) rebuild in the exact same frame when a boundary fires, even when underlying `TaskBoard` / `TaskItem` instances are unchanged.
2. **Context Evaluation With `dueLeadWindow`:** `_LandingContentSwitcher._evaluateBoard` watches `boundaryTickProvider`, `webDavConfigProvider`, and `clockProvider`, forwarding `dueLeadWindow: configuration.dueLeadWindow.duration` into `board.evaluateForContext(...)` across both global and filtered views.
3. **Single Earliest-Boundary `Timer`:** Pure helper `HomeScreenBoundaryTimer.nextBoundaryUtc` scans open tasks (`!task.isCompleted && task.completedAt == null`) in a single $O(N)$ flat pass (`P-NO-NESTED-LOOPS`, `P-ZERO-ALLOC`) against `now = TaskItem.normalizeTimestamp(nowUtc)` and finds the earliest strictly future UTC instant among:
   - Finite deferral expiry: `suspendedAt > now` (`!task.isSuspendedForever && suspendedAt != null && suspendedAt != TaskItem.defaultSuspendedAt`).
   - Lead-window entry: `dueAt.subtract(W_due) > now` when `W_due != null && !task.isDuePassive` (Dart `DateTime.utc` spans `±271,821` years, so subtracting up to `7 days` from `dueAt >= 0001-01-01` never underflows and naturally evaluates `leadStart.isAfter(now) == false` when `leadStart <= now`).
   - Exact deadline overdue transition: `dueAt > now` for every open task with `dueAt != null` (including tasks already inside `W_due`, marked `passive`, or under `DueLeadWindow.off` so `due_task_badge_<id>` and `TaskInfoDialog` transition live to overdue at `dueAt`).
   At most one `Timer` is active at any time; when no open task has a future boundary, zero timers run.
4. **Sub-Second Early-Wakeup Floor (`25 ms`) & Far-Future Chunk Cap (`7 days`):**
   - Because `TaskItem.normalizeTimestamp` truncates sub-second components (`16:59:59.994Z -> 16:59:59Z`), an OS timer scheduled from `targetBoundary.difference(rawUtcNow)` can fire slightly before the truncated UTC second advances. If `_handleBoundaryTimerFired` observes `TaskItem.normalizeTimestamp(rawUtcNow).isBefore(targetBoundary)`, it re-arms `_boundaryTimer` for `max(targetBoundary.difference(rawUtcNow), const Duration(milliseconds: 25))` without incrementing `boundaryTickProvider`.
   - Because TDF timestamps span up to `9999-12-31 23:59:59 UTC`, raw `Duration` differences can exceed 32-bit millisecond OS timer limits on desktop/mobile platforms. Each scheduled `Timer` delay is clamped to `[Duration(milliseconds: 25), Duration(days: 7)]`; if a `7-day` intermediate chunk expires before `targetBoundary`, `_handleBoundaryTimerFired` re-arms the next chunk transparently without rebuilding the UI prematurely.
5. **Lifecycle Conservation (`AppLifecycleListener`):** `_HomeScreenState` cancels `_boundaryTimer` in `dispose()` and whenever `AppLifecycleState` leaves `resumed` (`inactive`, `hidden`, `paused`, `detached`). Upon `AppLifecycleState.resumed`, `_HomeScreenState` increments `boundaryTickProvider` immediately to catch up on any boundaries crossed while backgrounded and schedules the next upcoming boundary.

#### 1.4.4 Urgency Badges on `TierTaskPill` & Status Details in `TaskInfoDialog`
* **`TierTaskPill` (`due_task_badge_<id>` in `lib/ui/widgets/tier_task_pill.dart`):**
  - `_TierTaskPillRow` forwards `isCompleted` (`_effectiveCompleted` in `_TierTaskPillState`, covering both `Completed`-tier tasks and open tasks playing their completion exit animation) to `_TierTaskIndicators(task: task, isCompleted: isCompleted)`.
  - `_TierTaskIndicators` formats the badge label in workspace local wall-clock date (`TaskItem.formatIsoDate(configuration.toLocalWallClock(dueAt))`) and resolves the badge text color against `normalizedNow = TaskItem.normalizeTimestamp(nowUtc)`:
    1. **Completed or Completing (`isCompleted || task.isCompleted || task.completedAt != null`):** Muted indicator color (`colorScheme.onSurfaceVariant.withValues(alpha: 0.55)`).
    2. **Open & Overdue (`!dueAt.isAfter(normalizedNow)`, i.e. `dueAt <= normalizedNow`):** `Theme.of(context).colorScheme.error` (for both active and `passive` deadlines, regardless of `DueLeadWindow`).
    3. **Open & Inside Active Lead Window (`dueAt.isAfter(normalizedNow)` and `task.isWithinDueLeadWindow(normalizedNow, configuration.dueLeadWindow.duration)`):** `AppTheme.of(context).warningAccent`.
    4. **Open & Outside Lead Window (or `isDuePassive` / `DueLeadWindow.off` before `dueAt`):** Muted indicator color (`colorScheme.onSurfaceVariant.withValues(alpha: 0.55)`).
  - Non-due indicator icons (`priority`, `suspended`, `blocked_by`, `conditions`, `repeat`, `note`, `links`, `subtasks`, `summary`) keep the muted indicator color unchanged.
* **`TaskInfoDialog` (`_buildDueSection` in `lib/ui/widgets/task_info_dialog.dart`):**
  - Evaluates `normalizedNow = TaskItem.normalizeTimestamp(nowUtc)` for `dueAt.isAfter(normalizedNow)` and `_formatRemainingDuration(dueAt.difference(normalizedNow), localizations)`.
  - Populates `_TaskInfoSectionData.details` deterministically:
    1. **Completed Task (`task.isCompleted || task.completedAt != null`):** `const <String>[]` (no active auto-priority hint on historical completed occurrences).
    2. **Open Task With `task.isDuePassive == true`:** `[localizations.taskInfoDuePassiveHint]`.
    3. **Open Task With `configuration.dueLeadWindow == DueLeadWindow.off`:** `[localizations.taskInfoDueLeadWindowOffHint]`.
    4. **Open Non-`passive` Task Currently Inside Lead Window (`task.isWithinDueLeadWindow(normalizedNow, configuration.dueLeadWindow.duration)` — includes overdue `dueAt <= normalizedNow` for `atDue`..`days7`):** `[localizations.taskInfoDueAutoPromotedActive]`.
    5. **Open Non-`passive` Future Task (`dueAt.isAfter(normalizedNow)`) With `configuration.dueLeadWindow == DueLeadWindow.atDue`:** `[localizations.taskInfoDueAutoPromoteAtDue]`.
    6. **Open Non-`passive` Future Task (`dueAt.isAfter(normalizedNow)`) Outside `hours12` / `hours24` / `hours48` / `days7`:** `[localizations.taskInfoDueAutoPromoteScheduled(_formatLeadWindowShort(configuration.dueLeadWindow, localizations))]`.

### 1.5 Alternatives
1. **Periodic `1`-Second Polling `Timer.periodic` in `HomeScreen`:** Rejected because waking the UI isolate every second across idle desktop and mobile sessions wastes CPU/battery and triggers `86,400` wakeups per day when zero boundaries are crossed. Scheduling a single one-shot `Timer` for the exact next UTC boundary performs $O(1)$ wakeups per actual task threshold.
2. **Pack `DueLeadWindow` into Remaining Bits of `flags` or `tzWord` in `TTW\x01`:** Rejected because all `8` bits of `flags` and all `16` bits of `tzWord` in `AppWorkspace` (`lib/models/app_workspace.dart` lines 236–263) are already allocated (`storageMode`, `language`, `themeMode`, `localWatchEnabled`, `themePalette`, `remoteLogFlag`, `timeZoneMode`, `locationEnabled`, `diagnosticsEnabled`, `logLevel`, and `11`-bit `offsetField`). Advancing the header version from `TTW\x01` to `TTW\x02` and appending `1` dedicated enum byte (`0..5`) per workspace record keeps encoding straightforward while preserving lossless `TTW\x01` decoding.
3. **Call `TaskNotifier` Directly From `WebDavConfigNotifier.updateDueLeadWindow`:** Rejected because `lib/providers/task_providers.dart` already imports `lib/providers/config_providers.dart`; importing `task_providers.dart` inside `config_providers.dart` would create a `2`-node circular import SCC violating `P-ACYCLIC-DAG`. Keeping `WebDavConfigNotifier` unidirectional and observing `dueLeadWindow` via `ref.listen` inside `TaskNotifier.build()` preserves `0` circular SCCs and prevents unnecessary `TaskNotifier.build()` storage reloads via `selectAsync` normalization.
4. **Use `_HomeScreenState`-Local `int _boundaryTick` Instead of `boundaryTickProvider`:** Rejected because `_TierTaskIndicators` is constructed inside `TierTaskPill` without prop-drilling wall-clock instants through `PageView -> TierScrollView -> HomeTierPane -> TierTaskPill -> _TierTaskPillRow`, and `TaskInfoDialog` runs in a separate modal `DialogRoute` outside `HomeScreen`'s subtree. A tiny Riverpod `boundaryTickProvider` (`int`) updates `HomeScreen`, `TierTaskPill`, and open `TaskInfoDialog` sheets atomically in one frame.

## Part 2: Technical Design & Code Changes

### 2.1 Architecture & Affected Modules

| Layer | File | Change Type | Responsibility |
| :--- | :--- | :--- | :--- |
| Models (`Rank 1`) | `lib/models/webdav_config.dart` | Modify | Add `DueLeadWindow` enum (`off`, `atDue`, `hours12`, `hours24`, `hours48`, `days7`) sorted alphabetically between `AppTimeZoneMode` and `StorageMode`; add `dueLeadWindow` field (`DueLeadWindow.hours24` default) to `WebDavConfig` (`constructor`, `copyWith`, `operator ==`, `hashCode`, `toString`). |
| Models (`Rank 1`) | `lib/models/app_workspace.dart` | Modify | Bump binary header version to `TTW\x02` (`0x02`), update pre-allocation guard (`+ 5` trailing/length bytes per string/record check), append `1` `dueLeadWindow` byte (`0..5`) per workspace record, accept `0x01` (`DueLeadWindow.hours24`) and `0x02` in `_validateBinaryHeader`, and reject truncated or `> 5` `dueLeadWindow` bytes in `_decodeRecord` with `WorkspaceErrorKind.corruptPayload`. |
| Models (`Rank 1`) | `lib/models/task_board_mutator.dart`, `lib/models/task_board_queue_mutator.dart` | Modify | Reset `isDuePassive` to `false` when explicitly promoting a task to `priority` in `TaskBoardQueueMutator.scheduleTask(..., isPriority: true)` (`Section 6.2`) and `TaskBoardMutator.updateTask` (`(isPriority == true || targetTier == TaskTier.focus) && nextPriority` when `isDuePassive == null`, `Section 6.6`). |
| Localization (`Rank 2`) | `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb` | Modify | Add `20` English and German localization keys for `DueLeadWindowSelectionCard`, `EditTaskScreen` auto-prioritize switch, and `TaskInfoDialog` deadline auto-priority status lines and short window labels (`flutter gen-l10n`). |
| Providers (`Rank 5`) | `lib/providers/config_providers.dart` | Modify | Add `boundaryTickProvider` (`BoundaryTickNotifier` with `increment()`), add `WebDavConfigNotifier.updateDueLeadWindow(DueLeadWindow)`, and include `'due_lead': newConfig.dueLeadWindow.name` in `config.update` structured logs. |
| Providers (`Rank 5`) | `lib/providers/sync_providers.dart` | Modify | Forward `config.dueLeadWindow.duration` across every `TdfImporter.importDocument`, `TdfService.parse`, `TaskBoardSync.stampAndNormalize`, `TaskBoardSync.merge`, and `TaskBoard.evaluate` call site in `TaskSyncPipeline`. |
| Providers (`Rank 5`) | `lib/providers/task_providers.dart` | Modify | Normalize `dueLeadWindow: DueLeadWindow.hours24` inside `build()`'s `selectAsync` watcher (preventing reload/sync I/O on preference change), listen to `webDavConfigProvider` `dueLeadWindow` via `ref.listen` for zero-I/O in-memory `applyAutoPull` re-evaluation, re-align post-`await` sync results with `_currentDueLeadWindow`, and forward `dueLeadWindow: _currentDueLeadWindow` across all `20` board/undo mutation methods. |
| UI (`Rank 6`) | `lib/ui/settings_screen.dart`, `lib/ui/widgets/settings_preference_cards.dart` | Modify | Add `DueLeadWindowSelectionCard` (`settings_due_lead_window_dropdown`) below `TimeZoneSelectionCard` inside `SettingsPreferenceCards` (`onPreferenceChanged(config.copyWith(dueLeadWindow: value))`) and dispatch `notifier.updateDueLeadWindow(updatedConfig.dueLeadWindow)` inside `_SettingsScreenState._handlePreferenceChanged`. |
| UI (`Rank 6`) | `lib/ui/edit_task_screen.dart`, `lib/ui/widgets/task_editor_scheduling_card.dart` | Modify | Render `task_editor_due_auto_prioritize_switch` when `hasDue && !isCompletedTask`, format initial `dueAt` via `TaskItem.formatTdfTimestamp`, implement deterministic `_didUserToggleAutoPrioritizeDue` reset on `dueAt` change and `QuickAddMode.priority` promotion, and pass `isDuePassive` to both `addTask` and `updateTask`. |
| UI (`Rank 6`) | `lib/ui/home_screen.dart` | Modify | Forward `dueLeadWindow` and watch `boundaryTickProvider` in `_LandingContentSwitcher._evaluateBoard`; add `HomeScreenBoundaryTimer` and single-timer scheduling in `_HomeScreenState` with `AppLifecycleListener`, `25 ms` early-wakeup floor, and `7-day` chunk clamp. |
| UI (`Rank 6`) | `lib/ui/widgets/tier_task_pill.dart`, `lib/ui/widgets/task_info_dialog.dart` | Modify | Watch `boundaryTickProvider`, forward `isCompleted` to `_TierTaskIndicators`, format `due_task_badge_<id>` in local wall-clock date with `warningAccent` / `colorScheme.error` urgency colors on open tasks, and render exhaustive auto-priority status lines in `TaskInfoDialog._buildDueSection`. |
| Tests | `test/models/app_workspace_test.dart`, `test/models/tdf_v050_primitives_test.dart`, `test/models/task_board_mutation_test.dart`, `test/models/task_board_lifecycle_test.dart`, `test/providers/config_providers_test.dart`, `test/providers/task_providers_test.dart`, `test/ui/settings_screen_test.dart`, `test/ui/edit_task_screen_test.dart`, `test/ui/home_screen_test.dart`, `test/ui/widgets/tier_task_pill_test.dart`, `test/ui/widgets/task_info_dialog_test.dart` | Modify | Unit and widget tests covering `TTW\x01`/`TTW\x02` encoding and bounds, Section 6.2/6.6 `isDuePassive` resets, sync/mutation `DueLeadWindow` forwarding, zero-I/O preference re-evaluation across mid-flight syncs, settings dropdown, editor switch state machine, live boundary timer/lifecycle/guards, pill badge colors, and `TaskInfoDialog` status lines. |

### 2.2 TDF Schema, Binary Envelope & Localization Changes

#### 2.2.1 TDF `0.7.0` Schema & Workspace Binary Envelope (`TTW\x02`)
* **`.tdf` Format (`spec/TDF_SPEC_0.7.0.md`):** Unchanged (`due <YYYY-MM-DD HH:MM:SS> [passive] ["<note>"]` in Section 4.1.2; `DEFAULT_DUE_LEAD_SECONDS = 86400` in Section 5.5; `passive` reset rules in Sections 6.2 and 6.6).
* **Workspace Binary Format (`lib/models/app_workspace.dart`):**
  - **Header (`6` bytes):** `[0x54, 0x54, 0x57, version, workspaceCount, activeIndex]` (`maxWorkspaces = 32`, `maxBinaryBytes = 65536`).
    - `encodePersistedState` writes `version = 0x02` (`_formatVersion = 0x02`).
    - `_validateBinaryHeader` returns `({int version, int count, int activeIndex})`, accepting `version == 0x01` (`_legacyFormatVersion`) or `version == 0x02` (`_formatVersion`) and throwing `WorkspaceException(WorkspaceErrorKind.corruptPayload, ...)` on any other version byte (`0x00`, `>= 0x03`), truncated header (`< 6` bytes), `count > maxWorkspaces`, or invalid `activeIndex`.
  - **Record Layout:**
    - `TTW\x01` (legacy read-only compatibility): `[flags (1B), 7 length-prefixed UTF-8 strings (id, name, serverUrl, username, remoteFilePath, localFilePath, remoteLogPath), tzWord (2B big-endian)]`. Decodes with `dueLeadWindow: DueLeadWindow.hours24`.
    - `TTW\x02` (active read/write format): `[flags (1B), 7 length-prefixed UTF-8 strings, tzWord (2B big-endian), dueLeadWindow (1B unsigned in 0..5)]`.
  - **Pre-Allocation Bound (`P-BOUND-ALLOC`):** Before appending each of the `7` UTF-8 strings in `_appendWorkspaceRecord`, verify `encoded.length <= maxStringBytes` (`2,048`) AND `builder.length + 2 + encoded.length + trailingRecordBytes <= maxBinaryBytes` (specifically checking `builder.length + 5 + encoded.length > maxBinaryBytes`, accounting for `2` string-length bytes + `2` `tzWord` bytes + `1` `dueLeadWindow` byte at the end of the record) so `BytesBuilder` never exceeds `65,536` bytes.
  - **Corruption Validation on Decode:** In `_decodeRecord(Uint8List source, int startOffset, {required int version})`, when `version == 0x02`, require `cursor < source.length` (minimum record tail `cursor + 3 <= source.length` before reading `tzWord` and `dueLeadWindow`). Read `final rawDueLead = source[cursor]; cursor += 1;`. If `rawDueLead > 5`, throw `WorkspaceException(WorkspaceErrorKind.corruptPayload, 'Workspace record contains invalid due lead window.')`. After decoding `count` records, if `offset != bytes.length`, throw `WorkspaceException(WorkspaceErrorKind.corruptPayload, 'Workspace payload contains trailing bytes.')`.

#### 2.2.2 Localization Keys (`lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`)

| Key | Placeholders | English (`app_en.arb`) | German (`app_de.arb`) |
| :--- | :--- | :--- | :--- |
| `dueLeadWindowSectionTitle` | — | `"Deadline Auto-Priority"` | `"Fälligkeits-Priorisierung"` |
| `dueLeadWindowSectionDescription` | — | `"Automatically prioritize scheduled open tasks into Focus and Ready when their due date approaches."` | `"Geplante offene Aufgaben bei nahender Fälligkeit automatisch für Fokus und Bereit priorisieren."` |
| `dueLeadWindowLabel` | — | `"Lead Window"` | `"Vorlaufzeit"` |
| `dueLeadWindowOff` | — | `"Off (never auto-prioritize)"` | `"Aus (nie automatisch priorisieren)"` |
| `dueLeadWindowAtDue` | — | `"At deadline (0 hours)"` | `"Bei Fälligkeit (0 Stunden)"` |
| `dueLeadWindow12Hours` | — | `"12 hours before deadline"` | `"12 Stunden vor Fälligkeit"` |
| `dueLeadWindow24Hours` | — | `"24 hours before deadline (Default)"` | `"24 Stunden vor Fälligkeit (Standard)"` |
| `dueLeadWindow48Hours` | — | `"48 hours before deadline"` | `"48 Stunden vor Fälligkeit"` |
| `dueLeadWindow7Days` | — | `"7 days before deadline"` | `"7 Tage vor Fälligkeit"` |
| `dueLeadWindowShort12Hours` | — | `"12 h"` | `"12 Std."` |
| `dueLeadWindowShort24Hours` | — | `"24 h"` | `"24 Std."` |
| `dueLeadWindowShort48Hours` | — | `"48 h"` | `"48 Std."` |
| `dueLeadWindowShort7Days` | — | `"7 d"` | `"7 Tg."` |
| `taskDueAutoPrioritizeLabel` | — | `"Auto-prioritize near deadline"` | `"Bei nahender Fälligkeit priorisieren"` |
| `taskDueAutoPrioritizeSubtitle` | — | `"Pull ahead of regular queued tasks once the lead window opens."` | `"Ab Beginn der Vorlaufzeit vor reguläre Aufgaben ziehen."` |
| `taskInfoDueAutoPromotedActive` | — | `"Prioritized by deadline lead window"` | `"Durch Fälligkeits-Vorlaufzeit priorisiert"` |
| `taskInfoDueAutoPromoteAtDue` | — | `"Auto-prioritizes at deadline"` | `"Automatische Priorisierung bei Fälligkeit"` |
| `taskInfoDueAutoPromoteScheduled` | `window: String` | `"Auto-prioritizes {window} before deadline"` | `"Automatische Priorisierung {window} vor Fälligkeit"` |
| `taskInfoDuePassiveHint` | — | `"Informational deadline (auto-priority off)"` | `"Informativer Termin (Auto-Priorität aus)"` |
| `taskInfoDueLeadWindowOffHint` | — | `"Deadline auto-priority disabled in settings"` | `"Fälligkeits-Priorisierung in Einstellungen deaktiviert"` |

*(Total: `20` new ARB keys across `app_en.arb` and `app_de.arb`, with `@taskInfoDueAutoPromoteScheduled` declaring `"placeholders": { "window": { "type": "String" } }`.)*

### 2.3 Implementation Details

#### 2.3.1 `DueLeadWindow` & `WebDavConfig` (`lib/models/webdav_config.dart`)
Place `DueLeadWindow` alphabetically between `AppTimeZoneMode` and `StorageMode` (`AGENTS.md` Section 2.5):
```dart
/// Per-workspace lead horizon before `due` during which non-`passive` open
/// queued tasks gain derived effective priority (`spec/TDF_SPEC_0.7.0.md` Section 5.5).
enum DueLeadWindow {
  /// Disables deadline-driven effective priority (`W_due = null`).
  off(id: 0, duration: null),

  /// Enables effective priority at exact deadline arrival (`W_due = 0s`).
  atDue(id: 1, duration: Duration.zero),

  /// Enables effective priority `12 hours` (`43,200s`) before `due`.
  hours12(id: 2, duration: Duration(hours: 12)),

  /// Normative default lead window of `24 hours` (`86,400s`) before `due`.
  hours24(id: 3, duration: Duration(hours: 24)),

  /// Enables effective priority `48 hours` (`172,800s`) before `due`.
  hours48(id: 4, duration: Duration(hours: 48)),

  /// Enables effective priority `7 days` (`604,800s`) before `due`.
  days7(id: 5, duration: Duration(days: 7));

  const DueLeadWindow({required this.id, required this.duration});

  /// Lead-window duration passed to [TaskBoard], or `null` when [off].
  final Duration? duration;

  /// Compact 1-byte identifier (`0..5`) persisted in `TTW\x02` workspace records.
  final int id;

  /// Resolves a [DueLeadWindow] from its persisted 1-byte [rawId], defaulting
  /// unknown values to [DueLeadWindow.hours24].
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
On `WebDavConfig`:
* Constructor parameter: `this.dueLeadWindow = DueLeadWindow.hours24`.
* Final field: `final DueLeadWindow dueLeadWindow;`.
* Include `DueLeadWindow? dueLeadWindow` in `copyWith`, `other.dueLeadWindow == dueLeadWindow` in `operator ==`, `dueLeadWindow` in `Object.hash(...)` in `hashCode`, and `'dueLeadWindow: ${dueLeadWindow.name}'` in `toString()`.

#### 2.3.2 Domain `isDuePassive` Reset Alignment (`lib/models/task_board_queue_mutator.dart`, `lib/models/task_board_mutator.dart`)
* **`TaskBoardQueueMutator.scheduleTask` (`lib/models/task_board_queue_mutator.dart`):**
  - Per `spec/TDF_SPEC_0.7.0.md` Sections 6.2 (`If explicitly promoting to Focus (priority set to true), also reset occurrence-scoped passive on due to omitted (false) and advance task.modified`) and 6.5 (`Remove finished, suspended ..., and due (including passive and any due note)`), compute `final nextDuePassive = (wasCompleted || isPriority) ? false : existing.isDuePassive;`, include `nextDuePassive != existing.isDuePassive` in `taskAttributesChanged`, and pass `clearDueAt: wasCompleted`, `clearDueNote: wasCompleted`, and `isDuePassive: nextDuePassive` into `existing.copyWith(...)`.
* **`TaskBoardMutator.updateTask` (`lib/models/task_board_mutator.dart`):**
  - Per `spec/TDF_SPEC_0.7.0.md` Section 6.6 (`explicitly setting priority to true also resets passive to omitted (false)`), define `final explicitlyPromotedPriority = (isPriority == true || targetTier == TaskTier.focus) && nextPriority;`.
  - Compute `nextIsDuePassive`:
    ```dart
    final nextIsDuePassive = normalizedNextDueAt == null
        ? false
        : (prior != null &&
                  normalizedNextDueAt == normalizedPriorDueAt &&
                  !explicitlyPromotedPriority
              ? (isDuePassive ?? prior.isDuePassive)
              : (isDuePassive ?? false));
    ```
    Thus, explicitly promoting a task to `priority` when `isDuePassive` is omitted (`null`) resets a prior `isDuePassive == true` to `false`, while still honoring an explicit `isDuePassive: true` argument when the caller intentionally marks a priority task's deadline informational.

#### 2.3.3 Acyclic Provider Wiring (`lib/providers/config_providers.dart`, `lib/providers/sync_providers.dart`, `lib/providers/task_providers.dart`)
* **`lib/providers/config_providers.dart` (`P-ACYCLIC-DAG` — does NOT import `task_providers.dart`):**
  - Declare top-level `boundaryTickProvider`:
    ```dart
    /// Monotonic tick counter incremented when a wall-clock task boundary fires or
    /// when the application resumes to the foreground.
    final boundaryTickProvider = NotifierProvider<BoundaryTickNotifier, int>(
      BoundaryTickNotifier.new,
    );
    ```
    with `class BoundaryTickNotifier extends Notifier<int>` (`@override int build() => 0;` and `void increment() => state++;`).
  - Add `Future<void> updateDueLeadWindow(DueLeadWindow dueLeadWindow)` on `WebDavConfigNotifier` delegating to `updateConfig(current.copyWith(dueLeadWindow: dueLeadWindow))`, and add `'due_lead': newConfig.dueLeadWindow.name` to the `config.update` `AppLogger.event` fields in `updateConfig`.
* **`lib/providers/sync_providers.dart` (`TaskSyncPipeline`):**
  - Forward `dueLeadWindow: config.dueLeadWindow.duration` into every board evaluation, stamping, and merge operation so loading, importing, local-file watching, and WebDAV CAS merging never revert tier slices to `24h`:
    1. `importLegacyTdf`: `TdfImporter.importDocument(..., dueLeadWindow: config.dueLeadWindow.duration)` and `TaskBoardSync.stampAndNormalize(..., dueLeadWindow: config.dueLeadWindow.duration)`.
    2. `_parseTdf`: `_tdfService.parse(..., dueLeadWindow: config.dueLeadWindow.duration)`.
    3. `_synchronizeLocalStage`, `_mergeRemoteSnapshot`, `_retryCasMergeStep`, `_retryRemoteCasMergeStep`, `_synchronizeRemoteStage`, `_scopeCandidateAndBaseline`: forward `dueLeadWindow: config.dueLeadWindow.duration` to every `TaskBoardSync.merge(...)` and `TaskBoardSync.stampAndNormalize(...)` call.
    4. `_rebaseCandidateToGeneration`, `_restorePreCleanupBystanderTasks`, and `_scopeBaselineToCandidateOrigin`: accept `Duration? dueLeadWindow` and forward `dueLeadWindow: dueLeadWindow` to `TaskBoard.evaluate(...)`.
* **`lib/providers/task_providers.dart` (`TaskNotifier`):**
  - Add private getter `Duration? get _currentDueLeadWindow => resolveCurrentConfig(ref).dueLeadWindow.duration;`.
  - In `TaskNotifier.build()`:
    1. Synchronously before the first `await` in `build()`, register `ref.listen<DueLeadWindow?>(webDavConfigProvider.select((asyncConfig) => asyncConfig.asData?.value.dueLeadWindow), _handleDueLeadWindowChanged);` so zero emissions are missed while `selectAsync` resolves.
    2. Normalize `dueLeadWindow: DueLeadWindow.hours24` alongside `localWatchEnabled: true` inside `ref.watch(webDavConfigProvider.selectAsync((config) => config.copyWith(localWatchEnabled: true, dueLeadWindow: DueLeadWindow.hours24)))` so changing `dueLeadWindow` within the active workspace NEVER triggers `TaskNotifier.build()` (`AsyncLoading` or storage reload/sync I/O).
    3. `_handleDueLeadWindowChanged(DueLeadWindow? previous, DueLeadWindow? next)`: if `next == null || previous == next`, if `ref.read(activeWorkspaceProvider).asData?.value.id != _undoWorkspaceId` (preventing cross-workspace emissions during workspace activation from re-evaluating the outgoing workspace's board), or if `state` is not `AsyncData<TaskBoard>`, return; compute `final (utcNow, localNow) = _resolveTimestamps(null);` and update `state = AsyncData(currentBoard.applyAutoPull(currentDate: utcNow, localEvaluationTime: localNow, timeZone: _resolveTimeZone(utcNow), dueLeadWindow: next.duration))` in memory with zero persistence I/O, logging `AppLogger.event(LogLevel.debug, LogTag.domain, 'domain.lead_window.reevaluated', fields: <String, Object?>{'due_lead': next.name})` when `AppLogger.shouldLog(LogLevel.debug)`.
    4. After any async `synchronize(...)` / `importLegacyTdf(...)` `await` gap (`build`, `refresh`, `_persistCurrentBoard`, `_consumeTriggeredWatchReload`, `_applyExternalReconciledBoard`), if the active workspace's live `resolveCurrentConfig(ref).dueLeadWindow` changed while the sync was in flight, re-apply `board.applyAutoPull(currentDate: utcNow, localEvaluationTime: localNow, timeZone: _resolveTimeZone(utcNow), dueLeadWindow: _currentDueLeadWindow)` before assigning `state = AsyncData(...)`.
  - Forward `dueLeadWindow: _currentDueLeadWindow` across all `20` board mutation and undo methods on `TaskNotifier`: `addLabel`, `addLocation`, `addTask`, `addTaskHistoryEntry`, `blockTask`, `completeTask`, `deleteLabel`, `deleteLocation`, `deleteTask`, `downgradeTask`, `moveTaskInQueue`, `removeTaskHistoryEntry`, `restoreTask`, `scheduleTask`, `toggleSubtask`, `undoLastAction` (`TaskBoardUndo.apply`), `updateLabel`, `updateLocation`, `updateTask`, and `updateTaskHistoryEntry`.

#### 2.3.4 `SettingsScreen` & `DueLeadWindowSelectionCard` (`lib/ui/settings_screen.dart`, `lib/ui/widgets/settings_preference_cards.dart`)
* In `lib/ui/widgets/settings_preference_cards.dart`:
  - Inside `SettingsPreferenceCards.build` (`Column(spacing: 10, ...)`), render `DueLeadWindowSelectionCard(selectedDueLeadWindow: config.dueLeadWindow, onDueLeadWindowChanged: (value) => onPreferenceChanged(config.copyWith(dueLeadWindow: value)))` immediately below `TimeZoneSelectionCard` without altering `SettingsPreferenceCards`'s `(config, onPreferenceChanged)` constructor signature.
  - Place `class DueLeadWindowSelectionCard extends StatelessWidget` alphabetically between `DiagnosticsSelectionCard` and `LanguageSelectionCard` (`AGENTS.md` Section 2.5), using `SettingsSectionCard` (`icon: Icons.hourglass_top_rounded`, `title: localizations.dueLeadWindowSectionTitle`, `description: localizations.dueLeadWindowSectionDescription`) and `KeyedSubtree(key: ValueKey(selectedDueLeadWindow), child: DropdownButtonFormField<DueLeadWindow>(key: const ValueKey('settings_due_lead_window_dropdown'), initialValue: selectedDueLeadWindow, decoration: InputDecoration(labelText: localizations.dueLeadWindowLabel, prefixIcon: const Icon(Icons.timer_outlined), border: const OutlineInputBorder()), items: ..., onChanged: ...))` mapping all `6` `DueLeadWindow.values` exhaustively (`P-EXHAUSTIVE-SWITCH`) and refreshing `FormField` state cleanly across workspace switches.
* In `lib/ui/settings_screen.dart`:
  - In `_SettingsScreenState._handlePreferenceChanged(WebDavConfig updatedConfig)`, detect `final dueLeadWindowChanged = updatedConfig.dueLeadWindow != _preferences.dueLeadWindow;` and dispatch `if (dueLeadWindowChanged) { await notifier.updateDueLeadWindow(updatedConfig.dueLeadWindow); }` alongside `diagnosticsChanged`, `localWatchChanged`, `logLevelChanged`, and `logStorageChanged` so unsaved WebDAV form edits are not persisted prematurely.

#### 2.3.5 `EditTaskScreen` & `TaskEditorSchedulingCard` (`lib/ui/edit_task_screen.dart`, `lib/ui/widgets/task_editor_scheduling_card.dart`)
* **`TaskEditorSchedulingCard` (`lib/ui/widgets/task_editor_scheduling_card.dart`):**
  - Add `this.autoPrioritizeDue = true`, `this.onToggleAutoPrioritizeDue`, and `this.showDueAutoPrioritizeToggle = false`.
  - When `hasDue && activeDueController != null && showDueAutoPrioritizeToggle`, render a dedicated private `StatelessWidget` (`_TaskEditorDueAutoPrioritizeRow`) directly below `TaskEditorSuspendedField` (`const SizedBox(height: 8)`), structured identically to `_LocalWatchToggleRow` (`Row(spacing: 12)` with `Expanded(Column(title, subtitle))` displaying `localizations.taskDueAutoPrioritizeLabel` and `localizations.taskDueAutoPrioritizeSubtitle`, followed by `Switch(key: const ValueKey('task_editor_due_auto_prioritize_switch'), value: autoPrioritizeDue, onChanged: onToggleAutoPrioritizeDue)`).
* **`EditTaskScreen` (`lib/ui/edit_task_screen.dart`):**
  - State fields on `_EditTaskScreenState`:
    - `late bool _autoPrioritizeDue;`
    - `bool _didUserToggleAutoPrioritizeDue = false;`
    - `late final DateTime? _initialDueAt;`
    - `late final String _initialDueText;`
  - In `initState()`:
    - `_hasDue = task?.dueAt != null;`
    - Format `_dueController` text using `if (task?.dueAt case final dueAt?) TaskItem.formatTdfTimestamp(dueAt) else ''` (avoiding `TaskEditorSuspendedField.formatInitialText`'s `defaultSuspendedAt` filter).
    - `_initialDueAt = task?.dueAt;`
    - `_initialDueText = _dueController.text.trim();`
    - `_autoPrioritizeDue = !(task?.isDuePassive ?? false);`
  - Helper `DateTime? _resolveCurrentEditorDueAt()`:
    - If `!_hasDue`, return `null`.
    - `final trimmed = _dueController.text.trim();`
    - If `trimmed == _initialDueText && _initialDueAt != null`, return `_initialDueAt`.
    - Return `TaskItem.tryParseTdfTimestampInput(trimmed)`.
  - Deterministic state transitions:
    1. `_handleDueChanged()` (invoked via `_dueController.addListener` on typing, clear button, date picker, and time picker):
       - Compute `final candidateDueAt = _resolveCurrentEditorDueAt();`.
       - Determine `final shouldResetAutoPrioritize = !_didUserToggleAutoPrioritizeDue && !_autoPrioritizeDue && candidateDueAt != null && !_isSameDueTimestamp(candidateDueAt, _initialDueAt);`.
       - If `_dueErrorMessage != null || shouldResetAutoPrioritize`, call `setState` clearing `_dueErrorMessage = null` and setting `if (shouldResetAutoPrioritize) _autoPrioritizeDue = true;`.
    2. `_toggleDue()`:
       - Flip `_hasDue = !_hasDue`. When `!_hasDue`, clear `_dueErrorMessage = null`, reset `_autoPrioritizeDue = true`, and reset `_didUserToggleAutoPrioritizeDue = false`.
    3. `_toggleAutoPrioritizeDue(bool value)`:
       - `setState(() { _autoPrioritizeDue = value; _didUserToggleAutoPrioritizeDue = true; });`
    4. `_toggleMode(QuickAddMode target)`:
       - Compute `final nextMode = _mode == target ? QuickAddMode.standard : target;`.
       - Inside `setState`, update `_mode = nextMode`, and if `nextMode == QuickAddMode.priority && !_didUserToggleAutoPrioritizeDue && !_autoPrioritizeDue`, set `_autoPrioritizeDue = true`.
  - In `_EditTaskSchedulingSection`: pass `autoPrioritizeDue: state._autoPrioritizeDue`, `showDueAutoPrioritizeToggle: !state._isCompletedTask`, `onToggleDue: state._toggleDue`, and `onToggleAutoPrioritizeDue: state._toggleAutoPrioritizeDue`.
  - In `_persistTask(_ValidatedTaskDraft draft)`:
    - For `updateTask`: compute `final isDuePassive = !_hasDue ? false : (_isCompletedTask && _isSameDueTimestamp(draft.dueAt, existingTask.dueAt) ? existingTask.isDuePassive : !_autoPrioritizeDue);` and pass `isDuePassive: isDuePassive`.
    - For `addTask`: pass `isDuePassive: _hasDue && !_autoPrioritizeDue`.

#### 2.3.6 `HomeScreen` Single Boundary Timer (`lib/ui/home_screen.dart`)
* Extract stateless helper `class HomeScreenBoundaryTimer` (`const HomeScreenBoundaryTimer._();`):
  - Constants:
    - `static const Duration minTimerDelay = Duration(milliseconds: 25);`
    - `static const Duration maxTimerChunk = Duration(days: 7);`
  - `static DateTime? nextBoundaryUtc({required Iterable<TaskItem> tasks, required DateTime nowUtc, required Duration? dueLeadWindow})`:
    - `final now = TaskItem.normalizeTimestamp(nowUtc);`
    - Single flat `for (final task in tasks)` loop (`< 25` lines, `P-LOOP-MODULARITY`, `P-NO-NESTED-LOOPS`) delegating per-task candidate extraction to `static DateTime? _earliestTaskBoundary(TaskItem task, DateTime now, Duration? dueLeadWindow)`:
      - If `task.isCompleted || task.completedAt != null`, return `null`.
      - Check finite deferral: if `!task.isSuspendedForever`, `task.suspendedAt case final suspendedAt?` when `suspendedAt != TaskItem.defaultSuspendedAt && suspendedAt.isAfter(now)`, update `candidate`.
      - Check deadline: if `task.dueAt case final dueAt?`:
        - If `dueLeadWindow != null && !task.isDuePassive`: compute `final leadStart = dueAt.subtract(dueLeadWindow);` and if `leadStart.isAfter(now)`, update `candidate`.
        - If `dueAt.isAfter(now)`, update `candidate`.
      - Return `candidate`.
  - `static Duration clampTimerDelay(Duration rawDelay)`:
    - Returns `minTimerDelay` when `rawDelay <= minTimerDelay`, `maxTimerChunk` when `rawDelay > maxTimerChunk`, and `rawDelay` otherwise.
* In `_HomeScreenState`:
  - Fields: `Timer? _boundaryTimer;`, `bool _isAppResumed = true;`, `AppLifecycleListener? _lifecycleListener;`, `DateTime? _scheduledBoundaryUtc;`.
  - In `initState()`: initialize `_lifecycleListener = AppLifecycleListener(onStateChange: _handleAppLifecycleStateChanged);` and schedule initial sync via `WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _syncBoundaryTimerFromProviders(); });`.
  - In `dispose()` (`P-DISPOSE-RESOURCES`): `_boundaryTimer?.cancel(); _lifecycleListener?.dispose();` alongside existing controllers.
  - In `_watchScaffoldState()` (alongside existing `activeWorkspaceProvider` and `taskUndoStateProvider` listeners so `_HomeScreenState.build` stays `< 40` lines per `P-FLATTEN-BUILD`): register `ref.listen<AsyncValue<TaskBoard>>(taskNotifierProvider, (_, _) => _syncBoundaryTimerFromProviders())`, `ref.listen<DueLeadWindow?>(webDavConfigProvider.select((c) => c.asData?.value.dueLeadWindow), (_, _) => _syncBoundaryTimerFromProviders())`, and `ref.listen<int>(boundaryTickProvider, (_, _) => _syncBoundaryTimerFromProviders())` so `_syncBoundaryTimer` runs deterministically on every board load/mutation, lead-window change, lifecycle resume, and boundary tick without mutating timers inside pure widget layout.
  - `_handleAppLifecycleStateChanged(AppLifecycleState state)`:
    - If `state == AppLifecycleState.resumed`: set `_isAppResumed = true`, call `ref.read(boundaryTickProvider.notifier).increment()`, and call `_syncBoundaryTimerFromProviders()`.
    - Otherwise (`inactive`, `hidden`, `paused`, `detached`): set `_isAppResumed = false`, cancel `_boundaryTimer`, and clear `_scheduledBoundaryUtc = null`.
  - `_syncBoundaryTimer(TaskBoard? board, WebDavConfig configuration)`:
    - If `!mounted || !_isAppResumed || board == null`, cancel `_boundaryTimer`, set `_scheduledBoundaryUtc = null`, and return.
    - Read `final rawUtcNow = ref.read(clockProvider)().toUtc();` and compute `final nextBoundary = HomeScreenBoundaryTimer.nextBoundaryUtc(tasks: board.allTasks, nowUtc: rawUtcNow, dueLeadWindow: configuration.dueLeadWindow.duration);`.
    - If `nextBoundary == _scheduledBoundaryUtc && (_boundaryTimer?.isActive ?? false)`, return.
    - Cancel `_boundaryTimer`, set `_scheduledBoundaryUtc = nextBoundary`, and if `nextBoundary != null`, arm `_boundaryTimer = Timer(HomeScreenBoundaryTimer.clampTimerDelay(nextBoundary.difference(rawUtcNow)), _handleBoundaryTimerFired);` and log `ui.boundary_timer.scheduled` when `AppLogger.shouldLog(LogLevel.debug)` (emitting only `'target_utc': nextBoundary.toIso8601String()` and `'delay_ms': delay.inMilliseconds`, zero task notes/titles per `P-SECRET-HYGIENE`).
  - `_handleBoundaryTimerFired()`:
    - If `!mounted || !_isAppResumed`, return.
    - Read `final rawUtcNow = ref.read(clockProvider)().toUtc();` and `final normalizedNow = TaskItem.normalizeTimestamp(rawUtcNow);`.
    - If `_scheduledBoundaryUtc case final target? when normalizedNow.isBefore(target)`:
      - Re-arm `_boundaryTimer = Timer(HomeScreenBoundaryTimer.clampTimerDelay(target.difference(rawUtcNow)), _handleBoundaryTimerFired);` and return without incrementing `boundaryTickProvider` (covers both `< 25 ms` sub-second early wakeups and multi-week `7-day` timer chunks).
    - Set `_scheduledBoundaryUtc = null`, log `ui.boundary_timer.fired` at `LogLevel.debug` when `AppLogger.shouldLog(LogLevel.debug)`, and call `ref.read(boundaryTickProvider.notifier).increment()` (which triggers `_LandingContentSwitcher`, `_TierTaskIndicators`, `TaskInfoDialog`, and `_syncBoundaryTimerFromProviders()` via `ref.listen`).

#### 2.3.7 `TierTaskPill` & `TaskInfoDialog` Urgency UI (`lib/ui/widgets/tier_task_pill.dart`, `lib/ui/widgets/task_info_dialog.dart`)
* **`lib/ui/widgets/tier_task_pill.dart`:**
  - Add `this.isCompleted = false` to `_TierTaskIndicators({required this.task, this.isCompleted = false})` and pass `_TierTaskIndicators(task: task, isCompleted: isCompleted)` from `_TierTaskPillRow._buildContentArea` (where `isCompleted` is `_TierTaskPillState._effectiveCompleted`).
  - Inside `_TierTaskIndicators`:
    - Watch `ref.watch(boundaryTickProvider);` in `build` (keeping `_TierTaskIndicators.build` `< 40` lines per `P-FLATTEN-BUILD`) so both `_resolveActiveSpecs` (`suspended_task_indicator`) and `_buildDueBadge` update live at wall-clock thresholds.
    - Inside `_buildDueBadge(BuildContext context, WidgetRef ref, AppLocalizations localizations, DateTime dueAt, Color mutedColor)`: watch `final configuration = ref.watch(webDavConfigProvider.select((c) => c.asData?.value)) ?? const WebDavConfig();` and `final normalizedNow = TaskItem.normalizeTimestamp(ref.watch(clockProvider)().toUtc());`, format the badge date as `localizations.pillDuePrefix(TaskItem.formatIsoDate(configuration.toLocalWallClock(dueAt)))`, and compute `dueBadgeColor` via `_resolveDueBadgeColor(context: context, task: task, dueAt: dueAt, normalizedNow: normalizedNow, dueLeadWindow: configuration.dueLeadWindow.duration, isCompleted: isCompleted, mutedColor: mutedColor)`:
      - Returns `mutedColor` if `isCompleted || task.isCompleted || task.completedAt != null`.
      - Returns `Theme.of(context).colorScheme.error` if `!dueAt.isAfter(normalizedNow)`.
      - Returns `AppTheme.of(context).warningAccent` if `task.isWithinDueLeadWindow(normalizedNow, dueLeadWindow)`.
      - Returns `mutedColor` otherwise.
* **`lib/ui/widgets/task_info_dialog.dart`:**
  - Watch `ref.watch(boundaryTickProvider);` in `TaskInfoDialog.build` so open dialogs refresh countdowns, overdue transitions, expired suspension visibility, and auto-priority status lines live.
  - Update `_buildDueSection` to compute `final normalizedNow = TaskItem.normalizeTimestamp(nowUtc);`, format `valueText` against `normalizedNow`, and resolve `details` via static helper `_buildDueStatusDetails(task, configuration, localizations, normalizedNow)` implementing the 6-branch exhaustive table from Section 1.4.4 (mapping `DueLeadWindow.hours12/hours24/hours48/days7` to `dueLeadWindowShort12Hours/24Hours/48Hours/7Days`).

### 2.4 Testing Strategy
1. **`test/models/app_workspace_test.dart`, `test/models/tdf_v050_primitives_test.dart`, `test/models/task_board_mutation_test.dart` & `test/models/task_board_lifecycle_test.dart` (`M-EXHAUSTIVE-STATE-TESTS`, `M-EXTREME-BOUND-TESTS`):**
   - Verify every `DueLeadWindow` variant (`off`, `atDue`, `hours12`, `hours24`, `hours48`, `days7`), `fromId(0..5)` plus fallback `fromId(99) == DueLeadWindow.hours24`, and `WebDavConfig` `copyWith` / `==` / `hashCode` / `toString`.
   - Round-trip all `6` `DueLeadWindow` variants through `AppWorkspace.encodePersistedState` / `toBytes` (`TTW\x02`, `52`-byte default single-workspace payload ending in `0x03`) and `AppWorkspace.decodePersistedState` / `fromBytes` across single and `32`-workspace (`maxWorkspaces`) payloads, updating the existing `51`-byte `toBytes()` assertion in `test/models/app_workspace_test.dart` to `52`-byte `TTW\x02` while retaining the `51`-byte legacy `TTW\x01` `fromBytes` compatibility test.
   - Construct raw legacy `TTW\x01` byte payloads (`version == 0x01`, omitting the trailing `dueLeadWindow` byte) and verify backward-compatible decoding to `DueLeadWindow.hours24`.
   - Verify `WorkspaceErrorKind.corruptPayload` on truncated `TTW\x02` records (missing `dueLeadWindow` byte), trailing garbage bytes, unsupported version `0x03`, out-of-range `dueLeadWindow` byte `0x06` / `0xFF`, and exact `65,536`-byte (`maxBinaryBytes`) boundary enforcement (`N`, `N + 1` bytes with the `TTW\x02` `+ 5` pre-allocation check).
   - Verify `TaskBoardQueueMutator.scheduleTask(id, isPriority: true)` (`Section 6.2`) and `TaskBoardMutator.updateTask(id, isPriority: true)` / `targetTier: TaskTier.focus` (`Section 6.6`) reset `isDuePassive: true` to `false` and advance `modifiedAt`, while explicit `updateTask(id, isPriority: true, isDuePassive: true)` preserves `isDuePassive: true`.
2. **`test/providers/config_providers_test.dart` & `test/providers/task_providers_test.dart` (`M-EXHAUSTIVE-STATE-TESTS`, `M-IO-TESTS`, `M-REAL-MECHANICS-TESTS`):**
   - Verify `WebDavConfigNotifier.updateDueLeadWindow` persists to `SettingsRepository`, survives workspace switches, updates `TaskNotifier` tier slices immediately in memory (`AsyncData` without `AsyncLoading`), and performs **zero** `.tdf` writes to `LocalFileRepository` or `WebDavRepository`.
   - Verify `TaskSyncPipeline` initial load, local-watch reload, and three-way WebDAV merge preserve non-default `DueLeadWindow` tier evaluation (`off`, `atDue`, `hours48`, `days7`) rather than reverting to `24h`.
   - Verify non-default `DueLeadWindow` forwarding across `downgradeTask` (urgent `due` within `7d` sets `isDuePassive = true` when downgraded under `days7`, whereas under `off` it leaves `isDuePassive = false`), `scheduleTask`, `moveTaskInQueue`, `completeTask`, `restoreTask`, and `undoLastAction`.
   - Exercise real mid-flight async persistence/sync (`Completer` suspended across `await`, `M-REAL-MECHANICS-TESTS`): change `dueLeadWindow` or switch between Workspace A (`DueLeadWindow.off`) and Workspace B (`DueLeadWindow.days7`) while sync is suspended and verify the resolved `TaskBoard` reflects the active workspace's `DueLeadWindow`.
3. **`test/ui/settings_screen_test.dart` & `test/ui/edit_task_screen_test.dart` (`M-EXHAUSTIVE-STATE-TESTS`, `M-EXTREME-BOUND-TESTS`):**
   - Verify selecting every `DueLeadWindow` option in `settings_due_lead_window_dropdown` in both `en` and `de` locales.
   - Verify `task_editor_due_auto_prioritize_switch`:
     1. Hidden when `hasDue` is `false` and hidden on `Completed` tasks; visible when `hasDue` is `true` on new and open tasks.
     2. Initializes `false` when editing an open `due ... passive` task and preserves `isDuePassive == true` + sub-minute `:SS` seconds (`e.g. 14:30:45`) and `9999-12-31 23:59:59` when `due` is untouched.
     3. Automatically resets to `true` (`isDuePassive == false`) when `dueAt` changes to a different timestamp or when `Priority` chip is toggled on without manual switch interaction.
     4. Honors manual user switch override (`isDuePassive == true` on `addTask` and `updateTask`, including when `dueAt` is edited after manual toggle or toggled off after `dueAt` change).
4. **`test/ui/home_screen_test.dart`, `test/ui/widgets/tier_task_pill_test.dart` & `test/ui/widgets/task_info_dialog_test.dart` (`M-EXTREME-BOUND-TESTS`, `M-REAL-MECHANICS-TESTS`):**
   - Controlled fake clock + `tester.pump(duration)` tests verifying live single-timer mechanics in `HomeScreen`:
     1. Open task in `Planned` automatically pulls into `Focus` and `due_task_badge_<id>` switches to `warningAccent` at exact `dueAt - W_due`.
     2. Open already-focused task, `passive` task, and `DueLeadWindow.off` task transition `due_task_badge_<id>` (despite `const` parent rebuilds) and open `TaskInfoDialog` live to `colorScheme.error` / overdue status at exact `dueAt`.
     3. Deferred task in `Blocked` wakes into `Focus`/`Ready` and hides `suspended_task_indicator_<id>` at exact `suspendedAt`.
     4. Sub-second early wakeup (`rawUtcNow = 16:59:59.990Z` for `targetBoundary = 17:00:00Z`) re-arms for `>= 25 ms` without premature promotion at `16:59:59Z` and promotes cleanly once clock reaches `17:00:00.015Z`.
     5. Far-future `dueAt = 9999-12-31 23:59:59Z` clamps single `Timer` delay to `7 days` (`maxTimerChunk`) without overflow or premature tick.
     6. `AppLifecycleState.paused` cancels the active `Timer`, and `AppLifecycleState.resumed` immediately increments `boundaryTickProvider`, catches up crossed thresholds, and schedules the next boundary.
   - Verify `Completed` tasks and open tasks mid-completion exit animation keep muted `due_task_badge_<id>` styling even when `dueAt <= nowUtc`, verify local wall-clock date formatting on `due_task_badge_<id>` under non-UTC offset configs, and verify all `6` `TaskInfoDialog._buildDueSection` auto-priority detail branches (`completed`, `passive`, `off`, `active`, `atDue`, and scheduled `12h`/`24h`/`48h`/`7d`) in `en` and `de`.

## Part 3: Implementation Record & Tasks

### 3.1 Task Breakdown
- [x] Run `python3 .agents/scripts/tiertask_dev.py verify --fast` to confirm a clean baseline.
- [x] Add all `20` English and German localization keys to `lib/l10n/app_en.arb` and `lib/l10n/app_de.arb` via `tiertask_dev.py l10n --set` (with placeholder metadata for `taskInfoDueAutoPromoteScheduled`) and run `flutter gen-l10n`.
- [x] Write failing unit and widget tests in `test/models/app_workspace_test.dart`, `test/models/location_state_test.dart`, `test/models/tdf_v050_primitives_test.dart`, `test/models/task_board_mutation_test.dart`, `test/models/task_board_lifecycle_test.dart`, `test/providers/config_providers_test.dart`, `test/providers/task_providers_test.dart`, `test/ui/settings_screen_test.dart`, `test/ui/edit_task_screen_test.dart`, `test/ui/home_screen_test.dart`, `test/ui/widgets/tier_task_pill_test.dart`, and `test/ui/widgets/task_info_dialog_test.dart` (TDD Red Phase — `P-TDD-FIRST`).
- [x] Implement `DueLeadWindow` in `lib/models/webdav_config.dart`, `TTW\x02` persistence in `lib/models/app_workspace.dart`, Section 6.2/6.6 `isDuePassive` resets in `lib/models/task_board_queue_mutator.dart` and `lib/models/task_board_mutator.dart`, acyclic provider wiring (`boundaryTickProvider`, `updateDueLeadWindow`, `TaskSyncPipeline`, `TaskNotifier`) in `lib/providers/`, `DueLeadWindowSelectionCard` in `lib/ui/widgets/settings_preference_cards.dart` and `lib/ui/settings_screen.dart`, `Auto-prioritize near deadline` switch in `lib/ui/widgets/task_editor_scheduling_card.dart` and `lib/ui/edit_task_screen.dart`, `HomeScreenBoundaryTimer` in `lib/ui/home_screen.dart`, and urgency badges/status in `lib/ui/widgets/tier_task_pill.dart` and `lib/ui/widgets/task_info_dialog.dart` (TDD Green & Refactor Phase).
- [x] Update Parts 1 and 2 if implementation details evolve during development.
- [x] Synchronize `ARCHITECTURE.md`, `README.md`, and `AGENTS.md` per **`update-documentation`**.
- [x] Update `CHANGELOG.md` under `## [Unreleased]` per **`changelog-updater`**.
- [x] Run `python3 .agents/scripts/tiertask_dev.py arch --sync-tree` and `python3 .agents/scripts/tiertask_dev.py verify --full --fix`.
- [x] Set `status: review`, update `BOARD.md`, and request user approval.
- [x] After user approval, set `status: completed`, update `BOARD.md`, and list delivered artifacts in Part 3.3.

### 3.2 Work Log & Decisions
* **2026-11-14:** Drafted initial concept (`status: concept`) for configurable `DueLeadWindow` preferences (`TTW\x02`), deterministic `Auto-prioritize near deadline` editor toggle, `HomeScreen` live boundary timer, and deadline urgency indicators on top of `TEP-006` (`spec/TDF_SPEC_0.7.0.md` Topic 2).
* **2026-11-15:** Elaborated complete technical design (`status: planned`): enforced `P-ACYCLIC-DAG` via `ref.listen` in `TaskNotifier` and `boundaryTickProvider` in `config_providers.dart`; specified full `TaskSyncPipeline` and `20`-method `TaskNotifier` `dueLeadWindow` forwarding; aligned explicit `priority` promotion `isDuePassive` resets with `spec/TDF_SPEC_0.7.0.md` Sections 6.2 and 6.6; specified `TTW\x02` `+ 5` pre-allocation `maxBinaryBytes` bound check; added `7-day` `Timer` chunk clamping for `<= 9999` timestamps; and defined the `6`-branch `TaskInfoDialog` status decision table and `M-*` TDD test matrix.
* **2026-11-15:** Completed Red-Green-Refactor TDD implementation across localization (`app_en.arb`, `app_de.arb`), models (`DueLeadWindow`, `TTW\x02` binary workspace records with `TTW\x01` compatibility, and Sections 6.2/6.6 `isDuePassive` resets), acyclic providers (`boundaryTickProvider`, `updateDueLeadWindow`, `TaskSyncPipeline`, and `TaskNotifier` in-memory lead-window re-evaluation), and UI (`DueLeadWindowSelectionCard`, `task_editor_due_auto_prioritize_switch` with lossless `TaskItem.formatTdfTimestamp` initial formatting, `HomeScreenBoundaryTimer` single lifecycle-aware wall-clock timer, `TierTaskPill` local wall-clock urgency badge colors, and `TaskInfoDialog` 6-branch deadline status lines). Synchronized `ARCHITECTURE.md`, `README.md`, and `CHANGELOG.md`, verified `tiertask_dev.py verify --full --fix`, and transitioned proposal to `status: review`.
* **2026-11-16:** Approved by user and marked `completed`.

### 3.3 Delivered Artifacts
* **Domain Models (`lib/models/`):** [`lib/models/app_workspace.dart`](../../lib/models/app_workspace.dart), [`lib/models/task_board_mutator.dart`](../../lib/models/task_board_mutator.dart), [`lib/models/task_board_queue_mutator.dart`](../../lib/models/task_board_queue_mutator.dart), [`lib/models/webdav_config.dart`](../../lib/models/webdav_config.dart).
* **State Providers (`lib/providers/`):** [`lib/providers/config_providers.dart`](../../lib/providers/config_providers.dart), [`lib/providers/sync_providers.dart`](../../lib/providers/sync_providers.dart), [`lib/providers/task_providers.dart`](../../lib/providers/task_providers.dart).
* **Localization & UI (`lib/l10n/`, `lib/ui/`):** [`lib/l10n/app_en.arb`](../../lib/l10n/app_en.arb), [`lib/l10n/app_de.arb`](../../lib/l10n/app_de.arb), [`lib/ui/edit_task_screen.dart`](../../lib/ui/edit_task_screen.dart), [`lib/ui/home_screen.dart`](../../lib/ui/home_screen.dart), [`lib/ui/settings_screen.dart`](../../lib/ui/settings_screen.dart), [`lib/ui/widgets/settings_preference_cards.dart`](../../lib/ui/widgets/settings_preference_cards.dart), [`lib/ui/widgets/task_editor_scheduling_card.dart`](../../lib/ui/widgets/task_editor_scheduling_card.dart), [`lib/ui/widgets/task_info_dialog.dart`](../../lib/ui/widgets/task_info_dialog.dart), [`lib/ui/widgets/tier_task_pill.dart`](../../lib/ui/widgets/tier_task_pill.dart).
* **Tests & Documentation:** [`test/models/app_workspace_test.dart`](../../test/models/app_workspace_test.dart), [`test/models/task_board_lifecycle_test.dart`](../../test/models/task_board_lifecycle_test.dart), [`test/models/task_board_mutation_test.dart`](../../test/models/task_board_mutation_test.dart), [`test/models/tdf_v050_primitives_test.dart`](../../test/models/tdf_v050_primitives_test.dart), [`test/providers/config_providers_test.dart`](../../test/providers/config_providers_test.dart), [`test/providers/task_providers_test.dart`](../../test/providers/task_providers_test.dart), [`test/ui/edit_task_screen_test.dart`](../../test/ui/edit_task_screen_test.dart), [`test/ui/home_screen_test.dart`](../../test/ui/home_screen_test.dart), [`test/ui/settings_screen_test.dart`](../../test/ui/settings_screen_test.dart), [`test/ui/widgets/task_info_dialog_test.dart`](../../test/ui/widgets/task_info_dialog_test.dart), [`test/ui/widgets/tier_task_pill_test.dart`](../../test/ui/widgets/tier_task_pill_test.dart), [`ARCHITECTURE.md`](../../ARCHITECTURE.md), [`README.md`](../../README.md), [`CHANGELOG.md`](../../CHANGELOG.md).
