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

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/task_board.dart';
import '../models/task_item.dart';
import '../models/tdf_error.dart';
import '../models/tdf_sync_metadata.dart';
import '../models/tdf_timezone.dart';
import '../models/webdav_config.dart';

/// Provides [TaskScheduleHelper] for task scheduling draft resolution, formatting, and validation helpers.
final taskScheduleHelperProvider = Provider<TaskScheduleHelper>(
  (ref) => const TaskScheduleHelper(),
);

/// Immutable resolution state for a task `due` timestamp input.
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

/// Immutable resolution state for a task `suspended` timestamp input.
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

/// Stateless presentation helper owning task scheduling draft resolution, timestamp formatting, duration formatting, and field validation.
class TaskScheduleHelper {
  /// Creates a [TaskScheduleHelper].
  const TaskScheduleHelper();

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
