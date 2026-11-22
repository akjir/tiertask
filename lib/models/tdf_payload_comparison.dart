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

import 'task_board_evaluator.dart';
import 'task_item.dart';
import 'tdf_location.dart';
import 'tdf_metadata.dart';
import 'tdf_sync_metadata.dart';

/// Normalized condition representation `(globalAny, dayGroup, timeGroup, locationGroup)` (`TDF-MODEL-006`).
@immutable
class NormalizedConditionModel {
  /// Creates a [NormalizedConditionModel].
  const NormalizedConditionModel({
    required this.globalAny,
    required this.dayResetAny,
    required this.dayRules,
    required this.timeResetAny,
    required this.timeRules,
    required this.locationResetAny,
    required this.locationIds,
  });

  /// Extracts a [NormalizedConditionModel] from [conditions] in a single pass.
  factory NormalizedConditionModel.fromList(List<TaskCondition> conditions) {
    var globalAny = false;
    var dayReset = false;
    var timeReset = false;
    var locReset = false;
    final dayRules = <DayTaskCondition>[];
    final timeRules = <TimeWindowTaskCondition>[];
    final locIds = <String>[];
    final seenLocIds = <String>{};

    for (final rule in conditions) {
      final flags = _accumulateNormalizedRule(
        rule,
        globalAny: globalAny,
        dayReset: dayReset,
        timeReset: timeReset,
        locReset: locReset,
        dayRules: dayRules,
        timeRules: timeRules,
        locIds: locIds,
        seenLocIds: seenLocIds,
      );
      globalAny = flags.globalAny;
      dayReset = flags.dayReset;
      timeReset = flags.timeReset;
      locReset = flags.locReset;
    }

    return NormalizedConditionModel(
      globalAny: globalAny,
      dayResetAny: dayReset,
      dayRules: dayRules,
      timeResetAny: timeReset,
      timeRules: timeRules,
      locationResetAny: locReset,
      locationIds: locIds,
    );
  }

  /// Whether the `day` condition group was reset via `condition day any`.
  final bool dayResetAny;

  /// Active weekday condition rules.
  final List<DayTaskCondition> dayRules;

  /// Whether all condition groups were reset via `condition any`.
  final bool globalAny;

  /// Referenced `<location-id>` tokens in canonical appearance order.
  final List<String> locationIds;

  /// Whether the `location` condition group was reset via `condition location any`.
  final bool locationResetAny;

  /// Whether the `time` condition group was reset via `condition time any`.
  final bool timeResetAny;

  /// Active daily time-window condition rules.
  final List<TimeWindowTaskCondition> timeRules;

  /// Converts this normalized condition model back into a canonical [List<TaskCondition>].
  List<TaskCondition> toConditionList() {
    if (globalAny) {
      return const <TaskCondition>[GlobalResetTaskCondition()];
    }
    return <TaskCondition>[
      if (dayResetAny)
        const GroupResetTaskCondition(targetGroup: ConditionGroup.day)
      else
        ...dayRules,
      if (timeResetAny)
        const GroupResetTaskCondition(targetGroup: ConditionGroup.time)
      else
        ...timeRules,
      if (locationResetAny)
        const GroupResetTaskCondition(targetGroup: ConditionGroup.location)
      else if (locationIds.isNotEmpty)
        LocationTaskCondition(locationIds: locationIds),
    ];
  }

  /// Returns a copy of this model with its `location` group replaced by [resetAny] and [locationIds].
  NormalizedConditionModel withLocationGroup({
    required bool resetAny,
    required List<String> locationIds,
  }) {
    return NormalizedConditionModel(
      globalAny: globalAny,
      dayResetAny: dayResetAny,
      dayRules: dayRules,
      timeResetAny: timeResetAny,
      timeRules: timeRules,
      locationResetAny: resetAny,
      locationIds: locationIds,
    );
  }

