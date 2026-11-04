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

import 'dart:convert' show utf8;

import 'package:flutter/foundation.dart';

import '../services/tdf_service.dart';
import 'task_item.dart';
import 'tdf_metadata.dart';
import 'tdf_sync_metadata.dart';
import 'tdf_timezone.dart';

/// Stateless decoded payload tuple comparator and three-way unit merge engine
/// per `TDF_SPEC.md` Sections 6.7.3–6.7.6 and 6.11.2.
@immutable
class TdfPayloadComparison {
  const TdfPayloadComparison._();

  /// Compares two condition lists normalized into `(globalAny, dayGroup, timeGroup, locationGroup)`.
  static int compareConditionModels(
    List<TaskCondition> left,
    List<TaskCondition> right,
  ) {
    final normLeft = _NormalizedConditionModel.fromList(left);
    final normRight = _NormalizedConditionModel.fromList(right);

    final globalCmp = _compareBool(normLeft.globalAny, normRight.globalAny);
    if (globalCmp != 0) {
      return globalCmp;
    }
    final dayResetCmp = _compareBool(
      normLeft.dayResetAny,
      normRight.dayResetAny,
    );
    if (dayResetCmp != 0) {
      return dayResetCmp;
    }
    final dayRulesCmp = _compareList(
      normLeft.dayRules,
      normRight.dayRules,
      _compareDayCondition,
    );
    if (dayRulesCmp != 0) {
      return dayRulesCmp;
    }
    final timeResetCmp = _compareBool(
      normLeft.timeResetAny,
      normRight.timeResetAny,
    );
    if (timeResetCmp != 0) {
      return timeResetCmp;
    }
    final timeRulesCmp = _compareList(
      normLeft.timeRules,
      normRight.timeRules,
      _compareTimeCondition,
    );
    if (timeRulesCmp != 0) {
      return timeRulesCmp;
    }
    final locResetCmp = _compareBool(
      normLeft.locationResetAny,
      normRight.locationResetAny,
    );
    if (locResetCmp != 0) {
      return locResetCmp;
    }
    return _compareList(
      normLeft.locationRules,
      normRight.locationRules,
      _compareLocationCondition,
    );
  }

  /// Compares two [TdfLabel] decoded payloads `(name, note, color, condition)` per Section 6.7.3.
  static int compareLabelPayloads(TdfLabel left, TdfLabel right) {
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
    return compareConditionModels(left.conditions, right.conditions);
  }

  /// Compares two [TdfLabel] versions for the complete entity winner per Section 6.7.4.
  static int compareLabelVersions(TdfLabel left, TdfLabel right) {
    final lMod = left.effectiveModifiedAt;
    final rMod = right.effectiveModifiedAt;
    final modCmp = lMod.compareTo(rMod);
    if (modCmp != 0) {
      return modCmp;
    }
    final payloadCmp = compareLabelPayloads(left, right);
    if (payloadCmp != 0) {
      return payloadCmp;
    }
    return _compareBool(left.modifiedAt != null, right.modifiedAt != null);
  }

  /// Compares two ordered [TaskLink] lists per Section 6.7.3.
  static int compareLinkLists(List<TaskLink> left, List<TaskLink> right) {
    return _compareList(left, right, _compareSingleLink);
  }

  /// Compares two [TdfQueueBlock] versions by `modifiedAt`, then lexicographical ASCII `taskIds` per Section 6.11.2.
  static int compareQueueBlocks(TdfQueueBlock left, TdfQueueBlock right) {
    final modCmp = left.modifiedAt.compareTo(right.modifiedAt);
    if (modCmp != 0) {
      return modCmp;
    }
    return _compareList(left.taskIds, right.taskIds, compareUtf8Strings);
  }

  /// Compares two [TaskItem] decoded payloads `(created, name, note, labels, condition, link, taskState)` per Section 6.7.3.
  static int compareTaskPayloads(TaskItem left, TaskItem right) {
    final createdCmp = left.createdAt.compareTo(right.createdAt);
    if (createdCmp != 0) {
      return createdCmp;
    }
    final nameCmp = compareUtf8Strings(left.title, right.title);
    if (nameCmp != 0) {
      return nameCmp;
    }
    final noteCmp = _compareNullable(left.note, right.note, compareUtf8Strings);
    if (noteCmp != 0) {
      return noteCmp;
    }
    final labelsCmp = _compareList(
      _normalizedLabelSet(left.labelIds),
      _normalizedLabelSet(right.labelIds),
      compareUtf8Strings,
    );
    if (labelsCmp != 0) {
      return labelsCmp;
    }
    final condCmp = compareConditionModels(left.conditions, right.conditions);
    if (condCmp != 0) {
      return condCmp;
    }
    final linkCmp = compareLinkLists(left.links, right.links);
    if (linkCmp != 0) {
      return linkCmp;
    }
    return compareTaskStates(left, right);
  }

