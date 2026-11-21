// TierTask
// Copyright (C) 2026  Stefan Stark
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option)
// any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with
// this program.  If not, see <https://www.gnu.org/licenses/>.

import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/task_board.dart';
import '../models/task_item.dart';
import '../models/task_tier.dart';
import '../models/tdf_error.dart';
import '../models/tdf_metadata.dart';
import '../models/tdf_sync_metadata.dart';
import '../models/tdf_timezone.dart';
import '../models/webdav_config.dart';
import '../providers/config_providers.dart';
import '../providers/task_providers.dart';
import '../services/app_logger.dart';

/// Provides [TaskEditorController] for task draft resolution, validation, persistence, and telemetry.
final taskEditorControllerProvider = Provider<TaskEditorController>(
  TaskEditorController.new,
);

/// Sealed outcome returned by [TaskEditorController.submitDraft].
sealed class TaskEditorSubmitResult {
  /// Creates a [TaskEditorSubmitResult].
  const TaskEditorSubmitResult();
}

/// Outcome returned when domain persistence rejects a validated task draft.
@immutable
final class TaskEditorPersistFailed extends TaskEditorSubmitResult {
  /// Creates a [TaskEditorPersistFailed] outcome with field [errors] and optional [committedHistoryEntries].
  TaskEditorPersistFailed({
    required this.errors,
    Iterable<TaskHistoryEntry>? committedHistoryEntries,
  }) : committedHistoryEntries = committedHistoryEntries == null
           ? null
           : List<TaskHistoryEntry>.unmodifiable(committedHistoryEntries);

  /// Normalized history list when a pending history draft was folded in prior to persistence failure.
  final List<TaskHistoryEntry>? committedHistoryEntries;

  /// Mapped inline field errors surfaced back to the task editor screen.
  final TaskEditorFieldErrors errors;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TaskEditorPersistFailed &&
        other.errors == errors &&
        listEquals(other.committedHistoryEntries, committedHistoryEntries);
  }

  @override
  int get hashCode => Object.hash(errors, switch (committedHistoryEntries) {
    final entries? => Object.hashAll(entries),
    null => null,
  });
}

/// Outcome returned when the task draft passes validation and persists cleanly.
@immutable
final class TaskEditorSubmitted extends TaskEditorSubmitResult {
  /// Creates a [TaskEditorSubmitted] outcome.
  const TaskEditorSubmitted();
}

/// Outcome returned when form validation rejects a task draft before persistence.
@immutable
final class TaskEditorValidationFailed extends TaskEditorSubmitResult {
  /// Creates a [TaskEditorValidationFailed] carrying per-field [errors].
  const TaskEditorValidationFailed(this.errors);

  /// Per-field localized validation errors.
  final TaskEditorFieldErrors errors;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TaskEditorValidationFailed && other.errors == errors;
  }

  @override
  int get hashCode => errors.hashCode;
}

/// Immutable resolution state for the task editor `due` timestamp input.
@immutable
class ResolvedDueDraft {
  /// Creates a [ResolvedDueDraft].
  const ResolvedDueDraft({
    required this.dueAt,
    required this.dueLocalInput,
    required this.dueAnchor,
    required this.isUnchanged,
    required this.isValid,
  });

  /// Preserved or newly derived local wall-clock anchor (`due.anchor`).
  final TdfLocalDateTime? dueAnchor;

  /// Resolved UTC due instant, or `null` when disabled or invalid.
  final DateTime? dueAt;

  /// Newly parsed local wall-clock input when edited, or `null` when unchanged or disabled.
  final TdfLocalDateTime? dueLocalInput;

  /// Whether the edited text exactly matched the initial formatted baseline.
  final bool isUnchanged;

  /// Whether the draft is valid (including when `hasDue` is `false`).
  final bool isValid;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ResolvedDueDraft &&
        other.dueAt == dueAt &&
        other.dueLocalInput == dueLocalInput &&
        other.dueAnchor == dueAnchor &&
        other.isUnchanged == isUnchanged &&
        other.isValid == isValid;
  }

  @override
  int get hashCode =>
      Object.hash(dueAt, dueLocalInput, dueAnchor, isUnchanged, isValid);
}

/// Immutable resolution state for the task editor `suspended` timestamp input.
@immutable
class ResolvedSuspendedDraft {
  /// Creates a [ResolvedSuspendedDraft].
  const ResolvedSuspendedDraft({
    required this.suspendedAt,
    required this.suspendedLocalInput,
    required this.isForever,
    required this.isValid,
  });

  /// Whether the task is suspended indefinitely (`suspended forever`).
  final bool isForever;

  /// Whether the draft is valid (including when `isSuspended` is `false`).
  final bool isValid;

  /// Preserved UTC instant when unchanged, or `null` when edited, forever, or disabled.
  final DateTime? suspendedAt;

  /// Newly parsed local wall-clock input when edited, or `null` when unchanged, forever, or disabled.
  final TdfLocalDateTime? suspendedLocalInput;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ResolvedSuspendedDraft &&
        other.suspendedAt == suspendedAt &&
        other.suspendedLocalInput == suspendedLocalInput &&
        other.isForever == isForever &&
        other.isValid == isValid;
  }

  @override
  int get hashCode =>
      Object.hash(suspendedAt, suspendedLocalInput, isForever, isValid);
}