  /// Accumulates a single [rule] into normalized condition group lists and reset flags.
  static ({bool globalAny, bool dayReset, bool timeReset, bool locReset})
  _accumulateNormalizedRule(
    TaskCondition rule, {
    required bool globalAny,
    required bool dayReset,
    required bool timeReset,
    required bool locReset,
    required List<DayTaskCondition> dayRules,
    required List<TimeWindowTaskCondition> timeRules,
    required List<String> locIds,
    required Set<String> seenLocIds,
  }) {
    switch (rule) {
      case GlobalResetTaskCondition():
        return (
          globalAny: true,
          dayReset: dayReset,
          timeReset: timeReset,
          locReset: locReset,
        );
      case GroupResetTaskCondition(:final targetGroup):
        return (
          globalAny: globalAny,
          dayReset: dayReset || targetGroup == ConditionGroup.day,
          timeReset: timeReset || targetGroup == ConditionGroup.time,
          locReset: locReset || targetGroup == ConditionGroup.location,
        );
      case DayTaskCondition():
        dayRules.add(rule);
        return (
          globalAny: globalAny,
          dayReset: dayReset,
          timeReset: timeReset,
          locReset: locReset,
        );
      case TimeWindowTaskCondition():
        timeRules.add(rule);
        return (
          globalAny: globalAny,
          dayReset: dayReset,
          timeReset: timeReset,
          locReset: locReset,
        );
      case LocationTaskCondition():
        if (rule.locationIds.isNotEmpty) {
          _appendUniqueLocationIds(rule.locationIds, seenLocIds, locIds);
        }
        return (
          globalAny: globalAny,
          dayReset: dayReset,
          timeReset: timeReset,
          locReset: locReset,
        );
    }
  }

  /// Appends unique `<location-id>` tokens from [source] into [target].
  static void _appendUniqueLocationIds(
    List<String> source,
    Set<String> seen,
    List<String> target,
  ) {
    for (final id in source) {
      if (seen.add(id)) {
        target.add(id);
      }
    }
  }
}

/// Stateless decoded payload tuple comparator and payload signature encoder per `spec/TDF_SPEC_0.8.0.md` Sections 2.6 and 12.
@immutable
class TdfPayloadComparison {
  /// Prevents instantiation of this stateless helper class.
  const TdfPayloadComparison._();

  /// Compares two condition lists normalized into `(globalAny, dayGroup, timeGroup, locationGroup)`.
  static int compareConditionModels(
    List<TaskCondition> left,
    List<TaskCondition> right,
  ) {
    final normLeft = NormalizedConditionModel.fromList(left);
    final normRight = NormalizedConditionModel.fromList(right);
    return compareNormalizedConditionModels(normLeft, normRight);
  }

  /// Compares the `day` condition group of two [NormalizedConditionModel] instances.
  static int compareDayConditionGroup(
    NormalizedConditionModel left,
    NormalizedConditionModel right,
  ) {
    final resetCmp = _compareBool(left.dayResetAny, right.dayResetAny);
    if (resetCmp != 0) {
      return resetCmp;
    }
    return _compareList(left.dayRules, right.dayRules, _compareDayCondition);
  }

  /// Compares two deferral states (`absent < (false, utcComponents, note) < (true, [], note)`).
  static int compareDeferral(TaskItem left, TaskItem right) {
    final leftPresent = left.isSuspendedForever || left.suspendedAt != null;
    final rightPresent = right.isSuspendedForever || right.suspendedAt != null;
    final presenceCmp = _compareBool(leftPresent, rightPresent);
    if (presenceCmp != 0 || !leftPresent) {
      return presenceCmp;
    }
    final foreverCmp = _compareBool(
      left.isSuspendedForever,
      right.isSuspendedForever,
    );
    if (foreverCmp != 0) {
      return foreverCmp;
    }
    if (left.isSuspendedForever) {
      return _compareNullable(
        left.suspendedNote,
        right.suspendedNote,
        compareUtf8Strings,
      );
    }
    final timeCmp = (left.suspendedAt ?? DateTime.utc(1970)).compareTo(
      right.suspendedAt ?? DateTime.utc(1970),
    );
    if (timeCmp != 0) {
      return timeCmp;
    }
    return _compareNullable(
      left.suspendedNote,
      right.suspendedNote,
      compareUtf8Strings,
    );
  }

  /// Compares two atomic `due` 4-tuples (`absent < (utcComponents, dueAnchor, isDuePassive, dueNote)`).
  static int compareDue(TaskItem left, TaskItem right) {
    final leftDue = left.dueAt;
    final rightDue = right.dueAt;
    if (leftDue == null && rightDue == null) {
      return 0;
    }
    if (leftDue == null) {
      return -1;
    }
    if (rightDue == null) {
      return 1;
    }
    final timeCmp = leftDue.compareTo(rightDue);
    if (timeCmp != 0) {
      return timeCmp;
    }
    final anchorCmp = _compareNullable(
      left.dueAnchor,
      right.dueAnchor,
      (first, second) => first.compareTo(second),
    );
    if (anchorCmp != 0) {
      return anchorCmp;
    }
    final passiveCmp = _compareBool(left.isDuePassive, right.isDuePassive);
    if (passiveCmp != 0) {
      return passiveCmp;
    }
    return _compareNullable(left.dueNote, right.dueNote, compareUtf8Strings);
  }

