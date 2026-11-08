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

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'tdf_metadata.dart';
import 'tdf_sync_metadata.dart';
import 'tdf_timezone.dart';

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

/// Immutable representation of a TDF `link "<title>" "<uri>"` directive belonging to a [TaskItem].
@immutable
class TaskLink {
  /// Creates a [TaskLink] with [title] and [uri].
  const TaskLink({required this.title, required this.uri});

  /// Maximum number of `link` directives permitted on a single task (`20`).
  static const int maxLinksPerTask = 20;

  /// Maximum character length of a link `<uri>` (`2048`).
  static const int maxUriLength = 2048;

  /// Human-readable display title (`<title>`).
  final String title;

  /// Target resource URI (`<uri>`).
  final String uri;

  /// Returns a copy of this link with updated fields.
  TaskLink copyWith({String? title, String? uri}) {
    return TaskLink(title: title ?? this.title, uri: uri ?? this.uri);
  }

  /// Validates that [rawUri] is non-empty, within [maxUriLength], free of ASCII control characters,
  /// and begins with a valid URI scheme matching `[a-zA-Z][a-zA-Z0-9+.-]*:`.
  static bool isValidUri(String rawUri) {
    if (rawUri.isEmpty) {
      return false;
    }
    final scalarCount = TdfCalendar.countUnicodeScalars(rawUri);
    if (scalarCount == null || scalarCount > maxUriLength) {
      return false;
    }
    var colonIndex = -1;
    var hasNonWhitespace = false;
    for (var i = 0; i < rawUri.length; i++) {
      final unit = rawUri.codeUnitAt(i);
      if (unit <= 0x1F || unit == 0x7F) {
        return false;
      }
      if (unit != 0x20) {
        hasNonWhitespace = true;
      }
      if (colonIndex == -1 && unit == 0x3A) {
        colonIndex = i;
      }
    }
    if (!hasNonWhitespace || colonIndex <= 0) {
      return false;
    }
    if (!_isAlphaChar(rawUri.codeUnitAt(0))) {
      return false;
    }
    for (var i = 1; i < colonIndex; i++) {
      if (!_isSchemeContinueChar(rawUri.codeUnitAt(i))) {
        return false;
      }
    }
    final scheme = rawUri.substring(0, colonIndex).toLowerCase();
    if (scheme == 'javascript' || scheme == 'vbscript' || scheme == 'data') {
      return false;
    }
    return true;
  }

  /// Trims and validates [rawTitle] and [rawUri], returning a [TaskLink] or `null` if invalid.
  static TaskLink? tryParse({
    required String rawTitle,
    required String rawUri,
    int maxTextLength = 500,
  }) {
    final trimmedTitle = rawTitle.trim();
    final trimmedUri = rawUri.trim();
    if (trimmedTitle.isEmpty || trimmedTitle.length > maxTextLength) {
      return null;
    }
    if (!isValidUri(trimmedUri)) {
      return null;
    }
    return TaskLink(title: trimmedTitle, uri: trimmedUri);
  }

  /// Checks whether [unit] is an ASCII letter (`[a-zA-Z]`).
  static bool _isAlphaChar(int unit) {
    return (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);
  }

  /// Checks whether [unit] is a valid URI scheme continuation character (`[a-zA-Z0-9+.-]`).
  static bool _isSchemeContinueChar(int unit) {
    return _isAlphaChar(unit) ||
        (unit >= 0x30 && unit <= 0x39) ||
        unit == 0x2B ||
        unit == 0x2D ||
        unit == 0x2E;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TaskLink && other.title == title && other.uri == uri;
  }

  @override
  int get hashCode => Object.hash(title, uri);

  @override
  String toString() => 'link "$title" "$uri"';
}

/// Immutable representation of a TDF `origin "<namespace>" "<external-key>"` correlation key on a [TaskItem].
@immutable
class TaskOrigin {
  /// Creates a [TaskOrigin] with [namespace] and [externalKey].
  const TaskOrigin({required this.namespace, required this.externalKey});