/// Immutable snapshot of all task editor form inputs submitted to [TaskEditorController.submitDraft].
@immutable
class TaskEditorDraftInput {
  /// Creates a [TaskEditorDraftInput].
  TaskEditorDraftInput({
    required this.autoFinish,
    required this.autoPrioritizeDue,
    required this.board,
    required Iterable<TaskCondition> conditions,
    required this.configuration,
    required this.editingHistoryIndex,
    required this.editingHistoryInitialTimestampText,
    required this.editingHistoryOriginalEntry,
    required this.existingTask,
    required this.hasDue,
    required Iterable<TaskHistoryEntry> historyEntries,
    required this.initialDueAnchor,
    required this.initialDueAt,
    required this.initialDueNote,
    required this.initialDueText,
    required this.initialEditorMode,
    required this.initialSuspendedAt,
    required this.initialSuspendedNote,
    required this.initialSuspendedText,
    required this.isRepeating,
    required this.isSuspended,
    required Iterable<TaskLink> links,
    required this.mode,
    required this.pendingSubtaskText,
    required this.rawDueNote,
    required this.rawDueText,
    required this.rawHistoryText,
    required this.rawHistoryTimestamp,
    required this.rawNote,
    required this.rawRepeatCount,
    required this.rawRepeatLeadDays,
    required this.rawSuspendedNote,
    required this.rawSuspendedText,
    required this.rawTitle,
    required this.repeatUnit,
    required Iterable<String> selectedBlockedByIds,
    required Iterable<String> selectedLabelIds,
    required Iterable<SubtaskItem> subtasks,
  }) : conditions = List<TaskCondition>.unmodifiable(conditions),
       historyEntries = List<TaskHistoryEntry>.unmodifiable(historyEntries),
       links = List<TaskLink>.unmodifiable(links),
       selectedBlockedByIds = Set<String>.unmodifiable(selectedBlockedByIds),
       selectedLabelIds = Set<String>.unmodifiable(selectedLabelIds),
       subtasks = List<SubtaskItem>.unmodifiable(subtasks);

  /// Whether completing all subtasks automatically completes the parent task.
  final bool autoFinish;

  /// Whether deadline lead-window auto-prioritization is enabled (`!isDuePassive`).
  final bool autoPrioritizeDue;

  /// Current board snapshot used for uniqueness and canonical ordering.
  final TaskBoard board;

  /// Built activation conditions from the condition editor.
  final List<TaskCondition> conditions;

  /// Active workspace configuration supplying wall-clock time zone conversion.
  final WebDavConfig configuration;

  /// Index of an actively edited history entry, or `null` when appending.
  final int? editingHistoryIndex;

  /// Formatted local timestamp string captured when editing started, or `null`.
  final String? editingHistoryInitialTimestampText;

  /// Original history entry captured when editing started, or `null`.
  final TaskHistoryEntry? editingHistoryOriginalEntry;

  /// Existing task being edited, or `null` when creating a new task.
  final TaskItem? existingTask;

  /// Whether deadline scheduling is enabled.
  final bool hasDue;

  /// Committed draft history entries currently displayed in the editor list.
  final List<TaskHistoryEntry> historyEntries;

  /// Initial `due.anchor` captured on open.
  final TdfLocalDateTime? initialDueAnchor;

  /// Initial UTC `dueAt` captured on open.
  final DateTime? initialDueAt;

  /// Initial deadline note captured on open.
  final String? initialDueNote;

  /// Initial formatted due timestamp baseline.
  final String initialDueText;

  /// Initial [QuickAddMode] derived when the editor opened.
  final QuickAddMode initialEditorMode;

  /// Initial UTC `suspendedAt` captured on open.
  final DateTime? initialSuspendedAt;

  /// Initial deferral note captured on open.
  final String? initialSuspendedNote;

  /// Initial formatted suspended timestamp baseline.
  final String initialSuspendedText;

  /// Whether recurrence is enabled.
  final bool isRepeating;

  /// Whether deferral is enabled.
  final bool isSuspended;

  /// Reference links attached to the task (after flushing any pending link input).
  final List<TaskLink> links;

  /// Active [QuickAddMode] selection.
  final QuickAddMode mode;

  /// Uncommitted text in the subtask input field.
  final String pendingSubtaskText;

  /// Raw text in the deadline note field.
  final String rawDueNote;

  /// Raw text in the deadline timestamp field.
  final String rawDueText;

  /// Raw text in the pending history text field.
  final String rawHistoryText;

  /// Raw text in the pending history timestamp field.
  final String rawHistoryTimestamp;

  /// Raw text in the task body note field.
  final String rawNote;

  /// Raw text in the repeat interval count field.
  final String rawRepeatCount;

  /// Raw text in the Mode 2 repeat lead-days field.
  final String rawRepeatLeadDays;

  /// Raw text in the deferral note field.
  final String rawSuspendedNote;

  /// Raw text in the deferral timestamp field.
  final String rawSuspendedText;

  /// Raw text in the task title field.
  final String rawTitle;

  /// Selected recurrence [RepeatUnit].
  final RepeatUnit repeatUnit;

  /// Selected prerequisite task IDs.
  final Set<String> selectedBlockedByIds;

  /// Selected label IDs.
  final Set<String> selectedLabelIds;

  /// Committed draft subtasks currently displayed in the editor list.
  final List<SubtaskItem> subtasks;
}

/// Immutable per-field validation or persistence error messages for the task editor.
@immutable
class TaskEditorFieldErrors {
  /// Creates a [TaskEditorFieldErrors] snapshot.
  const TaskEditorFieldErrors({
    this.dueError,
    this.dueNoteError,
    this.historyError,
    this.linkError,
    this.repeatError,
    this.repeatLeadDaysError,
    this.suspendedError,
    this.suspendedNoteError,
    this.titleError,
  });

  /// Inline error for the deadline timestamp input.
  final String? dueError;

  /// Inline error for the deadline note input.
  final String? dueNoteError;

  /// Inline error for the history journal section.
  final String? historyError;

  /// Inline error for the reference links section.
  final String? linkError;

  /// Inline error for the repeat interval count input.
  final String? repeatError;

  /// Inline error for the Mode 2 repeat lead-days input.
  final String? repeatLeadDaysError;

  /// Inline error for the deferral timestamp input.
  final String? suspendedError;

  /// Inline error for the deferral note input.
  final String? suspendedNoteError;

  /// Inline error for the task title input.
  final String? titleError;

  /// Whether at least one field error is present.
  bool get hasAnyError =>
      titleError != null ||
      suspendedError != null ||
      suspendedNoteError != null ||
      dueError != null ||
      dueNoteError != null ||
      repeatError != null ||
      repeatLeadDaysError != null ||
      historyError != null ||
      linkError != null;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TaskEditorFieldErrors &&
        other.titleError == titleError &&
        other.suspendedError == suspendedError &&
        other.suspendedNoteError == suspendedNoteError &&
        other.dueError == dueError &&
        other.dueNoteError == dueNoteError &&
        other.repeatError == repeatError &&
        other.repeatLeadDaysError == repeatLeadDaysError &&
        other.historyError == historyError &&
        other.linkError == linkError;
  }

  @override
  int get hashCode => Object.hash(
    titleError,
    suspendedError,
    suspendedNoteError,
    dueError,
    dueNoteError,
    repeatError,
    repeatLeadDaysError,
    historyError,
    linkError,
  );
}

