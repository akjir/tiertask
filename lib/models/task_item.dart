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

import 'tdf_error.dart';
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

/// Immutable representation of a TDF `history <timestamp> "<text>"` entry on a [TaskItem].
@immutable
class TaskHistoryEntry {
  /// Creates a [TaskHistoryEntry] with [timestampUtc] normalized to UTC seconds and single-line [text].
  TaskHistoryEntry({required DateTime timestampUtc, required this.text})
    : timestampUtc = TaskItem.normalizeTimestamp(timestampUtc);

  /// Single-line user-authored event description (`1..500` Unicode scalar values).
  final String text;

  /// Event UTC timestamp truncated to whole seconds.
  final DateTime timestampUtc;

  /// Compares two [TaskHistoryEntry] items by ascending [timestampUtc] and unsigned UTF-8 byte order of [text].
  static int compareCanonical(TaskHistoryEntry a, TaskHistoryEntry b) {
    final timeCompare = a.timestampUtc.millisecondsSinceEpoch.compareTo(
      b.timestampUtc.millisecondsSinceEpoch,
    );
    if (timeCompare != 0) return timeCompare;
    return compareUtf8Strings(a.text, b.text);
  }

  /// Compares [left] and [right] in exact unsigned UTF-8 byte order without allocating intermediate byte buffers.
  static int compareUtf8Strings(String left, String right) {
    if (identical(left, right)) {
      return 0;
    }
    final leftLength = left.length;
    final rightLength = right.length;
    var leftIndex = 0;
    var rightIndex = 0;
    while (leftIndex < leftLength && rightIndex < rightLength) {
      final leftUnit = left.codeUnitAt(leftIndex);
      final rightUnit = right.codeUnitAt(rightIndex);
      if (leftUnit < 0xD800 && rightUnit < 0xD800) {
        if (leftUnit != rightUnit) {
          return leftUnit < rightUnit ? -1 : 1;
        }
        leftIndex++;
        rightIndex++;
        continue;
      }
      if (leftUnit == rightUnit && leftUnit > 0xDFFF) {
        leftIndex++;
        rightIndex++;
        continue;
      }
      final leftStep = _decodeUtf8Scalar(left, leftIndex, leftLength);
      final rightStep = _decodeUtf8Scalar(right, rightIndex, rightLength);
      if (leftStep.scalar != rightStep.scalar) {
        return leftStep.scalar < rightStep.scalar ? -1 : 1;
      }
      leftIndex = leftStep.nextIndex;
      rightIndex = rightStep.nextIndex;
    }
    if (leftIndex < leftLength) return 1;
    if (rightIndex < rightLength) return -1;
    return 0;
  }

  /// Sorts [entries] via [compareCanonical] and deduplicates exact `(timestampUtc, text)` pairs into an unmodifiable list.
  static List<TaskHistoryEntry> normalizeList(
    Iterable<TaskHistoryEntry> entries,
  ) {
    final sorted = List<TaskHistoryEntry>.from(entries);
    if (sorted.isEmpty) {
      return const <TaskHistoryEntry>[];
    }
    sorted.sort(compareCanonical);
    final deduplicated = <TaskHistoryEntry>[sorted.first];
    for (var i = 1; i < sorted.length; i++) {
      final candidate = sorted[i];
      if (candidate != deduplicated.last) {
        deduplicated.add(candidate);
      }
    }
    return List<TaskHistoryEntry>.unmodifiable(deduplicated);
  }

