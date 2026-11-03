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

import 'tdf_metadata.dart';

/// Supported time units for a TDF `repeat <count> <unit>` directive.
enum RepeatUnit {
  /// Daily recurrence (`days`).
  days('days'),

  /// Weekly recurrence (`weeks`).
  weeks('weeks'),

  /// Monthly recurrence (`months`).
  months('months');

  /// Creates a [RepeatUnit] with its canonical [tdfToken].
  const RepeatUnit(this.tdfToken);

  /// Canonical bare-word token emitted in `.tdf` documents.
  final String tdfToken;

  /// Parses a canonical TDF unit token (`days`, `weeks`, `months`), or returns `null`.
  static RepeatUnit? tryParseToken(String token) {
    return switch (token) {
      'days' => RepeatUnit.days,
      'weeks' => RepeatUnit.weeks,
      'months' => RepeatUnit.months,
      _ => null,
    };
  }
}

/// Immutable representation of a single subtask step (`step <bool> "<text>"`) belonging to a [TaskItem].
@immutable
class SubtaskItem {
  /// Creates a [SubtaskItem] with [title] and optional [isCompleted] state.
  const SubtaskItem({required this.title, this.isCompleted = false});

  /// Whether the subtask step is marked as completed (`true`).
  final bool isCompleted;

  /// Plain-text subtask description.
  final String title;

  /// Returns a copy of this subtask with updated fields.
  SubtaskItem copyWith({String? title, bool? isCompleted}) {
    return SubtaskItem(
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SubtaskItem &&
        other.title == title &&
        other.isCompleted == isCompleted;
  }

  @override
  int get hashCode => Object.hash(title, isCompleted);

  @override
  String toString() => 'step $isCompleted "$title"';
}

/// Immutable representation of a TDF `repeat <count> <days|weeks|months>` rule.
@immutable
class TaskRepeatRule {
  /// Creates a [TaskRepeatRule] with positive [count] and [unit].
  const TaskRepeatRule({required this.count, required this.unit});

  /// Maximum allowed recurrence interval count (`3650`).
  static const int maxRepeatCount = 3650;

  /// Number of units between recurrence cycles (`1..3650`).
  final int count;

  /// Time unit (`days`, `weeks`, or `months`) for the recurrence interval.
  final RepeatUnit unit;

  /// Computes the next local due timestamp relative to [completionLocalTime],
  /// preserving a non-midnight `<HH:MM[:SS]>` from [previousSuspendedAt] when present.
  DateTime nextLocalDueDate(
    DateTime completionLocalTime, {
    DateTime? previousSuspendedAt,
  }) {
    final hasExplicitSuspendedTime =
        previousSuspendedAt != null &&
        previousSuspendedAt != TaskItem.defaultSuspendedAt &&
        (previousSuspendedAt.hour != 0 ||
            previousSuspendedAt.minute != 0 ||
            previousSuspendedAt.second != 0);
    final targetHour = hasExplicitSuspendedTime ? previousSuspendedAt.hour : 0;
    final targetMinute = hasExplicitSuspendedTime
        ? previousSuspendedAt.minute
        : 0;
    final targetSecond = hasExplicitSuspendedTime
        ? previousSuspendedAt.second
        : 0;

    return switch (unit) {
      RepeatUnit.days => _addDays(
        completionLocalTime,
        count,
        targetHour,
        targetMinute,
        targetSecond,
      ),
      RepeatUnit.weeks => _addDays(
        completionLocalTime,
        count * 7,
        targetHour,
        targetMinute,
        targetSecond,
      ),
      RepeatUnit.months => _addMonths(
        completionLocalTime,
        count,
        targetHour,
        targetMinute,
        targetSecond,
      ),
    };
  }

  /// Formats this rule as canonical TDF directive arguments (`<count> <unit>`).
  String toTdfDirectiveArgs() => '$count ${unit.tdfToken}';

