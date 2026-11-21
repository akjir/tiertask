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
import '../models/task_item.dart';
import '../models/tdf_error.dart';
import '../models/tdf_timezone.dart';
import '../providers/config_providers.dart';
import '../providers/task_providers.dart';
import '../services/app_logger.dart';
import 'task_editor_controller.dart';

/// Provides [TaskInfoController] for live Task Info history mutations, verification, and duration formatting.
final taskInfoControllerProvider = Provider<TaskInfoController>(
  TaskInfoController.new,
);

/// Sealed outcome returned by live history journal mutations on [TaskInfoController].
sealed class TaskHistoryMutationResult {
  /// Creates a [TaskHistoryMutationResult].
  const TaskHistoryMutationResult();
}

/// Outcome returned when post-mutation board state confirmed the history change.
@immutable
final class TaskHistoryMutationCommitted extends TaskHistoryMutationResult {
  /// Creates a [TaskHistoryMutationCommitted] outcome.
  const TaskHistoryMutationCommitted();
}

/// Outcome returned when validation or domain persistence rejected a history mutation.
@immutable
final class TaskHistoryMutationFailed extends TaskHistoryMutationResult {
  /// Creates a [TaskHistoryMutationFailed] carrying [localizedMessage].
  const TaskHistoryMutationFailed(this.localizedMessage);

  /// Localized inline error text for the history card.
  final String localizedMessage;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TaskHistoryMutationFailed &&
        other.localizedMessage == localizedMessage;
  }

  @override
  int get hashCode => localizedMessage.hashCode;
}

/// Outcome returned when the target task disappeared or persistence rolled back leaving prior history intact.
@immutable
final class TaskHistoryMutationNotApplied extends TaskHistoryMutationResult {
  /// Creates a [TaskHistoryMutationNotApplied] outcome.
  const TaskHistoryMutationNotApplied();
}

/// Outcome returned when an inline history edit matched the original entry text before or after sanitization.
@immutable
final class TaskHistoryMutationUnchanged extends TaskHistoryMutationResult {
  /// Creates a [TaskHistoryMutationUnchanged] outcome.
  const TaskHistoryMutationUnchanged();
}

/// Presentation controller owning Task Info history validation, rollback-safe mutations, telemetry, and duration formatting.
class TaskInfoController {
  /// Creates a [TaskInfoController] backed by [_ref].
  const TaskInfoController(this._ref);

  final Ref _ref;

  /// Validates and appends a single-line history entry stamped with the current UTC second.
  Future<TaskHistoryMutationResult> appendHistoryEntry({
    required TaskItem currentTask,
    required String rawText,
    Locale? locale,
  }) async {
    if (!isTaskOnBoard(currentTask.id)) {
      return const TaskHistoryMutationNotApplied();
    }
    final localizations = lookupAppLocalizations(
      locale ?? _ref.read(appLocaleProvider),
    );
    final sanitizedText = TaskEditorController.sanitizeHistoryText(rawText);
    final textError = TaskEditorController.validateHistoryText(
      sanitizedText,
      localizations,
    );
    if (textError != null) {
      _logValidationFailed(
        currentTask.id,
        _validationReasonCode(sanitizedText),
      );
      return TaskHistoryMutationFailed(textError);
    }
    final timestampUtc = TaskItem.normalizeTimestamp(
      _ref.read(clockProvider)().toUtc(),
    );
    if (!TdfCalendar.isWithinTimestampBounds(timestampUtc)) {
      _logValidationFailed(currentTask.id, 'invalid_timestamp');
      return TaskHistoryMutationFailed(
        localizations.historyErrorTimestampInvalid,
      );
    }
    final candidate = TaskHistoryEntry(
      timestampUtc: timestampUtc,
      text: sanitizedText,
    );
    if (!currentTask.history.contains(candidate) &&
        currentTask.history.length >= maxTdfHistoryPerTask) {
      _logValidationFailed(currentTask.id, 'max_exceeded');
      return TaskHistoryMutationFailed(localizations.historyErrorMaxExceeded);
    }
    final failure = await _runPersistMutation(
      taskId: currentTask.id,
      localizations: localizations,
      action: () => _ref
          .read(taskNotifierProvider.notifier)
          .addTaskHistoryEntry(
            currentTask.id,
            timestampUtc: candidate.timestampUtc,
            text: candidate.text,
          ),
    );
    if (failure != null) {
      return failure;
    }
    final postTask = _findTask(currentTask.id);
    if (postTask != null && postTask.history.contains(candidate)) {
      _logHistoryMutated(
        'ui.task_info.history_added',
        currentTask.id,
        postTask.history.length,
      );
      return const TaskHistoryMutationCommitted();
    }
    return const TaskHistoryMutationNotApplied();
  }