  /// Decodes the next UTF-8-equivalent Unicode scalar value at [index] in [value], mapping unpaired surrogates to `U+FFFD`.
  static ({int scalar, int nextIndex}) _decodeUtf8Scalar(
    String value,
    int index,
    int length,
  ) {
    final unit = value.codeUnitAt(index);
    if (unit < 0xD800 || unit > 0xDFFF) {
      return (scalar: unit, nextIndex: index + 1);
    }
    if (unit <= 0xDBFF && index + 1 < length) {
      final low = value.codeUnitAt(index + 1);
      if (low >= 0xDC00 && low <= 0xDFFF) {
        final scalar = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00);
        return (scalar: scalar, nextIndex: index + 2);
      }
    }
    return (scalar: 0xFFFD, nextIndex: index + 1);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TaskHistoryEntry &&
        other.timestampUtc == timestampUtc &&
        other.text == text;
  }

  @override
  int get hashCode => Object.hash(timestampUtc, text);

  @override
  String toString() =>
      'history ${TaskItem.formatTdfTimestampWithSeconds(timestampUtc)} "<redacted>"';
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

/// Immutable representation of a TDF `repeat <count> <days|weeks|months> [<repeat-time>] [lead <n> days]` rule.
@immutable
class TaskRepeatRule {
  /// Creates a [TaskRepeatRule] with positive [count], [unit], optional local [clock], and [leadDays].
  const TaskRepeatRule({
    required this.count,
    required this.unit,
    this.clock = TdfRepeatClock.midnight,
    this.leadDays = 0,
  });

  /// Maximum allowed recurrence interval or lead-window day count (`3650`).
  static const int maxRepeatCount = maxTdfRepeatCount;

  /// Maximum calendar days between `0001-01-01` and `9999-12-31` (`3,652,058` days).
  static const int _maxProlepticDaySpan = 3652058;

  /// Intended local wall-clock time (`00:00:00` default) for recurring occurrences.
  final TdfRepeatClock clock;

  /// Number of units between recurrence cycles (`1..3650`).
  final int count;

  /// Local calendar lead window in days (`0..3650`) subtracted from the next `due` date in Mode 2 recurrence.
  final int leadDays;

  /// Time unit (`days`, `weeks`, or `months`) for the recurrence interval.
  final RepeatUnit unit;

  /// Computes the next Mode 2 schedule-anchored occurrence (`newDueUtc`, `newAnchor`, `newSuspendedUtc`, `stepsK`) per `TDF-CAL-003`.
  ({
    DateTime newDueUtc,
    TdfLocalDateTime newAnchor,
    DateTime? newSuspendedUtc,
    int stepsK,
  })
  computeNextMode2Schedule({
    required DateTime completedAtUtc,
    required DateTime oldDueUtc,
    TdfLocalDateTime? oldAnchor,
    required TdfTimeZoneContext timeZone,
  }) {
    final nowUtc = TaskItem.normalizeTimestamp(completedAtUtc);
    final oldDue = TaskItem.normalizeTimestamp(oldDueUtc);
    if (!TdfCalendar.isWithinTimestampBounds(nowUtc) ||
        !TdfCalendar.isWithinTimestampBounds(oldDue)) {
      throw const TdfException(
        kind: TdfErrorKind.invalidTimestamp,
        line: 1,
        message: 'Recurrence input timestamp is outside 0001..9999 UTC.',
      );
    }
    if (!timeZone.isAvailable) {
      throw const TdfContextException(
        kind: TdfContextOutcomeKind.timeZoneContextRequired,
        message: 'Time zone context is required for Mode 2 recurrence.',
      );
    }
    final anchor = _resolveMode2Anchor(oldAnchor, oldDue, timeZone);
    final referenceUtc = oldDue.isAfter(nowUtc) ? oldDue : nowUtc;
    final nextDue = unit == RepeatUnit.months
        ? _advanceMonthlyMode2Due(
            oldDueUtc: oldDue,
            anchor: anchor,
            referenceUtc: referenceUtc,
            timeZone: timeZone,
          )
        : _advanceDayOrWeekMode2Due(
            anchor: anchor,
            referenceUtc: referenceUtc,
            timeZone: timeZone,
          );
    final newSuspendedUtc = _computeMode2WakeUpInstant(
      targetYear: nextDue.targetYear,
      targetMonth: nextDue.targetMonth,
      targetDay: nextDue.targetDay,
      newDueUtc: nextDue.newDueUtc,
      nowUtc: nowUtc,
      timeZone: timeZone,
    );
    return (
      newDueUtc: nextDue.newDueUtc,
      newAnchor: nextDue.newAnchor,
      newSuspendedUtc: newSuspendedUtc,
      stepsK: nextDue.stepsK,
    );
  }