  /// Adds [daysToAdd] calendar days to [baseDate] with the given time-of-day components.
  static DateTime _addDays(
    DateTime baseDate,
    int daysToAdd,
    int hour,
    int minute,
    int second,
  ) {
    final targetDate = DateTime.utc(
      baseDate.year,
      baseDate.month,
      baseDate.day,
    ).add(Duration(days: daysToAdd));
    return DateTime.utc(
      targetDate.year,
      targetDate.month,
      targetDate.day,
      hour,
      minute,
      second,
    );
  }

  /// Adds [monthsToAdd] calendar months to [baseDate], clamping the day to the target month's length.
  static DateTime _addMonths(
    DateTime baseDate,
    int monthsToAdd,
    int hour,
    int minute,
    int second,
  ) {
    final totalMonths =
        (baseDate.year * 12) + (baseDate.month - 1) + monthsToAdd;
    final targetYear = totalMonths ~/ 12;
    final targetMonth = (totalMonths % 12) + 1;
    final maxDayInTargetMonth = DateTime.utc(
      targetYear,
      targetMonth + 1,
      0,
    ).day;
    final clampedDay = baseDate.day <= maxDayInTargetMonth
        ? baseDate.day
        : maxDayInTargetMonth;
    return DateTime.utc(
      targetYear,
      targetMonth,
      clampedDay,
      hour,
      minute,
      second,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TaskRepeatRule &&
        other.count == count &&
        other.unit == unit;
  }

  @override
  int get hashCode => Object.hash(count, unit);

  @override
  String toString() => 'repeat $count ${unit.tdfToken}';
}

/// Immutable representation of a single TDF `task` block in TierTask.
@immutable
class TaskItem {
  /// Creates a [TaskItem] with TDF attributes and unmodifiable collection views.
  TaskItem({
    String? id,
    required this.title,
    this.note,
    this.isCompleted = false,
    this.isPriority = false,
    DateTime? createdAt,
    this.queuedAt,
    this.completedAt,
    this.modifiedAt,
    this.suspendedAt,
    this.repeatRule,
    List<String> labelIds = const [],
    List<String> blockedByTaskIds = const [],
    List<TaskCondition> conditions = const [],
    this.subtasksAutoFinish = false,
    List<SubtaskItem> subtasks = const [],
  }) : id = id ?? _nextId(),
       createdAt = createdAt ?? defaultCreatedAt,
       labelIds = List<String>.unmodifiable(labelIds),
       blockedByTaskIds = List<String>.unmodifiable(blockedByTaskIds),
       conditions = List<TaskCondition>.unmodifiable(conditions),
       subtasks = List<SubtaskItem>.unmodifiable(subtasks);

  /// Fallback UTC creation timestamp when none is provided explicitly.
  static final DateTime defaultCreatedAt = DateTime.utc(2026, 11, 1, 8, 0);

  /// Far-future UTC deferral timestamp used when a task is manually blocked without a specific date.
  static final DateTime defaultSuspendedAt = DateTime.utc(9999, 12, 31, 23, 59);

  static int _idCounter = 0;

  /// Prerequisite task IDs (`blocked` directive).
  final List<String> blockedByTaskIds;

  /// Completion timestamp (`finished` directive) when located in Tier 6 (`Completed`).
  final DateTime? completedAt;

  /// Dynamic activation conditions (`condition` directives).
  final List<TaskCondition> conditions;

  /// Creation timestamp (`created` directive).
  final DateTime createdAt;

  /// Unique TDF task entity identifier (`<id>`).
  final String id;

  /// Whether the task is completed (`finished` is present).
  final bool isCompleted;

  /// Whether the task carries the `priority` header flag.
  final bool isPriority;

  /// Associated label IDs (`labels` directive).
  final List<String> labelIds;

  /// Optional UTC modification timestamp (`modified` directive).
  final DateTime? modifiedAt;