  /// Compares two [TdfLabel] decoded payloads `(scoped, name, note, color, link, condition)` (`TDF-MERGE-002`).
  static int compareLabelPayloads(TdfLabel left, TdfLabel right) {
    if (identical(left, right)) {
      return 0;
    }
    final scopedCmp = _compareBool(left.isScoped, right.isScoped);
    if (scopedCmp != 0) {
      return scopedCmp;
    }
    final nameCmp = compareUtf8Strings(left.name, right.name);
    if (nameCmp != 0) {
      return nameCmp;
    }
    final noteCmp = _compareNullable(left.note, right.note, compareUtf8Strings);
    if (noteCmp != 0) {
      return noteCmp;
    }
    final colorCmp = _compareNullable(
      left.color?.toUpperCase(),
      right.color?.toUpperCase(),
      compareUtf8Strings,
    );
    if (colorCmp != 0) {
      return colorCmp;
    }
    final linkCmp = compareLinkLists(left.links, right.links);
    if (linkCmp != 0) {
      return linkCmp;
    }
    return compareConditionModels(left.conditions, right.conditions);
  }

  /// Compares two [TdfLabel] versions for the complete entity winner (`TDF-MERGE-003`).
  static int compareLabelVersions(TdfLabel left, TdfLabel right) {
    if (identical(left, right)) {
      return 0;
    }
    final modCmp = left.effectiveModifiedAt.compareTo(
      right.effectiveModifiedAt,
    );
    if (modCmp != 0) {
      return modCmp;
    }
    final payloadCmp = compareLabelPayloads(left, right);
    if (payloadCmp != 0) {
      return payloadCmp;
    }
    return _compareBool(left.modifiedAt != null, right.modifiedAt != null);
  }

  /// Compares two ordered [TaskLink] lists (`TDF-MERGE-002`).
  static int compareLinkLists(List<TaskLink> left, List<TaskLink> right) {
    return _compareList(left, right, _compareSingleLink);
  }

  /// Compares the `location` condition group of two [NormalizedConditionModel] instances.
  static int compareLocationConditionGroup(
    NormalizedConditionModel left,
    NormalizedConditionModel right,
  ) {
    final resetCmp = _compareBool(
      left.locationResetAny,
      right.locationResetAny,
    );
    if (resetCmp != 0) {
      return resetCmp;
    }
    return _compareList(
      left.locationIds,
      right.locationIds,
      compareUtf8Strings,
    );
  }

  /// Compares the coupled `((latitudeText, longitudeText), source)` unit of two [TdfLocation]s.
  static int compareLocationCoordAndSource(
    TdfLocation left,
    TdfLocation right,
  ) {
    final latCmp = compareUtf8Strings(
      TdfLocation.normalizeDecimalText(left.latitudeText),
      TdfLocation.normalizeDecimalText(right.latitudeText),
    );
    if (latCmp != 0) {
      return latCmp;
    }
    final lonCmp = compareUtf8Strings(
      TdfLocation.normalizeDecimalText(left.longitudeText),
      TdfLocation.normalizeDecimalText(right.longitudeText),
    );
    if (lonCmp != 0) {
      return lonCmp;
    }
    return _compareNullable(left.source, right.source, compareUtf8Strings);
  }

  /// Compares two [TdfLocation] decoded payloads `(name, note, (coordinates, source), radius)` (`TDF-MERGE-002`).
  static int compareLocationPayloads(TdfLocation left, TdfLocation right) {
    if (identical(left, right)) {
      return 0;
    }
    final nameCmp = compareUtf8Strings(left.name, right.name);
    if (nameCmp != 0) {
      return nameCmp;
    }
    final noteCmp = _compareNullable(left.note, right.note, compareUtf8Strings);
    if (noteCmp != 0) {
      return noteCmp;
    }
    final coordSourceCmp = compareLocationCoordAndSource(left, right);
    if (coordSourceCmp != 0) {
      return coordSourceCmp;
    }
    return compareUtf8Strings(
      TdfLocation.normalizeDecimalText(left.radiusText),
      TdfLocation.normalizeDecimalText(right.radiusText),
    );
  }