  /// External correlation identifier within [namespace] (`1..500` single-line Unicode scalar values).
  final String externalKey;

  /// Correlation namespace (`1..500` single-line Unicode scalar values).
  final String namespace;

  /// Returns a copy of this origin with updated fields.
  TaskOrigin copyWith({String? namespace, String? externalKey}) {
    return TaskOrigin(
      namespace: namespace ?? this.namespace,
      externalKey: externalKey ?? this.externalKey,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TaskOrigin &&
        other.namespace == namespace &&
        other.externalKey == externalKey;
  }

  @override
  int get hashCode => Object.hash(namespace, externalKey);

  @override
  String toString() => 'origin "$namespace" "<redacted>"';
}

/// Immutable representation of a TDF `repeat <count> <days|weeks|months> [<repeat-time>]` rule.
@immutable
class TaskRepeatRule {
  /// Creates a [TaskRepeatRule] with positive [count], [unit], and optional local [clock].
  const TaskRepeatRule({
    required this.count,
    required this.unit,
    this.clock = TdfRepeatClock.midnight,
  });

  /// Maximum allowed recurrence interval count (`3650`).
  static const int maxRepeatCount = 3650;

  /// Intended local wall-clock time (`00:00:00` default) for recurring occurrences.
  final TdfRepeatClock clock;

  /// Number of units between recurrence cycles (`1..3650`).
  final int count;

  /// Time unit (`days`, `weeks`, or `months`) for the recurrence interval.
  final RepeatUnit unit;

  /// Computes the next UTC due timestamp per `TDF_SPEC.md` Section 6.10.3:
  /// 1. Converts [completedAtUtc] into `localNow` in [timeZone].
  /// 2. Adds the interval to `localNow`'s calendar date.
  /// 3. Combines the target local date with [clock] and resolves to UTC via Section 6.10.2.
  /// 4. Requires the resulting UTC instant to be strictly later than [completedAtUtc].
  DateTime nextDueUtc({
    required DateTime completedAtUtc,
    required TdfTimeZoneContext timeZone,
  }) {
    final normalizedCompletionUtc = TaskItem.normalizeTimestamp(completedAtUtc);
    final localNow = timeZone.toLocalWallClock(normalizedCompletionUtc);
    final targetLocal = switch (unit) {
      RepeatUnit.days => _addDays(
        localNow,
        count,
        clock.hour,
        clock.minute,
        clock.second,
      ),
      RepeatUnit.weeks => _addDays(
        localNow,
        count * 7,
        clock.hour,
        clock.minute,
        clock.second,
      ),
      RepeatUnit.months => _addMonths(
        localNow,
        count,
        clock.hour,
        clock.minute,
        clock.second,
      ),
    };
    final resolvedUtc = timeZone.resolveLocalToUtc(
      targetLocal.year,
      targetLocal.month,
      targetLocal.day,
      targetLocal.hour,
      targetLocal.minute,
      targetLocal.second,
    );
    if (!resolvedUtc.isAfter(normalizedCompletionUtc)) {
      throw const FormatException('InvalidTimestamp');
    }
    return resolvedUtc;
  }