/// Presentation controller owning task editor pure helpers, draft resolution, validation, persistence, and telemetry.
class TaskEditorController {
  /// Creates a [TaskEditorController] backed by [_ref].
  const TaskEditorController(this._ref);

  final Ref _ref;

  /// Collects selected prerequisite task IDs in canonical board declaration order.
  static List<String> collectOrderedBlockedByIds(
    TaskBoard board,
    Set<String> selectedBlockedByIds,
  ) {
    return <String>[
      for (final task in board.allTasks)
        if (selectedBlockedByIds.contains(task.id)) task.id,
    ];
  }

  /// Collects selected label IDs in canonical board declaration order.
  static List<String> collectOrderedLabelIds(
    TaskBoard board,
    Set<String> selectedLabelIds,
  ) {
    return <String>[
      for (final label in board.labels)
        if (selectedLabelIds.contains(label.id)) label.id,
    ];
  }

  /// Returns the current local wall-clock timestamp derived from [clockProvider] and [configuration].
  DateTime currentLocalWallClock(WebDavConfig configuration) =>
      configuration.toLocalWallClock(_ref.read(clockProvider)().toUtc());

  /// Emits redacted `ui.delete_task.confirmed` telemetry and deletes [taskId].
  Future<void> deleteTask(String taskId) async {
    if (AppLogger.shouldLog(LogLevel.info)) {
      AppLogger.event(
        LogLevel.info,
        LogTag.ui,
        'ui.delete_task.confirmed',
        fields: <String, Object?>{'id': taskId},
      );
    }
    await _ref.read(taskNotifierProvider.notifier).deleteTask(taskId);
  }

  /// Formats an initial `suspended` UTC timestamp in [configuration]'s local wall-clock time (omitting `defaultSuspendedAt`).
  static String formatInitialSuspendedText(
    DateTime? suspendedAtUtc, [
    WebDavConfig configuration = const WebDavConfig(),
  ]) {
    if (suspendedAtUtc == null ||
        suspendedAtUtc == TaskItem.defaultSuspendedAt) {
      return '';
    }
    return formatLocalTimestamp(suspendedAtUtc, configuration);
  }

  /// Formats an optional UTC [instantUtc] in [configuration]'s local wall-clock time, or `''` when `null`.
  static String formatLocalTimestamp(
    DateTime? instantUtc,
    WebDavConfig configuration,
  ) {
    if (instantUtc == null) {
      return '';
    }
    return TaskItem.formatTdfTimestamp(
      configuration.toLocalWallClock(instantUtc),
    );
  }

  /// Normalizes user-edited [rawText], collapsing ASCII-whitespace-only strings to `null` and CR/CRLF breaks to `\n`.
  static String? normalizeSchedulingNote(String rawText) {
    var hasGraphic = false;
    var firstCrIndex = -1;
    for (var i = 0; i < rawText.length; i++) {
      final unit = rawText.codeUnitAt(i);
      if (unit == 0x0D && firstCrIndex < 0) {
        firstCrIndex = i;
      }
      if (unit != 0x09 && unit != 0x0A && unit != 0x0D && unit != 0x20) {
        hasGraphic = true;
      }
    }
    if (!hasGraphic) {
      return null;
    }
    if (firstCrIndex < 0) {
      return rawText;
    }
    return _collapseCrLineEndings(rawText, firstCrIndex);
  }

  /// Parses [rawLeadDays] into a bounded integer in `0..3650`, returning `0` when disabled or blank, or `null` when invalid.
  static int? parseLeadDays({
    required bool hasDue,
    required bool isRepeating,
    required String rawLeadDays,
  }) {
    if (!isRepeating || !hasDue) {
      return 0;
    }
    final trimmed = rawLeadDays.trim();
    if (trimmed.isEmpty) {
      return 0;
    }
    return _tryParseBoundedUnsignedInt(
      trimmed,
      min: 0,
      max: TaskRepeatRule.maxRepeatCount,
    );
  }

  /// Parses [rawCount] into a bounded integer in `1..3650` when [isRepeating] is enabled, or returns `null`.
  static int? parseRepeatCount({
    required bool isRepeating,
    required String rawCount,
  }) {
    if (!isRepeating) {
      return null;
    }
    return _tryParseBoundedUnsignedInt(
      rawCount.trim(),
      min: 1,
      max: TaskRepeatRule.maxRepeatCount,
    );
  }

  /// Resolves the `repeat` rule when [isRepeating] is enabled, preserving [existingClock], or returns `null`.
  static TaskRepeatRule? parseRepeatRule({
    TdfRepeatClock existingClock = TdfRepeatClock.midnight,
    bool hasDue = false,
    required bool isRepeating,
    required String rawCount,
    String rawLeadDays = '',
    required RepeatUnit unit,
  }) {
    final parsedCount = parseRepeatCount(
      isRepeating: isRepeating,
      rawCount: rawCount,
    );
    final parsedLeadDays = parseLeadDays(
      hasDue: hasDue,
      isRepeating: isRepeating,
      rawLeadDays: rawLeadDays,
    );
    if (parsedCount == null || parsedLeadDays == null) {
      return null;
    }
    return TaskRepeatRule(
      count: parsedCount,
      unit: unit,
      clock: existingClock,
      leadDays: parsedLeadDays,
    );
  }

  /// Resolves the current `due` draft in [configuration]'s local wall-clock time, preserving [initialDueAt] and [initialDueAnchor] when unedited.
  ResolvedDueDraft resolveDueDraft({
    required WebDavConfig configuration,
    required bool hasDue,
    required String rawDueText,
    required DateTime? initialDueAt,
    required TdfLocalDateTime? initialDueAnchor,
    required String initialDueText,
  }) {
    if (!hasDue) {
      return const ResolvedDueDraft(
        dueAt: null,
        dueLocalInput: null,
        dueAnchor: null,
        isUnchanged: false,
        isValid: true,
      );
    }
    final trimmed = rawDueText.trim();
    if (initialDueAt case final baselineDueAt? when trimmed == initialDueText) {
      return ResolvedDueDraft(
        dueAt: baselineDueAt,
        dueLocalInput: null,
        dueAnchor: initialDueAnchor,
        isUnchanged: true,
        isValid: true,
      );
    }
    final parsed = tryParseLocalDateTimeInput(trimmed, configuration);
    if (parsed == null) {
      return const ResolvedDueDraft(
        dueAt: null,
        dueLocalInput: null,
        dueAnchor: null,
        isUnchanged: false,
        isValid: false,
      );
    }
    return ResolvedDueDraft(
      dueAt: parsed.resolvedUtc,
      dueLocalInput: parsed.localInput,
      dueAnchor: parsed.localInput,
      isUnchanged: false,
      isValid: true,
    );
  }