  /// Optional extended description (`note` directive).
  final String? note;

  /// Active pull-cycle queue timestamp (`queued` directive), or `null` when in `Someday`.
  final DateTime? queuedAt;

  /// Optional recurrence rule (`repeat` directive).
  final TaskRepeatRule? repeatRule;

  /// Ordered checklist steps (`subtasks` sub-block).
  final List<SubtaskItem> subtasks;

  /// Whether the `subtasks` sub-block carries the `auto-finish` header flag.
  final bool subtasksAutoFinish;

  /// Optional deferral timestamp (`suspended` directive).
  final DateTime? suspendedAt;

  /// Human-readable task title (`name` directive).
  final String title;

  /// Effective UTC modification timestamp (`modifiedAt ?? max(createdAt, queuedAt, completedAt)`).
  DateTime get effectiveModifiedAt =>
      modifiedAt ?? _latestTimestamp(createdAt, queuedAt, completedAt);

  /// Returns a copy of this task with the provided fields updated.
  TaskItem copyWith({
    String? id,
    String? title,
    String? note,
    bool? isCompleted,
    bool? isPriority,
    DateTime? createdAt,
    DateTime? queuedAt,
    DateTime? completedAt,
    DateTime? modifiedAt,
    DateTime? suspendedAt,
    TaskRepeatRule? repeatRule,
    List<String>? labelIds,
    List<String>? blockedByTaskIds,
    List<TaskCondition>? conditions,
    bool? subtasksAutoFinish,
    List<SubtaskItem>? subtasks,
    bool clearNote = false,
    bool clearQueuedAt = false,
    bool clearCompletedAt = false,
    bool clearModifiedAt = false,
    bool clearSuspendedAt = false,
    bool clearRepeatRule = false,
  }) {
    return TaskItem(
      id: id ?? this.id,
      title: title ?? this.title,
      note: clearNote ? null : (note ?? this.note),
      isCompleted: isCompleted ?? this.isCompleted,
      isPriority: isPriority ?? this.isPriority,
      createdAt: createdAt ?? this.createdAt,
      queuedAt: clearQueuedAt ? null : (queuedAt ?? this.queuedAt),
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      modifiedAt: clearModifiedAt ? null : (modifiedAt ?? this.modifiedAt),
      suspendedAt: clearSuspendedAt ? null : (suspendedAt ?? this.suspendedAt),
      repeatRule: clearRepeatRule ? null : (repeatRule ?? this.repeatRule),
      labelIds: labelIds ?? this.labelIds,
      blockedByTaskIds: blockedByTaskIds ?? this.blockedByTaskIds,
      conditions: conditions ?? this.conditions,
      subtasksAutoFinish: subtasksAutoFinish ?? this.subtasksAutoFinish,
      subtasks: subtasks ?? this.subtasks,
    );
  }

  /// Formats [date] as an ISO-8601 date string (`YYYY-MM-DD`).
  static String formatIsoDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// Formats [timestamp] as a canonical TDF timestamp (`YYYY-MM-DD HH:MM` or `YYYY-MM-DD HH:MM:SS` when seconds are non-zero).
  static String formatTdfTimestamp(DateTime timestamp) {
    final datePart = formatIsoDate(timestamp);
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    if (timestamp.second != 0) {
      final second = timestamp.second.toString().padLeft(2, '0');
      return '$datePart $hour:$minute:$second';
    }
    return '$datePart $hour:$minute';
  }

  /// Computes a strictly advancing UTC modification timestamp (`max(normalize(now), normalize(previous) + 1s)`).
  static DateTime nextModifiedTimestamp(DateTime now, DateTime? previous) {
    final normalizedNow = normalizeTimestamp(now);
    if (previous == null) {
      return normalizedNow;
    }
    final normalizedPrevious = normalizeTimestamp(previous);
    if (normalizedNow.isAfter(normalizedPrevious)) {
      return normalizedNow;
    }
    return normalizedPrevious.add(const Duration(seconds: 1));
  }