  /// Computes the next local due timestamp relative to [completionLocalTime],
  /// using [clock] (or preserving a non-midnight `<HH:MM[:SS]>` from [previousSuspendedAt] when [clock] is midnight).
  DateTime nextLocalDueDate(
    DateTime completionLocalTime, {
    DateTime? previousSuspendedAt,
  }) {
    final int targetHour;
    final int targetMinute;
    final int targetSecond;
    if (!clock.isMidnight) {
      targetHour = clock.hour;
      targetMinute = clock.minute;
      targetSecond = clock.second;
    } else {
      final hasExplicitSuspendedTime =
          previousSuspendedAt != null &&
          previousSuspendedAt != TaskItem.defaultSuspendedAt &&
          (previousSuspendedAt.hour != 0 ||
              previousSuspendedAt.minute != 0 ||
              previousSuspendedAt.second != 0);
      targetHour = hasExplicitSuspendedTime ? previousSuspendedAt.hour : 0;
      targetMinute = hasExplicitSuspendedTime ? previousSuspendedAt.minute : 0;
      targetSecond = hasExplicitSuspendedTime ? previousSuspendedAt.second : 0;
    }

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

  /// Computes the next schedule-anchored occurrence (`newDueUtc`, `newSuspendedUtc`, `stepsK`)
  /// when completing a recurring task that has a `due` deadline per `spec/TDF_SPEC_0.6.0.md` Section 6.10.3 Mode 2.
  ({DateTime newDueUtc, DateTime newSuspendedUtc, int stepsK})
  nextScheduleAnchoredOccurrence({
    required DateTime completedAtUtc,
    required DateTime oldDueUtc,
    DateTime? oldSuspendedUtc,
    bool isSuspendedForever = false,
    required TdfTimeZoneContext timeZone,
  }) {
    final normalizedCompletionUtc = TaskItem.normalizeTimestamp(completedAtUtc);
    final normalizedOldDue = TaskItem.normalizeTimestamp(oldDueUtc);
    final oldDueLocal = timeZone.toLocalWallClock(normalizedOldDue);

    var stepsK = 1;
    late DateTime targetDueLocal;
    late DateTime newDueUtc;
    while (true) {
      targetDueLocal = _advanceLocalDate(
        oldDueLocal,
        stepsK,
        oldDueLocal.hour,
        oldDueLocal.minute,
        oldDueLocal.second,
      );
      if (!TdfCalendar.isWithinTimestampBounds(targetDueLocal)) {
        throw const FormatException('InvalidTimestamp');
      }
      newDueUtc = timeZone.resolveLocalToUtc(
        targetDueLocal.year,
        targetDueLocal.month,
        targetDueLocal.day,
        targetDueLocal.hour,
        targetDueLocal.minute,
        targetDueLocal.second,
      );
      if (!TdfCalendar.isWithinTimestampBounds(newDueUtc)) {
        throw const FormatException('InvalidTimestamp');
      }
      if (newDueUtc.isAfter(normalizedCompletionUtc)) {
        break;
      }
      stepsK++;
    }

    final normalizedOldSuspended = oldSuspendedUtc == null
        ? null
        : TaskItem.normalizeTimestamp(oldSuspendedUtc);
    final hasLeadWindow =
        normalizedOldSuspended != null &&
        !isSuspendedForever &&
        normalizedOldSuspended != TaskItem.defaultSuspendedAt &&
        normalizedOldSuspended.isBefore(normalizedOldDue);

    if (!hasLeadWindow) {
      final candidateSuspended = timeZone.resolveLocalToUtc(
        targetDueLocal.year,
        targetDueLocal.month,
        targetDueLocal.day,
        clock.hour,
        clock.minute,
        clock.second,
      );
      if (!TdfCalendar.isWithinTimestampBounds(candidateSuspended)) {
        throw const FormatException('InvalidTimestamp');
      }
      final clampedSuspended = candidateSuspended.isBefore(newDueUtc)
          ? candidateSuspended
          : newDueUtc;
      return (
        newDueUtc: newDueUtc,
        newSuspendedUtc: clampedSuspended,
        stepsK: stepsK,
      );
    }

    final oldSuspLocal = timeZone.toLocalWallClock(normalizedOldSuspended);
    final rawTargetSuspLocal = _advanceLocalDate(
      oldSuspLocal,
      stepsK,
      oldSuspLocal.hour,
      oldSuspLocal.minute,
      oldSuspLocal.second,
    );
    var targetSuspDay = rawTargetSuspLocal.day;
    if (unit == RepeatUnit.months &&
        oldSuspLocal.year == oldDueLocal.year &&
        oldSuspLocal.month == oldDueLocal.month &&
        oldSuspLocal.day < oldDueLocal.day) {
      final dEnd = TdfCalendar.daysInMonth(
        targetDueLocal.year,
        targetDueLocal.month,
      );
      if (rawTargetSuspLocal.day == dEnd && targetDueLocal.day == dEnd) {
        targetSuspDay = math.max(
          1,
          dEnd - (oldDueLocal.day - oldSuspLocal.day),
        );
      }
    }

    final sameLocalDate =
        rawTargetSuspLocal.year == targetDueLocal.year &&
        rawTargetSuspLocal.month == targetDueLocal.month &&
        targetSuspDay == targetDueLocal.day;
    final repeatClockSeconds =
        clock.hour * 3600 + clock.minute * 60 + clock.second;
    final dueClockSeconds =
        oldDueLocal.hour * 3600 + oldDueLocal.minute * 60 + oldDueLocal.second;
    final useRepeatClock =
        !clock.isMidnight &&
        !(sameLocalDate && repeatClockSeconds >= dueClockSeconds);
    final chosenHour = useRepeatClock ? clock.hour : oldSuspLocal.hour;
    final chosenMinute = useRepeatClock ? clock.minute : oldSuspLocal.minute;
    final chosenSecond = useRepeatClock ? clock.second : oldSuspLocal.second;

    var candidateSuspended = timeZone.resolveLocalToUtc(
      rawTargetSuspLocal.year,
      rawTargetSuspLocal.month,
      targetSuspDay,
      chosenHour,
      chosenMinute,
      chosenSecond,
    );
    if (sameLocalDate &&
        useRepeatClock &&
        !candidateSuspended.isBefore(newDueUtc)) {
      candidateSuspended = timeZone.resolveLocalToUtc(
        rawTargetSuspLocal.year,
        rawTargetSuspLocal.month,
        targetSuspDay,
        oldSuspLocal.hour,
        oldSuspLocal.minute,
        oldSuspLocal.second,
      );
    }
    if (!TdfCalendar.isWithinTimestampBounds(candidateSuspended)) {
      throw const FormatException('InvalidTimestamp');
    }
    final clampedSuspended = candidateSuspended.isBefore(newDueUtc)
        ? candidateSuspended
        : newDueUtc;
    return (
      newDueUtc: newDueUtc,
      newSuspendedUtc: clampedSuspended,
      stepsK: stepsK,
    );
  }

  /// Formats this rule as canonical TDF directive arguments (`<count> <unit> [<repeat-time>]`).
  String toTdfDirectiveArgs() {
    final clockText = clock.formatCanonical();
    if (clockText.isEmpty) {
      return '$count ${unit.tdfToken}';
    }
    return '$count ${unit.tdfToken} $clockText';
  }

  /// Advances [baseDate] by `stepsK * count` units while preserving the given local wall-clock time.
  DateTime _advanceLocalDate(
    DateTime baseDate,
    int stepsK,
    int hour,
    int minute,
    int second,
  ) {
    return switch (unit) {
      RepeatUnit.days => _addDays(
        baseDate,
        count * stepsK,
        hour,
        minute,
        second,
      ),
      RepeatUnit.weeks => _addDays(
        baseDate,
        count * 7 * stepsK,
        hour,
        minute,
        second,
      ),
      RepeatUnit.months => _addMonths(
        baseDate,
        count * stepsK,
        hour,
        minute,
        second,
      ),
    };
  }

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
    final maxDayInTargetMonth = TdfCalendar.daysInMonth(
      targetYear,
      targetMonth,
    );
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
        other.unit == unit &&
        other.clock == clock;
  }