  /// Resolves [rawTimestamp] in [configuration]'s local wall-clock time to a normalized UTC [DateTime], or `null` if invalid.
  static DateTime? resolveHistoryTimestampUtc({
    required WebDavConfig configuration,
    required DateTime fallbackNowUtc,
    String? preservedTimestampText,
    DateTime? preservedTimestampUtc,
    required String rawTimestamp,
  }) {
    final trimmed = rawTimestamp.trim();
    if (trimmed.isEmpty) {
      final normalizedFallback = TaskItem.normalizeTimestamp(fallbackNowUtc);
      return TdfCalendar.isWithinTimestampBounds(normalizedFallback)
          ? normalizedFallback
          : null;
    }
    if (preservedTimestampUtc != null &&
        preservedTimestampText != null &&
        trimmed == preservedTimestampText) {
      final normalizedPreserved = TaskItem.normalizeTimestamp(
        preservedTimestampUtc,
      );
      return TdfCalendar.isWithinTimestampBounds(normalizedPreserved)
          ? normalizedPreserved
          : null;
    }
    final parsedLocal = TaskItem.tryParseTdfTimestampInput(trimmed);
    if (parsedLocal == null) {
      return null;
    }
    return _tryConvertLocalWallClockToUtc(configuration, parsedLocal);
  }

  /// Validates pending task editor history inputs into a single [TaskHistoryEntry] or localized error.
  ({TaskHistoryEntry? candidate, String? error})
  resolvePendingHistoryCandidate({
    required WebDavConfig configuration,
    required AppLocalizations localizations,
    required int? editingHistoryIndex,
    required TaskHistoryEntry? editingHistoryOriginalEntry,
    required String? editingHistoryInitialTimestampText,
    required String rawTimestamp,
    required String rawText,
  }) {
    final trimmedTimestamp = rawTimestamp.trim();
    if (editingHistoryIndex != null &&
        editingHistoryOriginalEntry != null &&
        trimmedTimestamp == editingHistoryInitialTimestampText &&
        rawText == editingHistoryOriginalEntry.text) {
      return (candidate: editingHistoryOriginalEntry, error: null);
    }
    final nowUtc = _ref.read(clockProvider)().toUtc();
    final resolvedTimestampUtc = resolveHistoryTimestampUtc(
      configuration: configuration,
      fallbackNowUtc: nowUtc,
      preservedTimestampText: editingHistoryInitialTimestampText,
      preservedTimestampUtc: editingHistoryOriginalEntry?.timestampUtc,
      rawTimestamp: rawTimestamp,
    );
    if (resolvedTimestampUtc == null) {
      return (
        candidate: null,
        error: localizations.historyErrorTimestampInvalid,
      );
    }
    final sanitizedText = sanitizeHistoryText(rawText);
    final textError = validateHistoryText(sanitizedText, localizations);
    if (textError != null) {
      return (candidate: null, error: textError);
    }
    return (
      candidate: TaskHistoryEntry(
        timestampUtc: resolvedTimestampUtc,
        text: sanitizedText,
      ),
      error: null,
    );
  }

  /// Resolves the current `suspended` draft in [configuration]'s local wall-clock time, preserving [initialSuspendedAt] when unedited.
  ResolvedSuspendedDraft resolveSuspendedDraft({
    required WebDavConfig configuration,
    required bool isSuspended,
    required String rawSuspendedText,
    required DateTime? initialSuspendedAt,
    required String initialSuspendedText,
  }) {
    if (!isSuspended) {
      return const ResolvedSuspendedDraft(
        suspendedAt: null,
        suspendedLocalInput: null,
        isForever: false,
        isValid: true,
      );
    }
    final trimmed = rawSuspendedText.trim();
    if (trimmed.isEmpty) {
      return const ResolvedSuspendedDraft(
        suspendedAt: null,
        suspendedLocalInput: null,
        isForever: true,
        isValid: true,
      );
    }
    if (initialSuspendedAt case final baselineSuspendedAt?
        when trimmed == initialSuspendedText) {
      return ResolvedSuspendedDraft(
        suspendedAt: baselineSuspendedAt,
        suspendedLocalInput: null,
        isForever: false,
        isValid: true,
      );
    }
    final parsed = tryParseLocalDateTimeInput(trimmed, configuration);
    if (parsed == null) {
      return const ResolvedSuspendedDraft(
        suspendedAt: null,
        suspendedLocalInput: null,
        isForever: false,
        isValid: false,
      );
    }
    return ResolvedSuspendedDraft(
      suspendedAt: null,
      suspendedLocalInput: parsed.localInput,
      isForever: false,
      isValid: true,
    );
  }

  /// Trims outer ASCII whitespace and collapses internal CR/LF/TAB sequences into single spaces.
  static String sanitizeHistoryText(String rawText) {
    var firstKeep = -1;
    var lastKeep = -1;
    for (var i = 0; i < rawText.length; i++) {
      if (!_isAsciiTrimWhitespace(rawText.codeUnitAt(i))) {
        firstKeep = firstKeep < 0 ? i : firstKeep;
        lastKeep = i;
      }
    }
    if (firstKeep < 0) {
      return '';
    }
    var hasInternalBreak = false;
    for (var i = firstKeep; i <= lastKeep; i++) {
      if (_isInternalLineBreakOrTab(rawText.codeUnitAt(i))) {
        hasInternalBreak = true;
        break;
      }
    }
    if (!hasInternalBreak) {
      return firstKeep == 0 && lastKeep == rawText.length - 1
          ? rawText
          : rawText.substring(firstKeep, lastKeep + 1);
    }
    return _replaceInternalBreaksWithSpaces(rawText, firstKeep, lastKeep);
  }