  /// Normalizes [timestamp] to UTC at second precision (truncating milliseconds and microseconds).
  static DateTime normalizeTimestamp(DateTime timestamp) {
    final utc = timestamp.toUtc();
    return DateTime.utc(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
      utc.second,
    );
  }

  /// Creates an open (incomplete) task with no `finished` timestamp.
  TaskItem toActive({
    DateTime? queuedAt,
    bool clearQueuedAt = false,
    bool? isPriority,
    bool clearBlocking = false,
    DateTime? modifiedAt,
  }) {
    return copyWith(
      isCompleted: false,
      clearCompletedAt: true,
      queuedAt: queuedAt,
      clearQueuedAt: clearQueuedAt,
      isPriority: isPriority,
      clearSuspendedAt: clearBlocking,
      blockedByTaskIds: clearBlocking ? const [] : null,
      modifiedAt: modifiedAt,
    );
  }

  /// Creates a completed task stamped with [completionDate] (`finished` and `modified` directives).
  TaskItem toCompleted(DateTime completionDate) {
    final normalized = normalizeTimestamp(completionDate);
    return copyWith(
      isCompleted: true,
      completedAt: normalized,
      modifiedAt: nextModifiedTimestamp(normalized, effectiveModifiedAt),
    );
  }

  /// Parses a strict ISO-8601 date string (`YYYY-MM-DD`) into a UTC [DateTime],
  /// returning `null` if the format or calendar date is invalid.
  static DateTime? tryParseIsoDate(String rawDate) {
    if (rawDate.length != 10 ||
        rawDate.codeUnitAt(4) != 0x2D ||
        rawDate.codeUnitAt(7) != 0x2D) {
      return null;
    }
    final year = _parseFixedDigits(rawDate, 0, 4);
    final month = _parseFixedDigits(rawDate, 5, 7);
    final day = _parseFixedDigits(rawDate, 8, 10);
    if (year == null || month == null || day == null) {
      return null;
    }
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    final candidate = DateTime.utc(year, month, day);
    if (candidate.year != year ||
        candidate.month != month ||
        candidate.day != day) {
      return null;
    }
    return candidate;
  }

  /// Parses a strict TDF `<timestamp>` (`<YYYY-MM-DD>` and optional `<HH:MM[:SS]>`) into a UTC [DateTime].
  static DateTime? tryParseTdfTimestamp(String rawDate, [String? rawTime]) {
    final baseDate = tryParseIsoDate(rawDate);
    if (baseDate == null) {
      return null;
    }
    if (rawTime == null) {
      return baseDate;
    }
    if (rawTime.length == 5) {
      final minutesFromMidnight = tryParseTimeMinutes(rawTime);
      if (minutesFromMidnight == null) {
        return null;
      }
      final hour = minutesFromMidnight ~/ 60;
      final minute = minutesFromMidnight % 60;
      return DateTime.utc(
        baseDate.year,
        baseDate.month,
        baseDate.day,
        hour,
        minute,
      );
    }
    if (rawTime.length == 8 &&
        rawTime.codeUnitAt(2) == 0x3A &&
        rawTime.codeUnitAt(5) == 0x3A) {
      final minutesFromMidnight = tryParseTimeMinutes(rawTime.substring(0, 5));
      final second = _parseFixedDigits(rawTime, 6, 8);
      if (minutesFromMidnight == null ||
          second == null ||
          second < 0 ||
          second > 59) {
        return null;
      }
      final hour = minutesFromMidnight ~/ 60;
      final minute = minutesFromMidnight % 60;
      return DateTime.utc(
        baseDate.year,
        baseDate.month,
        baseDate.day,
        hour,
        minute,
        second,
      );
    }
    return null;
  }