  /// Returns a copy of this recurrence rule with updated fields.
  TaskRepeatRule copyWith({
    int? count,
    RepeatUnit? unit,
    TdfRepeatClock? clock,
    int? leadDays,
  }) {
    return TaskRepeatRule(
      count: count ?? this.count,
      unit: unit ?? this.unit,
      clock: clock ?? this.clock,
      leadDays: leadDays ?? this.leadDays,
    );
  }

  /// Computes the Mode 1 completion-relative UTC deferral timestamp (`due` omitted) per `TDF-CAL-002`.
  DateTime nextDueUtc({
    required DateTime completedAtUtc,
    required TdfTimeZoneContext timeZone,
  }) {
    if (!timeZone.isAvailable) {
      throw const TdfContextException(
        kind: TdfContextOutcomeKind.timeZoneContextRequired,
        message: 'Time zone context is required for Mode 1 recurrence.',
      );
    }
    final normalizedCompletionUtc = TaskItem.normalizeTimestamp(completedAtUtc);
    if (!TdfCalendar.isWithinTimestampBounds(normalizedCompletionUtc)) {
      _throwInvalidRecurrenceTimestamp();
    }
    final localNow = _toLocalDateTimeOrThrowTdf(
      timeZone,
      normalizedCompletionUtc,
    );
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
    final resolvedUtc = _resolveLocalOrThrowTdf(
      timeZone,
      targetLocal.year,
      targetLocal.month,
      targetLocal.day,
      targetLocal.hour,
      targetLocal.minute,
      targetLocal.second,
    );
    if (!resolvedUtc.isAfter(normalizedCompletionUtc)) {
      _throwInvalidRecurrenceTimestamp();
    }
    return resolvedUtc;
  }

  /// Formats this rule as canonical TDF directive arguments (`<count> <unit> [<repeat-time>] [lead <n> days]`).
  String toTdfDirectiveArgs() {
    final clockText = clock.formatCanonical();
    final base = clockText.isEmpty
        ? '$count ${unit.tdfToken}'
        : '$count ${unit.tdfToken} $clockText';
    if (leadDays <= 0) {
      return base;
    }
    return '$base lead $leadDays days';
  }