  @override
  int get hashCode => Object.hash(count, unit, clock);

  @override
  String toString() => 'repeat ${toTdfDirectiveArgs()}';
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
    int? completions,
    DateTime? createdAt,
    this.completedAt,
    this.modifiedAt,
    this.suspendedAt,
    this.isSuspendedForever = false,
    this.dueAt,
    this.origin,
    this.repeatRule,
    List<String> labelIds = const [],
    List<String>? blockedByTaskIds,
    List<TdfTaskDependency>? dependencies,
    List<TaskLink> links = const [],
    List<TaskCondition> conditions = const [],
    this.subtasksAutoFinish = false,
    List<SubtaskItem> subtasks = const [],
  }) : id = id ?? generateTaskId(timestamp: createdAt ?? defaultCreatedAt),
       createdAt = createdAt ?? defaultCreatedAt,
       completions =
           completions ?? ((isCompleted || completedAt != null) ? 1 : 0),
       labelIds = List<String>.unmodifiable(labelIds),
       dependencies = dependencies != null
           ? List<TdfTaskDependency>.unmodifiable(dependencies)
           : TdfTaskDependency.fromTaskIds(blockedByTaskIds ?? const []),
       blockedByTaskIds = blockedByTaskIds != null
           ? List<String>.unmodifiable(blockedByTaskIds)
           : List<String>.unmodifiable(<String>[
               if (dependencies != null)
                 for (final dep in dependencies) dep.taskId,
             ]),
       links = List<TaskLink>.unmodifiable(links),
       conditions = List<TaskCondition>.unmodifiable(conditions),
       subtasks = List<SubtaskItem>.unmodifiable(subtasks);

  /// Fallback UTC creation timestamp when none is provided explicitly.
  static final DateTime defaultCreatedAt = DateTime.utc(2026, 11, 1, 8, 0);

  /// Far-future UTC deferral timestamp sentinel retained for legacy compatibility.
  static final DateTime defaultSuspendedAt = DateTime.utc(9999, 12, 31, 23, 59);

  /// Prerequisite task IDs (`blocked` directive).
  final List<String> blockedByTaskIds;

  /// Completion timestamp (`finished` directive) when located in Tier 6 (`Completed`).
  final DateTime? completedAt;

  /// Cumulative completion counter (`completions` directive, `0..999,999,999`).
  final int completions;

  /// Dynamic activation conditions (`condition` directives).
  final List<TaskCondition> conditions;

  /// Creation timestamp (`created` directive).
  final DateTime createdAt;

  /// Prerequisite task dependencies with required completion counts (`blocked <task-id>[:<n>]`).
  final List<TdfTaskDependency> dependencies;

  /// Optional target deadline in UTC (`due` directive).
  final DateTime? dueAt;

  /// Unique TDF task entity identifier (`<id>`).
  final String id;

  /// Whether the task is completed (`finished` is present).
  final bool isCompleted;

  /// Whether the task carries the `priority` header flag.
  final bool isPriority;

  /// Whether the task carries an indefinite deferral (`suspended forever`).
  final bool isSuspendedForever;

  /// Associated label IDs (`labels` directive).
  final List<String> labelIds;

  /// External or internal resource links (`link` directives).
  final List<TaskLink> links;

  /// Optional UTC modification timestamp (`modified` directive).
  final DateTime? modifiedAt;

  /// Optional extended description (`note` directive).
  final String? note;

  /// Optional passive machine correlation key (`origin` directive).
  final TaskOrigin? origin;

  /// Optional recurrence rule (`repeat` directive).
  final TaskRepeatRule? repeatRule;

  /// Ordered checklist steps (`subtasks` sub-block).
  final List<SubtaskItem> subtasks;

  /// Whether the `subtasks` sub-block carries the `auto-finish` header flag.
  final bool subtasksAutoFinish;

  /// Optional finite UTC deferral timestamp (`suspended <timestamp>` directive).
  final DateTime? suspendedAt;

  /// Human-readable task title (`name` directive).
  final String title;

  /// Effective UTC modification timestamp (`modifiedAt ?? max(createdAt, completedAt)`).
  DateTime get effectiveModifiedAt =>
      modifiedAt ?? _latestTimestamp(createdAt, completedAt);

  /// Returns a copy of this task with the provided fields updated.
  TaskItem copyWith({
    String? id,
    String? title,
    String? note,
    bool? isCompleted,
    bool? isPriority,
    int? completions,
    DateTime? createdAt,
    DateTime? completedAt,
    DateTime? modifiedAt,
    DateTime? suspendedAt,
    bool? isSuspendedForever,
    DateTime? dueAt,
    TaskOrigin? origin,
    TaskRepeatRule? repeatRule,
    List<String>? labelIds,
    List<String>? blockedByTaskIds,
    List<TdfTaskDependency>? dependencies,
    List<TaskLink>? links,
    List<TaskCondition>? conditions,
    bool? subtasksAutoFinish,
    List<SubtaskItem>? subtasks,
    bool clearNote = false,
    bool clearCompletedAt = false,
    bool clearModifiedAt = false,
    bool clearSuspendedAt = false,
    bool clearDueAt = false,
    bool clearOrigin = false,
    bool clearRepeatRule = false,
  }) {
    final resolvedDependencies = _resolveCopyWithDependencies(
      currentDependencies: this.dependencies,
      newDependencies: dependencies,
      newBlockedByTaskIds: blockedByTaskIds,
    );
    final resolvedBlockedIds =
        blockedByTaskIds ??
        <String>[for (final dep in resolvedDependencies) dep.taskId];
    return TaskItem(
      id: id ?? this.id,
      title: title ?? this.title,
      note: clearNote ? null : (note ?? this.note),
      isCompleted: isCompleted ?? this.isCompleted,
      isPriority: isPriority ?? this.isPriority,
      completions: completions ?? this.completions,
      createdAt: createdAt ?? this.createdAt,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      modifiedAt: clearModifiedAt ? null : (modifiedAt ?? this.modifiedAt),
      suspendedAt: clearSuspendedAt ? null : (suspendedAt ?? this.suspendedAt),
      isSuspendedForever: clearSuspendedAt
          ? (isSuspendedForever ?? false)
          : (isSuspendedForever ??
                (suspendedAt != null ? false : this.isSuspendedForever)),
      dueAt: clearDueAt ? null : (dueAt ?? this.dueAt),
      origin: clearOrigin ? null : (origin ?? this.origin),
      repeatRule: clearRepeatRule ? null : (repeatRule ?? this.repeatRule),
      labelIds: labelIds ?? this.labelIds,
      blockedByTaskIds: resolvedBlockedIds,
      dependencies: resolvedDependencies,
      links: links ?? this.links,
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

  /// Formats [timestamp] with explicit seconds (`YYYY-MM-DD HH:MM:SS`) for `deleted`, `queue.modified`, and finite `suspended` directives.
  static String formatTdfTimestampWithSeconds(DateTime timestamp) {
    final datePart = formatIsoDate(timestamp);
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final second = timestamp.second.toString().padLeft(2, '0');
    return '$datePart $hour:$minute:$second';
  }

  /// Computes a strictly advancing UTC modification timestamp (`max(normalize(now), normalize(previous) + 1s)`).
  ///
  /// Throws [FormatException] (`InvalidTimestamp`) if the resulting timestamp exceeds `9999-12-31 23:59:59` UTC.
  static DateTime nextModifiedTimestamp(DateTime now, DateTime? previous) {
    final normalizedNow = normalizeTimestamp(now);
    if (!TdfCalendar.isWithinTimestampBounds(normalizedNow)) {
      throw const FormatException('InvalidTimestamp');
    }
    if (previous == null) {
      return normalizedNow;
    }
    final normalizedPrevious = normalizeTimestamp(previous);
    if (normalizedNow.isAfter(normalizedPrevious)) {
      return normalizedNow;
    }
    final advanced = normalizedPrevious.add(const Duration(seconds: 1));
    if (!TdfCalendar.isWithinTimestampBounds(advanced)) {
      throw const FormatException('InvalidTimestamp');
    }
    return advanced;
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
    bool? isPriority,
    bool clearBlocking = false,
    bool clearDueAt = false,
    DateTime? modifiedAt,
  }) {
    return copyWith(
      isCompleted: false,
      clearCompletedAt: true,
      isPriority: isPriority,
      clearSuspendedAt: clearBlocking,
      clearDueAt: clearDueAt,
      blockedByTaskIds: clearBlocking ? const [] : null,
      dependencies: clearBlocking ? const [] : null,
      modifiedAt: modifiedAt,
    );
  }

  /// Creates a completed task stamped with [completionDate] (`finished` and `modified` directives)
  /// and marks all subtasks as completed.
  TaskItem toCompleted(DateTime completionDate) {
    final normalized = normalizeTimestamp(completionDate);
    final completedSubtasks = subtasks.isEmpty
        ? subtasks
        : <SubtaskItem>[
            for (final step in subtasks)
              step.isCompleted ? step : step.copyWith(isCompleted: true),
          ];
    final nextCompletions = isCompleted ? completions : completions + 1;
    return copyWith(
      isCompleted: true,
      completedAt: normalized,
      completions: nextCompletions,
      subtasks: completedSubtasks,
      modifiedAt: nextModifiedTimestamp(normalized, effectiveModifiedAt),
    );
  }

  /// Parses a strict ISO-8601 date string (`YYYY-MM-DD`) in `0001-01-01..9999-12-31` into a UTC [DateTime],
  /// returning `null` if the format or proleptic Gregorian calendar date is invalid.
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
    if (!TdfCalendar.isValidGregorianDate(year, month, day)) {
      return null;
    }
    return DateTime.utc(year, month, day);
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

  /// Returns the latest non-null UTC timestamp between [created] and [completed].
  static DateTime _latestTimestamp(DateTime created, DateTime? completed) {
    var latest = normalizeTimestamp(created);
    if (completed case final c?) {
      final normalizedCompleted = normalizeTimestamp(c);
      if (normalizedCompleted.isAfter(latest)) {
        latest = normalizedCompleted;
      }
    }
    return latest;
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

  /// Resolves the updated [TdfTaskDependency] list during [copyWith], preserving existing required completion counts when only [newBlockedByTaskIds] is provided.
  static List<TdfTaskDependency> _resolveCopyWithDependencies({
    required List<TdfTaskDependency> currentDependencies,
    required List<TdfTaskDependency>? newDependencies,
    required List<String>? newBlockedByTaskIds,
  }) {
    if (newDependencies != null) {
      return newDependencies;
    }
    if (newBlockedByTaskIds == null) {
      return currentDependencies;
    }
    final existingMap = <String, int>{
      for (final dep in currentDependencies) dep.taskId: dep.requiredCompletion,
    };
    final result = <TdfTaskDependency>[];
    final seen = <String>{};
    for (final id in newBlockedByTaskIds) {
      if (seen.add(id)) {
        result.add(
          TdfTaskDependency(
            taskId: id,
            requiredCompletion: existingMap[id] ?? 1,
          ),
        );
      }
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
        other.completions == completions &&
        other.createdAt == createdAt &&
        other.completedAt == completedAt &&
        other.modifiedAt == modifiedAt &&
        other.suspendedAt == suspendedAt &&
        other.isSuspendedForever == isSuspendedForever &&
        other.dueAt == dueAt &&
        other.origin == origin &&
        other.repeatRule == repeatRule &&
        other.subtasksAutoFinish == subtasksAutoFinish &&
        listEquals(other.labelIds, labelIds) &&
        listEquals(other.blockedByTaskIds, blockedByTaskIds) &&
        listEquals(other.dependencies, dependencies) &&
        listEquals(other.links, links) &&
        listEquals(other.conditions, conditions) &&
        listEquals(other.subtasks, subtasks);
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
    id,
    title,
    note,
    isCompleted,
    isPriority,
    completions,
    createdAt,
    completedAt,
    modifiedAt,
    suspendedAt,
    isSuspendedForever,
    dueAt,
    origin,
    repeatRule,
    subtasksAutoFinish,
    Object.hashAll(labelIds),
    Object.hashAll(blockedByTaskIds),
    Object.hashAll(dependencies),
    Object.hashAll(links),
    Object.hashAll(conditions),
    Object.hashAll(subtasks),
  ]);

  @override
  String toString() => 'task $id "$title"';
}