  /// Parses a single-line TDF `<timestamp>` string (`<YYYY-MM-DD> [<HH:MM[:SS]>]`) into a UTC [DateTime].
  static DateTime? tryParseTdfTimestampInput(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    var separatorStart = -1;
    for (var i = 0; i < trimmed.length; i++) {
      final unit = trimmed.codeUnitAt(i);
      if (unit == 0x20 || unit == 0x09) {
        separatorStart = i;
        break;
      }
    }
    if (separatorStart == -1) {
      return tryParseTdfTimestamp(trimmed);
    }
    final datePart = trimmed.substring(0, separatorStart);
    final remainder = trimmed.substring(separatorStart).trimLeft();
    for (var i = 0; i < remainder.length; i++) {
      final unit = remainder.codeUnitAt(i);
      if (unit == 0x20 || unit == 0x09) {
        return null;
      }
    }
    return tryParseTdfTimestamp(datePart, remainder);
  }

  /// Parses a strict 24-hour `<HH:MM>` token into minutes from `00:00` (`0..1439`), or `null` if invalid.
  static int? tryParseTimeMinutes(String rawTime) {
    if (rawTime.length != 5 || rawTime.codeUnitAt(2) != 0x3A) {
      return null;
    }
    final hour = _parseFixedDigits(rawTime, 0, 2);
    final minute = _parseFixedDigits(rawTime, 3, 5);
    if (hour == null || minute == null) {
      return null;
    }
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }
    return hour * 60 + minute;
  }

  /// Returns the latest non-null UTC timestamp among [created], [queued], and [completed].
  static DateTime _latestTimestamp(
    DateTime created,
    DateTime? queued,
    DateTime? completed,
  ) {
    var latest = normalizeTimestamp(created);
    if (queued case final q?) {
      final normalizedQueued = normalizeTimestamp(q);
      if (normalizedQueued.isAfter(latest)) {
        latest = normalizedQueued;
      }
    }
    if (completed case final c?) {
      final normalizedCompleted = normalizeTimestamp(c);
      if (normalizedCompleted.isAfter(latest)) {
        latest = normalizedCompleted;
      }
    }
    return latest;
  }

  /// Generates a sequential TDF-compatible identifier (`t001`, `t002`, ...).
  static String _nextId() {
    _idCounter++;
    return 't${_idCounter.toString().padLeft(3, '0')}';
  }

  /// Parses an unsigned ASCII integer from `input[start..end]`, or `null` if any char is non-digit.
  static int? _parseFixedDigits(String input, int start, int end) {
    var result = 0;
    for (var i = start; i < end; i++) {
      final unit = input.codeUnitAt(i);
      if (unit < 0x30 || unit > 0x39) {
        return null;
      }
      result = result * 10 + (unit - 0x30);
    }
    return result;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TaskItem &&
        other.id == id &&
        other.title == title &&
        other.note == note &&
        other.isCompleted == isCompleted &&
        other.isPriority == isPriority &&
        other.createdAt == createdAt &&
        other.queuedAt == queuedAt &&
        other.completedAt == completedAt &&
        other.modifiedAt == modifiedAt &&
        other.suspendedAt == suspendedAt &&
        other.repeatRule == repeatRule &&
        other.subtasksAutoFinish == subtasksAutoFinish &&
        listEquals(other.labelIds, labelIds) &&
        listEquals(other.blockedByTaskIds, blockedByTaskIds) &&
        listEquals(other.conditions, conditions) &&
        listEquals(other.subtasks, subtasks);
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    note,
    isCompleted,
    isPriority,
    createdAt,
    queuedAt,
    completedAt,
    modifiedAt,
    suspendedAt,
    repeatRule,
    subtasksAutoFinish,
    Object.hashAll(labelIds),
    Object.hashAll(blockedByTaskIds),
    Object.hashAll(conditions),
    Object.hashAll(subtasks),
  );

  @override
  String toString() => 'task $id "$title"';
}