  /// Compares two [TdfLocation] versions for the complete entity winner (`TDF-MERGE-003`).
  static int compareLocationVersions(TdfLocation left, TdfLocation right) {
    if (identical(left, right)) {
      return 0;
    }
    final modCmp = left.effectiveModifiedAt.compareTo(
      right.effectiveModifiedAt,
    );
    if (modCmp != 0) {
      return modCmp;
    }
    final payloadCmp = compareLocationPayloads(left, right);
    if (payloadCmp != 0) {
      return payloadCmp;
    }
    return _compareBool(left.modifiedAt != null, right.modifiedAt != null);
  }

  /// Compares two [NormalizedConditionModel] instances.
  static int compareNormalizedConditionModels(
    NormalizedConditionModel normLeft,
    NormalizedConditionModel normRight,
  ) {
    final globalCmp = _compareBool(normLeft.globalAny, normRight.globalAny);
    if (globalCmp != 0) {
      return globalCmp;
    }
    final dayGroupCmp = compareDayConditionGroup(normLeft, normRight);
    if (dayGroupCmp != 0) {
      return dayGroupCmp;
    }
    final timeGroupCmp = compareTimeConditionGroup(normLeft, normRight);
    if (timeGroupCmp != 0) {
      return timeGroupCmp;
    }
    return compareLocationConditionGroup(normLeft, normRight);
  }

  /// Compares two nullable [TaskRepeatRule] values (`null < non-null`).
  static int compareNullableRepeatRules(
    TaskRepeatRule? left,
    TaskRepeatRule? right,
  ) => _compareNullable(left, right, _compareRepeatRule);

  /// Compares two [TdfQueueBlock] versions by `modifiedAt`, then lexicographical ASCII `taskIds` (`TDF-QSYNC-001`).
  static int compareQueueBlocks(TdfQueueBlock left, TdfQueueBlock right) {
    final modCmp = left.modifiedAt.compareTo(right.modifiedAt);
    if (modCmp != 0) {
      return modCmp;
    }
    return _compareList(left.taskIds, right.taskIds, compareUtf8Strings);
  }

  /// Compares two `subtasks` blocks (`omitted < (autoFinish, steps)`).
  static int compareSubtasksBlock(TaskItem left, TaskItem right) {
    final leftPresent = left.subtasks.isNotEmpty;
    final rightPresent = right.subtasks.isNotEmpty;
    final presenceCmp = _compareBool(leftPresent, rightPresent);
    if (presenceCmp != 0 || !leftPresent) {
      return presenceCmp;
    }
    final autoCmp = _compareBool(
      left.subtasksAutoFinish,
      right.subtasksAutoFinish,
    );
    if (autoCmp != 0) {
      return autoCmp;
    }
    return _compareList(left.subtasks, right.subtasks, _compareSingleSubtask);
  }

  /// Compares two [TaskItem] decoded payloads `(name, note, created, labels, origin, link, history, condition, taskState)` (`TDF-MERGE-002`).
  static int compareTaskPayloads(TaskItem left, TaskItem right) {
    if (identical(left, right)) {
      return 0;
    }
    final nameCmp = compareUtf8Strings(left.title, right.title);
    if (nameCmp != 0) {
      return nameCmp;
    }
    final noteCmp = _compareNullable(left.note, right.note, compareUtf8Strings);
    if (noteCmp != 0) {
      return noteCmp;
    }
    final createdCmp = left.createdAt.compareTo(right.createdAt);
    if (createdCmp != 0) {
      return createdCmp;
    }
    final labelsCmp = _compareList(
      normalizedLabelSet(left.labelIds),
      normalizedLabelSet(right.labelIds),
      compareUtf8Strings,
    );
    if (labelsCmp != 0) {
      return labelsCmp;
    }
    final originCmp = _compareNullable(
      left.origin,
      right.origin,
      _compareOrigin,
    );
    if (originCmp != 0) {
      return originCmp;
    }
    final linkCmp = compareLinkLists(left.links, right.links);
    if (linkCmp != 0) {
      return linkCmp;
    }
    final historyCmp = _compareList(
      left.history,
      right.history,
      TaskHistoryEntry.compareCanonical,
    );
    if (historyCmp != 0) {
      return historyCmp;
    }
    final condCmp = compareConditionModels(left.conditions, right.conditions);
    if (condCmp != 0) {
      return condCmp;
    }
    return compareTaskStates(left, right);
  }

