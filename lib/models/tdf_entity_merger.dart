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

import 'task_item.dart';
import 'tdf_error.dart';
import 'tdf_location.dart';
import 'tdf_metadata.dart';
import 'tdf_payload_comparison.dart';
import 'tdf_sync_metadata.dart';
import 'tdf_timezone.dart';

/// Stateless three-way entity and unit merge engine per `spec/TDF_SPEC_0.8.0.md` Section 12 (`TDF-MERGE-004` to `010`).
@immutable
class TdfEntityMerger {
  /// Prevents instantiation of this stateless helper class.
  const TdfEntityMerger._();

  /// Merges [local] and [incoming] [TdfLabel] versions using [baseline] and [tombstonedLocationIds] (`TDF-MERGE-004` to `007`).
  static TdfLabel mergeLabelWithBaseline({
    required TdfLabel local,
    required TdfLabel incoming,
    required TdfLabel? baseline,
    Set<String> tombstonedLocationIds = const <String>{},
  }) {
    final localWins =
        TdfPayloadComparison.compareLabelVersions(local, incoming) >= 0;
    final winner = localWins ? local : incoming;
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
      equalsFn: (first, second) =>
          TdfPayloadComparison.compareLinkLists(first, second) == 0,
    );
    final mergedConditions = _mergeConditionsGroupWise(
      local: local.conditions,
      incoming: incoming.conditions,
      baseline: baseline.conditions,
      localWins: localWins,
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

    final greatestExisting = _greatestLabelVersion(baseline, winner);
    if (TdfPayloadComparison.compareLabelPayloads(
          greatestExisting,
          candidate,
        ) ==
        0) {
      return greatestExisting;
    }
    final nextRevision = _nextMergedRevision(
      baseline.effectiveModifiedAt,
      local.effectiveModifiedAt,
      incoming.effectiveModifiedAt,
    );
    return candidate.copyWith(modifiedAt: nextRevision);
  }

  /// Merges [local] and [incoming] [TdfLocation] versions using [baseline] (`TDF-MERGE-004` to `005`).
  static TdfLocation mergeLocationWithBaseline({
    required TdfLocation local,
    required TdfLocation incoming,
    required TdfLocation? baseline,
  }) {
    final winner =
        TdfPayloadComparison.compareLocationVersions(local, incoming) >= 0
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
          TdfPayloadComparison.compareLocationCoordAndSource(first, second) ==
          0,
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

    final greatestExisting = _greatestLocationVersion(baseline, winner);
    if (TdfPayloadComparison.compareLocationPayloads(
          greatestExisting,
          candidate,
        ) ==
        0) {
      return greatestExisting;
    }
    final nextRevision = _nextMergedRevision(
      baseline.effectiveModifiedAt,
      local.effectiveModifiedAt,
      incoming.effectiveModifiedAt,
    );
    return candidate.copyWith(modifiedAt: nextRevision);
  }