  /// Adds [daysToAdd] calendar days to [baseDate] with the given time-of-day components.
  static DateTime _addDays(
    TdfLocalDateTime baseDate,
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
    TdfLocalDateTime baseDate,
    int monthsToAdd,
    int hour,
    int minute,
    int second,
  ) {
    final totalMonths =
        (baseDate.year * 12) + (baseDate.month - 1) + monthsToAdd;
    final targetYear = totalMonths ~/ 12;
    final targetMonth = (totalMonths % 12) + 1;
    final maxDayInTargetMonth = (targetYear >= 1 && targetYear <= 9999)
        ? TdfCalendar.daysInMonth(targetYear, targetMonth)
        : 31;
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

  /// Advances `days` or `weeks` Mode 2 deadline in $O(1)$ integer arithmetic beyond [referenceUtc] (`TDF-CAL-003`).
  ({
    int targetYear,
    int targetMonth,
    int targetDay,
    DateTime newDueUtc,
    TdfLocalDateTime newAnchor,
    int stepsK,
  })
  _advanceDayOrWeekMode2Due({
    required TdfLocalDateTime anchor,
    required DateTime referenceUtc,
    required TdfTimeZoneContext timeZone,
  }) {
    final stepDays = unit == RepeatUnit.weeks ? count * 7 : count;
    final anchorDateUtc = DateTime.utc(anchor.year, anchor.month, anchor.day);
    final refLocal = _toLocalDateTimeOrThrowTdf(timeZone, referenceUtc);
    final refDateUtc = DateTime.utc(
      refLocal.year,
      refLocal.month,
      refLocal.day,
    );
    final diffDays = refDateUtc.difference(anchorDateUtc).inDays;
    final initialK = diffDays <= 0
        ? 1
        : math.max(1, (diffDays ~/ stepDays) - 2);
    for (var probe = 0; probe <= 6; probe++) {
      final k = initialK + probe;
      final totalDays = k * stepDays;
      if (totalDays > _maxProlepticDaySpan) {
        _throwInvalidRecurrenceTimestamp();
      }
      final targetDate = anchorDateUtc.add(Duration(days: totalDays));
      if (targetDate.year < 1 || targetDate.year > 9999) {
        _throwInvalidRecurrenceTimestamp();
      }
      final candidateUtc = _resolveLocalOrThrowTdf(
        timeZone,
        targetDate.year,
        targetDate.month,
        targetDate.day,
        anchor.hour,
        anchor.minute,
        anchor.second,
      );
      if (candidateUtc.isAfter(referenceUtc)) {
        return (
          targetYear: targetDate.year,
          targetMonth: targetDate.month,
          targetDay: targetDate.day,
          newDueUtc: candidateUtc,
          newAnchor: TdfLocalDateTime(
            targetDate.year,
            targetDate.month,
            targetDate.day,
            anchor.hour,
            anchor.minute,
            anchor.second,
          ),
          stepsK: k,
        );
      }
    }
    _throwInvalidRecurrenceTimestamp();
  }

  /// Advances `months` Mode 2 deadline from `oldDue`'s `(Y_cur, M_cur)` clamping against `anchor.day` (`TDF-CAL-003`).
  ({
    int targetYear,
    int targetMonth,
    int targetDay,
    DateTime newDueUtc,
    TdfLocalDateTime newAnchor,
    int stepsK,
  })
  _advanceMonthlyMode2Due({
    required DateTime oldDueUtc,
    required TdfLocalDateTime anchor,
    required DateTime referenceUtc,
    required TdfTimeZoneContext timeZone,
  }) {
    final oldDueLocal = _toLocalDateTimeOrThrowTdf(timeZone, oldDueUtc);
    final refLocal = _toLocalDateTimeOrThrowTdf(timeZone, referenceUtc);
    final diffMonths =
        (refLocal.year - oldDueLocal.year) * 12 +
        (refLocal.month - oldDueLocal.month);
    final initialK = diffMonths <= 0
        ? 1
        : math.max(1, (diffMonths ~/ count) - 2);
    for (var probe = 0; probe <= 6; probe++) {
      final k = initialK + probe;
      final totalMonths =
          (oldDueLocal.year * 12) + (oldDueLocal.month - 1) + (k * count);
      final targetYear = totalMonths ~/ 12;
      final targetMonth = (totalMonths % 12) + 1;
      if (targetYear < 1 || targetYear > 9999) {
        _throwInvalidRecurrenceTimestamp();
      }
      final maxDay = TdfCalendar.daysInMonth(targetYear, targetMonth);
      final clampedDay = anchor.day <= maxDay ? anchor.day : maxDay;
      final candidateUtc = _resolveLocalOrThrowTdf(
        timeZone,
        targetYear,
        targetMonth,
        clampedDay,
        anchor.hour,
        anchor.minute,
        anchor.second,
      );
      if (candidateUtc.isAfter(referenceUtc)) {
        final nextAnchor = clampedDay == anchor.day
            ? TdfLocalDateTime(
                targetYear,
                targetMonth,
                clampedDay,
                anchor.hour,
                anchor.minute,
                anchor.second,
              )
            : anchor;
        return (
          targetYear: targetYear,
          targetMonth: targetMonth,
          targetDay: clampedDay,
          newDueUtc: candidateUtc,
          newAnchor: nextAnchor,
          stepsK: k,
        );
      }
    }
    _throwInvalidRecurrenceTimestamp();
  }

  /// Computes the Mode 2 wake-up `suspended` instant (`null` when `<= nowUtc`) per `TDF-CAL-003` Steps 4–6.
  DateTime? _computeMode2WakeUpInstant({
    required int targetYear,
    required int targetMonth,
    required int targetDay,
    required DateTime newDueUtc,
    required DateTime nowUtc,
    required TdfTimeZoneContext timeZone,
  }) {
    final targetSuspendedDate = DateTime.utc(
      targetYear,
      targetMonth,
      targetDay,
    ).subtract(Duration(days: leadDays));
    if (targetSuspendedDate.year < 1 || targetSuspendedDate.year > 9999) {
      _throwInvalidRecurrenceTimestamp();
    }
    final candidateSuspended = _resolveLocalOrThrowTdf(
      timeZone,
      targetSuspendedDate.year,
      targetSuspendedDate.month,
      targetSuspendedDate.day,
      clock.hour,
      clock.minute,
      clock.second,
    );
    final clamped = candidateSuspended.isAfter(newDueUtc)
        ? newDueUtc
        : candidateSuspended;
    return clamped.isAfter(nowUtc) ? clamped : null;
  }

  /// Resolves local components via [timeZone], mapping out-of-bounds [FormatException] to [TdfException] (`invalidTimestamp`).
  static DateTime _resolveLocalOrThrowTdf(
    TdfTimeZoneContext timeZone,
    int year,
    int month,
    int day,
    int hour,
    int minute,
    int second,
  ) {
    try {
      return timeZone.resolveLocalToUtc(year, month, day, hour, minute, second);
    } on FormatException catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const TdfException(
          kind: TdfErrorKind.invalidTimestamp,
          line: 1,
          message: 'Resolved recurring timestamp exceeds 0001..9999 UTC range.',
        ),
        stackTrace,
      );
    }
  }

  /// Resolves the Mode 2 local wall-clock anchor from [oldAnchor] or [oldDue] via [timeZone], mapping out-of-bounds [FormatException] to [TdfException].
  static TdfLocalDateTime _resolveMode2Anchor(
    TdfLocalDateTime? oldAnchor,
    DateTime oldDue,
    TdfTimeZoneContext timeZone,
  ) {
    if (oldAnchor != null) return oldAnchor;
    return _toLocalDateTimeOrThrowTdf(timeZone, oldDue);
  }

  /// Throws a canonical [TdfException] (`TdfErrorKind.invalidTimestamp`) for recurrence boundary overflows.
  static Never _throwInvalidRecurrenceTimestamp() {
    throw const TdfException(
      kind: TdfErrorKind.invalidTimestamp,
      line: 1,
      message: 'Resolved recurring timestamp exceeds 0001..9999 UTC range.',
    );
  }

  /// Converts [instantUtc] into a validated `0001..9999` [TdfLocalDateTime] via [timeZone], mapping out-of-bounds [FormatException] to [TdfException].
  static TdfLocalDateTime _toLocalDateTimeOrThrowTdf(
    TdfTimeZoneContext timeZone,
    DateTime instantUtc,
  ) {
    try {
      return timeZone.toLocalDateTime(instantUtc);
    } on FormatException catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const TdfException(
          kind: TdfErrorKind.invalidTimestamp,
          line: 1,
          message: 'Local calendar conversion exceeds 0001..9999 range.',
        ),
        stackTrace,
      );
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TaskRepeatRule &&
        other.count == count &&
        other.unit == unit &&
        other.clock == clock &&
        other.leadDays == leadDays;
  }

  @override
  int get hashCode => Object.hash(count, unit, clock, leadDays);

  @override
  String toString() => 'repeat ${toTdfDirectiveArgs()}';
}