  /// Returns `true` when editing the due timestamp should auto-reset `passive` back to active auto-priority.
  bool shouldResetAutoPrioritizeDue({
    required bool didUserToggleAutoPrioritizeDue,
    required bool autoPrioritizeDue,
    required bool hasDue,
    required ResolvedDueDraft candidateDue,
    required DateTime? initialDueAt,
    required TdfLocalDateTime? initialDueAnchor,
  }) {
    if (didUserToggleAutoPrioritizeDue ||
        autoPrioritizeDue ||
        !hasDue ||
        !candidateDue.isValid ||
        candidateDue.isUnchanged) {
      return false;
    }
    return !_isSameDueState(candidateDue, initialDueAt, initialDueAnchor);
  }

  /// Validates [input], emits redacted telemetry, persists via [TaskNotifier], and returns an exhaustive [TaskEditorSubmitResult].
  Future<TaskEditorSubmitResult> submitDraft(
    TaskEditorDraftInput input, {
    Locale? locale,
  }) async {
    final localizations = lookupAppLocalizations(
      locale ?? _ref.read(appLocaleProvider),
    );
    final historyResolution = _resolvePendingHistoryEntries(
      input,
      localizations,
    );
    final titleError = validateTaskTitle(
      board: input.board,
      rawTitle: input.rawTitle,
      excludingTaskId: input.existingTask?.id,
      localizations: localizations,
    );
    final suspendedDraft = resolveSuspendedDraft(
      configuration: input.configuration,
      isSuspended: input.isSuspended,
      rawSuspendedText: input.rawSuspendedText,
      initialSuspendedAt: input.initialSuspendedAt,
      initialSuspendedText: input.initialSuspendedText,
    );
    final suspendedNote = _resolveSchedulingNote(
      initialNote: input.initialSuspendedNote,
      isEnabled: input.isSuspended,
      rawText: input.rawSuspendedNote,
    );
    final suspendedNoteError = validateSchedulingNote(
      suspendedNote,
      localizations,
    );
    final dueDraft = resolveDueDraft(
      configuration: input.configuration,
      hasDue: input.hasDue,
      rawDueText: input.rawDueText,
      initialDueAt: input.initialDueAt,
      initialDueAnchor: input.initialDueAnchor,
      initialDueText: input.initialDueText,
    );
    final dueNote = _resolveSchedulingNote(
      initialNote: input.initialDueNote,
      isEnabled: input.hasDue,
      rawText: input.rawDueNote,
    );
    final dueNoteError = validateSchedulingNote(dueNote, localizations);
    final repeatCount = parseRepeatCount(
      isRepeating: input.isRepeating,
      rawCount: input.rawRepeatCount,
    );
    final leadDays = parseLeadDays(
      hasDue: input.hasDue,
      isRepeating: input.isRepeating,
      rawLeadDays: input.rawRepeatLeadDays,
    );
    final hasSuspendedError = input.isSuspended && !suspendedDraft.isValid;
    final hasDueError = input.hasDue && !dueDraft.isValid;
    final hasRepeatError = input.isRepeating && repeatCount == null;
    final hasLeadDaysError =
        input.isRepeating && input.hasDue && leadDays == null;
    final hasHistoryError = historyResolution.error != null;

    final validationErrors = TaskEditorFieldErrors(
      titleError: titleError,
      suspendedError: hasSuspendedError
          ? localizations.taskSuspendedErrorInvalid
          : null,
      suspendedNoteError: suspendedNoteError,
      dueError: hasDueError ? localizations.taskSuspendedErrorInvalid : null,
      dueNoteError: dueNoteError,
      repeatError: hasRepeatError ? localizations.repeatErrorInvalid : null,
      repeatLeadDaysError: hasLeadDaysError
          ? localizations.repeatLeadDaysErrorInvalid
          : null,
      historyError: historyResolution.error,
    );
    if (validationErrors.hasAnyError) {
      _logValidationFailed(
        hasDueError: hasDueError,
        hasDueNoteError: dueNoteError != null,
        hasHistoryError: hasHistoryError,
        hasLeadDaysError: hasLeadDaysError,
        hasRepeatError: hasRepeatError,
        hasSuspendedError: hasSuspendedError,
        hasSuspendedNoteError: suspendedNoteError != null,
        hasTitleError: titleError != null,
      );
      return TaskEditorValidationFailed(validationErrors);
    }

    final repeatRule = parseRepeatRule(
      existingClock:
          input.existingTask?.repeatRule?.clock ?? TdfRepeatClock.midnight,
      hasDue: input.hasDue,
      isRepeating: input.isRepeating,
      rawCount: input.rawRepeatCount,
      rawLeadDays: input.rawRepeatLeadDays,
      unit: input.repeatUnit,
    );
    final committedHistory = historyResolution.hasPending
        ? historyResolution.entries
        : null;
    final effectiveHistoryCount = historyResolution.entries.length;
    try {
      await _persistTask(
        input: input,
        due: dueDraft,
        dueNote: dueNote,
        history: historyResolution.entries,
        repeatRule: repeatRule,
        suspended: suspendedDraft,
        suspendedNote: suspendedNote,
      );
    } on TdfException catch (error) {
      return _buildPersistFailure(
        input: input,
        kindLabel: error.kind.name,
        kind: error.kind,
        historyCount: effectiveHistoryCount,
        committedHistoryEntries: committedHistory,
        localizations: localizations,
      );
    } on TdfContextException catch (error) {
      return _buildPersistFailure(
        input: input,
        kindLabel: error.kind.name,
        kind: null,
        contextKind: error.kind,
        historyCount: effectiveHistoryCount,
        committedHistoryEntries: committedHistory,
        localizations: localizations,
      );
    } on FormatException {
      return _buildPersistFailure(
        input: input,
        kindLabel: 'FormatException',
        kind: TdfErrorKind.invalidTimestamp,
        historyCount: effectiveHistoryCount,
        committedHistoryEntries: committedHistory,
        localizations: localizations,
      );
    }

    _logTaskSaved(
      input: input,
      dueNote: dueNote,
      suspendedNote: suspendedNote,
      repeatRule: repeatRule,
      historyCount: effectiveHistoryCount,
    );
    return const TaskEditorSubmitted();
  }