  /// Computes `cleaned` (gated by [cleanupMode]) and `uncleaned` (raw Case 2) merged [TaskItem] candidates (`TDF-MERGE-006` to `010`).
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
    final localWins =
        TdfPayloadComparison.compareTaskVersions(local, incoming) >= 0;
    return _mergeTaskCandidatesInternal(
      local: local,
      incoming: incoming,
      baseline: baseline,
      localWins: localWins,
      evaluationTime: evaluationTime,
      cleanupMode: cleanupMode,
      mergedLiveTasksById: mergedLiveTasksById,
      mergedDeletedTaskIds: mergedDeletedTaskIds,
      tombstonedLocationIds: tombstonedLocationIds,
      deletedLabelsLocal: deletedLabelsLocal,
      deletedLabelsIncoming: deletedLabelsIncoming,
      validLabelIds: validLabelIds,
      postCascadeLabelsById: postCascadeLabelsById,
    );
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
  }) => mergeTaskWithBaselineAndUncleaned(
    local: local,
    incoming: incoming,
    baseline: baseline,
    evaluationTime: evaluationTime,
    cleanupMode: cleanupMode,
    mergedLiveTasksById: mergedLiveTasksById,
    mergedDeletedTaskIds: mergedDeletedTaskIds,
    tombstonedLocationIds: tombstonedLocationIds,
    deletedLabelsLocal: deletedLabelsLocal,
    deletedLabelsIncoming: deletedLabelsIncoming,
    validLabelIds: validLabelIds,
    postCascadeLabelsById: postCascadeLabelsById,
  ).merged;

  /// Merges [local] and [incoming] in a single pass, returning the finalized task, its uncleaned candidate, and whether an unchanged identity fast path applied.
  static ({TaskItem merged, TaskItem uncleaned, bool wasUnchangedIdentity})
  mergeTaskWithBaselineAndUncleaned({
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
    final canIdentityFastPath =
        local == incoming &&
        (baseline == null || local == baseline) &&
        deletedLabelsLocal.isEmpty &&
        deletedLabelsIncoming.isEmpty &&
        tombstonedLocationIds.isEmpty &&
        (cleanupMode == TdfCleanupMode.deferred ||
            (local.suspendedAt == null && local.dependencies.isEmpty));
    if (canIdentityFastPath) {
      return (merged: local, uncleaned: local, wasUnchangedIdentity: true);
    }

    final normalizedNow = evaluationTime != null
        ? TaskItem.normalizeTimestamp(evaluationTime)
        : null;
    final localWins =
        TdfPayloadComparison.compareTaskVersions(local, incoming) >= 0;
    final winner = localWins ? local : incoming;
    final candidates = _mergeTaskCandidatesInternal(
      local: local,
      incoming: incoming,
      baseline: baseline,
      localWins: localWins,
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
    final referenceExisting =
        (baseline != null &&
            TdfPayloadComparison.compareTaskVersions(baseline, winner) > 0)
        ? baseline
        : winner;
    if (referenceExisting.completions == candidates.cleaned.completions &&
        TdfPayloadComparison.compareTaskPayloads(
              referenceExisting,
              candidates.cleaned,
            ) ==
            0) {
      final merged =
          candidates.cleaned.modifiedAt == referenceExisting.modifiedAt
          ? candidates.cleaned
          : candidates.cleaned.copyWith(
              modifiedAt: referenceExisting.modifiedAt,
              clearModifiedAt: referenceExisting.modifiedAt == null,
            );
      return (
        merged: merged,
        uncleaned: candidates.uncleaned,
        wasUnchangedIdentity: false,
      );
    }
    final bumped = _nextMergedTaskRevision(
      local.effectiveModifiedAt,
      incoming.effectiveModifiedAt,
      baseline?.effectiveModifiedAt,
    );
    if (cleanupMode == TdfCleanupMode.deferred ||
        normalizedNow == null ||
        identical(candidates.cleaned, candidates.uncleaned) ||
        TdfPayloadComparison.compareTaskPayloads(
              candidates.cleaned,
              candidates.uncleaned,
            ) ==
            0) {
      return (
        merged: candidates.cleaned.copyWith(modifiedAt: bumped),
        uncleaned: candidates.uncleaned,
        wasUnchangedIdentity: false,
      );
    }
    final withNow = normalizedNow.isAfter(bumped) ? normalizedNow : bumped;
    if (!TdfCalendar.isWithinTimestampBounds(withNow)) {
      throw const TdfException(
        kind: TdfErrorKind.invalidTimestamp,
        line: 1,
        message: 'Merged revision exceeds maximum supported timestamp.',
      );
    }
    return (
      merged: candidates.cleaned.copyWith(modifiedAt: withNow),
      uncleaned: candidates.uncleaned,
      wasUnchangedIdentity: false,
    );
  }

  /// Computes the merged `(completions, isCompleted, completedAt, repeatRule)` header of [local] and [incoming] for prerequisite pre-normalization.
  static TaskItem previewMergedTaskPrerequisiteHeader({
    required TaskItem local,
    required TaskItem incoming,
    required TaskItem? baseline,
  }) {
    if (identical(local, incoming) || local == incoming) {
      return local;
    }
    final winner =
        TdfPayloadComparison.compareTaskVersions(local, incoming) >= 0
        ? local
        : incoming;
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
          TdfPayloadComparison.compareNullableRepeatRules(first, second) == 0,
    );
    if (mergedRepeat == winner.repeatRule) {
      return winner;
    }
    return winner.copyWith(
      repeatRule: mergedRepeat,
      clearRepeatRule: mergedRepeat == null,
    );
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

  /// Constructs both `cleaned` and `uncleaned` merged [TaskItem] candidates in one shared pass (`TDF-MERGE-010`).
  static ({TaskItem cleaned, TaskItem uncleaned}) _buildMergedTaskCandidates({
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
    required TdfCleanupMode cleanupMode,
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
      final atomicCandidate = TaskItem(
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
      return (cleaned: atomicCandidate, uncleaned: atomicCandidate);
    }

    final mergedPriority = _mergeScalar(
      local: local.isPriority,
      incoming: incoming.isPriority,
      baseline: baseline.isPriority,
      winner: winner.isPriority,
      equalsFn: (first, second) => first == second,
    );
    final uncleanedDeferral = _mergeCase2Deferral(
      local: local,
      incoming: incoming,
      baseline: baseline,
      winner: winner,
      preNormalizeBlocks: false,
      evaluationTime: evaluationTime,
    );
    final dueSource = _mergeScalar(
      local: local,
      incoming: incoming,
      baseline: baseline,
      winner: winner,
      equalsFn: (first, second) =>
          TdfPayloadComparison.compareDue(first, second) == 0,
    );
    final mergedRepeat = _mergeScalar(
      local: local.repeatRule,
      incoming: incoming.repeatRule,
      baseline: baseline.repeatRule,
      winner: winner.repeatRule,
      equalsFn: (first, second) =>
          TdfPayloadComparison.compareNullableRepeatRules(first, second) == 0,
    );
    final uncleanedDependencies = _mergeDependencyMaps(
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

    final uncleaned = TaskItem(
      id: winner.id,
      title: mergedName,
      note: mergedNote,
      createdAt: winner.createdAt,
      completions: winner.completions,
      isPriority: mergedPriority,
      suspendedAt: uncleanedDeferral.suspendedAt,
      isSuspendedForever: uncleanedDeferral.isSuspendedForever,
      suspendedNote: uncleanedDeferral.suspendedNote,
      dueAt: dueSource.dueAt,
      dueAnchor: dueSource.dueAnchor,
      isDuePassive: dueSource.isDuePassive,
      dueNote: dueSource.dueNote,
      repeatRule: mergedRepeat,
      origin: mergedOrigin,
      labelIds: mergedLabels,
      dependencies: uncleanedDependencies,
      links: mergedLinks,
      history: mergedHistory,
      conditions: mergedConditions,
      subtasksAutoFinish: mergedSubtasks.autoFinish,
      subtasks: mergedSubtasks.steps,
    );
    if (cleanupMode == TdfCleanupMode.deferred) {
      return (cleaned: uncleaned, uncleaned: uncleaned);
    }

    final hasAnyDeferral =
        evaluationTime != null &&
        (local.suspendedAt != null ||
            incoming.suspendedAt != null ||
            baseline.suspendedAt != null);
    final hasAnyDependencies =
        local.dependencies.isNotEmpty ||
        incoming.dependencies.isNotEmpty ||
        baseline.dependencies.isNotEmpty;
    if (!hasAnyDeferral && !hasAnyDependencies) {
      return (cleaned: uncleaned, uncleaned: uncleaned);
    }

    final cleanedDeferral = hasAnyDeferral
        ? _mergeCase2Deferral(
            local: local,
            incoming: incoming,
            baseline: baseline,
            winner: winner,
            preNormalizeBlocks: true,
            evaluationTime: evaluationTime,
          )
        : uncleanedDeferral;
    final cleanedDependencies = hasAnyDependencies
        ? _mergePreNormalizedDependencyMaps(
            local: local,
            incoming: incoming,
            baseline: baseline,
            winner: winner,
            mergedLiveTasksById: mergedLiveTasksById,
            mergedDeletedTaskIds: mergedDeletedTaskIds,
          )
        : uncleanedDependencies;
    if (TdfPayloadComparison.compareDeferral(
              cleanedDeferral,
              uncleanedDeferral,
            ) ==
            0 &&
        listEquals(cleanedDependencies, uncleanedDependencies)) {
      return (cleaned: uncleaned, uncleaned: uncleaned);
    }
    final cleaned = uncleaned.copyWith(
      suspendedAt: cleanedDeferral.suspendedAt,
      clearSuspendedAt: cleanedDeferral.suspendedAt == null,
      isSuspendedForever: cleanedDeferral.isSuspendedForever,
      suspendedNote: cleanedDeferral.suspendedNote,
      clearSuspendedNote: cleanedDeferral.suspendedNote == null,
      dependencies: cleanedDependencies,
    );
    return (cleaned: cleaned, uncleaned: uncleaned);
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

  /// Selects the greatest existing [TdfLabel] between [baseline] and preselected [winner] (`TDF-MERGE-003`).
  static TdfLabel _greatestLabelVersion(TdfLabel baseline, TdfLabel winner) {
    return TdfPayloadComparison.compareLabelVersions(baseline, winner) > 0
        ? baseline
        : winner;
  }

  /// Selects the greatest existing [TdfLocation] between [baseline] and preselected [winner] (`TDF-MERGE-003`).
  static TdfLocation _greatestLocationVersion(
    TdfLocation baseline,
    TdfLocation winner,
  ) {
    return TdfPayloadComparison.compareLocationVersions(baseline, winner) > 0
        ? baseline
        : winner;
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
      if (label != null &&
          TdfMetadata.hasLocationConditionRule(label.conditions)) {
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
        equalsFn: (first, second) =>
            TdfPayloadComparison.compareDeferral(first, second) == 0,
      );
    }
    final normLocal = _stripExpiredDeferral(local, evaluationTime);
    final normIncoming = _stripExpiredDeferral(incoming, evaluationTime);
    final normBaseline = _stripExpiredDeferral(baseline, evaluationTime);
    final normWinner = identical(winner, local) ? normLocal : normIncoming;
    return _mergeScalar(
      local: normLocal,
      incoming: normIncoming,
      baseline: normBaseline,
      winner: normWinner,
      equalsFn: (first, second) =>
          TdfPayloadComparison.compareDeferral(first, second) == 0,
    );
  }

  /// Applies pre-merge tombstone stripping and the commutative group-wise `condition` merge (`TDF-MERGE-007`) using three normalized models.
  static List<TaskCondition> _mergeConditionsGroupWise({
    required List<TaskCondition> local,
    required List<TaskCondition> incoming,
    required List<TaskCondition> baseline,
    required bool localWins,
    required Set<String> tombstonedLocationIds,
    required bool isTask,
    required bool hasLiveLabelLocationRule,
  }) {
    final rawBase = NormalizedConditionModel.fromList(baseline);
    final rawLocal = NormalizedConditionModel.fromList(local);
    final rawIncoming = NormalizedConditionModel.fromList(incoming);

    final allBaseLocsTombstoned =
        isTask &&
        !rawBase.globalAny &&
        !rawBase.locationResetAny &&
        rawBase.locationIds.isNotEmpty &&
        rawBase.locationIds.every(tombstonedLocationIds.contains);
    final normalizeSideCascade =
        allBaseLocsTombstoned && !hasLiveLabelLocationRule;

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
      normalizeCascadeAnyToEmpty: normalizeSideCascade,
    );
    final normIncoming = _stripTombstonedLocations(
      rawIncoming,
      tombstonedLocationIds: tombstonedLocationIds,
      isTask: isTask,
      hasLiveLabelLocationRule: hasLiveLabelLocationRule,
      normalizeCascadeAnyToEmpty: normalizeSideCascade,
    );
    final normWinner = localWins ? normLocal : normIncoming;
    final normLoser = localWins ? normIncoming : normLocal;

    if (normBase.globalAny || normLocal.globalAny || normIncoming.globalAny) {
      final mergedFull = _mergeScalar(
        local: normLocal,
        incoming: normIncoming,
        baseline: normBase,
        winner: normWinner,
        equalsFn: (first, second) =>
            TdfPayloadComparison.compareNormalizedConditionModels(
              first,
              second,
            ) ==
            0,
      );
      return mergedFull.toConditionList();
    }

    final mergedDay = _mergeScalar(
      local: normLocal,
      incoming: normIncoming,
      baseline: normBase,
      winner: normWinner,
      equalsFn: (first, second) =>
          TdfPayloadComparison.compareDayConditionGroup(first, second) == 0,
    );
    final mergedTime = _mergeScalar(
      local: normLocal,
      incoming: normIncoming,
      baseline: normBase,
      winner: normWinner,
      equalsFn: (first, second) =>
          TdfPayloadComparison.compareTimeConditionGroup(first, second) == 0,
    );
    final mergedLoc = _mergeLocationConditionGroup(
      local: normLocal,
      incoming: normIncoming,
      baseline: normBase,
      winner: normWinner,
      loser: normLoser,
    );

    final mergedModel = NormalizedConditionModel(
      globalAny: false,
      dayResetAny: mergedDay.dayResetAny,
      dayRules: mergedDay.dayRules,
      timeResetAny: mergedTime.timeResetAny,
      timeRules: mergedTime.timeRules,
      locationResetAny: mergedLoc.locationResetAny,
      locationIds: mergedLoc.locationIds,
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
  static NormalizedConditionModel _mergeLocationConditionGroup({
    required NormalizedConditionModel local,
    required NormalizedConditionModel incoming,
    required NormalizedConditionModel baseline,
    required NormalizedConditionModel winner,
    required NormalizedConditionModel loser,
  }) {
    if (TdfPayloadComparison.compareLocationConditionGroup(local, incoming) ==
        0) {
      return local;
    }
    if (TdfPayloadComparison.compareLocationConditionGroup(local, baseline) ==
        0) {
      return incoming;
    }
    if (TdfPayloadComparison.compareLocationConditionGroup(
          incoming,
          baseline,
        ) ==
        0) {
      return local;
    }
    if (baseline.locationResetAny ||
        local.locationResetAny ||
        incoming.locationResetAny) {
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
        equalsFn: (first, second) =>
            TdfPayloadComparison.compareSubtasksBlock(first, second) == 0,
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

  /// Computes `cleaned` and `uncleaned` task merge candidates using a precomputed [localWins] decision.
  static ({TaskItem cleaned, TaskItem uncleaned}) _mergeTaskCandidatesInternal({
    required TaskItem local,
    required TaskItem incoming,
    required TaskItem? baseline,
    required bool localWins,
    required DateTime? evaluationTime,
    required TdfCleanupMode cleanupMode,
    required Map<String, TaskItem> mergedLiveTasksById,
    required Set<String> mergedDeletedTaskIds,
    required Set<String> tombstonedLocationIds,
    required Set<String> deletedLabelsLocal,
    required Set<String> deletedLabelsIncoming,
    required Set<String>? validLabelIds,
    required Map<String, TdfLabel> postCascadeLabelsById,
  }) {
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
      localWins: localWins,
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
      equalsFn: (first, second) =>
          TdfPayloadComparison.compareLinkLists(first, second) == 0,
    );
    final mergedHistory = _mergeHistorySets(
      local: local.history,
      incoming: incoming.history,
      baseline: baseline.history,
    );

    return _buildMergedTaskCandidates(
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
      cleanupMode: cleanupMode,
      evaluationTime: evaluationTime,
      mergedLiveTasksById: mergedLiveTasksById,
      mergedDeletedTaskIds: mergedDeletedTaskIds,
    );
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
    final combined = TdfPayloadComparison.normalizedLabelSet(<String>[
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
  static NormalizedConditionModel _stripTombstonedLocations(
    NormalizedConditionModel model, {
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