  /// Compares two [TaskItem] occurrence states `(completions, priority, finished, suspended, due, repeat, blocked, subtasks)` (`TDF-MERGE-002`).
  static int compareTaskStates(TaskItem left, TaskItem right) {
    final compCmp = left.completions.compareTo(right.completions);
    if (compCmp != 0) {
      return compCmp;
    }
    final prioCmp = _compareBool(left.isPriority, right.isPriority);
    if (prioCmp != 0) {
      return prioCmp;
    }
    final finCmp = _compareNullable(
      left.completedAt,
      right.completedAt,
      (first, second) => first.compareTo(second),
    );
    if (finCmp != 0) {
      return finCmp;
    }
    final suspCmp = compareDeferral(left, right);
    if (suspCmp != 0) {
      return suspCmp;
    }
    final dueCmp = compareDue(left, right);
    if (dueCmp != 0) {
      return dueCmp;
    }
    final repCmp = compareNullableRepeatRules(
      left.repeatRule,
      right.repeatRule,
    );
    if (repCmp != 0) {
      return repCmp;
    }
    final depCmp = _compareList(
      TdfTaskDependency.normalizeList(left.dependencies),
      TdfTaskDependency.normalizeList(right.dependencies),
      _compareDependency,
    );
    if (depCmp != 0) {
      return depCmp;
    }
    return compareSubtasksBlock(left, right);
  }

  /// Compares two [TaskItem] versions for the complete entity winner (`TDF-MERGE-003`).
  static int compareTaskVersions(TaskItem left, TaskItem right) {
    if (identical(left, right)) {
      return 0;
    }
    final compCmp = left.completions.compareTo(right.completions);
    if (compCmp != 0) {
      return compCmp;
    }
    final modCmp = left.effectiveModifiedAt.compareTo(
      right.effectiveModifiedAt,
    );
    if (modCmp != 0) {
      return modCmp;
    }
    final payloadCmp = compareTaskPayloads(left, right);
    if (payloadCmp != 0) {
      return payloadCmp;
    }
    return _compareBool(left.modifiedAt != null, right.modifiedAt != null);
  }

  /// Compares the `time` condition group of two [NormalizedConditionModel] instances.
  static int compareTimeConditionGroup(
    NormalizedConditionModel left,
    NormalizedConditionModel right,
  ) {
    final resetCmp = _compareBool(left.timeResetAny, right.timeResetAny);
    if (resetCmp != 0) {
      return resetCmp;
    }
    return _compareList(left.timeRules, right.timeRules, _compareTimeCondition);
  }

  /// Compares two strings by unsigned UTF-8 byte order (`TDF-MERGE-002`) without intermediate byte allocations.
  static int compareUtf8Strings(String left, String right) =>
      TaskHistoryEntry.compareUtf8Strings(left, right);

  /// Encodes the normalized `TDF-MODEL-006` payload signature of [label] (excluding `modifiedAt`) for `TdfBoundDeletionDecision`.
  static String labelPayloadSignature(TdfLabel label) {
    final buffer = StringBuffer('lbl|')..write(label.isScoped ? '1;' : '0;');
    _writeString(buffer, label.name);
    _writeNullableString(buffer, label.note);
    _writeNullableString(buffer, label.color?.toUpperCase());
    _writeLinkListSignature(buffer, label.links);
    _writeConditionSignature(buffer, label.conditions);
    return buffer.toString();
  }

  /// Encodes the normalized `TDF-MODEL-006` payload signature of [location] (excluding `modifiedAt`) for `TdfBoundDeletionDecision`.
  static String locationPayloadSignature(TdfLocation location) {
    final buffer = StringBuffer('loc|');
    _writeString(buffer, location.name);
    _writeNullableString(buffer, location.note);
    _writeString(
      buffer,
      TdfLocation.normalizeDecimalText(location.latitudeText),
    );
    _writeString(
      buffer,
      TdfLocation.normalizeDecimalText(location.longitudeText),
    );
    _writeNullableString(buffer, location.source);
    _writeString(buffer, TdfLocation.normalizeDecimalText(location.radiusText));
    return buffer.toString();
  }