  /// Parses [rawInput] as a local calendar timestamp and resolves its UTC instant under [configuration] (`TDF-CAL-001`).
  static ({TdfLocalDateTime localInput, DateTime resolvedUtc})?
  tryParseLocalDateTimeInput(String rawInput, WebDavConfig configuration) {
    final parsedWallClock = TaskItem.tryParseTdfTimestampInput(rawInput.trim());
    if (parsedWallClock == null) {
      return null;
    }
    try {
      final localInput = TdfLocalDateTime.fromWallClock(parsedWallClock);
      final resolvedUtc = TaskItem.normalizeTimestamp(
        configuration.localWallClockToUtc(parsedWallClock),
      );
      if (!TdfCalendar.isWithinTimestampBounds(resolvedUtc)) {
        return null;
      }
      return (localInput: localInput, resolvedUtc: resolvedUtc);
    } on TdfException {
      return null;
    } on TdfContextException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Validates [text] against TDF `0.8.0` single-line `<text>` bounds, returning a localized error or `null`.
  static String? validateHistoryText(
    String text,
    AppLocalizations localizations,
  ) {
    final scalarCount = TdfCalendar.countUnicodeScalars(text);
    if (scalarCount == null) {
      return localizations.historyErrorTextInvalid;
    }
    var hasGraphic = false;
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit <= 0x1F || unit == 0x7F) {
        return localizations.historyErrorTextInvalid;
      }
      if (unit != 0x20) {
        hasGraphic = true;
      }
    }
    if (!hasGraphic) {
      return localizations.historyErrorTextEmpty;
    }
    if (scalarCount > maxTdfTextLength) {
      return localizations.historyErrorTextTooLong;
    }
    return null;
  }

  /// Validates [note] against `<note>` control-character, surrogate, and `maxTdfNoteLength` (`2000`) bounds.
  static String? validateSchedulingNote(
    String? note,
    AppLocalizations localizations,
  ) {
    if (note == null) {
      return null;
    }
    final scalarCount = TdfCalendar.countUnicodeScalars(note);
    if (scalarCount == null || _containsIllegalNoteControlChar(note)) {
      return localizations.schedulingNoteErrorInvalid;
    }
    if (scalarCount > maxTdfNoteLength) {
      return localizations.schedulingNoteErrorTooLong;
    }
    return null;
  }

  /// Validates [rawTitle] against empty and case-insensitive duplicate task title constraints on [board].
  static String? validateTaskTitle({
    required TaskBoard board,
    required String rawTitle,
    required String? excludingTaskId,
    required AppLocalizations localizations,
  }) {
    final trimmed = rawTitle.trim();
    if (trimmed.isEmpty) {
      return localizations.taskNameErrorEmpty;
    }
    if (board.hasDuplicateTaskTitle(
      trimmed,
      excludingTaskId: excludingTaskId,
    )) {
      return localizations.taskNameErrorDuplicate;
    }
    return null;
  }

  /// Maps a domain persistence rejection into [TaskEditorPersistFailed] and logs redacted `ui.edit_task.persist_rejected`.
  TaskEditorPersistFailed _buildPersistFailure({
    required TaskEditorDraftInput input,
    required String kindLabel,
    required TdfErrorKind? kind,
    TdfContextOutcomeKind? contextKind,
    required int historyCount,
    required List<TaskHistoryEntry>? committedHistoryEntries,
    required AppLocalizations localizations,
  }) {
    if (AppLogger.shouldLog(LogLevel.warn)) {
      AppLogger.event(
        LogLevel.warn,
        LogTag.ui,
        'ui.edit_task.persist_rejected',
        fields: <String, Object?>{'kind': kindLabel},
      );
    }
    final errors = _mapPersistErrorFields(
      input: input,
      kind: kind,
      contextKind: contextKind,
      historyCount: historyCount,
      localizations: localizations,
    );
    return TaskEditorPersistFailed(
      errors: errors,
      committedHistoryEntries: committedHistoryEntries,
    );
  }

  /// Maps a timestamp-related persistence rejection onto the most specific active scheduling field.
  TaskEditorFieldErrors _buildTimestampPersistErrors({
    required TaskEditorDraftInput input,
    required String timestampError,
    required bool includeRepeatLeadDays,
    String? repeatLeadDaysError,
  }) {
    if (includeRepeatLeadDays &&
        repeatLeadDaysError != null &&
        input.isRepeating &&
        input.hasDue) {
      return TaskEditorFieldErrors(repeatLeadDaysError: repeatLeadDaysError);
    }
    if (input.isSuspended) {
      return TaskEditorFieldErrors(suspendedError: timestampError);
    }
    if (input.hasDue) {
      return TaskEditorFieldErrors(dueError: timestampError);
    }
    return TaskEditorFieldErrors(titleError: timestampError);
  }

  /// Returns whether [candidate] matches both [initialDueAt] and [initialDueAnchor].
  static bool _isSameDueState(
    ResolvedDueDraft candidate,
    DateTime? initialDueAt,
    TdfLocalDateTime? initialDueAnchor,
  ) {
    final resolvedDueAt = candidate.dueAt;
    if (resolvedDueAt == null || initialDueAt == null) {
      return false;
    }
    return TaskItem.normalizeTimestamp(resolvedDueAt) ==
            TaskItem.normalizeTimestamp(initialDueAt) &&
        candidate.dueAnchor == initialDueAnchor;
  }

  /// Emits redacted `ui.edit_task.saved` telemetry without logging raw note or history contents.
  void _logTaskSaved({
    required TaskEditorDraftInput input,
    required String? dueNote,
    required String? suspendedNote,
    required TaskRepeatRule? repeatRule,
    required int historyCount,
  }) {
    if (!AppLogger.shouldLog(LogLevel.info)) {
      return;
    }
    AppLogger.event(
      LogLevel.info,
      LogTag.ui,
      'ui.edit_task.saved',
      fields: <String, Object?>{
        'id': input.existingTask?.id ?? 'new',
        'is_suspended': input.isSuspended,
        'has_suspended_note': suspendedNote != null,
        'has_due': input.hasDue,
        'has_due_note': dueNote != null,
        'is_repeating': input.isRepeating,
        'lead_days': repeatRule?.leadDays ?? 0,
        'history_count': historyCount,
      },
    );
  }

  /// Emits redacted `ui.edit_task.validation_failed` telemetry when form validation rejects submission.
  void _logValidationFailed({
    required bool hasDueError,
    required bool hasDueNoteError,
    required bool hasHistoryError,
    required bool hasLeadDaysError,
    required bool hasRepeatError,
    required bool hasSuspendedError,
    required bool hasSuspendedNoteError,
    required bool hasTitleError,
  }) {
    if (!AppLogger.shouldLog(LogLevel.warn)) {
      return;
    }
    AppLogger.event(
      LogLevel.warn,
      LogTag.ui,
      'ui.edit_task.validation_failed',
      fields: <String, Object?>{
        'title': hasTitleError,
        'suspended': hasSuspendedError,
        'suspended_note': hasSuspendedNoteError,
        'due': hasDueError,
        'due_note': hasDueNoteError,
        'repeat': hasRepeatError,
        'lead_days': hasLeadDaysError,
        'history': hasHistoryError,
      },
    );
  }

  /// Routes a domain persistence exception kind to the corresponding [TaskEditorFieldErrors].
  TaskEditorFieldErrors _mapPersistErrorFields({
    required TaskEditorDraftInput input,
    required TdfErrorKind? kind,
    required TdfContextOutcomeKind? contextKind,
    required int historyCount,
    required AppLocalizations localizations,
  }) {
    if (contextKind == TdfContextOutcomeKind.timeZoneContextRequired) {
      return _buildTimestampPersistErrors(
        input: input,
        timestampError: localizations.taskSuspendedErrorInvalid,
        includeRepeatLeadDays: false,
      );
    }
    if (kind == TdfErrorKind.limitExceeded &&
        historyCount >= maxTdfHistoryPerTask) {
      return TaskEditorFieldErrors(
        historyError: localizations.historyErrorMaxExceeded,
      );
    }
    if (kind == TdfErrorKind.limitExceeded) {
      return TaskEditorFieldErrors(
        titleError: localizations.schedulingNoteErrorTooLong,
      );
    }
    if (kind == TdfErrorKind.invalidTimestamp) {
      return _buildTimestampPersistErrors(
        input: input,
        timestampError: localizations.taskSuspendedErrorInvalid,
        includeRepeatLeadDays: true,
        repeatLeadDaysError: localizations.repeatLeadDaysErrorInvalid,
      );
    }
    if (kind == TdfErrorKind.unexpectedToken) {
      return TaskEditorFieldErrors(
        titleError: localizations.schedulingNoteErrorInvalid,
      );
    }
    if (kind == TdfErrorKind.invalidUri) {
      return TaskEditorFieldErrors(linkError: localizations.linkErrorInvalid);
    }
    if (kind == TdfErrorKind.emptyText) {
      return TaskEditorFieldErrors(
        titleError: localizations.taskNameErrorEmpty,
      );
    }
    return TaskEditorFieldErrors(
      titleError: localizations.taskSuspendedErrorInvalid,
    );
  }

  /// Persists the validated draft onto [taskNotifierProvider].
  Future<void> _persistTask({
    required TaskEditorDraftInput input,
    required ResolvedDueDraft due,
    required String? dueNote,
    required List<TaskHistoryEntry> history,
    required TaskRepeatRule? repeatRule,
    required ResolvedSuspendedDraft suspended,
    required String? suspendedNote,
  }) {
    final notifier = _ref.read(taskNotifierProvider.notifier);
    final trimmedTitle = input.rawTitle.trim();
    final trimmedNote = input.rawNote.trim();
    final pendingSubtask = input.pendingSubtaskText.trim();
    final isCompletedTask = switch (input.existingTask) {
      final existing? => existing.isCompleted || existing.completedAt != null,
      null => false,
    };
    final subtasks = <SubtaskItem>[
      ...input.subtasks,
      if (pendingSubtask.isNotEmpty)
        SubtaskItem(title: pendingSubtask, isCompleted: isCompletedTask),
    ];
    final blockedByIds = collectOrderedBlockedByIds(
      input.board,
      input.selectedBlockedByIds,
    );
    final labelIds = collectOrderedLabelIds(
      input.board,
      input.selectedLabelIds,
    );

    if (input.existingTask case final existingTask?) {
      final isDuePassive = !input.hasDue
          ? false
          : (isCompletedTask && due.isUnchanged
                ? existingTask.isDuePassive
                : !input.autoPrioritizeDue);
      final effectiveTargetTier =
          (!isCompletedTask && input.mode == input.initialEditorMode)
          ? null
          : input.mode.targetTier;
      return notifier.updateTask(
        existingTask.id,
        title: trimmedTitle,
        note: trimmedNote,
        targetTier: effectiveTargetTier,
        isPriority: input.mode == QuickAddMode.priority,
        subtasksAutoFinish: input.autoFinish,
        subtasks: subtasks,
        labelIds: labelIds,
        dueAt: due.dueLocalInput == null ? due.dueAt : null,
        dueLocalInput: due.dueLocalInput,
        dueAnchor: due.dueLocalInput == null ? due.dueAnchor : null,
        isDuePassive: isDuePassive,
        dueNote: dueNote,
        clearDueAt: !input.hasDue,
        clearDueAnchor:
            !input.hasDue ||
            (due.dueLocalInput == null && due.dueAnchor == null),
        clearDueNote: !input.hasDue || dueNote == null,
        origin: existingTask.origin,
        suspendedAt: suspended.suspendedAt,
        suspendedLocalInput: suspended.suspendedLocalInput,
        isSuspendedForever: input.isSuspended ? suspended.isForever : false,
        suspendedNote: suspendedNote,
        clearSuspendedAt: !input.isSuspended,
        clearSuspendedNote: !input.isSuspended || suspendedNote == null,
        repeatRule: repeatRule,
        clearRepeatRule: !input.isRepeating,
        blockedByTaskIds: blockedByIds,
        links: input.links,
        history: history,
        conditions: input.conditions,
      );
    }

    return notifier.addTask(
      trimmedTitle,
      note: trimmedNote.isEmpty ? null : trimmedNote,
      targetTier: input.mode.targetTier,
      isPriority: input.mode == QuickAddMode.priority,
      subtasksAutoFinish: input.autoFinish,
      subtasks: subtasks,
      labelIds: labelIds,
      dueLocalInput: due.dueLocalInput,
      isDuePassive: input.hasDue && !input.autoPrioritizeDue,
      dueNote: dueNote,
      suspendedLocalInput: suspended.suspendedLocalInput,
      isSuspendedForever: suspended.isForever,
      suspendedNote: suspendedNote,
      repeatRule: repeatRule,
      blockedByTaskIds: blockedByIds,
      links: input.links,
      history: history,
      conditions: input.conditions,
    );
  }

  /// Resolves any pending history draft inputs inside [input] into a normalized entry list or localized error.
  ({List<TaskHistoryEntry> entries, String? error, bool hasPending})
  _resolvePendingHistoryEntries(
    TaskEditorDraftInput input,
    AppLocalizations localizations,
  ) {
    final hasPending =
        input.editingHistoryIndex != null ||
        input.rawHistoryTimestamp.trim().isNotEmpty ||
        input.rawHistoryText.isNotEmpty;
    if (!hasPending) {
      return (entries: input.historyEntries, error: null, hasPending: false);
    }
    final candidateResult = resolvePendingHistoryCandidate(
      configuration: input.configuration,
      localizations: localizations,
      editingHistoryIndex: input.editingHistoryIndex,
      editingHistoryOriginalEntry: input.editingHistoryOriginalEntry,
      editingHistoryInitialTimestampText:
          input.editingHistoryInitialTimestampText,
      rawTimestamp: input.rawHistoryTimestamp,
      rawText: input.rawHistoryText,
    );
    final candidate = candidateResult.candidate;
    if (candidate == null) {
      return (
        entries: input.historyEntries,
        error: candidateResult.error,
        hasPending: true,
      );
    }
    final activeIndex = input.editingHistoryIndex;
    final nextEntries = TaskHistoryEntry.normalizeList(<TaskHistoryEntry>[
      for (var i = 0; i < input.historyEntries.length; i++)
        if (i != activeIndex) input.historyEntries[i],
      candidate,
    ]);
    if (nextEntries.length > maxTdfHistoryPerTask) {
      return (
        entries: input.historyEntries,
        error: localizations.historyErrorMaxExceeded,
        hasPending: true,
      );
    }
    return (entries: nextEntries, error: null, hasPending: true);
  }

  /// Resolves an optional scheduling note, preserving [initialNote] verbatim when untouched.
  static String? _resolveSchedulingNote({
    required String? initialNote,
    required bool isEnabled,
    required String rawText,
  }) {
    if (!isEnabled) {
      return null;
    }
    if (initialNote != null && rawText == initialNote) {
      return initialNote;
    }
    return normalizeSchedulingNote(rawText);
  }

  /// Converts [parsedLocal] via [configuration] (`TDF-CAL-001`), returning `null` on calendar or context errors.
  static DateTime? _tryConvertLocalWallClockToUtc(
    WebDavConfig configuration,
    DateTime parsedLocal,
  ) {
    try {
      final convertedUtc = TaskItem.normalizeTimestamp(
        configuration.localWallClockToUtc(parsedLocal),
      );
      return TdfCalendar.isWithinTimestampBounds(convertedUtc)
          ? convertedUtc
          : null;
    } on TdfException {
      return null;
    } on TdfContextException {
      return null;
    } on FormatException {
      return null;
    }
  }
}