  /// Removes [entry] from [taskId] and verifies post-mutation removal on the board.
  Future<TaskHistoryMutationResult> deleteHistoryEntry({
    required String taskId,
    required TaskHistoryEntry entry,
    Locale? locale,
  }) async {
    if (!isTaskOnBoard(taskId)) {
      return const TaskHistoryMutationNotApplied();
    }
    final localizations = lookupAppLocalizations(
      locale ?? _ref.read(appLocaleProvider),
    );
    final failure = await _runPersistMutation(
      taskId: taskId,
      localizations: localizations,
      action: () => _ref
          .read(taskNotifierProvider.notifier)
          .removeTaskHistoryEntry(
            taskId,
            timestampUtc: entry.timestampUtc,
            text: entry.text,
          ),
    );
    if (failure != null) {
      return failure;
    }
    final postTask = _findTask(taskId);
    if (postTask != null && !postTask.history.contains(entry)) {
      _logHistoryMutated(
        'ui.task_info.history_removed',
        taskId,
        postTask.history.length,
      );
      return const TaskHistoryMutationCommitted();
    }
    return const TaskHistoryMutationNotApplied();
  }

  /// Returns `true` when [anchor] differs in any `(year, month, day, hour, minute, second)` component from [localWallClock].
  static bool differsFromWallClock(
    TdfLocalDateTime anchor,
    DateTime localWallClock,
  ) =>
      anchor.year != localWallClock.year ||
      anchor.month != localWallClock.month ||
      anchor.day != localWallClock.day ||
      anchor.hour != localWallClock.hour ||
      anchor.minute != localWallClock.minute ||
      anchor.second != localWallClock.second;

  /// Formats a positive [difference] into days/hours, hours/minutes, or minutes remaining.
  static String formatRemainingDuration(
    Duration difference,
    AppLocalizations localizations,
  ) {
    if (difference.inDays >= 1) {
      final remainingHours = difference.inHours % 24;
      return localizations.taskInfoDurationDaysHours(
        difference.inDays.toString(),
        remainingHours.toString(),
      );
    }
    if (difference.inHours >= 1) {
      final remainingMinutes = difference.inMinutes % 60;
      return localizations.taskInfoDurationHoursMinutes(
        difference.inHours.toString(),
        remainingMinutes.toString(),
      );
    }
    final minutes = difference.inMinutes < 1 ? 1 : difference.inMinutes;
    return localizations.taskInfoDurationMinutes(minutes.toString());
  }

  /// Returns `true` when [taskId] is currently present on [taskNotifierProvider].
  bool isTaskOnBoard(String taskId) => _findTask(taskId) != null;

  /// Validates and saves an inline text edit for [originalEntry] on [taskId], preserving `timestampUtc`.
  Future<TaskHistoryMutationResult> updateHistoryEntry({
    required String taskId,
    required TaskHistoryEntry originalEntry,
    required String rawText,
    Locale? locale,
  }) async {
    if (!isTaskOnBoard(taskId)) {
      return const TaskHistoryMutationNotApplied();
    }
    if (rawText == originalEntry.text) {
      return const TaskHistoryMutationUnchanged();
    }
    final localizations = lookupAppLocalizations(
      locale ?? _ref.read(appLocaleProvider),
    );
    final sanitizedText = TaskEditorController.sanitizeHistoryText(rawText);
    final textError = TaskEditorController.validateHistoryText(
      sanitizedText,
      localizations,
    );
    if (textError != null) {
      _logValidationFailed(taskId, _validationReasonCode(sanitizedText));
      return TaskHistoryMutationFailed(textError);
    }
    if (sanitizedText == originalEntry.text) {
      return const TaskHistoryMutationUnchanged();
    }
    final replacement = TaskHistoryEntry(
      timestampUtc: originalEntry.timestampUtc,
      text: sanitizedText,
    );
    final failure = await _runPersistMutation(
      taskId: taskId,
      localizations: localizations,
      action: () => _ref
          .read(taskNotifierProvider.notifier)
          .updateTaskHistoryEntry(
            taskId,
            oldTimestampUtc: originalEntry.timestampUtc,
            oldText: originalEntry.text,
            newTimestampUtc: replacement.timestampUtc,
            newText: replacement.text,
          ),
    );
    if (failure != null) {
      return failure;
    }
    final postTask = _findTask(taskId);
    if (postTask != null && postTask.history.contains(replacement)) {
      _logHistoryMutated(
        'ui.task_info.history_updated',
        taskId,
        postTask.history.length,
      );
      return const TaskHistoryMutationCommitted();
    }
    return const TaskHistoryMutationNotApplied();
  }

