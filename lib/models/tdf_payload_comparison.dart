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

import 'task_item.dart';
import 'tdf_error.dart';
import 'tdf_location.dart';
import 'tdf_metadata.dart';
import 'tdf_sync_metadata.dart';
import 'tdf_timezone.dart';

/// Stateless decoded payload tuple comparator and three-way unit merge engine
/// per `TDF_SPEC_0.6.0.md` Sections 6.7.3–6.7.6 and 6.11.2.
@immutable
class TdfPayloadComparison {
  /// Prevents instantiation of this stateless helper class.
  const TdfPayloadComparison._();

  /// Compares two condition lists normalized into `(globalAny, dayGroup, timeGroup, locationGroup)`.
  static int compareConditionModels(
    List<TaskCondition> left,
    List<TaskCondition> right,
  ) {
    final normLeft = _NormalizedConditionModel.fromList(left);
    final normRight = _NormalizedConditionModel.fromList(right);
    return _compareNormalizedConditionModels(normLeft, normRight);
  }

  /// Compares two [TdfLabel] decoded payloads `(scoped, name, note, color, condition)` per Section 6.7.3.
  static int compareLabelPayloads(TdfLabel left, TdfLabel right) {
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
    return compareConditionModels(left.conditions, right.conditions);
  }

  /// Compares two [TdfLabel] versions for the complete entity winner per Section 6.7.4.
  static int compareLabelVersions(TdfLabel left, TdfLabel right) {
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

  /// Compares two ordered [TaskLink] lists per Section 6.7.3.
  static int compareLinkLists(List<TaskLink> left, List<TaskLink> right) {
    return _compareList(left, right, _compareSingleLink);
  }

  /// Compares two [TdfLocation] decoded payloads `(name, note, (coordinates, source), radius)` per Section 6.7.3.
  static int compareLocationPayloads(TdfLocation left, TdfLocation right) {
    final nameCmp = compareUtf8Strings(left.name, right.name);
    if (nameCmp != 0) {
      return nameCmp;
    }
    final noteCmp = _compareNullable(left.note, right.note, compareUtf8Strings);
    if (noteCmp != 0) {
      return noteCmp;
    }
    final coordSourceCmp = _compareLocationCoordAndSource(left, right);
    if (coordSourceCmp != 0) {
      return coordSourceCmp;
    }
    return compareUtf8Strings(left.radiusText, right.radiusText);
  }

  /// Compares two [TdfLocation] versions for the complete entity winner per Section 6.7.4.
  static int compareLocationVersions(TdfLocation left, TdfLocation right) {
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

  /// Compares two [TdfQueueBlock] versions by `modifiedAt`, then lexicographical ASCII `taskIds` per Section 6.11.2.
  static int compareQueueBlocks(TdfQueueBlock left, TdfQueueBlock right) {
    final modCmp = left.modifiedAt.compareTo(right.modifiedAt);
    if (modCmp != 0) {
      return modCmp;
    }
    return _compareList(left.taskIds, right.taskIds, compareUtf8Strings);
  }

  /// Compares two [TaskItem] decoded payloads `(created, name, note, labels, condition, origin, link, taskState)` per Section 6.7.3.
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
    return compareTaskStates(left, right);
  }

  /// Compares two [TaskItem] occurrence states `(completions, priority, finished, suspended, due, repeat, blocked, subtasks)` per Section 6.7.3.
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
      (a, b) => a.compareTo(b),
    );
    if (finCmp != 0) {
      return finCmp;
    }
    final suspCmp = _compareDeferral(left, right);
    if (suspCmp != 0) {
      return suspCmp;
    }
    final dueCmp = _compareNullable(
      left.dueAt,
      right.dueAt,
      (a, b) => a.compareTo(b),
    );
    if (dueCmp != 0) {
      return dueCmp;
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

  /// Merges [local] and [incoming] [TdfLabel] versions using [baseline] and [tombstonedLocationIds] per Sections 6.7.5 and 6.7.6.
  static TdfLabel mergeLabelWithBaseline({
    required TdfLabel local,
    required TdfLabel incoming,
    required TdfLabel? baseline,
    Set<String> tombstonedLocationIds = const <String>{},
  }) {
    final localWins = compareLabelVersions(local, incoming) >= 0;
    final winner = localWins ? local : incoming;
    final loser = localWins ? incoming : local;
    if (baseline == null) {
      return winner;
    }
    final mergedScoped = _mergeScalar(
      local: local.isScoped,
      incoming: incoming.isScoped,
      baseline: baseline.isScoped,
      winner: winner.isScoped,
      equalsFn: (a, b) => a == b,
    );
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
    final mergedConditions = _mergeConditionsGroupWise(
      local: local.conditions,
      incoming: incoming.conditions,
      baseline: baseline.conditions,
      winner: winner.conditions,
      loser: loser.conditions,
      tombstonedLocationIds: tombstonedLocationIds,
      isTask: false,
      hasLiveLabelLocationRule: false,
    );

    final candidate = TdfLabel(
      id: winner.id,
      isScoped: mergedScoped,
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

  /// Merges [local] and [incoming] [TdfLocation] versions using [baseline] per Sections 6.7.5 and 6.7.6.
  static TdfLocation mergeLocationWithBaseline({
    required TdfLocation local,
    required TdfLocation incoming,
    required TdfLocation? baseline,
  }) {
    final winner = compareLocationVersions(local, incoming) >= 0
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
    final mergedCoordSource = _mergeScalar(
      local: local,
      incoming: incoming,
      baseline: baseline,
      winner: winner,
      equalsFn: (a, b) => _compareLocationCoordAndSource(a, b) == 0,
    );
    final mergedRadiusLoc = _mergeScalar(
      local: local,
      incoming: incoming,
      baseline: baseline,
      winner: winner,
      equalsFn: (a, b) => a.radiusText == b.radiusText,
    );

    final candidate = TdfLocation(
      id: winner.id,
      name: mergedName,
      note: mergedNote,
      source: mergedCoordSource.source,
      latitude: mergedCoordSource.latitude,
      longitude: mergedCoordSource.longitude,
      radius: mergedRadiusLoc.radius,
      rawLatitudeText: mergedCoordSource.latitudeText,
      rawLongitudeText: mergedCoordSource.longitudeText,
      rawRadiusText: mergedRadiusLoc.radiusText,
    );

    final greatestExisting = _greatestLocationVersion(
      baseline,
      local,
      incoming,
    );
    if (compareLocationPayloads(greatestExisting, candidate) == 0) {
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
    Set<String> tombstonedLocationIds = const <String>{},
    Set<String> tombstonedLabelIds = const <String>{},
    Set<String>? validLabelIds,
    Map<String, TdfLabel> postCascadeLabelsById = const <String, TdfLabel>{},
  }) {
    final localWins = compareTaskVersions(local, incoming) >= 0;
    final winner = localWins ? local : incoming;
    final loser = localWins ? incoming : local;
    if (baseline == null) {
      return _preserveTombstonedLabelsWithoutBaseline(
        winner,
        loser,
        tombstonedLabelIds,
      );
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
      tombstonedLabelIds: tombstonedLabelIds,
    );
    final hasLiveLabelLocationRule = _hasLiveLabelLocationRuleForTask(
      mergedLabels,
      validLabelIds,
      postCascadeLabelsById,
    );
    final mergedConditions = _mergeConditionsGroupWise(
      local: local.conditions,
      incoming: incoming.conditions,
      baseline: baseline.conditions,
      winner: winner.conditions,
      loser: loser.conditions,
      tombstonedLocationIds: tombstonedLocationIds,
      isTask: true,
      hasLiveLabelLocationRule: hasLiveLabelLocationRule,
    );
    final mergedOrigin = _mergeScalar(
      local: local.origin,
      incoming: incoming.origin,
      baseline: baseline.origin,
      winner: winner.origin,
      equalsFn: (a, b) => a == b,
    );
    final mergedLinks = _mergeScalar(
      local: local.links,
      incoming: incoming.links,
      baseline: baseline.links,
      winner: winner.links,
      equalsFn: (a, b) => compareLinkLists(a, b) == 0,
    );

    final candidate = _buildMergedTaskCandidate(
      local: local,
      incoming: incoming,
      baseline: baseline,
      winner: winner,
      mergedName: mergedName,
      mergedNote: mergedNote,
      mergedLabels: mergedLabels,
      mergedConditions: mergedConditions,
      mergedOrigin: mergedOrigin,
      mergedLinks: mergedLinks,
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

  /// Constructs the merged [TaskItem] candidate by applying either Same-Occurrence Unbundling (Case 2) or Cross-Occurrence Atomic State (Case 1) per Section 6.7.5.
  static TaskItem _buildMergedTaskCandidate({
    required TaskItem local,
    required TaskItem incoming,
    required TaskItem baseline,
    required TaskItem winner,
    required String mergedName,
    required String? mergedNote,
    required List<String> mergedLabels,
    required List<TaskCondition> mergedConditions,
    required TaskOrigin? mergedOrigin,
    required List<TaskLink> mergedLinks,
  }) {
    final sameOccurrenceOpen =
        baseline.completions == local.completions &&
        baseline.completions == incoming.completions &&
        baseline.completedAt == null &&
        local.completedAt == null &&
        incoming.completedAt == null &&
        !baseline.isCompleted &&
        !local.isCompleted &&
        !incoming.isCompleted;

    if (!sameOccurrenceOpen) {
      final stateSource = _mergeScalar(
        local: local,
        incoming: incoming,
        baseline: baseline,
        winner: winner,
        equalsFn: (a, b) => compareTaskStates(a, b) == 0,
      );
      return TaskItem(
        id: winner.id,
        title: mergedName,
        note: mergedNote,
        createdAt: winner.createdAt,
        completedAt: stateSource.completedAt,
        isCompleted: stateSource.isCompleted || stateSource.completedAt != null,
        completions: stateSource.completions,
        isPriority: stateSource.isPriority,
        suspendedAt: stateSource.suspendedAt,
        isSuspendedForever: stateSource.isSuspendedForever,
        dueAt: stateSource.dueAt,
        repeatRule: stateSource.repeatRule,
        origin: mergedOrigin,
        labelIds: mergedLabels,
        dependencies: stateSource.dependencies,
        links: mergedLinks,
        conditions: mergedConditions,
        subtasksAutoFinish: stateSource.subtasksAutoFinish,
        subtasks: stateSource.subtasks,
      );
    }

    final mergedPriority = _mergeScalar(
      local: local.isPriority,
      incoming: incoming.isPriority,
      baseline: baseline.isPriority,
      winner: winner.isPriority,
      equalsFn: (a, b) => a == b,
    );
    final deferralSource = _mergeScalar(
      local: local,
      incoming: incoming,
      baseline: baseline,
      winner: winner,
      equalsFn: (a, b) => _compareDeferral(a, b) == 0,
    );
    final mergedDue = _mergeScalar(
      local: local.dueAt,
      incoming: incoming.dueAt,
      baseline: baseline.dueAt,
      winner: winner.dueAt,
      equalsFn: (a, b) => a == b,
    );
    final mergedRepeat = _mergeScalar(
      local: local.repeatRule,
      incoming: incoming.repeatRule,
      baseline: baseline.repeatRule,
      winner: winner.repeatRule,
      equalsFn: (a, b) => _compareNullable(a, b, _compareRepeatRule) == 0,
    );
    final mergedDependencies = _mergeDependencyMaps(
      local: local.dependencies,
      incoming: incoming.dependencies,
      baseline: baseline.dependencies,
      winner: winner.dependencies,
    );
    final mergedSubtasks = _mergeSubtasksUnbundled(
      local: local,
      incoming: incoming,
      baseline: baseline,
      winner: winner,
    );

    return TaskItem(
      id: winner.id,
      title: mergedName,
      note: mergedNote,
      createdAt: winner.createdAt,
      completions: winner.completions,
      isPriority: mergedPriority,
      suspendedAt: deferralSource.suspendedAt,
      isSuspendedForever: deferralSource.isSuspendedForever,
      dueAt: mergedDue,
      repeatRule: mergedRepeat,
      origin: mergedOrigin,
      labelIds: mergedLabels,
      dependencies: mergedDependencies,
      links: mergedLinks,
      conditions: mergedConditions,
      subtasksAutoFinish: mergedSubtasks.autoFinish,
      subtasks: mergedSubtasks.steps,
    );
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
    final idCmp = _compareList(
      left.locationIds,
      right.locationIds,
      compareUtf8Strings,
    );
    if (idCmp != 0) {
      return idCmp;
    }
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

  /// Compares the coupled `((latitudeText, longitudeText), source)` unit of two [TdfLocation]s.
  static int _compareLocationCoordAndSource(
    TdfLocation left,
    TdfLocation right,
  ) {
    final latCmp = compareUtf8Strings(left.latitudeText, right.latitudeText);
    if (latCmp != 0) {
      return latCmp;
    }
    final lonCmp = compareUtf8Strings(left.longitudeText, right.longitudeText);
    if (lonCmp != 0) {
      return lonCmp;
    }
    return _compareNullable(left.source, right.source, compareUtf8Strings);
  }

  /// Compares two [_NormalizedConditionModel] instances.
  static int _compareNormalizedConditionModels(
    _NormalizedConditionModel normLeft,
    _NormalizedConditionModel normRight,
  ) {
    final globalCmp = _compareBool(normLeft.globalAny, normRight.globalAny);
    if (globalCmp != 0) {
      return globalCmp;
    }
    final dayGroupCmp = _compareDayGroup(normLeft, normRight);
    if (dayGroupCmp != 0) {
      return dayGroupCmp;
    }
    final timeGroupCmp = _compareTimeGroup(normLeft, normRight);
    if (timeGroupCmp != 0) {
      return timeGroupCmp;
    }
    return _compareLocationGroup(normLeft, normRight);
  }

  /// Compares the `day` condition group of two [_NormalizedConditionModel] instances.
  static int _compareDayGroup(
    _NormalizedConditionModel left,
    _NormalizedConditionModel right,
  ) {
    final resetCmp = _compareBool(left.dayResetAny, right.dayResetAny);
    if (resetCmp != 0) {
      return resetCmp;
    }
    return _compareList(left.dayRules, right.dayRules, _compareDayCondition);
  }

  /// Compares the `location` condition group of two [_NormalizedConditionModel] instances.
  static int _compareLocationGroup(
    _NormalizedConditionModel left,
    _NormalizedConditionModel right,
  ) {
    final resetCmp = _compareBool(
      left.locationResetAny,
      right.locationResetAny,
    );
    if (resetCmp != 0) {
      return resetCmp;
    }
    final idsCmp = _compareList(
      left.locationIds,
      right.locationIds,
      compareUtf8Strings,
    );
    if (idsCmp != 0) {
      return idsCmp;
    }
    return _compareList(
      left.legacyLocationRules,
      right.legacyLocationRules,
      _compareLocationCondition,
    );
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

  /// Compares two [TaskOrigin] values `(namespace, externalKey)` by unsigned UTF-8 byte order.
  static int _compareOrigin(TaskOrigin left, TaskOrigin right) {
    final nsCmp = compareUtf8Strings(left.namespace, right.namespace);
    if (nsCmp != 0) {
      return nsCmp;
    }
    return compareUtf8Strings(left.externalKey, right.externalKey);
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

  /// Compares the `time` condition group of two [_NormalizedConditionModel] instances.
  static int _compareTimeGroup(
    _NormalizedConditionModel left,
    _NormalizedConditionModel right,
  ) {
    final resetCmp = _compareBool(left.timeResetAny, right.timeResetAny);
    if (resetCmp != 0) {
      return resetCmp;
    }
    return _compareList(left.timeRules, right.timeRules, _compareTimeCondition);
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

  /// Selects the greatest existing [TdfLocation] among [baseline], [local], and [incoming] under Section 6.7.4.
  static TdfLocation _greatestLocationVersion(
    TdfLocation baseline,
    TdfLocation local,
    TdfLocation incoming,
  ) {
    var best = compareLocationVersions(local, incoming) >= 0 ? local : incoming;
    if (compareLocationVersions(baseline, best) > 0) {
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

  /// Returns whether at least one live label in [mergedLabels] carries a post-cascade `location` condition rule.
  static bool _hasLiveLabelLocationRuleForTask(
    List<String> mergedLabels,
    Set<String>? validLabelIds,
    Map<String, TdfLabel> postCascadeLabelsById,
  ) {
    for (final labelId in mergedLabels) {
      if (validLabelIds != null && !validLabelIds.contains(labelId)) {
        continue;
      }
      final label = postCascadeLabelsById[labelId];
      if (label != null && _labelHasLocationRule(label)) {
        return true;
      }
    }
    return false;
  }

  /// Returns whether [label] contains at least one `LocationTaskCondition` with non-empty `locationIds`.
  static bool _labelHasLocationRule(TdfLabel label) {
    for (final rule in label.conditions) {
      if (rule is LocationTaskCondition && rule.locationIds.isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  /// Applies pre-merge tombstone stripping and the commutative group-wise `condition` merge per Section 6.7.5 Point 2.
  static List<TaskCondition> _mergeConditionsGroupWise({
    required List<TaskCondition> local,
    required List<TaskCondition> incoming,
    required List<TaskCondition> baseline,
    required List<TaskCondition> winner,
    required List<TaskCondition> loser,
    required Set<String> tombstonedLocationIds,
    required bool isTask,
    required bool hasLiveLabelLocationRule,
  }) {
    final rawBase = _NormalizedConditionModel.fromList(baseline);
    final rawLocal = _NormalizedConditionModel.fromList(local);
    final rawIncoming = _NormalizedConditionModel.fromList(incoming);
    final rawWinner = _NormalizedConditionModel.fromList(winner);
    final rawLoser = _NormalizedConditionModel.fromList(loser);

    final allBaseLocsTombstoned =
        isTask &&
        !rawBase.globalAny &&
        !rawBase.locationResetAny &&
        rawBase.locationIds.isNotEmpty &&
        rawBase.locationIds.every(tombstonedLocationIds.contains);

    final normBase = _stripTombstonedLocations(
      rawBase,
      tombstonedLocationIds: tombstonedLocationIds,
      isTask: isTask,
      hasLiveLabelLocationRule: hasLiveLabelLocationRule,
      normalizeCascadeAnyToEmpty: false,
    );
    final normLocal = _stripTombstonedLocations(
      rawLocal,
      tombstonedLocationIds: tombstonedLocationIds,
      isTask: isTask,
      hasLiveLabelLocationRule: hasLiveLabelLocationRule,
      normalizeCascadeAnyToEmpty:
          allBaseLocsTombstoned && !hasLiveLabelLocationRule,
    );
    final normIncoming = _stripTombstonedLocations(
      rawIncoming,
      tombstonedLocationIds: tombstonedLocationIds,
      isTask: isTask,
      hasLiveLabelLocationRule: hasLiveLabelLocationRule,
      normalizeCascadeAnyToEmpty:
          allBaseLocsTombstoned && !hasLiveLabelLocationRule,
    );
    final normWinner = _stripTombstonedLocations(
      rawWinner,
      tombstonedLocationIds: tombstonedLocationIds,
      isTask: isTask,
      hasLiveLabelLocationRule: hasLiveLabelLocationRule,
      normalizeCascadeAnyToEmpty:
          allBaseLocsTombstoned && !hasLiveLabelLocationRule,
    );
    final normLoser = _stripTombstonedLocations(
      rawLoser,
      tombstonedLocationIds: tombstonedLocationIds,
      isTask: isTask,
      hasLiveLabelLocationRule: hasLiveLabelLocationRule,
      normalizeCascadeAnyToEmpty:
          allBaseLocsTombstoned && !hasLiveLabelLocationRule,
    );

    if (normBase.globalAny || normLocal.globalAny || normIncoming.globalAny) {
      final mergedFull = _mergeScalar(
        local: normLocal,
        incoming: normIncoming,
        baseline: normBase,
        winner: normWinner,
        equalsFn: (a, b) => _compareNormalizedConditionModels(a, b) == 0,
      );
      return mergedFull.toConditionList();
    }

    final mergedDay = _mergeScalar(
      local: normLocal,
      incoming: normIncoming,
      baseline: normBase,
      winner: normWinner,
      equalsFn: (a, b) => _compareDayGroup(a, b) == 0,
    );
    final mergedTime = _mergeScalar(
      local: normLocal,
      incoming: normIncoming,
      baseline: normBase,
      winner: normWinner,
      equalsFn: (a, b) => _compareTimeGroup(a, b) == 0,
    );
    final mergedLoc = _mergeLocationConditionGroup(
      local: normLocal,
      incoming: normIncoming,
      baseline: normBase,
      winner: normWinner,
      loser: normLoser,
    );

    final mergedModel = _NormalizedConditionModel(
      globalAny: false,
      dayResetAny: mergedDay.dayResetAny,
      dayRules: mergedDay.dayRules,
      timeResetAny: mergedTime.timeResetAny,
      timeRules: mergedTime.timeRules,
      locationResetAny: mergedLoc.locationResetAny,
      locationIds: mergedLoc.locationIds,
      legacyLocationRules: mergedLoc.legacyLocationRules,
    );
    return mergedModel.toConditionList();
  }

  /// Merges `blocked` dependency maps per `targetId` across [local], [incoming], and [baseline] using [winner] on conflict.
  static List<TdfTaskDependency> _mergeDependencyMaps({
    required List<TdfTaskDependency> local,
    required List<TdfTaskDependency> incoming,
    required List<TdfTaskDependency> baseline,
    required List<TdfTaskDependency> winner,
  }) {
    final bMap = <String, int>{
      for (final dep in baseline) dep.taskId: dep.requiredCompletion,
    };
    final lMap = <String, int>{
      for (final dep in local) dep.taskId: dep.requiredCompletion,
    };
    final rMap = <String, int>{
      for (final dep in incoming) dep.taskId: dep.requiredCompletion,
    };
    final wMap = <String, int>{
      for (final dep in winner) dep.taskId: dep.requiredCompletion,
    };

    final orderedTargetIds = <String>[];
    final seenIds = <String>{};
    for (final dep in <TdfTaskDependency>[
      ...winner,
      ...local,
      ...incoming,
      ...baseline,
    ]) {
      if (seenIds.add(dep.taskId)) {
        orderedTargetIds.add(dep.taskId);
      }
    }

    final merged = <TdfTaskDependency>[];
    for (final targetId in orderedTargetIds) {
      final mergedReq = _mergeScalar<int?>(
        local: lMap[targetId],
        incoming: rMap[targetId],
        baseline: bMap[targetId],
        winner: wMap[targetId],
        equalsFn: (a, b) => a == b,
      );
      if (mergedReq != null) {
        merged.add(
          TdfTaskDependency(taskId: targetId, requiredCompletion: mergedReq),
        );
      }
    }
    return merged;
  }

  /// Merges label reference sets `(B \ removed) U added` in ascending ASCII order per Section 6.7.5, excluding [tombstonedLabelIds] from `removed` per Section 6.7.8.
  static List<String> _mergeLabelSets({
    required List<String> local,
    required List<String> incoming,
    required List<String> baseline,
    Set<String> tombstonedLabelIds = const <String>{},
  }) {
    final bSet = <String>{...baseline};
    final lSet = <String>{...local};
    final rSet = <String>{...incoming};

    final added = <String>{...lSet.difference(bSet), ...rSet.difference(bSet)};
    final removed = <String>{
      ...bSet.difference(lSet).difference(tombstonedLabelIds),
      ...bSet.difference(rSet).difference(tombstonedLabelIds),
    };
    final result = bSet.difference(removed).union(added).toList()..sort();
    return result;
  }

  /// Merges the `location` condition group using the Commutative `W`-Anchored Ordered-List Merge per Section 6.7.5 Point 2.
  static _NormalizedConditionModel _mergeLocationConditionGroup({
    required _NormalizedConditionModel local,
    required _NormalizedConditionModel incoming,
    required _NormalizedConditionModel baseline,
    required _NormalizedConditionModel winner,
    required _NormalizedConditionModel loser,
  }) {
    if (_compareLocationGroup(local, incoming) == 0) {
      return local;
    }
    if (_compareLocationGroup(local, baseline) == 0) {
      return incoming;
    }
    if (_compareLocationGroup(incoming, baseline) == 0) {
      return local;
    }
    if (baseline.locationResetAny ||
        local.locationResetAny ||
        incoming.locationResetAny ||
        baseline.legacyLocationRules.isNotEmpty ||
        local.legacyLocationRules.isNotEmpty ||
        incoming.legacyLocationRules.isNotEmpty) {
      return winner;
    }

    final removedByLoser = <String>{
      for (final id in baseline.locationIds)
        if (!loser.locationIds.contains(id)) id,
    };
    final mergedIds = <String>[];
    final seen = <String>{};
    for (final id in winner.locationIds) {
      if (!removedByLoser.contains(id) && seen.add(id)) {
        mergedIds.add(id);
      }
    }
    for (final id in loser.locationIds) {
      if (!baseline.locationIds.contains(id) && seen.add(id)) {
        mergedIds.add(id);
      }
    }
    return winner.withLocationGroup(resetAny: false, locationIds: mergedIds);
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

  /// Merges `subtasks` per-step when ordered step titles match across [baseline], [local], and [incoming], or atomically otherwise.
  static ({bool autoFinish, List<SubtaskItem> steps}) _mergeSubtasksUnbundled({
    required TaskItem local,
    required TaskItem incoming,
    required TaskItem baseline,
    required TaskItem winner,
  }) {
    final sameStepTitles =
        baseline.subtasks.isNotEmpty &&
        local.subtasks.length == baseline.subtasks.length &&
        incoming.subtasks.length == baseline.subtasks.length &&
        _haveIdenticalStepTitles(
          baseline.subtasks,
          local.subtasks,
          incoming.subtasks,
        );

    if (!sameStepTitles) {
      final blockWinner = _mergeScalar(
        local: local,
        incoming: incoming,
        baseline: baseline,
        winner: winner,
        equalsFn: (a, b) => _compareSubtasksBlock(a, b) == 0,
      );
      return (
        autoFinish: blockWinner.subtasksAutoFinish,
        steps: blockWinner.subtasks,
      );
    }

    final mergedAutoFinish = _mergeScalar(
      local: local.subtasksAutoFinish,
      incoming: incoming.subtasksAutoFinish,
      baseline: baseline.subtasksAutoFinish,
      winner: winner.subtasksAutoFinish,
      equalsFn: (a, b) => a == b,
    );
    final mergedSteps = <SubtaskItem>[];
    for (var i = 0; i < baseline.subtasks.length; i++) {
      final mergedDone = _mergeScalar(
        local: local.subtasks[i].isCompleted,
        incoming: incoming.subtasks[i].isCompleted,
        baseline: baseline.subtasks[i].isCompleted,
        winner: winner.subtasks[i].isCompleted,
        equalsFn: (a, b) => a == b,
      );
      mergedSteps.add(
        SubtaskItem(title: baseline.subtasks[i].title, isCompleted: mergedDone),
      );
    }
    return (autoFinish: mergedAutoFinish, steps: mergedSteps);
  }

  /// Returns whether [baseSteps], [localSteps], and [incomingSteps] have identical ordered step titles.
  static bool _haveIdenticalStepTitles(
    List<SubtaskItem> baseSteps,
    List<SubtaskItem> localSteps,
    List<SubtaskItem> incomingSteps,
  ) {
    for (var i = 0; i < baseSteps.length; i++) {
      final title = baseSteps[i].title;
      if (localSteps[i].title != title || incomingSteps[i].title != title) {
        return false;
      }
    }
    return true;
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

  /// Preserves any [tombstonedLabelIds] from [loser] on [winner] when merging without a baseline so $L_{\text{before}}(T)$ includes tombstoned labels.
  static TaskItem _preserveTombstonedLabelsWithoutBaseline(
    TaskItem winner,
    TaskItem loser,
    Set<String> tombstonedLabelIds,
  ) {
    if (tombstonedLabelIds.isEmpty || loser.labelIds.isEmpty) {
      return winner;
    }
    final missingTombstoned = <String>[
      for (final id in loser.labelIds)
        if (tombstonedLabelIds.contains(id) && !winner.labelIds.contains(id))
          id,
    ];
    if (missingTombstoned.isEmpty) {
      return winner;
    }
    final combined = <String>[...winner.labelIds, ...missingTombstoned]..sort();
    return winner.copyWith(labelIds: combined);
  }

  /// Strips [tombstonedLocationIds] from [model] and converts an emptied task location group into its cascade target state per Section 6.7.5 Point 2.
  static _NormalizedConditionModel _stripTombstonedLocations(
    _NormalizedConditionModel model, {
    required Set<String> tombstonedLocationIds,
    required bool isTask,
    required bool hasLiveLabelLocationRule,
    required bool normalizeCascadeAnyToEmpty,
  }) {
    if (model.globalAny) {
      return model;
    }
    if (model.locationResetAny) {
      if (normalizeCascadeAnyToEmpty) {
        return model.withLocationGroup(
          resetAny: false,
          locationIds: const <String>[],
        );
      }
      return model;
    }
    if (tombstonedLocationIds.isEmpty || model.locationIds.isEmpty) {
      return model;
    }
    final retainedIds = <String>[
      for (final id in model.locationIds)
        if (!tombstonedLocationIds.contains(id)) id,
    ];
    if (retainedIds.length == model.locationIds.length) {
      return model;
    }
    if (retainedIds.isNotEmpty) {
      return model.withLocationGroup(resetAny: false, locationIds: retainedIds);
    }
    return model.withLocationGroup(
      resetAny: isTask && hasLiveLabelLocationRule,
      locationIds: const <String>[],
    );
  }
}

/// Normalized condition representation `(globalAny, dayGroup, timeGroup, locationGroup)` per Section 6.7.3.
@immutable
class _NormalizedConditionModel {
  /// Creates a [_NormalizedConditionModel].
  const _NormalizedConditionModel({
    required this.globalAny,
    required this.dayResetAny,
    required this.dayRules,
    required this.timeResetAny,
    required this.timeRules,
    required this.locationResetAny,
    required this.locationIds,
    required this.legacyLocationRules,
  });

  /// Extracts a [_NormalizedConditionModel] from [conditions] in a single pass.
  factory _NormalizedConditionModel.fromList(List<TaskCondition> conditions) {
    var globalAny = false;
    var dayReset = false;
    var timeReset = false;
    var locReset = false;
    final dayRules = <DayTaskCondition>[];
    final timeRules = <TimeWindowTaskCondition>[];
    final locIds = <String>[];
    final seenLocIds = <String>{};
    final legacyLocRules = <LocationTaskCondition>[];

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
          if (rule.locationIds.isNotEmpty) {
            _appendUniqueLocationIds(rule.locationIds, seenLocIds, locIds);
          } else {
            legacyLocRules.add(rule);
          }
      }
    }

    return _NormalizedConditionModel(
      globalAny: globalAny,
      dayResetAny: dayReset,
      dayRules: dayRules,
      timeResetAny: timeReset,
      timeRules: timeRules,
      locationResetAny: locReset,
      locationIds: locIds,
      legacyLocationRules: legacyLocRules,
    );
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

  final bool dayResetAny;
  final List<DayTaskCondition> dayRules;
  final bool globalAny;
  final List<LocationTaskCondition> legacyLocationRules;
  final List<String> locationIds;
  final bool locationResetAny;
  final bool timeResetAny;
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
      else ...[
        if (locationIds.isNotEmpty)
          LocationTaskCondition(locationIds: locationIds),
        ...legacyLocationRules,
      ],
    ];
  }

  /// Returns a copy of this model with its `location` group replaced by [resetAny] and [locationIds].
  _NormalizedConditionModel withLocationGroup({
    required bool resetAny,
    required List<String> locationIds,
  }) {
    return _NormalizedConditionModel(
      globalAny: globalAny,
      dayResetAny: dayResetAny,
      dayRules: dayRules,
      timeResetAny: timeResetAny,
      timeRules: timeRules,
      locationResetAny: resetAny,
      locationIds: locationIds,
      legacyLocationRules: const <LocationTaskCondition>[],
    );
  }
}