  /// Deduplicates and sorts [labelIds] in ascending ASCII order.
  static List<String> normalizedLabelSet(List<String> labelIds) {
    if (labelIds.isEmpty) {
      return const <String>[];
    }
    final sorted = <String>{...labelIds}.toList()..sort();
    return sorted;
  }

  /// Encodes the normalized `TDF-MODEL-006` payload signature of [task] (including `dueAnchor`, excluding `modifiedAt`) for `TdfBoundDeletionDecision`.
  static String taskPayloadSignature(TaskItem task) {
    final buffer = StringBuffer('tsk|');
    _writeString(buffer, task.title);
    _writeNullableString(buffer, task.note);
    buffer
      ..write(task.createdAt.toUtc().millisecondsSinceEpoch)
      ..write(';');
    _writeStringListSignature(buffer, normalizedLabelSet(task.labelIds));
    if (task.origin case final origin?) {
      buffer.write('1:');
      _writeString(buffer, origin.namespace);
      _writeString(buffer, origin.externalKey);
    } else {
      buffer.write('0;');
    }
    _writeLinkListSignature(buffer, task.links);
    _writeHistorySignature(buffer, task.history);
    _writeConditionSignature(buffer, task.conditions);
    _writeTaskStateSignature(buffer, task);
    return buffer.toString();
  }

  /// Returns whether [left] and [right] have identical decoded task payloads (`TDF-MODEL-006`).
  static bool taskPayloadsEqual(TaskItem left, TaskItem right) =>
      compareTaskPayloads(left, right) == 0;

  /// Returns whether open snapshots [left] and [right] have identical decoded payloads after stripping expired finite `suspended <= nowUtc` and resolved `blocked` entries.
  static bool taskPayloadsEqualModuloBlockCleanup({
    required TaskItem left,
    required TaskItem right,
    required Map<String, TaskItem> liveTasksById,
    required Set<String> deletedTaskIds,
    required DateTime nowUtc,
  }) {
    final normalizedLeft =
        TaskBoardEvaluator.normalizeOpenTaskForBlockCleanupComparison(
          task: left,
          liveTasksById: liveTasksById,
          deletedTaskIds: deletedTaskIds,
          nowUtc: nowUtc,
        );
    final normalizedRight =
        TaskBoardEvaluator.normalizeOpenTaskForBlockCleanupComparison(
          task: right,
          liveTasksById: liveTasksById,
          deletedTaskIds: deletedTaskIds,
          nowUtc: nowUtc,
        );
    return compareTaskPayloads(normalizedLeft, normalizedRight) == 0;
  }

  /// Compares two boolean values (`false < true`).
  static int _compareBool(bool left, bool right) {
    if (left == right) {
      return 0;
    }
    return left ? 1 : -1;
  }

  /// Compares two [DayTaskCondition] rules by ordered weekday tokens.
  static int _compareDayCondition(
    DayTaskCondition left,
    DayTaskCondition right,
  ) {
    return _compareList(left.dayTokens, right.dayTokens, compareUtf8Strings);
  }

  /// Compares two [TdfTaskDependency] entries by target ID, then required completion integer.
  static int _compareDependency(
    TdfTaskDependency left,
    TdfTaskDependency right,
  ) {
    final idCmp = compareUtf8Strings(left.taskId, right.taskId);
    if (idCmp != 0) {
      return idCmp;
    }
    return left.requiredCompletion.compareTo(right.requiredCompletion);
  }

  /// Compares two lists lexicographically using [elementCompare].
  static int _compareList<T>(
    List<T> left,
    List<T> right,
    int Function(T first, T second) elementCompare,
  ) {
    final minLen = left.length < right.length ? left.length : right.length;
    for (var i = 0; i < minLen; i++) {
      final cmp = elementCompare(left[i], right[i]);
      if (cmp != 0) {
        return cmp;
      }
    }
    return left.length.compareTo(right.length);
  }

  /// Compares two nullable values (`null < non-null`).
  static int _compareNullable<T extends Object>(
    T? left,
    T? right,
    int Function(T first, T second) valueCompare,
  ) {
    if (left == null && right == null) {
      return 0;
    }
    if (left == null) {
      return -1;
    }
    if (right == null) {
      return 1;
    }
    return valueCompare(left, right);
  }

