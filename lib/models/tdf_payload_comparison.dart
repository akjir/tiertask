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

import 'task_board_evaluator.dart';
import 'task_item.dart';
import 'tdf_error.dart';
import 'tdf_location.dart';
import 'tdf_metadata.dart';
import 'tdf_sync_metadata.dart';
import 'tdf_timezone.dart';

/// Stateless decoded payload tuple comparator, payload signature encoder, and
/// three-way unit merge engine per `spec/TDF_SPEC_0.8.0.md` Sections 2.6 and 12.
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

  /// Compares two [TdfLabel] decoded payloads `(scoped, name, note, color, link, condition)` (`TDF-MERGE-002`).
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
    final linkCmp = compareLinkLists(left.links, right.links);
    if (linkCmp != 0) {
      return linkCmp;
    }
    return compareConditionModels(left.conditions, right.conditions);
  }

  /// Compares two [TdfLabel] versions for the complete entity winner (`TDF-MERGE-003`).
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

  /// Compares two ordered [TaskLink] lists (`TDF-MERGE-002`).
  static int compareLinkLists(List<TaskLink> left, List<TaskLink> right) {
    return _compareList(left, right, _compareSingleLink);
  }

  /// Compares two [TdfLocation] decoded payloads `(name, note, (coordinates, source), radius)` (`TDF-MERGE-002`).
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
    return compareUtf8Strings(
      TdfLocation.normalizeDecimalText(left.radiusText),
      TdfLocation.normalizeDecimalText(right.radiusText),
    );
  }

  /// Compares two [TdfLocation] versions for the complete entity winner (`TDF-MERGE-003`).
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

  /// Compares two [TdfQueueBlock] versions by `modifiedAt`, then lexicographical ASCII `taskIds` (`TDF-QSYNC-001`).
  static int compareQueueBlocks(TdfQueueBlock left, TdfQueueBlock right) {
    final modCmp = left.modifiedAt.compareTo(right.modifiedAt);
    if (modCmp != 0) {
      return modCmp;
    }
    return _compareList(left.taskIds, right.taskIds, compareUtf8Strings);
  }

  /// Compares two [TaskItem] decoded payloads `(name, note, created, labels, origin, link, history, condition, taskState)` (`TDF-MERGE-002`).
  static int compareTaskPayloads(TaskItem left, TaskItem right) {
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
      _normalizedLabelSet(left.labelIds),
      _normalizedLabelSet(right.labelIds),
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
    final suspCmp = _compareDeferral(left, right);
    if (suspCmp != 0) {
      return suspCmp;
    }
    final dueCmp = _compareDue(left, right);
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

  /// Compares two [TaskItem] versions for the complete entity winner (`TDF-MERGE-003`).
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

  /// Compares two strings by unsigned UTF-8 byte order (`TDF-MERGE-002`).
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

  /// Merges [local] and [incoming] [TdfLabel] versions using [baseline] and [tombstonedLocationIds] (`TDF-MERGE-004`–`007`).
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
      equalsFn: (first, second) => first == second,
    );
    final mergedName = _mergeScalar(
      local: local.name,
      incoming: incoming.name,
      baseline: baseline.name,
      winner: winner.name,
      equalsFn: (first, second) => first == second,
    );
    final mergedNote = _mergeScalar(
      local: local.note,
      incoming: incoming.note,
      baseline: baseline.note,
      winner: winner.note,
      equalsFn: (first, second) => first == second,
    );
    final mergedColor = _mergeScalar(
      local: local.color,
      incoming: incoming.color,
      baseline: baseline.color,
      winner: winner.color,
      equalsFn: (first, second) =>
          first?.toUpperCase() == second?.toUpperCase(),
    );
    final mergedLinks = _mergeScalar(
      local: local.links,
      incoming: incoming.links,
      baseline: baseline.links,
      winner: winner.links,
      equalsFn: (first, second) => compareLinkLists(first, second) == 0,
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
      links: mergedLinks,
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

  /// Merges [local] and [incoming] [TdfLocation] versions using [baseline] (`TDF-MERGE-004`–`005`).
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
      equalsFn: (first, second) => first == second,
    );
    final mergedNote = _mergeScalar(
      local: local.note,
      incoming: incoming.note,
      baseline: baseline.note,
      winner: winner.note,
      equalsFn: (first, second) => first == second,
    );
    final mergedCoordSource = _mergeScalar(
      local: local,
      incoming: incoming,
      baseline: baseline,
      winner: winner,
      equalsFn: (first, second) =>
          _compareLocationCoordAndSource(first, second) == 0,
    );
    final mergedRadiusLoc = _mergeScalar(
      local: local,
      incoming: incoming,
      baseline: baseline,
      winner: winner,
      equalsFn: (first, second) =>
          TdfLocation.normalizeDecimalText(first.radiusText) ==
          TdfLocation.normalizeDecimalText(second.radiusText),
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

  /// Computes `cleaned` (gated by [cleanupMode]) and `uncleaned` (raw Case 2) merged [TaskItem] candidates (`TDF-MERGE-006`–`010`).
  static ({TaskItem cleaned, TaskItem uncleaned})
  mergeTaskCandidatesWithBaseline({
    required TaskItem local,
    required TaskItem incoming,
    required TaskItem? baseline,
    DateTime? evaluationTime,
    TdfCleanupMode cleanupMode = TdfCleanupMode.finalStage,
    Map<String, TaskItem> mergedLiveTasksById = const <String, TaskItem>{},
    Set<String> mergedDeletedTaskIds = const <String>{},
    Set<String> tombstonedLocationIds = const <String>{},
    Set<String> deletedLabelsLocal = const <String>{},
    Set<String> deletedLabelsIncoming = const <String>{},
    Set<String>? validLabelIds,
    Map<String, TdfLabel> postCascadeLabelsById = const <String, TdfLabel>{},
  }) {
    final localWins = compareTaskVersions(local, incoming) >= 0;
    final winner = localWins ? local : incoming;
    final loser = localWins ? incoming : local;
    if (baseline == null) {
      final deletedWinner = localWins
          ? deletedLabelsLocal
          : deletedLabelsIncoming;
      final deletedLoser = localWins
          ? deletedLabelsIncoming
          : deletedLabelsLocal;
      final baseFree = _mergeTaskWithoutBaseline(
        winner: winner,
        loser: loser,
        deletedLabelsWinner: deletedWinner,
        deletedLabelsLoser: deletedLoser,
      );
      return (cleaned: baseFree, uncleaned: baseFree);
    }

    final mergedName = _mergeScalar(
      local: local.title,
      incoming: incoming.title,
      baseline: baseline.title,
      winner: winner.title,
      equalsFn: (first, second) => first == second,
    );
    final mergedNote = _mergeScalar(
      local: local.note,
      incoming: incoming.note,
      baseline: baseline.note,
      winner: winner.note,
      equalsFn: (first, second) => first == second,
    );
    final mergedLabels = _mergeLabelSets(
      local: local.labelIds,
      incoming: incoming.labelIds,
      baseline: baseline.labelIds,
      deletedLabelsLocal: deletedLabelsLocal,
      deletedLabelsIncoming: deletedLabelsIncoming,
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
      equalsFn: (first, second) => first == second,
    );
    final mergedLinks = _mergeScalar(
      local: local.links,
      incoming: incoming.links,
      baseline: baseline.links,
      winner: winner.links,
      equalsFn: (first, second) => compareLinkLists(first, second) == 0,
    );
    final mergedHistory = _mergeHistorySets(
      local: local.history,
      incoming: incoming.history,
      baseline: baseline.history,
    );

    final uncleaned = _buildMergedTaskCandidate(
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
      mergedHistory: mergedHistory,
      preNormalizeBlocks: false,
      evaluationTime: evaluationTime,
      mergedLiveTasksById: const <String, TaskItem>{},
      mergedDeletedTaskIds: const <String>{},
    );
    if (cleanupMode == TdfCleanupMode.deferred) {
      return (cleaned: uncleaned, uncleaned: uncleaned);
    }
    final cleaned = _buildMergedTaskCandidate(
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
      mergedHistory: mergedHistory,
      preNormalizeBlocks: true,
      evaluationTime: evaluationTime,
      mergedLiveTasksById: mergedLiveTasksById,
      mergedDeletedTaskIds: mergedDeletedTaskIds,
    );
    return (cleaned: cleaned, uncleaned: uncleaned);
  }

  /// Merges [local] and [incoming] [TaskItem] versions using [baseline] and [cleanupMode] (`TDF-MERGE-004`, `TDF-MERGE-009`, `TDF-MERGE-010`).
  static TaskItem mergeTaskWithBaseline({
    required TaskItem local,
    required TaskItem incoming,
    required TaskItem? baseline,
    DateTime? evaluationTime,
    TdfCleanupMode cleanupMode = TdfCleanupMode.finalStage,
    Map<String, TaskItem> mergedLiveTasksById = const <String, TaskItem>{},
    Set<String> mergedDeletedTaskIds = const <String>{},
    Set<String> tombstonedLocationIds = const <String>{},
    Set<String> deletedLabelsLocal = const <String>{},
    Set<String> deletedLabelsIncoming = const <String>{},
    Set<String>? validLabelIds,
    Map<String, TdfLabel> postCascadeLabelsById = const <String, TdfLabel>{},
  }) {
    final normalizedNow = evaluationTime != null
        ? TaskItem.normalizeTimestamp(evaluationTime)
        : null;
    final candidates = mergeTaskCandidatesWithBaseline(
      local: local,
      incoming: incoming,
      baseline: baseline,
      evaluationTime: normalizedNow,
      cleanupMode: cleanupMode,
      mergedLiveTasksById: mergedLiveTasksById,
      mergedDeletedTaskIds: mergedDeletedTaskIds,
      tombstonedLocationIds: tombstonedLocationIds,
      deletedLabelsLocal: deletedLabelsLocal,
      deletedLabelsIncoming: deletedLabelsIncoming,
      validLabelIds: validLabelIds,
      postCascadeLabelsById: postCascadeLabelsById,
    );
    final localWins = compareTaskVersions(local, incoming) >= 0;
    final winner = localWins ? local : incoming;
    final referenceExisting = baseline != null
        ? _greatestTaskVersion(baseline, local, incoming)
        : winner;
    if (referenceExisting.completions == candidates.cleaned.completions &&
        compareTaskPayloads(referenceExisting, candidates.cleaned) == 0) {
      return candidates.cleaned.copyWith(
        modifiedAt: referenceExisting.modifiedAt,
        clearModifiedAt: referenceExisting.modifiedAt == null,
      );
    }
    final bumped = _nextMergedTaskRevision(
      local.effectiveModifiedAt,
      incoming.effectiveModifiedAt,
      baseline?.effectiveModifiedAt,
    );
    if (cleanupMode == TdfCleanupMode.deferred ||
        normalizedNow == null ||
        compareTaskPayloads(candidates.cleaned, candidates.uncleaned) == 0) {
      return candidates.cleaned.copyWith(modifiedAt: bumped);
    }
    final withNow = normalizedNow.isAfter(bumped) ? normalizedNow : bumped;
    if (!TdfCalendar.isWithinTimestampBounds(withNow)) {
      throw const TdfException(
        kind: TdfErrorKind.invalidTimestamp,
        line: 1,
        message: 'Merged revision exceeds maximum supported timestamp.',
      );
    }
    return candidates.cleaned.copyWith(modifiedAt: withNow);
  }

  /// Computes the merged `(completions, isCompleted, completedAt, repeatRule)` header of [local] and [incoming] for prerequisite pre-normalization.
  static TaskItem previewMergedTaskPrerequisiteHeader({
    required TaskItem local,
    required TaskItem incoming,
    required TaskItem? baseline,
  }) {
    final winner = compareTaskVersions(local, incoming) >= 0 ? local : incoming;
    if (baseline == null) {
      return winner;
    }
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
      return winner;
    }
    final mergedRepeat = _mergeScalar(
      local: local.repeatRule,
      incoming: incoming.repeatRule,
      baseline: baseline.repeatRule,
      winner: winner.repeatRule,
      equalsFn: (first, second) =>
          _compareNullable(first, second, _compareRepeatRule) == 0,
    );
    return winner.copyWith(
      repeatRule: mergedRepeat,
      clearRepeatRule: mergedRepeat == null,
    );
  }

  /// Encodes the normalized `TDF-MODEL-006` payload signature of [task] (including `dueAnchor`, excluding `modifiedAt`) for `TdfBoundDeletionDecision`.
  static String taskPayloadSignature(TaskItem task) {
    final buffer = StringBuffer('tsk|');
    _writeString(buffer, task.title);
    _writeNullableString(buffer, task.note);
    buffer
      ..write(task.createdAt.toUtc().millisecondsSinceEpoch)
      ..write(';');
    _writeStringListSignature(buffer, _normalizedLabelSet(task.labelIds));
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

  /// Appends unseen `<target-id>` keys from [dependencies] into [orderedIds].
  static void _appendUniqueDependencyIds(
    List<TdfTaskDependency> dependencies,
    Set<String> seenIds,
    List<String> orderedIds,
  ) {
    for (final dependency in dependencies) {
      if (seenIds.add(dependency.taskId)) {
        orderedIds.add(dependency.taskId);
      }
    }
  }

  /// Constructs the merged [TaskItem] candidate by applying either Same-Occurrence Unbundling (Case 2) or Cross-Occurrence Atomic State (Case 1) (`TDF-MERGE-010`).
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
    required List<TaskHistoryEntry> mergedHistory,
    required bool preNormalizeBlocks,
    required DateTime? evaluationTime,
    required Map<String, TaskItem> mergedLiveTasksById,
    required Set<String> mergedDeletedTaskIds,
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
      return TaskItem(
        id: winner.id,
        title: mergedName,
        note: mergedNote,
        createdAt: winner.createdAt,
        completedAt: winner.completedAt,
        isCompleted: winner.isCompleted || winner.completedAt != null,
        completions: winner.completions,
        isPriority: winner.isPriority,
        suspendedAt: winner.suspendedAt,
        isSuspendedForever: winner.isSuspendedForever,
        suspendedNote: winner.suspendedNote,
        dueAt: winner.dueAt,
        dueAnchor: winner.dueAnchor,
        isDuePassive: winner.isDuePassive,
        dueNote: winner.dueNote,
        repeatRule: winner.repeatRule,
        origin: mergedOrigin,
        labelIds: mergedLabels,
        dependencies: winner.dependencies,
        links: mergedLinks,
        history: mergedHistory,
        conditions: mergedConditions,
        subtasksAutoFinish: winner.subtasksAutoFinish,
        subtasks: winner.subtasks,
      );
    }

    final mergedPriority = _mergeScalar(
      local: local.isPriority,
      incoming: incoming.isPriority,
      baseline: baseline.isPriority,
      winner: winner.isPriority,
      equalsFn: (first, second) => first == second,
    );
    final deferralSource = _mergeCase2Deferral(
      local: local,
      incoming: incoming,
      baseline: baseline,
      winner: winner,
      preNormalizeBlocks: preNormalizeBlocks,
      evaluationTime: evaluationTime,
    );
    final dueSource = _mergeScalar(
      local: local,
      incoming: incoming,
      baseline: baseline,
      winner: winner,
      equalsFn: (first, second) => _compareDue(first, second) == 0,
    );
    final mergedRepeat = _mergeScalar(
      local: local.repeatRule,
      incoming: incoming.repeatRule,
      baseline: baseline.repeatRule,
      winner: winner.repeatRule,
      equalsFn: (first, second) =>
          _compareNullable(first, second, _compareRepeatRule) == 0,
    );
    final mergedDependencies = preNormalizeBlocks
        ? _mergePreNormalizedDependencyMaps(
            local: local,
            incoming: incoming,
            baseline: baseline,
            winner: winner,
            mergedLiveTasksById: mergedLiveTasksById,
            mergedDeletedTaskIds: mergedDeletedTaskIds,
          )
        : _mergeDependencyMaps(
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
      suspendedNote: deferralSource.suspendedNote,
      dueAt: dueSource.dueAt,
      dueAnchor: dueSource.dueAnchor,
      isDuePassive: dueSource.isDuePassive,
      dueNote: dueSource.dueNote,
      repeatRule: mergedRepeat,
      origin: mergedOrigin,
      labelIds: mergedLabels,
      dependencies: mergedDependencies,
      links: mergedLinks,
      history: mergedHistory,
      conditions: mergedConditions,
      subtasksAutoFinish: mergedSubtasks.autoFinish,
      subtasks: mergedSubtasks.steps,
    );
  }

  /// Collects unique ordered `<target-id>` keys from [lists].
  static List<String> _collectOrderedDependencyIds(
    List<List<TdfTaskDependency>> lists,
  ) {
    final orderedIds = <String>[];
    final seenIds = <String>{};
    for (final list in lists) {
      _appendUniqueDependencyIds(list, seenIds, orderedIds);
    }
    return orderedIds;
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

  /// Compares two deferral states (`absent < (false, utcComponents, note) < (true, [], note)`).
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

  /// Compares two atomic `due` 4-tuples (`absent < (utcComponents, dueAnchor, isDuePassive, dueNote)`).
  static int _compareDue(TaskItem left, TaskItem right) {
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

  /// Selects the greatest existing [TdfLabel] among [baseline], [local], and [incoming] (`TDF-MERGE-003`).
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

  /// Selects the greatest existing [TdfLocation] among [baseline], [local], and [incoming] (`TDF-MERGE-003`).
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

  /// Selects the greatest existing [TaskItem] among [baseline], [local], and [incoming] (`TDF-MERGE-003`).
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

  /// Returns whether [label] contains at least one `LocationTaskCondition` with non-empty `locationIds`.
  static bool _labelHasLocationRule(TdfLabel label) {
    for (final rule in label.conditions) {
      if (rule is LocationTaskCondition && rule.locationIds.isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  /// Merges the `suspended` deferral unit in Case 2 with optional expiry pre-normalization at [evaluationTime] (`TDF-MERGE-010`).
  static TaskItem _mergeCase2Deferral({
    required TaskItem local,
    required TaskItem incoming,
    required TaskItem baseline,
    required TaskItem winner,
    required bool preNormalizeBlocks,
    required DateTime? evaluationTime,
  }) {
    if (!preNormalizeBlocks || evaluationTime == null) {
      return _mergeScalar(
        local: local,
        incoming: incoming,
        baseline: baseline,
        winner: winner,
        equalsFn: (first, second) => _compareDeferral(first, second) == 0,
      );
    }
    final normLocal = _stripExpiredDeferral(local, evaluationTime);
    final normIncoming = _stripExpiredDeferral(incoming, evaluationTime);
    final normBaseline = _stripExpiredDeferral(baseline, evaluationTime);
    final normWinner = _stripExpiredDeferral(winner, evaluationTime);
    return _mergeScalar(
      local: normLocal,
      incoming: normIncoming,
      baseline: normBaseline,
      winner: normWinner,
      equalsFn: (first, second) => _compareDeferral(first, second) == 0,
    );
  }

  /// Applies pre-merge tombstone stripping and the commutative group-wise `condition` merge (`TDF-MERGE-007`).
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
        equalsFn: (first, second) =>
            _compareNormalizedConditionModels(first, second) == 0,
      );
      return mergedFull.toConditionList();
    }

    final mergedDay = _mergeScalar(
      local: normLocal,
      incoming: normIncoming,
      baseline: normBase,
      winner: normWinner,
      equalsFn: (first, second) => _compareDayGroup(first, second) == 0,
    );
    final mergedTime = _mergeScalar(
      local: normLocal,
      incoming: normIncoming,
      baseline: normBase,
      winner: normWinner,
      equalsFn: (first, second) => _compareTimeGroup(first, second) == 0,
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
      for (final dependency in baseline)
        dependency.taskId: dependency.requiredCompletion,
    };
    final lMap = <String, int>{
      for (final dependency in local)
        dependency.taskId: dependency.requiredCompletion,
    };
    final rMap = <String, int>{
      for (final dependency in incoming)
        dependency.taskId: dependency.requiredCompletion,
    };
    final wMap = <String, int>{
      for (final dependency in winner)
        dependency.taskId: dependency.requiredCompletion,
    };
    final orderedTargetIds = _collectOrderedDependencyIds(
      <List<TdfTaskDependency>>[winner, local, incoming, baseline],
    );

    final merged = <TdfTaskDependency>[];
    for (final targetId in orderedTargetIds) {
      final mergedReq = _mergeScalar<int?>(
        local: lMap[targetId],
        incoming: rMap[targetId],
        baseline: bMap[targetId],
        winner: wMap[targetId],
        equalsFn: (first, second) => first == second,
      );
      if (mergedReq != null) {
        merged.add(
          TdfTaskDependency(taskId: targetId, requiredCompletion: mergedReq),
        );
      }
    }
    return TdfTaskDependency.normalizeList(merged);
  }

  /// Merges occurrence-independent `history` sets `((B \ removed) U added)` (`TDF-MERGE-008`).
  static List<TaskHistoryEntry> _mergeHistorySets({
    required List<TaskHistoryEntry> local,
    required List<TaskHistoryEntry> incoming,
    required List<TaskHistoryEntry> baseline,
  }) {
    if (local.isEmpty && incoming.isEmpty && baseline.isEmpty) {
      return const <TaskHistoryEntry>[];
    }
    final baselineSet = <TaskHistoryEntry>{...baseline};
    final localSet = <TaskHistoryEntry>{...local};
    final incomingSet = <TaskHistoryEntry>{...incoming};
    final added = <TaskHistoryEntry>{
      ...localSet.difference(baselineSet),
      ...incomingSet.difference(baselineSet),
    };
    final removed = <TaskHistoryEntry>{
      ...baselineSet.difference(localSet),
      ...baselineSet.difference(incomingSet),
    };
    return TaskHistoryEntry.normalizeList(
      baselineSet.difference(removed).union(added),
    );
  }

  /// Reconstructs pre-cascade label set $L_{\text{before}}(T)$ in ascending ASCII order (`TDF-MERGE-006`).
  static List<String> _mergeLabelSets({
    required List<String> local,
    required List<String> incoming,
    required List<String> baseline,
    required Set<String> deletedLabelsLocal,
    required Set<String> deletedLabelsIncoming,
  }) {
    final bSet = <String>{...baseline};
    final lSet = <String>{...local};
    final rSet = <String>{...incoming};

    final added = <String>{...lSet.difference(bSet), ...rSet.difference(bSet)};
    final explicitRemovedL = bSet
        .difference(lSet)
        .difference(deletedLabelsLocal);
    final explicitRemovedR = bSet
        .difference(rSet)
        .difference(deletedLabelsIncoming);
    final result =
        bSet
            .difference(explicitRemovedL)
            .difference(explicitRemovedR)
            .union(added)
            .toList()
          ..sort();
    return result;
  }

  /// Merges the `location` condition group using the Commutative `W`-Anchored Ordered-List Merge (`TDF-MERGE-007`).
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

  /// Merges Case 2 `blocked` maps after `V.repeat`-aware pre-normalization against [mergedLiveTasksById] and [mergedDeletedTaskIds] (`TDF-MERGE-010`).
  static List<TdfTaskDependency> _mergePreNormalizedDependencyMaps({
    required TaskItem local,
    required TaskItem incoming,
    required TaskItem baseline,
    required TaskItem winner,
    required Map<String, TaskItem> mergedLiveTasksById,
    required Set<String> mergedDeletedTaskIds,
  }) {
    final bMap = <String, int>{
      for (final dependency in baseline.dependencies)
        dependency.taskId: dependency.requiredCompletion,
    };
    final lMap = <String, int>{
      for (final dependency in local.dependencies)
        dependency.taskId: dependency.requiredCompletion,
    };
    final rMap = <String, int>{
      for (final dependency in incoming.dependencies)
        dependency.taskId: dependency.requiredCompletion,
    };
    final wMap = <String, int>{
      for (final dependency in winner.dependencies)
        dependency.taskId: dependency.requiredCompletion,
    };
    final orderedTargetIds = _collectOrderedDependencyIds(
      <List<TdfTaskDependency>>[
        winner.dependencies,
        local.dependencies,
        incoming.dependencies,
        baseline.dependencies,
      ],
    );

    final merged = <TdfTaskDependency>[];
    for (final targetId in orderedTargetIds) {
      final mergedReq = _mergeSinglePreNormalizedDependency(
        targetId: targetId,
        rawLocal: lMap[targetId],
        rawIncoming: rMap[targetId],
        rawBaseline: bMap[targetId],
        rawWinner: wMap[targetId],
        localRepeat: local.repeatRule,
        incomingRepeat: incoming.repeatRule,
        baselineRepeat: baseline.repeatRule,
        winnerRepeat: winner.repeatRule,
        mergedLiveTasksById: mergedLiveTasksById,
        mergedDeletedTaskIds: mergedDeletedTaskIds,
      );
      if (mergedReq != null) {
        merged.add(
          TdfTaskDependency(taskId: targetId, requiredCompletion: mergedReq),
        );
      }
    }
    return TdfTaskDependency.normalizeList(merged);
  }

  /// Applies the 4-step three-way scalar merge rule (`TDF-MERGE-005`).
  static T _mergeScalar<T>({
    required T local,
    required T incoming,
    required T baseline,
    required T winner,
    required bool Function(T first, T second) equalsFn,
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

  /// Reconciles a single `<target-id>` dependency threshold across `(B', L', R')` under each variant's `repeatRule`.
  static int? _mergeSinglePreNormalizedDependency({
    required String targetId,
    required int? rawLocal,
    required int? rawIncoming,
    required int? rawBaseline,
    required int? rawWinner,
    required TaskRepeatRule? localRepeat,
    required TaskRepeatRule? incomingRepeat,
    required TaskRepeatRule? baselineRepeat,
    required TaskRepeatRule? winnerRepeat,
    required Map<String, TaskItem> mergedLiveTasksById,
    required Set<String> mergedDeletedTaskIds,
  }) {
    final normLocal = _preNormalizeSingleDependency(
      requiredCompletion: rawLocal,
      variantRepeat: localRepeat,
      targetId: targetId,
      mergedLiveTasksById: mergedLiveTasksById,
      mergedDeletedTaskIds: mergedDeletedTaskIds,
    );
    final normIncoming = _preNormalizeSingleDependency(
      requiredCompletion: rawIncoming,
      variantRepeat: incomingRepeat,
      targetId: targetId,
      mergedLiveTasksById: mergedLiveTasksById,
      mergedDeletedTaskIds: mergedDeletedTaskIds,
    );
    final normBaseline = _preNormalizeSingleDependency(
      requiredCompletion: rawBaseline,
      variantRepeat: baselineRepeat,
      targetId: targetId,
      mergedLiveTasksById: mergedLiveTasksById,
      mergedDeletedTaskIds: mergedDeletedTaskIds,
    );
    final normWinner = _preNormalizeSingleDependency(
      requiredCompletion: rawWinner,
      variantRepeat: winnerRepeat,
      targetId: targetId,
      mergedLiveTasksById: mergedLiveTasksById,
      mergedDeletedTaskIds: mergedDeletedTaskIds,
    );
    return _mergeScalar<int?>(
      local: normLocal,
      incoming: normIncoming,
      baseline: normBaseline,
      winner: normWinner,
      equalsFn: (first, second) => first == second,
    );
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
        equalsFn: (first, second) => _compareSubtasksBlock(first, second) == 0,
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
      equalsFn: (first, second) => first == second,
    );
    final mergedSteps = <SubtaskItem>[];
    for (var i = 0; i < baseline.subtasks.length; i++) {
      final mergedDone = _mergeScalar(
        local: local.subtasks[i].isCompleted,
        incoming: incoming.subtasks[i].isCompleted,
        baseline: baseline.subtasks[i].isCompleted,
        winner: winner.subtasks[i].isCompleted,
        equalsFn: (first, second) => first == second,
      );
      mergedSteps.add(
        SubtaskItem(title: baseline.subtasks[i].title, isCompleted: mergedDone),
      );
    }
    return (autoFinish: mergedAutoFinish, steps: mergedSteps);
  }

  /// Merges [winner] and [loser] when `baseline` is `null`, reconstructing $L_{\text{before}}(T)$ (`TDF-MERGE-006`) and unioning `history` (`TDF-MERGE-008`).
  static TaskItem _mergeTaskWithoutBaseline({
    required TaskItem winner,
    required TaskItem loser,
    required Set<String> deletedLabelsWinner,
    required Set<String> deletedLabelsLoser,
  }) {
    final withLabels = _preserveTombstonedLabelsWithoutBaseline(
      winner,
      loser,
      deletedLabelsWinner,
      deletedLabelsLoser,
    );
    if (winner.history.isEmpty && loser.history.isEmpty) {
      return withLabels;
    }
    final unionHistory = TaskHistoryEntry.normalizeList(<TaskHistoryEntry>[
      ...winner.history,
      ...loser.history,
    ]);
    return withLabels.copyWith(history: unionHistory);
  }

  /// Computes `max(bMod, lMod, rMod) + 1 second` and validates calendar bounds (`TDF-MERGE-004`).
  static DateTime _nextMergedRevision(
    DateTime bMod,
    DateTime lMod,
    DateTime rMod,
  ) => _nextMergedTaskRevision(lMod, rMod, bMod);

  /// Computes `max(lMod, rMod, bMod) + 1 second` and validates calendar bounds (`TDF-MERGE-004`).
  static DateTime _nextMergedTaskRevision(
    DateTime lMod,
    DateTime rMod,
    DateTime? bMod,
  ) {
    var maxMod = lMod.isAfter(rMod) ? lMod : rMod;
    if (bMod != null && bMod.isAfter(maxMod)) {
      maxMod = bMod;
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

  /// Pre-normalizes a single [requiredCompletion] threshold under [variantRepeat] (`TDF-MERGE-010`).
  static int? _preNormalizeSingleDependency({
    required int? requiredCompletion,
    required TaskRepeatRule? variantRepeat,
    required String targetId,
    required Map<String, TaskItem> mergedLiveTasksById,
    required Set<String> mergedDeletedTaskIds,
  }) {
    if (requiredCompletion == null) {
      return null;
    }
    if (mergedDeletedTaskIds.contains(targetId)) {
      return null;
    }
    final target = mergedLiveTasksById[targetId];
    if (target == null) {
      return requiredCompletion;
    }
    if (target.completions >= requiredCompletion &&
        (variantRepeat == null || target.repeatRule == null)) {
      return null;
    }
    return requiredCompletion;
  }

  /// Reconstructs $L_{\text{before}}(T) = W.\text{labels} \cup (\text{Loser}.\text{labels} \cap (D^{\text{label}}_W \setminus D^{\text{label}}_{\text{Loser}}))$ without a baseline (`TDF-MERGE-006`).
  static TaskItem _preserveTombstonedLabelsWithoutBaseline(
    TaskItem winner,
    TaskItem loser,
    Set<String> deletedLabelsWinner,
    Set<String> deletedLabelsLoser,
  ) {
    if (deletedLabelsWinner.isEmpty || loser.labelIds.isEmpty) {
      return winner;
    }
    final winnerOnlyDeleted = deletedLabelsWinner.difference(
      deletedLabelsLoser,
    );
    if (winnerOnlyDeleted.isEmpty) {
      return winner;
    }
    final missingTombstoned = <String>[
      for (final id in loser.labelIds)
        if (winnerOnlyDeleted.contains(id) && !winner.labelIds.contains(id)) id,
    ];
    if (missingTombstoned.isEmpty) {
      return winner;
    }
    final combined = _normalizedLabelSet(<String>[
      ...winner.labelIds,
      ...missingTombstoned,
    ]);
    return winner.copyWith(labelIds: combined);
  }

  /// Strips an expired finite `suspendedAt <= nowUtc` (together with `suspendedNote`) from [task] for Case 2 pre-normalization.
  static TaskItem _stripExpiredDeferral(TaskItem task, DateTime nowUtc) {
    if (task.isSuspendedForever) {
      return task;
    }
    if (task.suspendedAt case final suspendedTime?
        when !suspendedTime.isAfter(nowUtc)) {
      return task.copyWith(clearSuspendedAt: true, clearSuspendedNote: true);
    }
    return task;
  }

  /// Strips [tombstonedLocationIds] from [model] and converts an emptied task location group into its cascade target state (`TDF-MERGE-007`).
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

  /// Appends normalized [conditions] into [buffer] for payload signatures.
  static void _writeConditionSignature(
    StringBuffer buffer,
    List<TaskCondition> conditions,
  ) {
    final norm = _NormalizedConditionModel.fromList(conditions);
    buffer
      ..write(norm.globalAny ? '1;' : '0;')
      ..write(norm.dayResetAny ? '1;' : '0;');
    _writeDayRulesSignature(buffer, norm.dayRules);
    buffer.write(norm.timeResetAny ? '1;' : '0;');
    _writeTimeRulesSignature(buffer, norm.timeRules);
    buffer.write(norm.locationResetAny ? '1;' : '0;');
    _writeStringListSignature(buffer, norm.locationIds);
    _writeLegacyLocationRulesSignature(buffer, norm.legacyLocationRules);
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

  /// Appends legacy coordinate location [rules] into [buffer].
  static void _writeLegacyLocationRulesSignature(
    StringBuffer buffer,
    List<LocationTaskCondition> rules,
  ) {
    buffer
      ..write(rules.length)
      ..write(':');
    for (final rule in rules) {
      _writeSingleLegacyLocationRuleSignature(buffer, rule);
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

  /// Appends a single legacy coordinate [rule] into [buffer].
  static void _writeSingleLegacyLocationRuleSignature(
    StringBuffer buffer,
    LocationTaskCondition rule,
  ) {
    _writeStringListSignature(buffer, rule.locationIds);
    _writeString(buffer, rule.latitudeText);
    _writeString(buffer, rule.longitudeText);
    _writeString(buffer, rule.radiusText);
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

/// Normalized condition representation `(globalAny, dayGroup, timeGroup, locationGroup)` (`TDF-MODEL-006`).
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
        legacyLocRules: legacyLocRules,
      );
      globalAny = flags.globalAny;
      dayReset = flags.dayReset;
      timeReset = flags.timeReset;
      locReset = flags.locReset;
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

  /// Whether the `day` condition group was reset via `condition day any`.
  final bool dayResetAny;

  /// Active weekday condition rules.
  final List<DayTaskCondition> dayRules;

  /// Whether all condition groups were reset via `condition any`.
  final bool globalAny;

  /// Legacy inline coordinate location rules without `<location-id>` references.
  final List<LocationTaskCondition> legacyLocationRules;

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
    required List<LocationTaskCondition> legacyLocRules,
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
        } else {
          legacyLocRules.add(rule);
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