/// Collapses `\r\n` and standalone `\r` sequences starting at [firstCrIndex] into `\n` in a single pass.
String _collapseCrLineEndings(String rawText, int firstCrIndex) {
  final buffer = StringBuffer(rawText.substring(0, firstCrIndex));
  for (var i = firstCrIndex; i < rawText.length; i++) {
    final unit = rawText.codeUnitAt(i);
    if (unit == 0x0D) {
      buffer.write('\n');
      if (i + 1 < rawText.length && rawText.codeUnitAt(i + 1) == 0x0A) {
        i++;
      }
      continue;
    }
    buffer.writeCharCode(unit);
  }
  return buffer.toString();
}

/// Returns whether [text] contains any control character disallowed by `<note>` (`0x00..0x1F` except `\t`, `\n`, `\r`, or `0x7F`).
bool _containsIllegalNoteControlChar(String text) {
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    final isDisallowedLowControl =
        unit <= 0x1F && unit != 0x09 && unit != 0x0A && unit != 0x0D;
    if (isDisallowedLowControl || unit == 0x7F) {
      return true;
    }
  }
  return false;
}

/// Returns `true` when [unit] is ASCII trim whitespace (`TAB`, `LF`, `CR`, or `SPACE`).
bool _isAsciiTrimWhitespace(int unit) =>
    unit == 0x09 || unit == 0x0A || unit == 0x0D || unit == 0x20;