  /// Compares two [TaskOrigin] values `(namespace, externalKey)` by unsigned UTF-8 byte order.
  static int _compareOrigin(TaskOrigin left, TaskOrigin right) {
    final nsCmp = compareUtf8Strings(left.namespace, right.namespace);
    if (nsCmp != 0) {
      return nsCmp;
    }
    return compareUtf8Strings(left.externalKey, right.externalKey);
  }

  /// Compares two [TaskRepeatRule] values `(count, unit, (hour, minute, second), leadDays)`.
  static int _compareRepeatRule(TaskRepeatRule left, TaskRepeatRule right) {
    final countCmp = left.count.compareTo(right.count);
    if (countCmp != 0) {
      return countCmp;
    }
    final unitCmp = compareUtf8Strings(left.unit.tdfToken, right.unit.tdfToken);
    if (unitCmp != 0) {
      return unitCmp;
    }
    final hourCmp = left.clock.hour.compareTo(right.clock.hour);
    if (hourCmp != 0) {
      return hourCmp;
    }
    final minCmp = left.clock.minute.compareTo(right.clock.minute);
    if (minCmp != 0) {
      return minCmp;
    }
    final secCmp = left.clock.second.compareTo(right.clock.second);
    if (secCmp != 0) {
      return secCmp;
    }
    return left.leadDays.compareTo(right.leadDays);
  }

  /// Compares two [TaskLink] values `(title, uri)`.
  static int _compareSingleLink(TaskLink left, TaskLink right) {
    final titleCmp = compareUtf8Strings(left.title, right.title);
    if (titleCmp != 0) {
      return titleCmp;
    }
    return compareUtf8Strings(left.uri, right.uri);
  }

  /// Compares two [SubtaskItem] checklist steps `(completed, text)`.
  static int _compareSingleSubtask(SubtaskItem left, SubtaskItem right) {
    final compCmp = _compareBool(left.isCompleted, right.isCompleted);
    if (compCmp != 0) {
      return compCmp;
    }
    return compareUtf8Strings(left.title, right.title);
  }

  /// Compares two [TimeWindowTaskCondition] rules `(startMinutes, endMinutes)`.
  static int _compareTimeCondition(
    TimeWindowTaskCondition left,
    TimeWindowTaskCondition right,
  ) {
    final startCmp = left.startMinutes.compareTo(right.startMinutes);
    if (startCmp != 0) {
      return startCmp;
    }
    return left.endMinutes.compareTo(right.endMinutes);
  }

  /// Appends normalized [conditions] into [buffer] for payload signatures.
  static void _writeConditionSignature(
    StringBuffer buffer,
    List<TaskCondition> conditions,
  ) {
    final norm = NormalizedConditionModel.fromList(conditions);
    buffer
      ..write(norm.globalAny ? '1;' : '0;')
      ..write(norm.dayResetAny ? '1;' : '0;');
    _writeDayRulesSignature(buffer, norm.dayRules);
    buffer.write(norm.timeResetAny ? '1;' : '0;');
    _writeTimeRulesSignature(buffer, norm.timeRules);
    buffer.write(norm.locationResetAny ? '1;' : '0;');
    _writeStringListSignature(buffer, norm.locationIds);
  }

  /// Appends normalized [rules] weekday lists into [buffer].
  static void _writeDayRulesSignature(
    StringBuffer buffer,
    List<DayTaskCondition> rules,
  ) {
    buffer
      ..write(rules.length)
      ..write(':');
    for (final rule in rules) {
      _writeSingleDayRuleSignature(buffer, rule);
    }
  }

  /// Appends normalized [dependencies] into [buffer].
  static void _writeDependenciesSignature(
    StringBuffer buffer,
    List<TdfTaskDependency> dependencies,
  ) {
    final normalized = TdfTaskDependency.normalizeList(dependencies);
    buffer
      ..write(normalized.length)
      ..write(':');
    for (final dependency in normalized) {
      _writeString(buffer, dependency.taskId);
      buffer
        ..write(dependency.requiredCompletion)
        ..write(';');
    }
  }

  /// Appends canonical [history] entries into [buffer].
  static void _writeHistorySignature(
    StringBuffer buffer,
    List<TaskHistoryEntry> history,
  ) {
    buffer
      ..write(history.length)
      ..write(':');
    for (final entry in history) {
      buffer
        ..write(entry.timestampUtc.toUtc().millisecondsSinceEpoch)
        ..write(':');
      _writeString(buffer, entry.text);
    }
  }