  /// Compares two [TaskItem] occurrence states `(completions, priority, queued, finished, suspended, repeat, blocked, subtasks)` per Section 6.7.3.
  static int compareTaskStates(TaskItem left, TaskItem right) {
    final compCmp = left.completions.compareTo(right.completions);
    if (compCmp != 0) {
      return compCmp;
    }
    final prioCmp = _compareBool(left.isPriority, right.isPriority);
    if (prioCmp != 0) {
      return prioCmp;
    }
    final queuedCmp = _compareNullable(
      left.queuedAt,
      right.queuedAt,
      (a, b) => a.compareTo(b),
    );
    if (queuedCmp != 0) {
      return queuedCmp;
    }
    final finCmp = _compareNullable(
      left.completedAt,
      right.completedAt,
      (a, b) => a.compareTo(b),
    );
    if (finCmp != 0) {
      return finCmp;
    }
    final suspCmp = _compareDeferral(left, right);
    if (suspCmp != 0) {
      return suspCmp;
    }
    final repCmp = _compareNullable(
      left.repeatRule,
      right.repeatRule,
      _compareRepeatRule,
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
    return _compareSubtasksBlock(left, right);
  }

  /// Compares two [TaskItem] versions for the complete entity winner per Section 6.7.4.
  static int compareTaskVersions(TaskItem left, TaskItem right) {
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

  /// Compares two strings by unsigned UTF-8 byte order per Section 6.7.3.
  static int compareUtf8Strings(String left, String right) {
    if (left == right) {
      return 0;
    }
    final leftBytes = utf8.encode(left);
    final rightBytes = utf8.encode(right);
    final minLen = leftBytes.length < rightBytes.length
        ? leftBytes.length
        : rightBytes.length;
    for (var i = 0; i < minLen; i++) {
      final diff = leftBytes[i].compareTo(rightBytes[i]);
      if (diff != 0) {
        return diff;
      }
    }
    return leftBytes.length.compareTo(rightBytes.length);
  }

  /// Merges [local] and [incoming] [TdfLabel] versions using [baseline] per Sections 6.7.5 and 6.7.6.
  static TdfLabel mergeLabelWithBaseline({
    required TdfLabel local,
    required TdfLabel incoming,
    required TdfLabel? baseline,
  }) {
    final winner = compareLabelVersions(local, incoming) >= 0
        ? local
        : incoming;
    if (baseline == null) {
      return winner;
    }
    final mergedName = _mergeScalar(
      local: local.name,
      incoming: incoming.name,
      baseline: baseline.name,
      winner: winner.name,
      equalsFn: (a, b) => a == b,
    );
    final mergedNote = _mergeScalar(
      local: local.note,
      incoming: incoming.note,
      baseline: baseline.note,
      winner: winner.note,
      equalsFn: (a, b) => a == b,
    );
    final mergedColor = _mergeScalar(
      local: local.color,
      incoming: incoming.color,
      baseline: baseline.color,
      winner: winner.color,
      equalsFn: (a, b) => a?.toUpperCase() == b?.toUpperCase(),
    );
    final mergedConditions = _mergeScalar(
      local: local.conditions,
      incoming: incoming.conditions,
      baseline: baseline.conditions,
      winner: winner.conditions,
      equalsFn: (a, b) => compareConditionModels(a, b) == 0,
    );

    final candidate = TdfLabel(
      id: winner.id,
      name: mergedName,
      note: mergedNote,
      color: mergedColor,
      conditions: mergedConditions,
    );

    final greatestExisting = _greatestLabelVersion(baseline, local, incoming);
    if (compareLabelPayloads(greatestExisting, candidate) == 0) {
      return greatestExisting;
    }
    final nextRevision = _nextMergedRevision(
      baseline.effectiveModifiedAt,
      local.effectiveModifiedAt,
      incoming.effectiveModifiedAt,
    );
    return candidate.copyWith(modifiedAt: nextRevision);
  }

  /// Merges [local] and [incoming] [TaskItem] versions using [baseline] per Sections 6.7.5 and 6.7.6.
  static TaskItem mergeTaskWithBaseline({
    required TaskItem local,
    required TaskItem incoming,
    required TaskItem? baseline,
  }) {
    final winner = compareTaskVersions(local, incoming) >= 0 ? local : incoming;
    if (baseline == null) {
      return winner;
    }
    final mergedName = _mergeScalar(
      local: local.title,
      incoming: incoming.title,
      baseline: baseline.title,
      winner: winner.title,
      equalsFn: (a, b) => a == b,
    );
    final mergedNote = _mergeScalar(
      local: local.note,
      incoming: incoming.note,
      baseline: baseline.note,
      winner: winner.note,
      equalsFn: (a, b) => a == b,
    );
    final mergedLabels = _mergeLabelSets(
      local: local.labelIds,
      incoming: incoming.labelIds,
      baseline: baseline.labelIds,
    );
    final mergedConditions = _mergeScalar(
      local: local.conditions,
      incoming: incoming.conditions,
      baseline: baseline.conditions,
      winner: winner.conditions,
      equalsFn: (a, b) => compareConditionModels(a, b) == 0,
    );
    final mergedLinks = _mergeScalar(
      local: local.links,
      incoming: incoming.links,
      baseline: baseline.links,
      winner: winner.links,
      equalsFn: (a, b) => compareLinkLists(a, b) == 0,
    );
    final stateSource = _mergeScalar(
      local: local,
      incoming: incoming,
      baseline: baseline,
      winner: winner,
      equalsFn: (a, b) => compareTaskStates(a, b) == 0,
    );

    final candidate = TaskItem(
      id: winner.id,
      title: mergedName,
      note: mergedNote,
      createdAt: winner.createdAt,
      queuedAt: stateSource.queuedAt,
      completedAt: stateSource.completedAt,
      completions: stateSource.completions,
      isPriority: stateSource.isPriority,
      suspendedAt: stateSource.suspendedAt,
      isSuspendedForever: stateSource.isSuspendedForever,
      repeatRule: stateSource.repeatRule,
      labelIds: mergedLabels,
      dependencies: stateSource.dependencies,
      links: mergedLinks,
      conditions: mergedConditions,
      subtasksAutoFinish: stateSource.subtasksAutoFinish,
      subtasks: stateSource.subtasks,
    );

    final greatestExisting = _greatestTaskVersion(baseline, local, incoming);
    if (compareTaskPayloads(greatestExisting, candidate) == 0) {
      return greatestExisting;
    }
    final nextRevision = _nextMergedRevision(
      baseline.effectiveModifiedAt,
      local.effectiveModifiedAt,
      incoming.effectiveModifiedAt,
    );
    return candidate.copyWith(modifiedAt: nextRevision);
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

  /// Compares two deferral states (`absent < (false, utcComponents) < (true, [])`).
  static int _compareDeferral(TaskItem left, TaskItem right) {
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
    if (foreverCmp != 0 || left.isSuspendedForever) {
      return foreverCmp;
    }
    return (left.suspendedAt ?? DateTime.utc(1970)).compareTo(
      right.suspendedAt ?? DateTime.utc(1970),
    );
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
    int Function(T a, T b) elementCompare,
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

  /// Compares two [LocationTaskCondition] rules by normalized decimal strings.
  static int _compareLocationCondition(
    LocationTaskCondition left,
    LocationTaskCondition right,
  ) {
    final latCmp = compareUtf8Strings(left.latitudeText, right.latitudeText);
    if (latCmp != 0) {
      return latCmp;
    }
    final lonCmp = compareUtf8Strings(left.longitudeText, right.longitudeText);
    if (lonCmp != 0) {
      return lonCmp;
    }
    return compareUtf8Strings(left.radiusText, right.radiusText);
  }

  /// Compares two nullable values (`null < non-null`).
  static int _compareNullable<T extends Object>(
    T? left,
    T? right,
    int Function(T a, T b) valueCompare,
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

  /// Compares two [TaskRepeatRule] values `(count, unit, (hour, minute, second))`.
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
    return left.clock.second.compareTo(right.clock.second);
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

  /// Compares two `subtasks` blocks (`omitted < (autoFinish, steps)`).
  static int _compareSubtasksBlock(TaskItem left, TaskItem right) {
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

  /// Selects the greatest existing [TdfLabel] among [baseline], [local], and [incoming] under Section 6.7.4.
  static TdfLabel _greatestLabelVersion(
    TdfLabel baseline,
    TdfLabel local,
    TdfLabel incoming,
  ) {
    var best = compareLabelVersions(local, incoming) >= 0 ? local : incoming;
    if (compareLabelVersions(baseline, best) > 0) {
      best = baseline;
    }
    return best;
  }

  /// Selects the greatest existing [TaskItem] among [baseline], [local], and [incoming] under Section 6.7.4.
  static TaskItem _greatestTaskVersion(
    TaskItem baseline,
    TaskItem local,
    TaskItem incoming,
  ) {
    var best = compareTaskVersions(local, incoming) >= 0 ? local : incoming;
    if (compareTaskVersions(baseline, best) > 0) {
      best = baseline;
    }
    return best;
  }

  /// Merges label reference sets `(B \ removed) U added` in ascending ASCII order per Section 6.7.5.
  static List<String> _mergeLabelSets({
    required List<String> local,
    required List<String> incoming,
    required List<String> baseline,
  }) {
    final bSet = <String>{...baseline};
    final lSet = <String>{...local};
    final rSet = <String>{...incoming};

    final added = <String>{...lSet.difference(bSet), ...rSet.difference(bSet)};
    final removed = <String>{
      ...bSet.difference(lSet),
      ...bSet.difference(rSet),
    };
    final result = bSet.difference(removed).union(added).toList()..sort();
    return result;
  }

  /// Applies the 4-step three-way scalar merge rule from Section 6.7.5.
  static T _mergeScalar<T>({
    required T local,
    required T incoming,
    required T baseline,
    required T winner,
    required bool Function(T a, T b) equalsFn,
  }) {
    if (equalsFn(local, incoming)) {
      return local;
    }
    if (equalsFn(local, baseline)) {
      return incoming;
    }
    if (equalsFn(incoming, baseline)) {
      return local;
    }
    return winner;
  }

  /// Computes `max(bMod, lMod, rMod) + 1 second` and validates calendar bounds per Section 6.7.6.
  static DateTime _nextMergedRevision(
    DateTime bMod,
    DateTime lMod,
    DateTime rMod,
  ) {
    var maxMod = bMod.isAfter(lMod) ? bMod : lMod;
    if (rMod.isAfter(maxMod)) {
      maxMod = rMod;
    }
    final next = maxMod.add(const Duration(seconds: 1));
    if (!TdfCalendar.isWithinTimestampBounds(next)) {
      throw const TdfException(
        kind: TdfErrorKind.invalidTimestamp,
        line: 1,
        message: 'Merged revision exceeds maximum supported timestamp.',
      );
    }
    return next;
  }

  /// Deduplicates and sorts [labelIds] in ascending ASCII order.
  static List<String> _normalizedLabelSet(List<String> labelIds) {
    if (labelIds.isEmpty) {
      return const <String>[];
    }
    final sorted = <String>{...labelIds}.toList()..sort();
    return sorted;
  }
}

/// Normalized condition representation `(globalAny, dayGroup, timeGroup, locationGroup)` per Section 6.7.3.
@immutable
class _NormalizedConditionModel {
  const _NormalizedConditionModel({
    required this.globalAny,
    required this.dayResetAny,
    required this.dayRules,
    required this.timeResetAny,
    required this.timeRules,
    required this.locationResetAny,
    required this.locationRules,
  });

  /// Extracts a [_NormalizedConditionModel] from [conditions] in a single pass.
  factory _NormalizedConditionModel.fromList(List<TaskCondition> conditions) {
    var globalAny = false;
    var dayReset = false;
    var timeReset = false;
    var locReset = false;
    final dayRules = <DayTaskCondition>[];
    final timeRules = <TimeWindowTaskCondition>[];
    final locRules = <LocationTaskCondition>[];

    for (final rule in conditions) {
      switch (rule) {
        case GlobalResetTaskCondition():
          globalAny = true;
        case GroupResetTaskCondition(:final targetGroup):
          switch (targetGroup) {
            case ConditionGroup.day:
              dayReset = true;
            case ConditionGroup.time:
              timeReset = true;
            case ConditionGroup.location:
              locReset = true;
          }
        case DayTaskCondition():
          dayRules.add(rule);
        case TimeWindowTaskCondition():
          timeRules.add(rule);
        case LocationTaskCondition():
          locRules.add(rule);
      }
    }

    return _NormalizedConditionModel(
      globalAny: globalAny,
      dayResetAny: dayReset,
      dayRules: dayRules,
      timeResetAny: timeReset,
      timeRules: timeRules,
      locationResetAny: locReset,
      locationRules: locRules,
    );
  }

  final bool dayResetAny;
  final List<DayTaskCondition> dayRules;
  final bool globalAny;
  final bool locationResetAny;
  final List<LocationTaskCondition> locationRules;
  final bool timeResetAny;
  final List<TimeWindowTaskCondition> timeRules;
}