/// Returns `true` when [unit] is `TAB`, `LF`, or `CR`.
bool _isInternalLineBreakOrTab(int unit) =>
    unit == 0x09 || unit == 0x0A || unit == 0x0D;

/// Collapses `\r\n`, `\r`, `\n`, and `\t` inside `rawText[start..end]` into single `0x20` spaces.
String _replaceInternalBreaksWithSpaces(String rawText, int start, int end) {
  final buffer = StringBuffer();
  for (var i = start; i <= end; i++) {
    final unit = rawText.codeUnitAt(i);
    if (unit == 0x0D && i < end && rawText.codeUnitAt(i + 1) == 0x0A) {
      buffer.writeCharCode(0x20);
      i++;
    } else if (_isInternalLineBreakOrTab(unit)) {
      buffer.writeCharCode(0x20);
    } else {
      buffer.writeCharCode(unit);
    }
  }
  return buffer.toString();
}

/// Parses an unsigned ASCII decimal integer in `[min, max]` bounded by `maxTdfNumberLength`, or returns `null`.
int? _tryParseBoundedUnsignedInt(
  String trimmed, {
  required int min,
  required int max,
}) {
  if (trimmed.isEmpty || trimmed.length > maxTdfNumberLength) {
    return null;
  }
  var value = 0;
  for (var i = 0; i < trimmed.length; i++) {
    final unit = trimmed.codeUnitAt(i);
    if (unit < 0x30 || unit > 0x39) {
      return null;
    }
    value = (value * 10) + (unit - 0x30);
    if (value > max) {
      return null;
    }
  }
  return value >= min ? value : null;
}