  /// Appends ordered [links] into [buffer].
  static void _writeLinkListSignature(
    StringBuffer buffer,
    List<TaskLink> links,
  ) {
    buffer
      ..write(links.length)
      ..write(':');
    for (final link in links) {
      _writeString(buffer, link.title);
      _writeString(buffer, link.uri);
    }
  }

  /// Appends a length-prefixed optional [value] into [buffer].
  static void _writeNullableString(StringBuffer buffer, String? value) {
    if (value == null) {
      buffer.write('0;');
      return;
    }
    buffer.write('1:');
    _writeString(buffer, value);
  }

  /// Appends a single [rule]'s weekday tokens into [buffer].
  static void _writeSingleDayRuleSignature(
    StringBuffer buffer,
    DayTaskCondition rule,
  ) {
    _writeStringListSignature(buffer, rule.dayTokens);
  }

  /// Appends a length-prefixed non-null [value] into [buffer].
  static void _writeString(StringBuffer buffer, String value) {
    buffer
      ..write(value.length)
      ..write(':')
      ..write(value)
      ..write(';');
  }

  /// Appends an ordered list of [values] into [buffer].
  static void _writeStringListSignature(
    StringBuffer buffer,
    List<String> values,
  ) {
    buffer
      ..write(values.length)
      ..write(':');
    for (final value in values) {
      _writeString(buffer, value);
    }
  }

  /// Appends ordered [steps] into [buffer].
  static void _writeSubtasksSignature(
    StringBuffer buffer,
    List<SubtaskItem> steps,
  ) {
    buffer
      ..write(steps.length)
      ..write(':');
    for (final step in steps) {
      buffer.write(step.isCompleted ? '1:' : '0:');
      _writeString(buffer, step.title);
    }
  }

  /// Appends the normalized `Task state` tuple of [task] (including `dueAnchor`) into [buffer].
  static void _writeTaskStateSignature(StringBuffer buffer, TaskItem task) {
    buffer
      ..write(task.completions)
      ..write(';')
      ..write(task.isPriority ? '1;' : '0;');
    if (task.completedAt case final finished?) {
      buffer
        ..write('1:')
        ..write(finished.toUtc().millisecondsSinceEpoch)
        ..write(';');
    } else {
      buffer.write('0;');
    }
    if (task.isSuspendedForever) {
      buffer.write('F:');
      _writeNullableString(buffer, task.suspendedNote);
    } else if (task.suspendedAt case final suspended?) {
      buffer
        ..write('S:')
        ..write(suspended.toUtc().millisecondsSinceEpoch)
        ..write(';');
      _writeNullableString(buffer, task.suspendedNote);
    } else {
      buffer.write('0;');
    }
    if (task.dueAt case final due?) {
      buffer
        ..write('1:')
        ..write(due.toUtc().millisecondsSinceEpoch)
        ..write(';');
      _writeNullableString(buffer, task.dueAnchor?.formatExplicitSeconds());
      buffer.write(task.isDuePassive ? '1;' : '0;');
      _writeNullableString(buffer, task.dueNote);
    } else {
      buffer.write('0;');
    }
    if (task.repeatRule case final repeat?) {
      buffer
        ..write('1:')
        ..write(repeat.count)
        ..write(':');
      _writeString(buffer, repeat.unit.tdfToken);
      buffer
        ..write(repeat.clock.hour)
        ..write(':')
        ..write(repeat.clock.minute)
        ..write(':')
        ..write(repeat.clock.second)
        ..write(':')
        ..write(repeat.leadDays)
        ..write(';');
    } else {
      buffer.write('0;');
    }
    _writeDependenciesSignature(buffer, task.dependencies);
    if (task.subtasks.isEmpty) {
      buffer.write('0;');
    } else {
      buffer.write(task.subtasksAutoFinish ? '1:' : '0:');
      _writeSubtasksSignature(buffer, task.subtasks);
    }
  }

  /// Appends [rules] time windows into [buffer].
  static void _writeTimeRulesSignature(
    StringBuffer buffer,
    List<TimeWindowTaskCondition> rules,
  ) {
    buffer
      ..write(rules.length)
      ..write(':');
    for (final rule in rules) {
      buffer
        ..write(rule.startMinutes)
        ..write('-')
        ..write(rule.endMinutes)
        ..write(';');
    }
  }
}