  /// Looks up [taskId] on the latest board snapshot in [taskNotifierProvider].
  TaskItem? _findTask(String taskId) =>
      _ref.read(taskNotifierProvider).asData?.value.findTask(taskId);

  /// Maps a domain [TdfErrorKind] into a localized inline history validation message.
  static String _formatMutationException(
    TdfErrorKind kind,
    AppLocalizations localizations,
  ) {
    return switch (kind) {
      TdfErrorKind.emptyText => localizations.historyErrorTextEmpty,
      TdfErrorKind.limitExceeded => localizations.historyErrorMaxExceeded,
      TdfErrorKind.unexpectedToken => localizations.historyErrorTextInvalid,
      _ => localizations.historyErrorTimestampInvalid,
    };
  }

  /// Emits a redacted `LogTag.ui` info event after a history mutation commits.
  static void _logHistoryMutated(
    String eventName,
    String taskId,
    int historyCount,
  ) {
    if (!AppLogger.shouldLog(LogLevel.info)) {
      return;
    }
    AppLogger.event(
      LogLevel.info,
      LogTag.ui,
      eventName,
      fields: <String, Object?>{'id': taskId, 'history_count': historyCount},
    );
  }

  /// Emits a redacted `ui.task_info.history_persist_rejected` warning.
  static void _logPersistRejected(String taskId, String kindLabel) {
    if (!AppLogger.shouldLog(LogLevel.warn)) {
      return;
    }
    AppLogger.event(
      LogLevel.warn,
      LogTag.ui,
      'ui.task_info.history_persist_rejected',
      fields: <String, Object?>{'id': taskId, 'kind': kindLabel},
    );
  }

  /// Emits a redacted `ui.task_info.history_validation_failed` warning with [reasonCode].
  static void _logValidationFailed(String taskId, String reasonCode) {
    if (!AppLogger.shouldLog(LogLevel.warn)) {
      return;
    }
    AppLogger.event(
      LogLevel.warn,
      LogTag.ui,
      'ui.task_info.history_validation_failed',
      fields: <String, Object?>{'id': taskId, 'reason': reasonCode},
    );
  }

  /// Executes [action] and maps [TdfException] and [FormatException] into [TaskHistoryMutationFailed].
  Future<TaskHistoryMutationFailed?> _runPersistMutation({
    required String taskId,
    required AppLocalizations localizations,
    required Future<void> Function() action,
  }) async {
    try {
      await action();
      return null;
    } on TdfException catch (error) {
      _logPersistRejected(taskId, error.kind.name);
      return TaskHistoryMutationFailed(
        _formatMutationException(error.kind, localizations),
      );
    } on FormatException {
      _logPersistRejected(taskId, 'FormatException');
      return TaskHistoryMutationFailed(
        localizations.historyErrorTimestampInvalid,
      );
    }
  }

  /// Classifies why [sanitizedText] failed validation without inspecting or logging sensitive content.
  static String _validationReasonCode(String sanitizedText) {
    final scalarCount = TdfCalendar.countUnicodeScalars(sanitizedText);
    if (scalarCount == null) {
      return 'unpaired_surrogate';
    }
    for (var i = 0; i < sanitizedText.length; i++) {
      final unit = sanitizedText.codeUnitAt(i);
      if (unit <= 0x1F || unit == 0x7F) {
        return 'control_char';
      }
    }
    if (sanitizedText.trim().isEmpty) {
      return 'empty_text';
    }
    return 'text_too_long';
  }
}