/// Immutable representation of a single TDF `task` block in TierTask.
@immutable
class TaskItem {
  /// Creates a [TaskItem] with TDF attributes, schedule-note ownership normalization, and unmodifiable collection views.
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
    String? suspendedNote,
    this.dueAt,
    TdfLocalDateTime? dueAnchor,
    bool isDuePassive = false,
    String? dueNote,
    this.origin,
    this.repeatRule,
    List<String> labelIds = const [],
    List<String>? blockedByTaskIds,
    List<TdfTaskDependency>? dependencies,
    List<TaskLink> links = const [],
    Iterable<TaskHistoryEntry> history = const <TaskHistoryEntry>[],
    List<TaskCondition> conditions = const [],
    this.subtasksAutoFinish = false,
    List<SubtaskItem> subtasks = const [],
  }) : id = id ?? generateTaskId(timestamp: createdAt ?? defaultCreatedAt),
       createdAt = createdAt ?? defaultCreatedAt,
       completions =
           completions ?? ((isCompleted || completedAt != null) ? 1 : 0),
       suspendedNote = (isSuspendedForever || suspendedAt != null)
           ? suspendedNote
           : null,
       dueAnchor = dueAt != null ? dueAnchor : null,
       isDuePassive = dueAt != null && isDuePassive,
       dueNote = dueAt != null ? dueNote : null,
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
       history = TaskHistoryEntry.normalizeList(history),
       conditions = List<TaskCondition>.unmodifiable(conditions),
       subtasks = List<SubtaskItem>.unmodifiable(subtasks);

  /// Creates a [TaskItem] from already-normalized, unmodifiable collections without re-wrapping or re-sorting unchanged lists.
  const TaskItem._normalized({
    required this.id,
    required this.title,
    required this.note,
    required this.isCompleted,
    required this.isPriority,
    required this.completions,
    required this.createdAt,
    required this.completedAt,
    required this.modifiedAt,
    required this.suspendedAt,
    required this.isSuspendedForever,
    required this.suspendedNote,
    required this.dueAt,
    required this.dueAnchor,
    required this.isDuePassive,
    required this.dueNote,
    required this.origin,
    required this.repeatRule,
    required this.labelIds,
    required this.blockedByTaskIds,
    required this.dependencies,
    required this.links,
    required this.history,
    required this.conditions,
    required this.subtasksAutoFinish,
    required this.subtasks,
  });

  /// Fallback UTC creation timestamp when none is provided explicitly.
  static final DateTime defaultCreatedAt = DateTime.utc(2026, 11, 1, 8);

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

  /// Optional intended local calendar schedule anchor (`due ... anchor <YYYY-MM-DD HH:MM:SS>`).
  final TdfLocalDateTime? dueAnchor;

  /// Optional target deadline in UTC (`due` directive).
  final DateTime? dueAt;

  /// Optional contextual note attached to [dueAt] (`due <timestamp> [passive] "<note>"`).
  final String? dueNote;

  /// Canonical chronologically sorted, deduplicated log entries (`history <timestamp> "<text>"`).
  final List<TaskHistoryEntry> history;

  /// Unique TDF task entity identifier (`<id>`).
  final String id;

  /// Whether the task is completed (`finished` is present).
  final bool isCompleted;

  /// Whether [dueAt] carries the `passive` flag suppressing automatic due-lead-window promotion.
  final bool isDuePassive;

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

  /// Optional contextual note attached to [suspendedAt] or [isSuspendedForever] (`suspended ... "<note>"`).
  final String? suspendedNote;

  /// Human-readable task title (`name` directive).
  final String title;

  /// Number of direct child statements emitted inside this `task` block in canonical `0.7.0` form.
  int get canonicalDirectChildStatementCount {
    var count = 2;
    if (note case final currentNote? when currentNote.isNotEmpty) {
      count++;
    }
    if (isCompleted && completedAt != null) count++;
    if (modifiedAt != null) count++;
    if (completions > 0) count++;
    if (repeatRule != null) count++;
    if (labelIds.isNotEmpty) count++;
    if (dependencies.isNotEmpty) count++;
    if (isSuspendedForever || suspendedAt != null) count++;
    if (dueAt != null) count++;
    if (origin != null) count++;
    count += links.length;
    count += history.length;
    if (conditions.isNotEmpty) count++;
    if (subtasks.isNotEmpty) count++;
    return count;
  }

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
    String? suspendedNote,
    DateTime? dueAt,
    TdfLocalDateTime? dueAnchor,
    bool? isDuePassive,
    String? dueNote,
    TaskOrigin? origin,
    TaskRepeatRule? repeatRule,
    List<String>? labelIds,
    List<String>? blockedByTaskIds,
    List<TdfTaskDependency>? dependencies,
    List<TaskLink>? links,
    Iterable<TaskHistoryEntry>? history,
    List<TaskCondition>? conditions,
    bool? subtasksAutoFinish,
    List<SubtaskItem>? subtasks,
    bool clearNote = false,
    bool clearCompletedAt = false,
    bool clearModifiedAt = false,
    bool clearSuspendedAt = false,
    bool clearSuspendedNote = false,
    bool clearDueAt = false,
    bool clearDueAnchor = false,
    bool clearDueNote = false,
    bool clearOrigin = false,
    bool clearRepeatRule = false,
  }) {
    final nextSuspendedAt = clearSuspendedAt
        ? null
        : (suspendedAt ?? this.suspendedAt);
    final nextIsSuspendedForever = clearSuspendedAt
        ? (isSuspendedForever ?? false)
        : (isSuspendedForever ??
              (suspendedAt == null && this.isSuspendedForever));
    final rawSuspendedNote = clearSuspendedNote
        ? null
        : (suspendedNote ?? this.suspendedNote);
    final nextDueAt = clearDueAt ? null : (dueAt ?? this.dueAt);
    final rawDueAnchor = (clearDueAt || clearDueAnchor)
        ? null
        : (dueAnchor ?? this.dueAnchor);
    final rawDuePassive = !clearDueAt && (isDuePassive ?? this.isDuePassive);
    final rawDueNote = clearDueNote ? null : (dueNote ?? this.dueNote);

    final List<TdfTaskDependency> nextDependencies;
    final List<String> nextBlockedIds;
    if (dependencies == null && blockedByTaskIds == null) {
      nextDependencies = this.dependencies;
      nextBlockedIds = this.blockedByTaskIds;
    } else {
      final resolvedDependencies = _resolveCopyWithDependencies(
        currentDependencies: this.dependencies,
        newDependencies: dependencies,
        newBlockedByTaskIds: blockedByTaskIds,
      );
      nextDependencies = List<TdfTaskDependency>.unmodifiable(
        resolvedDependencies,
      );
      nextBlockedIds = blockedByTaskIds != null
          ? List<String>.unmodifiable(blockedByTaskIds)
          : List<String>.unmodifiable(<String>[
              for (final dependency in resolvedDependencies) dependency.taskId,
            ]);
    }
    return TaskItem._normalized(
      id: id ?? this.id,
      title: title ?? this.title,
      note: clearNote ? null : (note ?? this.note),
      isCompleted: isCompleted ?? this.isCompleted,
      isPriority: isPriority ?? this.isPriority,
      completions: completions ?? this.completions,
      createdAt: createdAt ?? this.createdAt,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      modifiedAt: clearModifiedAt ? null : (modifiedAt ?? this.modifiedAt),
      suspendedAt: nextSuspendedAt,
      isSuspendedForever: nextIsSuspendedForever,
      suspendedNote: (nextIsSuspendedForever || nextSuspendedAt != null)
          ? rawSuspendedNote
          : null,
      dueAt: nextDueAt,
      dueAnchor: nextDueAt != null ? rawDueAnchor : null,
      isDuePassive: nextDueAt != null && rawDuePassive,
      dueNote: nextDueAt != null ? rawDueNote : null,
      origin: clearOrigin ? null : (origin ?? this.origin),
      repeatRule: clearRepeatRule ? null : (repeatRule ?? this.repeatRule),
      labelIds: labelIds != null
          ? List<String>.unmodifiable(labelIds)
          : this.labelIds,
      blockedByTaskIds: nextBlockedIds,
      dependencies: nextDependencies,
      links: links != null ? List<TaskLink>.unmodifiable(links) : this.links,
      history: history != null
          ? TaskHistoryEntry.normalizeList(history)
          : this.history,
      conditions: conditions != null
          ? List<TaskCondition>.unmodifiable(conditions)
          : this.conditions,
      subtasksAutoFinish: subtasksAutoFinish ?? this.subtasksAutoFinish,
      subtasks: subtasks != null
          ? List<SubtaskItem>.unmodifiable(subtasks)
          : this.subtasks,
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

  /// Whether this task has an active deferral (`suspended forever` or `suspendedAt > normalize(nowUtc)`).
  bool hasActiveSuspendedAt(DateTime nowUtc) {
    if (isSuspendedForever) return true;
    if (suspendedAt case final suspended?) {
      return suspended.isAfter(normalizeTimestamp(nowUtc));
    }
    return false;
  }

  /// Whether [dueAt] is non-passive and falls at or within `[dueLeadWindow]` after `normalize(nowUtc)`.
  bool isWithinDueLeadWindow(DateTime nowUtc, Duration? dueLeadWindow) {
    if (dueLeadWindow == null || isDuePassive) return false;
    if (dueAt case final due?) {
      final threshold = normalizeTimestamp(nowUtc).add(dueLeadWindow);
      return !due.isAfter(threshold);
    }
    return false;
  }

  /// Computes a strictly advancing UTC modification timestamp (`max(normalize(now), normalize(previous) + 1s)`).
  ///
  /// Throws [TdfException] (`invalidTimestamp`) if the resulting timestamp is outside `0001..9999` UTC.
  static DateTime nextModifiedTimestamp(DateTime now, DateTime? previous) {
    final normalizedNow = normalizeTimestamp(now);
    if (!TdfCalendar.isWithinTimestampBounds(normalizedNow)) {
      throw const TdfException(
        kind: TdfErrorKind.invalidTimestamp,
        line: 1,
        message: 'Modified timestamp is outside 0001..9999 UTC.',
      );
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
      throw const TdfException(
        kind: TdfErrorKind.invalidTimestamp,
        line: 1,
        message: 'Modified timestamp exceeds 9999-12-31 23:59:59 UTC.',
      );
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

  /// Creates a completed task stamped with [completionDate] (`finished` and `modified` directives),
  /// clearing `priority`, `suspended`, `suspendedNote`, and `blocked` while preserving `due` and `history`.
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
      isPriority: false,
      completedAt: normalized,
      completions: nextCompletions,
      isSuspendedForever: false,
      clearSuspendedAt: true,
      clearSuspendedNote: true,
      blockedByTaskIds: const <String>[],
      dependencies: const <TdfTaskDependency>[],
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
  static int? tryParseTimeMinutes(String rawTime) =>
      TdfMetadata.tryParseTimeMinutes(rawTime);

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
        other.suspendedNote == suspendedNote &&
        other.dueAt == dueAt &&
        other.dueAnchor == dueAnchor &&
        other.isDuePassive == isDuePassive &&
        other.dueNote == dueNote &&
        other.origin == origin &&
        other.repeatRule == repeatRule &&
        other.subtasksAutoFinish == subtasksAutoFinish &&
        listEquals(other.labelIds, labelIds) &&
        listEquals(other.blockedByTaskIds, blockedByTaskIds) &&
        listEquals(other.dependencies, dependencies) &&
        listEquals(other.links, links) &&
        listEquals(other.history, history) &&
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
    suspendedNote,
    dueAt,
    dueAnchor,
    isDuePassive,
    dueNote,
    origin,
    repeatRule,
    subtasksAutoFinish,
    Object.hashAll(labelIds),
    Object.hashAll(blockedByTaskIds),
    Object.hashAll(dependencies),
    Object.hashAll(links),
    Object.hashAll(history),
    Object.hashAll(conditions),
    Object.hashAll(subtasks),
  ]);

  @override
  String toString() => 'task $id "$title"';
}
